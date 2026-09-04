-- Jalankan di Supabase project FUSION4 (nhmpwjriextmbotmvvbu.supabase.co), BUKAN HSSE-Fusion4.
-- Template UNIVERSAL buat kasih Author tag "Leader HSE Meeting" ke SIAPAPUN -- tinggal ganti
-- 'NAMA_KARYAWAN' di 3 tempat di bawah (SELECT-UPDATE-SELECT) sama nama orangnya.
-- Aman dijalankan berkali-kali (gak bakal dobel tag), dan gak menghapus tag Author lain yang
-- udah dia punya sebelumnya (misal udah punya "Permit & JSA", nanti jadi gabungan keduanya).

-- 1) Cek dulu kondisi Author-nya sekarang.
SELECT "NamaPersonnel", "QrCodeId", "Author", "DigitalPIN"
FROM "karyawanTbl"
WHERE "NamaPersonnel" ILIKE '%NAMA_KARYAWAN%';

-- 2) Tambahin tag "Leader HSE Meeting".
UPDATE "karyawanTbl"
SET "Author" = CASE
    WHEN "Author" IS NULL OR TRIM("Author") = '' THEN 'Leader HSE Meeting'
    WHEN "Author" ILIKE '%Leader HSE Meeting%' THEN "Author"
    ELSE "Author" || ', Leader HSE Meeting'
END
WHERE "NamaPersonnel" ILIKE '%NAMA_KARYAWAN%';

-- 3) Cek hasilnya.
SELECT "NamaPersonnel", "QrCodeId", "Author", "DigitalPIN"
FROM "karyawanTbl"
WHERE "NamaPersonnel" ILIKE '%NAMA_KARYAWAN%';
