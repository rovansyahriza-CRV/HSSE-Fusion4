-- =====================================================================================
-- 071 -- Modul Subkontraktor (CSMS ke bawah)
-- Jalankan di project Supabase HSSE-Fusion4 (BUKAN Fusion4 SmartGate). Run after 070.
--
-- Isi:
--   subkonTbl                  = register perusahaan subkon (data, kontak, status Aktif / Tidak Aktif / Daftar Hitam)
--   subkonPekerjaanTbl         = penugasan subkon per project (lingkup, SPK/PO, periode, tingkat risiko)
--   subkonDokumenTbl           = dokumen legalitas & kompetensi (NIB, CSMS/PQ, ISO 45001/SMK3, HSE Plan,
--                                BPJS/asuransi, sertifikat kompetensi personil, MCU) + masa berlaku
--   subkonEvaluasiTbl          = evaluasi CSMS per tahap: Prakualifikasi -> Pre-Job Activity ->
--                                Work in Progress (berkala) -> Final Evaluation, pakai checklist bernilai 0-3
--   subkonChecklistTemplateTbl = master checklist per tahap (edit lewat Table Editor, sama kayak modul alat)
-- Nilai evaluasi = jumlah nilai / (3 x item yang dinilai) x 100 (N/A tidak dihitung).
-- Nilai minimum lulus ikut tingkat risiko pekerjaan: Tinggi 75, Menengah 65, Rendah 55
--   (default, ubah di fungsi subkon_nilai_minimum kalau standar client beda). Disimpan per evaluasi.
-- Alur evaluasi:
--   (save_subkon_evaluasi) Menunggu Approval -> (approve_subkon_evaluasi) Disetujui | Dikembalikan -> edit -> Menunggu Approval
-- Akses (dicek di server lewat hsse_wajib_akses dari 065):
--   register subkon, pekerjaan, dokumen, evaluasi = PIC HSSE-SUB (atau HSSE-ALL)
--   setujui / kembalikan evaluasi              = Author "Approve Subkon" (tidak ikut HSSE-ALL)
-- HSE Program: item baru SUBKON_EVALUASI (Administrasi & Evaluasi), OTOMATIS = jumlah evaluasi
--   subkon Disetujui per bulan (semua tahap), bulan = tanggal evaluasi (WIB). Realisasi masuk lewat
--   helper hse_program_realisasi_modul (070), jadi get_hse_program & frame Management Review tidak diubah.
-- Tabel tidak bisa dibaca/ditulis langsung pakai anon key; semua lewat RPC.
-- Aman dijalankan ulang.
-- =====================================================================================

-- -------------------------------------------------------------------------------------
-- 1. Tabel
-- -------------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS "subkonTbl" (
    "Id"              BIGSERIAL PRIMARY KEY,
    "KodeSubkon"      TEXT NOT NULL UNIQUE,                  -- SUB-0001 (otomatis)
    "NamaPerusahaan"  TEXT NOT NULL,
    "BidangUsaha"     TEXT,                                  -- cth. Sipil, Mekanikal, Transportasi, Catering
    "Alamat"          TEXT,
    "NoNIB"           TEXT,
    "NamaKontak"      TEXT,
    "JabatanKontak"   TEXT,
    "Telepon"         TEXT,
    "Email"           TEXT,
    "Status"          TEXT NOT NULL DEFAULT 'Aktif' CHECK ("Status" IN ('Aktif', 'Tidak Aktif', 'Daftar Hitam')),
    "Keterangan"      TEXT,
    "DibuatOleh"      TEXT,
    "DibuatQrCodeId"  TEXT,
    "DiubahOleh"      TEXT,
    "CreatedAt"       TIMESTAMPTZ NOT NULL DEFAULT now(),
    "UpdatedAt"       TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX IF NOT EXISTS uq_subkon_nama ON "subkonTbl" (lower(trim("NamaPerusahaan")));

CREATE TABLE IF NOT EXISTS "subkonPekerjaanTbl" (
    "Id"                   BIGSERIAL PRIMARY KEY,
    "NoPekerjaan"          TEXT NOT NULL UNIQUE,             -- SKP/<kode project>/<tahun>/001
    "SubkonId"             BIGINT NOT NULL REFERENCES "subkonTbl"("Id"),
    "ProjectId"            BIGINT NOT NULL REFERENCES "projectTbl"("Id"),
    "LingkupPekerjaan"     TEXT NOT NULL,
    "NoKontrakPO"          TEXT,                             -- SPK / PO / kontrak dengan subkon
    "TanggalMulai"         DATE,
    "TanggalSelesai"       DATE,
    "TingkatRisiko"        TEXT NOT NULL DEFAULT 'Menengah' CHECK ("TingkatRisiko" IN ('Rendah', 'Menengah', 'Tinggi')),
    "JumlahPekerja"        INT CHECK ("JumlahPekerja" IS NULL OR "JumlahPekerja" >= 0),
    "PengawasHSE"          TEXT,                             -- nama HSE / pengawas dari pihak subkon
    "IntervalEvaluasiHari" INT NOT NULL DEFAULT 30 CHECK ("IntervalEvaluasiHari" BETWEEN 7 AND 365),
    "Status"               TEXT NOT NULL DEFAULT 'Rencana' CHECK ("Status" IN ('Rencana', 'Berjalan', 'Selesai', 'Dibatalkan')),
    "Keterangan"           TEXT,
    "DibuatOleh"           TEXT,
    "DibuatQrCodeId"       TEXT,
    "DiubahOleh"           TEXT,
    "CreatedAt"            TIMESTAMPTZ NOT NULL DEFAULT now(),
    "UpdatedAt"            TIMESTAMPTZ NOT NULL DEFAULT now(),
    CHECK ("TanggalSelesai" IS NULL OR "TanggalMulai" IS NULL OR "TanggalSelesai" >= "TanggalMulai")
);
CREATE INDEX IF NOT EXISTS idx_subkon_pekerjaan_project ON "subkonPekerjaanTbl" ("ProjectId", "Status");
CREATE INDEX IF NOT EXISTS idx_subkon_pekerjaan_subkon ON "subkonPekerjaanTbl" ("SubkonId");

CREATE TABLE IF NOT EXISTS "subkonDokumenTbl" (
    "Id"              BIGSERIAL PRIMARY KEY,
    "SubkonId"        BIGINT NOT NULL REFERENCES "subkonTbl"("Id") ON DELETE CASCADE,
    "PekerjaanId"     BIGINT REFERENCES "subkonPekerjaanTbl"("Id") ON DELETE CASCADE,  -- NULL = dokumen perusahaan
    "JenisDokumen"    TEXT NOT NULL CHECK ("JenisDokumen" IN (
                          'NIB / Izin Usaha', 'Sertifikat CSMS / PQ Client', 'ISO 45001 / SMK3', 'HSE Plan',
                          'BPJS Ketenagakerjaan / Asuransi', 'Sertifikat Kompetensi Personil', 'MCU / Fit to Work',
                          'Lainnya')),
    "NoDokumen"       TEXT NOT NULL,
    "NamaPersonil"    TEXT,                                  -- untuk sertifikat kompetensi / MCU per orang
    "Penerbit"        TEXT,
    "TanggalTerbit"   DATE,
    "BerlakuSampai"   DATE,                                  -- NULL = tidak ada masa berlaku
    "LinkDokumen"     TEXT,
    "Catatan"         TEXT,
    "DicatatOleh"     TEXT,
    "DicatatQrCodeId" TEXT,
    "DiubahOleh"      TEXT,
    "CreatedAt"       TIMESTAMPTZ NOT NULL DEFAULT now(),
    "UpdatedAt"       TIMESTAMPTZ NOT NULL DEFAULT now(),
    CHECK ("BerlakuSampai" IS NULL OR "TanggalTerbit" IS NULL OR "BerlakuSampai" >= "TanggalTerbit")
);
CREATE INDEX IF NOT EXISTS idx_subkon_dokumen ON "subkonDokumenTbl" ("SubkonId", "JenisDokumen", "TanggalTerbit");

CREATE TABLE IF NOT EXISTS "subkonEvaluasiTbl" (
    "Id"                BIGSERIAL PRIMARY KEY,
    "NoEvaluasi"        TEXT NOT NULL UNIQUE,                -- EVS/<kode project>/<tahun>/001
    "PekerjaanId"       BIGINT NOT NULL REFERENCES "subkonPekerjaanTbl"("Id"),
    "SubkonId"          BIGINT NOT NULL REFERENCES "subkonTbl"("Id"),
    "ProjectId"         BIGINT NOT NULL REFERENCES "projectTbl"("Id"),
    "Tahap"             TEXT NOT NULL CHECK ("Tahap" IN ('Prakualifikasi', 'Pre-Job Activity', 'Work in Progress', 'Final Evaluation')),
    "TanggalEvaluasi"   TIMESTAMPTZ NOT NULL,
    "ChecklistList"     JSONB NOT NULL DEFAULT '[]'::JSONB,  -- [{elemen, item, nilai: '0'..'3' / 'N/A', catatan}]
    "JumlahDinilai"     INT NOT NULL DEFAULT 0,
    "JumlahNol"         INT NOT NULL DEFAULT 0,
    "NilaiPersen"       NUMERIC(5,1) NOT NULL DEFAULT 0,
    "NilaiMinimum"      INT NOT NULL,
    "TingkatRisiko"     TEXT NOT NULL,
    "Hasil"             TEXT NOT NULL CHECK ("Hasil" IN ('Memenuhi', 'Memenuhi dengan Catatan', 'Tidak Memenuhi')),
    "TemuanTindakan"    TEXT,
    "LinkDokumen"       TEXT,                                -- berkas evaluasi / bukti (Drive)
    "Evaluator"         TEXT,
    "EvaluatorQrCodeId" TEXT,
    "Status"            TEXT NOT NULL DEFAULT 'Menunggu Approval'
                        CHECK ("Status" IN ('Menunggu Approval', 'Dikembalikan', 'Disetujui')),
    "DisetujuiOleh"     TEXT,
    "DisetujuiQrCodeId" TEXT,
    "TanggalDisetujui"  TIMESTAMPTZ,
    "CatatanApproval"   TEXT,
    "DiubahOleh"        TEXT,
    "CreatedAt"         TIMESTAMPTZ NOT NULL DEFAULT now(),
    "UpdatedAt"         TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_subkon_evaluasi_pekerjaan ON "subkonEvaluasiTbl" ("PekerjaanId", "Tahap", "TanggalEvaluasi");
CREATE INDEX IF NOT EXISTS idx_subkon_evaluasi_project ON "subkonEvaluasiTbl" ("ProjectId", "Status", "TanggalEvaluasi");

CREATE TABLE IF NOT EXISTS "subkonChecklistTemplateTbl" (
    "Id"        BIGSERIAL PRIMARY KEY,
    "Tahap"     TEXT NOT NULL,
    "Elemen"    TEXT NOT NULL,
    "Item"      TEXT NOT NULL,
    "Urutan"    INT NOT NULL DEFAULT 0,
    "Status"    TEXT NOT NULL DEFAULT 'Aktif' CHECK ("Status" IN ('Aktif', 'Non-Aktif')),
    "CreatedAt" TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_subkon_checklist_tahap ON "subkonChecklistTemplateTbl" ("Tahap", "Status", "Urutan");

-- Seed draft checklist HANYA kalau tabel masih kosong (biar editan kalian tidak ketimpa).
INSERT INTO "subkonChecklistTemplateTbl" ("Tahap", "Elemen", "Item", "Urutan")
SELECT * FROM (VALUES
    ('Prakualifikasi', 'Kepemimpinan & Komitmen', 'Kebijakan HSE tertulis, ditandatangani pimpinan dan dikomunikasikan', 1),
    ('Prakualifikasi', 'Kepemimpinan & Komitmen', 'Ada sasaran & program HSE tahunan', 2),
    ('Prakualifikasi', 'Organisasi & Tanggung Jawab', 'Struktur organisasi HSE + personil HSE kompeten (Ahli K3 / setara)', 3),
    ('Prakualifikasi', 'Manajemen Risiko', 'Prosedur identifikasi bahaya & penilaian risiko (HIRADC / JSA)', 4),
    ('Prakualifikasi', 'Prosedur Kerja', 'SOP / instruksi kerja aman sesuai lingkup pekerjaan', 5),
    ('Prakualifikasi', 'Prosedur Kerja', 'Menerapkan sistem izin kerja (PTW) untuk pekerjaan berisiko', 6),
    ('Prakualifikasi', 'Kompetensi & Pelatihan', 'Program pelatihan HSE dan matriks kompetensi pekerja', 7),
    ('Prakualifikasi', 'Kompetensi & Pelatihan', 'Sertifikat kompetensi personil kunci (SIO, Ahli K3, juru ikat, dll)', 8),
    ('Prakualifikasi', 'Peralatan', 'Program inspeksi & sertifikasi peralatan (SILO, riksa uji, kalibrasi)', 9),
    ('Prakualifikasi', 'Kesehatan Kerja', 'Program MCU / fit to work pekerja', 10),
    ('Prakualifikasi', 'APD', 'Penyediaan, penggantian & pengawasan pemakaian APD', 11),
    ('Prakualifikasi', 'Tanggap Darurat', 'Prosedur tanggap darurat & catatan latihan (drill)', 12),
    ('Prakualifikasi', 'Insiden', 'Prosedur pelaporan & investigasi insiden', 13),
    ('Prakualifikasi', 'Insiden', 'Statistik kinerja HSE 3 tahun terakhir (LTI, TRIR, fatality) tersedia & wajar', 14),
    ('Prakualifikasi', 'Lingkungan', 'Pengelolaan limbah & aspek lingkungan', 15),
    ('Prakualifikasi', 'Pengelolaan Sub-subkon', 'Seleksi & pengawasan HSE sub-subkon (kalau ada)', 16),
    ('Prakualifikasi', 'Inspeksi & Audit', 'Program inspeksi & audit internal HSE berjalan', 17),
    ('Prakualifikasi', 'Legal', 'Izin usaha, BPJS Ketenagakerjaan & asuransi masih berlaku', 18),
    ('Pre-Job Activity', 'Kick-off', 'Pre-job / kick-off meeting HSE dengan BIMA sudah dilakukan', 1),
    ('Pre-Job Activity', 'Dokumen', 'HSE Plan khusus pekerjaan ini sudah disetujui', 2),
    ('Pre-Job Activity', 'Dokumen', 'JSA / HIRADC pekerjaan sudah dibuat & disosialisasikan', 3),
    ('Pre-Job Activity', 'Personil', 'Daftar pekerja + sertifikat kompetensi sudah diverifikasi', 4),
    ('Pre-Job Activity', 'Personil', 'Seluruh pekerja lulus MCU / fit to work', 5),
    ('Pre-Job Activity', 'Personil', 'Seluruh pekerja sudah ikut safety induction', 6),
    ('Pre-Job Activity', 'Personil', 'Pengawas / HSE subkon di lokasi sudah ditunjuk', 7),
    ('Pre-Job Activity', 'Peralatan', 'Peralatan & kendaraan sudah diinspeksi / bersertifikat', 8),
    ('Pre-Job Activity', 'APD', 'APD sesuai bahaya pekerjaan tersedia untuk semua pekerja', 9),
    ('Pre-Job Activity', 'Tanggap Darurat', 'Rencana tanggap darurat & jalur komunikasi sudah dipahami', 10),
    ('Pre-Job Activity', 'Izin Kerja', 'Jenis izin kerja (PTW) yang dibutuhkan sudah diidentifikasi', 11),
    ('Work in Progress', 'Implementasi', 'HSE Plan dijalankan di lapangan', 1),
    ('Work in Progress', 'Izin Kerja', 'PTW & JSA dipakai sesuai pekerjaan', 2),
    ('Work in Progress', 'Komunikasi', 'Toolbox meeting dilakukan rutin', 3),
    ('Work in Progress', 'Komunikasi', 'Hadir di HSE meeting / inspeksi bersama', 4),
    ('Work in Progress', 'APD', 'Pemakaian APD sesuai', 5),
    ('Work in Progress', 'Peralatan', 'Peralatan & tools layak, tag inspeksi terpasang', 6),
    ('Work in Progress', 'Housekeeping & Lingkungan', 'Housekeeping & pengelolaan limbah baik', 7),
    ('Work in Progress', 'Insiden & Temuan', 'Insiden / near miss dilaporkan & temuan ditindaklanjuti tepat waktu', 8),
    ('Work in Progress', 'Pengawasan', 'Pengawas HSE subkon aktif di lapangan', 9),
    ('Work in Progress', 'Perilaku', 'Patuh Life Saving Rules / tidak ada pelanggaran berat', 10),
    ('Final Evaluation', 'Kinerja', 'Target kinerja HSE tercapai (tanpa LTI / fatality)', 1),
    ('Final Evaluation', 'Kepatuhan', 'Patuh HSE Plan selama pekerjaan', 2),
    ('Final Evaluation', 'Temuan', 'Temuan / tindak lanjut diselesaikan tepat waktu', 3),
    ('Final Evaluation', 'Pelaporan', 'Pelaporan HSE (statistik, man-hours, insiden) lengkap & tepat waktu', 4),
    ('Final Evaluation', 'Kerjasama', 'Kerjasama & respon terhadap instruksi HSE', 5),
    ('Final Evaluation', 'Lingkungan', 'Pengelolaan lingkungan & demobilisasi bersih', 6),
    ('Final Evaluation', 'Rekomendasi', 'Layak dipakai lagi untuk pekerjaan sejenis', 7)
) AS v("Tahap", "Elemen", "Item", "Urutan")
WHERE NOT EXISTS (SELECT 1 FROM "subkonChecklistTemplateTbl");

ALTER TABLE "subkonTbl" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "subkonPekerjaanTbl" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "subkonDokumenTbl" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "subkonEvaluasiTbl" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "subkonChecklistTemplateTbl" ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "subkonTbl_no_direct" ON "subkonTbl";
CREATE POLICY "subkonTbl_no_direct" ON "subkonTbl" FOR ALL TO anon, authenticated USING (false) WITH CHECK (false);
DROP POLICY IF EXISTS "subkonPekerjaanTbl_no_direct" ON "subkonPekerjaanTbl";
CREATE POLICY "subkonPekerjaanTbl_no_direct" ON "subkonPekerjaanTbl" FOR ALL TO anon, authenticated USING (false) WITH CHECK (false);
DROP POLICY IF EXISTS "subkonDokumenTbl_no_direct" ON "subkonDokumenTbl";
CREATE POLICY "subkonDokumenTbl_no_direct" ON "subkonDokumenTbl" FOR ALL TO anon, authenticated USING (false) WITH CHECK (false);
DROP POLICY IF EXISTS "subkonEvaluasiTbl_no_direct" ON "subkonEvaluasiTbl";
CREATE POLICY "subkonEvaluasiTbl_no_direct" ON "subkonEvaluasiTbl" FOR ALL TO anon, authenticated USING (false) WITH CHECK (false);
DROP POLICY IF EXISTS "subkonChecklistTemplateTbl_no_direct" ON "subkonChecklistTemplateTbl";
CREATE POLICY "subkonChecklistTemplateTbl_no_direct" ON "subkonChecklistTemplateTbl" FOR ALL TO anon, authenticated USING (false) WITH CHECK (false);

-- -------------------------------------------------------------------------------------
-- 2. Helper
-- -------------------------------------------------------------------------------------
-- Nilai minimum lulus per tingkat risiko pekerjaan. Ubah angka di sini kalau standar client beda.
CREATE OR REPLACE FUNCTION public.subkon_nilai_minimum(p_risiko TEXT)
RETURNS INT LANGUAGE sql IMMUTABLE AS $$
    SELECT CASE p_risiko WHEN 'Tinggi' THEN 75 WHEN 'Menengah' THEN 65 ELSE 55 END;
$$;

CREATE OR REPLACE FUNCTION public.subkon_dokumen_json(d "subkonDokumenTbl")
RETURNS JSONB LANGUAGE sql STABLE SET search_path = public AS $$
    SELECT jsonb_build_object(
        'id', d."Id", 'subkonId', d."SubkonId", 'pekerjaanId', d."PekerjaanId",
        'noPekerjaan', (SELECT p."NoPekerjaan" FROM "subkonPekerjaanTbl" p WHERE p."Id" = d."PekerjaanId"),
        'jenisDokumen', d."JenisDokumen", 'noDokumen', d."NoDokumen", 'namaPersonil', d."NamaPersonil",
        'penerbit', d."Penerbit", 'tanggalTerbit', d."TanggalTerbit", 'berlakuSampai', d."BerlakuSampai",
        'linkDokumen', d."LinkDokumen", 'catatan', d."Catatan", 'dicatatOleh', d."DicatatOleh",
        'diubahOleh', d."DiubahOleh", 'createdAt', d."CreatedAt",
        'sisaHari', d."BerlakuSampai" - (now() AT TIME ZONE 'Asia/Jakarta')::DATE,
        'statusBerlaku', CASE
            WHEN d."BerlakuSampai" IS NULL THEN 'Tanpa Masa Berlaku'
            WHEN d."BerlakuSampai" < (now() AT TIME ZONE 'Asia/Jakarta')::DATE THEN 'Kedaluwarsa'
            WHEN d."BerlakuSampai" - (now() AT TIME ZONE 'Asia/Jakarta')::DATE <= 30 THEN 'Segera Habis'
            ELSE 'Berlaku' END);
$$;

-- Dokumen yang sedang dipakai = terbaru per (pekerjaan, jenis, nama personil) untuk 1 subkon.
-- Perpanjangan = catat dokumen baru; yang lama tinggal jadi riwayat.
CREATE OR REPLACE FUNCTION public.subkon_dokumen_terkini(p_subkon_id BIGINT)
RETURNS SETOF "subkonDokumenTbl" LANGUAGE sql STABLE SET search_path = public AS $$
    SELECT DISTINCT ON (COALESCE(d."PekerjaanId", 0), d."JenisDokumen", lower(trim(COALESCE(d."NamaPersonil", '')))) d.*
    FROM "subkonDokumenTbl" d
    WHERE d."SubkonId" = p_subkon_id
    ORDER BY COALESCE(d."PekerjaanId", 0), d."JenisDokumen", lower(trim(COALESCE(d."NamaPersonil", ''))),
             d."TanggalTerbit" DESC NULLS LAST, d."BerlakuSampai" DESC NULLS LAST, d."Id" DESC;
$$;

-- Ringkasan CSMS 1 pekerjaan: evaluasi Disetujui terakhir per tahap + jadwal evaluasi berkala (WIP).
CREATE OR REPLACE FUNCTION public.subkon_pekerjaan_json(p "subkonPekerjaanTbl")
RETURNS JSONB LANGUAGE sql STABLE SET search_path = public AS $$
    WITH ok AS (
        SELECT DISTINCT ON (e."Tahap") e."Tahap", e."Id", e."NoEvaluasi", e."TanggalEvaluasi", e."NilaiPersen", e."Hasil"
        FROM "subkonEvaluasiTbl" e
        WHERE e."PekerjaanId" = p."Id" AND e."Status" = 'Disetujui'
        ORDER BY e."Tahap", e."TanggalEvaluasi" DESC, e."Id" DESC
    ), csms AS (
        SELECT COALESCE(jsonb_object_agg(ok."Tahap", jsonb_build_object('id', ok."Id", 'noEvaluasi', ok."NoEvaluasi",
                   'tanggal', ok."TanggalEvaluasi", 'nilai', ok."NilaiPersen", 'hasil', ok."Hasil")), '{}'::JSONB) AS j
        FROM ok
    ), ev AS (
        SELECT count(*) FILTER (WHERE e."Status" = 'Menunggu Approval') AS menunggu,
               count(*) FILTER (WHERE e."Status" = 'Dikembalikan') AS dikembalikan,
               max(e."TanggalEvaluasi") FILTER (WHERE e."Tahap" = 'Work in Progress' AND e."Status" <> 'Dikembalikan') AS wip,
               count(*) AS jumlah
        FROM "subkonEvaluasiTbl" e WHERE e."PekerjaanId" = p."Id"
    ), hari AS (SELECT (now() AT TIME ZONE 'Asia/Jakarta')::DATE AS ini),
    lolos AS (
        SELECT
            EXISTS (SELECT 1 FROM ok WHERE ok."Tahap" = 'Prakualifikasi' AND ok."Hasil" <> 'Tidak Memenuhi') AS pq,
            EXISTS (SELECT 1 FROM ok WHERE ok."Tahap" = 'Pre-Job Activity' AND ok."Hasil" <> 'Tidak Memenuhi') AS pja
    )
    SELECT jsonb_build_object(
        'id', p."Id", 'noPekerjaan', p."NoPekerjaan", 'subkonId', p."SubkonId",
        'kodeSubkon', s."KodeSubkon", 'namaPerusahaan', s."NamaPerusahaan", 'statusSubkon', s."Status",
        'projectId', p."ProjectId", 'namaProject', pr."NamaProject", 'kodeOperational', pr."KodeOperational",
        'noKontrak', pr."NoKontrak", 'client', pr."Client",
        'lingkupPekerjaan', p."LingkupPekerjaan", 'noKontrakPO', p."NoKontrakPO",
        'tanggalMulai', p."TanggalMulai", 'tanggalSelesai', p."TanggalSelesai",
        'tingkatRisiko', p."TingkatRisiko", 'nilaiMinimum', public.subkon_nilai_minimum(p."TingkatRisiko"),
        'jumlahPekerja', p."JumlahPekerja", 'pengawasHSE', p."PengawasHSE",
        'intervalEvaluasiHari', p."IntervalEvaluasiHari", 'status', p."Status", 'keterangan', p."Keterangan",
        'dibuatOleh', p."DibuatOleh", 'diubahOleh', p."DiubahOleh", 'createdAt', p."CreatedAt", 'updatedAt', p."UpdatedAt",
        'csms', csms.j,
        'lolosPrakualifikasi', lolos.pq, 'lolosPreJob', lolos.pja,
        'bolehMulai', lolos.pq AND lolos.pja,
        'evaluasiMenunggu', ev.menunggu, 'evaluasiDikembalikan', ev.dikembalikan, 'jumlahEvaluasi', ev.jumlah,
        'wipTerakhir', ev.wip,
        'wipJatuhTempo', CASE WHEN p."Status" = 'Berjalan'
            THEN COALESCE((ev.wip AT TIME ZONE 'Asia/Jakarta')::DATE, p."TanggalMulai", (p."UpdatedAt" AT TIME ZONE 'Asia/Jakarta')::DATE)
                 + p."IntervalEvaluasiHari" END,
        'wipLewat', p."Status" = 'Berjalan' AND
            COALESCE((ev.wip AT TIME ZONE 'Asia/Jakarta')::DATE, p."TanggalMulai", (p."UpdatedAt" AT TIME ZONE 'Asia/Jakarta')::DATE)
                + p."IntervalEvaluasiHari" < hari.ini,
        'perluFinal', p."Status" = 'Selesai' AND NOT (csms.j ? 'Final Evaluation'))
    FROM "subkonTbl" s, "projectTbl" pr, csms, ev, hari, lolos
    WHERE s."Id" = p."SubkonId" AND pr."Id" = p."ProjectId";
$$;

CREATE OR REPLACE FUNCTION public.subkon_header_json(s "subkonTbl")
RETURNS JSONB LANGUAGE sql STABLE SET search_path = public AS $$
    WITH dok AS (
        SELECT count(*) FILTER (WHERE d."BerlakuSampai" < (now() AT TIME ZONE 'Asia/Jakarta')::DATE) AS habis,
               count(*) FILTER (WHERE d."BerlakuSampai" >= (now() AT TIME ZONE 'Asia/Jakarta')::DATE
                                  AND d."BerlakuSampai" - (now() AT TIME ZONE 'Asia/Jakarta')::DATE <= 30) AS segera,
               count(*) AS jumlah
        FROM public.subkon_dokumen_terkini(s."Id") d
    ), pk AS (
        SELECT count(*) AS jumlah, count(*) FILTER (WHERE p."Status" = 'Berjalan') AS berjalan,
               string_agg(DISTINCT COALESCE(pr."KodeOperational", pr."NamaProject"), ', ') AS project
        FROM "subkonPekerjaanTbl" p JOIN "projectTbl" pr ON pr."Id" = p."ProjectId"
        WHERE p."SubkonId" = s."Id" AND p."Status" <> 'Dibatalkan'
    ), fin AS (
        SELECT e."NilaiPersen", e."Hasil", e."TanggalEvaluasi"
        FROM "subkonEvaluasiTbl" e
        WHERE e."SubkonId" = s."Id" AND e."Tahap" = 'Final Evaluation' AND e."Status" = 'Disetujui'
        ORDER BY e."TanggalEvaluasi" DESC, e."Id" DESC LIMIT 1
    ), pq AS (
        SELECT e."NilaiPersen", e."Hasil", e."TanggalEvaluasi"
        FROM "subkonEvaluasiTbl" e
        WHERE e."SubkonId" = s."Id" AND e."Tahap" = 'Prakualifikasi' AND e."Status" = 'Disetujui'
        ORDER BY e."TanggalEvaluasi" DESC, e."Id" DESC LIMIT 1
    ), ev AS (
        SELECT count(*) FILTER (WHERE e."Status" = 'Menunggu Approval') AS menunggu
        FROM "subkonEvaluasiTbl" e WHERE e."SubkonId" = s."Id"
    )
    SELECT jsonb_build_object(
        'id', s."Id", 'kodeSubkon', s."KodeSubkon", 'namaPerusahaan', s."NamaPerusahaan",
        'bidangUsaha', s."BidangUsaha", 'alamat', s."Alamat", 'noNIB', s."NoNIB",
        'namaKontak', s."NamaKontak", 'jabatanKontak', s."JabatanKontak", 'telepon', s."Telepon", 'email', s."Email",
        'status', s."Status", 'keterangan', s."Keterangan",
        'dibuatOleh', s."DibuatOleh", 'diubahOleh', s."DiubahOleh", 'createdAt', s."CreatedAt", 'updatedAt', s."UpdatedAt",
        'jumlahDokumen', dok.jumlah, 'dokumenKedaluwarsa', dok.habis, 'dokumenSegeraHabis', dok.segera,
        'jumlahPekerjaan', pk.jumlah, 'pekerjaanBerjalan', pk.berjalan, 'project', pk.project,
        'evaluasiMenunggu', ev.menunggu,
        'prakualifikasiTerakhir', (SELECT jsonb_build_object('nilai', pq."NilaiPersen", 'hasil', pq."Hasil", 'tanggal', pq."TanggalEvaluasi") FROM pq),
        'finalTerakhir', (SELECT jsonb_build_object('nilai', fin."NilaiPersen", 'hasil', fin."Hasil", 'tanggal', fin."TanggalEvaluasi") FROM fin))
    FROM dok, pk, ev;
$$;

CREATE OR REPLACE FUNCTION public.subkon_evaluasi_json(e "subkonEvaluasiTbl")
RETURNS JSONB LANGUAGE sql STABLE SET search_path = public AS $$
    SELECT jsonb_build_object(
        'id', e."Id", 'noEvaluasi', e."NoEvaluasi", 'pekerjaanId', e."PekerjaanId", 'subkonId', e."SubkonId",
        'projectId', e."ProjectId", 'noPekerjaan', p."NoPekerjaan", 'lingkupPekerjaan', p."LingkupPekerjaan",
        'kodeSubkon', s."KodeSubkon", 'namaPerusahaan', s."NamaPerusahaan",
        'namaProject', pr."NamaProject", 'kodeOperational', pr."KodeOperational", 'noKontrak', pr."NoKontrak",
        'client', pr."Client",
        'tahap', e."Tahap", 'tanggalEvaluasi', e."TanggalEvaluasi",
        'jumlahDinilai', e."JumlahDinilai", 'jumlahNol', e."JumlahNol",
        'nilaiPersen', e."NilaiPersen", 'nilaiMinimum', e."NilaiMinimum", 'tingkatRisiko', e."TingkatRisiko",
        'hasil', e."Hasil", 'temuanTindakan', e."TemuanTindakan", 'linkDokumen', e."LinkDokumen",
        'evaluator', e."Evaluator", 'status', e."Status",
        'disetujuiOleh', e."DisetujuiOleh", 'tanggalDisetujui', e."TanggalDisetujui",
        'catatanApproval', e."CatatanApproval", 'diubahOleh', e."DiubahOleh",
        'createdAt', e."CreatedAt", 'updatedAt', e."UpdatedAt")
    FROM "subkonPekerjaanTbl" p
    JOIN "subkonTbl" s ON s."Id" = e."SubkonId"
    JOIN "projectTbl" pr ON pr."Id" = e."ProjectId"
    WHERE p."Id" = e."PekerjaanId";
$$;

-- Realisasi HSE Program dari modul ini
CREATE OR REPLACE FUNCTION public.subkon_realisasi_bulanan(p_project_id BIGINT, p_tahun INT)
RETURNS TABLE (kode TEXT, bulan INT, jumlah BIGINT)
LANGUAGE sql STABLE SET search_path = public AS $$
    SELECT 'SUBKON_EVALUASI', EXTRACT(MONTH FROM ("TanggalEvaluasi" AT TIME ZONE 'Asia/Jakarta'))::INT, count(*)
    FROM "subkonEvaluasiTbl"
    WHERE "ProjectId" = p_project_id AND "Status" = 'Disetujui'
      AND EXTRACT(YEAR FROM ("TanggalEvaluasi" AT TIME ZONE 'Asia/Jakarta')) = p_tahun
    GROUP BY 2;
$$;

-- Satu pintu realisasi modul tambahan (069 drill/ERP + 070 alat + 071 subkon) untuk
-- get_hse_program & get_management_review_frame. Modul baru cukup menambah UNION ALL di sini.
CREATE OR REPLACE FUNCTION public.hse_program_realisasi_modul(p_project_id BIGINT, p_tahun INT)
RETURNS TABLE (kode TEXT, bulan INT, jumlah BIGINT)
LANGUAGE sql STABLE SET search_path = public AS $$
    SELECT dr.kode, dr.bulan, dr.jumlah FROM public.drill_realisasi_bulanan(p_project_id, p_tahun) dr
    UNION ALL
    SELECT al.kode, al.bulan, al.jumlah FROM public.alat_realisasi_bulanan(p_project_id, p_tahun) al
    UNION ALL
    SELECT sk.kode, sk.bulan, sk.jumlah FROM public.subkon_realisasi_bulanan(p_project_id, p_tahun) sk;
$$;

-- -------------------------------------------------------------------------------------
-- 3. Baca (terbuka, sama kayak list modul lain)
-- -------------------------------------------------------------------------------------
-- p_project_id: subkon yang punya pekerjaan di project itu
CREATE OR REPLACE FUNCTION public.get_subkon_list(p_project_id BIGINT DEFAULT NULL, p_status TEXT DEFAULT 'Aktif',
                                                  p_cari TEXT DEFAULT NULL)
RETURNS JSONB LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
    SELECT COALESCE(jsonb_agg(public.subkon_header_json(s) ORDER BY s."NamaPerusahaan"), '[]'::JSONB)
    FROM "subkonTbl" s
    WHERE (COALESCE(p_status, '') = '' OR s."Status" = p_status)
      AND (p_project_id IS NULL OR EXISTS (SELECT 1 FROM "subkonPekerjaanTbl" p
                                           WHERE p."SubkonId" = s."Id" AND p."ProjectId" = p_project_id))
      AND (COALESCE(trim(p_cari), '') = '' OR concat_ws(' ', s."KodeSubkon", s."NamaPerusahaan", s."BidangUsaha",
                                                         s."NamaKontak", s."NoNIB") ILIKE '%' || trim(p_cari) || '%');
$$;

CREATE OR REPLACE FUNCTION public.get_subkon_detail(p_id BIGINT)
RETURNS JSONB LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
    SELECT public.subkon_header_json(s) || jsonb_build_object(
        'dokumenList', COALESCE((
            SELECT jsonb_agg(public.subkon_dokumen_json(d) || jsonb_build_object(
                       'terkini', d."Id" IN (SELECT t."Id" FROM public.subkon_dokumen_terkini(s."Id") t))
                   ORDER BY d."PekerjaanId" NULLS FIRST, d."JenisDokumen", d."NamaPersonil" NULLS FIRST,
                            d."TanggalTerbit" DESC NULLS LAST, d."Id" DESC)
            FROM "subkonDokumenTbl" d WHERE d."SubkonId" = s."Id"), '[]'::JSONB),
        'pekerjaanList', COALESCE((
            SELECT jsonb_agg(public.subkon_pekerjaan_json(p) ORDER BY p."TanggalMulai" DESC NULLS FIRST, p."Id" DESC)
            FROM "subkonPekerjaanTbl" p WHERE p."SubkonId" = s."Id"), '[]'::JSONB),
        -- alat di modul Inspeksi Alat yang pemiliknya subkon ini (cocok nama)
        'alatList', COALESCE((
            SELECT jsonb_agg(jsonb_build_object('id', a."Id", 'noAlat', a."NoAlat", 'namaAlat', a."NamaAlat",
                       'kategori', a."Kategori", 'kondisi', a."Kondisi", 'statusAlat', a."StatusAlat")
                   ORDER BY a."NoAlat")
            FROM "alatTbl" a
            WHERE a."Pemilik" = 'Subkon' AND lower(trim(a."NamaPemilik")) = lower(trim(s."NamaPerusahaan"))), '[]'::JSONB))
    FROM "subkonTbl" s WHERE s."Id" = p_id;
$$;

CREATE OR REPLACE FUNCTION public.get_subkon_pekerjaan_list(p_project_id BIGINT DEFAULT NULL, p_status TEXT DEFAULT NULL,
                                                            p_cari TEXT DEFAULT NULL)
RETURNS JSONB LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
    SELECT COALESCE(jsonb_agg(public.subkon_pekerjaan_json(p)
        ORDER BY array_position(ARRAY['Berjalan', 'Rencana', 'Selesai', 'Dibatalkan'], p."Status"),
                 p."TanggalMulai" DESC NULLS FIRST, p."Id" DESC), '[]'::JSONB)
    FROM "subkonPekerjaanTbl" p JOIN "subkonTbl" s ON s."Id" = p."SubkonId"
    WHERE (p_project_id IS NULL OR p."ProjectId" = p_project_id)
      AND (COALESCE(p_status, '') = '' OR p."Status" = p_status)
      AND (COALESCE(trim(p_cari), '') = '' OR concat_ws(' ', p."NoPekerjaan", p."LingkupPekerjaan", p."NoKontrakPO",
                                                         s."NamaPerusahaan", s."KodeSubkon") ILIKE '%' || trim(p_cari) || '%');
$$;

CREATE OR REPLACE FUNCTION public.get_subkon_pekerjaan_detail(p_id BIGINT)
RETURNS JSONB LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
    SELECT public.subkon_pekerjaan_json(p) || jsonb_build_object(
        'evaluasiList', COALESCE((
            SELECT jsonb_agg(public.subkon_evaluasi_json(e) ORDER BY e."TanggalEvaluasi" DESC, e."Id" DESC)
            FROM "subkonEvaluasiTbl" e WHERE e."PekerjaanId" = p."Id"), '[]'::JSONB),
        -- dokumen terkini milik perusahaan + milik pekerjaan ini
        'dokumenList', COALESCE((
            SELECT jsonb_agg(public.subkon_dokumen_json(d) ORDER BY d."PekerjaanId" NULLS FIRST, d."JenisDokumen", d."NamaPersonil" NULLS FIRST)
            FROM public.subkon_dokumen_terkini(p."SubkonId") d
            WHERE d."PekerjaanId" IS NULL OR d."PekerjaanId" = p."Id"), '[]'::JSONB))
    FROM "subkonPekerjaanTbl" p WHERE p."Id" = p_id;
$$;

CREATE OR REPLACE FUNCTION public.get_subkon_evaluasi_list(p_project_id BIGINT DEFAULT NULL, p_tahun INT DEFAULT NULL,
                                                           p_tahap TEXT DEFAULT NULL, p_status TEXT DEFAULT NULL)
RETURNS JSONB LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
    SELECT COALESCE(jsonb_agg(public.subkon_evaluasi_json(e)
        ORDER BY (e."Status" <> 'Disetujui') DESC, e."TanggalEvaluasi" DESC, e."Id" DESC), '[]'::JSONB)
    FROM "subkonEvaluasiTbl" e
    WHERE (p_project_id IS NULL OR e."ProjectId" = p_project_id)
      AND (p_tahun IS NULL OR EXTRACT(YEAR FROM (e."TanggalEvaluasi" AT TIME ZONE 'Asia/Jakarta')) = p_tahun)
      AND (COALESCE(p_tahap, '') = '' OR e."Tahap" = p_tahap)
      AND (COALESCE(p_status, '') = '' OR e."Status" = p_status);
$$;

CREATE OR REPLACE FUNCTION public.get_subkon_evaluasi_detail(p_id BIGINT)
RETURNS JSONB LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
    SELECT public.subkon_evaluasi_json(e) || jsonb_build_object(
        'checklistList', e."ChecklistList",
        'statusPekerjaan', p."Status", 'tingkatRisikoPekerjaan', p."TingkatRisiko",
        'noKontrakPO', p."NoKontrakPO", 'tanggalMulai', p."TanggalMulai", 'tanggalSelesai', p."TanggalSelesai",
        'pengawasHSE', p."PengawasHSE", 'jumlahPekerja', p."JumlahPekerja",
        'bidangUsaha', s."BidangUsaha", 'namaKontak', s."NamaKontak")
    FROM "subkonEvaluasiTbl" e
    JOIN "subkonPekerjaanTbl" p ON p."Id" = e."PekerjaanId"
    JOIN "subkonTbl" s ON s."Id" = e."SubkonId"
    WHERE e."Id" = p_id;
$$;

-- Pengingat dokumen: dokumen terkini subkon aktif yang sudah / akan habis dalam p_hari hari.
-- p_project_id: subkon yang punya pekerjaan (bukan batal) di project itu.
CREATE OR REPLACE FUNCTION public.get_subkon_dokumen_list(p_project_id BIGINT DEFAULT NULL, p_hari INT DEFAULT 60)
RETURNS JSONB LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
    SELECT COALESCE(jsonb_agg(public.subkon_dokumen_json(d) || jsonb_build_object(
               'kodeSubkon', s."KodeSubkon", 'namaPerusahaan', s."NamaPerusahaan")
           ORDER BY d."BerlakuSampai", s."NamaPerusahaan"), '[]'::JSONB)
    FROM "subkonTbl" s
    CROSS JOIN LATERAL public.subkon_dokumen_terkini(s."Id") d
    WHERE s."Status" = 'Aktif' AND d."BerlakuSampai" IS NOT NULL
      AND (p_hari IS NULL OR d."BerlakuSampai" <= (now() AT TIME ZONE 'Asia/Jakarta')::DATE + p_hari)
      AND (d."PekerjaanId" IS NULL OR EXISTS (SELECT 1 FROM "subkonPekerjaanTbl" p
                                              WHERE p."Id" = d."PekerjaanId" AND p."Status" IN ('Rencana', 'Berjalan')))
      AND (p_project_id IS NULL OR EXISTS (SELECT 1 FROM "subkonPekerjaanTbl" p
                                           WHERE p."SubkonId" = s."Id" AND p."ProjectId" = p_project_id
                                             AND p."Status" <> 'Dibatalkan'
                                             AND (d."PekerjaanId" IS NULL OR d."PekerjaanId" = p."Id")));
$$;

CREATE OR REPLACE FUNCTION public.get_subkon_checklist_template(p_tahap TEXT)
RETURNS JSONB LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
    SELECT COALESCE(jsonb_agg(jsonb_build_object('elemen', t."Elemen", 'item', t."Item") ORDER BY t."Urutan", t."Id"), '[]'::JSONB)
    FROM "subkonChecklistTemplateTbl" t
    WHERE t."Status" = 'Aktif' AND t."Tahap" = p_tahap;
$$;

-- -------------------------------------------------------------------------------------
-- 4. Tulis: register subkon, dokumen, pekerjaan (cek PIC ke SmartGate dulu)
-- -------------------------------------------------------------------------------------
-- p_data: {namaPerusahaan, bidangUsaha, alamat, noNIB, namaKontak, jabatanKontak, telepon, email, status, keterangan}
CREATE OR REPLACE FUNCTION public.save_subkon(p_aktor_nama TEXT, p_aktor_qr TEXT, p_id BIGINT, p_data JSONB)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
    v_id    BIGINT := p_id;
    v_namaP TEXT := NULLIF(trim(p_data->>'namaPerusahaan'), '');
    v_email TEXT := NULLIF(trim(p_data->>'email'), '');
    v_seq   INT;
    v_nama  TEXT := COALESCE(NULLIF(trim(p_aktor_nama), ''), upper(trim(p_aktor_qr)));
BEGIN
    PERFORM public.hsse_wajib_akses(p_aktor_nama, p_aktor_qr, 'HSSE-SUB');
    IF v_namaP IS NULL THEN
        RAISE EXCEPTION 'Nama perusahaan wajib diisi.';
    END IF;
    IF v_email IS NOT NULL AND v_email !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' THEN
        RAISE EXCEPTION 'Format email tidak valid.';
    END IF;
    IF EXISTS (SELECT 1 FROM "subkonTbl" WHERE lower(trim("NamaPerusahaan")) = lower(v_namaP) AND "Id" IS DISTINCT FROM v_id) THEN
        RAISE EXCEPTION 'Subkon "%" sudah terdaftar.', v_namaP;
    END IF;

    IF v_id IS NULL THEN
        PERFORM pg_advisory_xact_lock(hashtext('subkon_kode'));
        SELECT COALESCE(max(substring("KodeSubkon" FROM '(\d+)$')::INT), 0) + 1 INTO v_seq FROM "subkonTbl";
        INSERT INTO "subkonTbl" ("KodeSubkon", "NamaPerusahaan", "BidangUsaha", "Alamat", "NoNIB", "NamaKontak",
                                 "JabatanKontak", "Telepon", "Email", "Status", "Keterangan",
                                 "DibuatOleh", "DibuatQrCodeId", "DiubahOleh")
        VALUES ('SUB-' || lpad(v_seq::TEXT, 4, '0'), v_namaP, NULLIF(trim(p_data->>'bidangUsaha'), ''),
                NULLIF(trim(p_data->>'alamat'), ''), NULLIF(trim(p_data->>'noNIB'), ''),
                NULLIF(trim(p_data->>'namaKontak'), ''), NULLIF(trim(p_data->>'jabatanKontak'), ''),
                NULLIF(trim(p_data->>'telepon'), ''), v_email, COALESCE(NULLIF(p_data->>'status', ''), 'Aktif'),
                NULLIF(trim(p_data->>'keterangan'), ''), v_nama, upper(trim(p_aktor_qr)), v_nama)
        RETURNING "Id" INTO v_id;
    ELSE
        UPDATE "subkonTbl" SET
            "NamaPerusahaan" = v_namaP, "BidangUsaha" = NULLIF(trim(p_data->>'bidangUsaha'), ''),
            "Alamat" = NULLIF(trim(p_data->>'alamat'), ''), "NoNIB" = NULLIF(trim(p_data->>'noNIB'), ''),
            "NamaKontak" = NULLIF(trim(p_data->>'namaKontak'), ''), "JabatanKontak" = NULLIF(trim(p_data->>'jabatanKontak'), ''),
            "Telepon" = NULLIF(trim(p_data->>'telepon'), ''), "Email" = v_email,
            "Status" = COALESCE(NULLIF(p_data->>'status', ''), 'Aktif'),
            "Keterangan" = NULLIF(trim(p_data->>'keterangan'), ''),
            "DiubahOleh" = v_nama, "UpdatedAt" = now()
        WHERE "Id" = v_id;
        IF NOT FOUND THEN
            RAISE EXCEPTION 'Subkon % tidak ditemukan.', v_id;
        END IF;
    END IF;
    RETURN public.get_subkon_detail(v_id);
END;
$$;

-- Hapus cuma kalau belum punya pekerjaan (salah input). Subkon lama di-set "Tidak Aktif".
CREATE OR REPLACE FUNCTION public.delete_subkon(p_aktor_nama TEXT, p_aktor_qr TEXT, p_id BIGINT)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
    PERFORM public.hsse_wajib_akses(p_aktor_nama, p_aktor_qr, 'HSSE-SUB');
    IF EXISTS (SELECT 1 FROM "subkonPekerjaanTbl" WHERE "SubkonId" = p_id) THEN
        RAISE EXCEPTION 'Subkon ini sudah punya pekerjaan, tidak bisa dihapus. Ubah status jadi "Tidak Aktif".';
    END IF;
    DELETE FROM "subkonTbl" WHERE "Id" = p_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Subkon % tidak ditemukan.', p_id;
    END IF;
END;
$$;

-- p_data: {pekerjaanId, jenisDokumen, noDokumen, namaPersonil, penerbit, tanggalTerbit, berlakuSampai, linkDokumen, catatan}
-- p_id NULL = dokumen baru (perpanjangan = catat dokumen baru; yang lama tetap jadi riwayat).
CREATE OR REPLACE FUNCTION public.save_subkon_dokumen(p_aktor_nama TEXT, p_aktor_qr TEXT, p_subkon_id BIGINT,
                                                      p_id BIGINT, p_data JSONB)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
    v_jenis   TEXT := NULLIF(trim(p_data->>'jenisDokumen'), '');
    v_pek     BIGINT := NULLIF(p_data->>'pekerjaanId', '')::BIGINT;
    v_terbit  DATE := NULLIF(p_data->>'tanggalTerbit', '')::DATE;
    v_sampai  DATE := NULLIF(p_data->>'berlakuSampai', '')::DATE;
    v_link    TEXT := NULLIF(trim(p_data->>'linkDokumen'), '');
    v_nama    TEXT := COALESCE(NULLIF(trim(p_aktor_nama), ''), upper(trim(p_aktor_qr)));
BEGIN
    PERFORM public.hsse_wajib_akses(p_aktor_nama, p_aktor_qr, 'HSSE-SUB');
    IF NOT EXISTS (SELECT 1 FROM "subkonTbl" WHERE "Id" = p_subkon_id) THEN
        RAISE EXCEPTION 'Subkon % tidak ditemukan.', p_subkon_id;
    END IF;
    IF v_pek IS NOT NULL AND NOT EXISTS (SELECT 1 FROM "subkonPekerjaanTbl" WHERE "Id" = v_pek AND "SubkonId" = p_subkon_id) THEN
        RAISE EXCEPTION 'Pekerjaan % bukan milik subkon ini.', v_pek;
    END IF;
    IF v_jenis IS NULL THEN
        RAISE EXCEPTION 'Pilih jenis dokumen.';
    END IF;
    IF COALESCE(trim(p_data->>'noDokumen'), '') = '' THEN
        RAISE EXCEPTION 'No. dokumen wajib diisi.';
    END IF;
    IF v_jenis IN ('Sertifikat Kompetensi Personil', 'MCU / Fit to Work') AND COALESCE(trim(p_data->>'namaPersonil'), '') = '' THEN
        RAISE EXCEPTION 'Dokumen "%": isi nama personilnya.', v_jenis;
    END IF;
    IF v_sampai IS NOT NULL AND v_terbit IS NOT NULL AND v_sampai < v_terbit THEN
        RAISE EXCEPTION 'Tanggal berlaku sampai tidak boleh sebelum tanggal terbit.';
    END IF;
    IF v_link IS NOT NULL AND v_link !~* '^https?://' THEN
        RAISE EXCEPTION 'Link dokumen harus diawali http:// atau https://';
    END IF;

    IF p_id IS NULL THEN
        INSERT INTO "subkonDokumenTbl" ("SubkonId", "PekerjaanId", "JenisDokumen", "NoDokumen", "NamaPersonil", "Penerbit",
                                        "TanggalTerbit", "BerlakuSampai", "LinkDokumen", "Catatan",
                                        "DicatatOleh", "DicatatQrCodeId", "DiubahOleh")
        VALUES (p_subkon_id, v_pek, v_jenis, trim(p_data->>'noDokumen'), NULLIF(trim(p_data->>'namaPersonil'), ''),
                NULLIF(trim(p_data->>'penerbit'), ''), v_terbit, v_sampai, v_link, NULLIF(trim(p_data->>'catatan'), ''),
                v_nama, upper(trim(p_aktor_qr)), v_nama);
    ELSE
        UPDATE "subkonDokumenTbl" SET "PekerjaanId" = v_pek, "JenisDokumen" = v_jenis, "NoDokumen" = trim(p_data->>'noDokumen'),
            "NamaPersonil" = NULLIF(trim(p_data->>'namaPersonil'), ''), "Penerbit" = NULLIF(trim(p_data->>'penerbit'), ''),
            "TanggalTerbit" = v_terbit, "BerlakuSampai" = v_sampai, "LinkDokumen" = v_link,
            "Catatan" = NULLIF(trim(p_data->>'catatan'), ''), "DiubahOleh" = v_nama, "UpdatedAt" = now()
        WHERE "Id" = p_id AND "SubkonId" = p_subkon_id;
        IF NOT FOUND THEN
            RAISE EXCEPTION 'Dokumen % tidak ditemukan di subkon ini.', p_id;
        END IF;
    END IF;
    UPDATE "subkonTbl" SET "DiubahOleh" = v_nama, "UpdatedAt" = now() WHERE "Id" = p_subkon_id;
    RETURN public.get_subkon_detail(p_subkon_id);
END;
$$;

CREATE OR REPLACE FUNCTION public.delete_subkon_dokumen(p_aktor_nama TEXT, p_aktor_qr TEXT, p_id BIGINT)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
    v_subkon BIGINT;
BEGIN
    PERFORM public.hsse_wajib_akses(p_aktor_nama, p_aktor_qr, 'HSSE-SUB');
    DELETE FROM "subkonDokumenTbl" WHERE "Id" = p_id RETURNING "SubkonId" INTO v_subkon;
    IF v_subkon IS NULL THEN
        RAISE EXCEPTION 'Dokumen % tidak ditemukan.', p_id;
    END IF;
    RETURN public.get_subkon_detail(v_subkon);
END;
$$;

-- p_data: {subkonId, projectId, lingkupPekerjaan, noKontrakPO, tanggalMulai, tanggalSelesai, tingkatRisiko,
--          jumlahPekerja, pengawasHSE, intervalEvaluasiHari, status, keterangan}
CREATE OR REPLACE FUNCTION public.save_subkon_pekerjaan(p_aktor_nama TEXT, p_aktor_qr TEXT, p_id BIGINT, p_data JSONB)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
    v_id       BIGINT := p_id;
    v_lama     "subkonPekerjaanTbl";
    v_subkon   "subkonTbl";
    v_project  BIGINT := NULLIF(p_data->>'projectId', '')::BIGINT;
    v_mulai    DATE := NULLIF(p_data->>'tanggalMulai', '')::DATE;
    v_selesai  DATE := NULLIF(p_data->>'tanggalSelesai', '')::DATE;
    v_risiko   TEXT := COALESCE(NULLIF(p_data->>'tingkatRisiko', ''), 'Menengah');
    v_status   TEXT := COALESCE(NULLIF(p_data->>'status', ''), 'Rencana');
    v_interval INT := COALESCE(NULLIF(p_data->>'intervalEvaluasiHari', '')::INT, 30);
    v_kode     TEXT;
    v_tahun    TEXT;
    v_seq      INT;
    v_nama     TEXT := COALESCE(NULLIF(trim(p_aktor_nama), ''), upper(trim(p_aktor_qr)));
BEGIN
    PERFORM public.hsse_wajib_akses(p_aktor_nama, p_aktor_qr, 'HSSE-SUB');
    SELECT * INTO v_subkon FROM "subkonTbl" WHERE "Id" = NULLIF(p_data->>'subkonId', '')::BIGINT;
    IF v_subkon."Id" IS NULL THEN
        RAISE EXCEPTION 'Pilih subkon dulu.';
    END IF;
    IF v_project IS NULL OR NOT EXISTS (SELECT 1 FROM "projectTbl" WHERE "Id" = v_project) THEN
        RAISE EXCEPTION 'Pilih project dulu.';
    END IF;
    IF COALESCE(trim(p_data->>'lingkupPekerjaan'), '') = '' THEN
        RAISE EXCEPTION 'Lingkup pekerjaan wajib diisi.';
    END IF;
    IF v_selesai IS NOT NULL AND v_mulai IS NOT NULL AND v_selesai < v_mulai THEN
        RAISE EXCEPTION 'Tanggal selesai tidak boleh sebelum tanggal mulai.';
    END IF;
    IF v_interval < 7 OR v_interval > 365 THEN
        RAISE EXCEPTION 'Interval evaluasi berkala harus 7 sampai 365 hari.';
    END IF;
    IF v_status = 'Berjalan' AND v_subkon."Status" = 'Daftar Hitam' THEN
        RAISE EXCEPTION 'Subkon % masuk Daftar Hitam, pekerjaan tidak bisa dijalankan.', v_subkon."NamaPerusahaan";
    END IF;

    IF v_id IS NULL THEN
        IF v_subkon."Status" <> 'Aktif' THEN
            RAISE EXCEPTION 'Subkon % berstatus %. Aktifkan dulu di data subkon.', v_subkon."NamaPerusahaan", v_subkon."Status";
        END IF;
        SELECT COALESCE(NULLIF("KodeOperational", ''), 'P' || "Id") INTO v_kode FROM "projectTbl" WHERE "Id" = v_project;
        v_tahun := to_char(COALESCE(v_mulai, (now() AT TIME ZONE 'Asia/Jakarta')::DATE), 'YYYY');
        PERFORM pg_advisory_xact_lock(hashtext('subkon_pek_no_' || v_kode || v_tahun));
        SELECT COALESCE(max(substring("NoPekerjaan" FROM '(\d+)$')::INT), 0) + 1 INTO v_seq
        FROM "subkonPekerjaanTbl" WHERE "NoPekerjaan" LIKE 'SKP/' || v_kode || '/' || v_tahun || '/%';

        INSERT INTO "subkonPekerjaanTbl" ("NoPekerjaan", "SubkonId", "ProjectId", "LingkupPekerjaan", "NoKontrakPO",
                                          "TanggalMulai", "TanggalSelesai", "TingkatRisiko", "JumlahPekerja", "PengawasHSE",
                                          "IntervalEvaluasiHari", "Status", "Keterangan",
                                          "DibuatOleh", "DibuatQrCodeId", "DiubahOleh")
        VALUES ('SKP/' || v_kode || '/' || v_tahun || '/' || lpad(v_seq::TEXT, 3, '0'), v_subkon."Id", v_project,
                trim(p_data->>'lingkupPekerjaan'), NULLIF(trim(p_data->>'noKontrakPO'), ''), v_mulai, v_selesai, v_risiko,
                NULLIF(p_data->>'jumlahPekerja', '')::INT, NULLIF(trim(p_data->>'pengawasHSE'), ''), v_interval, v_status,
                NULLIF(trim(p_data->>'keterangan'), ''), v_nama, upper(trim(p_aktor_qr)), v_nama)
        RETURNING "Id" INTO v_id;
    ELSE
        SELECT * INTO v_lama FROM "subkonPekerjaanTbl" WHERE "Id" = v_id FOR UPDATE;
        IF v_lama."Id" IS NULL THEN
            RAISE EXCEPTION 'Pekerjaan % tidak ditemukan.', v_id;
        END IF;
        IF EXISTS (SELECT 1 FROM "subkonEvaluasiTbl" WHERE "PekerjaanId" = v_id)
           AND (v_lama."SubkonId" <> v_subkon."Id" OR v_lama."ProjectId" <> v_project) THEN
            RAISE EXCEPTION 'Pekerjaan ini sudah punya evaluasi, subkon / project tidak bisa diganti.';
        END IF;
        UPDATE "subkonPekerjaanTbl" SET
            "SubkonId" = v_subkon."Id", "ProjectId" = v_project, "LingkupPekerjaan" = trim(p_data->>'lingkupPekerjaan'),
            "NoKontrakPO" = NULLIF(trim(p_data->>'noKontrakPO'), ''), "TanggalMulai" = v_mulai, "TanggalSelesai" = v_selesai,
            "TingkatRisiko" = v_risiko, "JumlahPekerja" = NULLIF(p_data->>'jumlahPekerja', '')::INT,
            "PengawasHSE" = NULLIF(trim(p_data->>'pengawasHSE'), ''), "IntervalEvaluasiHari" = v_interval,
            "Status" = v_status, "Keterangan" = NULLIF(trim(p_data->>'keterangan'), ''),
            "DiubahOleh" = v_nama, "UpdatedAt" = now()
        WHERE "Id" = v_id;
    END IF;
    RETURN public.get_subkon_pekerjaan_detail(v_id);
END;
$$;

-- Hapus cuma kalau belum ada evaluasi (salah input). Pekerjaan yang batal di-set "Dibatalkan".
CREATE OR REPLACE FUNCTION public.delete_subkon_pekerjaan(p_aktor_nama TEXT, p_aktor_qr TEXT, p_id BIGINT)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
    PERFORM public.hsse_wajib_akses(p_aktor_nama, p_aktor_qr, 'HSSE-SUB');
    IF EXISTS (SELECT 1 FROM "subkonEvaluasiTbl" WHERE "PekerjaanId" = p_id) THEN
        RAISE EXCEPTION 'Pekerjaan ini sudah punya evaluasi, tidak bisa dihapus. Ubah status jadi "Dibatalkan" atau "Selesai".';
    END IF;
    DELETE FROM "subkonPekerjaanTbl" WHERE "Id" = p_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Pekerjaan % tidak ditemukan.', p_id;
    END IF;
END;
$$;

-- -------------------------------------------------------------------------------------
-- 5. Tulis: evaluasi CSMS
-- -------------------------------------------------------------------------------------
-- p_data: {pekerjaanId, tahap, tanggalEvaluasi, checklistList:[{elemen, item, nilai:'0'..'3'/'N/A', catatan}],
--          hasil, temuanTindakan, linkDokumen}
-- Simpan = ajukan approval. Evaluasi Dikembalikan / Menunggu Approval masih bisa diubah.
CREATE OR REPLACE FUNCTION public.save_subkon_evaluasi(p_aktor_nama TEXT, p_aktor_qr TEXT, p_id BIGINT, p_data JSONB)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
    v_id      BIGINT := p_id;
    v_pek     "subkonPekerjaanTbl";
    v_lama    "subkonEvaluasiTbl";
    v_tgl     TIMESTAMPTZ := COALESCE(NULLIF(p_data->>'tanggalEvaluasi', '')::TIMESTAMPTZ, now());
    v_tahap   TEXT := NULLIF(trim(p_data->>'tahap'), '');
    v_hasil   TEXT := NULLIF(trim(p_data->>'hasil'), '');
    v_link    TEXT := NULLIF(trim(p_data->>'linkDokumen'), '');
    v_list    JSONB := CASE WHEN jsonb_typeof(p_data->'checklistList') = 'array' THEN p_data->'checklistList' ELSE '[]'::JSONB END;
    v_dinilai INT;
    v_nol     INT;
    v_kosong  INT;
    v_total   INT;
    v_persen  NUMERIC(5,1);
    v_min     INT;
    v_kode    TEXT;
    v_tahun   TEXT;
    v_seq     INT;
    v_nama    TEXT := COALESCE(NULLIF(trim(p_aktor_nama), ''), upper(trim(p_aktor_qr)));
BEGIN
    PERFORM public.hsse_wajib_akses(p_aktor_nama, p_aktor_qr, 'HSSE-SUB');
    SELECT * INTO v_pek FROM "subkonPekerjaanTbl" WHERE "Id" = NULLIF(p_data->>'pekerjaanId', '')::BIGINT;
    IF v_pek."Id" IS NULL THEN
        RAISE EXCEPTION 'Pilih pekerjaan subkon yang dievaluasi.';
    END IF;
    IF v_tahap IS NULL OR v_tahap NOT IN ('Prakualifikasi', 'Pre-Job Activity', 'Work in Progress', 'Final Evaluation') THEN
        RAISE EXCEPTION 'Pilih tahap evaluasi.';
    END IF;
    IF v_hasil IS NULL THEN
        RAISE EXCEPTION 'Pilih hasil evaluasi (Memenuhi / Memenuhi dengan Catatan / Tidak Memenuhi).';
    END IF;
    IF v_tgl > now() + INTERVAL '5 minutes' THEN
        RAISE EXCEPTION 'Tanggal evaluasi tidak boleh di masa depan.';
    END IF;
    IF v_link IS NOT NULL AND v_link !~* '^https?://' THEN
        RAISE EXCEPTION 'Link dokumen harus diawali http:// atau https://';
    END IF;

    v_list := COALESCE((SELECT jsonb_agg(jsonb_build_object('elemen', COALESCE(trim(e->>'elemen'), ''), 'item', trim(e->>'item'),
                                                            'nilai', COALESCE(e->>'nilai', ''), 'catatan', COALESCE(trim(e->>'catatan'), '')))
                        FROM jsonb_array_elements(v_list) e WHERE COALESCE(trim(e->>'item'), '') <> ''), '[]'::JSONB);
    SELECT count(*) FILTER (WHERE e->>'nilai' IN ('0', '1', '2', '3')),
           count(*) FILTER (WHERE e->>'nilai' = '0'),
           count(*) FILTER (WHERE e->>'nilai' NOT IN ('0', '1', '2', '3', 'N/A')),
           COALESCE(sum((e->>'nilai')::INT) FILTER (WHERE e->>'nilai' IN ('0', '1', '2', '3')), 0)
    INTO v_dinilai, v_nol, v_kosong, v_total
    FROM jsonb_array_elements(v_list) e;
    IF jsonb_array_length(v_list) = 0 THEN
        RAISE EXCEPTION 'Checklist evaluasi masih kosong.';
    END IF;
    IF v_kosong > 0 THEN
        RAISE EXCEPTION 'Masih ada % item checklist yang belum dinilai (0-3 / N/A).', v_kosong;
    END IF;
    IF v_dinilai = 0 THEN
        RAISE EXCEPTION 'Semua item N/A. Minimal 1 item harus dinilai.';
    END IF;
    v_persen := round(v_total * 100.0 / (3 * v_dinilai), 1);
    -- nilai minimum ikut risiko pekerjaan saat evaluasi pertama disimpan; edit tidak mengubahnya
    v_min := public.subkon_nilai_minimum(v_pek."TingkatRisiko");

    IF v_id IS NOT NULL THEN
        SELECT * INTO v_lama FROM "subkonEvaluasiTbl" WHERE "Id" = v_id FOR UPDATE;
        IF v_lama."Id" IS NULL THEN
            RAISE EXCEPTION 'Evaluasi % tidak ditemukan.', v_id;
        END IF;
        IF v_lama."Status" = 'Disetujui' THEN
            RAISE EXCEPTION 'Evaluasi yang sudah Disetujui tidak bisa diubah. Buat evaluasi baru kalau ada perubahan.';
        END IF;
        IF v_lama."PekerjaanId" <> v_pek."Id" OR v_lama."Tahap" <> v_tahap THEN
            RAISE EXCEPTION 'Pekerjaan / tahap pada evaluasi yang sudah tersimpan tidak bisa diganti. Hapus lalu buat evaluasi baru.';
        END IF;
        v_min := v_lama."NilaiMinimum";
    END IF;

    IF v_persen < v_min AND v_hasil <> 'Tidak Memenuhi' THEN
        RAISE EXCEPTION 'Nilai % di bawah minimum % (risiko %), jadi hasil harus "Tidak Memenuhi".', v_persen, v_min, v_pek."TingkatRisiko";
    END IF;
    IF v_nol > 0 AND v_hasil = 'Memenuhi' THEN
        RAISE EXCEPTION 'Ada % item bernilai 0, jadi hasil tidak bisa "Memenuhi". Pilih "Memenuhi dengan Catatan" atau "Tidak Memenuhi".', v_nol;
    END IF;
    IF v_hasil <> 'Memenuhi' AND COALESCE(trim(p_data->>'temuanTindakan'), '') = '' THEN
        RAISE EXCEPTION 'Hasil "%": tulis temuan dan tindak lanjutnya.', v_hasil;
    END IF;

    IF v_id IS NULL THEN
        IF v_pek."Status" = 'Dibatalkan' THEN
            RAISE EXCEPTION 'Pekerjaan % sudah Dibatalkan.', v_pek."NoPekerjaan";
        END IF;
        SELECT COALESCE(NULLIF("KodeOperational", ''), 'P' || "Id") INTO v_kode FROM "projectTbl" WHERE "Id" = v_pek."ProjectId";
        v_tahun := to_char(v_tgl AT TIME ZONE 'Asia/Jakarta', 'YYYY');
        PERFORM pg_advisory_xact_lock(hashtext('subkon_eval_no_' || v_kode || v_tahun));
        SELECT COALESCE(max(substring("NoEvaluasi" FROM '(\d+)$')::INT), 0) + 1 INTO v_seq
        FROM "subkonEvaluasiTbl" WHERE "NoEvaluasi" LIKE 'EVS/' || v_kode || '/' || v_tahun || '/%';

        INSERT INTO "subkonEvaluasiTbl" ("NoEvaluasi", "PekerjaanId", "SubkonId", "ProjectId", "Tahap", "TanggalEvaluasi",
                                         "ChecklistList", "JumlahDinilai", "JumlahNol", "NilaiPersen", "NilaiMinimum",
                                         "TingkatRisiko", "Hasil", "TemuanTindakan", "LinkDokumen",
                                         "Evaluator", "EvaluatorQrCodeId", "DiubahOleh")
        VALUES ('EVS/' || v_kode || '/' || v_tahun || '/' || lpad(v_seq::TEXT, 3, '0'), v_pek."Id", v_pek."SubkonId",
                v_pek."ProjectId", v_tahap, v_tgl, v_list, v_dinilai, v_nol, v_persen, v_min, v_pek."TingkatRisiko",
                v_hasil, NULLIF(trim(p_data->>'temuanTindakan'), ''), v_link, v_nama, upper(trim(p_aktor_qr)), v_nama)
        RETURNING "Id" INTO v_id;
    ELSE
        UPDATE "subkonEvaluasiTbl" SET "Status" = 'Menunggu Approval', "TanggalEvaluasi" = v_tgl,
            "ChecklistList" = v_list, "JumlahDinilai" = v_dinilai, "JumlahNol" = v_nol, "NilaiPersen" = v_persen,
            "Hasil" = v_hasil, "TemuanTindakan" = NULLIF(trim(p_data->>'temuanTindakan'), ''), "LinkDokumen" = v_link,
            "DiubahOleh" = v_nama, "UpdatedAt" = now()
        WHERE "Id" = v_id;
    END IF;
    RETURN public.get_subkon_evaluasi_detail(v_id);
END;
$$;

CREATE OR REPLACE FUNCTION public.delete_subkon_evaluasi(p_aktor_nama TEXT, p_aktor_qr TEXT, p_id BIGINT)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
    PERFORM public.hsse_wajib_akses(p_aktor_nama, p_aktor_qr, 'HSSE-SUB');
    DELETE FROM "subkonEvaluasiTbl" WHERE "Id" = p_id AND "Status" <> 'Disetujui';
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Evaluasi % tidak ditemukan atau sudah Disetujui (tidak bisa dihapus).', p_id;
    END IF;
END;
$$;

-- p_setuju TRUE = Disetujui, FALSE = Dikembalikan (catatan wajib)
CREATE OR REPLACE FUNCTION public.approve_subkon_evaluasi(p_aktor_nama TEXT, p_aktor_qr TEXT, p_id BIGINT,
                                                          p_setuju BOOLEAN, p_catatan TEXT DEFAULT NULL)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
    v_status TEXT;
    v_nama   TEXT := COALESCE(NULLIF(trim(p_aktor_nama), ''), upper(trim(p_aktor_qr)));
BEGIN
    PERFORM public.hsse_wajib_akses(p_aktor_nama, p_aktor_qr, 'Approve Subkon');
    SELECT "Status" INTO v_status FROM "subkonEvaluasiTbl" WHERE "Id" = p_id FOR UPDATE;
    IF v_status IS DISTINCT FROM 'Menunggu Approval' THEN
        RAISE EXCEPTION 'Evaluasi ini tidak sedang menunggu approval (status: %).', COALESCE(v_status, '-');
    END IF;
    IF p_setuju THEN
        UPDATE "subkonEvaluasiTbl" SET "Status" = 'Disetujui', "DisetujuiOleh" = v_nama,
            "DisetujuiQrCodeId" = upper(trim(p_aktor_qr)), "TanggalDisetujui" = now(),
            "CatatanApproval" = NULLIF(trim(p_catatan), ''), "DiubahOleh" = v_nama, "UpdatedAt" = now()
        WHERE "Id" = p_id;
    ELSE
        IF COALESCE(trim(p_catatan), '') = '' THEN
            RAISE EXCEPTION 'Tulis alasan kenapa dikembalikan.';
        END IF;
        UPDATE "subkonEvaluasiTbl" SET "Status" = 'Dikembalikan', "CatatanApproval" = trim(p_catatan),
            "DiubahOleh" = v_nama, "UpdatedAt" = now()
        WHERE "Id" = p_id;
    END IF;
    RETURN public.get_subkon_evaluasi_detail(p_id);
END;
$$;

-- -------------------------------------------------------------------------------------
-- 6. HSE Program: item baru Evaluasi HSE Subkontraktor (OTOMATIS)
-- -------------------------------------------------------------------------------------
INSERT INTO "hseProgramMasterItemTbl" ("KodeItem", "NamaItem", "Kategori", "SumberRealisasi", "SatuanTarget", "Urutan", "Keterangan")
VALUES ('SUBKON_EVALUASI', 'Evaluasi HSE Subkontraktor (CSMS)', 'Administrasi & Evaluasi', 'OTOMATIS', 'kali', 545,
        'Realisasi dari modul Subkon -- evaluasi CSMS Disetujui (semua tahap), bulan = tanggal evaluasi')
ON CONFLICT ("KodeItem") DO UPDATE SET "SumberRealisasi" = 'OTOMATIS', "Keterangan" = EXCLUDED."Keterangan";

-- -------------------------------------------------------------------------------------
-- 7. Hak eksekusi: helper internal tertutup, RPC halaman terbuka (cek akses ada di dalam)
-- -------------------------------------------------------------------------------------
REVOKE EXECUTE ON FUNCTION public.subkon_dokumen_json("subkonDokumenTbl") FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.subkon_dokumen_terkini(BIGINT) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.subkon_pekerjaan_json("subkonPekerjaanTbl") FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.subkon_header_json("subkonTbl") FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.subkon_evaluasi_json("subkonEvaluasiTbl") FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.subkon_realisasi_bulanan(BIGINT, INT) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.hse_program_realisasi_modul(BIGINT, INT) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.get_subkon_list(BIGINT, TEXT, TEXT) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.get_subkon_detail(BIGINT) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.get_subkon_pekerjaan_list(BIGINT, TEXT, TEXT) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.get_subkon_pekerjaan_detail(BIGINT) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.get_subkon_evaluasi_list(BIGINT, INT, TEXT, TEXT) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.get_subkon_evaluasi_detail(BIGINT) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.get_subkon_dokumen_list(BIGINT, INT) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.get_subkon_checklist_template(TEXT) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.save_subkon(TEXT, TEXT, BIGINT, JSONB) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.delete_subkon(TEXT, TEXT, BIGINT) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.save_subkon_dokumen(TEXT, TEXT, BIGINT, BIGINT, JSONB) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.delete_subkon_dokumen(TEXT, TEXT, BIGINT) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.save_subkon_pekerjaan(TEXT, TEXT, BIGINT, JSONB) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.delete_subkon_pekerjaan(TEXT, TEXT, BIGINT) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.save_subkon_evaluasi(TEXT, TEXT, BIGINT, JSONB) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.delete_subkon_evaluasi(TEXT, TEXT, BIGINT) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.approve_subkon_evaluasi(TEXT, TEXT, BIGINT, BOOLEAN, TEXT) TO anon, authenticated;

NOTIFY pgrst, 'reload schema';

-- =====================================================================================
-- CEK SETELAH JALAN
-- 1) 5 tabel, rls_on = true semua:
-- SELECT relname, relrowsecurity AS rls_on FROM pg_class WHERE relname IN ('subkonTbl', 'subkonPekerjaanTbl', 'subkonDokumenTbl', 'subkonEvaluasiTbl', 'subkonChecklistTemplateTbl');
-- 2) 17 RPC halaman:
-- SELECT count(*) FROM pg_proc WHERE pronamespace = 'public'::regnamespace AND proname IN (
--   'get_subkon_list', 'get_subkon_detail', 'get_subkon_pekerjaan_list', 'get_subkon_pekerjaan_detail',
--   'get_subkon_evaluasi_list', 'get_subkon_evaluasi_detail', 'get_subkon_dokumen_list', 'get_subkon_checklist_template',
--   'save_subkon', 'delete_subkon', 'save_subkon_dokumen', 'delete_subkon_dokumen', 'save_subkon_pekerjaan',
--   'delete_subkon_pekerjaan', 'save_subkon_evaluasi', 'delete_subkon_evaluasi', 'approve_subkon_evaluasi');
-- 3) Item HSE Program baru + checklist terisi (47 baris) + helper sudah ikut subkon:
-- SELECT "KodeItem", "SumberRealisasi", "Urutan" FROM "hseProgramMasterItemTbl" WHERE "KodeItem" = 'SUBKON_EVALUASI';
-- SELECT "Tahap", count(*) FROM "subkonChecklistTemplateTbl" GROUP BY 1;
-- SELECT pg_get_functiondef('public.hse_program_realisasi_modul(bigint,int)'::regprocedure) LIKE '%subkon_realisasi_bulanan%';
-- 4) Tulis tanpa QR harus ditolak ("Verifikasi identitas dulu"):
-- SELECT public.save_subkon(NULL, NULL, NULL, '{}'::jsonb);
--
-- ROLLBACK (hapus modul, data ikut hilang):
-- CREATE OR REPLACE FUNCTION public.hse_program_realisasi_modul(p_project_id BIGINT, p_tahun INT)
-- RETURNS TABLE (kode TEXT, bulan INT, jumlah BIGINT) LANGUAGE sql STABLE SET search_path = public AS $f$
--     SELECT dr.kode, dr.bulan, dr.jumlah FROM public.drill_realisasi_bulanan(p_project_id, p_tahun) dr
--     UNION ALL
--     SELECT al.kode, al.bulan, al.jumlah FROM public.alat_realisasi_bulanan(p_project_id, p_tahun) al; $f$;
-- DELETE FROM "hseProgramTbl" WHERE "ItemId" = (SELECT "Id" FROM "hseProgramMasterItemTbl" WHERE "KodeItem" = 'SUBKON_EVALUASI');
-- DELETE FROM "hseProgramMasterItemTbl" WHERE "KodeItem" = 'SUBKON_EVALUASI';
-- DROP FUNCTION IF EXISTS public.get_subkon_list(BIGINT, TEXT, TEXT), public.get_subkon_detail(BIGINT),
--   public.get_subkon_pekerjaan_list(BIGINT, TEXT, TEXT), public.get_subkon_pekerjaan_detail(BIGINT),
--   public.get_subkon_evaluasi_list(BIGINT, INT, TEXT, TEXT), public.get_subkon_evaluasi_detail(BIGINT),
--   public.get_subkon_dokumen_list(BIGINT, INT), public.get_subkon_checklist_template(TEXT),
--   public.save_subkon(TEXT, TEXT, BIGINT, JSONB), public.delete_subkon(TEXT, TEXT, BIGINT),
--   public.save_subkon_dokumen(TEXT, TEXT, BIGINT, BIGINT, JSONB), public.delete_subkon_dokumen(TEXT, TEXT, BIGINT),
--   public.save_subkon_pekerjaan(TEXT, TEXT, BIGINT, JSONB), public.delete_subkon_pekerjaan(TEXT, TEXT, BIGINT),
--   public.save_subkon_evaluasi(TEXT, TEXT, BIGINT, JSONB), public.delete_subkon_evaluasi(TEXT, TEXT, BIGINT),
--   public.approve_subkon_evaluasi(TEXT, TEXT, BIGINT, BOOLEAN, TEXT), public.subkon_realisasi_bulanan(BIGINT, INT),
--   public.subkon_evaluasi_json("subkonEvaluasiTbl"), public.subkon_header_json("subkonTbl"),
--   public.subkon_pekerjaan_json("subkonPekerjaanTbl"), public.subkon_dokumen_terkini(BIGINT),
--   public.subkon_dokumen_json("subkonDokumenTbl"), public.subkon_nilai_minimum(TEXT);
-- DROP TABLE IF EXISTS "subkonChecklistTemplateTbl", "subkonEvaluasiTbl", "subkonDokumenTbl", "subkonPekerjaanTbl", "subkonTbl";
-- =====================================================================================
