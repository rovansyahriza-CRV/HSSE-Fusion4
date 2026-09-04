-- =====================================================================================
-- HSSE-Fusion4 — MIGRASI #22: MODUL HSE WEEKLY/MONTHLY MEETING
-- Jalankan SETELAH 001-021, di Supabase project HSSE-Fusion4.
--
-- Konsep (disepakati di chat):
-- 1. HSE Weekly Meeting & Monthly Meeting DIGABUNG jadi 1 modul -- ada kolom "TipeMeeting"
--    ('Mingguan' / 'Bulanan') buat bedain, 1 form & 1 Riwayat aja.
-- 2. Submit tunggal + Author-gate (Author "Leader HSE Meeting") -- gak ada alur approval
--    berjenjang kayak Permit to Work, sesuai pola Inspeksi/CERMAT/Incident.
-- 3. Isi rapat: Agenda (dinamis, bisa lebih dari 1 topik), Peserta (dinamis, nama+jabatan),
--    Tindak Lanjut/Action Item (dinamis, item+PIC+deadline+status), Catatan Tambahan,
--    Foto Dokumentasi.
-- =====================================================================================


-- -------------------------------------------------------------------------------------
-- 1. TABEL HSE MEETING
-- -------------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS "hseMeetingTbl" (
    "Id" BIGSERIAL PRIMARY KEY,
    "NoMeeting" TEXT UNIQUE NOT NULL,
    "TipeMeeting" TEXT NOT NULL CHECK ("TipeMeeting" IN ('Mingguan', 'Bulanan')),
    "ProjectId" BIGINT NOT NULL REFERENCES "projectTbl"("Id"),
    "TanggalRapat" TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    "LokasiRapat" TEXT DEFAULT '',
    "NamaPemimpin" TEXT NOT NULL,
    "PemimpinQrCodeId" TEXT DEFAULT '',
    "AgendaList" JSONB NOT NULL DEFAULT '[]'::jsonb, -- [{topik, pembahasan}]
    "PesertaList" JSONB NOT NULL DEFAULT '[]'::jsonb, -- [{nama, jabatan}]
    "TindakLanjutList" JSONB NOT NULL DEFAULT '[]'::jsonb, -- [{item, pic, deadline, status}]
    "CatatanTambahan" TEXT DEFAULT '',
    "FotoList" JSONB NOT NULL DEFAULT '[]'::jsonb,
    "CreatedAt" TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_hse_meeting_project ON "hseMeetingTbl" ("ProjectId");
CREATE INDEX IF NOT EXISTS idx_hse_meeting_tipe ON "hseMeetingTbl" ("TipeMeeting");


-- -------------------------------------------------------------------------------------
-- 2. RPC: GENERATE NOMOR MEETING
-- -------------------------------------------------------------------------------------
DROP FUNCTION IF EXISTS generate_no_hse_meeting(TEXT);
CREATE OR REPLACE FUNCTION generate_no_hse_meeting(p_tipe_meeting TEXT)
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_date_str TEXT := TO_CHAR(NOW() AT TIME ZONE 'Asia/Makassar', 'YYYYMMDD');
    v_rand TEXT := LPAD(FLOOR(RANDOM() * 9000 + 1000)::TEXT, 4, '0');
    v_kode TEXT := CASE WHEN p_tipe_meeting = 'Bulanan' THEN 'MTG-BLN' ELSE 'MTG-MGG' END;
BEGIN
    RETURN 'BIMA/' || v_kode || '/' || v_date_str || '-' || v_rand;
END;
$$;


-- -------------------------------------------------------------------------------------
-- 3. RPC: SUBMIT HSE MEETING
-- -------------------------------------------------------------------------------------
DROP FUNCTION IF EXISTS submit_hse_meeting(TEXT, BIGINT, TEXT, TEXT, JSONB, JSONB, JSONB, TEXT, TEXT, TEXT, TIMESTAMPTZ, JSONB);
CREATE OR REPLACE FUNCTION submit_hse_meeting(
    p_tipe_meeting TEXT,
    p_project_id BIGINT,
    p_nama_pemimpin TEXT,
    p_lokasi_rapat TEXT,
    p_agenda_list JSONB,
    p_peserta_list JSONB,
    p_tindak_lanjut_list JSONB,
    p_pemimpin_qrcode TEXT DEFAULT '',
    p_catatan_tambahan TEXT DEFAULT '',
    p_tanggal_rapat TIMESTAMPTZ DEFAULT NULL,
    p_foto_list JSONB DEFAULT '[]'::jsonb
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_no_meeting TEXT := generate_no_hse_meeting(p_tipe_meeting);
    v_id BIGINT;
BEGIN
    INSERT INTO "hseMeetingTbl" (
        "NoMeeting", "TipeMeeting", "ProjectId", "TanggalRapat", "LokasiRapat",
        "NamaPemimpin", "PemimpinQrCodeId", "AgendaList", "PesertaList",
        "TindakLanjutList", "CatatanTambahan", "FotoList"
    ) VALUES (
        v_no_meeting, p_tipe_meeting, p_project_id, COALESCE(p_tanggal_rapat, NOW()), p_lokasi_rapat,
        p_nama_pemimpin, p_pemimpin_qrcode, p_agenda_list, p_peserta_list,
        p_tindak_lanjut_list, p_catatan_tambahan, p_foto_list
    )
    RETURNING "Id" INTO v_id;

    RETURN jsonb_build_object('success', true, 'id', v_id, 'noMeeting', v_no_meeting);
END;
$$;


-- -------------------------------------------------------------------------------------
-- 4. RPC: AMBIL DAFTAR (RIWAYAT) & DETAIL BY ID
-- -------------------------------------------------------------------------------------
DROP FUNCTION IF EXISTS get_hse_meeting_list(TEXT);
CREATE OR REPLACE FUNCTION get_hse_meeting_list(p_tipe_meeting TEXT DEFAULT NULL)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_result JSONB;
BEGIN
    SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'id', c."Id",
        'noMeeting', c."NoMeeting",
        'tipeMeeting', c."TipeMeeting",
        'tanggalRapat', c."TanggalRapat",
        'lokasiRapat', c."LokasiRapat",
        'namaPemimpin', c."NamaPemimpin",
        'pemimpinQrCodeId', c."PemimpinQrCodeId",
        'agendaList', c."AgendaList",
        'pesertaList', c."PesertaList",
        'tindakLanjutList', c."TindakLanjutList",
        'catatanTambahan', c."CatatanTambahan",
        'fotoList', c."FotoList",
        'namaProject', p."NamaProject",
        'noKontrak', p."NoKontrak"
    ) ORDER BY c."TanggalRapat" DESC), '[]'::JSONB)
    INTO v_result
    FROM "hseMeetingTbl" c
    JOIN "projectTbl" p ON p."Id" = c."ProjectId"
    WHERE p_tipe_meeting IS NULL OR c."TipeMeeting" = p_tipe_meeting;

    RETURN v_result;
END;
$$;


DROP FUNCTION IF EXISTS get_hse_meeting_by_id(BIGINT);
CREATE OR REPLACE FUNCTION get_hse_meeting_by_id(p_id BIGINT)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_result JSONB;
BEGIN
    SELECT jsonb_build_object(
        'id', c."Id",
        'noMeeting', c."NoMeeting",
        'tipeMeeting', c."TipeMeeting",
        'tanggalRapat', c."TanggalRapat",
        'lokasiRapat', c."LokasiRapat",
        'namaPemimpin', c."NamaPemimpin",
        'pemimpinQrCodeId', c."PemimpinQrCodeId",
        'agendaList', c."AgendaList",
        'pesertaList', c."PesertaList",
        'tindakLanjutList', c."TindakLanjutList",
        'catatanTambahan', c."CatatanTambahan",
        'fotoList', c."FotoList",
        'namaProject', p."NamaProject",
        'noKontrak', p."NoKontrak",
        'tipeKonstruksi', p."TipeKonstruksi"
    )
    INTO v_result
    FROM "hseMeetingTbl" c
    JOIN "projectTbl" p ON p."Id" = c."ProjectId"
    WHERE c."Id" = p_id;

    RETURN v_result;
END;
$$;
