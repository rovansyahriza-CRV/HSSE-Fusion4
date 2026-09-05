-- =====================================================================================
-- 032 -- HSE PROGRAM: input Target (qty) + Frequency, auto-spread ke matrik 12 bulan
-- Jalankan SETELAH sql/031, di Supabase project HSSE-Fusion4 (BUKAN Fusion4).
--
-- Sebelumnya admin harus isi manual 12 kolom target per bulan. Sekarang cukup isi
-- 1 angka Target (qty per siklus) + 1 Frequency (Harian/Mingguan/Bulanan/Triwulan/
-- Semester/Tahunan), lalu sistem otomatis nge-spread jadi matrik 12 bulan, dibatasi
-- oleh tanggal mulai & selesai project (jadi bulan di luar durasi project = 0).
-- Matrik hasil generate TETAP bisa di-edit manual per bulan di UI kalau ada
-- pengecualian (misal libur/shutdown sebulan) -- perhitungan spread dilakukan di
-- client (hse-program.html), migration ini cuma nyiapin tempat nyimpennya.
-- =====================================================================================

-- -------------------------------------------------------------------------------------
-- 1. Tanggal mulai/selesai project -- dipakai buat batasi rentang spread & tau
--    bulan mana yang "aktif" (bagian dari durasi project) di tahun berjalan.
-- -------------------------------------------------------------------------------------
ALTER TABLE "projectTbl" ADD COLUMN IF NOT EXISTS "TanggalMulaiProject" DATE;
ALTER TABLE "projectTbl" ADD COLUMN IF NOT EXISTS "TanggalSelesaiProject" DATE;

-- -------------------------------------------------------------------------------------
-- 2. Simpan juga setting Target Qty + Frequency per item (bukan cuma hasil matrik-nya),
--    biar kalau dibuka lagi form-nya udah keisi ulang & bisa di-generate ulang gampang.
-- -------------------------------------------------------------------------------------
ALTER TABLE "hseProgramTbl" ADD COLUMN IF NOT EXISTS "TargetQty" NUMERIC;
ALTER TABLE "hseProgramTbl" ADD COLUMN IF NOT EXISTS "Frequency" TEXT
    CHECK ("Frequency" IS NULL OR "Frequency" IN ('Harian', 'Mingguan', 'Bulanan', 'Triwulan', 'Semester', 'Tahunan'));

-- -------------------------------------------------------------------------------------
-- 3. RPC: update tanggal mulai/selesai project (dipanggil dari halaman HSE Program)
-- -------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.update_project_dates(
    p_project_id BIGINT,
    p_tanggal_mulai DATE,
    p_tanggal_selesai DATE
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $function$
BEGIN
    UPDATE "projectTbl"
    SET "TanggalMulaiProject" = p_tanggal_mulai,
        "TanggalSelesaiProject" = p_tanggal_selesai
    WHERE "Id" = p_project_id;

    RETURN jsonb_build_object('success', true);
END;
$function$;

-- -------------------------------------------------------------------------------------
-- 4. get_active_projects() -- tambah 2 field tanggal project (dipakai halaman HSE
--    Program buat tau durasi project sebelum nge-spread target). Signature sama
--    persis (tanpa parameter, return JSONB), jadi CREATE OR REPLACE aman -- semua
--    halaman lama yang manggil RPC ini tetap jalan normal, cuma dapet field baru.
-- -------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_active_projects()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_result JSONB;
BEGIN
    SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'id', "Id",
        'namaProject', "NamaProject",
        'noKontrak', "NoKontrak",
        'tipeKonstruksi', "TipeKonstruksi",
        'tanggalMulaiProject', "TanggalMulaiProject",
        'tanggalSelesaiProject', "TanggalSelesaiProject"
    ) ORDER BY "NamaProject"), '[]'::JSONB)
    INTO v_result
    FROM "projectTbl"
    WHERE "Status" = 'Aktif';

    RETURN v_result;
END;
$$;

-- -------------------------------------------------------------------------------------
-- 5. get_hse_program() -- tambah field targetQty & frequency di tiap item, biar form
--    di client bisa di-render ulang dengan setting yang udah pernah disimpan.
-- -------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_hse_program(p_project_id BIGINT, p_tahun INT)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $function$
DECLARE
    v_result JSONB;
BEGIN
    WITH realisasi AS (
        SELECT 'TBM' AS kode, EXTRACT(MONTH FROM "TanggalMulai")::INT AS bulan, COUNT(*) AS jumlah
        FROM "tbmTbl"
        WHERE "ProjectId" = p_project_id AND EXTRACT(YEAR FROM "TanggalMulai") = p_tahun
        GROUP BY 2

        UNION ALL
        SELECT 'HSE_MEETING_MINGGUAN', EXTRACT(MONTH FROM "TanggalRapat")::INT, COUNT(*)
        FROM "hseMeetingTbl"
        WHERE "ProjectId" = p_project_id AND "TipeMeeting" = 'Mingguan'
          AND EXTRACT(YEAR FROM "TanggalRapat") = p_tahun
        GROUP BY 2

        UNION ALL
        SELECT 'HSE_MEETING_BULANAN', EXTRACT(MONTH FROM "TanggalRapat")::INT, COUNT(*)
        FROM "hseMeetingTbl"
        WHERE "ProjectId" = p_project_id AND "TipeMeeting" = 'Bulanan'
          AND EXTRACT(YEAR FROM "TanggalRapat") = p_tahun
        GROUP BY 2

        UNION ALL
        SELECT 'INSPEKSI_OBSERVASI', EXTRACT(MONTH FROM "TanggalWaktu")::INT, COUNT(*)
        FROM "inspeksiTbl"
        WHERE "ProjectId" = p_project_id AND EXTRACT(YEAR FROM "TanggalWaktu") = p_tahun
        GROUP BY 2

        UNION ALL
        SELECT 'CERMAT', EXTRACT(MONTH FROM "TanggalWaktu")::INT, COUNT(*)
        FROM "cermatTbl"
        WHERE "ProjectId" = p_project_id AND EXTRACT(YEAR FROM "TanggalWaktu") = p_tahun
        GROUP BY 2

        UNION ALL
        SELECT 'INTERNAL_AUDIT', EXTRACT(MONTH FROM COALESCE("TanggalPelaksanaan", "TanggalRencana"::timestamptz))::INT, COUNT(*)
        FROM "auditTbl"
        WHERE "ProjectId" = p_project_id
          AND EXTRACT(YEAR FROM COALESCE("TanggalPelaksanaan", "TanggalRencana"::timestamptz)) = p_tahun
        GROUP BY 2

        UNION ALL
        SELECT 'PTW', EXTRACT(MONTH FROM "TanggalWaktu")::INT, COUNT(*)
        FROM "ptwTbl"
        WHERE "ProjectId" = p_project_id AND EXTRACT(YEAR FROM "TanggalWaktu") = p_tahun
        GROUP BY 2

        UNION ALL
        SELECT 'INCIDENT', EXTRACT(MONTH FROM "TanggalWaktu")::INT, COUNT(*)
        FROM "incidentTbl"
        WHERE "ProjectId" = p_project_id AND EXTRACT(YEAR FROM "TanggalWaktu") = p_tahun
        GROUP BY 2
    ),
    realisasi_agg AS (
        SELECT kode, jsonb_object_agg(bulan::text, jumlah) AS realisasi_bulanan, SUM(jumlah) AS realisasi_total
        FROM realisasi
        GROUP BY kode
    )
    SELECT COALESCE(jsonb_agg(
        jsonb_build_object(
            'itemId', mi."Id",
            'kodeItem', mi."KodeItem",
            'namaItem', mi."NamaItem",
            'satuanTarget', mi."SatuanTarget",
            'urutan', mi."Urutan",
            'statusPakai', COALESCE(hp."StatusPakai", 'N/A'),
            'targetQty', hp."TargetQty",
            'frequency', hp."Frequency",
            'targetBulanan', COALESCE(hp."TargetBulanan", '{"1":0,"2":0,"3":0,"4":0,"5":0,"6":0,"7":0,"8":0,"9":0,"10":0,"11":0,"12":0}'::jsonb),
            'targetTotal', COALESCE((
                SELECT SUM(v.value::text::int)
                FROM jsonb_each(COALESCE(hp."TargetBulanan", '{}'::jsonb)) v
            ), 0),
            'realisasiBulanan', COALESCE(ra.realisasi_bulanan, '{}'::jsonb),
            'realisasiTotal', COALESCE(ra.realisasi_total, 0)
        ) ORDER BY mi."Urutan"
    ), '[]'::jsonb)
    INTO v_result
    FROM "hseProgramMasterItemTbl" mi
    LEFT JOIN "hseProgramTbl" hp
        ON hp."ItemId" = mi."Id" AND hp."ProjectId" = p_project_id AND hp."Tahun" = p_tahun
    LEFT JOIN realisasi_agg ra ON ra.kode = mi."KodeItem";

    RETURN v_result;
END;
$function$;

-- -------------------------------------------------------------------------------------
-- 6. upsert_hse_program_item() -- tambah 2 parameter baru (TargetQty & Frequency),
--    signature berubah jadi DROP dulu versi lama baru CREATE yang baru.
-- -------------------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.upsert_hse_program_item(BIGINT, INT, BIGINT, TEXT, JSONB);

CREATE OR REPLACE FUNCTION public.upsert_hse_program_item(
    p_project_id BIGINT,
    p_tahun INT,
    p_item_id BIGINT,
    p_status_pakai TEXT,
    p_target_bulanan JSONB,
    p_target_qty NUMERIC DEFAULT NULL,
    p_frequency TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $function$
DECLARE
    v_id BIGINT;
BEGIN
    IF p_status_pakai NOT IN ('Use', 'N/A') THEN
        RAISE EXCEPTION 'StatusPakai harus Use atau N/A';
    END IF;

    IF p_frequency IS NOT NULL AND p_frequency NOT IN ('Harian', 'Mingguan', 'Bulanan', 'Triwulan', 'Semester', 'Tahunan') THEN
        RAISE EXCEPTION 'Frequency tidak valid';
    END IF;

    INSERT INTO "hseProgramTbl" ("ProjectId", "Tahun", "ItemId", "StatusPakai", "TargetBulanan", "TargetQty", "Frequency", "UpdatedAt")
    VALUES (
        p_project_id, p_tahun, p_item_id, p_status_pakai,
        COALESCE(p_target_bulanan, '{"1":0,"2":0,"3":0,"4":0,"5":0,"6":0,"7":0,"8":0,"9":0,"10":0,"11":0,"12":0}'::jsonb),
        p_target_qty, p_frequency, NOW()
    )
    ON CONFLICT ("ProjectId", "Tahun", "ItemId")
    DO UPDATE SET
        "StatusPakai" = EXCLUDED."StatusPakai",
        "TargetBulanan" = EXCLUDED."TargetBulanan",
        "TargetQty" = EXCLUDED."TargetQty",
        "Frequency" = EXCLUDED."Frequency",
        "UpdatedAt" = NOW()
    RETURNING "Id" INTO v_id;

    RETURN jsonb_build_object('success', true, 'id', v_id);
END;
$function$;
