-- =====================================================================================
-- HSSE-Fusion4 — MIGRASI #9: DEPT SEKARANG DIAMBIL DARI FUSION4 (departemenTbl), BUKAN
-- tabel deptTbl lokal lagi -- biar penamaan Dept seragam sama data Divisi/Departemen
-- di Fusion4.
-- Jalankan SETELAH 001-008, di Supabase project HSSE-Fusion4.
--
-- PRASYARAT: jalankan dulu sql/for-FUSION4_departemen_master.sql di project FUSION4
-- (nhmpwjriextmbotmvvbu.supabase.co) -- migrasi INI baru bisa dipakai kalau
-- get_departemen_list() di Fusion4 udah ada.
--
-- Kenapa AssignedDeptId (FK) diganti nyimpen NAMA langsung: deptTbl yang lama itu
-- tabel LOKAL di project HSSE-Fusion4, jadi bisa di-FK (BIGINT REFERENCES). Begitu
-- master-nya dipindah ke departemenTbl di project FUSION4 (beda database sama
-- sekali), FK gak bisa lagi nyebrang project. Solusinya sama kayak field2 lain yang
-- udah dari awal nyimpen nama orang langsung (VerifikatorOleh, FollowupOleh, dst):
-- cermatTbl nyimpen "AssignedDivisi" + "AssignedDeptNama" sebagai teks, bukan ID.
-- =====================================================================================

ALTER TABLE "cermatTbl"
    DROP COLUMN IF EXISTS "AssignedDeptId",
    ADD COLUMN IF NOT EXISTS "AssignedDivisi" TEXT,
    ADD COLUMN IF NOT EXISTS "AssignedDeptNama" TEXT;

-- deptTbl lokal & get_departments() udah gak dipakai lagi -- digantikan
-- get_departemen_list() di Fusion4 (dipanggil client langsung pakai fusion4Client,
-- gak lewat RPC HSSE-Fusion4 lagi).
DROP FUNCTION IF EXISTS get_departments();
DROP TABLE IF EXISTS "deptTbl";


-- -------------------------------------------------------------------------------------
-- RPC: HSE ADMIN VERIFIKASI & ASSIGN KE DEPT (Open -> In Progress) -- versi baru,
-- pakai nama Dept + Divisi langsung (bukan ID lokal lagi).
-- -------------------------------------------------------------------------------------
DROP FUNCTION IF EXISTS cermat_assign_to_dept(BIGINT, BIGINT, TEXT, TEXT);
CREATE OR REPLACE FUNCTION cermat_assign_to_dept(
    p_id BIGINT,
    p_dept_nama TEXT,
    p_divisi TEXT DEFAULT NULL,
    p_verifikator_nama TEXT DEFAULT NULL,
    p_verifikator_qrcode TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    UPDATE "cermatTbl"
    SET "AssignedDeptNama" = p_dept_nama,
        "AssignedDivisi" = p_divisi,
        "VerifikatorOleh" = p_verifikator_nama,
        "VerifikatorQrCodeId" = p_verifikator_qrcode,
        "TanggalVerifikasi" = NOW(),
        "Status" = 'In Progress'
    WHERE "Id" = p_id;

    RETURN jsonb_build_object('success', true);
END;
$$;


-- -------------------------------------------------------------------------------------
-- RPC: get_cermat_reports & get_cermat_report_by_id -- assignedDeptNama/assignedDivisi
-- sekarang langsung dari kolom cermatTbl (gak ada JOIN ke deptTbl lokal lagi).
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
        'assignedDivisi', c."AssignedDivisi",
        'assignedDeptNama', c."AssignedDeptNama",
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
        'assignedDivisi', c."AssignedDivisi",
        'assignedDeptNama', c."AssignedDeptNama",
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
    WHERE c."Id" = p_id;

    RETURN v_result;
END;
$$;
