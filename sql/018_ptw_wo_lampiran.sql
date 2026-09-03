-- =====================================================================================
-- HSSE-Fusion4 — MIGRASI #18: TAMBAH NO. WO & LAMPIRAN DOKUMEN PENDUKUNG DI PERMIT TO WORK
-- Jalankan SETELAH 001-017, di Supabase project HSSE-Fusion4.
--
-- Konsep (disepakati di chat):
-- 1. "WoNo" -- nomor Work Order dari sistem klien (Pertamina Hulu), opsional, biar
--    Permit to Work bisa dilacak balik ke WO aslinya.
-- 2. "LampiranList" -- dokumen pendukung (Surat WO, Prosedur Kerja/SOP, dst) yang bisa
--    berupa FOTO ATAU PDF, beda dari "FotoList" yang khusus dokumentasi kondisi lapangan.
--    Upload lewat uploadLampiranToDrive() (sudah ada di driveBridge.js sejak awal, belum
--    kepakai) -- file gak dikompres, nama file asli disimpan biar gampang dikenali.
-- =====================================================================================

ALTER TABLE "ptwTbl" ADD COLUMN IF NOT EXISTS "WoNo" TEXT DEFAULT '';
ALTER TABLE "ptwTbl" ADD COLUMN IF NOT EXISTS "LampiranList" JSONB NOT NULL DEFAULT '[]'::jsonb;
-- LampiranList isinya array [{fileId, url, fileName, mimeType}]


-- -------------------------------------------------------------------------------------
-- RE-CREATE submit_ptw() -- nambah p_wo_no & p_lampiran_list di AKHIR daftar parameter
-- (backward compatible, semua parameter lama tetap sama posisi & defaultnya).
-- -------------------------------------------------------------------------------------
DROP FUNCTION IF EXISTS submit_ptw(TEXT, BIGINT, TEXT, TEXT, TEXT, JSONB, JSONB, TEXT, TEXT, INT, TIMESTAMPTZ, TIMESTAMPTZ, JSONB);
CREATE OR REPLACE FUNCTION submit_ptw(
    p_jenis_pekerjaan TEXT,
    p_project_id BIGINT,
    p_nama_requester TEXT,
    p_lokasi_area TEXT,
    p_deskripsi_pekerjaan TEXT,
    p_jsa_items JSONB,
    p_hazard_checklist JSONB,
    p_requester_qrcode TEXT DEFAULT '',
    p_alat_yang_dipakai TEXT DEFAULT '',
    p_jumlah_pekerja INT DEFAULT NULL,
    p_tanggal_mulai TIMESTAMPTZ DEFAULT NULL,
    p_tanggal_selesai TIMESTAMPTZ DEFAULT NULL,
    p_foto_list JSONB DEFAULT '[]'::jsonb,
    p_wo_no TEXT DEFAULT '',
    p_lampiran_list JSONB DEFAULT '[]'::jsonb
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_no_permit TEXT := generate_no_ptw();
    v_id BIGINT;
BEGIN
    INSERT INTO "ptwTbl" (
        "NoPermit", "JenisPekerjaan", "ProjectId", "NamaRequester", "RequesterQrCodeId",
        "LokasiArea", "DeskripsiPekerjaan", "AlatYangDipakai", "JumlahPekerja",
        "TanggalMulaiKerja", "TanggalSelesaiKerja", "JsaItems", "HazardChecklist", "FotoList",
        "WoNo", "LampiranList"
    ) VALUES (
        v_no_permit, p_jenis_pekerjaan, p_project_id, p_nama_requester, p_requester_qrcode,
        p_lokasi_area, p_deskripsi_pekerjaan, p_alat_yang_dipakai, p_jumlah_pekerja,
        p_tanggal_mulai, p_tanggal_selesai, p_jsa_items, p_hazard_checklist, p_foto_list,
        p_wo_no, p_lampiran_list
    )
    RETURNING "Id" INTO v_id;

    RETURN jsonb_build_object('success', true, 'id', v_id, 'noPermit', v_no_permit);
END;
$$;


-- -------------------------------------------------------------------------------------
-- RE-CREATE get_ptw_list() & get_ptw_by_id() -- nambah field 'woNo' & 'lampiranList'.
-- -------------------------------------------------------------------------------------
DROP FUNCTION IF EXISTS get_ptw_list(TEXT);
CREATE OR REPLACE FUNCTION get_ptw_list(p_status TEXT DEFAULT NULL)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_result JSONB;
BEGIN
    SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'id', c."Id",
        'noPermit', c."NoPermit",
        'jenisPekerjaan', c."JenisPekerjaan",
        'tanggalWaktu', c."TanggalWaktu",
        'namaRequester', c."NamaRequester",
        'requesterQrCodeId', c."RequesterQrCodeId",
        'lokasiArea', c."LokasiArea",
        'deskripsiPekerjaan', c."DeskripsiPekerjaan",
        'alatYangDipakai', c."AlatYangDipakai",
        'jumlahPekerja', c."JumlahPekerja",
        'tanggalMulaiKerja', c."TanggalMulaiKerja",
        'tanggalSelesaiKerja', c."TanggalSelesaiKerja",
        'jsaItems', c."JsaItems",
        'hazardChecklist', c."HazardChecklist",
        'fotoList', c."FotoList",
        'woNo', c."WoNo",
        'lampiranList', c."LampiranList",
        'status', c."Status",
        'hseReviewOleh', c."HseReviewOleh",
        'hseReviewQrCodeId', c."HseReviewQrCodeId",
        'tanggalHseReview', c."TanggalHseReview",
        'areaAuthorityOleh', c."AreaAuthorityOleh",
        'areaAuthorityQrCodeId', c."AreaAuthorityQrCodeId",
        'tanggalAreaAuthority', c."TanggalAreaAuthority",
        'catatanPenolakan', c."CatatanPenolakan",
        'penutupanDiajukanOleh', c."PenutupanDiajukanOleh",
        'penutupanQrCodeId', c."PenutupanQrCodeId",
        'tanggalPenutupanDiajukan', c."TanggalPenutupanDiajukan",
        'catatanPenutupanDiajukan', c."CatatanPenutupanDiajukan",
        'ditutupOleh', c."DitutupOleh",
        'ditutupQrCodeId', c."DitutupQrCodeId",
        'tanggalDitutup', c."TanggalDitutup",
        'namaProject', p."NamaProject",
        'noKontrak', p."NoKontrak"
    ) ORDER BY c."TanggalWaktu" DESC), '[]'::JSONB)
    INTO v_result
    FROM "ptwTbl" c
    JOIN "projectTbl" p ON p."Id" = c."ProjectId"
    WHERE p_status IS NULL OR c."Status" = p_status;

    RETURN v_result;
END;
$$;


DROP FUNCTION IF EXISTS get_ptw_by_id(BIGINT);
CREATE OR REPLACE FUNCTION get_ptw_by_id(p_id BIGINT)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_result JSONB;
BEGIN
    SELECT jsonb_build_object(
        'id', c."Id",
        'noPermit', c."NoPermit",
        'jenisPekerjaan', c."JenisPekerjaan",
        'tanggalWaktu', c."TanggalWaktu",
        'namaRequester', c."NamaRequester",
        'requesterQrCodeId', c."RequesterQrCodeId",
        'lokasiArea', c."LokasiArea",
        'deskripsiPekerjaan', c."DeskripsiPekerjaan",
        'alatYangDipakai', c."AlatYangDipakai",
        'jumlahPekerja', c."JumlahPekerja",
        'tanggalMulaiKerja', c."TanggalMulaiKerja",
        'tanggalSelesaiKerja', c."TanggalSelesaiKerja",
        'jsaItems', c."JsaItems",
        'hazardChecklist', c."HazardChecklist",
        'fotoList', c."FotoList",
        'woNo', c."WoNo",
        'lampiranList', c."LampiranList",
        'status', c."Status",
        'hseReviewOleh', c."HseReviewOleh",
        'hseReviewQrCodeId', c."HseReviewQrCodeId",
        'tanggalHseReview', c."TanggalHseReview",
        'areaAuthorityOleh', c."AreaAuthorityOleh",
        'areaAuthorityQrCodeId', c."AreaAuthorityQrCodeId",
        'tanggalAreaAuthority', c."TanggalAreaAuthority",
        'catatanPenolakan', c."CatatanPenolakan",
        'penutupanDiajukanOleh', c."PenutupanDiajukanOleh",
        'penutupanQrCodeId', c."PenutupanQrCodeId",
        'tanggalPenutupanDiajukan', c."TanggalPenutupanDiajukan",
        'catatanPenutupanDiajukan', c."CatatanPenutupanDiajukan",
        'ditutupOleh', c."DitutupOleh",
        'ditutupQrCodeId', c."DitutupQrCodeId",
        'tanggalDitutup', c."TanggalDitutup",
        'namaProject', p."NamaProject",
        'noKontrak', p."NoKontrak",
        'tipeKonstruksi', p."TipeKonstruksi"
    )
    INTO v_result
    FROM "ptwTbl" c
    JOIN "projectTbl" p ON p."Id" = c."ProjectId"
    WHERE c."Id" = p_id;

    RETURN v_result;
END;
$$;
