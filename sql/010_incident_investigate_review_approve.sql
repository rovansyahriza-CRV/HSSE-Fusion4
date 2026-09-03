-- =====================================================================================
-- HSSE-Fusion4 — MIGRASI #10 (REVISI): ALUR "PORTAL" 3 TAHAP UNTUK INCIDENT/ACCIDENT
-- Jalankan SETELAH 001-009, di Supabase project HSSE-Fusion4.
-- Kalau kamu udah sempat jalanin versi 010 SEBELUMNYA, aman jalanin ulang file ini --
-- semua pakai CREATE OR REPLACE / ADD COLUMN IF NOT EXISTS, gak bakal dobel/rusak.
--
-- REVISI dari versi sebelumnya: isi laporan (Akar Masalah/Tindakan Korektif/dst) BUKAN
-- lagi form bebas yang bisa diedit kapan aja -- sekarang isi + submit itu SATU aksi
-- gabungan sama verifikasi identitas, persis pola CERMAT (Dept Admin verifikasi+isi+
-- submit followup jadi satu aksi):
--
--   Open --(verifikasi "Investigate Incident/Accident", ISI form investigasi, submit)--> Investigasi
--   Investigasi --(verifikasi "Review Incident/Accident", isi catatan review opsional, submit)--> Review
--   Review --(verifikasi "Approved Incident/Accident")--> Closed (approve, catatan penutupan opsional)
--                                                       \-> Open (reject, WAJIB isi catatan penolakan
--                                                           -- balik ke Open karena isi laporan cuma
--                                                           bisa diedit ulang lewat portal Open lagi)
--   Closed --(verifikasi "Approved Incident/Accident", reopen)--> Open (isi investigasi diulang dari nol)
-- =====================================================================================

ALTER TABLE "incidentTbl" DROP CONSTRAINT IF EXISTS "incidentTbl_Status_check";
ALTER TABLE "incidentTbl" ADD CONSTRAINT "incidentTbl_Status_check"
    CHECK ("Status" IN ('Open', 'Investigasi', 'Review', 'Closed'));

ALTER TABLE "incidentTbl"
    ADD COLUMN IF NOT EXISTS "InvestigasiOleh" TEXT,
    ADD COLUMN IF NOT EXISTS "InvestigasiQrCodeId" TEXT,
    ADD COLUMN IF NOT EXISTS "TanggalInvestigasi" TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS "ReviewOleh" TEXT,
    ADD COLUMN IF NOT EXISTS "ReviewQrCodeId" TEXT,
    ADD COLUMN IF NOT EXISTS "TanggalReview" TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS "CatatanReview" TEXT,
    ADD COLUMN IF NOT EXISTS "CatatanPenolakan" TEXT,
    ADD COLUMN IF NOT EXISTS "ApprovedOleh" TEXT,
    ADD COLUMN IF NOT EXISTS "ApprovedQrCodeId" TEXT,
    ADD COLUMN IF NOT EXISTS "TanggalApproved" TIMESTAMPTZ;

-- RPC lama dari revisi sebelumnya (form bebas tanpa gate) -- udah gak dipakai, digantikan
-- incident_submit_investigation() yang bundle isi+verifikasi+submit jadi satu.
DROP FUNCTION IF EXISTS update_incident_fields(BIGINT, TEXT, DATE, TEXT, TEXT, INT, JSONB);
DROP FUNCTION IF EXISTS update_incident_status(BIGINT, TEXT, TEXT, DATE, TEXT, JSONB, TEXT, TEXT, INT);
DROP FUNCTION IF EXISTS incident_start_investigation(BIGINT, TEXT, TEXT);


-- -------------------------------------------------------------------------------------
-- 1. RPC: PORTAL INVESTIGASI (Open -> Investigasi) -- Author "Investigate Incident/Accident".
-- Verifikasi + isi form investigasi + submit = SATU aksi. Field yang di-isi di sini
-- (PJ/Tenggat/Akar Masalah/Tindakan Korektif/Hari Kerja Hilang/Foto) kesimpen bareng
-- status berubah jadi "Investigasi".
-- -------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION incident_submit_investigation(
    p_id BIGINT,
    p_penanggung_jawab TEXT DEFAULT '',
    p_tenggat DATE DEFAULT NULL,
    p_akar_masalah TEXT DEFAULT '',
    p_tindakan_korektif TEXT DEFAULT '',
    p_hari_kerja_hilang INT DEFAULT NULL,
    p_foto_tambahan JSONB DEFAULT '[]'::jsonb,
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
        "Status" = 'Investigasi',
        "InvestigasiOleh" = p_nama,
        "InvestigasiQrCodeId" = p_qrcode,
        "TanggalInvestigasi" = NOW()
    WHERE "Id" = p_id;

    RETURN jsonb_build_object('success', true);
END;
$$;


-- -------------------------------------------------------------------------------------
-- 2. RPC: PORTAL REVIEW (Investigasi -> Review) -- Author "Review Incident/Accident".
-- Verifikasi + catatan review opsional + submit = satu aksi.
-- -------------------------------------------------------------------------------------
DROP FUNCTION IF EXISTS incident_submit_review(BIGINT, TEXT, TEXT);
CREATE OR REPLACE FUNCTION incident_submit_review(
    p_id BIGINT,
    p_catatan_review TEXT DEFAULT '',
    p_nama TEXT DEFAULT NULL,
    p_qrcode TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    UPDATE "incidentTbl"
    SET "Status" = 'Review',
        "CatatanReview" = p_catatan_review,
        "ReviewOleh" = p_nama,
        "ReviewQrCodeId" = p_qrcode,
        "TanggalReview" = NOW(),
        "CatatanPenolakan" = NULL
    WHERE "Id" = p_id;

    RETURN jsonb_build_object('success', true);
END;
$$;


-- -------------------------------------------------------------------------------------
-- 3. RPC: PORTAL APPROVAL -- keputusan Review: approve (Closed) atau reject (balik ke
-- Open, karena isi laporan cuma bisa diedit ulang lewat portal investigasi). Author
-- "Approved Incident/Accident".
-- -------------------------------------------------------------------------------------
DROP FUNCTION IF EXISTS incident_review_decision(BIGINT, TEXT, TEXT, TEXT, TEXT, TEXT);
CREATE OR REPLACE FUNCTION incident_review_decision(
    p_id BIGINT,
    p_decision TEXT, -- 'approve' | 'reject'
    p_catatan_closed TEXT DEFAULT '',
    p_catatan_penolakan TEXT DEFAULT '',
    p_nama TEXT DEFAULT NULL,
    p_qrcode TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    IF p_decision = 'approve' THEN
        UPDATE "incidentTbl"
        SET "Status" = 'Closed',
            "TanggalClosed" = NOW(),
            "CatatanClosed" = p_catatan_closed,
            "ApprovedOleh" = p_nama,
            "ApprovedQrCodeId" = p_qrcode,
            "TanggalApproved" = NOW(),
            "CatatanPenolakan" = NULL
        WHERE "Id" = p_id;
    ELSE
        UPDATE "incidentTbl"
        SET "Status" = 'Open',
            "CatatanPenolakan" = p_catatan_penolakan,
            "InvestigasiOleh" = NULL,
            "InvestigasiQrCodeId" = NULL,
            "TanggalInvestigasi" = NULL,
            "ReviewOleh" = NULL,
            "ReviewQrCodeId" = NULL,
            "TanggalReview" = NULL,
            "CatatanReview" = NULL
        WHERE "Id" = p_id;
    END IF;

    RETURN jsonb_build_object('success', true);
END;
$$;


-- -------------------------------------------------------------------------------------
-- 4. RPC: REOPEN (Closed -> Open, isi investigasi diulang dari nol) -- Author
-- "Approved Incident/Accident" juga.
-- -------------------------------------------------------------------------------------
DROP FUNCTION IF EXISTS incident_reopen(BIGINT, TEXT, TEXT);
CREATE OR REPLACE FUNCTION incident_reopen(
    p_id BIGINT,
    p_nama TEXT,
    p_qrcode TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    UPDATE "incidentTbl"
    SET "Status" = 'Open',
        "TanggalClosed" = NULL,
        "CatatanClosed" = '',
        "ApprovedOleh" = NULL,
        "ApprovedQrCodeId" = NULL,
        "TanggalApproved" = NULL,
        "InvestigasiOleh" = NULL,
        "InvestigasiQrCodeId" = NULL,
        "TanggalInvestigasi" = NULL,
        "ReviewOleh" = NULL,
        "ReviewQrCodeId" = NULL,
        "TanggalReview" = NULL,
        "CatatanReview" = NULL,
        "CatatanPenolakan" = NULL
    WHERE "Id" = p_id;

    RETURN jsonb_build_object('success', true);
END;
$$;


-- -------------------------------------------------------------------------------------
-- 5. RPC: get_incident_reports -- field baru buat 3 portal verifikasi.
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
        'catatanPenolakan', c."CatatanPenolakan",
        'investigasiOleh', c."InvestigasiOleh",
        'investigasiQrCodeId', c."InvestigasiQrCodeId",
        'tanggalInvestigasi', c."TanggalInvestigasi",
        'reviewOleh', c."ReviewOleh",
        'reviewQrCodeId', c."ReviewQrCodeId",
        'tanggalReview', c."TanggalReview",
        'catatanReview', c."CatatanReview",
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
