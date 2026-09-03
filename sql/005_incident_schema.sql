-- =====================================================================================
-- HSSE-Fusion4 — MIGRASI #5: MODUL "INCIDENT / ACCIDENT REPORT"
-- Jalankan SETELAH 001-004, di Supabase project HSSE-Fusion4 yang sama.
-- Pola sama kayak CERMAT: identifikasi Pelapor via QR/wajah (Fusion4), 3 foto bukti,
-- lifecycle Open -> Investigasi -> Closed (bisa reopen). Bedanya: ada klasifikasi
-- tingkat keparahan standar oil & gas (buat hitung LTIFR/TRIR di modul Statistik nanti)
-- + info korban (manual, gak lewat scan) + kolom investigasi (akar masalah/root cause,
-- tindakan korektif, hari kerja hilang).
-- =====================================================================================

-- -------------------------------------------------------------------------------------
-- 1. TABEL LAPORAN INCIDENT/ACCIDENT
-- -------------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS "incidentTbl" (
    "Id" BIGSERIAL PRIMARY KEY,
    "NoLaporan" TEXT UNIQUE NOT NULL,
    "ProjectId" BIGINT NOT NULL REFERENCES "projectTbl"("Id"),
    "TanggalWaktu" TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    "NamaPelapor" TEXT NOT NULL,
    "PelaporQrCodeId" TEXT,
    "Klasifikasi" TEXT NOT NULL CHECK ("Klasifikasi" IN (
        'Near Miss', 'First Aid Case', 'Medical Treatment Case', 'Restricted Work Case',
        'Lost Time Injury', 'Fatality', 'Kerusakan Properti', 'Lingkungan', 'Keamanan/Security'
    )),
    "LokasiArea" TEXT NOT NULL,
    "Kronologi" TEXT NOT NULL,
    "NamaKorban" TEXT DEFAULT '',
    "JabatanPerusahaanKorban" TEXT DEFAULT '',
    "HariKerjaHilang" INT,
    "TindakanLangsung" TEXT DEFAULT '',
    "FotoList" JSONB NOT NULL DEFAULT '[]'::jsonb,
    "AkarMasalah" TEXT DEFAULT '',
    "TindakanKorektif" TEXT DEFAULT '',
    "FotoTindakLanjutList" JSONB NOT NULL DEFAULT '[]'::jsonb,
    "PenanggungJawab" TEXT DEFAULT '',
    "Tenggat" DATE,
    "Status" TEXT NOT NULL DEFAULT 'Open' CHECK ("Status" IN ('Open', 'Investigasi', 'Closed')),
    "TanggalClosed" TIMESTAMPTZ,
    "CatatanClosed" TEXT DEFAULT '',
    "CreatedAt" TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_incident_project ON "incidentTbl" ("ProjectId");
CREATE INDEX IF NOT EXISTS idx_incident_status ON "incidentTbl" ("Status");
CREATE INDEX IF NOT EXISTS idx_incident_klasifikasi ON "incidentTbl" ("Klasifikasi");


-- -------------------------------------------------------------------------------------
-- 2. RPC: GENERATE NOMOR LAPORAN INCIDENT
-- Format: BIMA/INSIDEN/YYYYMMDD-XXXX
-- -------------------------------------------------------------------------------------
DROP FUNCTION IF EXISTS generate_no_incident();
CREATE OR REPLACE FUNCTION generate_no_incident()
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_date_str TEXT := TO_CHAR(NOW() AT TIME ZONE 'Asia/Makassar', 'YYYYMMDD');
    v_rand TEXT := LPAD(FLOOR(RANDOM() * 9000 + 1000)::TEXT, 4, '0');
BEGIN
    RETURN 'BIMA/INSIDEN/' || v_date_str || '-' || v_rand;
END;
$$;


-- -------------------------------------------------------------------------------------
-- 3. RPC: SUBMIT LAPORAN INCIDENT BARU
-- -------------------------------------------------------------------------------------
DROP FUNCTION IF EXISTS submit_incident_report(BIGINT, TEXT, TEXT, TEXT, TEXT, TEXT, JSONB, TEXT, TEXT, TEXT, INT);
CREATE OR REPLACE FUNCTION submit_incident_report(
    p_project_id BIGINT,
    p_nama_pelapor TEXT,
    p_klasifikasi TEXT,
    p_lokasi_area TEXT,
    p_kronologi TEXT,
    p_pelapor_qrcode TEXT DEFAULT '',
    p_foto_list JSONB DEFAULT '[]'::jsonb,
    p_nama_korban TEXT DEFAULT '',
    p_jabatan_korban TEXT DEFAULT '',
    p_tindakan_langsung TEXT DEFAULT '',
    p_hari_kerja_hilang INT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_no_laporan TEXT := generate_no_incident();
    v_id BIGINT;
BEGIN
    INSERT INTO "incidentTbl" (
        "NoLaporan", "ProjectId", "NamaPelapor", "PelaporQrCodeId", "Klasifikasi",
        "LokasiArea", "Kronologi", "FotoList", "NamaKorban", "JabatanPerusahaanKorban",
        "TindakanLangsung", "HariKerjaHilang"
    ) VALUES (
        v_no_laporan, p_project_id, p_nama_pelapor, NULLIF(p_pelapor_qrcode, ''), p_klasifikasi,
        p_lokasi_area, p_kronologi, p_foto_list, p_nama_korban, p_jabatan_korban,
        p_tindakan_langsung, p_hari_kerja_hilang
    )
    RETURNING "Id" INTO v_id;

    RETURN jsonb_build_object('success', true, 'id', v_id, 'noLaporan', v_no_laporan);
END;
$$;


-- -------------------------------------------------------------------------------------
-- 4. RPC: AMBIL DAFTAR LAPORAN INCIDENT (buat halaman riwayat)
-- p_status: NULL = semua, atau 'Open' / 'Investigasi' / 'Closed'
-- -------------------------------------------------------------------------------------
DROP FUNCTION IF EXISTS get_incident_reports(TEXT);
CREATE OR REPLACE FUNCTION get_incident_reports(p_status TEXT DEFAULT NULL)
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
        'pelaporQrCodeId', c."PelaporQrCodeId",
        'klasifikasi', c."Klasifikasi",
        'lokasiArea', c."LokasiArea",
        'kronologi', c."Kronologi",
        'namaKorban', c."NamaKorban",
        'jabatanPerusahaanKorban', c."JabatanPerusahaanKorban",
        'hariKerjaHilang', c."HariKerjaHilang",
        'tindakanLangsung', c."TindakanLangsung",
        'fotoList', c."FotoList",
        'akarMasalah', c."AkarMasalah",
        'tindakanKorektif', c."TindakanKorektif",
        'fotoTindakLanjutList', c."FotoTindakLanjutList",
        'penanggungJawab', c."PenanggungJawab",
        'tenggat', c."Tenggat",
        'status', c."Status",
        'tanggalClosed', c."TanggalClosed",
        'catatanClosed', c."CatatanClosed",
        'namaProject', p."NamaProject",
        'noKontrak', p."NoKontrak"
    ) ORDER BY c."TanggalWaktu" DESC), '[]'::JSONB)
    INTO v_result
    FROM "incidentTbl" c
    JOIN "projectTbl" p ON p."Id" = c."ProjectId"
    WHERE p_status IS NULL OR c."Status" = p_status;

    RETURN v_result;
END;
$$;


-- -------------------------------------------------------------------------------------
-- 5. RPC: UPDATE STATUS / INVESTIGASI LAPORAN INCIDENT
-- -------------------------------------------------------------------------------------
DROP FUNCTION IF EXISTS update_incident_status(BIGINT, TEXT, TEXT, DATE, TEXT, JSONB, TEXT, TEXT, INT);
CREATE OR REPLACE FUNCTION update_incident_status(
    p_id BIGINT,
    p_status TEXT,
    p_penanggung_jawab TEXT DEFAULT '',
    p_tenggat DATE DEFAULT NULL,
    p_catatan_closed TEXT DEFAULT '',
    p_foto_tambahan JSONB DEFAULT '[]'::jsonb,
    p_akar_masalah TEXT DEFAULT '',
    p_tindakan_korektif TEXT DEFAULT '',
    p_hari_kerja_hilang INT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    UPDATE "incidentTbl"
    SET "Status" = p_status,
        "PenanggungJawab" = p_penanggung_jawab,
        "Tenggat" = p_tenggat,
        "CatatanClosed" = p_catatan_closed,
        "AkarMasalah" = p_akar_masalah,
        "TindakanKorektif" = p_tindakan_korektif,
        "HariKerjaHilang" = COALESCE(p_hari_kerja_hilang, "HariKerjaHilang"),
        "TanggalClosed" = CASE WHEN p_status = 'Closed' THEN NOW() ELSE NULL END,
        "FotoTindakLanjutList" = "FotoTindakLanjutList" || COALESCE(p_foto_tambahan, '[]'::jsonb)
    WHERE "Id" = p_id;

    RETURN jsonb_build_object('success', true);
END;
$$;
