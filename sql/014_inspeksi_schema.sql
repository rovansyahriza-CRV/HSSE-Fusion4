-- =====================================================================================
-- HSSE-Fusion4 — MIGRASI #14: MODUL INSPEKSI & OBSERVASI LAPANGAN
-- Jalankan SETELAH 001-013, di Supabase project HSSE-Fusion4.
--
-- Konsep (udah disepakati di chat):
-- 1. SATU modul, field "Jenis" ('Inspeksi' | 'Observasi') dipilih pas isi form --
--    checklist yang muncul beda tergantung Jenis.
-- 2. Format laporan: checklist per item (Sesuai / Tidak Sesuai / N/A) + skor % otomatis
--    (Sesuai / (Sesuai + Tidak Sesuai) * 100 -- N/A gak masuk hitungan).
-- 3. Kalau ada item Tidak Sesuai, submit otomatis bikin SATU laporan CERMAT gabungan
--    (semua temuan Tidak Sesuai digabung jadi 1 Deskripsi), masuk ke alur CERMAT normal
--    (Open -> In Progress -> Review -> Closed) buat ditindaklanjuti dept terkait.
-- 4. Ad-hoc kayak CERMAT -- siapa aja yang identifikasi (scan wajah/PIN/QR) bisa isi form
--    kapan aja, gak ada jadwal/assignment.
-- 5. Master checklist disimpan di tabel sendiri (inspeksiChecklistTemplateTbl), BUKAN
--    di-hardcode di HTML -- biar bisa diedit/ditambah lewat SQL tanpa ubah kode frontend.
-- =====================================================================================


-- -------------------------------------------------------------------------------------
-- 1. TABEL MASTER CHECKLIST (draft standar HSE -- edit/tambah baris ini kapan aja lewat
--    Table Editor Supabase atau UPDATE/INSERT manual, gak perlu ubah kode).
-- -------------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS "inspeksiChecklistTemplateTbl" (
    "Id" BIGSERIAL PRIMARY KEY,
    "Jenis" TEXT NOT NULL CHECK ("Jenis" IN ('Inspeksi', 'Observasi')),
    "Kategori" TEXT NOT NULL,
    "Item" TEXT NOT NULL,
    "Urutan" INT NOT NULL DEFAULT 0,
    "Status" TEXT NOT NULL DEFAULT 'Aktif' CHECK ("Status" IN ('Aktif', 'Non-Aktif')),
    "CreatedAt" TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_inspeksi_template_jenis ON "inspeksiChecklistTemplateTbl" ("Jenis", "Status");

-- Seed draft standar -- HANYA kalau tabelnya masih kosong, biar migrasi ini aman
-- dijalankan ulang tanpa bikin duplikat kalau kalian udah mulai edit isinya.
INSERT INTO "inspeksiChecklistTemplateTbl" ("Jenis", "Kategori", "Item", "Urutan")
SELECT * FROM (VALUES
    -- ===== INSPEKSI LAPANGAN (kondisi fisik area kerja) =====
    ('Inspeksi', 'Housekeeping & Kerapian Area', 'Area kerja bersih dari sampah/material berserakan', 10),
    ('Inspeksi', 'Housekeeping & Kerapian Area', 'Jalur akses/evakuasi tidak terhalang', 11),
    ('Inspeksi', 'Housekeeping & Kerapian Area', 'Material tersusun rapi, tidak menghalangi lalu lintas', 12),
    ('Inspeksi', 'APD (Alat Pelindung Diri)', 'Helm safety dipakai dengan benar', 20),
    ('Inspeksi', 'APD (Alat Pelindung Diri)', 'Sepatu safety sesuai standar', 21),
    ('Inspeksi', 'APD (Alat Pelindung Diri)', 'Sarung tangan sesuai jenis pekerjaan', 22),
    ('Inspeksi', 'APD (Alat Pelindung Diri)', 'Kacamata/pelindung wajah (jika diperlukan)', 23),
    ('Inspeksi', 'APD (Alat Pelindung Diri)', 'Rompi/pakaian reflektif', 24),
    ('Inspeksi', 'Bekerja di Ketinggian', 'Full body harness terpasang & terhubung dengan benar', 30),
    ('Inspeksi', 'Bekerja di Ketinggian', 'Scaffolding/perancah kondisi baik & bertag inspeksi', 31),
    ('Inspeksi', 'Bekerja di Ketinggian', 'Barikade/tanda peringatan area ketinggian terpasang', 32),
    ('Inspeksi', 'Alat & Perkakas Kerja', 'Alat kerja dalam kondisi baik & terinspeksi', 40),
    ('Inspeksi', 'Alat & Perkakas Kerja', 'Alat listrik/portable tidak ada kabel terkelupas', 41),
    ('Inspeksi', 'Alat & Perkakas Kerja', 'Alat berat memiliki operator bersertifikat & inspeksi harian', 42),
    ('Inspeksi', 'Kebakaran & Bahan Berbahaya (B3)', 'APAR tersedia, mudah dijangkau, tidak kadaluarsa', 50),
    ('Inspeksi', 'Kebakaran & Bahan Berbahaya (B3)', 'Bahan mudah terbakar disimpan sesuai prosedur', 51),
    ('Inspeksi', 'Kebakaran & Bahan Berbahaya (B3)', 'Label B3/MSDS tersedia di lokasi penyimpanan', 52),
    ('Inspeksi', 'Dokumen & Izin Kerja', 'Izin kerja (Permit to Work/JSA) tersedia di lokasi', 60),
    ('Inspeksi', 'Dokumen & Izin Kerja', 'Toolbox meeting sudah dilakukan sebelum kerja', 61),
    ('Inspeksi', 'Lingkungan', 'Penanganan limbah sesuai prosedur', 70),
    ('Inspeksi', 'Lingkungan', 'Tidak ada ceceran oli/bahan kimia ke tanah/saluran air', 71),
    -- ===== OBSERVASI LAPANGAN (perilaku pekerja / Behavior-Based Safety) =====
    ('Observasi', 'Perilaku Aman (Safe Behavior)', 'Pekerja mematuhi prosedur kerja yang ditetapkan', 10),
    ('Observasi', 'Perilaku Aman (Safe Behavior)', 'Pekerja menggunakan APD dengan benar selama bekerja', 11),
    ('Observasi', 'Perilaku Aman (Safe Behavior)', 'Pekerja tidak mengambil jalan pintas (shortcut) yang berisiko', 12),
    ('Observasi', 'Komunikasi & Kesadaran Risiko', 'Pekerja paham bahaya di area kerjanya (risk awareness)', 20),
    ('Observasi', 'Komunikasi & Kesadaran Risiko', 'Komunikasi antar pekerja/tim berjalan baik (radio, sinyal, dll)', 21),
    ('Observasi', 'Interaksi Positif (Positive Reinforcement)', 'Ada tindakan saling mengingatkan antar pekerja soal safety', 30),
    ('Observasi', 'Interaksi Positif (Positive Reinforcement)', 'Supervisor/leader aktif mengawasi & membimbing', 31),
    ('Observasi', 'Temuan Perilaku Tidak Aman', 'Ditemukan perilaku tidak aman yang perlu dicatat (isi keterangan kalau Tidak Sesuai)', 40)
) AS v("Jenis", "Kategori", "Item", "Urutan")
WHERE NOT EXISTS (SELECT 1 FROM "inspeksiChecklistTemplateTbl");


-- -------------------------------------------------------------------------------------
-- 2. TABEL LAPORAN INSPEKSI/OBSERVASI
-- -------------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS "inspeksiTbl" (
    "Id" BIGSERIAL PRIMARY KEY,
    "NoLaporan" TEXT UNIQUE NOT NULL,
    "Jenis" TEXT NOT NULL CHECK ("Jenis" IN ('Inspeksi', 'Observasi')),
    "ProjectId" BIGINT NOT NULL REFERENCES "projectTbl"("Id"),
    "TanggalWaktu" TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    "NamaInspektor" TEXT NOT NULL,
    "InspektorQrCodeId" TEXT DEFAULT '',
    "LokasiArea" TEXT NOT NULL,
    "ChecklistItems" JSONB NOT NULL DEFAULT '[]'::jsonb, -- [{id,kategori,item,hasil,keterangan,foto:{url,fileId}}]
    "CatatanUmum" TEXT DEFAULT '',
    "FotoUmumList" JSONB NOT NULL DEFAULT '[]'::jsonb,
    "JumlahSesuai" INT NOT NULL DEFAULT 0,
    "JumlahTidakSesuai" INT NOT NULL DEFAULT 0,
    "JumlahNA" INT NOT NULL DEFAULT 0,
    "SkorPersen" NUMERIC(5,2),
    "CermatId" BIGINT,
    "CermatNoLaporan" TEXT,
    "CreatedAt" TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_inspeksi_project ON "inspeksiTbl" ("ProjectId");
CREATE INDEX IF NOT EXISTS idx_inspeksi_jenis ON "inspeksiTbl" ("Jenis");


-- -------------------------------------------------------------------------------------
-- 3. LINK BALIK DARI cermatTbl -- biar riwayat CERMAT juga bisa nunjukin "temuan ini
--    asalnya dari Inspeksi/Observasi No. X" (jejak audit dua arah).
-- -------------------------------------------------------------------------------------
ALTER TABLE "cermatTbl"
    ADD COLUMN IF NOT EXISTS "SourceInspeksiId" BIGINT REFERENCES "inspeksiTbl"("Id");

ALTER TABLE "inspeksiTbl" DROP CONSTRAINT IF EXISTS "inspeksiTbl_CermatId_fkey";
ALTER TABLE "inspeksiTbl"
    ADD CONSTRAINT "inspeksiTbl_CermatId_fkey" FOREIGN KEY ("CermatId") REFERENCES "cermatTbl"("Id");


-- -------------------------------------------------------------------------------------
-- 4. RPC: GENERATE NOMOR LAPORAN -- prefix beda per Jenis (INSP / OBS)
-- -------------------------------------------------------------------------------------
DROP FUNCTION IF EXISTS generate_no_inspeksi(TEXT);
CREATE OR REPLACE FUNCTION generate_no_inspeksi(p_jenis TEXT)
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_date_str TEXT := TO_CHAR(NOW() AT TIME ZONE 'Asia/Makassar', 'YYYYMMDD');
    v_rand TEXT := LPAD(FLOOR(RANDOM() * 9000 + 1000)::TEXT, 4, '0');
    v_prefix TEXT := CASE WHEN p_jenis = 'Observasi' THEN 'OBS' ELSE 'INSP' END;
BEGIN
    RETURN 'BIMA/' || v_prefix || '/' || v_date_str || '-' || v_rand;
END;
$$;


-- -------------------------------------------------------------------------------------
-- 5. RPC: AMBIL TEMPLATE CHECKLIST BUAT SATU JENIS (dipakai form pas Jenis dipilih)
-- -------------------------------------------------------------------------------------
DROP FUNCTION IF EXISTS get_inspeksi_checklist_template(TEXT);
CREATE OR REPLACE FUNCTION get_inspeksi_checklist_template(p_jenis TEXT)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_result JSONB;
BEGIN
    SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'id', "Id",
        'kategori', "Kategori",
        'item', "Item"
    ) ORDER BY "Urutan"), '[]'::jsonb)
    INTO v_result
    FROM "inspeksiChecklistTemplateTbl"
    WHERE "Jenis" = p_jenis AND "Status" = 'Aktif';

    RETURN v_result;
END;
$$;


-- -------------------------------------------------------------------------------------
-- 6. RPC: SUBMIT LAPORAN INSPEKSI/OBSERVASI
-- p_checklist_items: [{ "id":.., "kategori":.., "item":.., "hasil": "Sesuai"|"Tidak Sesuai"|"N/A",
--                        "keterangan": "...", "foto": {"url":..,"fileId":..} | null }, ...]
-- Kalau ada >=1 item "Tidak Sesuai", otomatis bikin SATU laporan CERMAT gabungan
-- (Sifat=Negatif, JenisTemuan=Unsafe Condition) lewat submit_cermat_report() yang
-- sudah ada -- laporan Inspeksi ini nyimpen balik CermatId/CermatNoLaporan-nya.
-- -------------------------------------------------------------------------------------
DROP FUNCTION IF EXISTS submit_inspeksi_report(TEXT, BIGINT, TEXT, TEXT, JSONB, TEXT, TEXT, JSONB);
CREATE OR REPLACE FUNCTION submit_inspeksi_report(
    p_jenis TEXT,
    p_project_id BIGINT,
    p_nama_inspektor TEXT,
    p_lokasi_area TEXT,
    p_checklist_items JSONB,
    p_inspektor_qrcode TEXT DEFAULT '',
    p_catatan_umum TEXT DEFAULT '',
    p_foto_umum_list JSONB DEFAULT '[]'::jsonb
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_no_laporan TEXT;
    v_id BIGINT;
    v_sesuai INT := 0;
    v_tidak INT := 0;
    v_na INT := 0;
    v_skor NUMERIC(5,2);
    v_item JSONB;
    v_deskripsi TEXT := '';
    v_foto_cermat JSONB := '[]'::jsonb;
    v_cermat_result JSONB;
    v_cermat_id BIGINT;
    v_cermat_no TEXT;
BEGIN
    IF p_jenis NOT IN ('Inspeksi', 'Observasi') THEN
        RAISE EXCEPTION 'Jenis harus Inspeksi atau Observasi';
    END IF;
    IF p_checklist_items IS NULL OR jsonb_array_length(p_checklist_items) = 0 THEN
        RAISE EXCEPTION 'Checklist tidak boleh kosong';
    END IF;

    FOR v_item IN SELECT * FROM jsonb_array_elements(p_checklist_items) LOOP
        IF v_item->>'hasil' = 'Sesuai' THEN
            v_sesuai := v_sesuai + 1;
        ELSIF v_item->>'hasil' = 'Tidak Sesuai' THEN
            v_tidak := v_tidak + 1;
            v_deskripsi := v_deskripsi || '- [' || COALESCE(v_item->>'kategori', '') || '] ' || COALESCE(v_item->>'item', '')
                || CASE WHEN COALESCE(v_item->>'keterangan', '') <> '' THEN ' — ' || (v_item->>'keterangan') ELSE '' END
                || E'\n';
            IF v_item->'foto' IS NOT NULL AND v_item->'foto' <> 'null'::jsonb THEN
                v_foto_cermat := v_foto_cermat || jsonb_build_array(v_item->'foto');
            END IF;
        ELSE
            v_na := v_na + 1;
        END IF;
    END LOOP;

    v_skor := CASE WHEN (v_sesuai + v_tidak) > 0
        THEN ROUND((v_sesuai::NUMERIC / (v_sesuai + v_tidak)) * 100, 2)
        ELSE NULL END;

    v_no_laporan := generate_no_inspeksi(p_jenis);

    INSERT INTO "inspeksiTbl" (
        "NoLaporan", "Jenis", "ProjectId", "NamaInspektor", "InspektorQrCodeId", "LokasiArea",
        "ChecklistItems", "CatatanUmum", "FotoUmumList", "JumlahSesuai", "JumlahTidakSesuai", "JumlahNA", "SkorPersen"
    ) VALUES (
        v_no_laporan, p_jenis, p_project_id, p_nama_inspektor, p_inspektor_qrcode, p_lokasi_area,
        p_checklist_items, p_catatan_umum, p_foto_umum_list, v_sesuai, v_tidak, v_na, v_skor
    )
    RETURNING "Id" INTO v_id;

    IF v_tidak > 0 THEN
        v_cermat_result := submit_cermat_report(
            p_project_id,
            p_nama_inspektor,
            'Negatif',
            'Unsafe Condition',
            p_lokasi_area,
            'Temuan dari ' || p_jenis || ' Lapangan No. ' || v_no_laporan || ':' || E'\n' || v_deskripsi,
            p_inspektor_qrcode,
            v_foto_cermat,
            '',
            ''
        );
        v_cermat_id := (v_cermat_result->>'id')::BIGINT;
        v_cermat_no := v_cermat_result->>'noLaporan';

        UPDATE "cermatTbl" SET "SourceInspeksiId" = v_id WHERE "Id" = v_cermat_id;
        UPDATE "inspeksiTbl" SET "CermatId" = v_cermat_id, "CermatNoLaporan" = v_cermat_no WHERE "Id" = v_id;
    END IF;

    RETURN jsonb_build_object(
        'success', true,
        'id', v_id,
        'noLaporan', v_no_laporan,
        'skorPersen', v_skor,
        'jumlahSesuai', v_sesuai,
        'jumlahTidakSesuai', v_tidak,
        'jumlahNA', v_na,
        'cermatId', v_cermat_id,
        'cermatNoLaporan', v_cermat_no
    );
END;
$$;


-- -------------------------------------------------------------------------------------
-- 7. RPC: AMBIL DAFTAR LAPORAN (riwayat) -- p_jenis: NULL = semua, atau 'Inspeksi'/'Observasi'
-- -------------------------------------------------------------------------------------
DROP FUNCTION IF EXISTS get_inspeksi_reports(TEXT);
CREATE OR REPLACE FUNCTION get_inspeksi_reports(p_jenis TEXT DEFAULT NULL)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_result JSONB;
BEGIN
    SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'id', c."Id",
        'noLaporan', c."NoLaporan",
        'jenis', c."Jenis",
        'tanggalWaktu', c."TanggalWaktu",
        'namaInspektor', c."NamaInspektor",
        'inspektorQrCodeId', c."InspektorQrCodeId",
        'lokasiArea', c."LokasiArea",
        'checklistItems', c."ChecklistItems",
        'catatanUmum', c."CatatanUmum",
        'fotoUmumList', c."FotoUmumList",
        'jumlahSesuai', c."JumlahSesuai",
        'jumlahTidakSesuai', c."JumlahTidakSesuai",
        'jumlahNA', c."JumlahNA",
        'skorPersen', c."SkorPersen",
        'cermatId', c."CermatId",
        'cermatNoLaporan', c."CermatNoLaporan",
        'namaProject', p."NamaProject",
        'noKontrak', p."NoKontrak"
    ) ORDER BY c."TanggalWaktu" DESC), '[]'::JSONB)
    INTO v_result
    FROM "inspeksiTbl" c
    JOIN "projectTbl" p ON p."Id" = c."ProjectId"
    WHERE p_jenis IS NULL OR c."Jenis" = p_jenis;

    RETURN v_result;
END;
$$;


-- -------------------------------------------------------------------------------------
-- 8. RPC: AMBIL SATU LAPORAN BY ID (siap dipakai buat inspeksi-pdf.html nanti)
-- -------------------------------------------------------------------------------------
DROP FUNCTION IF EXISTS get_inspeksi_report_by_id(BIGINT);
CREATE OR REPLACE FUNCTION get_inspeksi_report_by_id(p_id BIGINT)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_result JSONB;
BEGIN
    SELECT jsonb_build_object(
        'id', c."Id",
        'noLaporan', c."NoLaporan",
        'jenis', c."Jenis",
        'tanggalWaktu', c."TanggalWaktu",
        'namaInspektor', c."NamaInspektor",
        'inspektorQrCodeId', c."InspektorQrCodeId",
        'lokasiArea', c."LokasiArea",
        'checklistItems', c."ChecklistItems",
        'catatanUmum', c."CatatanUmum",
        'fotoUmumList', c."FotoUmumList",
        'jumlahSesuai', c."JumlahSesuai",
        'jumlahTidakSesuai', c."JumlahTidakSesuai",
        'jumlahNA', c."JumlahNA",
        'skorPersen', c."SkorPersen",
        'cermatId', c."CermatId",
        'cermatNoLaporan', c."CermatNoLaporan",
        'namaProject', p."NamaProject",
        'noKontrak', p."NoKontrak",
        'tipeKonstruksi', p."TipeKonstruksi"
    )
    INTO v_result
    FROM "inspeksiTbl" c
    JOIN "projectTbl" p ON p."Id" = c."ProjectId"
    WHERE c."Id" = p_id;

    RETURN v_result;
END;
$$;


-- -------------------------------------------------------------------------------------
-- 9. UPDATE get_cermat_reports & get_cermat_report_by_id -- tambah sourceInspeksiId biar
--    Riwayat CERMAT juga bisa nunjukin asal-usul temuan (kalau dari auto-generate ini).
-- -------------------------------------------------------------------------------------
DROP FUNCTION IF EXISTS get_cermat_reports(TEXT);
CREATE OR REPLACE FUNCTION get_cermat_reports(p_status TEXT DEFAULT NULL)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_result JSONB;
BEGIN
    SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'id', c."Id",
        'noLaporan', c."NoLaporan",
        'tanggalWaktu', c."TanggalWaktu",
        'namaPelapor', c."NamaPelapor",
        'pelaporQrCodeId', c."PelaporQrCodeId",
        'sifat', c."Sifat",
        'jenisTemuan', c."JenisTemuan",
        'lokasiArea', c."LokasiArea",
        'deskripsi', c."Deskripsi",
        'fotoList', c."FotoList",
        'fotoTindakLanjutList', c."FotoTindakLanjutList",
        'tindakanLangsung', c."TindakanLangsung",
        'rekomendasi', c."Rekomendasi",
        'penanggungJawab', c."PenanggungJawab",
        'tenggat', c."Tenggat",
        'status', c."Status",
        'tanggalClosed', c."TanggalClosed",
        'assignedDivisi', c."AssignedDivisi",
        'assignedDeptNama', c."AssignedDeptNama",
        'verifikatorOleh', c."VerifikatorOleh",
        'verifikatorQrCodeId', c."VerifikatorQrCodeId",
        'tanggalVerifikasi', c."TanggalVerifikasi",
        'followupOleh', c."FollowupOleh",
        'followupQrCodeId', c."FollowupQrCodeId",
        'tanggalFollowup', c."TanggalFollowup",
        'catatanFollowup', c."CatatanFollowup",
        'catatanPenolakan', c."CatatanPenolakan",
        'ditutupOleh', c."DitutupOleh",
        'ditutupQrCodeId', c."DitutupQrCodeId",
        'sourceInspeksiId', c."SourceInspeksiId",
        'sourceInspeksiNoLaporan', i."NoLaporan",
        'namaProject', p."NamaProject",
        'noKontrak', p."NoKontrak"
    ) ORDER BY c."TanggalWaktu" DESC), '[]'::JSONB)
    INTO v_result
    FROM "cermatTbl" c
    JOIN "projectTbl" p ON p."Id" = c."ProjectId"
    LEFT JOIN "inspeksiTbl" i ON i."Id" = c."SourceInspeksiId"
    WHERE p_status IS NULL OR c."Status" = p_status;

    RETURN v_result;
END;
$$;


DROP FUNCTION IF EXISTS get_cermat_report_by_id(BIGINT);
CREATE OR REPLACE FUNCTION get_cermat_report_by_id(p_id BIGINT)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_result JSONB;
BEGIN
    SELECT jsonb_build_object(
        'id', c."Id",
        'noLaporan', c."NoLaporan",
        'tanggalWaktu', c."TanggalWaktu",
        'namaPelapor', c."NamaPelapor",
        'pelaporQrCodeId', c."PelaporQrCodeId",
        'sifat', c."Sifat",
        'jenisTemuan', c."JenisTemuan",
        'lokasiArea', c."LokasiArea",
        'deskripsi', c."Deskripsi",
        'fotoList', c."FotoList",
        'fotoTindakLanjutList', c."FotoTindakLanjutList",
        'tindakanLangsung', c."TindakanLangsung",
        'rekomendasi', c."Rekomendasi",
        'penanggungJawab', c."PenanggungJawab",
        'tenggat', c."Tenggat",
        'status', c."Status",
        'tanggalClosed', c."TanggalClosed",
        'assignedDivisi', c."AssignedDivisi",
        'assignedDeptNama', c."AssignedDeptNama",
        'verifikatorOleh', c."VerifikatorOleh",
        'verifikatorQrCodeId', c."VerifikatorQrCodeId",
        'tanggalVerifikasi', c."TanggalVerifikasi",
        'followupOleh', c."FollowupOleh",
        'followupQrCodeId', c."FollowupQrCodeId",
        'tanggalFollowup', c."TanggalFollowup",
        'catatanFollowup', c."CatatanFollowup",
        'catatanPenolakan', c."CatatanPenolakan",
        'ditutupOleh', c."DitutupOleh",
        'ditutupQrCodeId', c."DitutupQrCodeId",
        'sourceInspeksiId', c."SourceInspeksiId",
        'sourceInspeksiNoLaporan', i."NoLaporan",
        'namaProject', p."NamaProject",
        'noKontrak', p."NoKontrak",
        'tipeKonstruksi', p."TipeKonstruksi"
    )
    INTO v_result
    FROM "cermatTbl" c
    JOIN "projectTbl" p ON p."Id" = c."ProjectId"
    LEFT JOIN "inspeksiTbl" i ON i."Id" = c."SourceInspeksiId"
    WHERE c."Id" = p_id;

    RETURN v_result;
END;
$$;
