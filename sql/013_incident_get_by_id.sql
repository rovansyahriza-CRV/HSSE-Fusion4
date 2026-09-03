-- =====================================================================================
-- HSSE-Fusion4 — MIGRASI #13: RPC get_incident_report_by_id (buat incident-pdf.html)
-- Jalankan SETELAH 001-012, di Supabase project HSSE-Fusion4.
--
-- CERMAT udah punya get_cermat_report_by_id() buat cermat-pdf.html -- Incident/Accident
-- belum, jadi belum ada halaman cetak per laporan. RPC ini bikin itu ada, dipakai sama
-- incident-pdf.html?id=<Id>.
-- =====================================================================================

DROP FUNCTION IF EXISTS get_incident_report_by_id(BIGINT);
CREATE OR REPLACE FUNCTION get_incident_report_by_id(p_id BIGINT)
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
        'lampiranList', c."LampiranList",
        'penanggungJawab', c."PenanggungJawab",
        'tenggat', c."Tenggat",
        'status', c."Status",
        'tanggalClosed', c."TanggalClosed",
        'catatanClosed', c."CatatanClosed",
        'catatanPenolakan', c."CatatanPenolakan",
        'investigasiOleh', c."InvestigasiOleh",
        'investigasiQrCodeId', c."InvestigasiQrCodeId",
        'tanggalInvestigasi', c."TanggalInvestigasi",
        'reviewOleh', c."ReviewOleh",
        'reviewQrCodeId', c."ReviewQrCodeId",
        'tanggalReview', c."TanggalReview",
        'lessonLearned', c."LessonLearned",
        'approvedOleh', c."ApprovedOleh",
        'approvedQrCodeId', c."ApprovedQrCodeId",
        'tanggalApproved', c."TanggalApproved",
        'namaProject', p."NamaProject",
        'noKontrak', p."NoKontrak",
        'tipeKonstruksi', p."TipeKonstruksi"
    )
    INTO v_result
    FROM "incidentTbl" c
    JOIN "projectTbl" p ON p."Id" = c."ProjectId"
    WHERE c."Id" = p_id;

    RETURN v_result;
END;
$$;
