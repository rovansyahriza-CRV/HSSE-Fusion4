-- Jalankan di Supabase project FUSION4 (nhmpwjriextmbotmvvbu.supabase.co).
-- Query kemarin error "relation PasswordTbl does not exist" -- berarti nama tabelnya
-- beda huruf besar/kecil dari yang aku tebak (Postgres itu case-sensitive kalau nama
-- tabelnya pakai tanda kutip ganda). Query ini nyari nama TABEL YANG BENER, apa pun
-- huruf besar/kecilnya.

SELECT table_name
FROM information_schema.tables
WHERE table_schema = 'public'
  AND table_name ILIKE '%password%';
