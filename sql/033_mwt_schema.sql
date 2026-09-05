-- =====================================================================================
-- HSSE-Fusion4 — MIGRASI #33: MODUL MANAGEMENT WALK THROUGH (MWT)
-- Jalankan SETELAH 001-032, di Supabase project HSSE-Fusion4.
--
-- Konsep (disepakati di chat):
-- 1. MWT itu kunjungan lapangan oleh manajemen/leadership buat liat langsung kondisi
--    HSSE, ngobrol sama pekerja, kasih bukti visible leadership commitment -- BUKAN
--    audit formal, jadi form-nya SIMPEL: submit tunggal + Author-gate (Author
--    "Management Walkthrough"), sesuai pola HSE Meeting/CERMAT/Inspeksi (gak ada
--    checklist+skor kayak Inspeksi, gak ada alur findings/CAPA berjenjang kayak
--    Internal Audit).
-- 2. Isi kunjungan: Area/Lokasi yang dikunjungi, Pendamping (dinamis, nama+jabatan),
--    Catatan Observasi Umum (freeform, BUKAN daftar temuan terstruktur), Jumlah
--    Pekerja yang Diajak Diskusi, Foto Dokumentasi.
-- 3. Realisasi-nya nyambung ke HSE Program (get_hse_program, KodeItem='MWT') yang
--    sebelumnya (sql/031) masih dikunci 0 karena modulnya belum dibangun.
-- =====================================================================================


-- -------------------------------------------------------------------------------------
-- 1. TABEL MWT
-- -------------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS "mwtTbl" (
    "Id" BIGSERIAL PRIMARY KEY,
    "NoMWT" TEXT UNIQUE NOT NULL,
    "ProjectId" BIGINT NOT NULL REFERENCES "projectTbl"("Id"),
    "TanggalKunjungan" TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    "AreaKunjungan" TEXT NOT NULL,
    "NamaManagement" TEXT NOT NULL,
    "ManagementQrCodeId" TEXT DEFAULT '',
    "PendampingList" JSONB NOT NULL DEFAULT '[]'::jsonb, -- [{nama, jabatan}]
    "JumlahPekerjaDiskusi" INT NOT NULL DEFAULT 0,
    "CatatanObservasi" TEXT DEFAULT '',
    "FotoList" JSONB NOT NULL DEFAULT '[]'::jsonb,
    "CreatedAt" TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_mwt_project ON "mwtTbl" ("ProjectId");


-- -------------------------------------------------------------------------------------
-- 2. RPC: GENERATE NOMOR MWT
-- -------------------------------------------------------------------------------------
DROP FUNCTION IF EXISTS generate_no_mwt();
CREATE OR REPLACE FUNCTION generate_no_mwt()
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_date_str TEXT := TO_CHAR(NOW() AT TIME ZONE 'Asia/Makassar', 'YYYYMMDD');
    v_rand TEXT := LPAD(FLOOR(RANDOM() * 9000 + 1000)::TEXT, 4, '0');
BEGIN
    RETURN 'BIMA/MWT/' || v_date_str || '-' || v_rand;
END;
$$;


-- -------------------------------------------------------------------------------------
-- 3. RPC: SUBMIT MWT
-- -------------------------------------------------------------------------------------
DROP FUNCTION IF EXISTS submit_mwt(BIGINT, TEXT, TEXT, JSONB, INT, TEXT, TEXT, TIMESTAMPTZ, JSONB);
CREATE OR REPLACE FUNCTION submit_mwt(
    p_project_id BIGINT,
    p_area_kunjungan TEXT,
    p_nama_management TEXT,
    p_pendamping_list JSONB,
    p_jumlah_pekerja_diskusi INT,
    p_management_qrcode TEXT DEFAULT '',
    p_catatan_observasi TEXT DEFAULT '',
    p_tanggal_kunjungan TIMESTAMPTZ DEFAULT NULL,
    p_foto_list JSONB DEFAULT '[]'::jsonb
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_no_mwt TEXT := generate_no_mwt();
    v_id BIGINT;
BEGIN
    INSERT INTO "mwtTbl" (
        "NoMWT", "ProjectId", "TanggalKunjungan", "AreaKunjungan",
        "NamaManagement", "ManagementQrCodeId", "PendampingList",
        "JumlahPekerjaDiskusi", "CatatanObservasi", "FotoList"
    ) VALUES (
        v_no_mwt, p_project_id, COALESCE(p_tanggal_kunjungan, NOW()), p_area_kunjungan,
        p_nama_management, p_management_qrcode, p_pendamping_list,
        p_jumlah_pekerja_diskusi, p_catatan_observasi, p_foto_list
    )
    RETURNING "Id" INTO v_id;

    RETURN jsonb_build_object('success', true, 'id', v_id, 'noMWT', v_no_mwt);
END;
$$;


-- -------------------------------------------------------------------------------------
-- 4. RPC: AMBIL DAFTAR (RIWAYAT) & DETAIL BY ID
-- -------------------------------------------------------------------------------------
DROP FUNCTION IF EXISTS get_mwt_list(BIGINT);
CREATE OR REPLACE FUNCTION get_mwt_list(p_project_id BIGINT DEFAULT NULL)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_result JSONB;
BEGIN
    SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'id', c."Id",
        'noMWT', c."NoMWT",
        'tanggalKunjungan', c."TanggalKunjungan",
        'areaKunjungan', c."AreaKunjungan",
        'namaManagement', c."NamaManagement",
        'managementQrCodeId', c."ManagementQrCodeId",
        'pendampingList', c."PendampingList",
        'jumlahPekerjaDiskusi', c."JumlahPekerjaDiskusi",
        'catatanObservasi', c."CatatanObservasi",
        'fotoList', c."FotoList",
        'namaProject', p."NamaProject",
        'noKontrak', p."NoKontrak"
    ) ORDER BY c."TanggalKunjungan" DESC), '[]'::JSONB)
    INTO v_result
    FROM "mwtTbl" c
    JOIN "projectTbl" p ON p."Id" = c."ProjectId"
    WHERE p_project_id IS NULL OR c."ProjectId" = p_project_id;

    RETURN v_result;
END;
$$;


DROP FUNCTION IF EXISTS get_mwt_by_id(BIGINT);
CREATE OR REPLACE FUNCTION get_mwt_by_id(p_id BIGINT)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_result JSONB;
BEGIN
    SELECT jsonb_build_object(
        'id', c."Id",
        'noMWT', c."NoMWT",
        'tanggalKunjungan', c."TanggalKunjungan",
        'areaKunjungan', c."AreaKunjungan",
        'namaManagement', c."NamaManagement",
        'managementQrCodeId', c."ManagementQrCodeId",
        'pendampingList', c."PendampingList",
        'jumlahPekerjaDiskusi', c."JumlahPekerjaDiskusi",
        'catatanObservasi', c."CatatanObservasi",
        'fotoList', c."FotoList",
        'namaProject', p."NamaProject",
        'noKontrak', p."NoKontrak",
        'tipeKonstruksi', p."TipeKonstruksi"
    )
    INTO v_result
    FROM "mwtTbl" c
    JOIN "projectTbl" p ON p."Id" = c."ProjectId"
    WHERE c."Id" = p_id;

    RETURN v_result;
END;
$$;


-- -------------------------------------------------------------------------------------
-- 5. get_hse_program() -- tambah 1 UNION ALL buat realisasi MWT (kode item 'MWT' udah
--    ada dari sql/031, sebelumnya realisasinya selalu 0 karena modulnya belum ada).
--    Body fungsi ini disalin utuh dari sql/032_hse_program_frequency_spread.sql,
--    cuma nambah 1 blok UNION ALL di CTE "realisasi" -- gak ada bagian lain yang diubah.
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

        UNION ALL
        SELECT 'MWT', EXTRACT(MONTH FROM "TanggalKunjungan")::INT, COUNT(*)
        FROM "mwtTbl"
        WHERE "ProjectId" = p_project_id AND EXTRACT(YEAR FROM "TanggalKunjungan") = p_tahun
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
-- 6. Update deskripsi item master MWT (baris sudah ada dari sql/031, KodeItem='MWT')
--    sekarang modulnya sudah dibangun -- gak ubah NamaItem/SatuanTarget/Urutan.
-- -------------------------------------------------------------------------------------
UPDATE "hseProgramMasterItemTbl" SET "Keterangan" = 'Realisasi dari modul MWT' WHERE "KodeItem" = 'MWT';
