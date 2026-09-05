-- Jalankan di Supabase project FUSION4 (nhmpwjriextmbotmvvbu.supabase.co), BUKAN HSSE-Fusion4.
-- Template UNIVERSAL buat kasih Author tag "Management Walkthrough" ke SIAPAPUN -- tinggal ganti
-- 'NAMA_KARYAWAN' di 3 tempat di bawah (SELECT-UPDATE-SELECT) sama nama orangnya (biasanya
-- Project Manager / Site Manager / level leadership yang jalanin MWT).
-- Aman dijalankan berkali-kali (gak bakal dobel tag), dan gak menghapus tag Author lain yang
-- udah dia punya sebelumnya (misal udah punya "Internal Auditor", nanti jadi gabungan keduanya).

-- 1) Cek dulu kondisi Author-nya sekarang.
SELECT "NamaPersonnel", "QrCodeId", "Author", "DigitalPIN"
FROM "karyawanTbl"
WHERE "NamaPersonnel" ILIKE '%NAMA_KARYAWAN%';

-- 2) Tambahin tag "Management Walkthrough".
UPDATE "karyawanTbl"
SET "Author" = CASE
    WHEN "Author" IS NULL OR TRIM("Author") = '' THEN 'Management Walkthrough'
    WHEN "Author" ILIKE '%Management Walkthrough%' THEN "Author"
    ELSE "Author" || ', Management Walkthrough'
END
WHERE "NamaPersonnel" ILIKE '%NAMA_KARYAWAN%';

-- 3) Cek hasilnya.
SELECT "NamaPersonnel", "QrCodeId", "Author", "DigitalPIN"
FROM "karyawanTbl"
WHERE "NamaPersonnel" ILIKE '%NAMA_KARYAWAN%';
