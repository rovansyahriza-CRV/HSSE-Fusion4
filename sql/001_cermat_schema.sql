-- =====================================================================================
-- HSSE-Fusion4 — MIGRASI SKEMA MODUL "CERMAT" (Anomaly Report: Positif & Negatif)
-- Jalankan file ini di Supabase project HSSE-Fusion4 (bukan project Fusion4/SMMS lama!)
-- lewat Dashboard -> SQL Editor -> New query -> paste semua isi file ini -> Run.
-- =====================================================================================

-- -------------------------------------------------------------------------------------
-- 1. TABEL MASTER PROJECT / KONTRAK
-- Setiap laporan CERMAT harus terikat ke satu Project, biar gampang direkap per-kontrak
-- pas audit klien migas.
-- -------------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS "projectTbl" (
    "Id" BIGSERIAL PRIMARY KEY,
    "NamaProject" TEXT NOT NULL,
    "NoKontrak" TEXT NOT NULL,
    "TipeKonstruksi" TEXT NOT NULL CHECK ("TipeKonstruksi" IN ('Onshore', 'Offshore')),
    "Client" TEXT DEFAULT 'Pertamina Hulu Energi',
    "Status" TEXT NOT NULL DEFAULT 'Aktif' CHECK ("Status" IN ('Aktif', 'Selesai', 'Non-Aktif')),
    "CreatedAt" TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Contoh 1 project placeholder biar dropdown gak kosong pas pertama kali dites.
-- GANTI/HAPUS ini lewat Table Editor Supabase, terus tambahkan project/kontrak asli kalian.
INSERT INTO "projectTbl" ("NamaProject", "NoKontrak", "TipeKonstruksi", "Status")
SELECT 'Contoh Project - GANTI INI', 'CONTRACT-NO-001', 'Onshore', 'Aktif'
WHERE NOT EXISTS (SELECT 1 FROM "projectTbl");


-- -------------------------------------------------------------------------------------
-- 2. TABEL LAPORAN CERMAT
-- Sifat: Positif (safe act/condition, layak diapresiasi) atau Negatif (unsafe act/
-- condition/near-miss, perlu tindak lanjut). Status dipakai buat tracking corrective
-- action sampai closed -- ini yang bikin sistemnya "audit-ready".
-- -------------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS "cermatTbl" (
    "Id" BIGSERIAL PRIMARY KEY,
    "NoLaporan" TEXT UNIQUE NOT NULL,
    "ProjectId" BIGINT NOT NULL REFERENCES "projectTbl"("Id"),
    "TanggalWaktu" TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    "NamaPelapor" TEXT NOT NULL,
    "Sifat" TEXT NOT NULL CHECK ("Sifat" IN ('Positif', 'Negatif')),
    "JenisTemuan" TEXT NOT NULL, -- 'Safe Act' | 'Safe Condition' | 'Unsafe Act' | 'Unsafe Condition' | 'Near Miss'
    "LokasiArea" TEXT NOT NULL,
    "Deskripsi" TEXT NOT NULL,
    "FotoUrl" TEXT,
    "FotoFileId" TEXT,
    "TindakanLangsung" TEXT DEFAULT '',
    "Rekomendasi" TEXT DEFAULT '',
    "PenanggungJawab" TEXT DEFAULT '',
    "Tenggat" DATE,
    "Status" TEXT NOT NULL DEFAULT 'Open' CHECK ("Status" IN ('Open', 'In Progress', 'Closed')),
    "TanggalClosed" TIMESTAMPTZ,
    "CatatanClosed" TEXT DEFAULT '',
    "CreatedAt" TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_cermat_project ON "cermatTbl" ("ProjectId");
CREATE INDEX IF NOT EXISTS idx_cermat_status ON "cermatTbl" ("Status");


-- -------------------------------------------------------------------------------------
-- 3. RPC: GENERATE NOMOR LAPORAN CERMAT
-- Format: BIMA/CERMAT/YYYYMMDD-XXXX (pola sama kayak generate_no_transaksi_eur di SMMS)
-- -------------------------------------------------------------------------------------
DROP FUNCTION IF EXISTS generate_no_cermat();
CREATE OR REPLACE FUNCTION generate_no_cermat()
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_date_str TEXT := TO_CHAR(NOW() AT TIME ZONE 'Asia/Makassar', 'YYYYMMDD');
    v_rand TEXT := LPAD(FLOOR(RANDOM() * 9000 + 1000)::TEXT, 4, '0');
BEGIN
    RETURN 'BIMA/CERMAT/' || v_date_str || '-' || v_rand;
END;
$$;


-- -------------------------------------------------------------------------------------
-- 4. RPC: AMBIL DAFTAR PROJECT AKTIF (buat dropdown di form)
-- -------------------------------------------------------------------------------------
DROP FUNCTION IF EXISTS get_active_projects();
CREATE OR REPLACE FUNCTION get_active_projects()
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
        'tipeKonstruksi', "TipeKonstruksi"
    ) ORDER BY "NamaProject"), '[]'::JSONB)
    INTO v_result
    FROM "projectTbl"
    WHERE "Status" = 'Aktif';

    RETURN v_result;
END;
$$;


-- -------------------------------------------------------------------------------------
-- 5. RPC: SUBMIT LAPORAN CERMAT BARU
-- -------------------------------------------------------------------------------------
DROP FUNCTION IF EXISTS submit_cermat_report(BIGINT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT);
CREATE OR REPLACE FUNCTION submit_cermat_report(
    p_project_id BIGINT,
    p_nama_pelapor TEXT,
    p_sifat TEXT,
    p_jenis_temuan TEXT,
    p_lokasi_area TEXT,
    p_deskripsi TEXT,
    p_foto_url TEXT DEFAULT NULL,
    p_foto_file_id TEXT DEFAULT NULL,
    p_tindakan_langsung TEXT DEFAULT '',
    p_rekomendasi TEXT DEFAULT ''
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_no_laporan TEXT := generate_no_cermat();
    v_id BIGINT;
BEGIN
    INSERT INTO "cermatTbl" (
        "NoLaporan", "ProjectId", "NamaPelapor", "Sifat", "JenisTemuan",
        "LokasiArea", "Deskripsi", "FotoUrl", "FotoFileId",
        "TindakanLangsung", "Rekomendasi"
    ) VALUES (
        v_no_laporan, p_project_id, p_nama_pelapor, p_sifat, p_jenis_temuan,
        p_lokasi_area, p_deskripsi, p_foto_url, p_foto_file_id,
        p_tindakan_langsung, p_rekomendasi
    )
    RETURNING "Id" INTO v_id;

    RETURN jsonb_build_object('success', true, 'id', v_id, 'noLaporan', v_no_laporan);
END;
$$;


-- -------------------------------------------------------------------------------------
-- 6. RPC: AMBIL DAFTAR LAPORAN CERMAT (buat halaman riwayat/audit)
-- p_status: NULL = semua, atau 'Open' / 'In Progress' / 'Closed'
-- -------------------------------------------------------------------------------------
DROP FUNCTION IF EXISTS get_cermat_reports(TEXT);
CREATE OR REPLACE FUNCTION get_cermat_reports(p_status TEXT DEFAULT NULL)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_result JSONB;
BEGIN
    SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'id', c."Id",
        'noLaporan', c."NoLaporan",
        'tanggalWaktu', c."TanggalWaktu",
        'namaPelapor', c."NamaPelapor",
        'sifat', c."Sifat",
        'jenisTemuan', c."JenisTemuan",
        'lokasiArea', c."LokasiArea",
        'deskripsi', c."Deskripsi",
        'fotoUrl', c."FotoUrl",
        'tindakanLangsung', c."TindakanLangsung",
        'rekomendasi', c."Rekomendasi",
        'penanggungJawab', c."PenanggungJawab",
        'tenggat', c."Tenggat",
        'status', c."Status",
        'tanggalClosed', c."TanggalClosed",
        'catatanClosed', c."CatatanClosed",
        'namaProject', p."NamaProject",
        'noKontrak', p."NoKontrak"
    ) ORDER BY c."TanggalWaktu" DESC), '[]'::JSONB)
    INTO v_result
    FROM "cermatTbl" c
    JOIN "projectTbl" p ON p."Id" = c."ProjectId"
    WHERE p_status IS NULL OR c."Status" = p_status;

    RETURN v_result;
END;
$$;


-- -------------------------------------------------------------------------------------
-- 7. RPC: UPDATE STATUS / TINDAK LANJUT LAPORAN (dipakai di halaman riwayat/audit)
-- -------------------------------------------------------------------------------------
DROP FUNCTION IF EXISTS update_cermat_status(BIGINT, TEXT, TEXT, DATE, TEXT);
CREATE OR REPLACE FUNCTION update_cermat_status(
    p_id BIGINT,
    p_status TEXT,
    p_penanggung_jawab TEXT DEFAULT '',
    p_tenggat DATE DEFAULT NULL,
    p_catatan_closed TEXT DEFAULT ''
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    UPDATE "cermatTbl"
    SET "Status" = p_status,
        "PenanggungJawab" = p_penanggung_jawab,
        "Tenggat" = p_tenggat,
        "CatatanClosed" = p_catatan_closed,
        "TanggalClosed" = CASE WHEN p_status = 'Closed' THEN NOW() ELSE NULL END
    WHERE "Id" = p_id;

    RETURN jsonb_build_object('success', true);
END;
$$;
