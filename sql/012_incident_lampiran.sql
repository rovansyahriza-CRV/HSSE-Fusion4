-- =====================================================================================
-- HSSE-Fusion4 — MIGRASI #12: Lampiran bebas (dokumen apa aja) di laporan Incident/Accident
-- Jalankan SETELAH 001-011, di Supabase project HSSE-Fusion4.
--
-- Investigator bisa upload lampiran APA AJA (PDF, Word, foto tambahan, dll) pas isi &
-- submit investigasi di tahap Open -> Investigasi -- satu aksi yang sama, gak ada form
-- terpisah. File-nya kesimpen di Google Drive (folder "lampiran"/HSSE-Lampiran) lewat
-- driveBridge.js, cuma link + nama filenya yang kesimpen di database.
-- =====================================================================================

ALTER TABLE "incidentTbl"
    ADD COLUMN IF NOT EXISTS "LampiranList" JSONB NOT NULL DEFAULT '[]'::jsonb;


-- -------------------------------------------------------------------------------------
-- RPC: PORTAL INVESTIGASI (Open -> Investigasi) -- tambah parameter p_lampiran.
-- -------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION incident_submit_investigation(
    p_id BIGINT,
    p_penanggung_jawab TEXT DEFAULT '',
    p_tenggat DATE DEFAULT NULL,
    p_akar_masalah TEXT DEFAULT '',
    p_tindakan_korektif TEXT DEFAULT '',
    p_hari_kerja_hilang INT DEFAULT NULL,
    p_foto_tambahan JSONB DEFAULT '[]'::jsonb,
    p_lampiran JSONB DEFAULT '[]'::jsonb,
    p_nama TEXT DEFAULT NULL,
    p_qrcode TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    UPDATE "incidentTbl"
    SET "PenanggungJawab" = p_penanggung_jawab,
        "Tenggat" = p_tenggat,
        "AkarMasalah" = p_akar_masalah,
        "TindakanKorektif" = p_tindakan_korektif,
        "HariKerjaHilang" = COALESCE(p_hari_kerja_hilang, "HariKerjaHilang"),
        "FotoTindakLanjutList" = "FotoTindakLanjutList" || COALESCE(p_foto_tambahan, '[]'::jsonb),
        "LampiranList" = "LampiranList" || COALESCE(p_lampiran, '[]'::jsonb),
        "Status" = 'Investigasi',
        "InvestigasiOleh" = p_nama,
        "InvestigasiQrCodeId" = p_qrcode,
        "TanggalInvestigasi" = NOW()
    WHERE "Id" = p_id;

    RETURN jsonb_build_object('success', true);
END;
$$;


-- -------------------------------------------------------------------------------------
-- RPC: get_incident_reports -- tambah field lampiranList.
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
        'noKontrak', p."NoKontrak"
    ) ORDER BY c."TanggalWaktu" DESC), '[]'::JSONB)
    INTO v_result
    FROM "incidentTbl" c
    JOIN "projectTbl" p ON p."Id" = c."ProjectId"
    WHERE p_status IS NULL OR c."Status" = p_status;

    RETURN v_result;
END;
$$;
