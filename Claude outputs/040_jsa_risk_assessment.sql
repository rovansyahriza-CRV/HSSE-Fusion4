-- =====================================================================================
-- HSSE-Fusion4 — MIGRASI #40: PENILAIAN RISIKO (HIRA) DI JSA
-- Jalankan SETELAH 001-039, di Supabase project HSSE-Fusion4.
--
-- Konsep (disepakati di chat, 06 Sep 2026): tiap baris JSA (Langkah Kerja - Bahaya -
-- Pengendalian) sekarang dilengkapi penilaian risiko ala HIRARC -- Kemungkinan x
-- Keparahan (skala 1-5) dihitung DUA KALI: sebelum ada pengendalian (Risiko Awal) dan
-- sesudah pengendalian diterapkan (Risiko Sisa). Matriks skor -> Tingkat Risiko
-- (Rendah/Sedang/Tinggi/Ekstrem) DITANAM DI KODE (JS di ptw-report.html & ptw-pdf.html),
-- bukan master table, karena kriterianya jarang berubah -- lihat chat kalau nanti mau
-- diubah jadi configurable.
--
-- Yang berubah:
-- 1. "ptwJsaTemplateTbl" (contoh JSA generik per Jenis Pekerjaan) -- ditambah 4 kolom
--    skor risiko + di-update isinya dengan estimasi wajar per baris yang udah ada.
-- 2. get_ptw_jsa_template() -- RPC-nya sekarang ikut balikin skor risiko, biar
--    pas prefill di ptw-report.html langsung ada estimasinya (tetap bisa diedit manual).
-- 3. "ptwTbl"."JsaItems" (JSA aktual per PTW) -- TIDAK perlu ALTER, tetap JSONB bebas
--    bentuk. Field baru (likelihoodAwal dkk) otomatis ikut kesimpen begitu
--    ptw-report.html mulai ngirim field itu di p_jsa_items -- submit_ptw/update RPC
--    udah passthrough JSONB apa adanya, gak perlu diubah.
-- =====================================================================================


-- -------------------------------------------------------------------------------------
-- 1. KOLOM SKOR RISIKO DI TABEL TEMPLATE JSA
-- -------------------------------------------------------------------------------------
ALTER TABLE "ptwJsaTemplateTbl" ADD COLUMN IF NOT EXISTS "LikelihoodAwal" INT NOT NULL DEFAULT 1
    CHECK ("LikelihoodAwal" BETWEEN 1 AND 5);
ALTER TABLE "ptwJsaTemplateTbl" ADD COLUMN IF NOT EXISTS "SeverityAwal" INT NOT NULL DEFAULT 1
    CHECK ("SeverityAwal" BETWEEN 1 AND 5);
ALTER TABLE "ptwJsaTemplateTbl" ADD COLUMN IF NOT EXISTS "LikelihoodSisa" INT NOT NULL DEFAULT 1
    CHECK ("LikelihoodSisa" BETWEEN 1 AND 5);
ALTER TABLE "ptwJsaTemplateTbl" ADD COLUMN IF NOT EXISTS "SeveritySisa" INT NOT NULL DEFAULT 1
    CHECK ("SeveritySisa" BETWEEN 1 AND 5);


-- -------------------------------------------------------------------------------------
-- 2. ISI ESTIMASI SKOR RISIKO UNTUK 21 BARIS TEMPLATE YANG SUDAH ADA (dari migrasi #19)
--    Dicocokkan lewat ("JenisPekerjaan", "Urutan") -- aman dijalankan berkali-kali.
--    Kalau HSE Officer mau ubah, tinggal edit langsung lewat Table Editor Supabase.
-- -------------------------------------------------------------------------------------
UPDATE "ptwJsaTemplateTbl" SET "LikelihoodAwal"=4, "SeverityAwal"=4, "LikelihoodSisa"=2, "SeveritySisa"=3 WHERE "JenisPekerjaan"='Hot Work' AND "Urutan"=10;
UPDATE "ptwJsaTemplateTbl" SET "LikelihoodAwal"=4, "SeverityAwal"=5, "LikelihoodSisa"=2, "SeveritySisa"=3 WHERE "JenisPekerjaan"='Hot Work' AND "Urutan"=11;
UPDATE "ptwJsaTemplateTbl" SET "LikelihoodAwal"=3, "SeverityAwal"=3, "LikelihoodSisa"=1, "SeveritySisa"=2 WHERE "JenisPekerjaan"='Hot Work' AND "Urutan"=12;

UPDATE "ptwJsaTemplateTbl" SET "LikelihoodAwal"=3, "SeverityAwal"=2, "LikelihoodSisa"=1, "SeveritySisa"=2 WHERE "JenisPekerjaan"='Cold Work' AND "Urutan"=10;
UPDATE "ptwJsaTemplateTbl" SET "LikelihoodAwal"=3, "SeverityAwal"=2, "LikelihoodSisa"=2, "SeveritySisa"=2 WHERE "JenisPekerjaan"='Cold Work' AND "Urutan"=11;
UPDATE "ptwJsaTemplateTbl" SET "LikelihoodAwal"=3, "SeverityAwal"=1, "LikelihoodSisa"=1, "SeveritySisa"=1 WHERE "JenisPekerjaan"='Cold Work' AND "Urutan"=12;

UPDATE "ptwJsaTemplateTbl" SET "LikelihoodAwal"=3, "SeverityAwal"=5, "LikelihoodSisa"=1, "SeveritySisa"=5 WHERE "JenisPekerjaan"='Confined Space' AND "Urutan"=10;
UPDATE "ptwJsaTemplateTbl" SET "LikelihoodAwal"=3, "SeverityAwal"=5, "LikelihoodSisa"=1, "SeveritySisa"=5 WHERE "JenisPekerjaan"='Confined Space' AND "Urutan"=11;
UPDATE "ptwJsaTemplateTbl" SET "LikelihoodAwal"=2, "SeverityAwal"=5, "LikelihoodSisa"=1, "SeveritySisa"=5 WHERE "JenisPekerjaan"='Confined Space' AND "Urutan"=12;

UPDATE "ptwJsaTemplateTbl" SET "LikelihoodAwal"=3, "SeverityAwal"=5, "LikelihoodSisa"=1, "SeveritySisa"=5 WHERE "JenisPekerjaan"='Bekerja di Ketinggian' AND "Urutan"=10;
UPDATE "ptwJsaTemplateTbl" SET "LikelihoodAwal"=4, "SeverityAwal"=5, "LikelihoodSisa"=1, "SeveritySisa"=5 WHERE "JenisPekerjaan"='Bekerja di Ketinggian' AND "Urutan"=11;
UPDATE "ptwJsaTemplateTbl" SET "LikelihoodAwal"=3, "SeverityAwal"=3, "LikelihoodSisa"=1, "SeveritySisa"=3 WHERE "JenisPekerjaan"='Bekerja di Ketinggian' AND "Urutan"=12;

UPDATE "ptwJsaTemplateTbl" SET "LikelihoodAwal"=3, "SeverityAwal"=4, "LikelihoodSisa"=1, "SeveritySisa"=4 WHERE "JenisPekerjaan"='Penggalian (Excavation)' AND "Urutan"=10;
UPDATE "ptwJsaTemplateTbl" SET "LikelihoodAwal"=3, "SeverityAwal"=5, "LikelihoodSisa"=1, "SeveritySisa"=5 WHERE "JenisPekerjaan"='Penggalian (Excavation)' AND "Urutan"=11;
UPDATE "ptwJsaTemplateTbl" SET "LikelihoodAwal"=3, "SeverityAwal"=3, "LikelihoodSisa"=1, "SeveritySisa"=3 WHERE "JenisPekerjaan"='Penggalian (Excavation)' AND "Urutan"=12;

UPDATE "ptwJsaTemplateTbl" SET "LikelihoodAwal"=3, "SeverityAwal"=5, "LikelihoodSisa"=1, "SeveritySisa"=5 WHERE "JenisPekerjaan"='Kelistrikan (Electrical/LOTO)' AND "Urutan"=10;
UPDATE "ptwJsaTemplateTbl" SET "LikelihoodAwal"=3, "SeverityAwal"=5, "LikelihoodSisa"=1, "SeveritySisa"=5 WHERE "JenisPekerjaan"='Kelistrikan (Electrical/LOTO)' AND "Urutan"=11;
UPDATE "ptwJsaTemplateTbl" SET "LikelihoodAwal"=2, "SeverityAwal"=5, "LikelihoodSisa"=1, "SeveritySisa"=5 WHERE "JenisPekerjaan"='Kelistrikan (Electrical/LOTO)' AND "Urutan"=12;

UPDATE "ptwJsaTemplateTbl" SET "LikelihoodAwal"=3, "SeverityAwal"=4, "LikelihoodSisa"=1, "SeveritySisa"=4 WHERE "JenisPekerjaan"='Pengangkatan (Lifting)' AND "Urutan"=10;
UPDATE "ptwJsaTemplateTbl" SET "LikelihoodAwal"=3, "SeverityAwal"=5, "LikelihoodSisa"=1, "SeveritySisa"=5 WHERE "JenisPekerjaan"='Pengangkatan (Lifting)' AND "Urutan"=11;
UPDATE "ptwJsaTemplateTbl" SET "LikelihoodAwal"=3, "SeverityAwal"=3, "LikelihoodSisa"=1, "SeveritySisa"=3 WHERE "JenisPekerjaan"='Pengangkatan (Lifting)' AND "Urutan"=12;


-- -------------------------------------------------------------------------------------
-- 3. RPC: AMBIL TEMPLATE JSA -- SEKARANG IKUT BALIKIN SKOR RISIKO
-- -------------------------------------------------------------------------------------
DROP FUNCTION IF EXISTS get_ptw_jsa_template(TEXT);
CREATE OR REPLACE FUNCTION get_ptw_jsa_template(p_jenis_pekerjaan TEXT)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_result JSONB;
BEGIN
    SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'langkah', "Langkah",
        'bahaya', "Bahaya",
        'pengendalian', "Pengendalian",
        'likelihoodAwal', "LikelihoodAwal",
        'severityAwal', "SeverityAwal",
        'likelihoodSisa', "LikelihoodSisa",
        'severitySisa', "SeveritySisa"
    ) ORDER BY "Urutan"), '[]'::jsonb)
    INTO v_result
    FROM "ptwJsaTemplateTbl"
    WHERE "JenisPekerjaan" = p_jenis_pekerjaan AND "Status" = 'Aktif';

    RETURN v_result;
END;
$$;

-- Catatan: "ptwTbl"."JsaItems" tetap JSONB bebas bentuk, gak perlu ALTER apa-apa.
-- submit_ptw / update PTW RPC (migrasi #16) udah passthrough p_jsa_items apa adanya,
-- jadi field likelihoodAwal/severityAwal/likelihoodSisa/severitySisa otomatis
-- kesimpen begitu ptw-report.html mulai ngirim field itu -- gak perlu ubah RPC lain.
