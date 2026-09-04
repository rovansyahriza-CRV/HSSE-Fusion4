-- Jalankan di Supabase project FUSION4 (nhmpwjriextmbotmvvbu.supabase.co).
-- Cek APAKAH ada lebih dari 1 baris buat "Hariyoto" (misal data dobel/duplikat dengan
-- QrCodeId beda) -- kalau ada 2+ baris, kemungkinan yang ke-scan/ke-match itu baris LAIN
-- yang belum kena UPDATE tadi.
SELECT "Id", "NamaPersonnel", "QrCodeId", "Author", "DigitalPIN"
FROM "karyawanTbl"
WHERE "NamaPersonnel" ILIKE '%Hariyoto%'
ORDER BY "Id";
