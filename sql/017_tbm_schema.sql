-- =====================================================================================
-- HSSE-Fusion4 — MIGRASI #17: MODUL TOOLBOX MEETING (TBM)
-- Jalankan SETELAH 001-016 (butuh ptwTbl dari migrasi 016 buat link opsional).
--
-- Konsep (disepakati di chat):
-- 1. Leader (harus punya Author "Leader Toolbox Meeting") bikin sesi dulu -> dapat
--    No. Sesi, status "Sedang Absen".
-- 2. Peserta scan wajah/QR SATU-SATU secara berurutan (mode kamera aktif terus) --
--    ke-scan dua kali di sesi yang sama = ditolak ("sudah absen jam segini"), gak dobel.
-- 3. Leader tekan "Selesai" kapan aja -> opsional tambah foto dokumentasi & catatan ->
--    status jadi "Selesai".
-- 4. Opsional link ke Permit to Work yang lagi Aktif (biar keliatan TBM ini buat
--    persiapan kerjaan yang mana).
-- =====================================================================================

CREATE TABLE IF NOT EXISTS "tbmTbl" (
    "Id" BIGSERIAL PRIMARY KEY,
    "NoSesi" TEXT UNIQUE NOT NULL,
    "ProjectId" BIGINT NOT NULL REFERENCES "projectTbl"("Id"),
    "LokasiArea" TEXT NOT NULL,
    "TopikBriefing" TEXT NOT NULL,
    "PermitId" BIGINT REFERENCES "ptwTbl"("Id"),
    "LeaderNama" TEXT NOT NULL,
    "LeaderQrCodeId" TEXT DEFAULT '',
    "TanggalMulai" TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    "Status" TEXT NOT NULL DEFAULT 'Sedang Absen' CHECK ("Status" IN ('Sedang Absen', 'Selesai')),
    "PesertaList" JSONB NOT NULL DEFAULT '[]'::jsonb, -- [{nama, qrCodeId, jamAbsen}]
    "CatatanPenutup" TEXT DEFAULT '',
    "FotoPenutupList" JSONB NOT NULL DEFAULT '[]'::jsonb,
    "TanggalSelesai" TIMESTAMPTZ,
    "CreatedAt" TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_tbm_project ON "tbmTbl" ("ProjectId");
CREATE INDEX IF NOT EXISTS idx_tbm_status ON "tbmTbl" ("Status");


-- -------------------------------------------------------------------------------------
-- RPC: GENERATE NOMOR SESI
-- -------------------------------------------------------------------------------------
DROP FUNCTION IF EXISTS generate_no_tbm();
CREATE OR REPLACE FUNCTION generate_no_tbm()
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_date_str TEXT := TO_CHAR(NOW() AT TIME ZONE 'Asia/Makassar', 'YYYYMMDD');
    v_rand TEXT := LPAD(FLOOR(RANDOM() * 9000 + 1000)::TEXT, 4, '0');
BEGIN
    RETURN 'BIMA/TBM/' || v_date_str || '-' || v_rand;
END;
$$;


-- -------------------------------------------------------------------------------------
-- RPC: MULAI SESI TBM BARU (leader udah diverifikasi Author "Leader Toolbox Meeting"
-- di client sebelum manggil ini -- sama pola kayak tahap Author-gated lainnya).
-- -------------------------------------------------------------------------------------
DROP FUNCTION IF EXISTS submit_tbm_session(BIGINT, TEXT, TEXT, TEXT, TEXT, BIGINT);
CREATE OR REPLACE FUNCTION submit_tbm_session(
    p_project_id BIGINT,
    p_lokasi_area TEXT,
    p_topik_briefing TEXT,
    p_leader_nama TEXT,
    p_leader_qrcode TEXT DEFAULT '',
    p_permit_id BIGINT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_no_sesi TEXT := generate_no_tbm();
    v_id BIGINT;
BEGIN
    INSERT INTO "tbmTbl" (
        "NoSesi", "ProjectId", "LokasiArea", "TopikBriefing", "PermitId", "LeaderNama", "LeaderQrCodeId"
    ) VALUES (
        v_no_sesi, p_project_id, p_lokasi_area, p_topik_briefing, p_permit_id, p_leader_nama, p_leader_qrcode
    )
    RETURNING "Id" INTO v_id;

    RETURN jsonb_build_object('success', true, 'id', v_id, 'noSesi', v_no_sesi);
END;
$$;


-- -------------------------------------------------------------------------------------
-- RPC: SCAN PESERTA (dipanggil berulang-ulang, satu per satu, selama sesi "Sedang
-- Absen"). Cek duplikat by QrCodeId dulu -- kalau udah ada, ditolak & kasih tau jam
-- absennya, TANPA nambah baris baru.
-- -------------------------------------------------------------------------------------
DROP FUNCTION IF EXISTS tbm_scan_peserta(BIGINT, TEXT, TEXT);
CREATE OR REPLACE FUNCTION tbm_scan_peserta(
    p_id BIGINT,
    p_nama TEXT,
    p_qrcode TEXT
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
    SELECT "Status", "PesertaList" INTO v_status, v_peserta FROM "tbmTbl" WHERE "Id" = p_id;

    IF v_status IS NULL THEN
        RETURN jsonb_build_object('success', false, 'message', 'Sesi TBM tidak ditemukan.');
    END IF;
    IF v_status <> 'Sedang Absen' THEN
        RETURN jsonb_build_object('success', false, 'message', 'Sesi ini sudah Selesai, tidak bisa absen lagi.');
    END IF;

    SELECT elem INTO v_existing
    FROM jsonb_array_elements(v_peserta) elem
    WHERE elem->>'qrCodeId' = p_qrcode
    LIMIT 1;

    IF v_existing IS NOT NULL THEN
        RETURN jsonb_build_object(
            'success', false, 'duplicate', true,
            'nama', v_existing->>'nama', 'jamAbsen', v_existing->>'jamAbsen'
        );
    END IF;

    v_new_entry := jsonb_build_object('nama', p_nama, 'qrCodeId', p_qrcode, 'jamAbsen', NOW());
    UPDATE "tbmTbl"
    SET "PesertaList" = "PesertaList" || jsonb_build_array(v_new_entry)
    WHERE "Id" = p_id
    RETURNING jsonb_array_length("PesertaList") INTO v_jumlah;

    RETURN jsonb_build_object('success', true, 'jumlahPeserta', v_jumlah);
END;
$$;


-- -------------------------------------------------------------------------------------
-- RPC: TUTUP SESI (Sedang Absen -> Selesai)
-- -------------------------------------------------------------------------------------
DROP FUNCTION IF EXISTS tbm_finish_session(BIGINT, TEXT, JSONB);
CREATE OR REPLACE FUNCTION tbm_finish_session(
    p_id BIGINT,
    p_catatan TEXT DEFAULT '',
    p_foto_list JSONB DEFAULT '[]'::jsonb
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    UPDATE "tbmTbl"
    SET "Status" = 'Selesai',
        "TanggalSelesai" = NOW(),
        "CatatanPenutup" = p_catatan,
        "FotoPenutupList" = COALESCE(p_foto_list, '[]'::jsonb)
    WHERE "Id" = p_id;

    RETURN jsonb_build_object('success', true);
END;
$$;


-- -------------------------------------------------------------------------------------
-- RPC: AMBIL DAFTAR SESI (riwayat) & DETAIL BY ID
-- -------------------------------------------------------------------------------------
DROP FUNCTION IF EXISTS get_tbm_list(TEXT);
CREATE OR REPLACE FUNCTION get_tbm_list(p_status TEXT DEFAULT NULL)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_result JSONB;
BEGIN
    SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'id', c."Id",
        'noSesi', c."NoSesi",
        'lokasiArea', c."LokasiArea",
        'topikBriefing', c."TopikBriefing",
        'permitId', c."PermitId",
        'permitNoPermit', ptw."NoPermit",
        'leaderNama', c."LeaderNama",
        'leaderQrCodeId', c."LeaderQrCodeId",
        'tanggalMulai', c."TanggalMulai",
        'status', c."Status",
        'pesertaList', c."PesertaList",
        'catatanPenutup', c."CatatanPenutup",
        'fotoPenutupList', c."FotoPenutupList",
        'tanggalSelesai', c."TanggalSelesai",
        'namaProject', p."NamaProject",
        'noKontrak', p."NoKontrak"
    ) ORDER BY c."TanggalMulai" DESC), '[]'::JSONB)
    INTO v_result
    FROM "tbmTbl" c
    JOIN "projectTbl" p ON p."Id" = c."ProjectId"
    LEFT JOIN "ptwTbl" ptw ON ptw."Id" = c."PermitId"
    WHERE p_status IS NULL OR c."Status" = p_status;

    RETURN v_result;
END;
$$;


DROP FUNCTION IF EXISTS get_tbm_by_id(BIGINT);
CREATE OR REPLACE FUNCTION get_tbm_by_id(p_id BIGINT)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_result JSONB;
BEGIN
    SELECT jsonb_build_object(
        'id', c."Id",
        'noSesi', c."NoSesi",
        'lokasiArea', c."LokasiArea",
        'topikBriefing', c."TopikBriefing",
        'permitId', c."PermitId",
        'permitNoPermit', ptw."NoPermit",
        'leaderNama', c."LeaderNama",
        'leaderQrCodeId', c."LeaderQrCodeId",
        'tanggalMulai', c."TanggalMulai",
        'status', c."Status",
        'pesertaList', c."PesertaList",
        'catatanPenutup', c."CatatanPenutup",
        'fotoPenutupList', c."FotoPenutupList",
        'tanggalSelesai', c."TanggalSelesai",
        'namaProject', p."NamaProject",
        'noKontrak', p."NoKontrak",
        'tipeKonstruksi', p."TipeKonstruksi"
    )
    INTO v_result
    FROM "tbmTbl" c
    JOIN "projectTbl" p ON p."Id" = c."ProjectId"
    LEFT JOIN "ptwTbl" ptw ON ptw."Id" = c."PermitId"
    WHERE c."Id" = p_id;

    RETURN v_result;
END;
$$;
