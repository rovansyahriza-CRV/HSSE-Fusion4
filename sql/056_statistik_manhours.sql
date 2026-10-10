-- =====================================================================================
-- MIGRASI #056 (HSSE): tabel man-hours buat modul Statistik & KPI
-- Jalankan di Supabase project **HSSE-Fusion4**, SETELAH 001-050.
-- Aman dijalankan ulang (IF NOT EXISTS / CREATE OR REPLACE).
--
-- Alur:
--   1. PIC "HSSE-STA" buka statistik-kpi-input.html, klik "Tarik dari SmartGate".
--      Halaman manggil RPC Fusion4 get_hsse_man_hours (sql/for-FUSION4_man_hours_rpc.sql) -> dapat angka per
--      LOKASI absensi per bulan -> dikirim ke save_man_hours_smartgate di sini.
--   2. Tiap lokasi absensi SmartGate dipetakan ke projectTbl HSSE lewat
--      manHoursProjectMapTbl (master lokasi Fusion4 gak nyimpen project). Lokasi yang
--      namanya sama persis dengan NamaProject / NoKontrak otomatis kepetakan; sisanya
--      dipilih manual di halaman input. Beberapa lokasi boleh ke 1 project.
--   3. Kalau angka SmartGate kurang (misal subkon gak lewat gate), PIC isi koreksi +
--      alasan per project per bulan. Angka final = koreksi kalau diisi, kalau nggak
--      angka SmartGate.
--   4. Semua tarik & koreksi dicatat di manHoursLogTbl (jejak audit).
-- Tabel dikunci dari akses langsung (pola sama kayak Management Review #046), semua
-- baca/tulis lewat RPC.
-- =====================================================================================

CREATE TABLE IF NOT EXISTS "manHoursProjectMapTbl" (
    "LokasiSmartGate" TEXT PRIMARY KEY,
    "ProjectId" BIGINT REFERENCES "projectTbl"("Id"),
    "DiubahOleh" TEXT DEFAULT '',
    "UpdatedAt" TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS "manHoursTbl" (
    "Id" BIGSERIAL PRIMARY KEY,
    "ProjectId" BIGINT NOT NULL REFERENCES "projectTbl"("Id"),
    "Tahun" INT NOT NULL,
    "Bulan" INT NOT NULL CHECK ("Bulan" BETWEEN 1 AND 12),
    "ManHoursSmartGate" NUMERIC NOT NULL DEFAULT 0,
    "JumlahPekerjaSmartGate" INT NOT NULL DEFAULT 0,
    "HariOrangSmartGate" INT NOT NULL DEFAULT 0,
    "BarisEstimasi" INT NOT NULL DEFAULT 0,
    "TanggalTarik" TIMESTAMPTZ,
    "ManHoursKoreksi" NUMERIC,
    "JumlahPekerjaKoreksi" INT,
    "AlasanKoreksi" TEXT DEFAULT '',
    "DiubahOleh" TEXT DEFAULT '',
    "DiubahQrCodeId" TEXT DEFAULT '',
    "UpdatedAt" TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE ("ProjectId", "Tahun", "Bulan")
);
CREATE INDEX IF NOT EXISTS idx_manhours_tahun ON "manHoursTbl" ("Tahun", "Bulan");

CREATE TABLE IF NOT EXISTS "manHoursLogTbl" (
    "Id" BIGSERIAL PRIMARY KEY,
    "Aksi" TEXT NOT NULL,              -- 'Tarik SmartGate' | 'Koreksi' | 'Hapus Koreksi' | 'Mapping'
    "ProjectId" BIGINT,
    "Tahun" INT,
    "Bulan" INT,
    "Detail" JSONB NOT NULL DEFAULT '{}'::jsonb,
    "Oleh" TEXT DEFAULT '',
    "OlehQrCodeId" TEXT DEFAULT '',
    "CreatedAt" TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE "manHoursProjectMapTbl" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "manHoursTbl" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "manHoursLogTbl" ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS manhours_map_no_direct ON "manHoursProjectMapTbl";
DROP POLICY IF EXISTS manhours_no_direct ON "manHoursTbl";
DROP POLICY IF EXISTS manhours_log_no_direct ON "manHoursLogTbl";
CREATE POLICY manhours_map_no_direct ON "manHoursProjectMapTbl" FOR ALL TO anon, authenticated USING (false) WITH CHECK (false);
CREATE POLICY manhours_no_direct ON "manHoursTbl" FOR ALL TO anon, authenticated USING (false) WITH CHECK (false);
CREATE POLICY manhours_log_no_direct ON "manHoursLogTbl" FOR ALL TO anon, authenticated USING (false) WITH CHECK (false);

-- -------------------------------------------------------------------------------------
-- Mapping lokasi absensi SmartGate -> project HSSE
-- -------------------------------------------------------------------------------------
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
        'projectId', m."ProjectId",
        'namaProject', p."NamaProject",
        'noKontrak', p."NoKontrak",
        'diubahOleh', m."DiubahOleh",
        'updatedAt', m."UpdatedAt"
    ) ORDER BY (m."ProjectId" IS NOT NULL), m."LokasiSmartGate"), '[]'::jsonb)
    FROM "manHoursProjectMapTbl" m
    LEFT JOIN "projectTbl" p ON p."Id" = m."ProjectId";
$$;

DROP FUNCTION IF EXISTS public.save_man_hours_project_map(TEXT, BIGINT, TEXT, TEXT);
CREATE OR REPLACE FUNCTION public.save_man_hours_project_map(
    p_lokasi TEXT,
    p_project_id BIGINT,
    p_nama TEXT,
    p_qr TEXT DEFAULT ''
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
    INSERT INTO "manHoursProjectMapTbl" ("LokasiSmartGate", "ProjectId", "DiubahOleh", "UpdatedAt")
    VALUES (trim(p_lokasi), p_project_id, p_nama, NOW())
    ON CONFLICT ("LokasiSmartGate") DO UPDATE
        SET "ProjectId" = EXCLUDED."ProjectId", "DiubahOleh" = EXCLUDED."DiubahOleh", "UpdatedAt" = NOW();
    INSERT INTO "manHoursLogTbl" ("Aksi", "ProjectId", "Detail", "Oleh", "OlehQrCodeId")
    VALUES ('Mapping', p_project_id, jsonb_build_object('lokasiSmartGate', trim(p_lokasi)), p_nama, COALESCE(p_qr, ''));
    RETURN jsonb_build_object('ok', true);
END;
$$;

-- -------------------------------------------------------------------------------------
-- Simpan hasil tarik SmartGate untuk 1 tahun.
-- p_rows = hasil get_hsse_man_hours (Fusion4) apa adanya:
--   [{ "Lokasi", "Bulan", "JumlahPekerja", "HariOrang", "ManHours", "BarisEstimasi" }, ...]
-- Angka SmartGate tahun itu di-reset dulu (koreksi manual TETAP disimpan), lalu diisi
-- ulang. Kalau beberapa lokasi dipetakan ke 1 project HSSE, angkanya dijumlah.
-- -------------------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.save_man_hours_smartgate(INT, JSONB, TEXT, TEXT);
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
DECLARE
    v_unmapped JSONB;
    v_count INT;
BEGIN
    IF COALESCE(trim(p_nama), '') = '' THEN
        RAISE EXCEPTION 'Verifikasi PIC dulu.';
    END IF;
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

    UPDATE "manHoursTbl"
    SET "ManHoursSmartGate" = 0, "JumlahPekerjaSmartGate" = 0, "HariOrangSmartGate" = 0,
        "BarisEstimasi" = 0, "TanggalTarik" = NOW(), "UpdatedAt" = NOW()
    WHERE "Tahun" = p_tahun;

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

    INSERT INTO "manHoursLogTbl" ("Aksi", "Tahun", "Detail", "Oleh", "OlehQrCodeId")
    VALUES ('Tarik SmartGate', p_tahun,
            jsonb_build_object('barisDiterima', jsonb_array_length(p_rows), 'barisDisimpan', v_count, 'belumDipetakan', v_unmapped),
            p_nama, COALESCE(p_qr, ''));

    RETURN jsonb_build_object('ok', true, 'barisDisimpan', v_count, 'belumDipetakan', v_unmapped);
END;
$$;

-- -------------------------------------------------------------------------------------
-- Koreksi manual per project per bulan. p_man_hours NULL = hapus koreksi (balik ke SmartGate).
-- -------------------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.save_man_hours_koreksi(BIGINT, INT, INT, NUMERIC, INT, TEXT, TEXT, TEXT);
CREATE OR REPLACE FUNCTION public.save_man_hours_koreksi(
    p_project_id BIGINT,
    p_tahun INT,
    p_bulan INT,
    p_man_hours NUMERIC,
    p_jumlah_pekerja INT,
    p_alasan TEXT,
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
    IF p_bulan NOT BETWEEN 1 AND 12 THEN
        RAISE EXCEPTION 'Bulan gak valid.';
    END IF;
    IF p_man_hours IS NOT NULL AND p_man_hours < 0 THEN
        RAISE EXCEPTION 'Man-hours gak boleh minus.';
    END IF;
    IF p_man_hours IS NOT NULL AND COALESCE(trim(p_alasan), '') = '' THEN
        RAISE EXCEPTION 'Alasan koreksi wajib diisi.';
    END IF;

    INSERT INTO "manHoursTbl" ("ProjectId", "Tahun", "Bulan", "ManHoursKoreksi", "JumlahPekerjaKoreksi",
        "AlasanKoreksi", "DiubahOleh", "DiubahQrCodeId", "UpdatedAt")
    VALUES (p_project_id, p_tahun, p_bulan, p_man_hours,
        CASE WHEN p_man_hours IS NULL THEN NULL ELSE p_jumlah_pekerja END,
        CASE WHEN p_man_hours IS NULL THEN '' ELSE trim(p_alasan) END,
        p_nama, COALESCE(p_qr, ''), NOW())
    ON CONFLICT ("ProjectId", "Tahun", "Bulan") DO UPDATE SET
        "ManHoursKoreksi" = EXCLUDED."ManHoursKoreksi",
        "JumlahPekerjaKoreksi" = EXCLUDED."JumlahPekerjaKoreksi",
        "AlasanKoreksi" = EXCLUDED."AlasanKoreksi",
        "DiubahOleh" = EXCLUDED."DiubahOleh",
        "DiubahQrCodeId" = EXCLUDED."DiubahQrCodeId",
        "UpdatedAt" = NOW();

    INSERT INTO "manHoursLogTbl" ("Aksi", "ProjectId", "Tahun", "Bulan", "Detail", "Oleh", "OlehQrCodeId")
    VALUES (CASE WHEN p_man_hours IS NULL THEN 'Hapus Koreksi' ELSE 'Koreksi' END,
            p_project_id, p_tahun, p_bulan,
            jsonb_build_object('manHours', p_man_hours, 'jumlahPekerja', p_jumlah_pekerja, 'alasan', p_alasan),
            p_nama, COALESCE(p_qr, ''));
    RETURN jsonb_build_object('ok', true);
END;
$$;

-- -------------------------------------------------------------------------------------
-- Baca man-hours (1 project atau semua project kalau p_project_id NULL)
-- -------------------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.get_man_hours(BIGINT, INT);
CREATE OR REPLACE FUNCTION public.get_man_hours(p_project_id BIGINT, p_tahun INT)
RETURNS JSONB
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'projectId', m."ProjectId",
        'namaProject', p."NamaProject",
        'tahun', m."Tahun",
        'bulan', m."Bulan",
        'manHoursSmartGate', m."ManHoursSmartGate",
        'jumlahPekerjaSmartGate', m."JumlahPekerjaSmartGate",
        'hariOrangSmartGate', m."HariOrangSmartGate",
        'barisEstimasi', m."BarisEstimasi",
        'tanggalTarik', m."TanggalTarik",
        'manHoursKoreksi', m."ManHoursKoreksi",
        'jumlahPekerjaKoreksi', m."JumlahPekerjaKoreksi",
        'alasanKoreksi', m."AlasanKoreksi",
        'manHoursFinal', COALESCE(m."ManHoursKoreksi", m."ManHoursSmartGate"),
        'jumlahPekerjaFinal', COALESCE(m."JumlahPekerjaKoreksi", m."JumlahPekerjaSmartGate"),
        'diubahOleh', m."DiubahOleh",
        'updatedAt', m."UpdatedAt"
    ) ORDER BY m."ProjectId", m."Bulan"), '[]'::jsonb)
    FROM "manHoursTbl" m
    JOIN "projectTbl" p ON p."Id" = m."ProjectId"
    WHERE m."Tahun" = p_tahun AND (p_project_id IS NULL OR m."ProjectId" = p_project_id);
$$;

DROP FUNCTION IF EXISTS public.get_man_hours_log(INT);
CREATE OR REPLACE FUNCTION public.get_man_hours_log(p_limit INT DEFAULT 50)
RETURNS JSONB
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT COALESCE(jsonb_agg(x ORDER BY (x->>'createdAt') DESC), '[]'::jsonb)
    FROM (
        SELECT jsonb_build_object('aksi', l."Aksi", 'projectId', l."ProjectId", 'tahun', l."Tahun", 'bulan', l."Bulan",
                                  'detail', l."Detail", 'oleh', l."Oleh", 'createdAt', l."CreatedAt") AS x
        FROM "manHoursLogTbl" l
        ORDER BY l."CreatedAt" DESC
        LIMIT LEAST(GREATEST(COALESCE(p_limit, 50), 1), 500)
    ) s;
$$;
