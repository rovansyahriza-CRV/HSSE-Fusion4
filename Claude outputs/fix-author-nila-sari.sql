-- Jalankan di Supabase project FUSION4 (nhmpwjriextmbotmvvbu.supabase.co), BUKAN HSSE-Fusion4.
-- Nambahin tag Author "Approved Incident/Accident" buat Nila Sari, tanpa menghapus tag
-- Author yang mungkin udah dia punya sebelumnya (kalau ada).

-- 1) Cek dulu kondisi sekarang (opsional, buat mastiin nama & Author yang ada).
SELECT "NamaPersonnel", "QrCodeId", "Author", "DigitalPIN"
FROM "karyawanTbl"
WHERE "NamaPersonnel" ILIKE '%Nila Sari%';

-- 2) Tambahin tag "Approved Incident/Accident" -- aman dijalankan berkali-kali, gak bakal dobel.
UPDATE "karyawanTbl"
SET "Author" = CASE
    WHEN "Author" IS NULL OR TRIM("Author") = '' THEN 'Approved Incident/Accident'
    WHEN "Author" ILIKE '%Approved Incident/Accident%' THEN "Author"
    ELSE "Author" || ', Approved Incident/Accident'
END
WHERE "NamaPersonnel" ILIKE '%Nila Sari%';

-- 3) Cek hasilnya.
SELECT "NamaPersonnel", "QrCodeId", "Author", "DigitalPIN"
FROM "karyawanTbl"
WHERE "NamaPersonnel" ILIKE '%Nila Sari%';
