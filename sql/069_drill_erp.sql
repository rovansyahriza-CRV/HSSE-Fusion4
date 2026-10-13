-- =====================================================================================
-- 069 -- Modul Drill / Tanggap Darurat + Review Emergency Response Plan (ERP)
-- Jalankan di project Supabase HSSE-Fusion4 (BUKAN Fusion4 SmartGate). Run after 068.
--
-- Isi:
--   drillTbl        = 1 drill/simulasi (fire, muster, medical, spill, gas release, lainnya):
--                     rencana -> pelaksanaan (absen peserta) -> laporan & evaluasi
--   drillTemuanTbl  = temuan + tindak lanjut per drill (Open/Closed)
--   erpReviewTbl    = catatan review dokumen Emergency Response Plan per project
-- Alur drill:
--   Direncanakan -> (start_drill) Berlangsung -> (finish_drill) Menunggu Approval
--   Menunggu Approval -> (approve_drill) Disetujui | Dikembalikan -> (finish_drill) Menunggu Approval
--   Direncanakan -> (cancel_drill) Dibatalkan
-- Alur review ERP:
--   (save_erp_review) Menunggu Approval -> (approve_erp_review) Disetujui | Dikembalikan -> edit -> Menunggu Approval
-- Akses (dicek di server lewat hsse_wajib_akses dari 065):
--   rencana, mulai, laporan, temuan, review ERP = PIC HSSE-DRL (atau HSSE-ALL)
--   setujui / kembalikan laporan drill & review ERP = Author "Approve Drill" (tidak ikut HSSE-ALL)
--   absen peserta = cukup QR terdaftar di SmartGate (sama dengan TBM)
-- HSE Program: item SAFETY_DRILL, MEDICAL_DRILL, ERP_REVIEW jadi OTOMATIS (hanya yang Disetujui)
--   SAFETY_DRILL  = drill Disetujui, jenis selain Medical, bulan = tanggal pelaksanaan (WIB)
--   MEDICAL_DRILL = drill Disetujui, jenis Medical
--   ERP_REVIEW    = review ERP Disetujui, bulan = tanggal review
--   get_hse_program dan get_management_review_frame ikut diganti (salinan 062 + baris drill).
-- Tabel tidak bisa dibaca/ditulis langsung pakai anon key; semua lewat RPC.
-- Aman dijalankan ulang.
-- =====================================================================================

-- -------------------------------------------------------------------------------------
-- 1. Tabel
-- -------------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS "drillTbl" (
    "Id"                  BIGSERIAL PRIMARY KEY,
    "NoDrill"             TEXT NOT NULL UNIQUE,
    "ProjectId"           BIGINT NOT NULL REFERENCES "projectTbl"("Id"),
    "JenisDrill"          TEXT NOT NULL
                          CHECK ("JenisDrill" IN ('Fire', 'Muster / Evakuasi', 'Medical', 'Spill', 'Gas Release / H2S', 'Lainnya')),
    "Judul"               TEXT NOT NULL,
    "Skenario"            TEXT,
    "LokasiArea"          TEXT,
    "TanggalRencana"      TIMESTAMPTZ NOT NULL,
    "Diumumkan"           BOOLEAN NOT NULL DEFAULT TRUE,   -- FALSE = drill tanpa pemberitahuan
    "Koordinator"         TEXT,
    "TargetPeserta"       INT CHECK ("TargetPeserta" IS NULL OR "TargetPeserta" >= 0),
    "Status"              TEXT NOT NULL DEFAULT 'Direncanakan'
                          CHECK ("Status" IN ('Direncanakan', 'Berlangsung', 'Menunggu Approval', 'Dikembalikan', 'Disetujui', 'Dibatalkan')),
    "DirencanakanOleh"    TEXT,
    "DirencanakanQrCodeId" TEXT,
    "AlasanBatal"         TEXT,
    "DimulaiOleh"         TEXT,
    "TanggalMulai"        TIMESTAMPTZ,                     -- = jam alarm / drill dimulai
    "JamSemuaBerkumpul"   TIMESTAMPTZ,                     -- semua orang terkumpul / kondisi terkendali
    "JamSelesai"          TIMESTAMPTZ,
    "JumlahOrangDiArea"   INT CHECK ("JumlahOrangDiArea" IS NULL OR "JumlahOrangDiArea" >= 0),
    "JumlahHadirManual"   INT CHECK ("JumlahHadirManual" IS NULL OR "JumlahHadirManual" >= 0), -- kalau absen pakai kertas
    "PesertaList"         JSONB NOT NULL DEFAULT '[]'::JSONB, -- [{nama, qrCodeId, peran, jamAbsen}]
    "Kronologi"           TEXT,
    "EvaluasiList"        JSONB NOT NULL DEFAULT '[]'::JSONB, -- [{aspek, hasil: Baik/Cukup/Kurang/NA, catatan}]
    "Kesimpulan"          TEXT,
    "FotoList"            JSONB NOT NULL DEFAULT '[]'::JSONB, -- [{url, fileId}]
    "DilaporkanOleh"      TEXT,
    "DilaporkanQrCodeId"  TEXT,
    "TanggalLaporan"      TIMESTAMPTZ,
    "DisetujuiOleh"       TEXT,
    "DisetujuiQrCodeId"   TEXT,
    "TanggalDisetujui"    TIMESTAMPTZ,
    "CatatanApproval"     TEXT,
    "DiubahOleh"          TEXT,
    "CreatedAt"           TIMESTAMPTZ NOT NULL DEFAULT now(),
    "UpdatedAt"           TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_drill_project ON "drillTbl" ("ProjectId", "Status", "TanggalRencana");

CREATE TABLE IF NOT EXISTS "drillTemuanTbl" (
    "Id"                BIGSERIAL PRIMARY KEY,
    "DrillId"           BIGINT NOT NULL REFERENCES "drillTbl"("Id") ON DELETE CASCADE,
    "Urutan"            INT NOT NULL DEFAULT 0,
    "Temuan"            TEXT NOT NULL,
    "Rekomendasi"       TEXT,
    "PicTindakLanjut"   TEXT,
    "TargetSelesai"     DATE,
    "Status"            TEXT NOT NULL DEFAULT 'Open' CHECK ("Status" IN ('Open', 'Closed')),
    "CatatanPenutupan"  TEXT,
    "DitutupOleh"       TEXT,
    "TanggalDitutup"    TIMESTAMPTZ
);
CREATE INDEX IF NOT EXISTS idx_drill_temuan ON "drillTemuanTbl" ("DrillId", "Urutan");

CREATE TABLE IF NOT EXISTS "erpReviewTbl" (
    "Id"                   BIGSERIAL PRIMARY KEY,
    "ProjectId"            BIGINT NOT NULL REFERENCES "projectTbl"("Id"),
    "NoDokumenErp"         TEXT NOT NULL,
    "RevisiErp"            TEXT,
    "JudulErp"             TEXT,
    "TanggalReview"        DATE NOT NULL,
    "JenisReview"          TEXT NOT NULL DEFAULT 'Tahunan'
                           CHECK ("JenisReview" IN ('Tahunan', 'Pasca Drill', 'Pasca Insiden', 'Perubahan Operasi', 'Lainnya')),
    "DrillId"              BIGINT REFERENCES "drillTbl"("Id") ON DELETE SET NULL,
    "TimReviewer"          TEXT,
    "Hasil"                TEXT NOT NULL CHECK ("Hasil" IN ('Masih Sesuai', 'Perlu Revisi')),
    "RingkasanPerubahan"   TEXT,
    "TindakLanjut"         TEXT,
    "LinkDokumen"          TEXT,
    "TanggalReviewBerikut" DATE,
    "Status"               TEXT NOT NULL DEFAULT 'Menunggu Approval'
                           CHECK ("Status" IN ('Menunggu Approval', 'Dikembalikan', 'Disetujui')),
    "DicatatOleh"          TEXT,
    "DicatatQrCodeId"      TEXT,
    "DisetujuiOleh"        TEXT,
    "DisetujuiQrCodeId"    TEXT,
    "TanggalDisetujui"     TIMESTAMPTZ,
    "CatatanApproval"      TEXT,
    "DiubahOleh"           TEXT,
    "CreatedAt"            TIMESTAMPTZ NOT NULL DEFAULT now(),
    "UpdatedAt"            TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_erp_review_project ON "erpReviewTbl" ("ProjectId", "TanggalReview");

ALTER TABLE "drillTbl" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "drillTemuanTbl" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "erpReviewTbl" ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "drillTbl_no_direct" ON "drillTbl";
CREATE POLICY "drillTbl_no_direct" ON "drillTbl" FOR ALL TO anon, authenticated USING (false) WITH CHECK (false);
DROP POLICY IF EXISTS "drillTemuanTbl_no_direct" ON "drillTemuanTbl";
CREATE POLICY "drillTemuanTbl_no_direct" ON "drillTemuanTbl" FOR ALL TO anon, authenticated USING (false) WITH CHECK (false);
DROP POLICY IF EXISTS "erpReviewTbl_no_direct" ON "erpReviewTbl";
CREATE POLICY "erpReviewTbl_no_direct" ON "erpReviewTbl" FOR ALL TO anon, authenticated USING (false) WITH CHECK (false);

-- -------------------------------------------------------------------------------------
-- 2. Helper JSON
-- -------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.drill_temuan_json(t "drillTemuanTbl")
RETURNS JSONB LANGUAGE sql STABLE AS $$
    SELECT jsonb_build_object(
        'id', t."Id", 'drillId', t."DrillId", 'urutan', t."Urutan", 'temuan', t."Temuan",
        'rekomendasi', t."Rekomendasi", 'picTindakLanjut', t."PicTindakLanjut", 'targetSelesai', t."TargetSelesai",
        'status', t."Status", 'catatanPenutupan', t."CatatanPenutupan", 'ditutupOleh', t."DitutupOleh",
        'tanggalDitutup', t."TanggalDitutup");
$$;

CREATE OR REPLACE FUNCTION public.drill_header_json(d "drillTbl")
RETURNS JSONB LANGUAGE sql STABLE SET search_path = public AS $$
    SELECT jsonb_build_object(
        'id', d."Id", 'noDrill', d."NoDrill", 'projectId', d."ProjectId",
        'namaProject', p."NamaProject", 'kodeOperational', p."KodeOperational", 'noKontrak', p."NoKontrak",
        'client', p."Client",
        'jenisDrill', d."JenisDrill", 'judul', d."Judul", 'skenario', d."Skenario", 'lokasiArea', d."LokasiArea",
        'tanggalRencana', d."TanggalRencana", 'diumumkan', d."Diumumkan", 'koordinator', d."Koordinator",
        'targetPeserta', d."TargetPeserta", 'status', d."Status",
        'direncanakanOleh', d."DirencanakanOleh", 'alasanBatal', d."AlasanBatal",
        'dimulaiOleh', d."DimulaiOleh", 'tanggalMulai', d."TanggalMulai",
        'jamSemuaBerkumpul', d."JamSemuaBerkumpul", 'jamSelesai', d."JamSelesai",
        'waktuResponMenit', CASE WHEN d."TanggalMulai" IS NOT NULL AND d."JamSemuaBerkumpul" IS NOT NULL
            THEN round((EXTRACT(EPOCH FROM (d."JamSemuaBerkumpul" - d."TanggalMulai")) / 60.0)::NUMERIC, 1) END,
        'jumlahOrangDiArea', d."JumlahOrangDiArea", 'jumlahHadirManual', d."JumlahHadirManual",
        'jumlahPesertaScan', jsonb_array_length(d."PesertaList"),
        'jumlahHadir', CASE WHEN jsonb_array_length(d."PesertaList") > 0 THEN jsonb_array_length(d."PesertaList")
                            ELSE COALESCE(d."JumlahHadirManual", 0) END,
        'kesimpulan', d."Kesimpulan",
        'dilaporkanOleh', d."DilaporkanOleh", 'tanggalLaporan', d."TanggalLaporan",
        'disetujuiOleh', d."DisetujuiOleh", 'tanggalDisetujui', d."TanggalDisetujui",
        'catatanApproval', d."CatatanApproval",
        'diubahOleh', d."DiubahOleh", 'createdAt', d."CreatedAt", 'updatedAt', d."UpdatedAt",
        'temuanTotal', (SELECT count(*) FROM "drillTemuanTbl" t WHERE t."DrillId" = d."Id"),
        'temuanOpen', (SELECT count(*) FROM "drillTemuanTbl" t WHERE t."DrillId" = d."Id" AND t."Status" = 'Open'))
    FROM "projectTbl" p WHERE p."Id" = d."ProjectId";
$$;

CREATE OR REPLACE FUNCTION public.erp_review_json(e "erpReviewTbl")
RETURNS JSONB LANGUAGE sql STABLE SET search_path = public AS $$
    SELECT jsonb_build_object(
        'id', e."Id", 'projectId', e."ProjectId", 'namaProject', p."NamaProject",
        'kodeOperational', p."KodeOperational", 'noKontrak', p."NoKontrak",
        'noDokumenErp', e."NoDokumenErp", 'revisiErp', e."RevisiErp", 'judulErp', e."JudulErp",
        'tanggalReview', e."TanggalReview", 'jenisReview', e."JenisReview",
        'drillId', e."DrillId", 'noDrill', d."NoDrill", 'judulDrill', d."Judul",
        'timReviewer', e."TimReviewer", 'hasil', e."Hasil", 'ringkasanPerubahan', e."RingkasanPerubahan",
        'tindakLanjut', e."TindakLanjut", 'linkDokumen', e."LinkDokumen",
        'tanggalReviewBerikut', e."TanggalReviewBerikut", 'status', e."Status",
        'dicatatOleh', e."DicatatOleh", 'diubahOleh', e."DiubahOleh",
        'disetujuiOleh', e."DisetujuiOleh", 'tanggalDisetujui', e."TanggalDisetujui",
        'catatanApproval', e."CatatanApproval",
        'createdAt', e."CreatedAt", 'updatedAt', e."UpdatedAt")
    FROM "projectTbl" p LEFT JOIN "drillTbl" d ON d."Id" = e."DrillId"
    WHERE p."Id" = e."ProjectId";
$$;

-- Realisasi HSE Program dari modul ini (dipakai get_hse_program & get_management_review_frame)
CREATE OR REPLACE FUNCTION public.drill_realisasi_bulanan(p_project_id BIGINT, p_tahun INT)
RETURNS TABLE (kode TEXT, bulan INT, jumlah BIGINT)
LANGUAGE sql STABLE SET search_path = public AS $$
    SELECT CASE WHEN "JenisDrill" = 'Medical' THEN 'MEDICAL_DRILL' ELSE 'SAFETY_DRILL' END,
           EXTRACT(MONTH FROM ("TanggalMulai" AT TIME ZONE 'Asia/Jakarta'))::INT, count(*)
    FROM "drillTbl"
    WHERE "ProjectId" = p_project_id AND "Status" = 'Disetujui'
      AND EXTRACT(YEAR FROM ("TanggalMulai" AT TIME ZONE 'Asia/Jakarta')) = p_tahun
    GROUP BY 1, 2
    UNION ALL
    SELECT 'ERP_REVIEW', EXTRACT(MONTH FROM "TanggalReview")::INT, count(*)
    FROM "erpReviewTbl"
    WHERE "ProjectId" = p_project_id AND "Status" = 'Disetujui' AND EXTRACT(YEAR FROM "TanggalReview") = p_tahun
    GROUP BY 2;
$$;

-- -------------------------------------------------------------------------------------
-- 3. Baca (terbuka, sama kayak list modul lain)
-- -------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_drill_list(p_project_id BIGINT DEFAULT NULL, p_tahun INT DEFAULT NULL,
                                                 p_status TEXT DEFAULT NULL, p_jenis TEXT DEFAULT NULL)
RETURNS JSONB LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
    SELECT COALESCE(jsonb_agg(public.drill_header_json(d)
        ORDER BY (d."Status" IN ('Direncanakan', 'Berlangsung')) DESC,
                 CASE WHEN d."Status" IN ('Direncanakan', 'Berlangsung') THEN d."TanggalRencana" END ASC,
                 COALESCE(d."TanggalMulai", d."TanggalRencana") DESC), '[]'::JSONB)
    FROM "drillTbl" d
    WHERE (p_project_id IS NULL OR d."ProjectId" = p_project_id)
      AND (p_tahun IS NULL OR EXTRACT(YEAR FROM (COALESCE(d."TanggalMulai", d."TanggalRencana") AT TIME ZONE 'Asia/Jakarta')) = p_tahun)
      AND (COALESCE(p_status, '') = '' OR d."Status" = p_status)
      AND (COALESCE(p_jenis, '') = '' OR d."JenisDrill" = p_jenis);
$$;

CREATE OR REPLACE FUNCTION public.get_drill_detail(p_id BIGINT)
RETURNS JSONB LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
    SELECT public.drill_header_json(d) || jsonb_build_object(
        'pesertaList', d."PesertaList", 'kronologi', d."Kronologi",
        'evaluasiList', d."EvaluasiList", 'fotoList', d."FotoList",
        'temuanList', COALESCE((SELECT jsonb_agg(public.drill_temuan_json(t) ORDER BY t."Urutan", t."Id")
                                FROM "drillTemuanTbl" t WHERE t."DrillId" = d."Id"), '[]'::JSONB),
        'erpReviewList', COALESCE((SELECT jsonb_agg(jsonb_build_object('id', e."Id", 'noDokumenErp', e."NoDokumenErp",
                                       'tanggalReview', e."TanggalReview", 'hasil', e."Hasil") ORDER BY e."TanggalReview")
                                   FROM "erpReviewTbl" e WHERE e."DrillId" = d."Id"), '[]'::JSONB))
    FROM "drillTbl" d WHERE d."Id" = p_id;
$$;

-- Semua temuan (default yang Open) lintas drill, buat tab "Temuan" di daftar.
CREATE OR REPLACE FUNCTION public.get_drill_temuan_list(p_project_id BIGINT DEFAULT NULL, p_status TEXT DEFAULT 'Open')
RETURNS JSONB LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
    SELECT COALESCE(jsonb_agg(public.drill_temuan_json(t) || jsonb_build_object(
               'noDrill', d."NoDrill", 'judulDrill', d."Judul", 'jenisDrill', d."JenisDrill",
               'projectId', d."ProjectId", 'namaProject', p."NamaProject", 'kodeOperational', p."KodeOperational",
               'tanggalDrill', COALESCE(d."TanggalMulai", d."TanggalRencana"))
           ORDER BY t."Status", t."TargetSelesai" NULLS LAST, t."Id"), '[]'::JSONB)
    FROM "drillTemuanTbl" t
    JOIN "drillTbl" d ON d."Id" = t."DrillId"
    JOIN "projectTbl" p ON p."Id" = d."ProjectId"
    WHERE (p_project_id IS NULL OR d."ProjectId" = p_project_id)
      AND (COALESCE(p_status, '') = '' OR t."Status" = p_status);
$$;

CREATE OR REPLACE FUNCTION public.get_erp_review_list(p_project_id BIGINT DEFAULT NULL, p_tahun INT DEFAULT NULL)
RETURNS JSONB LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
    SELECT COALESCE(jsonb_agg(public.erp_review_json(e) || jsonb_build_object(
               'terbaru', NOT EXISTS (SELECT 1 FROM "erpReviewTbl" x
                                      WHERE x."ProjectId" = e."ProjectId" AND x."NoDokumenErp" = e."NoDokumenErp"
                                        AND x."Status" = 'Disetujui'
                                        AND (x."TanggalReview", x."Id") > (e."TanggalReview", e."Id")))
           ORDER BY e."TanggalReview" DESC, e."Id" DESC), '[]'::JSONB)
    FROM "erpReviewTbl" e
    WHERE (p_project_id IS NULL OR e."ProjectId" = p_project_id)
      AND (p_tahun IS NULL OR EXTRACT(YEAR FROM e."TanggalReview") = p_tahun);
$$;

CREATE OR REPLACE FUNCTION public.get_erp_review_detail(p_id BIGINT)
RETURNS JSONB LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
    SELECT public.erp_review_json(e) FROM "erpReviewTbl" e WHERE e."Id" = p_id;
$$;

-- -------------------------------------------------------------------------------------
-- 4. Tulis: drill (cek PIC ke SmartGate dulu)
-- -------------------------------------------------------------------------------------
-- p_data: {projectId, jenisDrill, judul, skenario, lokasiArea, tanggalRencana, diumumkan, koordinator, targetPeserta}
-- p_id NULL = rencana baru. Project & tanggal masih bisa diubah selama Direncanakan
-- (nomor drill tidak ikut berubah).
CREATE OR REPLACE FUNCTION public.save_drill(p_aktor_nama TEXT, p_aktor_qr TEXT, p_id BIGINT, p_data JSONB)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
    v_id      BIGINT := p_id;
    v_status  TEXT;
    v_project BIGINT := NULLIF(p_data->>'projectId', '')::BIGINT;
    v_tgl     TIMESTAMPTZ := NULLIF(p_data->>'tanggalRencana', '')::TIMESTAMPTZ;
    v_jenis   TEXT := NULLIF(trim(p_data->>'jenisDrill'), '');
    v_kode    TEXT;
    v_tahun   TEXT;
    v_seq     INT;
    v_nama    TEXT := COALESCE(NULLIF(trim(p_aktor_nama), ''), upper(trim(p_aktor_qr)));
BEGIN
    PERFORM public.hsse_wajib_akses(p_aktor_nama, p_aktor_qr, 'HSSE-DRL');
    IF v_project IS NULL OR NOT EXISTS (SELECT 1 FROM "projectTbl" WHERE "Id" = v_project) THEN
        RAISE EXCEPTION 'Pilih project dulu.';
    END IF;
    IF v_jenis IS NULL THEN
        RAISE EXCEPTION 'Pilih jenis drill.';
    END IF;
    IF COALESCE(trim(p_data->>'judul'), '') = '' THEN
        RAISE EXCEPTION 'Judul drill wajib diisi.';
    END IF;
    IF v_tgl IS NULL THEN
        RAISE EXCEPTION 'Tanggal rencana wajib diisi.';
    END IF;

    IF v_id IS NULL THEN
        SELECT COALESCE(NULLIF("KodeOperational", ''), 'P' || "Id") INTO v_kode FROM "projectTbl" WHERE "Id" = v_project;
        v_tahun := to_char(v_tgl AT TIME ZONE 'Asia/Jakarta', 'YYYY');
        PERFORM pg_advisory_xact_lock(hashtext('drill_no_' || v_kode || v_tahun));
        SELECT COALESCE(max(substring("NoDrill" FROM '(\d+)$')::INT), 0) + 1 INTO v_seq
        FROM "drillTbl" WHERE "NoDrill" LIKE 'DRL/' || v_kode || '/' || v_tahun || '/%';

        INSERT INTO "drillTbl" ("NoDrill", "ProjectId", "JenisDrill", "Judul", "Skenario", "LokasiArea",
                                "TanggalRencana", "Diumumkan", "Koordinator", "TargetPeserta",
                                "DirencanakanOleh", "DirencanakanQrCodeId", "DiubahOleh")
        VALUES ('DRL/' || v_kode || '/' || v_tahun || '/' || lpad(v_seq::TEXT, 3, '0'),
                v_project, v_jenis, trim(p_data->>'judul'), NULLIF(trim(p_data->>'skenario'), ''),
                NULLIF(trim(p_data->>'lokasiArea'), ''), v_tgl, COALESCE((p_data->>'diumumkan')::BOOLEAN, TRUE),
                NULLIF(trim(p_data->>'koordinator'), ''), NULLIF(p_data->>'targetPeserta', '')::INT,
                v_nama, upper(trim(p_aktor_qr)), v_nama)
        RETURNING "Id" INTO v_id;
    ELSE
        SELECT "Status" INTO v_status FROM "drillTbl" WHERE "Id" = v_id FOR UPDATE;
        IF v_status IS NULL THEN
            RAISE EXCEPTION 'Drill % tidak ditemukan.', v_id;
        END IF;
        IF v_status <> 'Direncanakan' THEN
            RAISE EXCEPTION 'Rencana drill berstatus "%" tidak bisa diubah lagi.', v_status;
        END IF;
        UPDATE "drillTbl" SET
            "ProjectId" = v_project, "JenisDrill" = v_jenis, "Judul" = trim(p_data->>'judul'),
            "Skenario" = NULLIF(trim(p_data->>'skenario'), ''), "LokasiArea" = NULLIF(trim(p_data->>'lokasiArea'), ''),
            "TanggalRencana" = v_tgl, "Diumumkan" = COALESCE((p_data->>'diumumkan')::BOOLEAN, TRUE),
            "Koordinator" = NULLIF(trim(p_data->>'koordinator'), ''),
            "TargetPeserta" = NULLIF(p_data->>'targetPeserta', '')::INT,
            "DiubahOleh" = v_nama, "UpdatedAt" = now()
        WHERE "Id" = v_id;
    END IF;
    RETURN public.get_drill_detail(v_id);
END;
$$;

CREATE OR REPLACE FUNCTION public.cancel_drill(p_aktor_nama TEXT, p_aktor_qr TEXT, p_id BIGINT, p_alasan TEXT)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
    v_status TEXT;
    v_nama   TEXT := COALESCE(NULLIF(trim(p_aktor_nama), ''), upper(trim(p_aktor_qr)));
BEGIN
    PERFORM public.hsse_wajib_akses(p_aktor_nama, p_aktor_qr, 'HSSE-DRL');
    SELECT "Status" INTO v_status FROM "drillTbl" WHERE "Id" = p_id FOR UPDATE;
    IF v_status IS DISTINCT FROM 'Direncanakan' THEN
        RAISE EXCEPTION 'Cuma drill yang masih Direncanakan yang bisa dibatalkan (status: %).', COALESCE(v_status, '-');
    END IF;
    IF COALESCE(trim(p_alasan), '') = '' THEN
        RAISE EXCEPTION 'Tulis alasan pembatalan.';
    END IF;
    UPDATE "drillTbl" SET "Status" = 'Dibatalkan', "AlasanBatal" = trim(p_alasan), "DiubahOleh" = v_nama, "UpdatedAt" = now()
    WHERE "Id" = p_id;
    RETURN public.get_drill_detail(p_id);
END;
$$;

CREATE OR REPLACE FUNCTION public.delete_drill(p_aktor_nama TEXT, p_aktor_qr TEXT, p_id BIGINT)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
    v_status TEXT;
BEGIN
    PERFORM public.hsse_wajib_akses(p_aktor_nama, p_aktor_qr, 'HSSE-DRL');
    SELECT "Status" INTO v_status FROM "drillTbl" WHERE "Id" = p_id FOR UPDATE;
    IF v_status IS NULL OR v_status NOT IN ('Direncanakan', 'Dibatalkan') THEN
        RAISE EXCEPTION 'Cuma drill Direncanakan/Dibatalkan yang bisa dihapus (status: %).', COALESCE(v_status, '-');
    END IF;
    DELETE FROM "drillTbl" WHERE "Id" = p_id;
END;
$$;

-- Mulai drill = jam alarm. p_waktu kosong = sekarang; boleh diisi jam lampau buat
-- mencatat drill yang sudah terjadi (absen pakai kertas -> isi JumlahHadirManual di laporan).
CREATE OR REPLACE FUNCTION public.start_drill(p_aktor_nama TEXT, p_aktor_qr TEXT, p_id BIGINT, p_waktu TIMESTAMPTZ DEFAULT NULL)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
    v_status TEXT;
    v_nama   TEXT := COALESCE(NULLIF(trim(p_aktor_nama), ''), upper(trim(p_aktor_qr)));
BEGIN
    PERFORM public.hsse_wajib_akses(p_aktor_nama, p_aktor_qr, 'HSSE-DRL');
    SELECT "Status" INTO v_status FROM "drillTbl" WHERE "Id" = p_id FOR UPDATE;
    IF v_status IS DISTINCT FROM 'Direncanakan' THEN
        RAISE EXCEPTION 'Drill ini tidak bisa dimulai (status: %).', COALESCE(v_status, '-');
    END IF;
    IF p_waktu IS NOT NULL AND p_waktu > now() + INTERVAL '5 minutes' THEN
        RAISE EXCEPTION 'Jam mulai tidak boleh di masa depan.';
    END IF;
    UPDATE "drillTbl" SET "Status" = 'Berlangsung', "TanggalMulai" = COALESCE(p_waktu, now()),
        "DimulaiOleh" = v_nama, "DiubahOleh" = v_nama, "UpdatedAt" = now()
    WHERE "Id" = p_id;
    RETURN public.get_drill_detail(p_id);
END;
$$;

-- Absen peserta: cukup QR terdaftar di SmartGate (sama dengan TBM). Dipanggil dari HP PIC.
CREATE OR REPLACE FUNCTION public.checkin_drill(p_id BIGINT, p_nama TEXT, p_qrcode TEXT, p_peran TEXT DEFAULT 'Peserta')
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
    v_status   TEXT;
    v_peserta  JSONB;
    v_existing JSONB;
    v_qr       TEXT := upper(trim(p_qrcode));
    v_jumlah   INT;
BEGIN
    PERFORM public.hsse_wajib_akses(p_nama, p_qrcode, NULL);
    SELECT "Status", "PesertaList" INTO v_status, v_peserta FROM "drillTbl" WHERE "Id" = p_id FOR UPDATE;
    IF v_status IS NULL THEN
        RETURN jsonb_build_object('success', false, 'message', 'Drill tidak ditemukan.');
    END IF;
    IF v_status <> 'Berlangsung' THEN
        RETURN jsonb_build_object('success', false, 'message', 'Absen cuma bisa saat drill Berlangsung.');
    END IF;
    SELECT elem INTO v_existing FROM jsonb_array_elements(v_peserta) elem
    WHERE upper(elem->>'qrCodeId') = v_qr LIMIT 1;
    IF v_existing IS NOT NULL THEN
        RETURN jsonb_build_object('success', false, 'duplicate', true,
                                  'nama', v_existing->>'nama', 'jamAbsen', v_existing->>'jamAbsen');
    END IF;
    UPDATE "drillTbl"
    SET "PesertaList" = "PesertaList" || jsonb_build_array(jsonb_build_object(
            'nama', COALESCE(NULLIF(trim(p_nama), ''), v_qr), 'qrCodeId', v_qr,
            'peran', COALESCE(NULLIF(trim(p_peran), ''), 'Peserta'), 'jamAbsen', now())),
        "UpdatedAt" = now()
    WHERE "Id" = p_id
    RETURNING jsonb_array_length("PesertaList") INTO v_jumlah;
    RETURN jsonb_build_object('success', true, 'jumlahPeserta', v_jumlah);
END;
$$;

CREATE OR REPLACE FUNCTION public.remove_drill_peserta(p_aktor_nama TEXT, p_aktor_qr TEXT, p_id BIGINT, p_qrcode TEXT)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
    v_status TEXT;
BEGIN
    PERFORM public.hsse_wajib_akses(p_aktor_nama, p_aktor_qr, 'HSSE-DRL');
    SELECT "Status" INTO v_status FROM "drillTbl" WHERE "Id" = p_id FOR UPDATE;
    IF v_status IS NULL OR v_status NOT IN ('Berlangsung', 'Menunggu Approval', 'Dikembalikan') THEN
        RAISE EXCEPTION 'Peserta tidak bisa dihapus (status: %).', COALESCE(v_status, '-');
    END IF;
    UPDATE "drillTbl"
    SET "PesertaList" = COALESCE((SELECT jsonb_agg(elem) FROM jsonb_array_elements("PesertaList") elem
                                  WHERE upper(elem->>'qrCodeId') <> upper(trim(p_qrcode))), '[]'::JSONB),
        "DiubahOleh" = COALESCE(NULLIF(trim(p_aktor_nama), ''), upper(trim(p_aktor_qr))), "UpdatedAt" = now()
    WHERE "Id" = p_id;
    RETURN public.get_drill_detail(p_id);
END;
$$;

-- Laporan & evaluasi = ajukan approval. Bisa dipanggil saat Berlangsung (menutup drill),
-- Dikembalikan (perbaikan), atau Menunggu Approval (koreksi sebelum diputuskan).
-- p_laporan: {jamMulai, jamSemuaBerkumpul, jamSelesai, jumlahOrangDiArea, jumlahHadirManual,
--             kronologi, evaluasiList:[{aspek, hasil, catatan}], kesimpulan}
-- p_temuan : [{id?, temuan, rekomendasi, picTindakLanjut, targetSelesai}]
--            baris dengan id = update (kalau masih Open); tanpa id = baru;
--            temuan Open yang tidak ada di daftar = dihapus; temuan Closed tidak disentuh.
-- p_foto   : [{url, fileId}] atau NULL = foto lama dipertahankan
CREATE OR REPLACE FUNCTION public.finish_drill(p_aktor_nama TEXT, p_aktor_qr TEXT, p_id BIGINT,
                                               p_laporan JSONB, p_temuan JSONB DEFAULT '[]'::JSONB,
                                               p_foto JSONB DEFAULT NULL)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
    v_d       "drillTbl";
    v_nama    TEXT := COALESCE(NULLIF(trim(p_aktor_nama), ''), upper(trim(p_aktor_qr)));
    v_mulai   TIMESTAMPTZ;
    v_kumpul  TIMESTAMPTZ := NULLIF(p_laporan->>'jamSemuaBerkumpul', '')::TIMESTAMPTZ;
    v_selesai TIMESTAMPTZ;
    v_manual  INT := NULLIF(p_laporan->>'jumlahHadirManual', '')::INT;
    v_t       JSONB;
    v_urut    INT := 0;
    v_ids     BIGINT[] := '{}';
    v_tid     BIGINT;
BEGIN
    PERFORM public.hsse_wajib_akses(p_aktor_nama, p_aktor_qr, 'HSSE-DRL');
    SELECT * INTO v_d FROM "drillTbl" WHERE "Id" = p_id FOR UPDATE;
    IF v_d."Id" IS NULL THEN
        RAISE EXCEPTION 'Drill % tidak ditemukan.', p_id;
    END IF;
    IF v_d."Status" NOT IN ('Berlangsung', 'Menunggu Approval', 'Dikembalikan') THEN
        RAISE EXCEPTION 'Laporan tidak bisa diisi/diubah (status: %).', v_d."Status";
    END IF;

    v_mulai := COALESCE(NULLIF(p_laporan->>'jamMulai', '')::TIMESTAMPTZ, v_d."TanggalMulai");
    v_selesai := COALESCE(NULLIF(p_laporan->>'jamSelesai', '')::TIMESTAMPTZ, v_d."JamSelesai", now());
    IF v_kumpul IS NOT NULL AND v_kumpul < v_mulai THEN
        RAISE EXCEPTION 'Jam semua berkumpul tidak boleh sebelum jam mulai/alarm.';
    END IF;
    IF v_selesai < v_mulai THEN
        RAISE EXCEPTION 'Jam selesai tidak boleh sebelum jam mulai/alarm.';
    END IF;
    IF jsonb_array_length(v_d."PesertaList") = 0 AND COALESCE(v_manual, 0) = 0 THEN
        RAISE EXCEPTION 'Belum ada peserta. Scan peserta dulu, atau isi jumlah hadir manual kalau absen pakai kertas.';
    END IF;
    IF COALESCE(trim(p_laporan->>'kesimpulan'), '') = '' THEN
        RAISE EXCEPTION 'Kesimpulan drill wajib diisi.';
    END IF;

    UPDATE "drillTbl" SET
        "Status" = 'Menunggu Approval',
        "TanggalMulai" = v_mulai, "JamSemuaBerkumpul" = v_kumpul, "JamSelesai" = v_selesai,
        "JumlahOrangDiArea" = NULLIF(p_laporan->>'jumlahOrangDiArea', '')::INT,
        "JumlahHadirManual" = v_manual,
        "Kronologi" = NULLIF(trim(p_laporan->>'kronologi'), ''),
        "EvaluasiList" = COALESCE(CASE WHEN jsonb_typeof(p_laporan->'evaluasiList') = 'array'
                                       THEN p_laporan->'evaluasiList' END, '[]'::JSONB),
        "Kesimpulan" = trim(p_laporan->>'kesimpulan'),
        "FotoList" = COALESCE(p_foto, "FotoList"),
        "DilaporkanOleh" = COALESCE("DilaporkanOleh", v_nama),
        "DilaporkanQrCodeId" = COALESCE("DilaporkanQrCodeId", upper(trim(p_aktor_qr))),
        "TanggalLaporan" = COALESCE("TanggalLaporan", now()),
        "DiubahOleh" = v_nama, "UpdatedAt" = now()
    WHERE "Id" = p_id;

    IF jsonb_typeof(p_temuan) = 'array' THEN
        FOR v_t IN SELECT value FROM jsonb_array_elements(p_temuan) LOOP
            v_urut := v_urut + 1;
            v_tid := NULLIF(v_t->>'id', '')::BIGINT;
            IF COALESCE(trim(v_t->>'temuan'), '') = '' THEN
                RAISE EXCEPTION 'Temuan #%: isi temuannya, atau hapus barisnya.', v_urut;
            END IF;
            IF v_tid IS NOT NULL AND EXISTS (SELECT 1 FROM "drillTemuanTbl" WHERE "Id" = v_tid AND "DrillId" = p_id) THEN
                UPDATE "drillTemuanTbl" SET "Urutan" = v_urut, "Temuan" = trim(v_t->>'temuan'),
                    "Rekomendasi" = NULLIF(trim(v_t->>'rekomendasi'), ''),
                    "PicTindakLanjut" = NULLIF(trim(v_t->>'picTindakLanjut'), ''),
                    "TargetSelesai" = NULLIF(v_t->>'targetSelesai', '')::DATE
                WHERE "Id" = v_tid AND "Status" = 'Open';
                UPDATE "drillTemuanTbl" SET "Urutan" = v_urut WHERE "Id" = v_tid;
            ELSE
                INSERT INTO "drillTemuanTbl" ("DrillId", "Urutan", "Temuan", "Rekomendasi", "PicTindakLanjut", "TargetSelesai")
                VALUES (p_id, v_urut, trim(v_t->>'temuan'), NULLIF(trim(v_t->>'rekomendasi'), ''),
                        NULLIF(trim(v_t->>'picTindakLanjut'), ''), NULLIF(v_t->>'targetSelesai', '')::DATE)
                RETURNING "Id" INTO v_tid;
            END IF;
            v_ids := v_ids || v_tid;
        END LOOP;
        DELETE FROM "drillTemuanTbl" WHERE "DrillId" = p_id AND "Status" = 'Open' AND NOT ("Id" = ANY (v_ids));
    END IF;

    RETURN public.get_drill_detail(p_id);
END;
$$;

CREATE OR REPLACE FUNCTION public.close_drill_temuan(p_aktor_nama TEXT, p_aktor_qr TEXT, p_temuan_id BIGINT,
                                                     p_catatan TEXT, p_buka_lagi BOOLEAN DEFAULT FALSE)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
    v_drill  BIGINT;
    v_status TEXT;
    v_nama   TEXT := COALESCE(NULLIF(trim(p_aktor_nama), ''), upper(trim(p_aktor_qr)));
BEGIN
    PERFORM public.hsse_wajib_akses(p_aktor_nama, p_aktor_qr, 'HSSE-DRL');
    SELECT "DrillId", "Status" INTO v_drill, v_status FROM "drillTemuanTbl" WHERE "Id" = p_temuan_id FOR UPDATE;
    IF v_drill IS NULL THEN
        RAISE EXCEPTION 'Temuan % tidak ditemukan.', p_temuan_id;
    END IF;
    IF p_buka_lagi THEN
        IF v_status <> 'Closed' THEN
            RAISE EXCEPTION 'Temuan ini masih Open.';
        END IF;
        UPDATE "drillTemuanTbl" SET "Status" = 'Open',
            "CatatanPenutupan" = COALESCE(NULLIF(trim(p_catatan), '') || E'\n', '') || '[dibuka lagi oleh ' || v_nama || ']',
            "DitutupOleh" = NULL, "TanggalDitutup" = NULL
        WHERE "Id" = p_temuan_id;
    ELSE
        IF v_status <> 'Open' THEN
            RAISE EXCEPTION 'Temuan ini sudah Closed.';
        END IF;
        IF COALESCE(trim(p_catatan), '') = '' THEN
            RAISE EXCEPTION 'Tulis bukti/catatan penyelesaian tindak lanjut.';
        END IF;
        UPDATE "drillTemuanTbl" SET "Status" = 'Closed', "CatatanPenutupan" = trim(p_catatan),
            "DitutupOleh" = v_nama, "TanggalDitutup" = now()
        WHERE "Id" = p_temuan_id;
    END IF;
    UPDATE "drillTbl" SET "DiubahOleh" = v_nama, "UpdatedAt" = now() WHERE "Id" = v_drill;
    RETURN public.get_drill_detail(v_drill);
END;
$$;

-- p_setuju TRUE = Disetujui, FALSE = Dikembalikan (catatan wajib)
CREATE OR REPLACE FUNCTION public.approve_drill(p_aktor_nama TEXT, p_aktor_qr TEXT, p_id BIGINT,
                                                p_setuju BOOLEAN, p_catatan TEXT DEFAULT NULL)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
    v_status TEXT;
    v_nama   TEXT := COALESCE(NULLIF(trim(p_aktor_nama), ''), upper(trim(p_aktor_qr)));
BEGIN
    PERFORM public.hsse_wajib_akses(p_aktor_nama, p_aktor_qr, 'Approve Drill');
    SELECT "Status" INTO v_status FROM "drillTbl" WHERE "Id" = p_id FOR UPDATE;
    IF v_status IS DISTINCT FROM 'Menunggu Approval' THEN
        RAISE EXCEPTION 'Laporan drill ini tidak sedang menunggu approval (status: %).', COALESCE(v_status, '-');
    END IF;
    IF p_setuju THEN
        UPDATE "drillTbl" SET "Status" = 'Disetujui', "DisetujuiOleh" = v_nama,
            "DisetujuiQrCodeId" = upper(trim(p_aktor_qr)), "TanggalDisetujui" = now(),
            "CatatanApproval" = NULLIF(trim(p_catatan), ''), "DiubahOleh" = v_nama, "UpdatedAt" = now()
        WHERE "Id" = p_id;
    ELSE
        IF COALESCE(trim(p_catatan), '') = '' THEN
            RAISE EXCEPTION 'Tulis alasan kenapa dikembalikan.';
        END IF;
        UPDATE "drillTbl" SET "Status" = 'Dikembalikan', "CatatanApproval" = trim(p_catatan),
            "DiubahOleh" = v_nama, "UpdatedAt" = now()
        WHERE "Id" = p_id;
    END IF;
    RETURN public.get_drill_detail(p_id);
END;
$$;

-- -------------------------------------------------------------------------------------
-- 5. Tulis: review ERP
-- -------------------------------------------------------------------------------------
-- p_data: {projectId, noDokumenErp, revisiErp, judulErp, tanggalReview, jenisReview, drillId,
--          timReviewer, hasil, ringkasanPerubahan, tindakLanjut, linkDokumen, tanggalReviewBerikut}
CREATE OR REPLACE FUNCTION public.save_erp_review(p_aktor_nama TEXT, p_aktor_qr TEXT, p_id BIGINT, p_data JSONB)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
    v_id      BIGINT := p_id;
    v_project BIGINT := NULLIF(p_data->>'projectId', '')::BIGINT;
    v_tgl     DATE := NULLIF(p_data->>'tanggalReview', '')::DATE;
    v_drill   BIGINT := NULLIF(p_data->>'drillId', '')::BIGINT;
    v_hasil   TEXT := NULLIF(trim(p_data->>'hasil'), '');
    v_link    TEXT := NULLIF(trim(p_data->>'linkDokumen'), '');
    v_nama    TEXT := COALESCE(NULLIF(trim(p_aktor_nama), ''), upper(trim(p_aktor_qr)));
BEGIN
    PERFORM public.hsse_wajib_akses(p_aktor_nama, p_aktor_qr, 'HSSE-DRL');
    IF v_project IS NULL OR NOT EXISTS (SELECT 1 FROM "projectTbl" WHERE "Id" = v_project) THEN
        RAISE EXCEPTION 'Pilih project dulu.';
    END IF;
    IF COALESCE(trim(p_data->>'noDokumenErp'), '') = '' THEN
        RAISE EXCEPTION 'No. dokumen ERP wajib diisi.';
    END IF;
    IF v_tgl IS NULL THEN
        RAISE EXCEPTION 'Tanggal review wajib diisi.';
    END IF;
    IF v_hasil IS NULL THEN
        RAISE EXCEPTION 'Pilih hasil review.';
    END IF;
    IF v_hasil = 'Perlu Revisi' AND COALESCE(trim(p_data->>'ringkasanPerubahan'), '') = '' THEN
        RAISE EXCEPTION 'Hasil "Perlu Revisi": tulis ringkasan perubahan yang dibutuhkan.';
    END IF;
    IF v_link IS NOT NULL AND v_link !~* '^https?://' THEN
        RAISE EXCEPTION 'Link dokumen harus diawali http:// atau https://';
    END IF;
    IF v_drill IS NOT NULL AND NOT EXISTS (SELECT 1 FROM "drillTbl" WHERE "Id" = v_drill AND "ProjectId" = v_project) THEN
        RAISE EXCEPTION 'Drill terkait harus dari project yang sama.';
    END IF;

    IF v_id IS NULL THEN
        INSERT INTO "erpReviewTbl" ("ProjectId", "NoDokumenErp", "RevisiErp", "JudulErp", "TanggalReview", "JenisReview",
            "DrillId", "TimReviewer", "Hasil", "RingkasanPerubahan", "TindakLanjut", "LinkDokumen", "TanggalReviewBerikut",
            "DicatatOleh", "DicatatQrCodeId", "DiubahOleh")
        VALUES (v_project, trim(p_data->>'noDokumenErp'), NULLIF(trim(p_data->>'revisiErp'), ''),
            NULLIF(trim(p_data->>'judulErp'), ''), v_tgl, COALESCE(NULLIF(p_data->>'jenisReview', ''), 'Tahunan'),
            v_drill, NULLIF(trim(p_data->>'timReviewer'), ''), v_hasil, NULLIF(trim(p_data->>'ringkasanPerubahan'), ''),
            NULLIF(trim(p_data->>'tindakLanjut'), ''), v_link,
            COALESCE(NULLIF(p_data->>'tanggalReviewBerikut', '')::DATE, (v_tgl + INTERVAL '1 year')::DATE),
            v_nama, upper(trim(p_aktor_qr)), v_nama)
        RETURNING "Id" INTO v_id;
    ELSE
        IF NOT EXISTS (SELECT 1 FROM "erpReviewTbl" WHERE "Id" = v_id) THEN
            RAISE EXCEPTION 'Review ERP % tidak ditemukan.', v_id;
        END IF;
        IF EXISTS (SELECT 1 FROM "erpReviewTbl" WHERE "Id" = v_id AND "Status" = 'Disetujui') THEN
            RAISE EXCEPTION 'Review ERP yang sudah Disetujui tidak bisa diubah. Catat review baru kalau ada perubahan.';
        END IF;
        UPDATE "erpReviewTbl" SET "Status" = 'Menunggu Approval',
            "ProjectId" = v_project, "NoDokumenErp" = trim(p_data->>'noDokumenErp'),
            "RevisiErp" = NULLIF(trim(p_data->>'revisiErp'), ''), "JudulErp" = NULLIF(trim(p_data->>'judulErp'), ''),
            "TanggalReview" = v_tgl, "JenisReview" = COALESCE(NULLIF(p_data->>'jenisReview', ''), 'Tahunan'),
            "DrillId" = v_drill, "TimReviewer" = NULLIF(trim(p_data->>'timReviewer'), ''), "Hasil" = v_hasil,
            "RingkasanPerubahan" = NULLIF(trim(p_data->>'ringkasanPerubahan'), ''),
            "TindakLanjut" = NULLIF(trim(p_data->>'tindakLanjut'), ''), "LinkDokumen" = v_link,
            "TanggalReviewBerikut" = COALESCE(NULLIF(p_data->>'tanggalReviewBerikut', '')::DATE, (v_tgl + INTERVAL '1 year')::DATE),
            "DiubahOleh" = v_nama, "UpdatedAt" = now()
        WHERE "Id" = v_id;
    END IF;
    RETURN public.get_erp_review_detail(v_id);
END;
$$;

CREATE OR REPLACE FUNCTION public.delete_erp_review(p_aktor_nama TEXT, p_aktor_qr TEXT, p_id BIGINT)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
    PERFORM public.hsse_wajib_akses(p_aktor_nama, p_aktor_qr, 'HSSE-DRL');
    DELETE FROM "erpReviewTbl" WHERE "Id" = p_id AND "Status" <> 'Disetujui';
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Review ERP % tidak ditemukan atau sudah Disetujui (tidak bisa dihapus).', p_id;
    END IF;
END;
$$;

CREATE OR REPLACE FUNCTION public.approve_erp_review(p_aktor_nama TEXT, p_aktor_qr TEXT, p_id BIGINT,
                                                     p_setuju BOOLEAN, p_catatan TEXT DEFAULT NULL)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
    v_status TEXT;
    v_nama   TEXT := COALESCE(NULLIF(trim(p_aktor_nama), ''), upper(trim(p_aktor_qr)));
BEGIN
    PERFORM public.hsse_wajib_akses(p_aktor_nama, p_aktor_qr, 'Approve Drill');
    SELECT "Status" INTO v_status FROM "erpReviewTbl" WHERE "Id" = p_id FOR UPDATE;
    IF v_status IS DISTINCT FROM 'Menunggu Approval' THEN
        RAISE EXCEPTION 'Review ERP ini tidak sedang menunggu approval (status: %).', COALESCE(v_status, '-');
    END IF;
    IF p_setuju THEN
        UPDATE "erpReviewTbl" SET "Status" = 'Disetujui', "DisetujuiOleh" = v_nama,
            "DisetujuiQrCodeId" = upper(trim(p_aktor_qr)), "TanggalDisetujui" = now(),
            "CatatanApproval" = NULLIF(trim(p_catatan), ''), "DiubahOleh" = v_nama, "UpdatedAt" = now()
        WHERE "Id" = p_id;
    ELSE
        IF COALESCE(trim(p_catatan), '') = '' THEN
            RAISE EXCEPTION 'Tulis alasan kenapa dikembalikan.';
        END IF;
        UPDATE "erpReviewTbl" SET "Status" = 'Dikembalikan', "CatatanApproval" = trim(p_catatan),
            "DiubahOleh" = v_nama, "UpdatedAt" = now()
        WHERE "Id" = p_id;
    END IF;
    RETURN public.get_erp_review_detail(p_id);
END;
$$;

-- -------------------------------------------------------------------------------------
-- 6. HSE Program: 3 item Emergency Preparedness jadi OTOMATIS
-- -------------------------------------------------------------------------------------
UPDATE "hseProgramMasterItemTbl" SET "SumberRealisasi" = 'OTOMATIS',
    "Keterangan" = 'Realisasi dari modul Drill & ERP -- laporan drill Disetujui selain jenis Medical, bulan = tanggal pelaksanaan'
WHERE "KodeItem" = 'SAFETY_DRILL';
UPDATE "hseProgramMasterItemTbl" SET "SumberRealisasi" = 'OTOMATIS',
    "Keterangan" = 'Realisasi dari modul Drill & ERP -- laporan drill Disetujui jenis Medical, bulan = tanggal pelaksanaan'
WHERE "KodeItem" = 'MEDICAL_DRILL';
UPDATE "hseProgramMasterItemTbl" SET "SumberRealisasi" = 'OTOMATIS',
    "Keterangan" = 'Realisasi dari modul Drill & ERP -- review ERP Disetujui, bulan = tanggal review'
WHERE "KodeItem" = 'ERP_REVIEW';

-- Salinan get_hse_program dari 062 + baris drill/ERP di akhir CTE realisasi.
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
        SELECT dr.kode, dr.bulan, dr.jumlah FROM public.drill_realisasi_bulanan(p_project_id, p_tahun) dr
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

-- Salinan get_management_review_frame dari 062 + 3 baris WHEN drill/ERP.
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
                    WHEN 'SAFETY_DRILL' THEN (SELECT COALESCE(SUM(dr.jumlah), 0) FROM public.drill_realisasi_bulanan(p_project_id, v_tahun) dr WHERE dr.kode = 'SAFETY_DRILL')
                    WHEN 'MEDICAL_DRILL' THEN (SELECT COALESCE(SUM(dr.jumlah), 0) FROM public.drill_realisasi_bulanan(p_project_id, v_tahun) dr WHERE dr.kode = 'MEDICAL_DRILL')
                    WHEN 'ERP_REVIEW' THEN (SELECT COALESCE(SUM(dr.jumlah), 0) FROM public.drill_realisasi_bulanan(p_project_id, v_tahun) dr WHERE dr.kode = 'ERP_REVIEW')
                    ELSE 0
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
REVOKE EXECUTE ON FUNCTION public.drill_temuan_json("drillTemuanTbl") FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.drill_header_json("drillTbl") FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.erp_review_json("erpReviewTbl") FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.drill_realisasi_bulanan(BIGINT, INT) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.get_drill_list(BIGINT, INT, TEXT, TEXT) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.get_drill_detail(BIGINT) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.get_drill_temuan_list(BIGINT, TEXT) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.get_erp_review_list(BIGINT, INT) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.get_erp_review_detail(BIGINT) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.save_drill(TEXT, TEXT, BIGINT, JSONB) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.cancel_drill(TEXT, TEXT, BIGINT, TEXT) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.delete_drill(TEXT, TEXT, BIGINT) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.start_drill(TEXT, TEXT, BIGINT, TIMESTAMPTZ) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.checkin_drill(BIGINT, TEXT, TEXT, TEXT) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.remove_drill_peserta(TEXT, TEXT, BIGINT, TEXT) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.finish_drill(TEXT, TEXT, BIGINT, JSONB, JSONB, JSONB) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.close_drill_temuan(TEXT, TEXT, BIGINT, TEXT, BOOLEAN) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.approve_drill(TEXT, TEXT, BIGINT, BOOLEAN, TEXT) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.approve_erp_review(TEXT, TEXT, BIGINT, BOOLEAN, TEXT) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.save_erp_review(TEXT, TEXT, BIGINT, JSONB) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.delete_erp_review(TEXT, TEXT, BIGINT) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.get_hse_program(BIGINT, INT) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.get_management_review_frame(BIGINT, INT) TO anon, authenticated;

NOTIFY pgrst, 'reload schema';

-- =====================================================================================
-- CEK SETELAH JALAN
-- 1) 3 tabel, rls_on = true semua:
-- SELECT relname, relrowsecurity AS rls_on FROM pg_class WHERE relname IN ('drillTbl', 'drillTemuanTbl', 'erpReviewTbl');
-- 2) 17 RPC halaman:
-- SELECT count(*) FROM pg_proc WHERE pronamespace = 'public'::regnamespace AND proname IN (
--   'get_drill_list', 'get_drill_detail', 'get_drill_temuan_list', 'get_erp_review_list', 'get_erp_review_detail',
--   'save_drill', 'cancel_drill', 'delete_drill', 'start_drill', 'checkin_drill', 'remove_drill_peserta',
--   'finish_drill', 'close_drill_temuan', 'approve_drill', 'save_erp_review', 'delete_erp_review', 'approve_erp_review');
-- 3) 3 item HSE Program sudah OTOMATIS:
-- SELECT "KodeItem", "SumberRealisasi" FROM "hseProgramMasterItemTbl" WHERE "KodeItem" IN ('SAFETY_DRILL', 'MEDICAL_DRILL', 'ERP_REVIEW');
-- 4) Tulis tanpa QR harus ditolak ("Verifikasi identitas dulu"):
-- SELECT public.save_drill(NULL, NULL, NULL, '{}'::jsonb);
--
-- ROLLBACK (hapus modul, data ikut hilang; HSE Program perlu 062 dijalankan ulang + 3 item dikembalikan ke MANUAL):
-- DROP FUNCTION IF EXISTS public.get_drill_list(BIGINT, INT, TEXT, TEXT), public.get_drill_detail(BIGINT),
--   public.get_drill_temuan_list(BIGINT, TEXT), public.get_erp_review_list(BIGINT, INT), public.get_erp_review_detail(BIGINT),
--   public.save_drill(TEXT, TEXT, BIGINT, JSONB), public.cancel_drill(TEXT, TEXT, BIGINT, TEXT),
--   public.delete_drill(TEXT, TEXT, BIGINT), public.start_drill(TEXT, TEXT, BIGINT, TIMESTAMPTZ),
--   public.checkin_drill(BIGINT, TEXT, TEXT, TEXT), public.remove_drill_peserta(TEXT, TEXT, BIGINT, TEXT),
--   public.finish_drill(TEXT, TEXT, BIGINT, JSONB, JSONB, JSONB), public.close_drill_temuan(TEXT, TEXT, BIGINT, TEXT, BOOLEAN),
--   public.save_erp_review(TEXT, TEXT, BIGINT, JSONB), public.delete_erp_review(TEXT, TEXT, BIGINT),
--   public.approve_drill(TEXT, TEXT, BIGINT, BOOLEAN, TEXT), public.approve_erp_review(TEXT, TEXT, BIGINT, BOOLEAN, TEXT);
-- (jalankan 062 dulu supaya get_hse_program/MR frame tidak memanggil drill_realisasi_bulanan lagi, baru:)
-- DROP FUNCTION IF EXISTS public.drill_realisasi_bulanan(BIGINT, INT), public.erp_review_json("erpReviewTbl"),
--   public.drill_header_json("drillTbl"), public.drill_temuan_json("drillTemuanTbl");
-- DROP TABLE IF EXISTS "erpReviewTbl", "drillTemuanTbl", "drillTbl";
-- =====================================================================================
