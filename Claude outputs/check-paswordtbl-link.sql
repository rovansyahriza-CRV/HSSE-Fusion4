-- Jalankan di Supabase project FUSION4 (nhmpwjriextmbotmvvbu.supabase.co).
-- Nama tabel yang bener: "paswordTbl" (cuma 1 huruf "s", bukan "password").
-- Cuma SELECT/introspeksi -- gak ubah data apa pun.

-- 1) Liat SEMUA kolom paswordTbl (biar keliatan semua, termasuk yang belum kelihatan
--    di layar kemarin -- misalnya ada kolom QrCodeId atau IdKaryawan di sana).
SELECT column_name, data_type
FROM information_schema.columns
WHERE table_name = 'paswordTbl'
ORDER BY ordinal_position;

-- 2) Tes dugaan #1: "paswordTbl"."Id" = "karyawanTbl"."Id"
SELECT p."Id" AS pasword_id, k."Id" AS karyawan_id, k."NamaPersonnel", k."QrCodeId",
       p."Author" AS author_di_paswordtbl, p."IsActive", p."AppKontrakKaryawan"
FROM "paswordTbl" p
LEFT JOIN "karyawanTbl" k ON k."Id" = p."Id"
WHERE p."Author" IS NOT NULL
ORDER BY p."Id"
LIMIT 30;

-- 3) Tes dugaan #2 (jaga-jaga kalau dugaan #1 hasil NamaPersonnel-nya NULL semua):
--    "paswordTbl"."AppKontrakKaryawan" = "karyawanTbl"."Id"
SELECT p."Id" AS pasword_id, p."AppKontrakKaryawan", k."Id" AS karyawan_id,
       k."NamaPersonnel", k."QrCodeId", p."Author" AS author_di_paswordtbl
FROM "paswordTbl" p
LEFT JOIN "karyawanTbl" k ON k."Id" = p."AppKontrakKaryawan"
WHERE p."Author" IS NOT NULL
ORDER BY p."Id"
LIMIT 30;

-- 4) Cek spesifik: siapa aja yang keliatan punya tag "Internal Auditor" kalau kita gabung
--    (UNION) Author dari karyawanTbl DAN dari paswordTbl sekaligus. Coba dulu pakai
--    dugaan #1 (join by Id) -- kalau hasil dugaan #2 di atas ternyata yang bener, kabarin
--    aku aja, nanti aku ganti join-nya di RPC final.
SELECT DISTINCT k."NamaPersonnel", k."QrCodeId"
FROM "karyawanTbl" k
LEFT JOIN "paswordTbl" p ON p."Id" = k."Id" AND p."IsActive" = TRUE
WHERE k."Author" ILIKE '%Internal Auditor%'
   OR p."Author" ILIKE '%Internal Auditor%'
ORDER BY k."NamaPersonnel";
