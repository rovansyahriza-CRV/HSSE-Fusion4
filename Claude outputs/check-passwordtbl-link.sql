-- Jalankan di Supabase project FUSION4 (nhmpwjriextmbotmvvbu.supabase.co), BUKAN HSSE-Fusion4.
-- Cuma SELECT/introspeksi -- gak ubah data apa pun. Tujuannya nyari tau kolom apa di
-- "PasswordTbl" yang jadi penghubung ke "karyawanTbl" (Id? AppKontrakKaryawan? kolom lain
-- yang belum kelihatan di layar kemarin?).

-- 1) Liat SEMUA kolom PasswordTbl (barangkali ada kolom lain di sebelah kanan "PIN" yang
--    belum kelihatan di layar kemarin, misalnya QrCodeId atau IdKaryawan).
SELECT column_name, data_type
FROM information_schema.columns
WHERE table_name = 'PasswordTbl'
ORDER BY ordinal_position;

-- 2) Tes dugaan #1: "PasswordTbl"."Id" = "karyawanTbl"."Id"
--    Kalau dugaan ini BENER, harusnya nama-nama di bawah ini masuk akal (ketemu nama
--    orang asli, bukan NULL semua) dan cocok sama orang yang emang pernah di-tag lewat
--    form Fusion4.
SELECT p."Id" AS password_id, k."Id" AS karyawan_id, k."NamaPersonnel", k."QrCodeId",
       p."Author" AS author_di_passwordtbl, p."IsActive"
FROM "PasswordTbl" p
LEFT JOIN "karyawanTbl" k ON k."Id" = p."Id"
WHERE p."Author" IS NOT NULL
ORDER BY p."Id"
LIMIT 30;

-- 3) Tes dugaan #2 (jaga-jaga kalau dugaan #1 hasilnya NamaPersonnel NULL semua):
--    "PasswordTbl"."AppKontrakKaryawan" = "karyawanTbl"."Id"
SELECT p."Id" AS password_id, p."AppKontrakKaryawan", k."Id" AS karyawan_id,
       k."NamaPersonnel", k."QrCodeId", p."Author" AS author_di_passwordtbl
FROM "PasswordTbl" p
LEFT JOIN "karyawanTbl" k ON k."Id" = p."AppKontrakKaryawan"
WHERE p."Author" IS NOT NULL
ORDER BY p."Id"
LIMIT 30;

-- 4) Cek spesifik: siapa aja yang keliatan punya tag "Internal Auditor" kalau kita gabung
--    (UNION) Author dari karyawanTbl DAN dari PasswordTbl sekaligus, pakai dugaan #1.
--    Ini query kandidat buat RPC yang bakal aku pakai -- tolong cek nama-nama yang
--    muncul di sini udah sesuai harapan (termasuk auditor yang kemarin gak muncul).
SELECT DISTINCT k."NamaPersonnel", k."QrCodeId"
FROM "karyawanTbl" k
LEFT JOIN "PasswordTbl" p ON p."Id" = k."Id" AND p."IsActive" = TRUE
WHERE k."Author" ILIKE '%Internal Auditor%'
   OR p."Author" ILIKE '%Internal Auditor%'
ORDER BY k."NamaPersonnel";
