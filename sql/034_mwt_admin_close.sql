-- =====================================================================================
-- HSSE-Fusion4 -- MIGRASI #34: MWT -- ADMIN MWT BISA TUTUP PAKSA SESI
-- Jalankan SETELAH sql/033_mwt_schema.sql, di Supabase project HSSE-Fusion4 (BUKAN Fusion4).
--
-- Latar belakang: sql/033 cuma kasih 1 cara nutup sesi MWT -- peserta (Author
-- "Management Walkthrough") centang "Tandai Selesai" pas submit kunjungannya sendiri.
-- User minta tambahan: Admin MWT (yang bikin jadwalnya, Author "Admin MWT") juga bisa
-- nutup paksa sesi langsung dari Riwayat MWT, buat jaga-jaga kalau gak ada peserta yang
-- nutup manual. DUA-DUANYA JALAN BARENG -- gak saling gantiin, gak ada yang dihapus.
--
-- Tambahan lain di migrasi ini: dicatat SIAPA yang nutup sesi (nama + QrCodeId) di kolom
-- baru DitutupOlehNama/DitutupOlehQrCodeId -- baik ditutup sendiri sama salah satu
-- peserta (lewat submit_mwt_kunjungan p_tandai_selesai=true) ataupun ditutup paksa sama
-- Admin MWT (lewat close_mwt_session baru) -- biar keliatan di riwayat siapa yang nutup.
-- =====================================================================================

ALTER TABLE "mwtTbl" ADD COLUMN IF NOT EXISTS "DitutupOlehNama" TEXT;
ALTER TABLE "mwtTbl" ADD COLUMN IF NOT EXISTS "DitutupOlehQrCodeId" TEXT DEFAULT '';

-- -------------------------------------------------------------------------------------
-- 1. submit_mwt_kunjungan -- signature SAMA PERSIS kayak sql/033, cuma nambah catat
--    DitutupOlehNama/QrCodeId pas peserta sendiri yang tandai selesai.
-- -------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION submit_mwt_kunjungan(
    p_id BIGINT,
    p_management_nama TEXT,
    p_management_qrcode TEXT,
    p_jumlah_pekerja_diskusi INT,
    p_catatan_observasi TEXT,
    p_pendamping_list JSONB DEFAULT '[]'::jsonb,
    p_foto_list JSONB DEFAULT '[]'::jsonb,
    p_tandai_selesai BOOLEAN DEFAULT false
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_status TEXT;
    v_new_entry JSONB;
    v_jumlah_entry INT;
BEGIN
    SELECT "Status" INTO v_status FROM "mwtTbl" WHERE "Id" = p_id;
    IF v_status IS NULL THEN
        RETURN jsonb_build_object('success', false, 'message', 'Jadwal MWT tidak ditemukan.');
    END IF;
    IF v_status = 'Selesai' THEN
        RETURN jsonb_build_object('success', false, 'message', 'Sesi MWT ini sudah Selesai, tidak bisa ditambah kunjungan lagi.');
    END IF;

    v_new_entry := jsonb_build_object(
        'managementNama', p_management_nama,
        'managementQrCodeId', p_management_qrcode,
        'tanggalKunjungan', to_jsonb(NOW()),
        'jumlahPekerjaDiskusi', COALESCE(p_jumlah_pekerja_diskusi, 0),
        'catatanObservasi', COALESCE(p_catatan_observasi, ''),
        'pendampingList', COALESCE(p_pendamping_list, '[]'::jsonb),
        'fotoList', COALESCE(p_foto_list, '[]'::jsonb)
    );

    UPDATE "mwtTbl"
    SET "KunjunganList" = "KunjunganList" || jsonb_build_array(v_new_entry),
        "Status" = CASE WHEN p_tandai_selesai THEN 'Selesai' ELSE 'Berlangsung' END,
        "TanggalDitutup" = CASE WHEN p_tandai_selesai THEN NOW() ELSE "TanggalDitutup" END,
        "DitutupOlehNama" = CASE WHEN p_tandai_selesai THEN p_management_nama ELSE "DitutupOlehNama" END,
        "DitutupOlehQrCodeId" = CASE WHEN p_tandai_selesai THEN p_management_qrcode ELSE "DitutupOlehQrCodeId" END
    WHERE "Id" = p_id
    RETURNING jsonb_array_length("KunjunganList") INTO v_jumlah_entry;

    RETURN jsonb_build_object('success', true, 'jumlahKunjungan', v_jumlah_entry, 'status', CASE WHEN p_tandai_selesai THEN 'Selesai' ELSE 'Berlangsung' END);
END;
$$;

-- -------------------------------------------------------------------------------------
-- 2. close_mwt_session -- BARU. Tutup paksa sesi, khusus Author "Admin MWT" (dicek di
--    client sebelum manggil ini, sama pola Author-gated lainnya). Gak butuh kunjungan
--    minimal 1 dulu -- Admin bisa nutup sesi yang bahkan belum ada kunjungan sama sekali
--    (misal jadwal batal/gak jadi jalan).
-- -------------------------------------------------------------------------------------
DROP FUNCTION IF EXISTS close_mwt_session(BIGINT, TEXT, TEXT);
CREATE OR REPLACE FUNCTION close_mwt_session(
    p_id BIGINT,
    p_admin_nama TEXT,
    p_admin_qrcode TEXT DEFAULT ''
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_status TEXT;
BEGIN
    SELECT "Status" INTO v_status FROM "mwtTbl" WHERE "Id" = p_id;
    IF v_status IS NULL THEN
        RETURN jsonb_build_object('success', false, 'message', 'Sesi MWT tidak ditemukan.');
    END IF;
    IF v_status = 'Selesai' THEN
        RETURN jsonb_build_object('success', false, 'message', 'Sesi MWT ini sudah Selesai sebelumnya.');
    END IF;

    UPDATE "mwtTbl"
    SET "Status" = 'Selesai',
        "TanggalDitutup" = NOW(),
        "DitutupOlehNama" = p_admin_nama,
        "DitutupOlehQrCodeId" = p_admin_qrcode
    WHERE "Id" = p_id;

    RETURN jsonb_build_object('success', true, 'status', 'Selesai');
END;
$$;

-- -------------------------------------------------------------------------------------
-- 3. get_mwt_list / get_mwt_by_id -- signature SAMA PERSIS, cuma nambah field
--    ditutupOlehNama/ditutupOlehQrCodeId di output JSON-nya.
-- -------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION get_mwt_list(p_status TEXT DEFAULT NULL, p_project_id BIGINT DEFAULT NULL)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_result JSONB;
BEGIN
    SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'id', c."Id",
        'noMWT', c."NoMWT",
        'areaRencana', c."AreaRencana",
        'tanggalRencana', c."TanggalRencana",
        'catatanRencana', c."CatatanRencana",
        'adminNama', c."AdminNama",
        'adminQrCodeId', c."AdminQrCodeId",
        'status', c."Status",
        'kunjunganList', c."KunjunganList",
        'tanggalDitutup', c."TanggalDitutup",
        'ditutupOlehNama', c."DitutupOlehNama",
        'ditutupOlehQrCodeId', c."DitutupOlehQrCodeId",
        'createdAt', c."CreatedAt",
        'namaProject', p."NamaProject",
        'noKontrak', p."NoKontrak"
    ) ORDER BY c."CreatedAt" DESC), '[]'::JSONB)
    INTO v_result
    FROM "mwtTbl" c
    JOIN "projectTbl" p ON p."Id" = c."ProjectId"
    WHERE (p_status IS NULL OR c."Status" = p_status)
      AND (p_project_id IS NULL OR c."ProjectId" = p_project_id);

    RETURN v_result;
END;
$$;

CREATE OR REPLACE FUNCTION get_mwt_by_id(p_id BIGINT)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_result JSONB;
BEGIN
    SELECT jsonb_build_object(
        'id', c."Id",
        'noMWT', c."NoMWT",
        'projectId', c."ProjectId",
        'areaRencana', c."AreaRencana",
        'tanggalRencana', c."TanggalRencana",
        'catatanRencana', c."CatatanRencana",
        'adminNama', c."AdminNama",
        'adminQrCodeId', c."AdminQrCodeId",
        'status', c."Status",
        'kunjunganList', c."KunjunganList",
        'tanggalDitutup', c."TanggalDitutup",
        'ditutupOlehNama', c."DitutupOlehNama",
        'ditutupOlehQrCodeId', c."DitutupOlehQrCodeId",
        'createdAt', c."CreatedAt",
        'namaProject', p."NamaProject",
        'noKontrak', p."NoKontrak",
        'tipeKonstruksi', p."TipeKonstruksi"
    )
    INTO v_result
    FROM "mwtTbl" c
    JOIN "projectTbl" p ON p."Id" = c."ProjectId"
    WHERE c."Id" = p_id;

    RETURN v_result;
END;
$$;
