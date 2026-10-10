-- =====================================================================================
-- MIGRASI #059 (HSSE): tarik man-hours SmartGate OTOMATIS tiap malam
-- Jalankan di Supabase project **HSSE-Fusion4**, SETELAH 056 (tabel man-hours).
-- Aman dijalankan ulang (IF NOT EXISTS / CREATE OR REPLACE / cron.schedule upsert).
--
-- Cara kerja:
--   - pg_cron di database HSSE jalan tiap hari jam 18:00 UTC = 01:00 WIB.
--   - Database HSSE manggil RPC Fusion4 get_hsse_man_hours langsung lewat extension
--     `http` (pakai publishable key Fusion4 yang sama dengan config.js, read only).
--   - Hasilnya disimpan pakai logika yang sama dengan tombol "Tarik dari SmartGate":
--     angka SmartGate tahun itu diganti, koreksi manual TETAP, lokasi yang belum
--     dipetakan gak ikut dihitung.
--   - Default SEMUA project ikut. Project yang dimatikan di halaman input gak disentuh
--     sama tarik otomatis (angka SmartGate terakhirnya tetap). Tombol manual tetap
--     narik semua project.
--   - Tahun yang ditarik: tahun berjalan (WIB). Di bulan Januari, tahun lalu juga ditarik
--     ulang biar absensi akhir Desember ikut masuk.
--   - Hasil tiap jalan dicatat di manHoursLogTbl (Aksi 'Tarik Otomatis') dan status
--     terakhirnya muncul di halaman input.
-- =====================================================================================

CREATE EXTENSION IF NOT EXISTS http WITH SCHEMA extensions;
CREATE EXTENSION IF NOT EXISTS pg_cron;

-- -------------------------------------------------------------------------------------
-- Tabel setting
-- -------------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS "manHoursAutoConfigTbl" (
    "Id" INT PRIMARY KEY DEFAULT 1 CHECK ("Id" = 1),
    "Aktif" BOOLEAN NOT NULL DEFAULT TRUE,
    "JamStandar" NUMERIC NOT NULL DEFAULT 8,
    "SmartGateUrl" TEXT NOT NULL DEFAULT '',
    "SmartGateKey" TEXT NOT NULL DEFAULT '',
    "TerakhirJalan" TIMESTAMPTZ,
    "TerakhirStatus" TEXT DEFAULT '',
    "TerakhirDetail" JSONB NOT NULL DEFAULT '{}'::jsonb,
    "DiubahOleh" TEXT DEFAULT '',
    "UpdatedAt" TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- URL + publishable key Fusion4 SmartGate (sama persis dengan FUSION4_SUPABASE_URL/KEY di config.js).
-- Kalau key Fusion4 diganti, update baris ini juga.
INSERT INTO "manHoursAutoConfigTbl" ("Id", "SmartGateUrl", "SmartGateKey")
VALUES (1, 'https://nhmpwjriextmbotmvvbu.supabase.co', 'sb_publishable_XNqLw7iz873TtrLn9ag8dQ_AkL2rImz')
ON CONFLICT ("Id") DO UPDATE
    SET "SmartGateUrl" = EXCLUDED."SmartGateUrl", "SmartGateKey" = EXCLUDED."SmartGateKey";

-- Project yang DIMATIKAN dari tarik otomatis. Gak ada baris = ikut (default semua ikut).
CREATE TABLE IF NOT EXISTS "manHoursAutoProjectTbl" (
    "ProjectId" BIGINT PRIMARY KEY REFERENCES "projectTbl"("Id") ON DELETE CASCADE,
    "Ikut" BOOLEAN NOT NULL DEFAULT TRUE,
    "DiubahOleh" TEXT DEFAULT '',
    "UpdatedAt" TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE "manHoursAutoConfigTbl" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "manHoursAutoProjectTbl" ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS manhours_auto_cfg_no_direct ON "manHoursAutoConfigTbl";
DROP POLICY IF EXISTS manhours_auto_prj_no_direct ON "manHoursAutoProjectTbl";
CREATE POLICY manhours_auto_cfg_no_direct ON "manHoursAutoConfigTbl" FOR ALL TO anon, authenticated USING (false) WITH CHECK (false);
CREATE POLICY manhours_auto_prj_no_direct ON "manHoursAutoProjectTbl" FOR ALL TO anon, authenticated USING (false) WITH CHECK (false);

-- -------------------------------------------------------------------------------------
-- Inti simpan hasil tarik (dipakai tombol manual DAN tarik otomatis).
-- p_hanya_ikut = TRUE -> cuma project yang ikut tarik otomatis yang direset/diisi.
-- Internal: gak bisa dipanggil dari browser.
-- -------------------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.man_hours_simpan_smartgate_inti(INT, JSONB, TEXT, TEXT, BOOLEAN, TEXT);
CREATE OR REPLACE FUNCTION public.man_hours_simpan_smartgate_inti(
    p_tahun INT,
    p_rows JSONB,
    p_nama TEXT,
    p_qr TEXT,
    p_hanya_ikut BOOLEAN,
    p_aksi TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_unmapped JSONB;
    v_count INT;
    v_dilewati JSONB := '[]'::jsonb;
BEGIN
    IF p_tahun IS NULL OR p_rows IS NULL OR jsonb_typeof(p_rows) <> 'array' THEN
        RAISE EXCEPTION 'Data tarikan SmartGate gak valid.';
    END IF;

    -- Daftarin lokasi baru. Coba cocokin otomatis ke NamaProject / NoKontrak.
    INSERT INTO "manHoursProjectMapTbl" ("LokasiSmartGate", "ProjectId", "DiubahOleh")
    SELECT DISTINCT ON (r.proj) r.proj,
        (SELECT p."Id" FROM "projectTbl" p
          WHERE lower(trim(p."NamaProject")) = lower(r.proj) OR lower(trim(p."NoKontrak")) = lower(r.proj)
          ORDER BY p."Id" LIMIT 1),
        'otomatis'
    FROM (SELECT trim(e->>'Lokasi') AS proj FROM jsonb_array_elements(p_rows) e) r
    WHERE COALESCE(r.proj, '') <> ''
    ON CONFLICT ("LokasiSmartGate") DO NOTHING;

    UPDATE "manHoursTbl" m
    SET "ManHoursSmartGate" = 0, "JumlahPekerjaSmartGate" = 0, "HariOrangSmartGate" = 0,
        "BarisEstimasi" = 0, "TanggalTarik" = NOW(), "UpdatedAt" = NOW()
    WHERE m."Tahun" = p_tahun
      AND (NOT p_hanya_ikut OR NOT EXISTS (
            SELECT 1 FROM "manHoursAutoProjectTbl" a WHERE a."ProjectId" = m."ProjectId" AND NOT a."Ikut"));

    WITH r AS (
        SELECT m."ProjectId",
               (e->>'Bulan')::INT AS bulan,
               SUM(COALESCE((e->>'ManHours')::NUMERIC, 0)) AS mh,
               SUM(COALESCE((e->>'JumlahPekerja')::INT, 0)) AS pekerja,
               SUM(COALESCE((e->>'HariOrang')::INT, 0)) AS hari_orang,
               SUM(COALESCE((e->>'BarisEstimasi')::INT, 0)) AS estimasi
        FROM jsonb_array_elements(p_rows) e
        JOIN "manHoursProjectMapTbl" m ON m."LokasiSmartGate" = trim(e->>'Lokasi')
        WHERE m."ProjectId" IS NOT NULL AND (e->>'Bulan')::INT BETWEEN 1 AND 12
          AND (NOT p_hanya_ikut OR NOT EXISTS (
                SELECT 1 FROM "manHoursAutoProjectTbl" a WHERE a."ProjectId" = m."ProjectId" AND NOT a."Ikut"))
        GROUP BY 1, 2
    )
    INSERT INTO "manHoursTbl" ("ProjectId", "Tahun", "Bulan", "ManHoursSmartGate", "JumlahPekerjaSmartGate",
        "HariOrangSmartGate", "BarisEstimasi", "TanggalTarik", "DiubahOleh", "DiubahQrCodeId", "UpdatedAt")
    SELECT "ProjectId", p_tahun, bulan, mh, pekerja, hari_orang, estimasi, NOW(), p_nama, COALESCE(p_qr, ''), NOW()
    FROM r
    ON CONFLICT ("ProjectId", "Tahun", "Bulan") DO UPDATE SET
        "ManHoursSmartGate" = EXCLUDED."ManHoursSmartGate",
        "JumlahPekerjaSmartGate" = EXCLUDED."JumlahPekerjaSmartGate",
        "HariOrangSmartGate" = EXCLUDED."HariOrangSmartGate",
        "BarisEstimasi" = EXCLUDED."BarisEstimasi",
        "TanggalTarik" = NOW(),
        "DiubahOleh" = EXCLUDED."DiubahOleh",
        "DiubahQrCodeId" = EXCLUDED."DiubahQrCodeId",
        "UpdatedAt" = NOW();
    GET DIAGNOSTICS v_count = ROW_COUNT;

    SELECT COALESCE(jsonb_agg(jsonb_build_object('lokasiSmartGate', x.proj, 'manHours', x.mh) ORDER BY x.mh DESC), '[]'::jsonb)
    INTO v_unmapped
    FROM (
        SELECT trim(e->>'Lokasi') AS proj, SUM(COALESCE((e->>'ManHours')::NUMERIC, 0)) AS mh
        FROM jsonb_array_elements(p_rows) e
        LEFT JOIN "manHoursProjectMapTbl" m ON m."LokasiSmartGate" = trim(e->>'Lokasi')
        WHERE m."ProjectId" IS NULL
        GROUP BY 1
    ) x;

    IF p_hanya_ikut THEN
        SELECT COALESCE(jsonb_agg(a."ProjectId" ORDER BY a."ProjectId"), '[]'::jsonb)
        INTO v_dilewati
        FROM "manHoursAutoProjectTbl" a WHERE NOT a."Ikut";
    END IF;

    INSERT INTO "manHoursLogTbl" ("Aksi", "Tahun", "Detail", "Oleh", "OlehQrCodeId")
    VALUES (p_aksi, p_tahun,
            jsonb_build_object('barisDiterima', jsonb_array_length(p_rows), 'barisDisimpan', v_count,
                               'belumDipetakan', v_unmapped, 'projectDilewati', v_dilewati),
            p_nama, COALESCE(p_qr, ''));

    RETURN jsonb_build_object('ok', true, 'barisDisimpan', v_count, 'belumDipetakan', v_unmapped,
                              'projectDilewati', v_dilewati);
END;
$$;
REVOKE ALL ON FUNCTION public.man_hours_simpan_smartgate_inti(INT, JSONB, TEXT, TEXT, BOOLEAN, TEXT) FROM PUBLIC, anon, authenticated;

-- Tombol manual: perilaku sama kayak #056 (semua project), sekarang lewat fungsi inti.
CREATE OR REPLACE FUNCTION public.save_man_hours_smartgate(
    p_tahun INT,
    p_rows JSONB,
    p_nama TEXT,
    p_qr TEXT DEFAULT ''
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    IF COALESCE(trim(p_nama), '') = '' THEN
        RAISE EXCEPTION 'Verifikasi PIC dulu.';
    END IF;
    RETURN public.man_hours_simpan_smartgate_inti(p_tahun, p_rows, p_nama, p_qr, FALSE, 'Tarik SmartGate');
END;
$$;

-- -------------------------------------------------------------------------------------
-- Tarik otomatis. Dipanggil pg_cron. Bisa juga dites manual di SQL Editor:
--   SELECT public.man_hours_tarik_otomatis(true);
-- p_paksa = TRUE -> tetap jalan walau setting "Aktif" dimatikan.
-- -------------------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.man_hours_tarik_otomatis(BOOLEAN);
CREATE OR REPLACE FUNCTION public.man_hours_tarik_otomatis(p_paksa BOOLEAN DEFAULT FALSE)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
    v_cfg "manHoursAutoConfigTbl"%ROWTYPE;
    v_now_wib TIMESTAMP := (NOW() AT TIME ZONE 'Asia/Jakarta');
    v_tahun INT;
    v_tahun_list INT[];
    v_resp RECORD;
    v_rows JSONB;
    v_res JSONB;
    v_hasil JSONB := '[]'::jsonb;
    v_gagal BOOLEAN := FALSE;
BEGIN
    SELECT * INTO v_cfg FROM "manHoursAutoConfigTbl" WHERE "Id" = 1;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Setting tarik otomatis belum ada (jalankan ulang 059).';
    END IF;
    IF NOT v_cfg."Aktif" AND NOT p_paksa THEN
        RETURN jsonb_build_object('ok', true, 'dilewati', 'Tarik otomatis lagi dimatikan.');
    END IF;

    v_tahun_list := ARRAY[EXTRACT(YEAR FROM v_now_wib)::INT];
    IF EXTRACT(MONTH FROM v_now_wib) = 1 THEN
        v_tahun_list := ARRAY[EXTRACT(YEAR FROM v_now_wib)::INT - 1] || v_tahun_list;
    END IF;

    PERFORM http_set_curlopt('CURLOPT_TIMEOUT', '120');

    FOREACH v_tahun IN ARRAY v_tahun_list LOOP
        BEGIN
            SELECT status, content INTO v_resp
            FROM http((
                'POST',
                rtrim(v_cfg."SmartGateUrl", '/') || '/rest/v1/rpc/get_hsse_man_hours',
                ARRAY[http_header('apikey', v_cfg."SmartGateKey"),
                      http_header('Authorization', 'Bearer ' || v_cfg."SmartGateKey")],
                'application/json',
                jsonb_build_object('p_tahun', v_tahun, 'p_bulan', NULL, 'p_jam_standar', v_cfg."JamStandar")::TEXT
            )::http_request);

            IF v_resp.status <> 200 THEN
                RAISE EXCEPTION 'SmartGate balas HTTP %: %', v_resp.status, left(COALESCE(v_resp.content, ''), 300);
            END IF;
            v_rows := v_resp.content::JSONB;

            v_res := public.man_hours_simpan_smartgate_inti(v_tahun, v_rows, 'Otomatis (jadwal)', '', TRUE, 'Tarik Otomatis');
            v_hasil := v_hasil || jsonb_build_object(
                'tahun', v_tahun, 'ok', true,
                'barisSmartGate', jsonb_array_length(v_rows),
                'barisDisimpan', v_res->'barisDisimpan',
                'belumDipetakan', jsonb_array_length(v_res->'belumDipetakan'));
        EXCEPTION WHEN OTHERS THEN
            v_gagal := TRUE;
            v_hasil := v_hasil || jsonb_build_object('tahun', v_tahun, 'ok', false, 'error', SQLERRM);
            INSERT INTO "manHoursLogTbl" ("Aksi", "Tahun", "Detail", "Oleh")
            VALUES ('Tarik Otomatis Gagal', v_tahun, jsonb_build_object('error', SQLERRM), 'Otomatis (jadwal)');
        END;
    END LOOP;

    UPDATE "manHoursAutoConfigTbl"
    SET "TerakhirJalan" = NOW(),
        "TerakhirStatus" = CASE WHEN v_gagal THEN 'Gagal' ELSE 'Berhasil' END,
        "TerakhirDetail" = jsonb_build_object('hasil', v_hasil)
    WHERE "Id" = 1;

    RETURN jsonb_build_object('ok', NOT v_gagal, 'hasil', v_hasil);
END;
$$;
REVOKE ALL ON FUNCTION public.man_hours_tarik_otomatis(BOOLEAN) FROM PUBLIC, anon, authenticated;

-- -------------------------------------------------------------------------------------
-- RPC buat halaman input
-- -------------------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.get_man_hours_auto();
CREATE OR REPLACE FUNCTION public.get_man_hours_auto()
RETURNS JSONB
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT jsonb_build_object(
        'aktif', c."Aktif",
        'jamStandar', c."JamStandar",
        'jadwal', 'Tiap hari 01:00 WIB',
        'terakhirJalan', c."TerakhirJalan",
        'terakhirStatus', c."TerakhirStatus",
        'terakhirDetail', c."TerakhirDetail",
        'diubahOleh', c."DiubahOleh",
        'updatedAt', c."UpdatedAt",
        'projectMati', COALESCE((SELECT jsonb_agg(a."ProjectId" ORDER BY a."ProjectId")
                                 FROM "manHoursAutoProjectTbl" a WHERE NOT a."Ikut"), '[]'::jsonb)
    )
    FROM "manHoursAutoConfigTbl" c
    WHERE c."Id" = 1;
$$;

DROP FUNCTION IF EXISTS public.save_man_hours_auto_config(BOOLEAN, NUMERIC, TEXT, TEXT);
CREATE OR REPLACE FUNCTION public.save_man_hours_auto_config(
    p_aktif BOOLEAN,
    p_jam_standar NUMERIC,
    p_nama TEXT,
    p_qr TEXT DEFAULT ''
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    IF COALESCE(trim(p_nama), '') = '' THEN
        RAISE EXCEPTION 'Verifikasi PIC dulu.';
    END IF;
    IF p_aktif IS NULL THEN
        RAISE EXCEPTION 'Status aktif kosong.';
    END IF;
    IF p_jam_standar IS NULL OR p_jam_standar < 1 OR p_jam_standar > 24 THEN
        RAISE EXCEPTION 'Jam standar harus 1-24.';
    END IF;
    UPDATE "manHoursAutoConfigTbl"
    SET "Aktif" = p_aktif, "JamStandar" = p_jam_standar, "DiubahOleh" = p_nama, "UpdatedAt" = NOW()
    WHERE "Id" = 1;
    INSERT INTO "manHoursLogTbl" ("Aksi", "Detail", "Oleh", "OlehQrCodeId")
    VALUES ('Setting Otomatis', jsonb_build_object('aktif', p_aktif, 'jamStandar', p_jam_standar), p_nama, COALESCE(p_qr, ''));
    RETURN jsonb_build_object('ok', true);
END;
$$;

DROP FUNCTION IF EXISTS public.save_man_hours_auto_project(BIGINT, BOOLEAN, TEXT, TEXT);
CREATE OR REPLACE FUNCTION public.save_man_hours_auto_project(
    p_project_id BIGINT,
    p_ikut BOOLEAN,
    p_nama TEXT,
    p_qr TEXT DEFAULT ''
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    IF COALESCE(trim(p_nama), '') = '' THEN
        RAISE EXCEPTION 'Verifikasi PIC dulu.';
    END IF;
    IF p_project_id IS NULL OR p_ikut IS NULL THEN
        RAISE EXCEPTION 'Project / status kosong.';
    END IF;
    INSERT INTO "manHoursAutoProjectTbl" ("ProjectId", "Ikut", "DiubahOleh", "UpdatedAt")
    VALUES (p_project_id, p_ikut, p_nama, NOW())
    ON CONFLICT ("ProjectId") DO UPDATE
        SET "Ikut" = EXCLUDED."Ikut", "DiubahOleh" = EXCLUDED."DiubahOleh", "UpdatedAt" = NOW();
    INSERT INTO "manHoursLogTbl" ("Aksi", "ProjectId", "Detail", "Oleh", "OlehQrCodeId")
    VALUES ('Setting Otomatis', p_project_id, jsonb_build_object('ikut', p_ikut), p_nama, COALESCE(p_qr, ''));
    RETURN jsonb_build_object('ok', true);
END;
$$;

-- -------------------------------------------------------------------------------------
-- Jadwal pg_cron: 18:00 UTC = 01:00 WIB tiap hari. Nama job sama -> jadwal lama diganti.
-- -------------------------------------------------------------------------------------
SELECT cron.schedule(
    'hsse-man-hours-otomatis',
    '0 18 * * *',
    $cron$SET statement_timeout = '10min'; SELECT public.man_hours_tarik_otomatis();$cron$
);

-- -------------------------------------------------------------------------------------
-- CEK (jalanin manual kalau mau):
-- 1. Tes tarik sekarang juga (gak perlu nunggu jam 1 malam):
--      SELECT public.man_hours_tarik_otomatis(true);
-- 2. Jadwal terpasang:
--      SELECT jobid, jobname, schedule, active FROM cron.job WHERE jobname = 'hsse-man-hours-otomatis';
-- 3. Riwayat jalan pg_cron:
--      SELECT status, return_message, start_time FROM cron.job_run_details
--      WHERE jobid = (SELECT jobid FROM cron.job WHERE jobname = 'hsse-man-hours-otomatis')
--      ORDER BY start_time DESC LIMIT 10;
-- 4. Matikan jadwal sama sekali (kalau perlu):
--      SELECT cron.unschedule('hsse-man-hours-otomatis');
-- -------------------------------------------------------------------------------------
