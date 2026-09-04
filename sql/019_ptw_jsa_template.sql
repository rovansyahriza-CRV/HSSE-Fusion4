-- =====================================================================================
-- HSSE-Fusion4 — MIGRASI #19: TEMPLATE JSA GENERIK PER JENIS PEKERJAAN
-- Jalankan SETELAH 001-018, di Supabase project HSSE-Fusion4.
--
-- Konsep (disepakati di chat): sama kayak "ptwHazardChecklistTemplateTbl" (lihat 016) --
-- JSA (Langkah Kerja - Potensi Bahaya - Pengendalian) juga ada contoh generik per Jenis
-- Pekerjaan, disimpan di tabel master sendiri (bisa diedit/ditambah lewat Table Editor
-- Supabase kapan aja, gak perlu ubah kode). Pas Requester pilih Jenis Pekerjaan di
-- ptw-report.html, baris JSA otomatis keisi contoh ini -- tetap bisa diedit, ditambah,
-- atau dihapus manual sesuai kondisi kerja yang sebenarnya di lapangan.
-- =====================================================================================


-- -------------------------------------------------------------------------------------
-- 1. TABEL MASTER CONTOH JSA PER JENIS PEKERJAAN
-- -------------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS "ptwJsaTemplateTbl" (
    "Id" BIGSERIAL PRIMARY KEY,
    "JenisPekerjaan" TEXT NOT NULL,
    "Langkah" TEXT NOT NULL,
    "Bahaya" TEXT NOT NULL,
    "Pengendalian" TEXT NOT NULL,
    "Urutan" INT NOT NULL DEFAULT 0,
    "Status" TEXT NOT NULL DEFAULT 'Aktif' CHECK ("Status" IN ('Aktif', 'Non-Aktif')),
    "CreatedAt" TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_ptw_jsa_template_jenis ON "ptwJsaTemplateTbl" ("JenisPekerjaan", "Status");

INSERT INTO "ptwJsaTemplateTbl" ("JenisPekerjaan", "Langkah", "Bahaya", "Pengendalian", "Urutan")
SELECT * FROM (VALUES
    ('Hot Work', 'Persiapan area & alat pengelasan/pemotongan', 'Percikan api mengenai material mudah terbakar di sekitar', 'Bersihkan/pindahkan material mudah terbakar radius 10m, pasang fire blanket', 10),
    ('Hot Work', 'Proses pengelasan/pemotongan', 'Kebakaran, luka bakar, paparan asap las', 'Fire watch siaga dengan APAR, gunakan APD las lengkap, ventilasi asap', 11),
    ('Hot Work', 'Pembersihan & pengecekan area setelah selesai', 'Bara api sisa yang belum padam sempurna', 'Cek ulang area minimal 30 menit setelah pekerjaan selesai (fire watch)', 12),

    ('Cold Work', 'Persiapan alat & area kerja', 'Alat kerja rusak/tidak layak, area belum dibarikade', 'Cek kondisi alat sebelum pakai, pasang barikade/rambu area kerja', 10),
    ('Cold Work', 'Pelaksanaan pekerjaan utama', 'Terpeleset/tersandung, tangan/anggota badan terjepit alat', 'Jaga kerapian area kerja, gunakan APD standar (helm, sarung tangan, sepatu safety)', 11),
    ('Cold Work', 'Selesai kerja & bersih-bersih', 'Sisa material/alat berserakan jadi bahaya tersandung', 'Rapikan alat dan sisa material, buang sampah pada tempatnya', 12),

    ('Confined Space', 'Uji gas (gas test) sebelum masuk', 'Gas beracun/mudah terbakar, kadar oksigen rendah', 'Gas test wajib oleh personel bersertifikat, catat hasilnya sebelum masuk', 10),
    ('Confined Space', 'Masuk & bekerja di dalam ruang terbatas', 'Kekurangan oksigen, sulit evakuasi darurat', 'Ventilasi/blower aktif selama kerja, standby man siaga di luar terus-menerus', 11),
    ('Confined Space', 'Keluar dari ruang terbatas', 'Personel tertinggal di dalam tanpa terdeteksi', 'Hitung jumlah personel keluar = jumlah masuk, komunikasi 2 arah dengan standby man', 12),

    ('Bekerja di Ketinggian', 'Pemeriksaan alat pelindung jatuh', 'Full body harness/lanyard rusak atau kadaluarsa', 'Cek tag inspeksi & kondisi fisik harness/lanyard sebelum dipakai', 10),
    ('Bekerja di Ketinggian', 'Naik/bekerja di scaffolding atau struktur tinggi', 'Jatuh dari ketinggian, benda jatuh mengenai pekerja lain di bawah', 'Kaitkan lanyard ke anchor point yang kuat, pasang barikade di area bawah', 11),
    ('Bekerja di Ketinggian', 'Turun & selesai pekerjaan', 'Terburu-buru turun, alat/material tertinggal di atas', 'Turun perlahan sesuai prosedur, pastikan semua alat dibawa turun', 12),

    ('Penggalian (Excavation)', 'Pengecekan utilitas bawah tanah', 'Kabel listrik/pipa gas/pipa air tergali tanpa sengaja', 'Cek peta utilitas & lakukan hand digging di titik yang dicurigai', 10),
    ('Penggalian (Excavation)', 'Proses penggalian', 'Longsor dinding galian menimpa pekerja', 'Pasang sloping/shoring sesuai kedalaman, jangan ada beban di tepi galian', 11),
    ('Penggalian (Excavation)', 'Area galian terbuka (belum ditutup)', 'Orang/kendaraan terperosok ke lubang galian', 'Pasang barikade & rambu peringatan di sekeliling area galian', 12),

    ('Kelistrikan (Electrical/LOTO)', 'Isolasi sumber listrik (LOTO)', 'Tersengat listrik karena sumber belum benar-benar terputus', 'Pasang Lock-Out Tag-Out di sumber, uji tegangan nol sebelum kerja', 10),
    ('Kelistrikan (Electrical/LOTO)', 'Pekerjaan pada instalasi/panel listrik', 'Tersengat listrik, korsleting, kebakaran', 'Gunakan APD kelistrikan (sarung tangan isolasi, sepatu safety), alat kerja berinsulasi', 11),
    ('Kelistrikan (Electrical/LOTO)', 'Pelepasan LOTO & pengaktifan kembali', 'Sumber listrik diaktifkan saat masih ada orang bekerja', 'Pastikan semua personel aman & alat sudah dilepas sebelum lepas LOTO', 12),

    ('Pengangkatan (Lifting)', 'Persiapan alat angkat & rigging', 'Sling/tali/alat bantu angkat rusak, kapasitas tidak sesuai beban', 'Cek load chart sesuai kapasitas alat, cek kondisi sling/rigging sebelum pakai', 10),
    ('Pengangkatan (Lifting)', 'Proses pengangkatan beban', 'Beban jatuh/terjatuh mengenai orang di bawah', 'Area di bawah beban steril dari orang, operator & rigger bersertifikat', 11),
    ('Pengangkatan (Lifting)', 'Penurunan & penempatan beban', 'Beban bergeser/terguling saat diletakkan', 'Pastikan area penempatan rata & kuat, pandu penurunan dengan aba-aba jelas', 12)
) AS v("JenisPekerjaan", "Langkah", "Bahaya", "Pengendalian", "Urutan")
WHERE NOT EXISTS (SELECT 1 FROM "ptwJsaTemplateTbl");


-- -------------------------------------------------------------------------------------
-- 2. RPC: AMBIL TEMPLATE JSA SESUAI JENIS PEKERJAAN
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
        'pengendalian', "Pengendalian"
    ) ORDER BY "Urutan"), '[]'::jsonb)
    INTO v_result
    FROM "ptwJsaTemplateTbl"
    WHERE "JenisPekerjaan" = p_jenis_pekerjaan AND "Status" = 'Aktif';

    RETURN v_result;
END;
$$;
