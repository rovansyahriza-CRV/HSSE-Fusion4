-- Jalankan di Supabase project FUSION4 (nhmpwjriextmbotmvvbu.supabase.co), BUKAN HSSE-Fusion4.
-- Template UNIVERSAL buat kasih Author tag "Admin MWT" ke SIAPAPUN -- tinggal ganti
-- 'NAMA_KARYAWAN' di 3 tempat di bawah (SELECT-UPDATE-SELECT) sama nama orangnya (biasanya
-- HSE Admin / koordinator HSE yang bikin jadwal MWT, BUKAN yang isi kunjungannya -- itu
-- pakai tag "Management Walkthrough", lihat template-grant-author-management-walkthrough.sql).
-- Aman dijalankan berkali-kali (gak bakal dobel tag), dan gak menghapus tag Author lain yang
-- udah dia punya sebelumnya.

-- 1) Cek dulu kondisi Author-nya sekarang.
SELECT "NamaPersonnel", "QrCodeId", "Author", "DigitalPIN"
FROM "karyawanTbl"
WHERE "NamaPersonnel" ILIKE '%NAMA_KARYAWAN%';

-- 2) Tambahin tag "Admin MWT".
UPDATE "karyawanTbl"
SET "Author" = CASE
    WHEN "Author" IS NULL OR TRIM("Author") = '' THEN 'Admin MWT'
    WHEN "Author" ILIKE '%Admin MWT%' THEN "Author"
    ELSE "Author" || ', Admin MWT'
END
WHERE "NamaPersonnel" ILIKE '%NAMA_KARYAWAN%';

-- 3) Cek hasilnya.
SELECT "NamaPersonnel", "QrCodeId", "Author", "DigitalPIN"
FROM "karyawanTbl"
WHERE "NamaPersonnel" ILIKE '%NAMA_KARYAWAN%';
