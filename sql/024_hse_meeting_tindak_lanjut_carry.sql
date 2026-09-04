-- =====================================================================================
-- HSSE-Fusion4 — MIGRASI #24: TINDAK LANJUT (ACTION ITEM) OTOMATIS LANJUT ANTAR RAPAT
-- Jalankan SETELAH 023, di Supabase project HSSE-Fusion4.
--
-- Aturan yang disepakati di chat:
-- 1. Tindak Lanjut berstatus "Open" di rapat manapun (Weekly/Monthly) otomatis ikut
--    muncul lagi di rapat BERIKUTNYA milik project yang sama -- baik itu Weekly
--    maupun Monthly -- terus sampai statusnya diubah jadi "Selesai".
-- 2. Tindak Lanjut yang baru aja ditandai "Selesai" masih muncul SEKALI lagi di
--    rapat berikutnya (buat konfirmasi/arsip), setelah itu gak dimunculin lagi.
--
-- Caranya: tiap item Tindak Lanjut dikasih "id" (dibikin di browser, dipertahankan
-- tiap kali item itu kebawa ke rapat berikutnya) + "closedCarryCount" (penanda udah
-- berapa kali item yang statusnya Selesai itu ikut nampang lagi di rapat sesudahnya).
-- Karena tiap rapat baru selalu ambil-alih (carry) semua item Open dari rapat
-- sebelumnya, cukup liat TindakLanjutList dari SATU rapat terakhir (paling baru,
-- gak peduli Weekly/Monthly) yang statusnya udah Selesai di project yang sama --
-- gak perlu scan seluruh histori.
-- =====================================================================================

DROP FUNCTION IF EXISTS get_carried_tindak_lanjut(BIGINT);
CREATE OR REPLACE FUNCTION get_carried_tindak_lanjut(p_project_id BIGINT)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_last_list JSONB;
BEGIN
    -- Ambil TindakLanjutList dari rapat TERAKHIR (paling baru berdasarkan tanggal
    -- rapat) yang udah Selesai, di project yang sama -- gak peduli Tipe Meeting-nya.
    SELECT "TindakLanjutList" INTO v_last_list
    FROM "hseMeetingTbl"
    WHERE "ProjectId" = p_project_id AND "Status" = 'Selesai'
    ORDER BY "TanggalRapat" DESC
    LIMIT 1;

    IF v_last_list IS NULL THEN
        RETURN '[]'::jsonb;
    END IF;

    RETURN COALESCE((
        SELECT jsonb_agg(
            CASE
                -- Item yang statusnya Selesai & baru pertama kali dibawa (closedCarryCount
                -- masih kosong/0) -> dibawa 1x lagi, tandanya dinaikin jadi 1 biar rapat
                -- SESUDAHNYA berhenti nampilin item ini lagi.
                WHEN item->>'status' = 'Selesai'
                    THEN item || jsonb_build_object('closedCarryCount', 1, 'carried', true)
                -- Item Open selalu dibawa apa adanya.
                ELSE item || jsonb_build_object('carried', true)
            END
        )
        FROM jsonb_array_elements(v_last_list) item
        WHERE item->>'status' = 'Open'
           OR (item->>'status' = 'Selesai' AND COALESCE((item->>'closedCarryCount')::int, 0) = 0)
    ), '[]'::jsonb);
END;
$$;


-- -------------------------------------------------------------------------------------
-- Tambah "projectId" ke get_hse_meeting_by_id -- dipakai klien buat tau project dari
-- rapat yang lagi di-resume (?resume=<id>), soalnya carry-forward Tindak Lanjut di
-- atas butuh p_project_id, dan pas resume gak ada dropdown project yang keisi.
-- -------------------------------------------------------------------------------------
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
        'projectId', c."ProjectId",
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
