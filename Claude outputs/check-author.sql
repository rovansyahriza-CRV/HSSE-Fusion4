-- Jalankan di Supabase project FUSION4 (nhmpwjriextmbotmvvbu.supabase.co).
-- Ganti '%NAMA ORANGNYA%' sesuai yang baru di-edit lewat form "Edit Karyawan".
-- Kalau kolom Author di sini KOSONG/NULL padahal di form udah di-isi, berarti bug-nya
-- masih ada dan tetap butuh UPDATE manual kayak sebelumnya.

SELECT "NamaPersonnel", "QrCodeId", "Author", "DigitalPIN"
FROM "karyawanTbl"
WHERE "NamaPersonnel" ILIKE '%NAMA ORANGNYA%';
