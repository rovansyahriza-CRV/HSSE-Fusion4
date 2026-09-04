-- Jalankan di Supabase project FUSION4 (nhmpwjriextmbotmvvbu.supabase.co).
-- Kita mau liat 2 hal:

-- 1) Isi PERSIS yang dibalikin fungsi get_person_face_data buat QR-nya Hariyoto --
--    biar keliatan apa field "author" ada di dalamnya atau nggak.
SELECT get_person_face_data('10Har0801202');

-- 2) Definisi SQL lengkap fungsi ini -- biar kelihatan dia narik data dari mana aja
--    dan field apa aja yang di-build di dalam jsonb_build_object-nya.
SELECT pg_get_functiondef(oid)
FROM pg_proc
WHERE proname = 'get_person_face_data';
