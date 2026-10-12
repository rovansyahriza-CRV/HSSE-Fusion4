-- =====================================================================================
-- 066 -- PIC fase 2, tahap 4: RPC yang belum tahu siapa pelakunya + audit trail HSE Program.
-- Jalankan di project Supabase HSSE-Fusion4 (BUKAN Fusion4 SmartGate). Run after 065.
-- Pasang bareng 5 HTML baru: audit-report, hse-meeting-report, tbm-report, hse-program,
-- management-review. Kalau HTML lama masih kepakai, aksinya ditolak "QR Code ID kosong".
--
-- Sebelumnya: 10 RPC ini gak nerima nama/QR sama sekali, jadi siapa pun bisa manggil:
--   start_audit_pelaksanaan, submit_audit_temuan        (Internal Audit)
--   finalize_hse_meeting                                (HSE Meeting)
--   tbm_finish_session                                  (TBM)
--   update_project_dates, upsert_hse_program_item       (HSE Program)
--   save_management_review_action, delete_management_review,
--   delete_management_review_action, save_management_review_closing_statement (MR)
-- Sekarang: semuanya nerima p_aktor_nama + p_aktor_qr, dicek ke SmartGate (hsse_wajib_akses
--   dari 065) dengan PIC yang sama dengan halaman: HSSE-AUD / HSSE-MTG / HSSE-TBM /
--   HSSE-PRG / HSSE-MRV. Pola sama dengan 065: isi asli jadi "<nama>__inti".
--   HSE Program: tiap simpan item & durasi project dicatat di hseProgramLogTbl
--   (sebelum/sesudah + siapa), bisa dilihat lewat get_hse_program_log.
-- Aman dijalankan ulang.
-- =====================================================================================

-- -------------------------------------------------------------------------------------
-- 1. Tabel log HSE Program
-- -------------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS "hseProgramLogTbl" (
    "Id" BIGSERIAL PRIMARY KEY,
    "ProjectId" BIGINT NOT NULL,
    "Tahun" INT,
    "ItemId" BIGINT,
    "Aksi" TEXT NOT NULL,
    "Sebelum" JSONB,
    "Sesudah" JSONB,
    "Oleh" TEXT NOT NULL DEFAULT '',
    "OlehQrCodeId" TEXT NOT NULL DEFAULT '',
    "CreatedAt" TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_hse_program_log_project ON "hseProgramLogTbl" ("ProjectId", "Tahun", "CreatedAt" DESC);
ALTER TABLE "hseProgramLogTbl" ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "hseProgramLogTbl_no_direct" ON "hseProgramLogTbl";
CREATE POLICY "hseProgramLogTbl_no_direct" ON "hseProgramLogTbl"
    FOR ALL TO anon, authenticated USING (false) WITH CHECK (false);

-- -------------------------------------------------------------------------------------
-- 2. Isi asli dipindah ke "<nama>__inti" (cuma sekali; run ulang = dilewati)
-- -------------------------------------------------------------------------------------
DO $do$
DECLARE
    f RECORD;
BEGIN
    FOR f IN
        SELECT p.oid, p.proname, oidvectortypes(p.proargtypes) AS argtypes
        FROM pg_proc p
        WHERE p.pronamespace = 'public'::regnamespace
          AND p.proname IN ('start_audit_pelaksanaan', 'submit_audit_temuan', 'finalize_hse_meeting',
                            'tbm_finish_session', 'update_project_dates', 'upsert_hse_program_item',
                            'save_management_review_action', 'delete_management_review',
                            'delete_management_review_action', 'save_management_review_closing_statement')
          AND NOT ('p_aktor_qr' = ANY (COALESCE(p.proargnames, '{}')))
    LOOP
        IF to_regprocedure(format('public.%I(%s)', f.proname || '__inti', f.argtypes)) IS NULL THEN
            -- overload lama yang sudah dicabut di 063 ditandai, biar wrapper-nya tetap tertutup
            IF NOT has_function_privilege('anon', f.oid, 'EXECUTE') THEN
                EXECUTE format('COMMENT ON FUNCTION %s IS %L', f.oid::regprocedure, 'hsse:tertutup');
            END IF;
            EXECUTE format('ALTER FUNCTION %s RENAME TO %I', f.oid::regprocedure, f.proname || '__inti');
        ELSE
            RAISE EXCEPTION '% (%) dan %__inti dua-duanya ada. Cek manual dulu.', f.proname, f.argtypes, f.proname;
        END IF;
    END LOOP;
END $do$;

-- -------------------------------------------------------------------------------------
-- 3. Wrapper umum: cek PIC lalu panggil __inti (8 RPC; 2 RPC HSE Program di bagian 4)
-- -------------------------------------------------------------------------------------
DO $do$
DECLARE
    m RECORD;
    f RECORD;
    v_call TEXT;
    v_args TEXT;
BEGIN
    FOR m IN SELECT * FROM (VALUES
        ('start_audit_pelaksanaan',                 'HSSE-AUD'),
        ('submit_audit_temuan',                     'HSSE-AUD'),
        ('finalize_hse_meeting',                    'HSSE-MTG'),
        ('tbm_finish_session',                      'HSSE-TBM'),
        ('save_management_review_action',           'HSSE-MRV'),
        ('delete_management_review',                'HSSE-MRV'),
        ('delete_management_review_action',         'HSSE-MRV'),
        ('save_management_review_closing_statement','HSSE-MRV')
    ) AS t(fn, tag)
    LOOP
        FOR f IN
            SELECT p.oid, oidvectortypes(p.proargtypes) AS argtypes
            FROM pg_proc p
            WHERE p.pronamespace = 'public'::regnamespace AND p.proname = m.fn || '__inti'
        LOOP
            EXECUTE format('REVOKE EXECUTE ON FUNCTION %s FROM PUBLIC, anon, authenticated', f.oid::regprocedure);
            SELECT string_agg(format('%1$I => %1$I', n), ', ' ORDER BY i) INTO v_call
            FROM unnest((SELECT proargnames FROM pg_proc WHERE oid = f.oid)) WITH ORDINALITY AS a(n, i);
            -- kalau ada parameter ber-DEFAULT, parameter aktor juga wajib ber-DEFAULT
            v_args := pg_get_function_arguments(f.oid) || ', p_aktor_nama TEXT DEFAULT NULL, p_aktor_qr TEXT DEFAULT NULL';

            EXECUTE format($f$
                CREATE OR REPLACE FUNCTION public.%I(%s)
                RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $w$
                BEGIN
                    PERFORM public.hsse_wajib_akses(p_aktor_nama, p_aktor_qr, %L);
                    RETURN public.%I(%s);
                END;
                $w$ $f$,
                m.fn, v_args, m.tag, m.fn || '__inti', v_call);

            IF obj_description(f.oid, 'pg_proc') IS DISTINCT FROM 'hsse:tertutup' THEN
                EXECUTE format('GRANT EXECUTE ON FUNCTION public.%I(%s, TEXT, TEXT) TO anon, authenticated', m.fn, f.argtypes);
            ELSE
                EXECUTE format('REVOKE EXECUTE ON FUNCTION public.%I(%s, TEXT, TEXT) FROM PUBLIC, anon, authenticated', m.fn, f.argtypes);
            END IF;
        END LOOP;
    END LOOP;
END $do$;

-- -------------------------------------------------------------------------------------
-- 4. HSE Program: cek PIC HSSE-PRG + catat sebelum/sesudah
-- -------------------------------------------------------------------------------------
REVOKE EXECUTE ON FUNCTION public.upsert_hse_program_item__inti(BIGINT, INT, BIGINT, TEXT, JSONB, NUMERIC, TEXT, JSONB)
    FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.update_project_dates__inti(BIGINT, DATE, DATE)
    FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.upsert_hse_program_item(
    p_project_id BIGINT, p_tahun INT, p_item_id BIGINT, p_status_pakai TEXT, p_target_bulanan JSONB,
    p_target_qty NUMERIC DEFAULT NULL, p_frequency TEXT DEFAULT NULL, p_realisasi_manual_bulanan JSONB DEFAULT NULL,
    p_aktor_nama TEXT DEFAULT NULL, p_aktor_qr TEXT DEFAULT NULL
) RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
    v_sebelum JSONB;
    v_sesudah JSONB;
    v_hasil JSONB;
BEGIN
    PERFORM public.hsse_wajib_akses(p_aktor_nama, p_aktor_qr, 'HSSE-PRG');

    SELECT jsonb_build_object('statusPakai', "StatusPakai", 'targetQty', "TargetQty", 'frequency', "Frequency",
                              'targetBulanan', "TargetBulanan", 'realisasiManualBulanan', "RealisasiManualBulanan")
    INTO v_sebelum
    FROM "hseProgramTbl" WHERE "ProjectId" = p_project_id AND "Tahun" = p_tahun AND "ItemId" = p_item_id;

    v_hasil := public.upsert_hse_program_item__inti(p_project_id, p_tahun, p_item_id, p_status_pakai,
        p_target_bulanan, p_target_qty, p_frequency, p_realisasi_manual_bulanan);

    SELECT jsonb_build_object('statusPakai', "StatusPakai", 'targetQty', "TargetQty", 'frequency', "Frequency",
                              'targetBulanan', "TargetBulanan", 'realisasiManualBulanan', "RealisasiManualBulanan")
    INTO v_sesudah
    FROM "hseProgramTbl" WHERE "ProjectId" = p_project_id AND "Tahun" = p_tahun AND "ItemId" = p_item_id;

    IF v_sebelum IS DISTINCT FROM v_sesudah THEN
        INSERT INTO "hseProgramLogTbl" ("ProjectId", "Tahun", "ItemId", "Aksi", "Sebelum", "Sesudah", "Oleh", "OlehQrCodeId")
        VALUES (p_project_id, p_tahun, p_item_id, CASE WHEN v_sebelum IS NULL THEN 'Item Baru' ELSE 'Ubah Item' END,
                v_sebelum, v_sesudah, COALESCE(trim(p_aktor_nama), ''), upper(trim(p_aktor_qr)));
    END IF;
    RETURN v_hasil;
END;
$$;

CREATE OR REPLACE FUNCTION public.update_project_dates(
    p_project_id BIGINT, p_tanggal_mulai DATE, p_tanggal_selesai DATE,
    p_aktor_nama TEXT DEFAULT NULL, p_aktor_qr TEXT DEFAULT NULL
) RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
    v_sebelum JSONB;
    v_hasil JSONB;
BEGIN
    PERFORM public.hsse_wajib_akses(p_aktor_nama, p_aktor_qr, 'HSSE-PRG');
    SELECT jsonb_build_object('tanggalMulai', "TanggalMulaiProject", 'tanggalSelesai', "TanggalSelesaiProject")
    INTO v_sebelum FROM "projectTbl" WHERE "Id" = p_project_id;

    v_hasil := public.update_project_dates__inti(p_project_id, p_tanggal_mulai, p_tanggal_selesai);

    IF v_sebelum IS DISTINCT FROM jsonb_build_object('tanggalMulai', p_tanggal_mulai, 'tanggalSelesai', p_tanggal_selesai) THEN
        INSERT INTO "hseProgramLogTbl" ("ProjectId", "Aksi", "Sebelum", "Sesudah", "Oleh", "OlehQrCodeId")
        VALUES (p_project_id, 'Ubah Durasi Project', v_sebelum,
                jsonb_build_object('tanggalMulai', p_tanggal_mulai, 'tanggalSelesai', p_tanggal_selesai),
                COALESCE(trim(p_aktor_nama), ''), upper(trim(p_aktor_qr)));
    END IF;
    RETURN v_hasil;
END;
$$;

GRANT EXECUTE ON FUNCTION public.upsert_hse_program_item(BIGINT, INT, BIGINT, TEXT, JSONB, NUMERIC, TEXT, JSONB, TEXT, TEXT) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.update_project_dates(BIGINT, DATE, DATE, TEXT, TEXT) TO anon, authenticated;

-- -------------------------------------------------------------------------------------
-- 5. Baca riwayat perubahan HSE Program (publik, sama kayak get_hse_program)
-- -------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_hse_program_log(p_project_id BIGINT, p_tahun INT, p_limit INT DEFAULT 50)
RETURNS JSONB LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
    SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'waktu', x."CreatedAt", 'aksi', x."Aksi", 'item', x."NamaItem",
        'sebelum', x."Sebelum", 'sesudah', x."Sesudah", 'oleh', x."Oleh", 'olehQr', x."OlehQrCodeId"
    ) ORDER BY x."CreatedAt" DESC, x."Id" DESC), '[]'::jsonb)
    FROM (
        SELECT l.*, mi."NamaItem"
        FROM "hseProgramLogTbl" l
        LEFT JOIN "hseProgramMasterItemTbl" mi ON mi."Id" = l."ItemId"
        WHERE l."ProjectId" = p_project_id AND (l."Tahun" = p_tahun OR l."Tahun" IS NULL)
        ORDER BY l."CreatedAt" DESC, l."Id" DESC
        LIMIT LEAST(GREATEST(COALESCE(p_limit, 50), 1), 200)
    ) x;
$$;
GRANT EXECUTE ON FUNCTION public.get_hse_program_log(BIGINT, INT, INT) TO anon, authenticated;

-- =====================================================================================
-- CEK SETELAH JALAN:
-- 1) harusnya 44 baris (34 dari 065 + 10), anon_inti semua false:
-- SELECT replace(p.proname, '__inti', '') AS rpc, has_function_privilege('anon', p.oid, 'EXECUTE') AS anon_inti
-- FROM pg_proc p WHERE p.pronamespace = 'public'::regnamespace AND p.proname LIKE '%\_\_inti' ORDER BY 1;
-- 2) RPC tulis yang masih bisa dipanggil anon TANPA cek akses (harusnya 0 baris):
-- SELECT p.proname FROM pg_proc p
-- WHERE p.pronamespace = 'public'::regnamespace AND has_function_privilege('anon', p.oid, 'EXECUTE')
--   AND p.prosrc ~* '\m(insert|update|delete)\M' AND p.prosrc NOT LIKE '%hsse_wajib_akses%';
-- =====================================================================================
