-- =====================================================================================
-- MIGRASI for-FUSION4 (dulu #052 di paket): RPC man-hours bulanan per LOKASI absensi buat modul Statistik HSSE
-- Jalankan di Supabase project **FUSION4 SmartGate** (bukan HSSE).
-- Aman dijalankan ulang (CREATE OR REPLACE). READ ONLY: gak ngubah tabel apa pun.
--
-- Yang dikeluarin cuma ANGKA AGREGAT per lokasi per bulan (jumlah orang, jam kerja).
-- Gak ada nama, QR, PIN, atau data pribadi yang keluar.
--
-- Cara hitung jam kerja per baris absensiTbl (1 orang 1 hari):
--   a. 4 scan lengkap (Masuk1, Istirahat, Masuk2, Pulang) dan urut:
--        (Istirahat - Masuk1) + (Pulang - Masuk2)
--   b. Ada Masuk1 & Pulang tapi scan istirahat gak lengkap:
--        (Pulang - Masuk1), dipotong 1 jam istirahat kalau lebih dari 5 jam
--   c. Cuma ada Masuk1 (lupa scan pulang):
--        p_jam_standar (default 8 jam) -- dihitung sebagai "BarisEstimasi"
--   Hasil per hari dibatasi 0..24 jam. Lembur udah ikut kehitung otomatis kalau
--   orangnya scan pulang lebih telat (pengajuan lembur TIDAK ditambah lagi biar gak dobel).
--   Baris tanpa JamMasuk1 (izin/sakit/cuti/alpha) gak dihitung.
--
-- Lokasi:
--   Lokasi scan diambil dari LokasiMasuk1 (isinya Nama Lokasi; kalau kosong: LokasiMasuk2
--   -> LokasiPulang -> LokasiIstirahat). Kalau cocok sama lokasiTbl.NamaLokasi /
--   KodeLokasi, dipakai NamaLokasi resminya (biar beda huruf besar/kecil gak pecah jadi
--   2 lokasi). Kalau gak cocok, dipakai teks aslinya. Kosong -> '(Tanpa Lokasi)'.
--
-- Kode project ("KodeProject", Operational Code 014, 015, 901...):
--   Diambil dari kolom TYPE karyawan (karyawanTbl."Type", dicocokkan lewat QrCodeId tanpa
--   peduli huruf besar/kecil). Kalau karyawannya gak ketemu / TYPE kosong, pakai kode
--   project lokasi scan (lokasiTbl."Project"). HSSE (migrasi #060/#061) masukin man-hours
--   ke project HSSE dengan kode yang sama.
--   Update 2026-10-12: tambah "KodeProject"; versi kedua: ikut TYPE karyawan dulu.
--   Versi ketiga: baris karyawan ber-TYPE keluar dengan "Lokasi" NULL (dikelompokkan per kode +
--   bulan), biar "JumlahPekerja" gak dobel waktu orang yang sama scan di beberapa lokasi.
-- =====================================================================================

DROP FUNCTION IF EXISTS public.get_hsse_man_hours(INT, INT, NUMERIC);

CREATE OR REPLACE FUNCTION public.get_hsse_man_hours(
    p_tahun INT,
    p_bulan INT DEFAULT NULL,
    p_jam_standar NUMERIC DEFAULT 8
)
RETURNS TABLE (
    "Lokasi" TEXT,
    "KodeProject" TEXT,
    "Tahun" INT,
    "Bulan" INT,
    "JumlahPekerja" INT,
    "HariOrang" INT,
    "ManHours" NUMERIC,
    "BarisEstimasi" INT
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    WITH a AS (
        SELECT
            ab."Tanggal",
            ab."QrCodeId",
            ab."JamMasuk1"   AS m1,
            ab."JamIstirahat" AS ist,
            ab."JamMasuk2"   AS m2,
            ab."JamPulang"   AS pl,
            trim(COALESCE(
                NULLIF(trim(ab."LokasiMasuk1"), ''),
                NULLIF(trim(ab."LokasiMasuk2"), ''),
                NULLIF(trim(ab."LokasiPulang"), ''),
                NULLIF(trim(ab."LokasiIstirahat"), '')
            )) AS lok
        FROM "absensiTbl" ab
        WHERE ab."JamMasuk1" IS NOT NULL
          AND EXTRACT(YEAR FROM ab."Tanggal") = p_tahun
          AND (p_bulan IS NULL OR EXTRACT(MONTH FROM ab."Tanggal") = p_bulan)
    ),
    j AS (
        SELECT
            a.*,
            CASE
                WHEN ist IS NOT NULL AND m2 IS NOT NULL AND pl IS NOT NULL
                     AND ist > m1 AND m2 >= ist AND pl > m2
                    THEN EXTRACT(EPOCH FROM (ist - m1) + (pl - m2)) / 3600.0
                WHEN pl IS NOT NULL AND pl > m1
                    THEN EXTRACT(EPOCH FROM (pl - m1)) / 3600.0
                         - CASE WHEN EXTRACT(EPOCH FROM (pl - m1)) / 3600.0 > 5 THEN 1 ELSE 0 END
                ELSE NULL
            END AS jam_hitung
        FROM a
    ),
    k AS (
        SELECT
            -- Karyawan yang punya TYPE: lokasi dikosongin, jadi 1 orang dihitung sekali per kode per
            -- bulan walau scan di beberapa lokasi. Lokasi cuma dipakai buat yang gak punya TYPE.
            CASE WHEN NULLIF(trim(kr."Type"), '') IS NOT NULL THEN NULL
                 ELSE COALESCE(NULLIF(trim(l."NamaLokasi"), ''), NULLIF(j.lok, ''), '(Tanpa Lokasi)')
            END AS lokasi,
            COALESCE(NULLIF(trim(kr."Type"), ''), NULLIF(trim(l."Project"), '')) AS kode,
            EXTRACT(MONTH FROM j."Tanggal")::INT AS bulan,
            j."QrCodeId",
            LEAST(GREATEST(COALESCE(j.jam_hitung, p_jam_standar), 0), 24) AS jam,
            (j.jam_hitung IS NULL) AS estimasi
        FROM j
        LEFT JOIN LATERAL (
            SELECT lt."NamaLokasi", lt."Project"
            FROM "lokasiTbl" lt
            WHERE j.lok IS NOT NULL
              AND (lower(trim(lt."NamaLokasi")) = lower(j.lok) OR lower(trim(lt."KodeLokasi")) = lower(j.lok))
            ORDER BY (lower(trim(lt."NamaLokasi")) = lower(j.lok)) DESC, lt."Id"
            LIMIT 1
        ) l ON TRUE
        LEFT JOIN LATERAL (
            SELECT kt."Type"
            FROM "karyawanTbl" kt
            WHERE upper(trim(kt."QrCodeId")) = upper(trim(j."QrCodeId"))
            ORDER BY (kt."QrCodeId" = j."QrCodeId") DESC, kt."IsActive" DESC NULLS LAST, kt."Id"
            LIMIT 1
        ) kr ON TRUE
    )
    SELECT
        lokasi,
        kode,
        p_tahun,
        bulan,
        COUNT(DISTINCT "QrCodeId")::INT,
        COUNT(*)::INT,
        ROUND(SUM(jam)::NUMERIC, 1),
        COUNT(*) FILTER (WHERE estimasi)::INT
    FROM k
    GROUP BY lokasi, kode, bulan
    ORDER BY kode, lokasi NULLS FIRST, bulan;
$$;

REVOKE ALL ON FUNCTION public.get_hsse_man_hours(INT, INT, NUMERIC) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_hsse_man_hours(INT, INT, NUMERIC) TO anon, authenticated;

-- -------------------------------------------------------------------------------------
-- CEK OPSIONAL (read only, jalanin manual kalau mau lihat):
-- 1. Lokasi scan tahun ini + cocok/gak sama master lokasi (cuma nama lokasi, bukan orang):
--
-- SELECT COALESCE(NULLIF(trim(ab."LokasiMasuk1"),''), '(kosong)') AS lokasi_scan,
--        (l."Id" IS NOT NULL) AS ada_di_master, COUNT(*) AS jumlah_baris
-- FROM "absensiTbl" ab
-- LEFT JOIN "lokasiTbl" l ON lower(trim(l."NamaLokasi")) = lower(trim(ab."LokasiMasuk1"))
-- WHERE ab."JamMasuk1" IS NOT NULL AND EXTRACT(YEAR FROM ab."Tanggal") = EXTRACT(YEAR FROM CURRENT_DATE)
-- GROUP BY 1, 2 ORDER BY 3 DESC;
--
-- 2. Man-hours per kode project tahun ini:
-- SELECT "KodeProject", SUM("ManHours") FROM public.get_hsse_man_hours(EXTRACT(YEAR FROM CURRENT_DATE)::INT) GROUP BY 1;
--
-- 3. Lokasi + kode project-nya:
-- SELECT "KodeLokasi", "NamaLokasi", "Project" FROM "lokasiTbl" ORDER BY "Project" NULLS LAST, "NamaLokasi";
--
-- 4. Hasil RPC tahun ini:
-- SELECT * FROM public.get_hsse_man_hours(EXTRACT(YEAR FROM CURRENT_DATE)::INT);
-- -------------------------------------------------------------------------------------
