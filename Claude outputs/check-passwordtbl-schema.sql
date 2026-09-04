-- Jalankan di Supabase project FUSION4 (nhmpwjriextmbotmvvbu.supabase.co), BUKAN HSSE-Fusion4.
-- Tujuan: liat struktur "PasswordTbl" biar RPC get_karyawan_by_author() bisa dibenerin
-- baca dari tabel yang bener. Ini cuma SELECT/introspeksi, gak ubah data apa pun.

-- 1) Liat semua kolom PasswordTbl (nama + tipe data) -- ini yang paling penting,
--    tolong copas HASILNYA (screenshot atau teks) balik ke sini.
SELECT column_name, data_type
FROM information_schema.columns
WHERE table_name = 'PasswordTbl'
ORDER BY ordinal_position;

-- 2) Liat 5 baris contoh, TAPI kita belum tau nama kolomnya jadi query ini mungkin perlu
--    disesuaikan setelah liat hasil query #1 di atas. Kalau mau langsung coba, ganti
--    "kolom_password_atau_hash" di bawah ini jadi nama kolom yang keliatan berisi
--    password/hash (biar gak usah kelihatan) -- atau skip dulu bagian ini, cukup kirim
--    hasil query #1 aja dulu.
-- SELECT * FROM "PasswordTbl" LIMIT 5;
