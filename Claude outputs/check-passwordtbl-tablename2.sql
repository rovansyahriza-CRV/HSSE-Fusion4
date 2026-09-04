-- Jalankan di Supabase project FUSION4 (nhmpwjriextmbotmvvbu.supabase.co).
-- Ternyata gak ada tabel yang namanya mengandung "password" sama sekali -- berarti nama
-- tabel yang keliatan di Table Editor kemarin BUKAN "PasswordTbl" persis, itu cuma cara
-- gampang kamu nyebutnya. Query ini nyari tabel itu lewat kolom-kolom KHASNYA yang udah
-- keliatan di screenshot kemarin ("AppKontrakKaryawan" itu nama kolom yang cukup unik).

SELECT table_name, column_name
FROM information_schema.columns
WHERE table_schema = 'public'
  AND column_name = 'AppKontrakKaryawan';

-- Kalau query di atas kosong juga, coba yang ini (jaring lebih lebar, siapa tau ada
-- tabel dengan kolom mirip nama itu):
SELECT table_name, column_name
FROM information_schema.columns
WHERE table_schema = 'public'
  AND (column_name ILIKE '%kontrak%' OR column_name ILIKE '%digitalpin%' OR column_name = 'PIN');
