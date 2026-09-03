-- Jalankan di Supabase project FUSION4 (nhmpwjriextmbotmvvbu.supabase.co), BUKAN HSSE-Fusion4.
-- Nambahin tag Author "Permit & JSA" buat Anelka Bugihadinata Hariyono, tanpa menghapus tag
-- Author yang mungkin udah dia punya sebelumnya (kalau ada).

-- 1) Cek dulu kondisi sekarang (opsional, buat mastiin nama & Author yang ada).
SELECT "NamaPersonnel", "QrCodeId", "Author", "DigitalPIN"
FROM "karyawanTbl"
WHERE "NamaPersonnel" ILIKE '%Anelka Bugihadinata%';

-- 2) Tambahin tag "Permit & JSA" -- aman dijalankan berkali-kali, gak bakal dobel.
UPDATE "karyawanTbl"
SET "Author" = CASE
    WHEN "Author" IS NULL OR TRIM("Author") = '' THEN 'Permit & JSA'
    WHEN "Author" ILIKE '%Permit & JSA%' THEN "Author"
    ELSE "Author" || ', Permit & JSA'
END
WHERE "NamaPersonnel" ILIKE '%Anelka Bugihadinata%';

-- 3) Cek hasilnya.
SELECT "NamaPersonnel", "QrCodeId", "Author", "DigitalPIN"
FROM "karyawanTbl"
WHERE "NamaPersonnel" ILIKE '%Anelka Bugihadinata%';
