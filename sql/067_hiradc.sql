-- =====================================================================================
-- 067 -- Modul HIRADC (Hazard Identification, Risk Assessment & Determining Control)
-- Jalankan di project Supabase HSSE-Fusion4 (BUKAN Fusion4 SmartGate). Run after 066.
--
-- Isi:
--   hiradcTbl      = 1 dokumen HIRADC per project/area/aktivitas (nomor, revisi, status, approval)
--   hiradcItemTbl  = baris register: aktivitas, bahaya, risiko, skor awal, pengendalian, skor sisa
-- Alur status:
--   Draft -> Menunggu Approval -> Disetujui            (approve: Author "Approve HIRADC")
--                              -> Dikembalikan -> (edit) -> Menunggu Approval
--   Disetujui -> "Buat Revisi" = salinan Draft Rev+1; begitu revisi disetujui,
--   dokumen lama otomatis jadi "Tidak Berlaku".
-- Akses (dicek di server lewat hsse_wajib_akses dari 065):
--   susun / edit / ajukan / revisi / hapus draft = PIC HSSE-HRC (atau HSSE-ALL)
--   setujui / kembalikan                         = Author "Approve HIRADC"
-- Matriks risiko 5x5 sama dengan JSA PTW (migrasi 040 / getRiskLevel di ptw-report.html):
--   skor 1-4 Rendah, 5-9 Sedang, 10-15 Tinggi, 16-25 Ekstrem.
-- Tabel tidak bisa dibaca/ditulis langsung pakai anon key; semua lewat RPC.
-- Aman dijalankan ulang.
-- =====================================================================================

-- -------------------------------------------------------------------------------------
-- 1. Tabel
-- -------------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS "hiradcTbl" (
    "Id"                 BIGSERIAL PRIMARY KEY,
    "NoDokumen"          TEXT NOT NULL,
    "Revisi"             INT  NOT NULL DEFAULT 0,
    "RevisiDariId"       BIGINT REFERENCES "hiradcTbl"("Id"),
    "ProjectId"          BIGINT NOT NULL REFERENCES "projectTbl"("Id"),
    "Judul"              TEXT NOT NULL,              -- area / aktivitas utama yang dinilai
    "LokasiArea"         TEXT,
    "Departemen"         TEXT,
    "TimPenyusun"        TEXT,
    "Status"             TEXT NOT NULL DEFAULT 'Draft'
                         CHECK ("Status" IN ('Draft', 'Menunggu Approval', 'Dikembalikan', 'Disetujui', 'Tidak Berlaku')),
    "DisusunOleh"        TEXT,
    "DisusunQrCodeId"    TEXT,
    "DiajukanOleh"       TEXT,
    "TanggalDiajukan"    TIMESTAMPTZ,
    "DisetujuiOleh"      TEXT,
    "DisetujuiQrCodeId"  TEXT,
    "TanggalDisetujui"   TIMESTAMPTZ,
    "CatatanApproval"    TEXT,
    "TanggalReviewBerikut" DATE,                     -- default 1 tahun setelah disetujui
    "DiubahOleh"         TEXT,
    "CreatedAt"          TIMESTAMPTZ NOT NULL DEFAULT now(),
    "UpdatedAt"          TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX IF NOT EXISTS ux_hiradc_no_revisi ON "hiradcTbl" ("NoDokumen", "Revisi");
CREATE INDEX IF NOT EXISTS idx_hiradc_project ON "hiradcTbl" ("ProjectId", "Status");

CREATE TABLE IF NOT EXISTS "hiradcItemTbl" (
    "Id"                   BIGSERIAL PRIMARY KEY,
    "HiradcId"             BIGINT NOT NULL REFERENCES "hiradcTbl"("Id") ON DELETE CASCADE,
    "Urutan"               INT NOT NULL DEFAULT 0,
    "Aktivitas"            TEXT NOT NULL,
    "Kondisi"              TEXT NOT NULL DEFAULT 'Rutin' CHECK ("Kondisi" IN ('Rutin', 'Non Rutin', 'Darurat')),
    "Kategori"             TEXT NOT NULL DEFAULT 'Keselamatan'
                           CHECK ("Kategori" IN ('Keselamatan', 'Kesehatan', 'Lingkungan', 'Security')),
    "Bahaya"               TEXT NOT NULL,
    "Risiko"               TEXT NOT NULL,            -- dampak / akibat kalau bahaya terjadi
    "LikelihoodAwal"       INT NOT NULL CHECK ("LikelihoodAwal" BETWEEN 1 AND 5),
    "SeverityAwal"         INT NOT NULL CHECK ("SeverityAwal" BETWEEN 1 AND 5),
    "PengendalianExisting" TEXT,
    "Hierarki"             TEXT[] NOT NULL DEFAULT '{}', -- Eliminasi/Substitusi/Rekayasa/Administrasi/APD
    "PengendalianTambahan" TEXT,
    "LikelihoodSisa"       INT NOT NULL CHECK ("LikelihoodSisa" BETWEEN 1 AND 5),
    "SeveritySisa"         INT NOT NULL CHECK ("SeveritySisa" BETWEEN 1 AND 5),
    "PicTindakLanjut"      TEXT,
    "TargetSelesai"        DATE,
    "Peraturan"            TEXT,
    "SkorAwal"             INT GENERATED ALWAYS AS ("LikelihoodAwal" * "SeverityAwal") STORED,
    "SkorSisa"             INT GENERATED ALWAYS AS ("LikelihoodSisa" * "SeveritySisa") STORED
);
CREATE INDEX IF NOT EXISTS idx_hiradc_item_header ON "hiradcItemTbl" ("HiradcId", "Urutan");

ALTER TABLE "hiradcTbl" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "hiradcItemTbl" ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "hiradcTbl_no_direct" ON "hiradcTbl";
CREATE POLICY "hiradcTbl_no_direct" ON "hiradcTbl" FOR ALL TO anon, authenticated USING (false) WITH CHECK (false);
DROP POLICY IF EXISTS "hiradcItemTbl_no_direct" ON "hiradcItemTbl";
CREATE POLICY "hiradcItemTbl_no_direct" ON "hiradcItemTbl" FOR ALL TO anon, authenticated USING (false) WITH CHECK (false);

-- -------------------------------------------------------------------------------------
-- 2. Helper
-- -------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.hiradc_tingkat(p_skor INT)
RETURNS TEXT LANGUAGE sql IMMUTABLE AS $$
    SELECT CASE WHEN p_skor <= 4 THEN 'Rendah' WHEN p_skor <= 9 THEN 'Sedang'
                WHEN p_skor <= 15 THEN 'Tinggi' ELSE 'Ekstrem' END;
$$;

CREATE OR REPLACE FUNCTION public.hiradc_item_json(i "hiradcItemTbl")
RETURNS JSONB LANGUAGE sql STABLE AS $$
    SELECT jsonb_build_object(
        'id', i."Id", 'urutan', i."Urutan", 'aktivitas', i."Aktivitas", 'kondisi', i."Kondisi",
        'kategori', i."Kategori", 'bahaya', i."Bahaya", 'risiko', i."Risiko",
        'likelihoodAwal', i."LikelihoodAwal", 'severityAwal', i."SeverityAwal",
        'skorAwal', i."SkorAwal", 'tingkatAwal', public.hiradc_tingkat(i."SkorAwal"),
        'pengendalianExisting', i."PengendalianExisting", 'hierarki', to_jsonb(i."Hierarki"),
        'pengendalianTambahan', i."PengendalianTambahan",
        'likelihoodSisa', i."LikelihoodSisa", 'severitySisa', i."SeveritySisa",
        'skorSisa', i."SkorSisa", 'tingkatSisa', public.hiradc_tingkat(i."SkorSisa"),
        'picTindakLanjut', i."PicTindakLanjut", 'targetSelesai', i."TargetSelesai",
        'peraturan', i."Peraturan");
$$;

CREATE OR REPLACE FUNCTION public.hiradc_header_json(h "hiradcTbl")
RETURNS JSONB LANGUAGE sql STABLE SET search_path = public AS $$
    SELECT jsonb_build_object(
        'id', h."Id", 'noDokumen', h."NoDokumen", 'revisi', h."Revisi", 'revisiDariId', h."RevisiDariId",
        'projectId', h."ProjectId", 'namaProject', p."NamaProject", 'kodeOperational', p."KodeOperational",
        'noKontrak', p."NoKontrak", 'client', p."Client",
        'judul', h."Judul", 'lokasiArea', h."LokasiArea", 'departemen', h."Departemen",
        'timPenyusun', h."TimPenyusun", 'status', h."Status",
        'disusunOleh', h."DisusunOleh", 'diajukanOleh', h."DiajukanOleh", 'tanggalDiajukan', h."TanggalDiajukan",
        'disetujuiOleh', h."DisetujuiOleh", 'tanggalDisetujui', h."TanggalDisetujui",
        'catatanApproval', h."CatatanApproval", 'tanggalReviewBerikut', h."TanggalReviewBerikut",
        'diubahOleh', h."DiubahOleh", 'createdAt', h."CreatedAt", 'updatedAt', h."UpdatedAt",
        'adaRevisiTerbuka', EXISTS (SELECT 1 FROM "hiradcTbl" r WHERE r."RevisiDariId" = h."Id"
                                    AND r."Status" IN ('Draft', 'Menunggu Approval', 'Dikembalikan')))
    FROM "projectTbl" p WHERE p."Id" = h."ProjectId";
$$;

-- -------------------------------------------------------------------------------------
-- 3. Baca (terbuka, sama kayak list modul lain)
-- -------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_hiradc_list(p_project_id BIGINT DEFAULT NULL, p_status TEXT DEFAULT NULL,
                                                  p_search TEXT DEFAULT NULL)
RETURNS JSONB LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
    SELECT COALESCE(jsonb_agg(public.hiradc_header_json(h) || jsonb_build_object(
        'jumlahItem', s.n,
        'awal',  jsonb_build_object('Rendah', s.a1, 'Sedang', s.a2, 'Tinggi', s.a3, 'Ekstrem', s.a4),
        'sisa',  jsonb_build_object('Rendah', s.r1, 'Sedang', s.r2, 'Tinggi', s.r3, 'Ekstrem', s.r4))
        ORDER BY h."UpdatedAt" DESC), '[]'::JSONB)
    FROM "hiradcTbl" h
    CROSS JOIN LATERAL (
        SELECT count(*) n,
               count(*) FILTER (WHERE i."SkorAwal" <= 4) a1,
               count(*) FILTER (WHERE i."SkorAwal" BETWEEN 5 AND 9) a2,
               count(*) FILTER (WHERE i."SkorAwal" BETWEEN 10 AND 15) a3,
               count(*) FILTER (WHERE i."SkorAwal" >= 16) a4,
               count(*) FILTER (WHERE i."SkorSisa" <= 4) r1,
               count(*) FILTER (WHERE i."SkorSisa" BETWEEN 5 AND 9) r2,
               count(*) FILTER (WHERE i."SkorSisa" BETWEEN 10 AND 15) r3,
               count(*) FILTER (WHERE i."SkorSisa" >= 16) r4
        FROM "hiradcItemTbl" i WHERE i."HiradcId" = h."Id") s
    WHERE (p_project_id IS NULL OR h."ProjectId" = p_project_id)
      AND (COALESCE(p_status, '') = '' OR h."Status" = p_status)
      AND (COALESCE(trim(p_search), '') = ''
           OR h."NoDokumen" ILIKE '%' || trim(p_search) || '%'
           OR h."Judul" ILIKE '%' || trim(p_search) || '%'
           OR h."LokasiArea" ILIKE '%' || trim(p_search) || '%'
           OR EXISTS (SELECT 1 FROM "hiradcItemTbl" i WHERE i."HiradcId" = h."Id"
                      AND (i."Aktivitas" ILIKE '%' || trim(p_search) || '%' OR i."Bahaya" ILIKE '%' || trim(p_search) || '%')));
$$;

CREATE OR REPLACE FUNCTION public.get_hiradc_detail(p_id BIGINT)
RETURNS JSONB LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
    SELECT public.hiradc_header_json(h) || jsonb_build_object('items',
        COALESCE((SELECT jsonb_agg(public.hiradc_item_json(i) ORDER BY i."Urutan", i."Id")
                  FROM "hiradcItemTbl" i WHERE i."HiradcId" = h."Id"), '[]'::JSONB))
    FROM "hiradcTbl" h WHERE h."Id" = p_id;
$$;

-- Buat tombol "Ambil dari HIRADC" di JSA PTW: semua baris HIRADC yang Disetujui di project itu.
CREATE OR REPLACE FUNCTION public.get_hiradc_items_for_project(p_project_id BIGINT)
RETURNS JSONB LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
    SELECT COALESCE(jsonb_agg(public.hiradc_item_json(i) || jsonb_build_object(
               'hiradcId', h."Id", 'noDokumen', h."NoDokumen", 'revisi', h."Revisi", 'judul', h."Judul")
           ORDER BY h."NoDokumen", i."Urutan", i."Id"), '[]'::JSONB)
    FROM "hiradcTbl" h JOIN "hiradcItemTbl" i ON i."HiradcId" = h."Id"
    WHERE h."ProjectId" = p_project_id AND h."Status" = 'Disetujui';
$$;

-- -------------------------------------------------------------------------------------
-- 4. Tulis (cek PIC/Author ke SmartGate dulu)
-- -------------------------------------------------------------------------------------
-- p_header: {projectId, judul, lokasiArea, departemen, timPenyusun}
-- p_items : [{aktivitas, kondisi, kategori, bahaya, risiko, likelihoodAwal, severityAwal,
--             pengendalianExisting, hierarki:[..], pengendalianTambahan, likelihoodSisa,
--             severitySisa, picTindakLanjut, targetSelesai, peraturan}]
-- p_id NULL = dokumen baru. Item selalu diganti utuh.
CREATE OR REPLACE FUNCTION public.save_hiradc(p_aktor_nama TEXT, p_aktor_qr TEXT, p_id BIGINT,
                                              p_header JSONB, p_items JSONB)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
    v_id      BIGINT := p_id;
    v_status  TEXT;
    v_project BIGINT := NULLIF(p_header->>'projectId', '')::BIGINT;
    v_kode    TEXT;
    v_no      TEXT;
    v_seq     INT;
    v_item    JSONB;
    v_urut    INT := 0;
    v_nama    TEXT := COALESCE(NULLIF(trim(p_aktor_nama), ''), upper(trim(p_aktor_qr)));
BEGIN
    PERFORM public.hsse_wajib_akses(p_aktor_nama, p_aktor_qr, 'HSSE-HRC');

    IF COALESCE(trim(p_header->>'judul'), '') = '' THEN
        RAISE EXCEPTION 'Judul / area HIRADC wajib diisi.';
    END IF;
    IF jsonb_typeof(p_items) IS DISTINCT FROM 'array' OR jsonb_array_length(p_items) = 0 THEN
        RAISE EXCEPTION 'Isi minimal 1 baris bahaya.';
    END IF;

    IF v_id IS NULL THEN
        IF v_project IS NULL OR NOT EXISTS (SELECT 1 FROM "projectTbl" WHERE "Id" = v_project) THEN
            RAISE EXCEPTION 'Pilih project dulu.';
        END IF;
        SELECT COALESCE(NULLIF("KodeOperational", ''), 'P' || "Id") INTO v_kode FROM "projectTbl" WHERE "Id" = v_project;
        PERFORM pg_advisory_xact_lock(hashtext('hiradc_no_' || v_kode));
        SELECT COALESCE(max(substring("NoDokumen" FROM '(\d+)$')::INT), 0) + 1 INTO v_seq
        FROM "hiradcTbl" WHERE "NoDokumen" LIKE 'HIRADC/' || v_kode || '/%';
        v_no := 'HIRADC/' || v_kode || '/' || to_char(now() AT TIME ZONE 'Asia/Jakarta', 'YYYY') || '/' || lpad(v_seq::TEXT, 3, '0');

        INSERT INTO "hiradcTbl" ("NoDokumen", "ProjectId", "Judul", "LokasiArea", "Departemen", "TimPenyusun",
                                 "DisusunOleh", "DisusunQrCodeId", "DiubahOleh")
        VALUES (v_no, v_project, trim(p_header->>'judul'), NULLIF(trim(p_header->>'lokasiArea'), ''),
                NULLIF(trim(p_header->>'departemen'), ''), NULLIF(trim(p_header->>'timPenyusun'), ''),
                v_nama, upper(trim(p_aktor_qr)), v_nama)
        RETURNING "Id" INTO v_id;
    ELSE
        SELECT "Status" INTO v_status FROM "hiradcTbl" WHERE "Id" = v_id FOR UPDATE;
        IF v_status IS NULL THEN
            RAISE EXCEPTION 'HIRADC % tidak ditemukan.', v_id;
        END IF;
        IF v_status NOT IN ('Draft', 'Dikembalikan') THEN
            RAISE EXCEPTION 'HIRADC berstatus "%" tidak bisa diedit. Buat revisi kalau perlu perubahan.', v_status;
        END IF;
        -- project tidak bisa dipindah setelah nomor dokumen terbentuk
        UPDATE "hiradcTbl" SET
            "Judul" = trim(p_header->>'judul'),
            "LokasiArea" = NULLIF(trim(p_header->>'lokasiArea'), ''),
            "Departemen" = NULLIF(trim(p_header->>'departemen'), ''),
            "TimPenyusun" = NULLIF(trim(p_header->>'timPenyusun'), ''),
            "DiubahOleh" = v_nama, "UpdatedAt" = now()
        WHERE "Id" = v_id;
        DELETE FROM "hiradcItemTbl" WHERE "HiradcId" = v_id;
    END IF;

    FOR v_item IN SELECT value FROM jsonb_array_elements(p_items) LOOP
        v_urut := v_urut + 1;
        IF COALESCE(trim(v_item->>'aktivitas'), '') = '' OR COALESCE(trim(v_item->>'bahaya'), '') = ''
           OR COALESCE(trim(v_item->>'risiko'), '') = '' THEN
            RAISE EXCEPTION 'Baris %: aktivitas, bahaya, dan risiko wajib diisi.', v_urut;
        END IF;
        IF (v_item->>'likelihoodSisa')::INT * (v_item->>'severitySisa')::INT >= 10
           AND COALESCE(trim(v_item->>'pengendalianTambahan'), '') = '' THEN
            RAISE EXCEPTION 'Baris %: risiko sisa masih Tinggi/Ekstrem, isi pengendalian tambahan.', v_urut;
        END IF;
        INSERT INTO "hiradcItemTbl" ("HiradcId", "Urutan", "Aktivitas", "Kondisi", "Kategori", "Bahaya", "Risiko",
            "LikelihoodAwal", "SeverityAwal", "PengendalianExisting", "Hierarki", "PengendalianTambahan",
            "LikelihoodSisa", "SeveritySisa", "PicTindakLanjut", "TargetSelesai", "Peraturan")
        VALUES (v_id, v_urut, trim(v_item->>'aktivitas'), COALESCE(NULLIF(v_item->>'kondisi', ''), 'Rutin'),
            COALESCE(NULLIF(v_item->>'kategori', ''), 'Keselamatan'), trim(v_item->>'bahaya'), trim(v_item->>'risiko'),
            (v_item->>'likelihoodAwal')::INT, (v_item->>'severityAwal')::INT,
            NULLIF(trim(v_item->>'pengendalianExisting'), ''),
            COALESCE(ARRAY(SELECT jsonb_array_elements_text(COALESCE(v_item->'hierarki', '[]'::JSONB))), '{}'),
            NULLIF(trim(v_item->>'pengendalianTambahan'), ''),
            (v_item->>'likelihoodSisa')::INT, (v_item->>'severitySisa')::INT,
            NULLIF(trim(v_item->>'picTindakLanjut'), ''), NULLIF(v_item->>'targetSelesai', '')::DATE,
            NULLIF(trim(v_item->>'peraturan'), ''));
    END LOOP;

    RETURN public.get_hiradc_detail(v_id);
END;
$$;

CREATE OR REPLACE FUNCTION public.submit_hiradc(p_aktor_nama TEXT, p_aktor_qr TEXT, p_id BIGINT)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
    v_status TEXT;
BEGIN
    PERFORM public.hsse_wajib_akses(p_aktor_nama, p_aktor_qr, 'HSSE-HRC');
    SELECT "Status" INTO v_status FROM "hiradcTbl" WHERE "Id" = p_id FOR UPDATE;
    IF v_status IS NULL OR v_status NOT IN ('Draft', 'Dikembalikan') THEN
        RAISE EXCEPTION 'Cuma HIRADC Draft/Dikembalikan yang bisa diajukan (status sekarang: %).', COALESCE(v_status, '-');
    END IF;
    IF NOT EXISTS (SELECT 1 FROM "hiradcItemTbl" WHERE "HiradcId" = p_id) THEN
        RAISE EXCEPTION 'Belum ada baris bahaya.';
    END IF;
    UPDATE "hiradcTbl" SET "Status" = 'Menunggu Approval',
        "DiajukanOleh" = COALESCE(NULLIF(trim(p_aktor_nama), ''), upper(trim(p_aktor_qr))),
        "TanggalDiajukan" = now(), "DiubahOleh" = COALESCE(NULLIF(trim(p_aktor_nama), ''), upper(trim(p_aktor_qr))),
        "UpdatedAt" = now()
    WHERE "Id" = p_id;
    RETURN public.get_hiradc_detail(p_id);
END;
$$;

-- p_setuju TRUE = Disetujui, FALSE = Dikembalikan (catatan wajib)
CREATE OR REPLACE FUNCTION public.approve_hiradc(p_aktor_nama TEXT, p_aktor_qr TEXT, p_id BIGINT,
                                                 p_setuju BOOLEAN, p_catatan TEXT DEFAULT NULL,
                                                 p_tanggal_review_berikut DATE DEFAULT NULL)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
    v_status TEXT;
    v_dari   BIGINT;
    v_nama   TEXT := COALESCE(NULLIF(trim(p_aktor_nama), ''), upper(trim(p_aktor_qr)));
BEGIN
    PERFORM public.hsse_wajib_akses(p_aktor_nama, p_aktor_qr, 'Approve HIRADC');
    SELECT "Status", "RevisiDariId" INTO v_status, v_dari FROM "hiradcTbl" WHERE "Id" = p_id FOR UPDATE;
    IF v_status IS DISTINCT FROM 'Menunggu Approval' THEN
        RAISE EXCEPTION 'HIRADC ini tidak sedang menunggu approval (status: %).', COALESCE(v_status, '-');
    END IF;

    IF p_setuju THEN
        UPDATE "hiradcTbl" SET "Status" = 'Disetujui', "DisetujuiOleh" = v_nama,
            "DisetujuiQrCodeId" = upper(trim(p_aktor_qr)), "TanggalDisetujui" = now(),
            "CatatanApproval" = NULLIF(trim(p_catatan), ''),
            "TanggalReviewBerikut" = COALESCE(p_tanggal_review_berikut,
                                              ((now() AT TIME ZONE 'Asia/Jakarta')::DATE + INTERVAL '1 year')::DATE),
            "DiubahOleh" = v_nama, "UpdatedAt" = now()
        WHERE "Id" = p_id;
        IF v_dari IS NOT NULL THEN
            UPDATE "hiradcTbl" SET "Status" = 'Tidak Berlaku', "DiubahOleh" = v_nama, "UpdatedAt" = now()
            WHERE "Id" = v_dari AND "Status" = 'Disetujui';
        END IF;
    ELSE
        IF COALESCE(trim(p_catatan), '') = '' THEN
            RAISE EXCEPTION 'Tulis alasan kenapa dikembalikan.';
        END IF;
        UPDATE "hiradcTbl" SET "Status" = 'Dikembalikan', "CatatanApproval" = trim(p_catatan),
            "DiubahOleh" = v_nama, "UpdatedAt" = now()
        WHERE "Id" = p_id;
    END IF;
    RETURN public.get_hiradc_detail(p_id);
END;
$$;

-- Salin HIRADC Disetujui jadi Draft revisi berikutnya. Kalau sudah ada revisi terbuka, balikin itu.
CREATE OR REPLACE FUNCTION public.revise_hiradc(p_aktor_nama TEXT, p_aktor_qr TEXT, p_id BIGINT)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
    v_h     "hiradcTbl";
    v_baru  BIGINT;
    v_nama  TEXT := COALESCE(NULLIF(trim(p_aktor_nama), ''), upper(trim(p_aktor_qr)));
BEGIN
    PERFORM public.hsse_wajib_akses(p_aktor_nama, p_aktor_qr, 'HSSE-HRC');
    SELECT * INTO v_h FROM "hiradcTbl" WHERE "Id" = p_id FOR UPDATE;
    IF v_h."Status" IS DISTINCT FROM 'Disetujui' THEN
        RAISE EXCEPTION 'Revisi cuma bisa dibuat dari HIRADC yang Disetujui.';
    END IF;
    SELECT "Id" INTO v_baru FROM "hiradcTbl"
    WHERE "RevisiDariId" = p_id AND "Status" IN ('Draft', 'Menunggu Approval', 'Dikembalikan') LIMIT 1;
    IF v_baru IS NOT NULL THEN
        RETURN public.get_hiradc_detail(v_baru);
    END IF;

    INSERT INTO "hiradcTbl" ("NoDokumen", "Revisi", "RevisiDariId", "ProjectId", "Judul", "LokasiArea",
                             "Departemen", "TimPenyusun", "DisusunOleh", "DisusunQrCodeId", "DiubahOleh")
    VALUES (v_h."NoDokumen", (SELECT max("Revisi") + 1 FROM "hiradcTbl" WHERE "NoDokumen" = v_h."NoDokumen"),
            p_id, v_h."ProjectId", v_h."Judul", v_h."LokasiArea", v_h."Departemen", v_h."TimPenyusun",
            v_nama, upper(trim(p_aktor_qr)), v_nama)
    RETURNING "Id" INTO v_baru;

    INSERT INTO "hiradcItemTbl" ("HiradcId", "Urutan", "Aktivitas", "Kondisi", "Kategori", "Bahaya", "Risiko",
        "LikelihoodAwal", "SeverityAwal", "PengendalianExisting", "Hierarki", "PengendalianTambahan",
        "LikelihoodSisa", "SeveritySisa", "PicTindakLanjut", "TargetSelesai", "Peraturan")
    SELECT v_baru, "Urutan", "Aktivitas", "Kondisi", "Kategori", "Bahaya", "Risiko",
        "LikelihoodAwal", "SeverityAwal", "PengendalianExisting", "Hierarki", "PengendalianTambahan",
        "LikelihoodSisa", "SeveritySisa", "PicTindakLanjut", "TargetSelesai", "Peraturan"
    FROM "hiradcItemTbl" WHERE "HiradcId" = p_id;

    RETURN public.get_hiradc_detail(v_baru);
END;
$$;

CREATE OR REPLACE FUNCTION public.delete_hiradc(p_aktor_nama TEXT, p_aktor_qr TEXT, p_id BIGINT)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
    v_status TEXT;
BEGIN
    PERFORM public.hsse_wajib_akses(p_aktor_nama, p_aktor_qr, 'HSSE-HRC');
    SELECT "Status" INTO v_status FROM "hiradcTbl" WHERE "Id" = p_id FOR UPDATE;
    IF v_status IS NULL OR v_status NOT IN ('Draft', 'Dikembalikan') THEN
        RAISE EXCEPTION 'Cuma HIRADC Draft/Dikembalikan yang bisa dihapus (status: %).', COALESCE(v_status, '-');
    END IF;
    DELETE FROM "hiradcTbl" WHERE "Id" = p_id;
END;
$$;

-- -------------------------------------------------------------------------------------
-- 5. Hak eksekusi: helper internal tertutup, RPC halaman terbuka (cek akses ada di dalam)
-- -------------------------------------------------------------------------------------
REVOKE EXECUTE ON FUNCTION public.hiradc_item_json("hiradcItemTbl") FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.hiradc_header_json("hiradcTbl") FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.get_hiradc_list(BIGINT, TEXT, TEXT) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.get_hiradc_detail(BIGINT) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.get_hiradc_items_for_project(BIGINT) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.save_hiradc(TEXT, TEXT, BIGINT, JSONB, JSONB) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.submit_hiradc(TEXT, TEXT, BIGINT) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.approve_hiradc(TEXT, TEXT, BIGINT, BOOLEAN, TEXT, DATE) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.revise_hiradc(TEXT, TEXT, BIGINT) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.delete_hiradc(TEXT, TEXT, BIGINT) TO anon, authenticated;

NOTIFY pgrst, 'reload schema';

-- =====================================================================================
-- CEK SETELAH JALAN (harus: 2 tabel rls_on = true, 8 RPC)
-- SELECT relname, relrowsecurity AS rls_on FROM pg_class WHERE relname IN ('hiradcTbl', 'hiradcItemTbl');
-- SELECT proname FROM pg_proc WHERE pronamespace = 'public'::regnamespace
--   AND proname IN ('get_hiradc_list', 'get_hiradc_detail', 'get_hiradc_items_for_project', 'save_hiradc',
--                   'submit_hiradc', 'approve_hiradc', 'revise_hiradc', 'delete_hiradc');
-- SELECT public.hiradc_tingkat(4), public.hiradc_tingkat(9), public.hiradc_tingkat(15), public.hiradc_tingkat(16);
--   -> Rendah, Sedang, Tinggi, Ekstrem
--
-- ROLLBACK (hapus modul, data ikut hilang):
-- DROP FUNCTION IF EXISTS public.get_hiradc_list(BIGINT, TEXT, TEXT), public.get_hiradc_detail(BIGINT),
--   public.get_hiradc_items_for_project(BIGINT), public.save_hiradc(TEXT, TEXT, BIGINT, JSONB, JSONB),
--   public.submit_hiradc(TEXT, TEXT, BIGINT), public.approve_hiradc(TEXT, TEXT, BIGINT, BOOLEAN, TEXT, DATE),
--   public.revise_hiradc(TEXT, TEXT, BIGINT), public.delete_hiradc(TEXT, TEXT, BIGINT),
--   public.hiradc_item_json("hiradcItemTbl"), public.hiradc_header_json("hiradcTbl"), public.hiradc_tingkat(INT);
-- DROP TABLE IF EXISTS "hiradcItemTbl", "hiradcTbl";
-- =====================================================================================
