-- =====================================================================================
-- HSSE-Fusion4 — MIGRASI #6: APPROVAL DIGITAL "DIPERIKSA OLEH (HSSE)" & "DISETUJUI OLEH"
-- Jalankan SETELAH 001-005, di Supabase project HSSE-Fusion4 yang sama.
--
-- Konsep: pas status laporan CERMAT diubah ke "In Progress", HSSE Officer/Supervisor
-- yang berwenang (author "Review Cermat" di data karyawan Fusion4) verifikasi diri via
-- scan wajah (mobile) atau input PIN (desktop) -- ini jadi "Diperiksa Oleh". Pas diubah
-- ke "Closed", yang berwenang (author "Approve Cermat") verifikasi diri jadi "Disetujui
-- Oleh". Verifikasi wajah/PIN & cek author-nya dilakukan CLIENT-SIDE lewat data yang
-- udah dibalikin get_all_face_data() punya Fusion4 (read-only, gak ada perubahan di
-- Fusion4 -- field digitalPin & author di situ udah ada duluan).
-- =====================================================================================

ALTER TABLE "cermatTbl"
    ADD COLUMN IF NOT EXISTS "DiperiksaOleh" TEXT,
    ADD COLUMN IF NOT EXISTS "DiperiksaQrCodeId" TEXT,
    ADD COLUMN IF NOT EXISTS "TanggalDiperiksa" TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS "DisetujuiOleh" TEXT,
    ADD COLUMN IF NOT EXISTS "DisetujuiQrCodeId" TEXT,
    ADD COLUMN IF NOT EXISTS "TanggalDisetujui" TIMESTAMPTZ;


-- -------------------------------------------------------------------------------------
-- RPC: UPDATE STATUS -- versi baru, nambah 4 parameter approval.
-- Konvensi NULL vs '' vs isi buat p_diperiksa_oleh/p_disetujui_oleh:
--   NULL (default, gak dikirim)  -> JANGAN diubah, biarin apa adanya (dipakai pas edit
--                                   biasa yang gak nyentuh approval).
--   ''  (string kosong)          -> HAPUS/reset (dipakai pas reopen laporan).
--   isi (nama hasil verifikasi)  -> SET nilai baru + catat TanggalDiperiksa/Disetujui = NOW().
-- Ini biar timestamp approval gak ke-reset ke "sekarang" tiap kali form di-save ulang
-- padahal verifikasinya udah dari kunjungan sebelumnya.
-- -------------------------------------------------------------------------------------
DROP FUNCTION IF EXISTS update_cermat_status(BIGINT, TEXT, TEXT, DATE, TEXT, JSONB);
DROP FUNCTION IF EXISTS update_cermat_status(BIGINT, TEXT, TEXT, DATE, TEXT, JSONB, TEXT, TEXT, TEXT, TEXT);
CREATE OR REPLACE FUNCTION update_cermat_status(
    p_id BIGINT,
    p_status TEXT,
    p_penanggung_jawab TEXT DEFAULT '',
    p_tenggat DATE DEFAULT NULL,
    p_catatan_closed TEXT DEFAULT '',
    p_foto_tambahan JSONB DEFAULT '[]'::jsonb,
    p_diperiksa_oleh TEXT DEFAULT NULL,
    p_diperiksa_qrcode TEXT DEFAULT NULL,
    p_disetujui_oleh TEXT DEFAULT NULL,
    p_disetujui_qrcode TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    UPDATE "cermatTbl"
    SET "Status" = p_status,
        "PenanggungJawab" = p_penanggung_jawab,
        "Tenggat" = p_tenggat,
        "CatatanClosed" = p_catatan_closed,
        "TanggalClosed" = CASE WHEN p_status = 'Closed' THEN NOW() ELSE NULL END,
        "FotoTindakLanjutList" = "FotoTindakLanjutList" || COALESCE(p_foto_tambahan, '[]'::jsonb),

        "DiperiksaOleh" = CASE WHEN p_diperiksa_oleh IS NULL THEN "DiperiksaOleh"
                               WHEN p_diperiksa_oleh = '' THEN NULL
                               ELSE p_diperiksa_oleh END,
        "DiperiksaQrCodeId" = CASE WHEN p_diperiksa_oleh IS NULL THEN "DiperiksaQrCodeId"
                                   WHEN p_diperiksa_oleh = '' THEN NULL
                                   ELSE p_diperiksa_qrcode END,
        "TanggalDiperiksa" = CASE WHEN p_diperiksa_oleh IS NULL THEN "TanggalDiperiksa"
                                  WHEN p_diperiksa_oleh = '' THEN NULL
                                  ELSE NOW() END,

        "DisetujuiOleh" = CASE WHEN p_disetujui_oleh IS NULL THEN "DisetujuiOleh"
                               WHEN p_disetujui_oleh = '' THEN NULL
                               ELSE p_disetujui_oleh END,
        "DisetujuiQrCodeId" = CASE WHEN p_disetujui_oleh IS NULL THEN "DisetujuiQrCodeId"
                                   WHEN p_disetujui_oleh = '' THEN NULL
                                   ELSE p_disetujui_qrcode END,
        "TanggalDisetujui" = CASE WHEN p_disetujui_oleh IS NULL THEN "TanggalDisetujui"
                                  WHEN p_disetujui_oleh = '' THEN NULL
                                  ELSE NOW() END
    WHERE "Id" = p_id;

    RETURN jsonb_build_object('success', true);
END;
$$;


-- -------------------------------------------------------------------------------------
-- RPC: get_cermat_reports -- tambah field approval di response.
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
        'catatanClosed', c."CatatanClosed",
        'diperiksaOleh', c."DiperiksaOleh",
        'diperiksaQrCodeId', c."DiperiksaQrCodeId",
        'tanggalDiperiksa', c."TanggalDiperiksa",
        'disetujuiOleh', c."DisetujuiOleh",
        'disetujuiQrCodeId', c."DisetujuiQrCodeId",
        'tanggalDisetujui', c."TanggalDisetujui",
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


-- -------------------------------------------------------------------------------------
-- RPC: get_cermat_report_by_id -- tambah field approval juga (dipakai cermat-pdf.html).
-- -------------------------------------------------------------------------------------
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
        'diperiksaOleh', c."DiperiksaOleh",
        'diperiksaQrCodeId', c."DiperiksaQrCodeId",
        'tanggalDiperiksa', c."TanggalDiperiksa",
        'disetujuiOleh', c."DisetujuiOleh",
        'disetujuiQrCodeId', c."DisetujuiQrCodeId",
        'tanggalDisetujui', c."TanggalDisetujui",
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
