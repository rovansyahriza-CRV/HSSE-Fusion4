-- =====================================================================================
-- 070 -- Modul Inspeksi Alat & Sertifikasi (Tools & Equipment)
-- Jalankan di project Supabase HSSE-Fusion4 (BUKAN Fusion4 SmartGate). Run after 069.
--
-- Isi:
--   alatTbl                  = register alat/peralatan per project (alat angkat, alat berat,
--                              kelistrikan, bejana tekan, APAR, gas detector, dll)
--   alatSertifikatTbl        = sertifikat per alat (SILO/riksa uji, PJK3, kalibrasi, load test, ...)
--                              + masa berlaku (pengingat kedaluwarsa)
--   alatInspeksiTbl          = inspeksi alat (pre-use, mingguan, bulanan/color code, ...) pakai checklist
--   alatChecklistTemplateTbl = master checklist per kategori alat (edit lewat SQL/Table Editor,
--                              sama kayak inspeksiChecklistTemplateTbl di modul Inspeksi)
-- Alur inspeksi:
--   (save_alat_inspeksi) Menunggu Approval -> (approve_alat_inspeksi) Disetujui | Dikembalikan -> edit -> Menunggu Approval
-- Kondisi alat (Layak / Layak dengan Catatan / Tidak Layak) = hasil inspeksi terakhir yang
--   sudah Disetujui. Pengecualian demi keselamatan: hasil "Tidak Layak" langsung berlaku
--   begitu inspeksi disimpan (tag out), tanpa menunggu approval. Alat Tidak Layak baru
--   kembali Layak setelah inspeksi berikutnya (mis. Pasca Perbaikan) Disetujui.
-- Akses (dicek di server lewat hsse_wajib_akses dari 065):
--   register alat, sertifikat, inspeksi = PIC HSSE-ALT (atau HSSE-ALL)
--   setujui / kembalikan inspeksi       = Author "Approve Inspeksi Alat" (tidak ikut HSSE-ALL)
-- HSE Program: item TOOLS_EQUIPMENT_COMPLIANCE jadi OTOMATIS = jumlah inspeksi alat Disetujui,
--   bulan = tanggal inspeksi (WIB). Dicek 2026-10-13: belum ada baris HSE Program untuk item ini,
--   jadi tidak ada angka manual yang hilang.
--   get_hse_program dan get_management_review_frame diganti (salinan 069) supaya realisasi
--   modul tambahan diambil dari satu helper: hse_program_realisasi_modul (drill + alat).
--   Modul berikutnya cukup mengganti helper itu, tidak perlu menyalin 2 fungsi besar lagi.
-- Tabel tidak bisa dibaca/ditulis langsung pakai anon key; semua lewat RPC.
-- Aman dijalankan ulang.
-- =====================================================================================

-- -------------------------------------------------------------------------------------
-- 1. Tabel
-- -------------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS "alatTbl" (
    "Id"                   BIGSERIAL PRIMARY KEY,
    "NoAlat"               TEXT NOT NULL UNIQUE,            -- ALT/<kode project>/0001 (otomatis)
    "NoAset"               TEXT,                            -- nomor aset / lambung internal (opsional)
    "ProjectId"            BIGINT NOT NULL REFERENCES "projectTbl"("Id"),
    "Kategori"             TEXT NOT NULL CHECK ("Kategori" IN (
                               'Alat Angkat & Lifting Gear', 'Alat Berat & Kendaraan', 'Kelistrikan & Power Tools',
                               'Bejana Tekan & Kompresor', 'Peralatan Las & Tabung Gas', 'Scaffolding & Tangga',
                               'APAR & Peralatan Pemadam', 'Gas Detector & Alat Ukur', 'Hand Tools', 'Lainnya')),
    "NamaAlat"             TEXT NOT NULL,
    "MerkTipe"             TEXT,
    "NoSeri"               TEXT,
    "Kapasitas"            TEXT,                            -- cth. SWL 5 ton, 9 kg, 10 bar
    "Pemilik"              TEXT NOT NULL DEFAULT 'BIMA' CHECK ("Pemilik" IN ('BIMA', 'Subkon', 'Sewa / Rental', 'Client')),
    "NamaPemilik"          TEXT,                            -- nama subkon / vendor rental / client
    "LokasiArea"           TEXT,
    "IntervalInspeksiHari" INT NOT NULL DEFAULT 30 CHECK ("IntervalInspeksiHari" BETWEEN 1 AND 730),
    "WajibSertifikat"      BOOLEAN NOT NULL DEFAULT TRUE,
    "StatusAlat"           TEXT NOT NULL DEFAULT 'Aktif' CHECK ("StatusAlat" IN ('Aktif', 'Tidak Dipakai')),
    "Keterangan"           TEXT,
    "Kondisi"              TEXT NOT NULL DEFAULT 'Belum Diinspeksi'
                           CHECK ("Kondisi" IN ('Belum Diinspeksi', 'Layak', 'Layak dengan Catatan', 'Tidak Layak')),
    "KondisiInspeksiId"    BIGINT,                          -- inspeksi yang menentukan Kondisi
    "KondisiTanggal"       TIMESTAMPTZ,
    "WarnaTag"             TEXT,
    "DibuatOleh"           TEXT,
    "DibuatQrCodeId"       TEXT,
    "DiubahOleh"           TEXT,
    "CreatedAt"            TIMESTAMPTZ NOT NULL DEFAULT now(),
    "UpdatedAt"            TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_alat_project ON "alatTbl" ("ProjectId", "StatusAlat", "Kategori");

CREATE TABLE IF NOT EXISTS "alatSertifikatTbl" (
    "Id"               BIGSERIAL PRIMARY KEY,
    "AlatId"           BIGINT NOT NULL REFERENCES "alatTbl"("Id") ON DELETE CASCADE,
    "JenisSertifikat"  TEXT NOT NULL CHECK ("JenisSertifikat" IN (
                           'SILO / Riksa Uji Disnaker', 'Sertifikat Inspeksi PJK3 / Third Party', 'Kalibrasi',
                           'Load Test', 'Sertifikat Pabrikan / COC', 'Lainnya')),
    "NoSertifikat"     TEXT NOT NULL,
    "Penerbit"         TEXT,
    "TanggalTerbit"    DATE,
    "BerlakuSampai"    DATE,                                -- NULL = tidak ada masa berlaku
    "LinkDokumen"      TEXT,
    "Catatan"          TEXT,
    "DicatatOleh"      TEXT,
    "DicatatQrCodeId"  TEXT,
    "DiubahOleh"       TEXT,
    "CreatedAt"        TIMESTAMPTZ NOT NULL DEFAULT now(),
    "UpdatedAt"        TIMESTAMPTZ NOT NULL DEFAULT now(),
    CHECK ("BerlakuSampai" IS NULL OR "TanggalTerbit" IS NULL OR "BerlakuSampai" >= "TanggalTerbit")
);
CREATE INDEX IF NOT EXISTS idx_alat_sertifikat ON "alatSertifikatTbl" ("AlatId", "JenisSertifikat", "TanggalTerbit");

CREATE TABLE IF NOT EXISTS "alatInspeksiTbl" (
    "Id"                 BIGSERIAL PRIMARY KEY,
    "NoInspeksi"         TEXT NOT NULL UNIQUE,              -- INA/<kode project>/<tahun>/001
    "AlatId"             BIGINT NOT NULL REFERENCES "alatTbl"("Id"),
    "ProjectId"          BIGINT NOT NULL REFERENCES "projectTbl"("Id"),
    "TanggalInspeksi"    TIMESTAMPTZ NOT NULL,
    "JenisInspeksi"      TEXT NOT NULL CHECK ("JenisInspeksi" IN (
                             'Pre-use / Harian', 'Mingguan', 'Bulanan / Color Code', 'Pasca Perbaikan', 'Insidental')),
    "WarnaTag"           TEXT,
    "LokasiArea"         TEXT,
    "ChecklistList"      JSONB NOT NULL DEFAULT '[]'::JSONB, -- [{item, hasil: Baik/Tidak Baik/N/A, catatan}]
    "JumlahBaik"         INT NOT NULL DEFAULT 0,
    "JumlahTidakBaik"    INT NOT NULL DEFAULT 0,
    "Hasil"              TEXT NOT NULL CHECK ("Hasil" IN ('Layak', 'Layak dengan Catatan', 'Tidak Layak')),
    "TemuanTindakan"     TEXT,
    "FotoList"           JSONB NOT NULL DEFAULT '[]'::JSONB, -- [{url, fileId}]
    "Inspektor"          TEXT,
    "InspektorQrCodeId"  TEXT,
    "Status"             TEXT NOT NULL DEFAULT 'Menunggu Approval'
                         CHECK ("Status" IN ('Menunggu Approval', 'Dikembalikan', 'Disetujui')),
    "DisetujuiOleh"      TEXT,
    "DisetujuiQrCodeId"  TEXT,
    "TanggalDisetujui"   TIMESTAMPTZ,
    "CatatanApproval"    TEXT,
    "DiubahOleh"         TEXT,
    "CreatedAt"          TIMESTAMPTZ NOT NULL DEFAULT now(),
    "UpdatedAt"          TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_alat_inspeksi_alat ON "alatInspeksiTbl" ("AlatId", "TanggalInspeksi");
CREATE INDEX IF NOT EXISTS idx_alat_inspeksi_project ON "alatInspeksiTbl" ("ProjectId", "Status", "TanggalInspeksi");

CREATE TABLE IF NOT EXISTS "alatChecklistTemplateTbl" (
    "Id"        BIGSERIAL PRIMARY KEY,
    "Kategori"  TEXT NOT NULL,                              -- kategori alat, atau 'Umum' = ikut semua kategori
    "Item"      TEXT NOT NULL,
    "Urutan"    INT NOT NULL DEFAULT 0,
    "Status"    TEXT NOT NULL DEFAULT 'Aktif' CHECK ("Status" IN ('Aktif', 'Non-Aktif')),
    "CreatedAt" TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_alat_checklist_kategori ON "alatChecklistTemplateTbl" ("Kategori", "Status", "Urutan");

-- Seed draft checklist HANYA kalau tabel masih kosong (biar editan kalian tidak ketimpa).
INSERT INTO "alatChecklistTemplateTbl" ("Kategori", "Item", "Urutan")
SELECT * FROM (VALUES
    ('Umum', 'Label / nomor alat & tag inspeksi terpasang dan terbaca', 1),
    ('Umum', 'Sertifikat / dokumen alat masih berlaku (kalau wajib)', 2),
    ('Alat Angkat & Lifting Gear', 'SWL / kapasitas tertera jelas', 10),
    ('Alat Angkat & Lifting Gear', 'Wire rope / sling: tidak putus serabut, tidak tertekuk (kink), tidak berkarat parah', 11),
    ('Alat Angkat & Lifting Gear', 'Hook: safety latch berfungsi, tidak melebar / retak', 12),
    ('Alat Angkat & Lifting Gear', 'Shackle, master link, eye bolt: pin lengkap, tidak aus / berubah bentuk', 13),
    ('Alat Angkat & Lifting Gear', 'Chain block / lever hoist: rem dan rantai berfungsi baik', 14),
    ('Alat Angkat & Lifting Gear', 'Limit switch, load indicator & alarm crane berfungsi', 15),
    ('Alat Angkat & Lifting Gear', 'Outrigger / pad dan landasan stabil', 16),
    ('Alat Berat & Kendaraan', 'Rem, setir & sabuk pengaman berfungsi', 20),
    ('Alat Berat & Kendaraan', 'Lampu, klakson & alarm mundur berfungsi', 21),
    ('Alat Berat & Kendaraan', 'Tidak ada kebocoran oli / bahan bakar / hidrolik', 22),
    ('Alat Berat & Kendaraan', 'Ban / track kondisi baik', 23),
    ('Alat Berat & Kendaraan', 'APAR tersedia di unit', 24),
    ('Alat Berat & Kendaraan', 'Kaca, spion & kabin dalam kondisi baik', 25),
    ('Alat Berat & Kendaraan', 'Operator memiliki SIO / SIM yang berlaku', 26),
    ('Kelistrikan & Power Tools', 'Kabel & isolasi tidak terkelupas / tersambung tidak standar', 30),
    ('Kelistrikan & Power Tools', 'Steker / plug & stop kontak dalam kondisi baik', 31),
    ('Kelistrikan & Power Tools', 'Guard / pelindung mata gerinda / pisau terpasang', 32),
    ('Kelistrikan & Power Tools', 'Grounding / ELCB / RCD berfungsi', 33),
    ('Kelistrikan & Power Tools', 'Saklar on/off berfungsi normal', 34),
    ('Kelistrikan & Power Tools', 'Panel listrik tertutup, berlabel & bebas hambatan', 35),
    ('Bejana Tekan & Kompresor', 'Pressure gauge berfungsi & terbaca', 40),
    ('Bejana Tekan & Kompresor', 'Safety valve / relief valve terpasang & tidak dimodifikasi', 41),
    ('Bejana Tekan & Kompresor', 'Selang & sambungan tidak bocor, whip check terpasang', 42),
    ('Bejana Tekan & Kompresor', 'Badan tabung tidak korosi / penyok', 43),
    ('Bejana Tekan & Kompresor', 'Drain valve berfungsi', 44),
    ('Peralatan Las & Tabung Gas', 'Kabel las & holder tidak terkelupas', 50),
    ('Peralatan Las & Tabung Gas', 'Regulator & gauge tabung berfungsi', 51),
    ('Peralatan Las & Tabung Gas', 'Flashback arrestor terpasang (oksi-asetilen)', 52),
    ('Peralatan Las & Tabung Gas', 'Tabung diikat tegak, tutup valve tersedia', 53),
    ('Peralatan Las & Tabung Gas', 'Selang gas tidak retak / bocor', 54),
    ('Scaffolding & Tangga', 'Base plate / sole board & landasan stabil', 60),
    ('Scaffolding & Tangga', 'Guardrail, midrail & toe board lengkap', 61),
    ('Scaffolding & Tangga', 'Platform / papan terkunci, tidak ada celah', 62),
    ('Scaffolding & Tangga', 'Bracing & coupler terpasang kencang', 63),
    ('Scaffolding & Tangga', 'Akses tangga aman', 64),
    ('Scaffolding & Tangga', 'Scaff tag sesuai status (hijau / merah)', 65),
    ('APAR & Peralatan Pemadam', 'Jarum tekanan di zona hijau', 70),
    ('APAR & Peralatan Pemadam', 'Pin pengaman & segel utuh', 71),
    ('APAR & Peralatan Pemadam', 'Selang & nozzle tidak retak / tersumbat', 72),
    ('APAR & Peralatan Pemadam', 'Tabung tidak berkarat / penyok', 73),
    ('APAR & Peralatan Pemadam', 'Mudah dijangkau, ada rambu & tidak terhalang', 74),
    ('APAR & Peralatan Pemadam', 'Kartu inspeksi bulanan terisi', 75),
    ('Gas Detector & Alat Ukur', 'Bump test / functional test lulus', 80),
    ('Gas Detector & Alat Ukur', 'Kalibrasi masih berlaku', 81),
    ('Gas Detector & Alat Ukur', 'Baterai cukup / pengisian normal', 82),
    ('Gas Detector & Alat Ukur', 'Sensor & alarm (bunyi / getar / lampu) berfungsi', 83),
    ('Hand Tools', 'Gagang / pegangan tidak retak atau longgar', 90),
    ('Hand Tools', 'Mata / ujung alat tidak aus atau tumpul berlebihan', 91),
    ('Hand Tools', 'Tidak ada modifikasi non-standar', 92),
    ('Hand Tools', 'Disimpan rapi di toolbox / rak', 93),
    ('Lainnya', 'Kondisi fisik alat baik (tidak retak / bocor / aus berlebihan)', 100),
    ('Lainnya', 'Pengaman / guard lengkap', 101),
    ('Lainnya', 'Berfungsi normal saat dicoba', 102)
) AS v("Kategori", "Item", "Urutan")
WHERE NOT EXISTS (SELECT 1 FROM "alatChecklistTemplateTbl");

ALTER TABLE "alatTbl" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "alatSertifikatTbl" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "alatInspeksiTbl" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "alatChecklistTemplateTbl" ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "alatTbl_no_direct" ON "alatTbl";
CREATE POLICY "alatTbl_no_direct" ON "alatTbl" FOR ALL TO anon, authenticated USING (false) WITH CHECK (false);
DROP POLICY IF EXISTS "alatSertifikatTbl_no_direct" ON "alatSertifikatTbl";
CREATE POLICY "alatSertifikatTbl_no_direct" ON "alatSertifikatTbl" FOR ALL TO anon, authenticated USING (false) WITH CHECK (false);
DROP POLICY IF EXISTS "alatInspeksiTbl_no_direct" ON "alatInspeksiTbl";
CREATE POLICY "alatInspeksiTbl_no_direct" ON "alatInspeksiTbl" FOR ALL TO anon, authenticated USING (false) WITH CHECK (false);
DROP POLICY IF EXISTS "alatChecklistTemplateTbl_no_direct" ON "alatChecklistTemplateTbl";
CREATE POLICY "alatChecklistTemplateTbl_no_direct" ON "alatChecklistTemplateTbl" FOR ALL TO anon, authenticated USING (false) WITH CHECK (false);

-- -------------------------------------------------------------------------------------
-- 2. Helper
-- -------------------------------------------------------------------------------------
-- Sisa hari & status 1 sertifikat (Berlaku / Segera Habis = <= 30 hari / Kedaluwarsa / Tanpa Masa Berlaku)
CREATE OR REPLACE FUNCTION public.alat_sertifikat_json(s "alatSertifikatTbl")
RETURNS JSONB LANGUAGE sql STABLE AS $$
    SELECT jsonb_build_object(
        'id', s."Id", 'alatId', s."AlatId", 'jenisSertifikat', s."JenisSertifikat", 'noSertifikat', s."NoSertifikat",
        'penerbit', s."Penerbit", 'tanggalTerbit', s."TanggalTerbit", 'berlakuSampai', s."BerlakuSampai",
        'linkDokumen', s."LinkDokumen", 'catatan', s."Catatan", 'dicatatOleh', s."DicatatOleh",
        'diubahOleh', s."DiubahOleh", 'createdAt', s."CreatedAt",
        'sisaHari', s."BerlakuSampai" - (now() AT TIME ZONE 'Asia/Jakarta')::DATE,
        'statusBerlaku', CASE
            WHEN s."BerlakuSampai" IS NULL THEN 'Tanpa Masa Berlaku'
            WHEN s."BerlakuSampai" < (now() AT TIME ZONE 'Asia/Jakarta')::DATE THEN 'Kedaluwarsa'
            WHEN s."BerlakuSampai" - (now() AT TIME ZONE 'Asia/Jakarta')::DATE <= 30 THEN 'Segera Habis'
            ELSE 'Berlaku' END);
$$;

-- Sertifikat yang sedang dipakai = yang terbaru per jenis (terbit paling akhir) untuk 1 alat.
CREATE OR REPLACE FUNCTION public.alat_sertifikat_terkini(p_alat_id BIGINT)
RETURNS SETOF "alatSertifikatTbl" LANGUAGE sql STABLE SET search_path = public AS $$
    SELECT DISTINCT ON (s."JenisSertifikat") s.*
    FROM "alatSertifikatTbl" s
    WHERE s."AlatId" = p_alat_id
    ORDER BY s."JenisSertifikat", s."TanggalTerbit" DESC NULLS LAST, s."BerlakuSampai" DESC NULLS LAST, s."Id" DESC;
$$;

CREATE OR REPLACE FUNCTION public.alat_header_json(a "alatTbl")
RETURNS JSONB LANGUAGE sql STABLE SET search_path = public AS $$
    WITH sert AS (
        SELECT min(s."BerlakuSampai") AS habis, count(*) AS jumlah
        FROM public.alat_sertifikat_terkini(a."Id") s
    ), insp AS (
        SELECT max(i."TanggalInspeksi") AS terakhir,
               count(*) FILTER (WHERE i."Status" = 'Menunggu Approval') AS menunggu,
               count(*) FILTER (WHERE i."Status" = 'Dikembalikan') AS dikembalikan
        FROM "alatInspeksiTbl" i WHERE i."AlatId" = a."Id"
    ), hari AS (SELECT (now() AT TIME ZONE 'Asia/Jakarta')::DATE AS ini)
    SELECT jsonb_build_object(
        'id', a."Id", 'noAlat', a."NoAlat", 'noAset', a."NoAset", 'projectId', a."ProjectId",
        'namaProject', p."NamaProject", 'kodeOperational', p."KodeOperational", 'noKontrak', p."NoKontrak",
        'client', p."Client",
        'kategori', a."Kategori", 'namaAlat', a."NamaAlat", 'merkTipe', a."MerkTipe", 'noSeri', a."NoSeri",
        'kapasitas', a."Kapasitas", 'pemilik', a."Pemilik", 'namaPemilik', a."NamaPemilik",
        'lokasiArea', a."LokasiArea", 'intervalInspeksiHari', a."IntervalInspeksiHari",
        'wajibSertifikat', a."WajibSertifikat", 'statusAlat', a."StatusAlat", 'keterangan', a."Keterangan",
        'kondisi', a."Kondisi", 'kondisiInspeksiId', a."KondisiInspeksiId", 'kondisiTanggal', a."KondisiTanggal",
        'warnaTag', a."WarnaTag",
        'dibuatOleh', a."DibuatOleh", 'diubahOleh', a."DiubahOleh", 'createdAt', a."CreatedAt", 'updatedAt', a."UpdatedAt",
        'jumlahSertifikat', sert.jumlah,
        'sertifikatBerlakuSampai', sert.habis,
        'sertifikatStatus', CASE
            WHEN sert.jumlah = 0 THEN CASE WHEN a."WajibSertifikat" THEN 'Belum Ada' ELSE 'Tidak Wajib' END
            WHEN sert.habis IS NULL THEN 'Berlaku'
            WHEN sert.habis < hari.ini THEN 'Kedaluwarsa'
            WHEN sert.habis - hari.ini <= 30 THEN 'Segera Habis'
            ELSE 'Berlaku' END,
        'inspeksiTerakhir', insp.terakhir,
        'jatuhTempo', CASE WHEN insp.terakhir IS NOT NULL
            THEN (insp.terakhir AT TIME ZONE 'Asia/Jakarta')::DATE + a."IntervalInspeksiHari" END,
        'lewatTempo', a."StatusAlat" = 'Aktif' AND (insp.terakhir IS NULL
            OR (insp.terakhir AT TIME ZONE 'Asia/Jakarta')::DATE + a."IntervalInspeksiHari" < hari.ini),
        'inspeksiMenunggu', insp.menunggu, 'inspeksiDikembalikan', insp.dikembalikan)
    FROM "projectTbl" p, sert, insp, hari
    WHERE p."Id" = a."ProjectId";
$$;

CREATE OR REPLACE FUNCTION public.alat_inspeksi_json(i "alatInspeksiTbl")
RETURNS JSONB LANGUAGE sql STABLE SET search_path = public AS $$
    SELECT jsonb_build_object(
        'id', i."Id", 'noInspeksi', i."NoInspeksi", 'alatId', i."AlatId", 'projectId', i."ProjectId",
        'noAlat', a."NoAlat", 'noAset', a."NoAset", 'namaAlat', a."NamaAlat", 'kategori', a."Kategori",
        'merkTipe', a."MerkTipe", 'noSeri', a."NoSeri", 'kapasitas', a."Kapasitas",
        'namaProject', p."NamaProject", 'kodeOperational', p."KodeOperational", 'noKontrak', p."NoKontrak",
        'client', p."Client",
        'tanggalInspeksi', i."TanggalInspeksi", 'jenisInspeksi', i."JenisInspeksi", 'warnaTag', i."WarnaTag",
        'lokasiArea', i."LokasiArea", 'jumlahBaik', i."JumlahBaik", 'jumlahTidakBaik', i."JumlahTidakBaik",
        'hasil', i."Hasil", 'temuanTindakan', i."TemuanTindakan",
        'inspektor', i."Inspektor", 'status', i."Status",
        'disetujuiOleh', i."DisetujuiOleh", 'tanggalDisetujui', i."TanggalDisetujui",
        'catatanApproval', i."CatatanApproval", 'diubahOleh', i."DiubahOleh",
        'createdAt', i."CreatedAt", 'updatedAt', i."UpdatedAt")
    FROM "alatTbl" a JOIN "projectTbl" p ON p."Id" = i."ProjectId"
    WHERE a."Id" = i."AlatId";
$$;

-- Hitung ulang Kondisi alat: inspeksi terakhir yang Disetujui, ATAU yang hasilnya Tidak Layak
-- (tag out langsung berlaku walau belum disetujui).
CREATE OR REPLACE FUNCTION public.alat_refresh_kondisi(p_alat_id BIGINT)
RETURNS VOID LANGUAGE plpgsql SET search_path = public AS $$
DECLARE
    v_i "alatInspeksiTbl";
BEGIN
    SELECT * INTO v_i FROM "alatInspeksiTbl"
    WHERE "AlatId" = p_alat_id AND ("Status" = 'Disetujui' OR "Hasil" = 'Tidak Layak')
    ORDER BY "TanggalInspeksi" DESC, "Id" DESC LIMIT 1;
    UPDATE "alatTbl" SET
        "Kondisi" = COALESCE(v_i."Hasil", 'Belum Diinspeksi'),
        "KondisiInspeksiId" = v_i."Id",
        "KondisiTanggal" = v_i."TanggalInspeksi",
        "WarnaTag" = v_i."WarnaTag"
    WHERE "Id" = p_alat_id;
END;
$$;

-- Realisasi HSE Program dari modul ini
CREATE OR REPLACE FUNCTION public.alat_realisasi_bulanan(p_project_id BIGINT, p_tahun INT)
RETURNS TABLE (kode TEXT, bulan INT, jumlah BIGINT)
LANGUAGE sql STABLE SET search_path = public AS $$
    SELECT 'TOOLS_EQUIPMENT_COMPLIANCE', EXTRACT(MONTH FROM ("TanggalInspeksi" AT TIME ZONE 'Asia/Jakarta'))::INT, count(*)
    FROM "alatInspeksiTbl"
    WHERE "ProjectId" = p_project_id AND "Status" = 'Disetujui'
      AND EXTRACT(YEAR FROM ("TanggalInspeksi" AT TIME ZONE 'Asia/Jakarta')) = p_tahun
    GROUP BY 2;
$$;

-- Satu pintu realisasi modul tambahan (069 drill/ERP + 070 alat) untuk get_hse_program &
-- get_management_review_frame. Modul baru cukup menambah UNION ALL di sini.
CREATE OR REPLACE FUNCTION public.hse_program_realisasi_modul(p_project_id BIGINT, p_tahun INT)
RETURNS TABLE (kode TEXT, bulan INT, jumlah BIGINT)
LANGUAGE sql STABLE SET search_path = public AS $$
    SELECT dr.kode, dr.bulan, dr.jumlah FROM public.drill_realisasi_bulanan(p_project_id, p_tahun) dr
    UNION ALL
    SELECT al.kode, al.bulan, al.jumlah FROM public.alat_realisasi_bulanan(p_project_id, p_tahun) al;
$$;

-- -------------------------------------------------------------------------------------
-- 3. Baca (terbuka, sama kayak list modul lain)
-- -------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_alat_list(p_project_id BIGINT DEFAULT NULL, p_kategori TEXT DEFAULT NULL,
                                                p_status_alat TEXT DEFAULT 'Aktif', p_cari TEXT DEFAULT NULL)
RETURNS JSONB LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
    SELECT COALESCE(jsonb_agg(public.alat_header_json(a) ORDER BY a."Kategori", a."NamaAlat", a."NoAlat"), '[]'::JSONB)
    FROM "alatTbl" a
    WHERE (p_project_id IS NULL OR a."ProjectId" = p_project_id)
      AND (COALESCE(p_kategori, '') = '' OR a."Kategori" = p_kategori)
      AND (COALESCE(p_status_alat, '') = '' OR a."StatusAlat" = p_status_alat)
      AND (COALESCE(trim(p_cari), '') = '' OR concat_ws(' ', a."NoAlat", a."NoAset", a."NamaAlat", a."MerkTipe",
                                                         a."NoSeri", a."NamaPemilik", a."LokasiArea") ILIKE '%' || trim(p_cari) || '%');
$$;

CREATE OR REPLACE FUNCTION public.get_alat_detail(p_id BIGINT)
RETURNS JSONB LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
    SELECT public.alat_header_json(a) || jsonb_build_object(
        'sertifikatList', COALESCE((
            SELECT jsonb_agg(public.alat_sertifikat_json(s) || jsonb_build_object(
                       'terkini', s."Id" IN (SELECT t."Id" FROM public.alat_sertifikat_terkini(a."Id") t))
                   ORDER BY s."JenisSertifikat", s."TanggalTerbit" DESC NULLS LAST, s."Id" DESC)
            FROM "alatSertifikatTbl" s WHERE s."AlatId" = a."Id"), '[]'::JSONB),
        'inspeksiList', COALESCE((
            SELECT jsonb_agg(x.j ORDER BY x.t DESC, x.id DESC) FROM (
                SELECT public.alat_inspeksi_json(i) AS j, i."TanggalInspeksi" AS t, i."Id" AS id
                FROM "alatInspeksiTbl" i WHERE i."AlatId" = a."Id"
                ORDER BY i."TanggalInspeksi" DESC, i."Id" DESC LIMIT 100) x), '[]'::JSONB))
    FROM "alatTbl" a WHERE a."Id" = p_id;
$$;

CREATE OR REPLACE FUNCTION public.get_alat_inspeksi_list(p_project_id BIGINT DEFAULT NULL, p_tahun INT DEFAULT NULL,
                                                         p_status TEXT DEFAULT NULL, p_hasil TEXT DEFAULT NULL)
RETURNS JSONB LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
    SELECT COALESCE(jsonb_agg(public.alat_inspeksi_json(i)
        ORDER BY (i."Status" <> 'Disetujui') DESC, i."TanggalInspeksi" DESC, i."Id" DESC), '[]'::JSONB)
    FROM "alatInspeksiTbl" i
    WHERE (p_project_id IS NULL OR i."ProjectId" = p_project_id)
      AND (p_tahun IS NULL OR EXTRACT(YEAR FROM (i."TanggalInspeksi" AT TIME ZONE 'Asia/Jakarta')) = p_tahun)
      AND (COALESCE(p_status, '') = '' OR i."Status" = p_status)
      AND (COALESCE(p_hasil, '') = '' OR i."Hasil" = p_hasil);
$$;

CREATE OR REPLACE FUNCTION public.get_alat_inspeksi_detail(p_id BIGINT)
RETURNS JSONB LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
    SELECT public.alat_inspeksi_json(i) || jsonb_build_object(
        'checklistList', i."ChecklistList", 'fotoList', i."FotoList",
        'statusAlat', a."StatusAlat", 'kondisiAlat', a."Kondisi",
        'sertifikatList', COALESCE((SELECT jsonb_agg(public.alat_sertifikat_json(s) ORDER BY s."JenisSertifikat")
                                    FROM public.alat_sertifikat_terkini(a."Id") s), '[]'::JSONB))
    FROM "alatInspeksiTbl" i JOIN "alatTbl" a ON a."Id" = i."AlatId"
    WHERE i."Id" = p_id;
$$;

-- Pengingat sertifikat: sertifikat terkini yang sudah / akan habis dalam p_hari hari,
-- plus alat aktif yang wajib sertifikat tapi belum punya sama sekali (jenisSertifikat null).
CREATE OR REPLACE FUNCTION public.get_alat_sertifikat_list(p_project_id BIGINT DEFAULT NULL, p_hari INT DEFAULT 60)
RETURNS JSONB LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
    WITH rows AS (
        SELECT public.alat_sertifikat_json(s) || jsonb_build_object(
                   'noAlat', a."NoAlat", 'namaAlat', a."NamaAlat", 'kategori', a."Kategori",
                   'projectId', a."ProjectId", 'namaProject', p."NamaProject", 'kodeOperational', p."KodeOperational") AS j,
               s."BerlakuSampai" AS urut
        FROM "alatTbl" a
        JOIN "projectTbl" p ON p."Id" = a."ProjectId"
        CROSS JOIN LATERAL public.alat_sertifikat_terkini(a."Id") s
        WHERE a."StatusAlat" = 'Aktif' AND (p_project_id IS NULL OR a."ProjectId" = p_project_id)
          AND s."BerlakuSampai" IS NOT NULL
          AND (p_hari IS NULL OR s."BerlakuSampai" <= (now() AT TIME ZONE 'Asia/Jakarta')::DATE + p_hari)
        UNION ALL
        SELECT jsonb_build_object('id', NULL, 'alatId', a."Id", 'jenisSertifikat', NULL, 'statusBerlaku', 'Belum Ada',
                   'noAlat', a."NoAlat", 'namaAlat', a."NamaAlat", 'kategori', a."Kategori",
                   'projectId', a."ProjectId", 'namaProject', p."NamaProject", 'kodeOperational', p."KodeOperational"),
               DATE '1900-01-01'
        FROM "alatTbl" a JOIN "projectTbl" p ON p."Id" = a."ProjectId"
        WHERE a."StatusAlat" = 'Aktif' AND a."WajibSertifikat" AND (p_project_id IS NULL OR a."ProjectId" = p_project_id)
          AND NOT EXISTS (SELECT 1 FROM "alatSertifikatTbl" s WHERE s."AlatId" = a."Id")
    )
    SELECT COALESCE(jsonb_agg(j ORDER BY urut, j->>'noAlat'), '[]'::JSONB) FROM rows;
$$;

CREATE OR REPLACE FUNCTION public.get_alat_checklist_template(p_kategori TEXT)
RETURNS JSONB LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
    SELECT COALESCE(jsonb_agg(jsonb_build_object('item', t."Item", 'kategori', t."Kategori")
                    ORDER BY (t."Kategori" = 'Umum') DESC, t."Urutan", t."Id"), '[]'::JSONB)
    FROM "alatChecklistTemplateTbl" t
    WHERE t."Status" = 'Aktif' AND (t."Kategori" = 'Umum' OR t."Kategori" = p_kategori);
$$;

-- -------------------------------------------------------------------------------------
-- 4. Tulis: register alat & sertifikat (cek PIC ke SmartGate dulu)
-- -------------------------------------------------------------------------------------
-- p_data: {projectId, kategori, namaAlat, noAset, merkTipe, noSeri, kapasitas, pemilik, namaPemilik,
--          lokasiArea, intervalInspeksiHari, wajibSertifikat, statusAlat, keterangan}
CREATE OR REPLACE FUNCTION public.save_alat(p_aktor_nama TEXT, p_aktor_qr TEXT, p_id BIGINT, p_data JSONB)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
    v_id       BIGINT := p_id;
    v_project  BIGINT := NULLIF(p_data->>'projectId', '')::BIGINT;
    v_kategori TEXT := NULLIF(trim(p_data->>'kategori'), '');
    v_interval INT := COALESCE(NULLIF(p_data->>'intervalInspeksiHari', '')::INT, 30);
    v_kode     TEXT;
    v_seq      INT;
    v_nama     TEXT := COALESCE(NULLIF(trim(p_aktor_nama), ''), upper(trim(p_aktor_qr)));
BEGIN
    PERFORM public.hsse_wajib_akses(p_aktor_nama, p_aktor_qr, 'HSSE-ALT');
    IF v_project IS NULL OR NOT EXISTS (SELECT 1 FROM "projectTbl" WHERE "Id" = v_project) THEN
        RAISE EXCEPTION 'Pilih project dulu.';
    END IF;
    IF v_kategori IS NULL THEN
        RAISE EXCEPTION 'Pilih kategori alat.';
    END IF;
    IF COALESCE(trim(p_data->>'namaAlat'), '') = '' THEN
        RAISE EXCEPTION 'Nama alat wajib diisi.';
    END IF;
    IF v_interval < 1 OR v_interval > 730 THEN
        RAISE EXCEPTION 'Interval inspeksi harus 1 sampai 730 hari.';
    END IF;

    IF v_id IS NULL THEN
        SELECT COALESCE(NULLIF("KodeOperational", ''), 'P' || "Id") INTO v_kode FROM "projectTbl" WHERE "Id" = v_project;
        PERFORM pg_advisory_xact_lock(hashtext('alat_no_' || v_kode));
        SELECT COALESCE(max(substring("NoAlat" FROM '(\d+)$')::INT), 0) + 1 INTO v_seq
        FROM "alatTbl" WHERE "NoAlat" LIKE 'ALT/' || v_kode || '/%';

        INSERT INTO "alatTbl" ("NoAlat", "NoAset", "ProjectId", "Kategori", "NamaAlat", "MerkTipe", "NoSeri", "Kapasitas",
                               "Pemilik", "NamaPemilik", "LokasiArea", "IntervalInspeksiHari", "WajibSertifikat",
                               "StatusAlat", "Keterangan", "DibuatOleh", "DibuatQrCodeId", "DiubahOleh")
        VALUES ('ALT/' || v_kode || '/' || lpad(v_seq::TEXT, 4, '0'), NULLIF(trim(p_data->>'noAset'), ''),
                v_project, v_kategori, trim(p_data->>'namaAlat'), NULLIF(trim(p_data->>'merkTipe'), ''),
                NULLIF(trim(p_data->>'noSeri'), ''), NULLIF(trim(p_data->>'kapasitas'), ''),
                COALESCE(NULLIF(p_data->>'pemilik', ''), 'BIMA'), NULLIF(trim(p_data->>'namaPemilik'), ''),
                NULLIF(trim(p_data->>'lokasiArea'), ''), v_interval,
                COALESCE((p_data->>'wajibSertifikat')::BOOLEAN, TRUE),
                COALESCE(NULLIF(p_data->>'statusAlat', ''), 'Aktif'), NULLIF(trim(p_data->>'keterangan'), ''),
                v_nama, upper(trim(p_aktor_qr)), v_nama)
        RETURNING "Id" INTO v_id;
    ELSE
        IF NOT EXISTS (SELECT 1 FROM "alatTbl" WHERE "Id" = v_id) THEN
            RAISE EXCEPTION 'Alat % tidak ditemukan.', v_id;
        END IF;
        UPDATE "alatTbl" SET
            "NoAset" = NULLIF(trim(p_data->>'noAset'), ''), "ProjectId" = v_project, "Kategori" = v_kategori,
            "NamaAlat" = trim(p_data->>'namaAlat'), "MerkTipe" = NULLIF(trim(p_data->>'merkTipe'), ''),
            "NoSeri" = NULLIF(trim(p_data->>'noSeri'), ''), "Kapasitas" = NULLIF(trim(p_data->>'kapasitas'), ''),
            "Pemilik" = COALESCE(NULLIF(p_data->>'pemilik', ''), 'BIMA'),
            "NamaPemilik" = NULLIF(trim(p_data->>'namaPemilik'), ''), "LokasiArea" = NULLIF(trim(p_data->>'lokasiArea'), ''),
            "IntervalInspeksiHari" = v_interval,
            "WajibSertifikat" = COALESCE((p_data->>'wajibSertifikat')::BOOLEAN, TRUE),
            "StatusAlat" = COALESCE(NULLIF(p_data->>'statusAlat', ''), 'Aktif'),
            "Keterangan" = NULLIF(trim(p_data->>'keterangan'), ''),
            "DiubahOleh" = v_nama, "UpdatedAt" = now()
        WHERE "Id" = v_id;
    END IF;
    RETURN public.get_alat_detail(v_id);
END;
$$;

-- Hapus cuma boleh kalau alat belum pernah diinspeksi (salah input). Alat yang sudah punya
-- riwayat inspeksi di-set "Tidak Dipakai" saja supaya buktinya tetap ada.
CREATE OR REPLACE FUNCTION public.delete_alat(p_aktor_nama TEXT, p_aktor_qr TEXT, p_id BIGINT)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
    PERFORM public.hsse_wajib_akses(p_aktor_nama, p_aktor_qr, 'HSSE-ALT');
    IF EXISTS (SELECT 1 FROM "alatInspeksiTbl" WHERE "AlatId" = p_id) THEN
        RAISE EXCEPTION 'Alat ini sudah punya riwayat inspeksi, tidak bisa dihapus. Ubah status jadi "Tidak Dipakai".';
    END IF;
    DELETE FROM "alatTbl" WHERE "Id" = p_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Alat % tidak ditemukan.', p_id;
    END IF;
END;
$$;

-- p_data: {jenisSertifikat, noSertifikat, penerbit, tanggalTerbit, berlakuSampai, linkDokumen, catatan}
-- p_id NULL = sertifikat baru (perpanjangan = catat sertifikat baru; yang lama tetap jadi riwayat).
CREATE OR REPLACE FUNCTION public.save_alat_sertifikat(p_aktor_nama TEXT, p_aktor_qr TEXT, p_alat_id BIGINT,
                                                       p_id BIGINT, p_data JSONB)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
    v_jenis   TEXT := NULLIF(trim(p_data->>'jenisSertifikat'), '');
    v_terbit  DATE := NULLIF(p_data->>'tanggalTerbit', '')::DATE;
    v_sampai  DATE := NULLIF(p_data->>'berlakuSampai', '')::DATE;
    v_link    TEXT := NULLIF(trim(p_data->>'linkDokumen'), '');
    v_nama    TEXT := COALESCE(NULLIF(trim(p_aktor_nama), ''), upper(trim(p_aktor_qr)));
BEGIN
    PERFORM public.hsse_wajib_akses(p_aktor_nama, p_aktor_qr, 'HSSE-ALT');
    IF NOT EXISTS (SELECT 1 FROM "alatTbl" WHERE "Id" = p_alat_id) THEN
        RAISE EXCEPTION 'Alat % tidak ditemukan.', p_alat_id;
    END IF;
    IF v_jenis IS NULL THEN
        RAISE EXCEPTION 'Pilih jenis sertifikat.';
    END IF;
    IF COALESCE(trim(p_data->>'noSertifikat'), '') = '' THEN
        RAISE EXCEPTION 'No. sertifikat wajib diisi.';
    END IF;
    IF v_sampai IS NOT NULL AND v_terbit IS NOT NULL AND v_sampai < v_terbit THEN
        RAISE EXCEPTION 'Tanggal berlaku sampai tidak boleh sebelum tanggal terbit.';
    END IF;
    IF v_link IS NOT NULL AND v_link !~* '^https?://' THEN
        RAISE EXCEPTION 'Link dokumen harus diawali http:// atau https://';
    END IF;

    IF p_id IS NULL THEN
        INSERT INTO "alatSertifikatTbl" ("AlatId", "JenisSertifikat", "NoSertifikat", "Penerbit", "TanggalTerbit",
                                         "BerlakuSampai", "LinkDokumen", "Catatan", "DicatatOleh", "DicatatQrCodeId", "DiubahOleh")
        VALUES (p_alat_id, v_jenis, trim(p_data->>'noSertifikat'), NULLIF(trim(p_data->>'penerbit'), ''), v_terbit,
                v_sampai, v_link, NULLIF(trim(p_data->>'catatan'), ''), v_nama, upper(trim(p_aktor_qr)), v_nama);
    ELSE
        UPDATE "alatSertifikatTbl" SET "JenisSertifikat" = v_jenis, "NoSertifikat" = trim(p_data->>'noSertifikat'),
            "Penerbit" = NULLIF(trim(p_data->>'penerbit'), ''), "TanggalTerbit" = v_terbit, "BerlakuSampai" = v_sampai,
            "LinkDokumen" = v_link, "Catatan" = NULLIF(trim(p_data->>'catatan'), ''),
            "DiubahOleh" = v_nama, "UpdatedAt" = now()
        WHERE "Id" = p_id AND "AlatId" = p_alat_id;
        IF NOT FOUND THEN
            RAISE EXCEPTION 'Sertifikat % tidak ditemukan di alat ini.', p_id;
        END IF;
    END IF;
    UPDATE "alatTbl" SET "DiubahOleh" = v_nama, "UpdatedAt" = now() WHERE "Id" = p_alat_id;
    RETURN public.get_alat_detail(p_alat_id);
END;
$$;

CREATE OR REPLACE FUNCTION public.delete_alat_sertifikat(p_aktor_nama TEXT, p_aktor_qr TEXT, p_id BIGINT)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
    v_alat BIGINT;
BEGIN
    PERFORM public.hsse_wajib_akses(p_aktor_nama, p_aktor_qr, 'HSSE-ALT');
    DELETE FROM "alatSertifikatTbl" WHERE "Id" = p_id RETURNING "AlatId" INTO v_alat;
    IF v_alat IS NULL THEN
        RAISE EXCEPTION 'Sertifikat % tidak ditemukan.', p_id;
    END IF;
    RETURN public.get_alat_detail(v_alat);
END;
$$;

-- -------------------------------------------------------------------------------------
-- 5. Tulis: inspeksi alat
-- -------------------------------------------------------------------------------------
-- p_data: {alatId, tanggalInspeksi, jenisInspeksi, warnaTag, lokasiArea,
--          checklistList:[{item, hasil: Baik/Tidak Baik/N/A, catatan}], hasil, temuanTindakan}
-- p_foto: [{url, fileId}] atau NULL = foto lama dipertahankan
-- Simpan = ajukan approval. Inspeksi Dikembalikan / Menunggu Approval masih bisa diubah.
CREATE OR REPLACE FUNCTION public.save_alat_inspeksi(p_aktor_nama TEXT, p_aktor_qr TEXT, p_id BIGINT,
                                                     p_data JSONB, p_foto JSONB DEFAULT NULL)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
    v_id       BIGINT := p_id;
    v_alat     "alatTbl";
    v_lama     "alatInspeksiTbl";
    v_tgl      TIMESTAMPTZ := COALESCE(NULLIF(p_data->>'tanggalInspeksi', '')::TIMESTAMPTZ, now());
    v_jenis    TEXT := NULLIF(trim(p_data->>'jenisInspeksi'), '');
    v_hasil    TEXT := NULLIF(trim(p_data->>'hasil'), '');
    v_list     JSONB := CASE WHEN jsonb_typeof(p_data->'checklistList') = 'array' THEN p_data->'checklistList' ELSE '[]'::JSONB END;
    v_baik     INT;
    v_tidak    INT;
    v_kosong   INT;
    v_kode     TEXT;
    v_tahun    TEXT;
    v_seq      INT;
    v_nama     TEXT := COALESCE(NULLIF(trim(p_aktor_nama), ''), upper(trim(p_aktor_qr)));
BEGIN
    PERFORM public.hsse_wajib_akses(p_aktor_nama, p_aktor_qr, 'HSSE-ALT');
    SELECT * INTO v_alat FROM "alatTbl" WHERE "Id" = NULLIF(p_data->>'alatId', '')::BIGINT;
    IF v_alat."Id" IS NULL THEN
        RAISE EXCEPTION 'Pilih alat yang diinspeksi.';
    END IF;
    IF v_jenis IS NULL THEN
        RAISE EXCEPTION 'Pilih jenis inspeksi.';
    END IF;
    IF v_hasil IS NULL THEN
        RAISE EXCEPTION 'Pilih hasil inspeksi (Layak / Layak dengan Catatan / Tidak Layak).';
    END IF;
    IF v_tgl > now() + INTERVAL '5 minutes' THEN
        RAISE EXCEPTION 'Tanggal inspeksi tidak boleh di masa depan.';
    END IF;

    v_list := COALESCE((SELECT jsonb_agg(jsonb_build_object('item', trim(e->>'item'), 'hasil', COALESCE(e->>'hasil', ''),
                                                            'catatan', COALESCE(trim(e->>'catatan'), '')))
                        FROM jsonb_array_elements(v_list) e WHERE COALESCE(trim(e->>'item'), '') <> ''), '[]'::JSONB);
    SELECT count(*) FILTER (WHERE e->>'hasil' = 'Baik'),
           count(*) FILTER (WHERE e->>'hasil' = 'Tidak Baik'),
           count(*) FILTER (WHERE e->>'hasil' NOT IN ('Baik', 'Tidak Baik', 'N/A'))
    INTO v_baik, v_tidak, v_kosong
    FROM jsonb_array_elements(v_list) e;
    IF jsonb_array_length(v_list) = 0 THEN
        RAISE EXCEPTION 'Checklist inspeksi masih kosong.';
    END IF;
    IF v_kosong > 0 THEN
        RAISE EXCEPTION 'Masih ada % item checklist yang belum dinilai (Baik / Tidak Baik / N/A).', v_kosong;
    END IF;
    IF v_tidak > 0 AND v_hasil = 'Layak' THEN
        RAISE EXCEPTION 'Ada % item Tidak Baik, jadi hasil tidak bisa "Layak". Pilih "Layak dengan Catatan" atau "Tidak Layak".', v_tidak;
    END IF;
    IF v_hasil <> 'Layak' AND COALESCE(trim(p_data->>'temuanTindakan'), '') = '' THEN
        RAISE EXCEPTION 'Hasil "%": tulis temuan dan tindakan perbaikannya.', v_hasil;
    END IF;

    IF v_id IS NULL THEN
        IF v_alat."StatusAlat" <> 'Aktif' THEN
            RAISE EXCEPTION 'Alat % berstatus Tidak Dipakai. Aktifkan lagi di data alat kalau mau diinspeksi.', v_alat."NoAlat";
        END IF;
        SELECT COALESCE(NULLIF("KodeOperational", ''), 'P' || "Id") INTO v_kode FROM "projectTbl" WHERE "Id" = v_alat."ProjectId";
        v_tahun := to_char(v_tgl AT TIME ZONE 'Asia/Jakarta', 'YYYY');
        PERFORM pg_advisory_xact_lock(hashtext('alat_insp_no_' || v_kode || v_tahun));
        SELECT COALESCE(max(substring("NoInspeksi" FROM '(\d+)$')::INT), 0) + 1 INTO v_seq
        FROM "alatInspeksiTbl" WHERE "NoInspeksi" LIKE 'INA/' || v_kode || '/' || v_tahun || '/%';

        INSERT INTO "alatInspeksiTbl" ("NoInspeksi", "AlatId", "ProjectId", "TanggalInspeksi", "JenisInspeksi", "WarnaTag",
                                       "LokasiArea", "ChecklistList", "JumlahBaik", "JumlahTidakBaik", "Hasil",
                                       "TemuanTindakan", "FotoList", "Inspektor", "InspektorQrCodeId", "DiubahOleh")
        VALUES ('INA/' || v_kode || '/' || v_tahun || '/' || lpad(v_seq::TEXT, 3, '0'), v_alat."Id", v_alat."ProjectId",
                v_tgl, v_jenis, NULLIF(trim(p_data->>'warnaTag'), ''),
                COALESCE(NULLIF(trim(p_data->>'lokasiArea'), ''), v_alat."LokasiArea"),
                v_list, v_baik, v_tidak, v_hasil, NULLIF(trim(p_data->>'temuanTindakan'), ''),
                COALESCE(p_foto, '[]'::JSONB), v_nama, upper(trim(p_aktor_qr)), v_nama)
        RETURNING "Id" INTO v_id;
    ELSE
        SELECT * INTO v_lama FROM "alatInspeksiTbl" WHERE "Id" = v_id FOR UPDATE;
        IF v_lama."Id" IS NULL THEN
            RAISE EXCEPTION 'Inspeksi % tidak ditemukan.', v_id;
        END IF;
        IF v_lama."Status" = 'Disetujui' THEN
            RAISE EXCEPTION 'Inspeksi yang sudah Disetujui tidak bisa diubah. Buat inspeksi baru kalau ada perubahan.';
        END IF;
        IF v_lama."AlatId" <> v_alat."Id" THEN
            RAISE EXCEPTION 'Alat pada inspeksi yang sudah tersimpan tidak bisa diganti. Hapus lalu buat inspeksi baru.';
        END IF;
        UPDATE "alatInspeksiTbl" SET "Status" = 'Menunggu Approval',
            "TanggalInspeksi" = v_tgl, "JenisInspeksi" = v_jenis, "WarnaTag" = NULLIF(trim(p_data->>'warnaTag'), ''),
            "LokasiArea" = COALESCE(NULLIF(trim(p_data->>'lokasiArea'), ''), v_alat."LokasiArea"),
            "ChecklistList" = v_list, "JumlahBaik" = v_baik, "JumlahTidakBaik" = v_tidak, "Hasil" = v_hasil,
            "TemuanTindakan" = NULLIF(trim(p_data->>'temuanTindakan'), ''),
            "FotoList" = COALESCE(p_foto, "FotoList"),
            "DiubahOleh" = v_nama, "UpdatedAt" = now()
        WHERE "Id" = v_id;
    END IF;
    PERFORM public.alat_refresh_kondisi(v_alat."Id");
    RETURN public.get_alat_inspeksi_detail(v_id);
END;
$$;

CREATE OR REPLACE FUNCTION public.delete_alat_inspeksi(p_aktor_nama TEXT, p_aktor_qr TEXT, p_id BIGINT)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
    v_alat BIGINT;
BEGIN
    PERFORM public.hsse_wajib_akses(p_aktor_nama, p_aktor_qr, 'HSSE-ALT');
    DELETE FROM "alatInspeksiTbl" WHERE "Id" = p_id AND "Status" <> 'Disetujui' RETURNING "AlatId" INTO v_alat;
    IF v_alat IS NULL THEN
        RAISE EXCEPTION 'Inspeksi % tidak ditemukan atau sudah Disetujui (tidak bisa dihapus).', p_id;
    END IF;
    PERFORM public.alat_refresh_kondisi(v_alat);
END;
$$;

-- p_setuju TRUE = Disetujui, FALSE = Dikembalikan (catatan wajib)
CREATE OR REPLACE FUNCTION public.approve_alat_inspeksi(p_aktor_nama TEXT, p_aktor_qr TEXT, p_id BIGINT,
                                                        p_setuju BOOLEAN, p_catatan TEXT DEFAULT NULL)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
    v_status TEXT;
    v_alat   BIGINT;
    v_nama   TEXT := COALESCE(NULLIF(trim(p_aktor_nama), ''), upper(trim(p_aktor_qr)));
BEGIN
    PERFORM public.hsse_wajib_akses(p_aktor_nama, p_aktor_qr, 'Approve Inspeksi Alat');
    SELECT "Status", "AlatId" INTO v_status, v_alat FROM "alatInspeksiTbl" WHERE "Id" = p_id FOR UPDATE;
    IF v_status IS DISTINCT FROM 'Menunggu Approval' THEN
        RAISE EXCEPTION 'Inspeksi ini tidak sedang menunggu approval (status: %).', COALESCE(v_status, '-');
    END IF;
    IF p_setuju THEN
        UPDATE "alatInspeksiTbl" SET "Status" = 'Disetujui', "DisetujuiOleh" = v_nama,
            "DisetujuiQrCodeId" = upper(trim(p_aktor_qr)), "TanggalDisetujui" = now(),
            "CatatanApproval" = NULLIF(trim(p_catatan), ''), "DiubahOleh" = v_nama, "UpdatedAt" = now()
        WHERE "Id" = p_id;
    ELSE
        IF COALESCE(trim(p_catatan), '') = '' THEN
            RAISE EXCEPTION 'Tulis alasan kenapa dikembalikan.';
        END IF;
        UPDATE "alatInspeksiTbl" SET "Status" = 'Dikembalikan', "CatatanApproval" = trim(p_catatan),
            "DiubahOleh" = v_nama, "UpdatedAt" = now()
        WHERE "Id" = p_id;
    END IF;
    PERFORM public.alat_refresh_kondisi(v_alat);
    RETURN public.get_alat_inspeksi_detail(p_id);
END;
$$;

-- -------------------------------------------------------------------------------------
-- 6. HSE Program: Tools & Equipment Compliance jadi OTOMATIS
-- -------------------------------------------------------------------------------------
UPDATE "hseProgramMasterItemTbl" SET "SumberRealisasi" = 'OTOMATIS',
    "Keterangan" = 'Realisasi dari modul Inspeksi Alat -- inspeksi alat Disetujui, bulan = tanggal inspeksi'
WHERE "KodeItem" = 'TOOLS_EQUIPMENT_COMPLIANCE';

-- Salinan get_hse_program dari 069; realisasi drill/ERP/alat lewat hse_program_realisasi_modul.
CREATE OR REPLACE FUNCTION public.get_hse_program(p_project_id BIGINT, p_tahun INT)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_result JSONB;
BEGIN
    WITH realisasi AS (
        SELECT 'TBM' AS kode, EXTRACT(MONTH FROM "TanggalMulai")::INT AS bulan, COUNT(*) AS jumlah
        FROM "tbmTbl" WHERE "ProjectId" = p_project_id
          AND EXTRACT(YEAR FROM "TanggalMulai") = p_tahun GROUP BY 2
        UNION ALL
        SELECT CASE WHEN "TipeMeeting" = 'Mingguan' THEN 'HSE_MEETING_MINGGUAN' ELSE 'HSE_MEETING_BULANAN' END,
               EXTRACT(MONTH FROM "TanggalRapat")::INT, COUNT(*)
        FROM "hseMeetingTbl" WHERE "ProjectId" = p_project_id
          AND EXTRACT(YEAR FROM "TanggalRapat") = p_tahun GROUP BY 1, 2
        UNION ALL
        SELECT 'INSPEKSI_OBSERVASI', EXTRACT(MONTH FROM "TanggalWaktu")::INT, COUNT(*)
        FROM "inspeksiTbl" WHERE "ProjectId" = p_project_id
          AND EXTRACT(YEAR FROM "TanggalWaktu") = p_tahun GROUP BY 2
        UNION ALL
        SELECT 'CERMAT', EXTRACT(MONTH FROM "TanggalWaktu")::INT, COUNT(*)
        FROM "cermatTbl" WHERE "ProjectId" = p_project_id
          AND EXTRACT(YEAR FROM "TanggalWaktu") = p_tahun GROUP BY 2
        UNION ALL
        SELECT 'INTERNAL_AUDIT', EXTRACT(MONTH FROM COALESCE("TanggalSelesaiAudit", "TanggalDitutup"))::INT, COUNT(*)
        FROM "auditTbl" WHERE "ProjectId" = p_project_id
          AND "Status" IN ('Selesai Audit', 'Ditutup')
          AND EXTRACT(YEAR FROM COALESCE("TanggalSelesaiAudit", "TanggalDitutup")) = p_tahun GROUP BY 2
        UNION ALL
        SELECT 'PTW', EXTRACT(MONTH FROM COALESCE("TanggalAreaAuthority", "TanggalWaktu"))::INT, COUNT(*)
        FROM "ptwTbl" WHERE "ProjectId" = p_project_id
          AND "Status" IN ('Aktif', 'Menunggu Approval Penutupan', 'Ditutup')
          AND EXTRACT(YEAR FROM COALESCE("TanggalAreaAuthority", "TanggalWaktu")) = p_tahun GROUP BY 2
        UNION ALL
        SELECT 'INCIDENT', EXTRACT(MONTH FROM "TanggalWaktu")::INT, COUNT(*)
        FROM "incidentTbl" WHERE "ProjectId" = p_project_id
          AND EXTRACT(YEAR FROM "TanggalWaktu") = p_tahun GROUP BY 2
        UNION ALL
        SELECT 'MWT', EXTRACT(MONTH FROM mv.tgl_kunjungan_pertama)::INT, COUNT(*)
        FROM "mwtTbl" m
        CROSS JOIN LATERAL (
            SELECT MIN((elem->>'tanggalKunjungan')::timestamptz) AS tgl_kunjungan_pertama
            FROM jsonb_array_elements(m."KunjunganList") elem
        ) mv
        WHERE m."ProjectId" = p_project_id AND mv.tgl_kunjungan_pertama IS NOT NULL
          AND EXTRACT(YEAR FROM mv.tgl_kunjungan_pertama) = p_tahun GROUP BY 2
        UNION ALL
        SELECT 'MANAGEMENT_REVIEW' AS kode,
               EXTRACT(MONTH FROM "TanggalReview")::INT AS bulan, COUNT(*) AS jumlah
        FROM "managementReviewTbl"
        WHERE "ProjectId" = p_project_id AND "Status" = 'Completed'
          AND EXTRACT(YEAR FROM "TanggalReview") = p_tahun
        GROUP BY 2
        UNION ALL
        SELECT rm.kode, rm.bulan, rm.jumlah FROM public.hse_program_realisasi_modul(p_project_id, p_tahun) rm
    ), realisasi_agg AS (
        SELECT kode, jsonb_object_agg(bulan::text, jumlah) AS bulanan, SUM(jumlah) AS total
        FROM realisasi GROUP BY kode
    )
    SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'itemId', mi."Id", 'kodeItem', mi."KodeItem", 'namaItem', mi."NamaItem",
        'kategori', mi."Kategori", 'sumberRealisasi', mi."SumberRealisasi",
        'satuanTarget', mi."SatuanTarget", 'urutan', mi."Urutan",
        'statusPakai', COALESCE(hp."StatusPakai", 'N/A'),
        'targetQty', hp."TargetQty", 'frequency', hp."Frequency",
        'targetBulanan', COALESCE(hp."TargetBulanan",
          '{"1":0,"2":0,"3":0,"4":0,"5":0,"6":0,"7":0,"8":0,"9":0,"10":0,"11":0,"12":0}'::jsonb),
        'targetTotal', COALESCE((SELECT SUM(v.value::text::int)
          FROM jsonb_each(COALESCE(hp."TargetBulanan", '{}'::jsonb)) v), 0),
        'realisasiBulanan', CASE WHEN mi."SumberRealisasi" = 'MANUAL'
          THEN COALESCE(hp."RealisasiManualBulanan", '{}'::jsonb)
          ELSE COALESCE(ra.bulanan, '{}'::jsonb) END,
        'realisasiTotal', CASE WHEN mi."SumberRealisasi" = 'MANUAL'
          THEN COALESCE((SELECT SUM(v.value::text::int)
            FROM jsonb_each(COALESCE(hp."RealisasiManualBulanan", '{}'::jsonb)) v), 0)
          ELSE COALESCE(ra.total, 0) END
    ) ORDER BY mi."Urutan"), '[]'::jsonb)
    INTO v_result
    FROM "hseProgramMasterItemTbl" mi
    LEFT JOIN "hseProgramTbl" hp
      ON hp."ItemId" = mi."Id" AND hp."ProjectId" = p_project_id AND hp."Tahun" = p_tahun
    LEFT JOIN realisasi_agg ra ON ra.kode = mi."KodeItem";
    RETURN v_result;
END;
$$;

-- Salinan get_management_review_frame dari 069; 3 baris WHEN drill/ERP diganti satu ELSE
-- yang mengambil dari hse_program_realisasi_modul (drill, ERP, alat, dan modul berikutnya).
CREATE OR REPLACE FUNCTION public.get_management_review_frame(p_project_id BIGINT, p_tahun INT DEFAULT NULL)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_tahun INT := COALESCE(p_tahun, EXTRACT(YEAR FROM NOW())::INT);
    v_result JSONB;
BEGIN
    SELECT jsonb_build_object(
        'tahun', v_tahun,

        'hseProgram', COALESCE((
            SELECT jsonb_agg(jsonb_build_object(
                'itemId', mi."Id",
                'kodeItem', mi."KodeItem",
                'namaItem', mi."NamaItem",
                'targetTotal', COALESCE((
                    SELECT SUM(v.value::text::int) FROM jsonb_each(COALESCE(hp."TargetBulanan", '{}'::jsonb)) v
                ), 0),
                'realisasiTotal', CASE mi."KodeItem"
                    WHEN 'TBM' THEN (SELECT COUNT(*) FROM "tbmTbl" WHERE "ProjectId" = p_project_id AND EXTRACT(YEAR FROM "TanggalMulai") = v_tahun)
                    WHEN 'HSE_MEETING_MINGGUAN' THEN (SELECT COUNT(*) FROM "hseMeetingTbl" WHERE "ProjectId" = p_project_id AND "TipeMeeting" = 'Mingguan' AND EXTRACT(YEAR FROM "TanggalRapat") = v_tahun)
                    WHEN 'HSE_MEETING_BULANAN' THEN (SELECT COUNT(*) FROM "hseMeetingTbl" WHERE "ProjectId" = p_project_id AND "TipeMeeting" = 'Bulanan' AND EXTRACT(YEAR FROM "TanggalRapat") = v_tahun)
                    WHEN 'INSPEKSI_OBSERVASI' THEN (SELECT COUNT(*) FROM "inspeksiTbl" WHERE "ProjectId" = p_project_id AND EXTRACT(YEAR FROM "TanggalWaktu") = v_tahun)
                    WHEN 'CERMAT' THEN (SELECT COUNT(*) FROM "cermatTbl" WHERE "ProjectId" = p_project_id AND EXTRACT(YEAR FROM "TanggalWaktu") = v_tahun)
                    WHEN 'INTERNAL_AUDIT' THEN (SELECT COUNT(*) FROM "auditTbl" WHERE "ProjectId" = p_project_id AND EXTRACT(YEAR FROM COALESCE("TanggalPelaksanaan", "TanggalRencana"::timestamptz)) = v_tahun)
                    WHEN 'PTW' THEN (SELECT COUNT(*) FROM "ptwTbl" WHERE "ProjectId" = p_project_id AND "Status" IN ('Aktif', 'Menunggu Approval Penutupan', 'Ditutup') AND EXTRACT(YEAR FROM COALESCE("TanggalAreaAuthority", "TanggalWaktu")) = v_tahun)
                    WHEN 'INCIDENT' THEN (SELECT COUNT(*) FROM "incidentTbl" WHERE "ProjectId" = p_project_id AND EXTRACT(YEAR FROM "TanggalWaktu") = v_tahun)
                    WHEN 'MWT' THEN (SELECT COUNT(*) FROM "mwtTbl" WHERE "ProjectId" = p_project_id AND EXTRACT(YEAR FROM "TanggalRencana") = v_tahun)
                    WHEN 'MANAGEMENT_REVIEW' THEN (SELECT COUNT(*) FROM "managementReviewTbl" WHERE "ProjectId" = p_project_id AND "Status" = 'Completed' AND EXTRACT(YEAR FROM "TanggalReview") = v_tahun)
                    ELSE (SELECT COALESCE(SUM(rm.jumlah), 0) FROM public.hse_program_realisasi_modul(p_project_id, v_tahun) rm WHERE rm.kode = mi."KodeItem")
                END
            ) ORDER BY mi."Urutan")
            FROM "hseProgramMasterItemTbl" mi
            JOIN "hseProgramTbl" hp ON hp."ItemId" = mi."Id"
                AND hp."ProjectId" = p_project_id AND hp."Tahun" = v_tahun
            WHERE hp."StatusPakai" = 'Use'
        ), '[]'::jsonb),

        'incidentNearMiss', COALESCE((
            SELECT jsonb_agg(jsonb_build_object(
                'id', i."Id",
                'noLaporan', i."NoLaporan", 'tanggalWaktu', i."TanggalWaktu",
                'namaPelapor', i."NamaPelapor", 'klasifikasi', i."Klasifikasi",
                'lokasiArea', i."LokasiArea", 'kronologi', i."Kronologi",
                'akarMasalah', i."AkarMasalah", 'tindakanKorektif', i."TindakanKorektif",
                'tindakanLangsung', i."TindakanLangsung",
                'penanggungJawab', i."PenanggungJawab", 'tenggat', i."Tenggat",
                'status', i."Status"
            ) ORDER BY i."TanggalWaktu" DESC)
            FROM "incidentTbl" i
            WHERE i."ProjectId" = p_project_id AND i."Status" <> 'Closed'
        ), '[]'::jsonb),

        'cermat', jsonb_build_object(
            'totalOpen', (SELECT COUNT(*) FROM "cermatTbl" WHERE "ProjectId" = p_project_id AND "Status" <> 'Closed'),
            'totalClosed', (SELECT COUNT(*) FROM "cermatTbl" WHERE "ProjectId" = p_project_id AND "Status" = 'Closed'),
            'openList', COALESCE((
                SELECT jsonb_agg(jsonb_build_object(
                    'id', c."Id",
                    'noLaporan', c."NoLaporan", 'tanggalWaktu', c."TanggalWaktu",
                    'namaPelapor', c."NamaPelapor", 'sifat', c."Sifat", 'jenisTemuan', c."JenisTemuan",
                    'lokasiArea', c."LokasiArea", 'deskripsi', c."Deskripsi",
                    'tindakanLangsung', c."TindakanLangsung", 'rekomendasi', c."Rekomendasi",
                    'status', c."Status", 'penanggungJawab', c."PenanggungJawab", 'tenggat', c."Tenggat"
                ) ORDER BY c."TanggalWaktu" DESC)
                FROM "cermatTbl" c WHERE c."ProjectId" = p_project_id AND c."Status" <> 'Closed'
            ), '[]'::jsonb)
        ),

        'inspeksi', jsonb_build_object(
            'totalOpen', (
                SELECT COUNT(*) FROM "inspeksiTbl"
                WHERE "ProjectId" = p_project_id AND "JumlahTidakSesuai" > 0 AND "CermatId" IS NULL
            ),
            'totalClosed', (
                SELECT COUNT(*) FROM "inspeksiTbl"
                WHERE "ProjectId" = p_project_id AND ("JumlahTidakSesuai" = 0 OR "CermatId" IS NOT NULL)
            ),
            'openList', COALESCE((
                SELECT jsonb_agg(jsonb_build_object(
                    'id', ii."Id",
                    'noLaporan', ii."NoLaporan", 'jenis', ii."Jenis", 'tanggalWaktu', ii."TanggalWaktu",
                    'namaInspektor', ii."NamaInspektor", 'lokasiArea', ii."LokasiArea",
                    'catatanUmum', ii."CatatanUmum", 'jumlahSesuai', ii."JumlahSesuai",
                    'jumlahTidakSesuai', ii."JumlahTidakSesuai", 'jumlahNA', ii."JumlahNA",
                    'skorPersen', ii."SkorPersen"
                ) ORDER BY ii."TanggalWaktu" DESC)
                FROM "inspeksiTbl" ii
                WHERE ii."ProjectId" = p_project_id AND ii."JumlahTidakSesuai" > 0 AND ii."CermatId" IS NULL
            ), '[]'::jsonb)
        ),

        'partisipasiPekerja', jsonb_build_object(
            'totalSesi', (SELECT COUNT(*) FROM "mwtTbl" WHERE "ProjectId" = p_project_id),
            'totalKunjungan', COALESCE((
                SELECT SUM(jsonb_array_length(COALESCE("KunjunganList", '[]'::jsonb)))
                FROM "mwtTbl" WHERE "ProjectId" = p_project_id
            ), 0),
            'totalPekerjaDiskusi', COALESCE((
                SELECT SUM((k->>'jumlahPekerjaDiskusi')::int)
                FROM "mwtTbl" m, jsonb_array_elements(COALESCE(m."KunjunganList", '[]'::jsonb)) k
                WHERE m."ProjectId" = p_project_id
            ), 0),
            'sesiList', COALESCE((
                SELECT jsonb_agg(jsonb_build_object(
                    'id', m."Id",
                    'noMWT', m."NoMWT", 'areaRencana', m."AreaRencana", 'tanggalRencana', m."TanggalRencana",
                    'status', m."Status", 'kunjunganList', COALESCE(m."KunjunganList", '[]'::jsonb)
                ) ORDER BY m."TanggalRencana" DESC)
                FROM "mwtTbl" m WHERE m."ProjectId" = p_project_id
            ), '[]'::jsonb)
        )
    ) INTO v_result;

    RETURN v_result;
END;
$$;

-- -------------------------------------------------------------------------------------
-- 7. Hak eksekusi: helper internal tertutup, RPC halaman terbuka (cek akses ada di dalam)
-- -------------------------------------------------------------------------------------
REVOKE EXECUTE ON FUNCTION public.alat_sertifikat_json("alatSertifikatTbl") FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.alat_sertifikat_terkini(BIGINT) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.alat_header_json("alatTbl") FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.alat_inspeksi_json("alatInspeksiTbl") FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.alat_refresh_kondisi(BIGINT) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.alat_realisasi_bulanan(BIGINT, INT) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.hse_program_realisasi_modul(BIGINT, INT) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.get_alat_list(BIGINT, TEXT, TEXT, TEXT) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.get_alat_detail(BIGINT) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.get_alat_inspeksi_list(BIGINT, INT, TEXT, TEXT) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.get_alat_inspeksi_detail(BIGINT) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.get_alat_sertifikat_list(BIGINT, INT) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.get_alat_checklist_template(TEXT) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.save_alat(TEXT, TEXT, BIGINT, JSONB) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.delete_alat(TEXT, TEXT, BIGINT) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.save_alat_sertifikat(TEXT, TEXT, BIGINT, BIGINT, JSONB) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.delete_alat_sertifikat(TEXT, TEXT, BIGINT) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.save_alat_inspeksi(TEXT, TEXT, BIGINT, JSONB, JSONB) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.delete_alat_inspeksi(TEXT, TEXT, BIGINT) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.approve_alat_inspeksi(TEXT, TEXT, BIGINT, BOOLEAN, TEXT) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.get_hse_program(BIGINT, INT) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.get_management_review_frame(BIGINT, INT) TO anon, authenticated;

NOTIFY pgrst, 'reload schema';

-- =====================================================================================
-- CEK SETELAH JALAN
-- 1) 4 tabel, rls_on = true semua:
-- SELECT relname, relrowsecurity AS rls_on FROM pg_class WHERE relname IN ('alatTbl', 'alatSertifikatTbl', 'alatInspeksiTbl', 'alatChecklistTemplateTbl');
-- 2) 15 RPC halaman:
-- SELECT count(*) FROM pg_proc WHERE pronamespace = 'public'::regnamespace AND proname IN (
--   'get_alat_list', 'get_alat_detail', 'get_alat_inspeksi_list', 'get_alat_inspeksi_detail', 'get_alat_sertifikat_list',
--   'get_alat_checklist_template', 'save_alat', 'delete_alat', 'save_alat_sertifikat', 'delete_alat_sertifikat',
--   'save_alat_inspeksi', 'delete_alat_inspeksi', 'approve_alat_inspeksi', 'get_hse_program', 'get_management_review_frame');
-- 3) Item HSE Program sudah OTOMATIS + checklist terisi (55 baris):
-- SELECT "KodeItem", "SumberRealisasi" FROM "hseProgramMasterItemTbl" WHERE "KodeItem" = 'TOOLS_EQUIPMENT_COMPLIANCE';
-- SELECT count(*) FROM "alatChecklistTemplateTbl";
-- 4) Tulis tanpa QR harus ditolak ("Verifikasi identitas dulu"):
-- SELECT public.save_alat(NULL, NULL, NULL, '{}'::jsonb);
--
-- ROLLBACK (hapus modul, data ikut hilang): jalankan ulang bagian 6 dari 069 (get_hse_program &
-- get_management_review_frame versi drill), kembalikan item ke MANUAL, lalu:
-- UPDATE "hseProgramMasterItemTbl" SET "SumberRealisasi" = 'MANUAL' WHERE "KodeItem" = 'TOOLS_EQUIPMENT_COMPLIANCE';
-- DROP FUNCTION IF EXISTS public.get_alat_list(BIGINT, TEXT, TEXT, TEXT), public.get_alat_detail(BIGINT),
--   public.get_alat_inspeksi_list(BIGINT, INT, TEXT, TEXT), public.get_alat_inspeksi_detail(BIGINT),
--   public.get_alat_sertifikat_list(BIGINT, INT), public.get_alat_checklist_template(TEXT),
--   public.save_alat(TEXT, TEXT, BIGINT, JSONB), public.delete_alat(TEXT, TEXT, BIGINT),
--   public.save_alat_sertifikat(TEXT, TEXT, BIGINT, BIGINT, JSONB), public.delete_alat_sertifikat(TEXT, TEXT, BIGINT),
--   public.save_alat_inspeksi(TEXT, TEXT, BIGINT, JSONB, JSONB), public.delete_alat_inspeksi(TEXT, TEXT, BIGINT),
--   public.approve_alat_inspeksi(TEXT, TEXT, BIGINT, BOOLEAN, TEXT),
--   public.hse_program_realisasi_modul(BIGINT, INT), public.alat_realisasi_bulanan(BIGINT, INT),
--   public.alat_refresh_kondisi(BIGINT), public.alat_inspeksi_json("alatInspeksiTbl"), public.alat_header_json("alatTbl"),
--   public.alat_sertifikat_terkini(BIGINT), public.alat_sertifikat_json("alatSertifikatTbl");
-- DROP TABLE IF EXISTS "alatChecklistTemplateTbl", "alatInspeksiTbl", "alatSertifikatTbl", "alatTbl";
-- =====================================================================================
