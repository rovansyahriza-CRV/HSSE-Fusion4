-- Jalankan di Supabase project FUSION4 (nhmpwjriextmbotmvvbu.supabase.co), BUKAN HSSE-Fusion4.
-- Ngecek dulu kondisi Author-nya Hariyoto sekarang, baru nambahin tag "Leader Toolbox Meeting"
-- tanpa menghapus tag Author lain yang mungkin udah dia punya sebelumnya.

-- 1) Cek dulu kondisi sekarang -- kalau kolom Author di sini KOSONG/NULL padahal kemarin
--    udah coba di-isi lewat form "Edit Karyawan", berarti kena bug lama itu lagi.
SELECT "NamaPersonnel", "QrCodeId", "Author", "DigitalPIN"
FROM "karyawanTbl"
WHERE "NamaPersonnel" ILIKE '%Hariyoto%';

-- 2) Tambahin tag "Leader Toolbox Meeting" -- aman dijalankan berkali-kali, gak bakal dobel.
UPDATE "karyawanTbl"
SET "Author" = CASE
    WHEN "Author" IS NULL OR TRIM("Author") = '' THEN 'Leader Toolbox Meeting'
    WHEN "Author" ILIKE '%Leader Toolbox Meeting%' THEN "Author"
    ELSE "Author" || ', Leader Toolbox Meeting'
END
WHERE "NamaPersonnel" ILIKE '%Hariyoto%';

-- 3) Cek hasilnya.
SELECT "NamaPersonnel", "QrCodeId", "Author", "DigitalPIN"
FROM "karyawanTbl"
WHERE "NamaPersonnel" ILIKE '%Hariyoto%';
