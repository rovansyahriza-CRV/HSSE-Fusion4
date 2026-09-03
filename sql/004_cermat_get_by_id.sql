-- =====================================================================================
-- HSSE-Fusion4 — MIGRASI #4: RPC ambil 1 laporan CERMAT by Id (buat halaman cetak PDF)
-- Jalankan SETELAH 001, 002, 003, di Supabase project HSSE-Fusion4 yang sama.
-- =====================================================================================

DROP FUNCTION IF EXISTS get_cermat_report_by_id(BIGINT);
CREATE OR REPLACE FUNCTION get_cermat_report_by_id(p_id BIGINT)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_result JSONB;
BEGIN
    SELECT jsonb_build_object(
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
        'fotoTindakLanjutList', c."FotoTindakLanjutList",
        'tindakanLangsung', c."TindakanLangsung",
        'rekomendasi', c."Rekomendasi",
        'penanggungJawab', c."PenanggungJawab",
        'tenggat', c."Tenggat",
        'status', c."Status",
        'tanggalClosed', c."TanggalClosed",
        'catatanClosed', c."CatatanClosed",
        'namaProject', p."NamaProject",
        'noKontrak', p."NoKontrak",
        'tipeKonstruksi', p."TipeKonstruksi"
    )
    INTO v_result
    FROM "cermatTbl" c
    JOIN "projectTbl" p ON p."Id" = c."ProjectId"
    WHERE c."Id" = p_id;

    RETURN v_result;
END;
$$;
