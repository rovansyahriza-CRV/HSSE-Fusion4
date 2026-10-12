-- =====================================================================================
-- MIGRASI #060 (HSSE): project HSSE ikut Operational Code SmartGate
-- Jalankan di Supabase project **HSSE-Fusion4**, SETELAH 059.
-- Sebelumnya jalankan dulu sql/for-FUSION4_man_hours_rpc.sql versi baru di project
-- **Fusion4 SmartGate** (biar man-hours ikut bawa kode project tiap lokasi).
-- Aman dijalankan ulang (IF NOT EXISTS / CREATE OR REPLACE).
--
-- Isi:
--   1. projectTbl dapat kolom KodeOperational (014, 015, 901...), TipeProject (CLIENT /
--      INTERNAL), Divisi. Project contoh Id 1 = 014 (keputusan CRV 2026-10-12).
--   2. Sinkron master project dari SmartGate (operational.projects lewat RPC publik
--      op_list_projects_public). SmartGate = master: nama, no. kontrak, client, status,
--      tanggal ikut SmartGate. Kode baru otomatis jadi project HSSE baru.
--      Jalan: sekali di akhir migrasi ini, tiap malam sebelum tarik man-hours otomatis,
--      dan tiap klik "Tarik dari SmartGate" di halaman input.
--   3. Man-hours: lokasi absensi otomatis masuk ke project sesuai kode project lokasi
--      itu di SmartGate (lokasiTbl.Project). Pemetaan manual tetap bisa dan MENANG,
--      plus pilihan "Gak dihitung".
--   4. get_statistik_kpi & get_statistik_piramida dapat parameter p_scope:
--        'ALL'         = Corporate + semua project (sama dengan "gabungan" lama)
--        'ALL_PROJECT' = semua project client (TipeProject <> INTERNAL)
--        'CORPORATE'   = kode internal 9xx (TipeProject = INTERNAL)
--      Kalau p_project_id diisi, scope diabaikan (1 project).
-- =====================================================================================

-- -------------------------------------------------------------------------------------
-- 1. Kolom baru
-- -------------------------------------------------------------------------------------
ALTER TABLE "projectTbl" ADD COLUMN IF NOT EXISTS "KodeOperational" TEXT;
ALTER TABLE "projectTbl" ADD COLUMN IF NOT EXISTS "TipeProject" TEXT NOT NULL DEFAULT 'CLIENT';
ALTER TABLE "projectTbl" ADD COLUMN IF NOT EXISTS "Divisi" TEXT DEFAULT '';
ALTER TABLE "projectTbl" ADD COLUMN IF NOT EXISTS "SinkronSmartGateAt" TIMESTAMPTZ;
CREATE UNIQUE INDEX IF NOT EXISTS "projectTbl_KodeOperational_key"
    ON "projectTbl" ("KodeOperational") WHERE "KodeOperational" IS NOT NULL;

UPDATE "projectTbl" SET "KodeOperational" = '014'
WHERE "Id" = 1 AND "KodeOperational" IS NULL
  AND NOT EXISTS (SELECT 1 FROM "projectTbl" WHERE "KodeOperational" = '014');

ALTER TABLE "manHoursProjectMapTbl" ADD COLUMN IF NOT EXISTS "KodeSmartGate" TEXT;
ALTER TABLE "manHoursProjectMapTbl" ADD COLUMN IF NOT EXISTS "Abaikan" BOOLEAN NOT NULL DEFAULT FALSE;

-- -------------------------------------------------------------------------------------
-- 2. Daftar project buat dropdown (dipakai semua halaman)
-- -------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_active_projects()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_result JSONB;
BEGIN
    SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'id', "Id",
        'kodeOperational', "KodeOperational",
        'namaProject', "NamaProject",
        'label', CASE WHEN COALESCE("KodeOperational", '') <> '' THEN "KodeOperational" || ' · ' || "NamaProject" ELSE "NamaProject" END,
        'noKontrak', "NoKontrak",
        'tipeProject', "TipeProject",
        'divisi', "Divisi",
        'client', "Client",
        'tipeKonstruksi', "TipeKonstruksi",
        'tanggalMulaiProject', "TanggalMulaiProject",
        'tanggalSelesaiProject', "TanggalSelesaiProject"
    ) ORDER BY ("TipeProject" = 'INTERNAL'), "KodeOperational" NULLS LAST, "NamaProject"), '[]'::JSONB)
    INTO v_result
    FROM "projectTbl"
    WHERE "Status" = 'Aktif';

    RETURN v_result;
END;
$$;

-- -------------------------------------------------------------------------------------
-- 3. Sinkron master project dari SmartGate
-- p_rows = hasil op_list_projects_public SmartGate apa adanya:
--   [{ "code", "name", "client", "contractNumber", "status", "projectType", "divisi",
--      "startDate", "endDate", ... }]
-- Internal: gak bisa dipanggil dari browser.
-- -------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.project_sinkron_inti(p_rows JSONB, p_oleh TEXT)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_baru JSONB;
    v_ubah INT;
BEGIN
    IF p_rows IS NULL OR jsonb_typeof(p_rows) <> 'array' THEN
        RAISE EXCEPTION 'Data project SmartGate gak valid.';
    END IF;

    CREATE TEMP TABLE IF NOT EXISTS _sg_project (
        kode TEXT PRIMARY KEY, nama TEXT, kontrak TEXT, client TEXT, status TEXT,
        tipe TEXT, divisi TEXT, mulai DATE, selesai DATE
    ) ON COMMIT DROP;
    TRUNCATE _sg_project;

    INSERT INTO _sg_project
    SELECT DISTINCT ON (trim(e->>'code'))
        trim(e->>'code'),
        COALESCE(NULLIF(trim(e->>'name'), ''), trim(e->>'code')),
        NULLIF(trim(e->>'contractNumber'), ''),
        NULLIF(trim(e->>'client'), ''),
        CASE upper(COALESCE(trim(e->>'status'), ''))
            WHEN 'ACTIVE' THEN 'Aktif'
            WHEN 'COMPLETED' THEN 'Selesai'
            WHEN 'CLOSED' THEN 'Selesai'
            WHEN 'DONE' THEN 'Selesai'
            WHEN 'FINISHED' THEN 'Selesai'
            ELSE 'Non-Aktif'
        END,
        CASE WHEN upper(COALESCE(e->>'projectType', '')) = 'INTERNAL' THEN 'INTERNAL' ELSE 'CLIENT' END,
        COALESCE(trim(e->>'divisi'), ''),
        NULLIF(e->>'startDate', '')::DATE,
        NULLIF(e->>'endDate', '')::DATE
    FROM jsonb_array_elements(p_rows) e
    WHERE COALESCE(trim(e->>'code'), '') <> '';

    UPDATE "projectTbl" p SET
        "NamaProject" = s.nama,
        "NoKontrak" = COALESCE(s.kontrak, p."NoKontrak"),
        "Client" = COALESCE(s.client, p."Client"),
        "Status" = s.status,
        "TipeProject" = s.tipe,
        "Divisi" = s.divisi,
        "TanggalMulaiProject" = COALESCE(s.mulai, p."TanggalMulaiProject"),
        "TanggalSelesaiProject" = COALESCE(s.selesai, p."TanggalSelesaiProject"),
        "SinkronSmartGateAt" = NOW()
    FROM _sg_project s
    WHERE p."KodeOperational" = s.kode;
    GET DIAGNOSTICS v_ubah = ROW_COUNT;

    WITH ins AS (
        INSERT INTO "projectTbl" ("KodeOperational", "NamaProject", "NoKontrak", "Client", "Status",
            "TipeProject", "Divisi", "TipeKonstruksi", "TanggalMulaiProject", "TanggalSelesaiProject", "SinkronSmartGateAt")
        SELECT s.kode, s.nama, COALESCE(s.kontrak, s.kode), COALESCE(s.client, ''), s.status,
            s.tipe, s.divisi, 'Onshore', s.mulai, s.selesai, NOW()
        FROM _sg_project s
        WHERE NOT EXISTS (SELECT 1 FROM "projectTbl" p WHERE p."KodeOperational" = s.kode)
        RETURNING "KodeOperational"
    )
    SELECT COALESCE(jsonb_agg("KodeOperational" ORDER BY "KodeOperational"), '[]'::jsonb) INTO v_baru FROM ins;

    IF jsonb_array_length(v_baru) > 0 THEN
        INSERT INTO "manHoursLogTbl" ("Aksi", "Detail", "Oleh")
        VALUES ('Sinkron Project', jsonb_build_object('projectBaru', v_baru, 'diperbarui', v_ubah), COALESCE(p_oleh, ''));
    END IF;

    RETURN jsonb_build_object('ok', true, 'diperbarui', v_ubah, 'projectBaru', v_baru);
END;
$$;
REVOKE ALL ON FUNCTION public.project_sinkron_inti(JSONB, TEXT) FROM PUBLIC, anon, authenticated;

-- Narik op_list_projects_public SmartGate lewat extension http (URL + publishable key
-- sama dengan tarik man-hours otomatis, disimpan di manHoursAutoConfigTbl).
CREATE OR REPLACE FUNCTION public.project_sinkron_smartgate(p_oleh TEXT DEFAULT 'Otomatis')
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
    v_cfg "manHoursAutoConfigTbl"%ROWTYPE;
    v_resp RECORD;
BEGIN
    SELECT * INTO v_cfg FROM "manHoursAutoConfigTbl" WHERE "Id" = 1;
    IF NOT FOUND OR COALESCE(v_cfg."SmartGateUrl", '') = '' THEN
        RAISE EXCEPTION 'URL/key SmartGate belum ada di manHoursAutoConfigTbl (jalankan 059 dulu).';
    END IF;

    PERFORM http_set_curlopt('CURLOPT_TIMEOUT', '30');
    SELECT status, content INTO v_resp
    FROM http((
        'POST',
        rtrim(v_cfg."SmartGateUrl", '/') || '/rest/v1/rpc/op_list_projects_public',
        ARRAY[http_header('apikey', v_cfg."SmartGateKey"),
              http_header('Authorization', 'Bearer ' || v_cfg."SmartGateKey")],
        'application/json',
        '{}'
    )::http_request);

    IF v_resp.status IS DISTINCT FROM 200 THEN
        RAISE EXCEPTION 'SmartGate balas HTTP %: %', v_resp.status, left(COALESCE(v_resp.content, ''), 300);
    END IF;

    RETURN public.project_sinkron_inti(v_resp.content::JSONB, p_oleh);
END;
$$;
REVOKE ALL ON FUNCTION public.project_sinkron_smartgate(TEXT) FROM PUBLIC, anon, authenticated;

-- Dipanggil halaman input (PIC HSSE-STA) sebelum tarik man-hours manual.
CREATE OR REPLACE FUNCTION public.sinkron_project_smartgate(p_nama TEXT, p_qr TEXT DEFAULT '')
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    IF COALESCE(trim(p_nama), '') = '' THEN
        RAISE EXCEPTION 'Verifikasi PIC dulu.';
    END IF;
    RETURN public.project_sinkron_smartgate(p_nama);
END;
$$;
GRANT EXECUTE ON FUNCTION public.sinkron_project_smartgate(TEXT, TEXT) TO anon, authenticated;

-- -------------------------------------------------------------------------------------
-- 4. Man-hours: lokasi -> project
-- Urutan: "Gak dihitung" (Abaikan) -> pemetaan manual (ProjectId) -> kode project
-- lokasi di SmartGate (KodeSmartGate = projectTbl.KodeOperational).
-- -------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.man_hours_project_efektif(p_lokasi TEXT, p_kode TEXT)
RETURNS BIGINT
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT CASE
        WHEN m."Abaikan" THEN NULL
        WHEN m."ProjectId" IS NOT NULL THEN m."ProjectId"
        ELSE (SELECT p."Id" FROM "projectTbl" p
              WHERE p."KodeOperational" = COALESCE(NULLIF(trim(p_kode), ''), m."KodeSmartGate")
              LIMIT 1)
    END
    FROM (SELECT 1) d
    LEFT JOIN "manHoursProjectMapTbl" m ON m."LokasiSmartGate" = trim(p_lokasi);
$$;
REVOKE ALL ON FUNCTION public.man_hours_project_efektif(TEXT, TEXT) FROM PUBLIC, anon, authenticated;

-- Inti simpan hasil tarik (tombol manual & otomatis). Sama dengan 059, bedanya lokasi
-- dipetakan lewat man_hours_project_efektif (kode SmartGate ikut dipakai).
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

    -- Daftarin lokasi baru (tanpa pemetaan manual) + simpan kode project SmartGate terbarunya.
    INSERT INTO "manHoursProjectMapTbl" ("LokasiSmartGate", "ProjectId", "KodeSmartGate", "DiubahOleh")
    SELECT DISTINCT ON (r.lok) r.lok, NULL, r.kode, 'otomatis'
    FROM (SELECT trim(e->>'Lokasi') AS lok, NULLIF(trim(e->>'KodeProject'), '') AS kode
          FROM jsonb_array_elements(p_rows) e) r
    WHERE COALESCE(r.lok, '') <> ''
    ORDER BY r.lok, (r.kode IS NULL)
    ON CONFLICT ("LokasiSmartGate") DO UPDATE SET "KodeSmartGate" = EXCLUDED."KodeSmartGate";

    UPDATE "manHoursTbl" m
    SET "ManHoursSmartGate" = 0, "JumlahPekerjaSmartGate" = 0, "HariOrangSmartGate" = 0,
        "BarisEstimasi" = 0, "TanggalTarik" = NOW(), "UpdatedAt" = NOW()
    WHERE m."Tahun" = p_tahun
      AND (NOT p_hanya_ikut OR NOT EXISTS (
            SELECT 1 FROM "manHoursAutoProjectTbl" a WHERE a."ProjectId" = m."ProjectId" AND NOT a."Ikut"));

    WITH src AS (
        SELECT public.man_hours_project_efektif(e->>'Lokasi', e->>'KodeProject') AS pid, e
        FROM jsonb_array_elements(p_rows) e
    ),
    r AS (
        SELECT pid AS "ProjectId",
               (e->>'Bulan')::INT AS bulan,
               SUM(COALESCE((e->>'ManHours')::NUMERIC, 0)) AS mh,
               SUM(COALESCE((e->>'JumlahPekerja')::INT, 0)) AS pekerja,
               SUM(COALESCE((e->>'HariOrang')::INT, 0)) AS hari_orang,
               SUM(COALESCE((e->>'BarisEstimasi')::INT, 0)) AS estimasi
        FROM src
        WHERE pid IS NOT NULL AND (e->>'Bulan')::INT BETWEEN 1 AND 12
          AND (NOT p_hanya_ikut OR NOT EXISTS (
                SELECT 1 FROM "manHoursAutoProjectTbl" a WHERE a."ProjectId" = src.pid AND NOT a."Ikut"))
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

    SELECT COALESCE(jsonb_agg(jsonb_build_object('lokasiSmartGate', x.lok, 'kodeSmartGate', x.kode, 'manHours', x.mh)
                              ORDER BY x.mh DESC), '[]'::jsonb)
    INTO v_unmapped
    FROM (
        SELECT trim(e->>'Lokasi') AS lok, MAX(NULLIF(trim(e->>'KodeProject'), '')) AS kode,
               SUM(COALESCE((e->>'ManHours')::NUMERIC, 0)) AS mh
        FROM jsonb_array_elements(p_rows) e
        WHERE public.man_hours_project_efektif(e->>'Lokasi', e->>'KodeProject') IS NULL
          AND NOT EXISTS (SELECT 1 FROM "manHoursProjectMapTbl" m
                          WHERE m."LokasiSmartGate" = trim(e->>'Lokasi') AND m."Abaikan")
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

-- Tarik otomatis (jadwal 01:00 WIB, dari 059). Sekarang sinkron project dulu.
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
    v_sinkron JSONB;
    v_gagal BOOLEAN := FALSE;
BEGIN
    SELECT * INTO v_cfg FROM "manHoursAutoConfigTbl" WHERE "Id" = 1;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Setting tarik otomatis belum ada (jalankan ulang 059).';
    END IF;
    IF NOT v_cfg."Aktif" AND NOT p_paksa THEN
        RETURN jsonb_build_object('ok', true, 'dilewati', 'Tarik otomatis lagi dimatikan.');
    END IF;

    -- Sinkron master project dulu. Kalau gagal, tarik man-hours tetap jalan.
    BEGIN
        v_sinkron := public.project_sinkron_smartgate('Otomatis (jadwal)');
    EXCEPTION WHEN OTHERS THEN
        v_sinkron := jsonb_build_object('ok', false, 'error', SQLERRM);
        INSERT INTO "manHoursLogTbl" ("Aksi", "Detail", "Oleh")
        VALUES ('Sinkron Project Gagal', jsonb_build_object('error', SQLERRM), 'Otomatis (jadwal)');
    END;

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
        "TerakhirDetail" = jsonb_build_object('hasil', v_hasil, 'sinkronProject', v_sinkron)
    WHERE "Id" = 1;

    RETURN jsonb_build_object('ok', NOT v_gagal, 'hasil', v_hasil, 'sinkronProject', v_sinkron);
END;
$$;
REVOKE ALL ON FUNCTION public.man_hours_tarik_otomatis(BOOLEAN) FROM PUBLIC, anon, authenticated;

-- Pemetaan lokasi buat halaman input.
--   mode 'kode'   = ikut kode project SmartGate (default)
--   mode 'manual' = dipetakan manual ke projectId
--   mode 'abaikan'= gak dihitung
DROP FUNCTION IF EXISTS public.get_man_hours_project_map();
CREATE OR REPLACE FUNCTION public.get_man_hours_project_map()
RETURNS JSONB
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'lokasiSmartGate', m."LokasiSmartGate",
        'kodeSmartGate', m."KodeSmartGate",
        'mode', CASE WHEN m."Abaikan" THEN 'abaikan' WHEN m."ProjectId" IS NOT NULL THEN 'manual' ELSE 'kode' END,
        'projectId', m."ProjectId",
        'projectIdKode', pk."Id",
        'projectIdEfektif', CASE WHEN m."Abaikan" THEN NULL ELSE COALESCE(m."ProjectId", pk."Id") END,
        'namaProject', COALESCE(p."NamaProject", pk."NamaProject"),
        'noKontrak', COALESCE(p."NoKontrak", pk."NoKontrak"),
        'diubahOleh', m."DiubahOleh",
        'updatedAt', m."UpdatedAt"
    ) ORDER BY (m."Abaikan" OR COALESCE(m."ProjectId", pk."Id") IS NOT NULL), m."LokasiSmartGate"), '[]'::jsonb)
    FROM "manHoursProjectMapTbl" m
    LEFT JOIN "projectTbl" p ON p."Id" = m."ProjectId"
    LEFT JOIN "projectTbl" pk ON pk."KodeOperational" = m."KodeSmartGate";
$$;
GRANT EXECUTE ON FUNCTION public.get_man_hours_project_map() TO anon, authenticated;

DROP FUNCTION IF EXISTS public.save_man_hours_project_map(TEXT, BIGINT, TEXT, TEXT);
DROP FUNCTION IF EXISTS public.save_man_hours_project_map(TEXT, BIGINT, TEXT, TEXT, BOOLEAN);
CREATE OR REPLACE FUNCTION public.save_man_hours_project_map(
    p_lokasi TEXT,
    p_project_id BIGINT,
    p_nama TEXT,
    p_qr TEXT DEFAULT '',
    p_abaikan BOOLEAN DEFAULT FALSE
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    IF COALESCE(trim(p_lokasi), '') = '' THEN
        RAISE EXCEPTION 'Nama lokasi kosong.';
    END IF;
    IF COALESCE(trim(p_nama), '') = '' THEN
        RAISE EXCEPTION 'Verifikasi PIC dulu.';
    END IF;
    INSERT INTO "manHoursProjectMapTbl" ("LokasiSmartGate", "ProjectId", "Abaikan", "DiubahOleh", "UpdatedAt")
    VALUES (trim(p_lokasi), CASE WHEN p_abaikan THEN NULL ELSE p_project_id END, COALESCE(p_abaikan, FALSE), p_nama, NOW())
    ON CONFLICT ("LokasiSmartGate") DO UPDATE
        SET "ProjectId" = EXCLUDED."ProjectId", "Abaikan" = EXCLUDED."Abaikan",
            "DiubahOleh" = EXCLUDED."DiubahOleh", "UpdatedAt" = NOW();
    INSERT INTO "manHoursLogTbl" ("Aksi", "ProjectId", "Detail", "Oleh", "OlehQrCodeId")
    VALUES ('Mapping', CASE WHEN p_abaikan THEN NULL ELSE p_project_id END,
            jsonb_build_object('lokasiSmartGate', trim(p_lokasi),
                               'mode', CASE WHEN p_abaikan THEN 'abaikan' WHEN p_project_id IS NOT NULL THEN 'manual' ELSE 'kode' END),
            p_nama, COALESCE(p_qr, ''));
    RETURN jsonb_build_object('ok', true);
END;
$$;
GRANT EXECUTE ON FUNCTION public.save_man_hours_project_map(TEXT, BIGINT, TEXT, TEXT, BOOLEAN) TO anon, authenticated;

-- -------------------------------------------------------------------------------------
-- 5. Scope statistik
-- Hasil NULL = gak difilter (ALL). Array kosong = gak ada project yang cocok.
-- -------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.hsse_scope_project_ids(p_project_id BIGINT, p_scope TEXT)
RETURNS BIGINT[]
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT CASE
        WHEN p_project_id IS NOT NULL THEN ARRAY[p_project_id]
        WHEN upper(COALESCE(p_scope, 'ALL')) = 'ALL_PROJECT' THEN
            COALESCE((SELECT array_agg("Id") FROM "projectTbl" WHERE "TipeProject" <> 'INTERNAL'), '{}'::BIGINT[])
        WHEN upper(COALESCE(p_scope, 'ALL')) = 'CORPORATE' THEN
            COALESCE((SELECT array_agg("Id") FROM "projectTbl" WHERE "TipeProject" = 'INTERNAL'), '{}'::BIGINT[])
        ELSE NULL
    END;
$$;
GRANT EXECUTE ON FUNCTION public.hsse_scope_project_ids(BIGINT, TEXT) TO anon, authenticated;

-- get_statistik_kpi (dari 057) + p_scope
DROP FUNCTION IF EXISTS public.get_statistik_kpi(BIGINT, INT, NUMERIC);
DROP FUNCTION IF EXISTS public.get_statistik_kpi(BIGINT, INT, NUMERIC, TEXT);
CREATE OR REPLACE FUNCTION public.get_statistik_kpi(
    p_project_id BIGINT,
    p_tahun INT,
    p_basis NUMERIC DEFAULT 1000000,
    p_scope TEXT DEFAULT 'ALL'
)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_ids BIGINT[] := public.hsse_scope_project_ids(p_project_id, p_scope);
    v_bulan JSONB;
    v_ytd JSONB;
    v_rolling JSONB;
    v_klas JSONB;
    v_temuan JSONB;
    v_lti JSONB;
    v_basis NUMERIC := COALESCE(NULLIF(p_basis, 0), 1000000);
    v_akhir DATE;
    v_awal DATE;
BEGIN
    -- Periode rolling 12 bulan: tahun berjalan -> s/d bulan ini, tahun lalu -> s/d Desember.
    IF p_tahun = EXTRACT(YEAR FROM CURRENT_DATE)::INT THEN
        v_akhir := date_trunc('month', CURRENT_DATE)::DATE;
    ELSE
        v_akhir := make_date(p_tahun, 12, 1);
    END IF;
    v_awal := (v_akhir - INTERVAL '11 months')::DATE;

    WITH bln AS (SELECT generate_series(1, 12) AS b),
    mh AS (
        SELECT "Bulan" AS b,
               SUM(COALESCE("ManHoursKoreksi", "ManHoursSmartGate")) AS man_hours,
               SUM(COALESCE("JumlahPekerjaKoreksi", "JumlahPekerjaSmartGate")) AS pekerja
        FROM "manHoursTbl"
        WHERE "Tahun" = p_tahun AND (v_ids IS NULL OR "ProjectId" = ANY(v_ids))
        GROUP BY 1
    ),
    inc AS (
        SELECT EXTRACT(MONTH FROM "TanggalWaktu")::INT AS b,
               COUNT(*) FILTER (WHERE "Klasifikasi" = 'First Aid Case') AS fac,
               COUNT(*) FILTER (WHERE "Klasifikasi" = 'Medical Treatment Case') AS mtc,
               COUNT(*) FILTER (WHERE "Klasifikasi" = 'Restricted Work Case') AS rwc,
               COUNT(*) FILTER (WHERE "Klasifikasi" = 'Lost Time Injury') AS lti,
               COUNT(*) FILTER (WHERE "Klasifikasi" = 'Fatality') AS fatality,
               COUNT(*) FILTER (WHERE "Klasifikasi" = 'Near Miss') AS near_miss,
               COUNT(*) FILTER (WHERE "Klasifikasi" IN ('Kerusakan Properti', 'Lingkungan', 'Keamanan/Security')) AS non_injury,
               COALESCE(SUM("HariKerjaHilang") FILTER (WHERE "Klasifikasi" IN ('Restricted Work Case', 'Lost Time Injury', 'Fatality')), 0) AS hari_hilang
        FROM "incidentTbl"
        WHERE EXTRACT(YEAR FROM "TanggalWaktu") = p_tahun AND (v_ids IS NULL OR "ProjectId" = ANY(v_ids))
        GROUP BY 1
    ),
    cer AS (
        SELECT EXTRACT(MONTH FROM "TanggalWaktu")::INT AS b,
               COUNT(*) FILTER (WHERE "Sifat" = 'Positif') AS positif,
               COUNT(*) FILTER (WHERE "Sifat" = 'Negatif') AS negatif,
               COUNT(*) FILTER (WHERE "JenisTemuan" = 'Near Miss') AS near_miss
        FROM "cermatTbl"
        WHERE EXTRACT(YEAR FROM "TanggalWaktu") = p_tahun AND (v_ids IS NULL OR "ProjectId" = ANY(v_ids))
        GROUP BY 1
    ),
    ins AS (
        SELECT EXTRACT(MONTH FROM "TanggalWaktu")::INT AS b, COUNT(*) AS jml, ROUND(AVG("SkorPersen"), 1) AS skor
        FROM "inspeksiTbl"
        WHERE EXTRACT(YEAR FROM "TanggalWaktu") = p_tahun AND (v_ids IS NULL OR "ProjectId" = ANY(v_ids))
        GROUP BY 1
    ),
    tbm AS (
        SELECT EXTRACT(MONTH FROM "TanggalMulai")::INT AS b, COUNT(*) AS jml,
               COALESCE(SUM(jsonb_array_length(COALESCE("PesertaList", '[]'::jsonb))), 0) AS peserta
        FROM "tbmTbl"
        WHERE EXTRACT(YEAR FROM "TanggalMulai") = p_tahun AND (v_ids IS NULL OR "ProjectId" = ANY(v_ids))
        GROUP BY 1
    ),
    ptw AS (
        SELECT EXTRACT(MONTH FROM "TanggalWaktu")::INT AS b,
               COUNT(*) AS diajukan,
               COUNT(*) FILTER (WHERE "Status" IN ('Aktif', 'Menunggu Approval Penutupan', 'Ditutup')) AS disetujui
        FROM "ptwTbl"
        WHERE EXTRACT(YEAR FROM "TanggalWaktu") = p_tahun AND (v_ids IS NULL OR "ProjectId" = ANY(v_ids))
        GROUP BY 1
    ),
    mtg AS (
        SELECT EXTRACT(MONTH FROM "TanggalRapat")::INT AS b, COUNT(*) AS jml
        FROM "hseMeetingTbl"
        WHERE EXTRACT(YEAR FROM "TanggalRapat") = p_tahun AND (v_ids IS NULL OR "ProjectId" = ANY(v_ids))
        GROUP BY 1
    ),
    mwt AS (
        SELECT EXTRACT(MONTH FROM mv.tgl)::INT AS b, COUNT(*) AS jml
        FROM "mwtTbl" m
        CROSS JOIN LATERAL (
            SELECT MIN((elem->>'tanggalKunjungan')::timestamptz) AS tgl
            FROM jsonb_array_elements(COALESCE(m."KunjunganList", '[]'::jsonb)) elem
        ) mv
        WHERE mv.tgl IS NOT NULL AND EXTRACT(YEAR FROM mv.tgl) = p_tahun
          AND (v_ids IS NULL OR m."ProjectId" = ANY(v_ids))
        GROUP BY 1
    ),
    aud AS (
        SELECT EXTRACT(MONTH FROM COALESCE("TanggalSelesaiAudit", "TanggalDitutup"))::INT AS b, COUNT(*) AS jml
        FROM "auditTbl"
        WHERE "Status" IN ('Selesai Audit', 'Ditutup')
          AND EXTRACT(YEAR FROM COALESCE("TanggalSelesaiAudit", "TanggalDitutup")) = p_tahun
          AND (v_ids IS NULL OR "ProjectId" = ANY(v_ids))
        GROUP BY 1
    ),
    rows AS (
        SELECT bln.b,
               mh.man_hours, COALESCE(mh.pekerja, 0) AS pekerja,
               COALESCE(inc.fac, 0) AS fac, COALESCE(inc.mtc, 0) AS mtc, COALESCE(inc.rwc, 0) AS rwc,
               COALESCE(inc.lti, 0) AS lti, COALESCE(inc.fatality, 0) AS fatality,
               COALESCE(inc.near_miss, 0) AS nm_inc, COALESCE(cer.near_miss, 0) AS nm_cer,
               COALESCE(inc.non_injury, 0) AS non_injury, COALESCE(inc.hari_hilang, 0) AS hari_hilang,
               COALESCE(cer.positif, 0) AS positif, COALESCE(cer.negatif, 0) AS negatif,
               COALESCE(ins.jml, 0) AS inspeksi, ins.skor AS inspeksi_skor,
               COALESCE(tbm.jml, 0) AS tbm, COALESCE(tbm.peserta, 0) AS tbm_peserta,
               COALESCE(ptw.diajukan, 0) AS ptw_diajukan, COALESCE(ptw.disetujui, 0) AS ptw_disetujui,
               COALESCE(mtg.jml, 0) AS hse_meeting, COALESCE(mwt.jml, 0) AS mwt, COALESCE(aud.jml, 0) AS audit
        FROM bln
        LEFT JOIN mh ON mh.b = bln.b
        LEFT JOIN inc ON inc.b = bln.b
        LEFT JOIN cer ON cer.b = bln.b
        LEFT JOIN ins ON ins.b = bln.b
        LEFT JOIN tbm ON tbm.b = bln.b
        LEFT JOIN ptw ON ptw.b = bln.b
        LEFT JOIN mtg ON mtg.b = bln.b
        LEFT JOIN mwt ON mwt.b = bln.b
        LEFT JOIN aud ON aud.b = bln.b
    )
    SELECT
        jsonb_agg(jsonb_build_object(
            'bulan', b,
            'manHours', man_hours,
            'jumlahPekerja', pekerja,
            'fac', fac, 'mtc', mtc, 'rwc', rwc, 'lti', lti, 'fatality', fatality,
            'recordable', mtc + rwc + lti + fatality,
            'nearMissIncident', nm_inc, 'nearMissCermat', nm_cer, 'nearMiss', nm_inc + nm_cer,
            'nonInjury', non_injury, 'hariHilang', hari_hilang,
            'trir', CASE WHEN COALESCE(man_hours, 0) > 0 THEN ROUND((mtc + rwc + lti + fatality) * v_basis / man_hours, 2) END,
            'ltifr', CASE WHEN COALESCE(man_hours, 0) > 0 THEN ROUND((lti + fatality) * v_basis / man_hours, 2) END,
            'severityRate', CASE WHEN COALESCE(man_hours, 0) > 0 THEN ROUND(hari_hilang * v_basis / man_hours, 2) END,
            'cermatPositif', positif, 'cermatNegatif', negatif,
            'inspeksi', inspeksi, 'inspeksiSkorRata', inspeksi_skor,
            'tbm', tbm, 'tbmPeserta', tbm_peserta,
            'ptwDiajukan', ptw_diajukan, 'ptwDisetujui', ptw_disetujui,
            'hseMeeting', hse_meeting, 'mwt', mwt, 'auditSelesai', audit
        ) ORDER BY b),
        jsonb_build_object(
            'manHours', COALESCE(SUM(man_hours), 0),
            'bulanAdaManHours', COUNT(*) FILTER (WHERE COALESCE(man_hours, 0) > 0),
            'rataPekerja', ROUND(AVG(pekerja) FILTER (WHERE COALESCE(man_hours, 0) > 0), 0),
            'fac', SUM(fac), 'mtc', SUM(mtc), 'rwc', SUM(rwc), 'lti', SUM(lti), 'fatality', SUM(fatality),
            'recordable', SUM(mtc + rwc + lti + fatality),
            'nearMissIncident', SUM(nm_inc), 'nearMissCermat', SUM(nm_cer), 'nearMiss', SUM(nm_inc + nm_cer),
            'nonInjury', SUM(non_injury), 'hariHilang', SUM(hari_hilang),
            'trir', CASE WHEN COALESCE(SUM(man_hours), 0) > 0 THEN ROUND(SUM(mtc + rwc + lti + fatality) * v_basis / SUM(man_hours), 2) END,
            'ltifr', CASE WHEN COALESCE(SUM(man_hours), 0) > 0 THEN ROUND(SUM(lti + fatality) * v_basis / SUM(man_hours), 2) END,
            'severityRate', CASE WHEN COALESCE(SUM(man_hours), 0) > 0 THEN ROUND(SUM(hari_hilang) * v_basis / SUM(man_hours), 2) END,
            'fatalityRate', CASE WHEN COALESCE(SUM(man_hours), 0) > 0 THEN ROUND(SUM(fatality) * v_basis / SUM(man_hours), 2) END,
            'cermatPositif', SUM(positif), 'cermatNegatif', SUM(negatif),
            'inspeksi', SUM(inspeksi),
            'tbm', SUM(tbm), 'tbmPeserta', SUM(tbm_peserta),
            'ptwDiajukan', SUM(ptw_diajukan), 'ptwDisetujui', SUM(ptw_disetujui),
            'hseMeeting', SUM(hse_meeting), 'mwt', SUM(mwt), 'auditSelesai', SUM(audit)
        )
    INTO v_bulan, v_ytd
    FROM rows;

    -- Rata-rata skor inspeksi setahun (bukan rata-rata dari rata-rata bulanan)
    v_ytd := v_ytd || jsonb_build_object('inspeksiSkorRata', (
        SELECT ROUND(AVG("SkorPersen"), 1) FROM "inspeksiTbl"
        WHERE EXTRACT(YEAR FROM "TanggalWaktu") = p_tahun AND (v_ids IS NULL OR "ProjectId" = ANY(v_ids))
    ));

    -- Rolling 12 bulan
    WITH mh AS (
        SELECT COALESCE(SUM(COALESCE("ManHoursKoreksi", "ManHoursSmartGate")), 0) AS man_hours
        FROM "manHoursTbl"
        WHERE make_date("Tahun", "Bulan", 1) BETWEEN v_awal AND v_akhir
          AND (v_ids IS NULL OR "ProjectId" = ANY(v_ids))
    ),
    inc AS (
        SELECT COUNT(*) FILTER (WHERE "Klasifikasi" IN ('Medical Treatment Case', 'Restricted Work Case', 'Lost Time Injury', 'Fatality')) AS rec,
               COUNT(*) FILTER (WHERE "Klasifikasi" IN ('Lost Time Injury', 'Fatality')) AS lti,
               COALESCE(SUM("HariKerjaHilang") FILTER (WHERE "Klasifikasi" IN ('Restricted Work Case', 'Lost Time Injury', 'Fatality')), 0) AS hari
        FROM "incidentTbl"
        WHERE "TanggalWaktu" >= v_awal AND "TanggalWaktu" < (v_akhir + INTERVAL '1 month')
          AND (v_ids IS NULL OR "ProjectId" = ANY(v_ids))
    )
    SELECT jsonb_build_object(
        'dari', to_char(v_awal, 'YYYY-MM'), 'sampai', to_char(v_akhir, 'YYYY-MM'),
        'manHours', mh.man_hours, 'recordable', inc.rec, 'ltiFatality', inc.lti, 'hariHilang', inc.hari,
        'trir', CASE WHEN mh.man_hours > 0 THEN ROUND(inc.rec * v_basis / mh.man_hours, 2) END,
        'ltifr', CASE WHEN mh.man_hours > 0 THEN ROUND(inc.lti * v_basis / mh.man_hours, 2) END,
        'severityRate', CASE WHEN mh.man_hours > 0 THEN ROUND(inc.hari * v_basis / mh.man_hours, 2) END
    )
    INTO v_rolling
    FROM mh, inc;

    -- Klasifikasi incident setahun
    SELECT COALESCE(jsonb_object_agg(k, COALESCE(c.jml, 0)), '{}'::jsonb)
    INTO v_klas
    FROM unnest(ARRAY['Near Miss', 'First Aid Case', 'Medical Treatment Case', 'Restricted Work Case',
                      'Lost Time Injury', 'Fatality', 'Kerusakan Properti', 'Lingkungan', 'Keamanan/Security']) k
    LEFT JOIN (
        SELECT "Klasifikasi", COUNT(*) AS jml FROM "incidentTbl"
        WHERE EXTRACT(YEAR FROM "TanggalWaktu") = p_tahun AND (v_ids IS NULL OR "ProjectId" = ANY(v_ids))
        GROUP BY 1
    ) c ON c."Klasifikasi" = k;

    -- Temuan / tindak lanjut dari laporan tahun ini
    SELECT jsonb_build_array(
        (SELECT jsonb_build_object('modul', 'CERMAT (negatif)',
                'total', COUNT(*), 'closed', COUNT(*) FILTER (WHERE "Status" = 'Closed'),
                'open', COUNT(*) FILTER (WHERE "Status" <> 'Closed'),
                'overdue', COUNT(*) FILTER (WHERE "Status" <> 'Closed' AND "Tenggat" < CURRENT_DATE))
         FROM "cermatTbl"
         WHERE "Sifat" = 'Negatif' AND EXTRACT(YEAR FROM "TanggalWaktu") = p_tahun
           AND (v_ids IS NULL OR "ProjectId" = ANY(v_ids))),
        (SELECT jsonb_build_object('modul', 'Incident',
                'total', COUNT(*), 'closed', COUNT(*) FILTER (WHERE "Status" = 'Closed'),
                'open', COUNT(*) FILTER (WHERE "Status" <> 'Closed'),
                'overdue', COUNT(*) FILTER (WHERE "Status" <> 'Closed' AND "Tenggat" < CURRENT_DATE))
         FROM "incidentTbl"
         WHERE EXTRACT(YEAR FROM "TanggalWaktu") = p_tahun
           AND (v_ids IS NULL OR "ProjectId" = ANY(v_ids))),
        (SELECT jsonb_build_object('modul', 'Internal Audit (NC)',
                'total', COUNT(*),
                'closed', COUNT(*) FILTER (WHERE t->'capa'->>'status' = 'Ditutup'),
                'open', COUNT(*) FILTER (WHERE COALESCE(t->'capa'->>'status', 'Open') <> 'Ditutup'),
                'overdue', COUNT(*) FILTER (WHERE COALESCE(t->'capa'->>'status', 'Open') <> 'Ditutup'
                                             AND NULLIF(t->'capa'->>'tenggat', '')::DATE < CURRENT_DATE))
         FROM "auditTbl" a
         CROSS JOIN LATERAL jsonb_array_elements(COALESCE(a."TemuanList", '[]'::jsonb)) t
         WHERE t->>'hasil' = 'Tidak Sesuai'
           AND EXTRACT(YEAR FROM COALESCE(a."TanggalPelaksanaan", a."CreatedAt")) = p_tahun
           AND (v_ids IS NULL OR a."ProjectId" = ANY(v_ids)))
    ) INTO v_temuan;

    -- LTI / Fatality terakhir (semua tahun)
    SELECT jsonb_build_object(
        'tanggal', x.tgl,
        'hari', CASE WHEN x.tgl IS NOT NULL THEN (CURRENT_DATE - x.tgl::DATE) END,
        'manHoursSejak', CASE WHEN x.tgl IS NOT NULL THEN (
            SELECT COALESCE(SUM(COALESCE("ManHoursKoreksi", "ManHoursSmartGate")), 0)
            FROM "manHoursTbl"
            WHERE make_date("Tahun", "Bulan", 1) > date_trunc('month', x.tgl)::DATE
              AND (v_ids IS NULL OR "ProjectId" = ANY(v_ids))
        ) END
    ) INTO v_lti
    FROM (
        SELECT MAX("TanggalWaktu") AS tgl FROM "incidentTbl"
        WHERE "Klasifikasi" IN ('Lost Time Injury', 'Fatality')
          AND (v_ids IS NULL OR "ProjectId" = ANY(v_ids))
    ) x;

    RETURN jsonb_build_object(
        'projectId', p_project_id,
        'scope', CASE WHEN p_project_id IS NOT NULL THEN 'PROJECT' ELSE upper(COALESCE(p_scope, 'ALL')) END,
        'tahun', p_tahun,
        'basis', v_basis,
        'bulan', v_bulan,
        'ytd', v_ytd,
        'rolling12', v_rolling,
        'klasifikasi', v_klas,
        'temuan', v_temuan,
        'ltiTerakhir', v_lti,
        'dihitungPada', NOW()
    );
END;
$$;
GRANT EXECUTE ON FUNCTION public.get_statistik_kpi(BIGINT, INT, NUMERIC, TEXT) TO anon, authenticated;

-- get_statistik_piramida (dari 058) + p_scope
DROP FUNCTION IF EXISTS public.get_statistik_piramida(BIGINT, INT, INT, INT);
DROP FUNCTION IF EXISTS public.get_statistik_piramida(BIGINT, INT, INT, INT, TEXT);
CREATE OR REPLACE FUNCTION public.get_statistik_piramida(
    p_project_id BIGINT,
    p_tahun INT,
    p_bulan_dari INT DEFAULT 1,
    p_bulan_sampai INT DEFAULT 12,
    p_scope TEXT DEFAULT 'ALL'
)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_ids BIGINT[] := public.hsse_scope_project_ids(p_project_id, p_scope);
    v_dari INT := LEAST(GREATEST(COALESCE(p_bulan_dari, 1), 1), 12);
    v_sampai INT := LEAST(GREATEST(COALESCE(p_bulan_sampai, 12), 1), 12);
    v_awal TIMESTAMPTZ;
    v_akhir TIMESTAMPTZ;
    v_inc RECORD;
    v_cer RECORD;
    v_ins RECORD;
BEGIN
    IF v_dari > v_sampai THEN
        v_dari := v_sampai;
    END IF;
    v_awal := make_date(p_tahun, v_dari, 1)::TIMESTAMPTZ;
    v_akhir := (make_date(p_tahun, v_sampai, 1) + INTERVAL '1 month')::TIMESTAMPTZ;

    SELECT COUNT(*) FILTER (WHERE "Klasifikasi" = 'Fatality') AS fatality,
           COUNT(*) FILTER (WHERE "Klasifikasi" = 'Lost Time Injury') AS lti,
           COUNT(*) FILTER (WHERE "Klasifikasi" = 'Restricted Work Case') AS rwc,
           COUNT(*) FILTER (WHERE "Klasifikasi" = 'Medical Treatment Case') AS mtc,
           COUNT(*) FILTER (WHERE "Klasifikasi" = 'First Aid Case') AS fac,
           COUNT(*) FILTER (WHERE "Klasifikasi" = 'Near Miss') AS near_miss,
           COUNT(*) FILTER (WHERE "Klasifikasi" = 'Kerusakan Properti') AS properti,
           COUNT(*) FILTER (WHERE "Klasifikasi" = 'Lingkungan') AS lingkungan,
           COUNT(*) FILTER (WHERE "Klasifikasi" = 'Keamanan/Security') AS keamanan
    INTO v_inc
    FROM "incidentTbl"
    WHERE "TanggalWaktu" >= v_awal AND "TanggalWaktu" < v_akhir
      AND (v_ids IS NULL OR "ProjectId" = ANY(v_ids));

    SELECT COUNT(*) FILTER (WHERE "JenisTemuan" = 'Near Miss') AS near_miss,
           COUNT(*) FILTER (WHERE "Sifat" = 'Negatif' AND COALESCE("JenisTemuan", '') <> 'Near Miss'
                              AND "SourceInspeksiId" IS NULL) AS unsafe,
           COUNT(*) FILTER (WHERE "Sifat" = 'Negatif' AND COALESCE("JenisTemuan", '') <> 'Near Miss'
                              AND "SourceInspeksiId" IS NOT NULL) AS dari_inspeksi
    INTO v_cer
    FROM "cermatTbl"
    WHERE "TanggalWaktu" >= v_awal AND "TanggalWaktu" < v_akhir
      AND (v_ids IS NULL OR "ProjectId" = ANY(v_ids));

    SELECT COUNT(*) AS jml, COALESCE(SUM("JumlahTidakSesuai"), 0) AS tidak_sesuai
    INTO v_ins
    FROM "inspeksiTbl"
    WHERE "TanggalWaktu" >= v_awal AND "TanggalWaktu" < v_akhir
      AND (v_ids IS NULL OR "ProjectId" = ANY(v_ids));

    RETURN jsonb_build_object(
        'projectId', p_project_id,
        'scope', CASE WHEN p_project_id IS NOT NULL THEN 'PROJECT' ELSE upper(COALESCE(p_scope, 'ALL')) END,
        'tahun', p_tahun,
        'bulanDari', v_dari,
        'bulanSampai', v_sampai,
        'lapisan', jsonb_build_array(
            jsonb_build_object('kode', 'FAT', 'nama', 'Fatality', 'jumlah', v_inc.fatality),
            jsonb_build_object('kode', 'LTI', 'nama', 'Lost Time Injury', 'jumlah', v_inc.lti),
            jsonb_build_object('kode', 'RWC', 'nama', 'Restricted Work Case', 'jumlah', v_inc.rwc),
            jsonb_build_object('kode', 'MTC', 'nama', 'Medical Treatment Case', 'jumlah', v_inc.mtc),
            jsonb_build_object('kode', 'FAC', 'nama', 'First Aid Case', 'jumlah', v_inc.fac),
            jsonb_build_object('kode', 'NM', 'nama', 'Near Miss', 'jumlah', v_inc.near_miss + v_cer.near_miss,
                               'rincian', jsonb_build_object('incident', v_inc.near_miss, 'cermat', v_cer.near_miss)),
            jsonb_build_object('kode', 'UA', 'nama', 'Unsafe Act / Unsafe Condition', 'jumlah', v_cer.unsafe + v_ins.tidak_sesuai,
                               'rincian', jsonb_build_object('cermat', v_cer.unsafe, 'inspeksi', v_ins.tidak_sesuai))
        ),
        'diLuarPiramida', jsonb_build_object(
            'kerusakanProperti', v_inc.properti,
            'lingkungan', v_inc.lingkungan,
            'keamanan', v_inc.keamanan
        ),
        'info', jsonb_build_object(
            'jumlahInspeksi', v_ins.jml,
            'cermatDariInspeksi', v_cer.dari_inspeksi
        ),
        'dihitungPada', NOW()
    );
END;
$$;
GRANT EXECUTE ON FUNCTION public.get_statistik_piramida(BIGINT, INT, INT, INT, TEXT) TO anon, authenticated;

-- -------------------------------------------------------------------------------------
-- 6. Sinkron pertama (kalau SmartGate gak bisa dihubungi, migrasi tetap jadi; nanti
--    sinkron lagi otomatis jam 01:00 WIB atau pas klik "Tarik dari SmartGate").
-- -------------------------------------------------------------------------------------
DO $$
DECLARE v JSONB;
BEGIN
    v := public.project_sinkron_smartgate('Migrasi 060');
    RAISE NOTICE 'Sinkron project SmartGate: %', v;
EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'Sinkron project SmartGate GAGAL (gak apa-apa, nanti dicoba lagi): %', SQLERRM;
END $$;

-- -------------------------------------------------------------------------------------
-- CEK (jalanin manual kalau mau):
-- 1. Project HSSE + kodenya:
--      SELECT "Id", "KodeOperational", "NamaProject", "NoKontrak", "TipeProject", "Status"
--      FROM "projectTbl" ORDER BY "KodeOperational";
-- 2. Sinkron ulang sekarang:
--      SELECT public.project_sinkron_smartgate('manual SQL');
-- 3. Tarik man-hours sekarang (sekalian sinkron project):
--      SELECT public.man_hours_tarik_otomatis(true);
-- 4. Statistik per scope:
--      SELECT public.get_statistik_kpi(NULL, 2026, 1000000, 'ALL_PROJECT')->'ytd'->'manHours';
--      SELECT public.get_statistik_kpi(NULL, 2026, 1000000, 'CORPORATE')->'ytd'->'manHours';
--      SELECT public.get_statistik_kpi(NULL, 2026, 1000000, 'ALL')->'ytd'->'manHours';
-- -------------------------------------------------------------------------------------
