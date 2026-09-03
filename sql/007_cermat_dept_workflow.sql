-- =====================================================================================
-- HSSE-Fusion4 — MIGRASI #7: ALUR VERIFIKASI HSE -> ASSIGN DEPT -> FOLLOWUP -> REVIEW -> CLOSE
-- Jalankan SETELAH 001-006, di Supabase project HSSE-Fusion4 yang sama.
--
-- GANTI TOTAL alur approval "Diperiksa Oleh (HSSE)/Disetujui Oleh" dari migrasi 006 --
-- itu digantikan alur ini:
--
--   Open --(HSE Admin, Author "Verifikasi Cermat", pilih Dept)--> In Progress
--   In Progress --(Admin Dept terkait, Author "<NamaDept> Admin", isi foto+catatan)--> Review
--   Review --(HSE Admin, Author "Verifikasi Cermat")--> Closed (approve)
--                                                     \-> In Progress (kirim balik/reject)
--   Closed --(HSE Admin, Author "Verifikasi Cermat", reopen)--> In Progress (dept sama)
--
-- Semua verifikasi identitas (scan wajah/PIN) & cek Author tetap dilakukan di client
-- (cermat-list.html), sama kayak sebelumnya -- RPC di sini cuma nyimpen SIAPA (nama +
-- QrCodeId) yang udah lolos cek Author itu, dikirim dari client.
-- =====================================================================================

-- Bersih-bersih kolom approval lama (migrasi 006) -- gak dipakai lagi di alur baru ini.
ALTER TABLE "cermatTbl"
    DROP COLUMN IF EXISTS "DiperiksaOleh",
    DROP COLUMN IF EXISTS "DiperiksaQrCodeId",
    DROP COLUMN IF EXISTS "TanggalDiperiksa",
    DROP COLUMN IF EXISTS "DisetujuiOleh",
    DROP COLUMN IF EXISTS "DisetujuiQrCodeId",
    DROP COLUMN IF EXISTS "TanggalDisetujui";


-- -------------------------------------------------------------------------------------
-- 1. TABEL MASTER DEPARTEMEN
-- Dipakai buat dropdown assign di HSE Admin. Author di data karyawan Fusion4 harus
-- persis "<NamaDept> Admin" (pakai spasi) biar client bisa cocokin siapa yang berhak
-- jadi admin dept itu -- misal dept "Equipment" -> Author "Equipment Admin".
-- GANTI/tambah baris di bawah ini lewat Table Editor Supabase sesuai departemen asli.
-- -------------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS "deptTbl" (
    "Id" BIGSERIAL PRIMARY KEY,
    "NamaDept" TEXT NOT NULL UNIQUE,
    "Status" TEXT NOT NULL DEFAULT 'Aktif' CHECK ("Status" IN ('Aktif', 'Non-Aktif')),
    "CreatedAt" TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

INSERT INTO "deptTbl" ("NamaDept")
SELECT v.n FROM (VALUES ('Equipment - GANTI INI'), ('Electrical - GANTI INI')) AS v(n)
WHERE NOT EXISTS (SELECT 1 FROM "deptTbl");

DROP FUNCTION IF EXISTS get_departments();
CREATE OR REPLACE FUNCTION get_departments()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_result JSONB;
BEGIN
    SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'id', "Id",
        'namaDept', "NamaDept"
    ) ORDER BY "NamaDept"), '[]'::JSONB)
    INTO v_result
    FROM "deptTbl"
    WHERE "Status" = 'Aktif';

    RETURN v_result;
END;
$$;


-- -------------------------------------------------------------------------------------
-- 2. KOLOM BARU DI cermatTbl BUAT ALUR VERIFIKASI -> DEPT -> FOLLOWUP -> REVIEW
-- -------------------------------------------------------------------------------------
ALTER TABLE "cermatTbl"
    ADD COLUMN IF NOT EXISTS "AssignedDeptId" BIGINT REFERENCES "deptTbl"("Id"),
    ADD COLUMN IF NOT EXISTS "VerifikatorOleh" TEXT,
    ADD COLUMN IF NOT EXISTS "VerifikatorQrCodeId" TEXT,
    ADD COLUMN IF NOT EXISTS "TanggalVerifikasi" TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS "FollowupOleh" TEXT,
    ADD COLUMN IF NOT EXISTS "FollowupQrCodeId" TEXT,
    ADD COLUMN IF NOT EXISTS "TanggalFollowup" TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS "CatatanFollowup" TEXT,
    ADD COLUMN IF NOT EXISTS "CatatanPenolakan" TEXT,
    ADD COLUMN IF NOT EXISTS "DitutupOleh" TEXT,
    ADD COLUMN IF NOT EXISTS "DitutupQrCodeId" TEXT;

-- Status sekarang 4 tahap: Open -> In Progress -> Review -> Closed (+ reject kembali ke
-- In Progress, + reopen dari Closed kembali ke In Progress).
ALTER TABLE "cermatTbl" DROP CONSTRAINT IF EXISTS "cermatTbl_Status_check";
ALTER TABLE "cermatTbl" ADD CONSTRAINT "cermatTbl_Status_check"
    CHECK ("Status" IN ('Open', 'In Progress', 'Review', 'Closed'));


-- -------------------------------------------------------------------------------------
-- 3. RPC: HSE ADMIN VERIFIKASI & ASSIGN KE DEPT (Open -> In Progress)
-- -------------------------------------------------------------------------------------
DROP FUNCTION IF EXISTS cermat_assign_to_dept(BIGINT, BIGINT, TEXT, TEXT);
CREATE OR REPLACE FUNCTION cermat_assign_to_dept(
    p_id BIGINT,
    p_dept_id BIGINT,
    p_verifikator_nama TEXT,
    p_verifikator_qrcode TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    UPDATE "cermatTbl"
    SET "AssignedDeptId" = p_dept_id,
        "VerifikatorOleh" = p_verifikator_nama,
        "VerifikatorQrCodeId" = p_verifikator_qrcode,
        "TanggalVerifikasi" = NOW(),
        "Status" = 'In Progress'
    WHERE "Id" = p_id;

    RETURN jsonb_build_object('success', true);
END;
$$;


-- -------------------------------------------------------------------------------------
-- 4. RPC: DEPT ADMIN SUBMIT FOLLOWUP (In Progress -> Review)
-- -------------------------------------------------------------------------------------
DROP FUNCTION IF EXISTS cermat_submit_followup(BIGINT, TEXT, JSONB, TEXT, DATE, TEXT, TEXT);
CREATE OR REPLACE FUNCTION cermat_submit_followup(
    p_id BIGINT,
    p_catatan_followup TEXT,
    p_foto_tambahan JSONB DEFAULT '[]'::jsonb,
    p_penanggung_jawab TEXT DEFAULT '',
    p_tenggat DATE DEFAULT NULL,
    p_followup_nama TEXT DEFAULT NULL,
    p_followup_qrcode TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    UPDATE "cermatTbl"
    SET "CatatanFollowup" = p_catatan_followup,
        "FotoTindakLanjutList" = "FotoTindakLanjutList" || COALESCE(p_foto_tambahan, '[]'::jsonb),
        "PenanggungJawab" = p_penanggung_jawab,
        "Tenggat" = p_tenggat,
        "FollowupOleh" = p_followup_nama,
        "FollowupQrCodeId" = p_followup_qrcode,
        "TanggalFollowup" = NOW(),
        "CatatanPenolakan" = NULL,
        "Status" = 'Review'
    WHERE "Id" = p_id;

    RETURN jsonb_build_object('success', true);
END;
$$;


-- -------------------------------------------------------------------------------------
-- 5. RPC: HSE ADMIN REVIEW HASIL FOLLOWUP -- approve (Closed) atau reject (balik In Progress)
-- -------------------------------------------------------------------------------------
DROP FUNCTION IF EXISTS cermat_review_decision(BIGINT, TEXT, TEXT, TEXT, TEXT);
CREATE OR REPLACE FUNCTION cermat_review_decision(
    p_id BIGINT,
    p_decision TEXT, -- 'approve' | 'reject'
    p_catatan_penolakan TEXT DEFAULT '',
    p_reviewer_nama TEXT DEFAULT NULL,
    p_reviewer_qrcode TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    IF p_decision = 'approve' THEN
        UPDATE "cermatTbl"
        SET "Status" = 'Closed',
            "TanggalClosed" = NOW(),
            "DitutupOleh" = p_reviewer_nama,
            "DitutupQrCodeId" = p_reviewer_qrcode,
            "CatatanPenolakan" = NULL
        WHERE "Id" = p_id;
    ELSE
        UPDATE "cermatTbl"
        SET "Status" = 'In Progress',
            "CatatanPenolakan" = p_catatan_penolakan
        WHERE "Id" = p_id;
    END IF;

    RETURN jsonb_build_object('success', true);
END;
$$;


-- -------------------------------------------------------------------------------------
-- 6. RPC: REOPEN (Closed -> In Progress, balik ke Dept yang sama)
-- -------------------------------------------------------------------------------------
DROP FUNCTION IF EXISTS cermat_reopen(BIGINT, TEXT, TEXT);
CREATE OR REPLACE FUNCTION cermat_reopen(
    p_id BIGINT,
    p_reopener_nama TEXT,
    p_reopener_qrcode TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    UPDATE "cermatTbl"
    SET "Status" = 'In Progress',
        "TanggalClosed" = NULL,
        "CatatanClosed" = '',
        "DitutupOleh" = NULL,
        "DitutupQrCodeId" = NULL,
        "VerifikatorOleh" = COALESCE("VerifikatorOleh", p_reopener_nama),
        "VerifikatorQrCodeId" = COALESCE("VerifikatorQrCodeId", p_reopener_qrcode)
    WHERE "Id" = p_id;

    RETURN jsonb_build_object('success', true);
END;
$$;


-- -------------------------------------------------------------------------------------
-- 7. RPC: get_cermat_reports & get_cermat_report_by_id -- field baru, hapus field lama
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
        'assignedDeptId', c."AssignedDeptId",
        'assignedDeptNama', d."NamaDept",
        'verifikatorOleh', c."VerifikatorOleh",
        'verifikatorQrCodeId', c."VerifikatorQrCodeId",
        'tanggalVerifikasi', c."TanggalVerifikasi",
        'followupOleh', c."FollowupOleh",
        'followupQrCodeId', c."FollowupQrCodeId",
        'tanggalFollowup', c."TanggalFollowup",
        'catatanFollowup', c."CatatanFollowup",
        'catatanPenolakan', c."CatatanPenolakan",
        'ditutupOleh', c."DitutupOleh",
        'ditutupQrCodeId', c."DitutupQrCodeId",
        'namaProject', p."NamaProject",
        'noKontrak', p."NoKontrak"
    ) ORDER BY c."TanggalWaktu" DESC), '[]'::JSONB)
    INTO v_result
    FROM "cermatTbl" c
    JOIN "projectTbl" p ON p."Id" = c."ProjectId"
    LEFT JOIN "deptTbl" d ON d."Id" = c."AssignedDeptId"
    WHERE p_status IS NULL OR c."Status" = p_status;

    RETURN v_result;
END;
$$;


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
        'assignedDeptId', c."AssignedDeptId",
        'assignedDeptNama', d."NamaDept",
        'verifikatorOleh', c."VerifikatorOleh",
        'verifikatorQrCodeId', c."VerifikatorQrCodeId",
        'tanggalVerifikasi', c."TanggalVerifikasi",
        'followupOleh', c."FollowupOleh",
        'followupQrCodeId', c."FollowupQrCodeId",
        'tanggalFollowup', c."TanggalFollowup",
        'catatanFollowup', c."CatatanFollowup",
        'catatanPenolakan', c."CatatanPenolakan",
        'ditutupOleh', c."DitutupOleh",
        'ditutupQrCodeId', c."DitutupQrCodeId",
        'namaProject', p."NamaProject",
        'noKontrak', p."NoKontrak",
        'tipeKonstruksi', p."TipeKonstruksi"
    )
    INTO v_result
    FROM "cermatTbl" c
    JOIN "projectTbl" p ON p."Id" = c."ProjectId"
    LEFT JOIN "deptTbl" d ON d."Id" = c."AssignedDeptId"
    WHERE c."Id" = p_id;

    RETURN v_result;
END;
$$;
