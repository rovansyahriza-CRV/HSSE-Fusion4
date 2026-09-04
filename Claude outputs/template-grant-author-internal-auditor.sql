-- Jalankan di Supabase project FUSION4 (nhmpwjriextmbotmvvbu.supabase.co), BUKAN HSSE-Fusion4.
-- Template UNIVERSAL buat kasih Author tag "Internal Auditor" ke SIAPAPUN -- tinggal ganti
-- 'NAMA_KARYAWAN' di 3 tempat di bawah (SELECT-UPDATE-SELECT) sama nama orangnya.
-- Aman dijalankan berkali-kali (gak bakal dobel tag), dan gak menghapus tag Author lain yang
-- udah dia punya sebelumnya (misal udah punya "Leader HSE Meeting", nanti jadi gabungan keduanya).

-- 1) Cek dulu kondisi Author-nya sekarang.
SELECT "NamaPersonnel", "QrCodeId", "Author", "DigitalPIN"
FROM "karyawanTbl"
WHERE "NamaPersonnel" ILIKE '%NAMA_KARYAWAN%';

-- 2) Tambahin tag "Internal Auditor".
UPDATE "karyawanTbl"
SET "Author" = CASE
    WHEN "Author" IS NULL OR TRIM("Author") = '' THEN 'Internal Auditor'
    WHEN "Author" ILIKE '%Internal Auditor%' THEN "Author"
    ELSE "Author" || ', Internal Auditor'
END
WHERE "NamaPersonnel" ILIKE '%NAMA_KARYAWAN%';

-- 3) Cek hasilnya.
SELECT "NamaPersonnel", "QrCodeId", "Author", "DigitalPIN"
FROM "karyawanTbl"
WHERE "NamaPersonnel" ILIKE '%NAMA_KARYAWAN%';
