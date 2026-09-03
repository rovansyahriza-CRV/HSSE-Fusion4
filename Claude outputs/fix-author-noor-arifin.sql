-- Jalankan di Supabase project FUSION4 (nhmpwjriextmbotmvvbu.supabase.co), BUKAN HSSE-Fusion4.
-- Nambahin tag Author "Review Incident/Accident" buat Noor Arifin, tanpa menghapus tag
-- Author yang mungkin udah dia punya sebelumnya (kalau ada).

-- 1) Cek dulu kondisi sekarang (opsional, buat mastiin nama & Author yang ada).
SELECT "NamaPersonnel", "QrCodeId", "Author", "DigitalPIN"
FROM "karyawanTbl"
WHERE "NamaPersonnel" ILIKE '%Noor Arifin%';

-- 2) Tambahin tag "Review Incident/Accident" -- aman dijalankan berkali-kali, gak bakal dobel.
UPDATE "karyawanTbl"
SET "Author" = CASE
    WHEN "Author" IS NULL OR TRIM("Author") = '' THEN 'Review Incident/Accident'
    WHEN "Author" ILIKE '%Review Incident/Accident%' THEN "Author"
    ELSE "Author" || ', Review Incident/Accident'
END
WHERE "NamaPersonnel" ILIKE '%Noor Arifin%';

-- 3) Cek hasilnya.
SELECT "NamaPersonnel", "QrCodeId", "Author", "DigitalPIN"
FROM "karyawanTbl"
WHERE "NamaPersonnel" ILIKE '%Noor Arifin%';
