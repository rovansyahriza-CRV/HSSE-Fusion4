-- =====================================================================================
-- HSSE-Fusion4 — MIGRASI #2: Identitas Pelapor Terverifikasi + Multi-Foto
-- Jalankan SETELAH 001_cermat_schema.sql, di Supabase project HSSE-Fusion4 yang sama
-- (Dashboard -> SQL Editor -> New query -> paste semua isi file ini -> Run).
--
-- Perubahan:
-- 1. Pelapor sekarang diidentifikasi lewat Scan QR Code / Scan Wajah (dicocokkan ke
--    database karyawan Fusion4, read-only), bukan diketik manual -- makanya perlu kolom
--    "PelaporQrCodeId" buat jejak audit siapa yang beneran lapor.
-- 2. Foto bukti sekarang bisa sampai 3 slot (dulu cuma 1), jadi diganti dari 2 kolom
--    TEXT ("FotoUrl"/"FotoFileId") jadi 1 kolom JSONB ("FotoList") berisi array
--    [{ "url": ..., "fileId": ... }, ...]. Data foto lama (kalau ada) dipindah dulu ke
--    format baru sebelum kolom lamanya dihapus, jadi aman dijalankan meski sudah ada
--    laporan tes tersimpan.
-- =====================================================================================

ALTER TABLE "cermatTbl" ADD COLUMN IF NOT EXISTS "FotoList" JSONB NOT NULL DEFAULT '[]'::jsonb;
ALTER TABLE "cermatTbl" ADD COLUMN IF NOT EXISTS "PelaporQrCodeId" TEXT DEFAULT '';

-- Pindahkan data foto lama (kalau kolomnya masih ada & masih ada isinya) ke FotoList.
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'cermatTbl' AND column_name = 'FotoUrl') THEN
    UPDATE "cermatTbl"
    SET "FotoList" = jsonb_build_array(jsonb_build_object('url', "FotoUrl", 'fileId', "FotoFileId"))
    WHERE "FotoUrl" IS NOT NULL AND "FotoUrl" <> '' AND "FotoList" = '[]'::jsonb;
  END IF;
END $$;

ALTER TABLE "cermatTbl" DROP COLUMN IF EXISTS "FotoUrl";
ALTER TABLE "cermatTbl" DROP COLUMN IF EXISTS "FotoFileId";


-- -------------------------------------------------------------------------------------
-- RPC: SUBMIT LAPORAN CERMAT -- signature baru (p_foto_list JSONB, p_pelapor_qrcode TEXT)
-- Signature LAMA (dari 001) di-drop dulu karena daftar parameternya beda.
-- -------------------------------------------------------------------------------------
DROP FUNCTION IF EXISTS submit_cermat_report(BIGINT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT);
DROP FUNCTION IF EXISTS submit_cermat_report(BIGINT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, JSONB, TEXT, TEXT);
CREATE OR REPLACE FUNCTION submit_cermat_report(
    p_project_id BIGINT,
    p_nama_pelapor TEXT,
    p_sifat TEXT,
    p_jenis_temuan TEXT,
    p_lokasi_area TEXT,
    p_deskripsi TEXT,
    p_pelapor_qrcode TEXT DEFAULT '',
    p_foto_list JSONB DEFAULT '[]'::jsonb,
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
        "NoLaporan", "ProjectId", "NamaPelapor", "PelaporQrCodeId", "Sifat", "JenisTemuan",
        "LokasiArea", "Deskripsi", "FotoList",
        "TindakanLangsung", "Rekomendasi"
    ) VALUES (
        v_no_laporan, p_project_id, p_nama_pelapor, p_pelapor_qrcode, p_sifat, p_jenis_temuan,
        p_lokasi_area, p_deskripsi, p_foto_list,
        p_tindakan_langsung, p_rekomendasi
    )
    RETURNING "Id" INTO v_id;

    RETURN jsonb_build_object('success', true, 'id', v_id, 'noLaporan', v_no_laporan);
END;
$$;


-- -------------------------------------------------------------------------------------
-- RPC: AMBIL DAFTAR LAPORAN CERMAT -- update: fotoList (array) & pelaporQrCodeId
-- Signature (p_status TEXT) TIDAK berubah, jadi cukup CREATE OR REPLACE.
-- -------------------------------------------------------------------------------------
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
        'pelaporQrCodeId', c."PelaporQrCodeId",
        'sifat', c."Sifat",
        'jenisTemuan', c."JenisTemuan",
        'lokasiArea', c."LokasiArea",
        'deskripsi', c."Deskripsi",
        'fotoList', c."FotoList",
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
