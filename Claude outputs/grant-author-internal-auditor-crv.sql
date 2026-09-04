-- Jalankan di Supabase project FUSION4 (nhmpwjriextmbotmvvbu.supabase.co), BUKAN HSSE-Fusion4.
-- Ini bukan bug -- modul Internal Audit emang sengaja di-gate kayak PTW/TBM/HSE Meeting,
-- cuma yang punya Author tag "Internal Auditor" yang boleh bikin/isi Internal Audit.
-- Script ini nambahin tag itu ke CRV tanpa menghapus tag Author lain yang udah dipunya.

-- 1) Cek dulu kondisi Author-nya CRV sekarang.
SELECT "NamaPersonnel", "QrCodeId", "Author", "DigitalPIN"
FROM "karyawanTbl"
WHERE "NamaPersonnel" ILIKE '%CRV%';

-- 2) Tambahin tag "Internal Auditor" -- aman dijalankan berkali-kali, gak bakal dobel.
UPDATE "karyawanTbl"
SET "Author" = CASE
    WHEN "Author" IS NULL OR TRIM("Author") = '' THEN 'Internal Auditor'
    WHEN "Author" ILIKE '%Internal Auditor%' THEN "Author"
    ELSE "Author" || ', Internal Auditor'
END
WHERE "NamaPersonnel" ILIKE '%CRV%';

-- 3) Cek hasilnya.
SELECT "NamaPersonnel", "QrCodeId", "Author", "DigitalPIN"
FROM "karyawanTbl"
WHERE "NamaPersonnel" ILIKE '%CRV%';
