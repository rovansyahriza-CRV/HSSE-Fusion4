-- =====================================================================================
-- HSSE-Fusion4 — MIGRASI #3: Reopen Laporan + Foto Tindak Lanjut/Bukti Perbaikan
-- Jalankan SETELAH 001 & 002, di Supabase project HSSE-Fusion4 yang sama.
--
-- Perubahan:
-- 1. Sekarang bisa nambahin foto tambahan pas update status (misal foto bukti udah
--    diperbaiki/ditindaklanjuti) -- terpisah dari foto temuan awal ("FotoList"), biar
--    jelas mana foto "sebelum" vs "sesudah" pas ditinjau audit. Disimpan di kolom baru
--    "FotoTindakLanjutList", dan foto baru DITAMBAHKAN ke yang lama (bukan menimpa),
--    jadi bisa nambah foto lagi tiap kali status diupdate.
-- 2. Laporan yang sudah "Closed" sekarang bisa "dibuka lagi" (reopen) kalau ternyata
--    keliru ditutup atau masalahnya muncul lagi -- lewat RPC yang sama (update_cermat_status),
--    cukup kirim status baru yang bukan "Closed".
-- =====================================================================================

ALTER TABLE "cermatTbl" ADD COLUMN IF NOT EXISTS "FotoTindakLanjutList" JSONB NOT NULL DEFAULT '[]'::jsonb;


-- -------------------------------------------------------------------------------------
-- RPC: UPDATE STATUS / TINDAK LANJUT -- tambah parameter p_foto_tambahan (JSONB array),
-- yang di-APPEND ke "FotoTindakLanjutList" yang sudah ada (bukan menimpa).
-- Signature lama (5 parameter) di-drop dulu.
-- -------------------------------------------------------------------------------------
DROP FUNCTION IF EXISTS update_cermat_status(BIGINT, TEXT, TEXT, DATE, TEXT);
CREATE OR REPLACE FUNCTION update_cermat_status(
    p_id BIGINT,
    p_status TEXT,
    p_penanggung_jawab TEXT DEFAULT '',
    p_tenggat DATE DEFAULT NULL,
    p_catatan_closed TEXT DEFAULT '',
    p_foto_tambahan JSONB DEFAULT '[]'::jsonb
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
        "FotoTindakLanjutList" = "FotoTindakLanjutList" || COALESCE(p_foto_tambahan, '[]'::jsonb)
    WHERE "Id" = p_id;

    RETURN jsonb_build_object('success', true);
END;
$$;


-- -------------------------------------------------------------------------------------
-- RPC: AMBIL DAFTAR LAPORAN -- tambah 'fotoTindakLanjutList' di hasilnya.
-- Signature (p_status TEXT) tidak berubah, cukup CREATE OR REPLACE.
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
        'fotoTindakLanjutList', c."FotoTindakLanjutList",
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
