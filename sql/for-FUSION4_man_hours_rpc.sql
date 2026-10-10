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
--   Master lokasi Fusion4 gak nyimpen project, jadi tiap lokasi dipetakan ke project
--   HSSE di halaman statistik-kpi-input.html.
-- =====================================================================================

DROP FUNCTION IF EXISTS public.get_hsse_man_hours(INT, INT, NUMERIC);

CREATE OR REPLACE FUNCTION public.get_hsse_man_hours(
    p_tahun INT,
    p_bulan INT DEFAULT NULL,
    p_jam_standar NUMERIC DEFAULT 8
)
RETURNS TABLE (
    "Lokasi" TEXT,
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
            COALESCE(NULLIF(trim(l."NamaLokasi"), ''), NULLIF(j.lok, ''), '(Tanpa Lokasi)') AS lokasi,
            EXTRACT(MONTH FROM j."Tanggal")::INT AS bulan,
            j."QrCodeId",
            LEAST(GREATEST(COALESCE(j.jam_hitung, p_jam_standar), 0), 24) AS jam,
            (j.jam_hitung IS NULL) AS estimasi
        FROM j
        LEFT JOIN LATERAL (
            SELECT lt."NamaLokasi"
            FROM "lokasiTbl" lt
            WHERE j.lok IS NOT NULL
              AND (lower(trim(lt."NamaLokasi")) = lower(j.lok) OR lower(trim(lt."KodeLokasi")) = lower(j.lok))
            ORDER BY (lower(trim(lt."NamaLokasi")) = lower(j.lok)) DESC, lt."Id"
            LIMIT 1
        ) l ON TRUE
    )
    SELECT
        lokasi,
        p_tahun,
        bulan,
        COUNT(DISTINCT "QrCodeId")::INT,
        COUNT(*)::INT,
        ROUND(SUM(jam)::NUMERIC, 1),
        COUNT(*) FILTER (WHERE estimasi)::INT
    FROM k
    GROUP BY lokasi, bulan
    ORDER BY lokasi, bulan;
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
-- 2. Hasil RPC tahun ini:
-- SELECT * FROM public.get_hsse_man_hours(EXTRACT(YEAR FROM CURRENT_DATE)::INT);
-- -------------------------------------------------------------------------------------
