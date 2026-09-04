-- =====================================================================================
-- HSSE-Fusion4 — MIGRASI #23: SESI HSE MEETING + ABSEN MANDIRI VIA QR CODE
-- Jalankan SETELAH 022, di Supabase project HSSE-Fusion4.
--
-- Konsep (disepakati di chat):
-- 1. Leader (Author "Leader HSE Meeting") buka sesi dulu (Tipe Meeting, Project, Tanggal,
--    Lokasi) -> dapat No. Meeting, status "Berlangsung".
-- 2. Layar ditampilkan di TV/proyektor ruang meeting (hse-meeting-session.html) berisi
--    QR code -- peserta scan pakai HP sendiri (atau pinjam HP teman kalau gak bawa),
--    lalu verifikasi diri sendiri (Scan QR badge/Wajah/PIN) di hse-meeting-checkin.html.
--    Diverifikasi PER-ORANG, jadi biarpun pakai HP pinjaman tetap sah -- bukan device
--    yang diverifikasi, tapi identitas orangnya.
-- 3. Leader isi Agenda & Pembahasan, Tindak Lanjut, Catatan Tambahan, Foto Dokumentasi,
--    lalu "Selesaikan Notulen" -> status jadi "Selesai" -- setelah itu gak bisa absen lagi.
-- =====================================================================================


-- -------------------------------------------------------------------------------------
-- 1. KOLOM STATUS -- default 'Selesai' buat baris lama (kalau ada, dari migrasi 022
--    submit_hse_meeting yang submit langsung tanpa fase sesi).
-- -------------------------------------------------------------------------------------
ALTER TABLE "hseMeetingTbl" ADD COLUMN IF NOT EXISTS "Status" TEXT NOT NULL DEFAULT 'Selesai';

ALTER TABLE "hseMeetingTbl" DROP CONSTRAINT IF EXISTS hse_meeting_status_check;
ALTER TABLE "hseMeetingTbl" ADD CONSTRAINT hse_meeting_status_check CHECK ("Status" IN ('Berlangsung', 'Selesai'));

CREATE INDEX IF NOT EXISTS idx_hse_meeting_status ON "hseMeetingTbl" ("Status");


-- -------------------------------------------------------------------------------------
-- 2. RPC: BUKA SESI BARU (leader udah diverifikasi Author "Leader HSE Meeting" di
--    client sebelum manggil ini -- sama pola kayak tahap Author-gated lainnya).
-- -------------------------------------------------------------------------------------
DROP FUNCTION IF EXISTS start_hse_meeting_session(TEXT, BIGINT, TEXT, TEXT, TEXT, TIMESTAMPTZ);
CREATE OR REPLACE FUNCTION start_hse_meeting_session(
    p_tipe_meeting TEXT,
    p_project_id BIGINT,
    p_nama_pemimpin TEXT,
    p_pemimpin_qrcode TEXT DEFAULT '',
    p_lokasi_rapat TEXT DEFAULT '',
    p_tanggal_rapat TIMESTAMPTZ DEFAULT NULL
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
        "NamaPemimpin", "PemimpinQrCodeId", "Status"
    ) VALUES (
        v_no_meeting, p_tipe_meeting, p_project_id, COALESCE(p_tanggal_rapat, NOW()), p_lokasi_rapat,
        p_nama_pemimpin, p_pemimpin_qrcode, 'Berlangsung'
    )
    RETURNING "Id" INTO v_id;

    RETURN jsonb_build_object('success', true, 'id', v_id, 'noMeeting', v_no_meeting);
END;
$$;


-- -------------------------------------------------------------------------------------
-- 3. RPC: INFO RINGAN BUAT HALAMAN CHECK-IN PUBLIK (gak perlu Author, gak perlu data
--    lengkap kayak agenda/tindak lanjut -- cukup buat nampilin konteks + cek status).
-- -------------------------------------------------------------------------------------
DROP FUNCTION IF EXISTS get_hse_meeting_checkin_info(BIGINT);
CREATE OR REPLACE FUNCTION get_hse_meeting_checkin_info(p_id BIGINT)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_result JSONB;
BEGIN
    SELECT jsonb_build_object(
        'found', true,
        'id', c."Id",
        'noMeeting', c."NoMeeting",
        'tipeMeeting', c."TipeMeeting",
        'status', c."Status",
        'lokasiRapat', c."LokasiRapat",
        'tanggalRapat', c."TanggalRapat",
        'namaPemimpin', c."NamaPemimpin",
        'namaProject', p."NamaProject",
        'jumlahPeserta', jsonb_array_length(c."PesertaList")
    )
    INTO v_result
    FROM "hseMeetingTbl" c
    JOIN "projectTbl" p ON p."Id" = c."ProjectId"
    WHERE c."Id" = p_id;

    IF v_result IS NULL THEN
        RETURN jsonb_build_object('found', false);
    END IF;

    RETURN v_result;
END;
$$;


-- -------------------------------------------------------------------------------------
-- 4. RPC: CHECK-IN PESERTA (dipanggil dari hse-meeting-checkin.html, per orang, setelah
--    dia verifikasi diri sendiri lewat Scan QR badge/Wajah/PIN -- boleh pakai HP siapa
--    aja, yang penting identitas orangnya kevalidasi). Dedup by QrCodeId, sama pola
--    kayak tbm_scan_peserta().
-- -------------------------------------------------------------------------------------
DROP FUNCTION IF EXISTS checkin_hse_meeting(BIGINT, TEXT, TEXT, TEXT);
CREATE OR REPLACE FUNCTION checkin_hse_meeting(
    p_id BIGINT,
    p_nama TEXT,
    p_qrcode TEXT,
    p_jabatan TEXT DEFAULT ''
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_status TEXT;
    v_peserta JSONB;
    v_existing JSONB;
    v_new_entry JSONB;
    v_jumlah INT;
BEGIN
    SELECT "Status", "PesertaList" INTO v_status, v_peserta FROM "hseMeetingTbl" WHERE "Id" = p_id;

    IF v_status IS NULL THEN
        RETURN jsonb_build_object('success', false, 'message', 'Sesi HSE Meeting tidak ditemukan.');
    END IF;
    IF v_status <> 'Berlangsung' THEN
        RETURN jsonb_build_object('success', false, 'message', 'Sesi ini sudah Selesai, tidak bisa absen lagi.');
    END IF;

    SELECT elem INTO v_existing
    FROM jsonb_array_elements(v_peserta) elem
    WHERE elem->>'qrCodeId' = p_qrcode
    LIMIT 1;

    IF v_existing IS NOT NULL THEN
        RETURN jsonb_build_object(
            'success', false, 'duplicate', true,
            'nama', v_existing->>'nama', 'jamHadir', v_existing->>'jamHadir'
        );
    END IF;

    v_new_entry := jsonb_build_object('nama', p_nama, 'qrCodeId', p_qrcode, 'jabatan', p_jabatan, 'jamHadir', NOW());
    UPDATE "hseMeetingTbl"
    SET "PesertaList" = "PesertaList" || jsonb_build_array(v_new_entry)
    WHERE "Id" = p_id
    RETURNING jsonb_array_length("PesertaList") INTO v_jumlah;

    RETURN jsonb_build_object('success', true, 'jumlahPeserta', v_jumlah);
END;
$$;


-- -------------------------------------------------------------------------------------
-- 5. RPC: SELESAIKAN NOTULEN (Berlangsung -> Selesai). Leader isi Agenda, Tindak
--    Lanjut, Catatan Tambahan, Foto Dokumentasi -- Peserta udah otomatis kebentuk dari
--    hasil scan, gak perlu dikirim ulang di sini.
-- -------------------------------------------------------------------------------------
DROP FUNCTION IF EXISTS finalize_hse_meeting(BIGINT, JSONB, JSONB, TEXT, JSONB);
CREATE OR REPLACE FUNCTION finalize_hse_meeting(
    p_id BIGINT,
    p_agenda_list JSONB,
    p_tindak_lanjut_list JSONB,
    p_catatan_tambahan TEXT DEFAULT '',
    p_foto_list JSONB DEFAULT '[]'::jsonb
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_no_meeting TEXT;
BEGIN
    UPDATE "hseMeetingTbl"
    SET "AgendaList" = p_agenda_list,
        "TindakLanjutList" = p_tindak_lanjut_list,
        "CatatanTambahan" = p_catatan_tambahan,
        "FotoList" = COALESCE(p_foto_list, '[]'::jsonb),
        "Status" = 'Selesai'
    WHERE "Id" = p_id
    RETURNING "NoMeeting" INTO v_no_meeting;

    IF v_no_meeting IS NULL THEN
        RETURN jsonb_build_object('success', false, 'message', 'Sesi HSE Meeting tidak ditemukan.');
    END IF;

    RETURN jsonb_build_object('success', true, 'id', p_id, 'noMeeting', v_no_meeting);
END;
$$;


-- -------------------------------------------------------------------------------------
-- 6. UPDATE get_hse_meeting_list & get_hse_meeting_by_id -- tambah field "status" yang
--    kemarin ketinggalan di migrasi 022.
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
        'status', c."Status",
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
        'status', c."Status",
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
