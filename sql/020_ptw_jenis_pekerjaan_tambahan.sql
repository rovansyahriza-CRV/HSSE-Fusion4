-- =====================================================================================
-- HSSE-Fusion4 — MIGRASI #20: TAMBAH 9 JENIS PEKERJAAN BARU (Permit to Work)
-- Jalankan SETELAH 001-019, di Supabase project HSSE-Fusion4.
--
-- Hasil "sounding" referensi PTW/HSE (Indonesia Safety Center, HSE Blog, dst) buat
-- ngelengkapin 7 Jenis Pekerjaan yang udah ada, disesuaikan sama scope kerjaan
-- kontraktor konstruksi BiMa di proyek Pertamina Hulu (onshore & offshore):
--   1. Pengelasan & Pemotongan (Welding & Cutting)
--   2. Scaffolding (Ereksi/Modifikasi/Pembongkaran Perancah)
--   3. Sandblasting & Painting/Coating
--   4. Line Breaking / Buka Sambungan Pipa-Vessel Bertekanan
--   5. Radiography / NDT (Non-Destructive Testing)
--   6. Pressure Test (Hydrotest / Pneumatic Test)
--   7. Bekerja di Atas Air / Marine Work (Offshore)
--   8. Pekerjaan dengan Bahan Kimia Berbahaya
--   9. Mobilisasi Kendaraan/Alat Berat ke Area Proses
--
-- Insert ke 2 tabel master sekaligus (WHERE NOT EXISTS per Jenis Pekerjaan biar aman
-- dijalankan berkali-kali / gak dobel kalau sebagian udah pernah ditambah manual).
-- =====================================================================================


-- -------------------------------------------------------------------------------------
-- 1. HAZARD CHECKLIST -- ptwHazardChecklistTemplateTbl
-- -------------------------------------------------------------------------------------
INSERT INTO "ptwHazardChecklistTemplateTbl" ("JenisPekerjaan", "Item", "Urutan")
SELECT * FROM (VALUES
    ('Pengelasan & Pemotongan', 'Welder bersertifikat/qualified sesuai jenis pengelasan', 10),
    ('Pengelasan & Pemotongan', 'APAR / fire watch siaga di lokasi', 11),
    ('Pengelasan & Pemotongan', 'Area kerja bebas material mudah terbakar dalam radius aman', 12),
    ('Pengelasan & Pemotongan', 'Welding screen/tirai las terpasang biar percikan & radiasi gak kena orang lain', 13),

    ('Scaffolding', 'Scaffolder yang mengerjakan bersertifikat', 10),
    ('Scaffolding', 'Scafftag terpasang & sesuai status (hijau/kuning/merah)', 11),
    ('Scaffolding', 'Pondasi/base plate scaffolding rata dan kuat', 12),
    ('Scaffolding', 'Pemeriksaan berkala/mingguan terdokumentasi', 13),

    ('Sandblasting & Painting/Coating', 'Area kerja ditutup terpal/enclosure biar debu/uap gak nyebar', 10),
    ('Sandblasting & Painting/Coating', 'Respirator/APD pernafasan sesuai jenis blasting/cat dipakai', 11),
    ('Sandblasting & Painting/Coating', 'Ventilasi memadai di area tertutup', 12),
    ('Sandblasting & Painting/Coating', 'APAR siaga (cat/thinner mudah terbakar)', 13),

    ('Line Breaking', 'Pipa/vessel dipastikan bebas tekanan & sudah terisolasi (LOTO/blind)', 10),
    ('Line Breaking', 'Sudah dilakukan drain/purging sisa fluida di dalam line', 11),
    ('Line Breaking', 'APD kimia/proses sesuai fluida yang pernah ada di dalam line dipakai', 12),
    ('Line Breaking', 'Rencana tanggap darurat tumpahan/paparan disiapkan', 13),

    ('Radiography / NDT', 'Petugas radiografi bersertifikat & punya izin (SIB) dari BAPETEN', 10),
    ('Radiography / NDT', 'Zona eksklusi radiasi dipasang & dijaga', 11),
    ('Radiography / NDT', 'Sumber radioaktif aman (shielding) saat gak dipakai', 12),
    ('Radiography / NDT', 'Alat pendeteksi radiasi (survey meter) berfungsi & sudah dicek', 13),

    ('Pressure Test (Hydrotest/Pneumatic)', 'Rencana uji tekanan (test pressure, media uji) disetujui sebelum mulai', 10),
    ('Pressure Test (Hydrotest/Pneumatic)', 'Area uji dibarikade & steril dari orang yang gak berkepentingan', 11),
    ('Pressure Test (Hydrotest/Pneumatic)', 'Alat ukur tekanan (pressure gauge) terkalibrasi', 12),
    ('Pressure Test (Hydrotest/Pneumatic)', 'Rencana tanggap darurat kalau line/vessel gagal (failure) disiapkan', 13),

    ('Bekerja di Atas Air / Marine Work', 'Life jacket/PFD dipakai selama bekerja dekat/di atas air', 10),
    ('Bekerja di Atas Air / Marine Work', 'Kondisi cuaca & gelombang laut dicek sebelum kerja dimulai', 11),
    ('Bekerja di Atas Air / Marine Work', 'Alat komunikasi & rencana rescue di air disiapkan', 12),
    ('Bekerja di Atas Air / Marine Work', 'Prosedur man overboard dipahami tim', 13),

    ('Bahan Kimia Berbahaya', 'SDS (Safety Data Sheet) bahan kimia tersedia & dipahami pekerja', 10),
    ('Bahan Kimia Berbahaya', 'APD sesuai jenis bahan kimia dipakai', 11),
    ('Bahan Kimia Berbahaya', 'Tempat penyimpanan & spill kit tersedia', 12),
    ('Bahan Kimia Berbahaya', 'Ventilasi memadai di area kerja', 13),

    ('Mobilisasi Kendaraan/Alat Berat', 'Kendaraan/alat berat dilengkapi spark arrestor (kalau masuk area hazardous)', 10),
    ('Mobilisasi Kendaraan/Alat Berat', 'Operator punya SIO/SIM sesuai jenis alat', 11),
    ('Mobilisasi Kendaraan/Alat Berat', 'Rute & area parkir sudah ditentukan, bebas dari jalur pejalan kaki utama', 12),
    ('Mobilisasi Kendaraan/Alat Berat', 'Pengawas (spotter/flagman) siaga saat manuver di area sempit/proses aktif', 13)
) AS v("JenisPekerjaan", "Item", "Urutan")
WHERE NOT EXISTS (
    SELECT 1 FROM "ptwHazardChecklistTemplateTbl" t WHERE t."JenisPekerjaan" = v."JenisPekerjaan"
);


-- -------------------------------------------------------------------------------------
-- 2. CONTOH JSA -- ptwJsaTemplateTbl
-- -------------------------------------------------------------------------------------
INSERT INTO "ptwJsaTemplateTbl" ("JenisPekerjaan", "Langkah", "Bahaya", "Pengendalian", "Urutan")
SELECT * FROM (VALUES
    ('Pengelasan & Pemotongan', 'Persiapan alat las & area kerja', 'Percikan api & radiasi busur las mengenai sekitar', 'Pasang welding screen, cek APAR, sterilkan area dari material mudah terbakar', 10),
    ('Pengelasan & Pemotongan', 'Proses pengelasan/pemotongan', 'Fume/asap las terhirup, luka bakar, radiasi ke mata', 'Pakai APD las lengkap (welding mask, apron, sarung tangan las), ventilasi asap', 11),
    ('Pengelasan & Pemotongan', 'Selesai kerja & pembersihan', 'Bara/percikan sisa masih panas', 'Fire watch tetap siaga minimal 30 menit setelah pekerjaan selesai', 12),

    ('Scaffolding', 'Persiapan material & pondasi scaffolding', 'Pondasi ambles, material scaffolding cacat', 'Cek base plate rata & kuat, cek kondisi pipa/clamp sebelum dipakai', 10),
    ('Scaffolding', 'Proses ereksi/pembongkaran perancah', 'Jatuh dari ketinggian, tertimpa material scaffolding', 'Pakai full body harness selama proses, barikade area di bawahnya', 11),
    ('Scaffolding', 'Serah terima & pemasangan scafftag', 'Scaffolding dipakai padahal belum selesai/gak layak', 'Pasang scafftag sesuai status setelah inspeksi selesai', 12),

    ('Sandblasting & Painting/Coating', 'Persiapan area & material (pasir blasting/cat)', 'Debu silika & uap kimia terhirup', 'Pakai respirator sesuai standar, tutup area dengan terpal/enclosure', 10),
    ('Sandblasting & Painting/Coating', 'Proses blasting/pengecatan', 'Ledakan debu, kebakaran (uap solvent), iritasi kulit/mata', 'Ventilasi aktif, APAR siaga, pakai APD lengkap (goggle, sarung tangan kimia)', 11),
    ('Sandblasting & Painting/Coating', 'Pembersihan & pembuangan sisa material', 'Limbah B3 tercecer sembarangan', 'Kumpulkan sisa blasting/cat sebagai limbah B3, buang sesuai prosedur', 12),

    ('Line Breaking', 'Verifikasi isolasi & tekanan nol', 'Fluida bertekanan masih ada di dalam line', 'Cek pressure gauge nol, verifikasi isolasi/blind sebelum dibuka', 10),
    ('Line Breaking', 'Proses membuka flange/sambungan', 'Tumpahan/semburan fluida sisa (minyak, gas, kimia)', 'Buka baut secara bertahap (crack open), pakai APD sesuai jenis fluida', 11),
    ('Line Breaking', 'Penanganan fluida sisa & penutupan kembali', 'Fluida sisa tercecer, sambungan gak rapat kembali', 'Tampung fluida sisa, cek torque baut saat dipasang kembali', 12),

    ('Radiography / NDT', 'Persiapan & pemasangan zona eksklusi', 'Orang lain kena paparan radiasi tanpa sadar', 'Pasang barikade & rambu radiasi, jaga zona eksklusi selama penyinaran', 10),
    ('Radiography / NDT', 'Proses penyinaran (exposure)', 'Paparan radiasi ke petugas/orang sekitar', 'Petugas pakai dosimeter, jaga jarak aman sesuai perhitungan, cek survey meter', 11),
    ('Radiography / NDT', 'Penyimpanan kembali sumber radioaktif', 'Sumber radioaktif tertinggal/gak tersimpan aman', 'Cek sumber kembali ke shielding/container sebelum tinggalkan lokasi', 12),

    ('Pressure Test (Hydrotest/Pneumatic)', 'Persiapan alat uji & isolasi area', 'Alat ukur gak akurat, area belum steril', 'Cek kalibrasi gauge, pasang barikade radius aman (terutama pneumatic test)', 10),
    ('Pressure Test (Hydrotest/Pneumatic)', 'Proses menaikkan tekanan bertahap', 'Line/vessel pecah/bocor mendadak', 'Naikkan tekanan bertahap sesuai prosedur, pantau dari jarak aman', 11),
    ('Pressure Test (Hydrotest/Pneumatic)', 'Penurunan tekanan & release', 'Tekanan sisa masih ada saat dibuka', 'Turunkan tekanan bertahap sampai nol sebelum buka sambungan', 12),

    ('Bekerja di Atas Air / Marine Work', 'Pengecekan cuaca & persiapan alat keselamatan air', 'Kondisi laut/cuaca buruk, alat keselamatan gak lengkap', 'Cek forecast cuaca, pastikan life jacket & alat komunikasi siap', 10),
    ('Bekerja di Atas Air / Marine Work', 'Proses kerja di atas air/dekat air (deck barge, platform)', 'Terjatuh ke laut, tertimpa alat karena gerakan kapal/gelombang', 'Pakai life jacket terus-menerus, batasi kerja kalau gelombang tinggi', 11),
    ('Bekerja di Atas Air / Marine Work', 'Evakuasi darurat man overboard', 'Korban terjatuh ke laut gak segera ditemukan/diselamatkan', 'Siapkan rescue boat/ring buoy standby, tim paham prosedur man overboard', 12),

    ('Bahan Kimia Berbahaya', 'Persiapan & pengecekan SDS bahan kimia', 'Salah penanganan karena gak tau sifat bahan', 'Baca & pahami SDS, siapkan APD sesuai rekomendasi', 10),
    ('Bahan Kimia Berbahaya', 'Proses penggunaan/penanganan bahan kimia', 'Terpapar/terhirup/terkena kulit, reaksi kimia berbahaya', 'Pakai APD lengkap (goggle, sarung tangan, respirator), ventilasi aktif', 11),
    ('Bahan Kimia Berbahaya', 'Penyimpanan & penanganan tumpahan', 'Tumpahan bahan kimia gak ditangani dengan benar', 'Sediakan spill kit, tangani tumpahan sesuai prosedur di SDS', 12),

    ('Mobilisasi Kendaraan/Alat Berat', 'Pengecekan kendaraan/alat sebelum masuk area', 'Alat gak layak (spark arrestor gak berfungsi, dll) jadi sumber api di area hazardous', 'Cek kelengkapan spark arrestor & kondisi alat sebelum masuk', 10),
    ('Mobilisasi Kendaraan/Alat Berat', 'Manuver & mobilisasi di area proses aktif', 'Tabrakan dengan pekerja/alat lain, alat berat kena obstacle', 'Spotter/flagman siaga, ikuti rute yang ditentukan, klakson saat manuver', 11),
    ('Mobilisasi Kendaraan/Alat Berat', 'Parkir & selesai mobilisasi', 'Kendaraan parkir sembarangan menghalangi akses darurat', 'Parkir di area yang ditentukan, jangan halangi jalur emergency', 12)
) AS v("JenisPekerjaan", "Langkah", "Bahaya", "Pengendalian", "Urutan")
WHERE NOT EXISTS (
    SELECT 1 FROM "ptwJsaTemplateTbl" t WHERE t."JenisPekerjaan" = v."JenisPekerjaan"
);
