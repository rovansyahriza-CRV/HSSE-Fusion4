-- =====================================================================================
-- HSSE-Fusion4 — MIGRASI #11: Lesson Learned di tahap Review (Incident/Accident)
-- Jalankan SETELAH 001-010, di Supabase project HSSE-Fusion4.
--
-- Reviewer (Author "Review Incident/Accident") baca hasil investigasi, lalu WAJIB isi
-- "Lesson Learned" (pelajaran yang bisa diambil dari insiden ini) sebelum status bisa
-- pindah dari Investigasi -> Review. Ini gantiin "Catatan Review" yang sebelumnya
-- opsional di migrasi 010 -- kalau kamu udah sempat jalanin 010, kolom lama otomatis
-- di-rename (data yang udah keisi gak hilang); kalau belum, kolom baru langsung dibikin.
-- Aman dijalankan ulang.
-- =====================================================================================

DO $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_name = 'incidentTbl' AND column_name = 'CatatanReview'
    ) THEN
        ALTER TABLE "incidentTbl" RENAME COLUMN "CatatanReview" TO "LessonLearned";
    ELSIF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_name = 'incidentTbl' AND column_name = 'LessonLearned'
    ) THEN
        ALTER TABLE "incidentTbl" ADD COLUMN "LessonLearned" TEXT;
    END IF;
END $$;


-- -------------------------------------------------------------------------------------
-- RPC: PORTAL REVIEW (Investigasi -> Review) -- Lesson Learned sekarang WAJIB diisi.
-- -------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION incident_submit_review(
    p_id BIGINT,
    p_lesson_learned TEXT DEFAULT '',
    p_nama TEXT DEFAULT NULL,
    p_qrcode TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    IF p_lesson_learned IS NULL OR TRIM(p_lesson_learned) = '' THEN
        RAISE EXCEPTION 'Lesson Learned wajib diisi sebelum kirim ke Review.';
    END IF;

    UPDATE "incidentTbl"
    SET "Status" = 'Review',
        "LessonLearned" = p_lesson_learned,
        "ReviewOleh" = p_nama,
        "ReviewQrCodeId" = p_qrcode,
        "TanggalReview" = NOW(),
        "CatatanPenolakan" = NULL
    WHERE "Id" = p_id;

    RETURN jsonb_build_object('success', true);
END;
$$;


-- -------------------------------------------------------------------------------------
-- RPC: PORTAL APPROVAL -- reject sekarang bersihin LessonLearned juga (harus diulang
-- dari portal Review lagi setelah investigator submit ulang).
-- -------------------------------------------------------------------------------------
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
            "LessonLearned" = NULL
        WHERE "Id" = p_id;
    END IF;

    RETURN jsonb_build_object('success', true);
END;
$$;


-- -------------------------------------------------------------------------------------
-- RPC: REOPEN (Closed -> Open) -- bersihin LessonLearned juga.
-- -------------------------------------------------------------------------------------
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
        "LessonLearned" = NULL,
        "CatatanPenolakan" = NULL
    WHERE "Id" = p_id;

    RETURN jsonb_build_object('success', true);
END;
$$;


-- -------------------------------------------------------------------------------------
-- RPC: get_incident_reports -- 'catatanReview' diganti 'lessonLearned'.
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
