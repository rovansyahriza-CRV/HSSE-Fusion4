-- =====================================================================================
-- 068 -- HIRADC <-> contoh generik JSA PTW (ptwJsaTemplateTbl): tautan asal + usulan.
-- Jalankan di project Supabase HSSE-Fusion4 (BUKAN Fusion4 SmartGate). Run after 067.
--
-- 1. Baris HIRADC nyimpen asal generiknya (jenis pekerjaan + Id baris template) kalau
--    diisi lewat "Isi dari contoh generik" di form HIRADC.
-- 2. Dari HIRADC yang sudah Disetujui, baris bisa diusulkan jadi contoh generik:
--      Tambah = baris baru di template jenis pekerjaan itu
--      Ganti  = memperbarui baris template asalnya
--    Usulan TIDAK langsung mengubah template. Harus disetujui manual.
-- Akses (dicek di server, pola 065):
--    mengusulkan                = PIC HSSE-HRC (atau HSSE-ALL)
--    menyetujui / menolak usulan = PIC HSSE-PTW (atau HSSE-ALL, atau Author lama "Permit & JSA")
-- get_ptw_jsa_template sekarang ikut ngirim "id" (form PTW gak terpengaruh).
-- Catatan: save_hiradc, revise_hiradc, hiradc_item_json di-replace (versi 067 + kolom asal).
-- Aman dijalankan ulang.
-- =====================================================================================

-- -------------------------------------------------------------------------------------
-- 1. Kolom & tabel
-- -------------------------------------------------------------------------------------
ALTER TABLE "hiradcItemTbl" ADD COLUMN IF NOT EXISTS "AsalJenisPekerjaan" TEXT;
ALTER TABLE "hiradcItemTbl" ADD COLUMN IF NOT EXISTS "AsalTemplateId" BIGINT
    REFERENCES "ptwJsaTemplateTbl"("Id") ON DELETE SET NULL;

CREATE TABLE IF NOT EXISTS "ptwJsaTemplateUsulanTbl" (
    "Id"                 BIGSERIAL PRIMARY KEY,
    "HiradcId"           BIGINT REFERENCES "hiradcTbl"("Id") ON DELETE SET NULL,
    "HiradcItemId"       BIGINT REFERENCES "hiradcItemTbl"("Id") ON DELETE SET NULL,
    "NoDokumenHiradc"    TEXT,
    "Mode"               TEXT NOT NULL CHECK ("Mode" IN ('Tambah', 'Ganti')),
    "TemplateTargetId"   BIGINT REFERENCES "ptwJsaTemplateTbl"("Id") ON DELETE SET NULL,
    "JenisPekerjaan"     TEXT NOT NULL,
    "Langkah"            TEXT NOT NULL,
    "Bahaya"             TEXT NOT NULL,
    "Pengendalian"       TEXT NOT NULL,
    "LikelihoodAwal"     INT NOT NULL CHECK ("LikelihoodAwal" BETWEEN 1 AND 5),
    "SeverityAwal"       INT NOT NULL CHECK ("SeverityAwal" BETWEEN 1 AND 5),
    "LikelihoodSisa"     INT NOT NULL CHECK ("LikelihoodSisa" BETWEEN 1 AND 5),
    "SeveritySisa"       INT NOT NULL CHECK ("SeveritySisa" BETWEEN 1 AND 5),
    "Alasan"             TEXT,
    "Status"             TEXT NOT NULL DEFAULT 'Menunggu' CHECK ("Status" IN ('Menunggu', 'Disetujui', 'Ditolak')),
    "DiusulkanOleh"      TEXT,
    "DiusulkanQrCodeId"  TEXT,
    "TanggalDiusulkan"   TIMESTAMPTZ NOT NULL DEFAULT now(),
    "DiputuskanOleh"     TEXT,
    "DiputuskanQrCodeId" TEXT,
    "TanggalDiputuskan"  TIMESTAMPTZ,
    "CatatanKeputusan"   TEXT,
    "TemplateHasilId"    BIGINT REFERENCES "ptwJsaTemplateTbl"("Id") ON DELETE SET NULL
);
CREATE INDEX IF NOT EXISTS idx_jsa_usulan_status ON "ptwJsaTemplateUsulanTbl" ("Status", "TanggalDiusulkan" DESC);
CREATE INDEX IF NOT EXISTS idx_jsa_usulan_item ON "ptwJsaTemplateUsulanTbl" ("HiradcItemId");
ALTER TABLE "ptwJsaTemplateUsulanTbl" ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "ptwJsaTemplateUsulanTbl_no_direct" ON "ptwJsaTemplateUsulanTbl";
CREATE POLICY "ptwJsaTemplateUsulanTbl_no_direct" ON "ptwJsaTemplateUsulanTbl"
    FOR ALL TO anon, authenticated USING (false) WITH CHECK (false);

-- -------------------------------------------------------------------------------------
-- 2. Template generik ikut ngirim id (buat nyimpen asal)
-- -------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_ptw_jsa_template(p_jenis_pekerjaan TEXT)
RETURNS JSONB LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
    SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'id', "Id", 'langkah', "Langkah", 'bahaya', "Bahaya", 'pengendalian', "Pengendalian",
        'likelihoodAwal', "LikelihoodAwal", 'severityAwal', "SeverityAwal",
        'likelihoodSisa', "LikelihoodSisa", 'severitySisa', "SeveritySisa"
    ) ORDER BY "Urutan"), '[]'::JSONB)
    FROM "ptwJsaTemplateTbl"
    WHERE "JenisPekerjaan" = p_jenis_pekerjaan AND "Status" = 'Aktif';
$$;

-- -------------------------------------------------------------------------------------
-- 3. Fungsi HIRADC versi 067 + kolom asal
-- -------------------------------------------------------------------------------------
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
        'peraturan', i."Peraturan",
        'asalJenisPekerjaan', i."AsalJenisPekerjaan", 'asalTemplateId', i."AsalTemplateId",
        'usulan', (SELECT jsonb_build_object('id', u."Id", 'status', u."Status", 'jenisPekerjaan', u."JenisPekerjaan",
                                             'catatan', u."CatatanKeputusan")
                   FROM "ptwJsaTemplateUsulanTbl" u WHERE u."HiradcItemId" = i."Id" ORDER BY u."Id" DESC LIMIT 1));
$$;

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
            "LikelihoodSisa", "SeveritySisa", "PicTindakLanjut", "TargetSelesai", "Peraturan",
            "AsalJenisPekerjaan", "AsalTemplateId")
        VALUES (v_id, v_urut, trim(v_item->>'aktivitas'), COALESCE(NULLIF(v_item->>'kondisi', ''), 'Rutin'),
            COALESCE(NULLIF(v_item->>'kategori', ''), 'Keselamatan'), trim(v_item->>'bahaya'), trim(v_item->>'risiko'),
            (v_item->>'likelihoodAwal')::INT, (v_item->>'severityAwal')::INT,
            NULLIF(trim(v_item->>'pengendalianExisting'), ''),
            COALESCE(ARRAY(SELECT jsonb_array_elements_text(COALESCE(v_item->'hierarki', '[]'::JSONB))), '{}'),
            NULLIF(trim(v_item->>'pengendalianTambahan'), ''),
            (v_item->>'likelihoodSisa')::INT, (v_item->>'severitySisa')::INT,
            NULLIF(trim(v_item->>'picTindakLanjut'), ''), NULLIF(v_item->>'targetSelesai', '')::DATE,
            NULLIF(trim(v_item->>'peraturan'), ''),
            NULLIF(trim(v_item->>'asalJenisPekerjaan'), ''),
            (SELECT t."Id" FROM "ptwJsaTemplateTbl" t WHERE t."Id" = NULLIF(v_item->>'asalTemplateId', '')::BIGINT));
    END LOOP;

    RETURN public.get_hiradc_detail(v_id);
END;
$$;

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
        "LikelihoodSisa", "SeveritySisa", "PicTindakLanjut", "TargetSelesai", "Peraturan",
        "AsalJenisPekerjaan", "AsalTemplateId")
    SELECT v_baru, "Urutan", "Aktivitas", "Kondisi", "Kategori", "Bahaya", "Risiko",
        "LikelihoodAwal", "SeverityAwal", "PengendalianExisting", "Hierarki", "PengendalianTambahan",
        "LikelihoodSisa", "SeveritySisa", "PicTindakLanjut", "TargetSelesai", "Peraturan",
        "AsalJenisPekerjaan", "AsalTemplateId"
    FROM "hiradcItemTbl" WHERE "HiradcId" = p_id;

    RETURN public.get_hiradc_detail(v_baru);
END;
$$;

-- -------------------------------------------------------------------------------------
-- 4. Usulan jadi contoh generik
-- -------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.usulan_jsa_template_json(u "ptwJsaTemplateUsulanTbl")
RETURNS JSONB LANGUAGE sql STABLE SET search_path = public AS $$
    SELECT jsonb_build_object(
        'id', u."Id", 'hiradcId', u."HiradcId", 'hiradcItemId', u."HiradcItemId", 'noDokumenHiradc', u."NoDokumenHiradc",
        'mode', u."Mode", 'templateTargetId', u."TemplateTargetId", 'jenisPekerjaan', u."JenisPekerjaan",
        'langkah', u."Langkah", 'bahaya', u."Bahaya", 'pengendalian', u."Pengendalian",
        'likelihoodAwal', u."LikelihoodAwal", 'severityAwal', u."SeverityAwal",
        'likelihoodSisa', u."LikelihoodSisa", 'severitySisa', u."SeveritySisa",
        'alasan', u."Alasan", 'status', u."Status",
        'diusulkanOleh', u."DiusulkanOleh", 'tanggalDiusulkan', u."TanggalDiusulkan",
        'diputuskanOleh', u."DiputuskanOleh", 'tanggalDiputuskan', u."TanggalDiputuskan",
        'catatanKeputusan', u."CatatanKeputusan", 'templateHasilId', u."TemplateHasilId",
        'target', (SELECT jsonb_build_object('langkah', t."Langkah", 'bahaya', t."Bahaya", 'pengendalian', t."Pengendalian",
                       'likelihoodAwal', t."LikelihoodAwal", 'severityAwal', t."SeverityAwal",
                       'likelihoodSisa', t."LikelihoodSisa", 'severitySisa', t."SeveritySisa", 'status', t."Status")
                   FROM "ptwJsaTemplateTbl" t WHERE t."Id" = u."TemplateTargetId"));
$$;

-- p_usulan: {jenisPekerjaan, mode ('Tambah'|'Ganti'), langkah, bahaya, pengendalian,
--            likelihoodAwal, severityAwal, likelihoodSisa, severitySisa, alasan}
CREATE OR REPLACE FUNCTION public.propose_jsa_template(p_aktor_nama TEXT, p_aktor_qr TEXT,
                                                       p_hiradc_item_id BIGINT, p_usulan JSONB)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
    v_item   "hiradcItemTbl";
    v_h      "hiradcTbl";
    v_mode   TEXT := COALESCE(NULLIF(p_usulan->>'mode', ''), 'Tambah');
    v_jenis  TEXT := trim(COALESCE(p_usulan->>'jenisPekerjaan', ''));
    v_target BIGINT;
    v_id     BIGINT;
BEGIN
    PERFORM public.hsse_wajib_akses(p_aktor_nama, p_aktor_qr, 'HSSE-HRC');
    SELECT * INTO v_item FROM "hiradcItemTbl" WHERE "Id" = p_hiradc_item_id;
    IF v_item."Id" IS NULL THEN
        RAISE EXCEPTION 'Baris HIRADC tidak ditemukan.';
    END IF;
    SELECT * INTO v_h FROM "hiradcTbl" WHERE "Id" = v_item."HiradcId";
    IF v_h."Status" IS DISTINCT FROM 'Disetujui' THEN
        RAISE EXCEPTION 'Cuma baris dari HIRADC yang sudah Disetujui yang bisa diusulkan jadi contoh generik.';
    END IF;
    IF v_jenis = '' OR NOT EXISTS (SELECT 1 FROM "ptwJsaTemplateTbl" WHERE "JenisPekerjaan" = v_jenis) THEN
        RAISE EXCEPTION 'Jenis pekerjaan "%" tidak ada di contoh generik PTW.', v_jenis;
    END IF;
    IF v_mode = 'Ganti' THEN
        v_target := v_item."AsalTemplateId";
        IF v_target IS NULL OR NOT EXISTS (SELECT 1 FROM "ptwJsaTemplateTbl" WHERE "Id" = v_target AND "JenisPekerjaan" = v_jenis) THEN
            RAISE EXCEPTION 'Mode Ganti butuh baris asal generik di jenis pekerjaan yang sama. Pakai mode Tambah.';
        END IF;
    ELSIF v_mode <> 'Tambah' THEN
        RAISE EXCEPTION 'Mode harus Tambah atau Ganti.';
    END IF;
    IF COALESCE(trim(p_usulan->>'langkah'), '') = '' OR COALESCE(trim(p_usulan->>'bahaya'), '') = ''
       OR COALESCE(trim(p_usulan->>'pengendalian'), '') = '' THEN
        RAISE EXCEPTION 'Langkah, bahaya, dan pengendalian wajib diisi.';
    END IF;
    IF EXISTS (SELECT 1 FROM "ptwJsaTemplateUsulanTbl" WHERE "HiradcItemId" = p_hiradc_item_id AND "Status" = 'Menunggu') THEN
        RAISE EXCEPTION 'Baris ini sudah punya usulan yang menunggu keputusan.';
    END IF;

    INSERT INTO "ptwJsaTemplateUsulanTbl" ("HiradcId", "HiradcItemId", "NoDokumenHiradc", "Mode", "TemplateTargetId",
        "JenisPekerjaan", "Langkah", "Bahaya", "Pengendalian", "LikelihoodAwal", "SeverityAwal", "LikelihoodSisa",
        "SeveritySisa", "Alasan", "DiusulkanOleh", "DiusulkanQrCodeId")
    VALUES (v_h."Id", v_item."Id", v_h."NoDokumen" || ' Rev.' || v_h."Revisi", v_mode, v_target, v_jenis,
        trim(p_usulan->>'langkah'), trim(p_usulan->>'bahaya'), trim(p_usulan->>'pengendalian'),
        COALESCE((p_usulan->>'likelihoodAwal')::INT, v_item."LikelihoodAwal"),
        COALESCE((p_usulan->>'severityAwal')::INT, v_item."SeverityAwal"),
        COALESCE((p_usulan->>'likelihoodSisa')::INT, v_item."LikelihoodSisa"),
        COALESCE((p_usulan->>'severitySisa')::INT, v_item."SeveritySisa"),
        NULLIF(trim(p_usulan->>'alasan'), ''),
        COALESCE(NULLIF(trim(p_aktor_nama), ''), upper(trim(p_aktor_qr))), upper(trim(p_aktor_qr)))
    RETURNING "Id" INTO v_id;
    RETURN (SELECT public.usulan_jsa_template_json(u) FROM "ptwJsaTemplateUsulanTbl" u WHERE u."Id" = v_id);
END;
$$;

CREATE OR REPLACE FUNCTION public.get_jsa_template_usulan(p_status TEXT DEFAULT NULL)
RETURNS JSONB LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
    SELECT COALESCE(jsonb_agg(public.usulan_jsa_template_json(u)
        ORDER BY (u."Status" = 'Menunggu') DESC, u."TanggalDiusulkan" DESC), '[]'::JSONB)
    FROM "ptwJsaTemplateUsulanTbl" u
    WHERE COALESCE(p_status, '') = '' OR u."Status" = p_status;
$$;

-- p_setuju TRUE = template diubah/ditambah, FALSE = ditolak (catatan wajib)
CREATE OR REPLACE FUNCTION public.decide_jsa_template_usulan(p_aktor_nama TEXT, p_aktor_qr TEXT, p_id BIGINT,
                                                             p_setuju BOOLEAN, p_catatan TEXT DEFAULT NULL)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
    v_u     "ptwJsaTemplateUsulanTbl";
    v_hasil BIGINT;
    v_nama  TEXT := COALESCE(NULLIF(trim(p_aktor_nama), ''), upper(trim(p_aktor_qr)));
BEGIN
    PERFORM public.hsse_wajib_akses(p_aktor_nama, p_aktor_qr, 'HSSE-PTW');
    SELECT * INTO v_u FROM "ptwJsaTemplateUsulanTbl" WHERE "Id" = p_id FOR UPDATE;
    IF v_u."Status" IS DISTINCT FROM 'Menunggu' THEN
        RAISE EXCEPTION 'Usulan ini sudah diputuskan (status: %).', COALESCE(v_u."Status", '-');
    END IF;

    IF p_setuju THEN
        IF v_u."Mode" = 'Ganti' AND v_u."TemplateTargetId" IS NOT NULL THEN
            UPDATE "ptwJsaTemplateTbl" SET "Langkah" = v_u."Langkah", "Bahaya" = v_u."Bahaya",
                "Pengendalian" = v_u."Pengendalian", "LikelihoodAwal" = v_u."LikelihoodAwal",
                "SeverityAwal" = v_u."SeverityAwal", "LikelihoodSisa" = v_u."LikelihoodSisa",
                "SeveritySisa" = v_u."SeveritySisa", "Status" = 'Aktif'
            WHERE "Id" = v_u."TemplateTargetId"
            RETURNING "Id" INTO v_hasil;
        END IF;
        IF v_hasil IS NULL THEN   -- Tambah, atau baris target sudah dihapus
            INSERT INTO "ptwJsaTemplateTbl" ("JenisPekerjaan", "Langkah", "Bahaya", "Pengendalian", "Urutan", "Status",
                "LikelihoodAwal", "SeverityAwal", "LikelihoodSisa", "SeveritySisa")
            VALUES (v_u."JenisPekerjaan", v_u."Langkah", v_u."Bahaya", v_u."Pengendalian",
                (SELECT COALESCE(max("Urutan"), 0) + 1 FROM "ptwJsaTemplateTbl" WHERE "JenisPekerjaan" = v_u."JenisPekerjaan"),
                'Aktif', v_u."LikelihoodAwal", v_u."SeverityAwal", v_u."LikelihoodSisa", v_u."SeveritySisa")
            RETURNING "Id" INTO v_hasil;
        END IF;
        UPDATE "ptwJsaTemplateUsulanTbl" SET "Status" = 'Disetujui', "DiputuskanOleh" = v_nama,
            "DiputuskanQrCodeId" = upper(trim(p_aktor_qr)), "TanggalDiputuskan" = now(),
            "CatatanKeputusan" = NULLIF(trim(p_catatan), ''), "TemplateHasilId" = v_hasil
        WHERE "Id" = p_id;
    ELSE
        IF COALESCE(trim(p_catatan), '') = '' THEN
            RAISE EXCEPTION 'Tulis alasan kenapa ditolak.';
        END IF;
        UPDATE "ptwJsaTemplateUsulanTbl" SET "Status" = 'Ditolak', "DiputuskanOleh" = v_nama,
            "DiputuskanQrCodeId" = upper(trim(p_aktor_qr)), "TanggalDiputuskan" = now(),
            "CatatanKeputusan" = trim(p_catatan)
        WHERE "Id" = p_id;
    END IF;
    RETURN (SELECT public.usulan_jsa_template_json(u) FROM "ptwJsaTemplateUsulanTbl" u WHERE u."Id" = p_id);
END;
$$;

-- -------------------------------------------------------------------------------------
-- 5. Hak eksekusi
-- -------------------------------------------------------------------------------------
REVOKE EXECUTE ON FUNCTION public.hiradc_item_json("hiradcItemTbl") FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.usulan_jsa_template_json("ptwJsaTemplateUsulanTbl") FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.get_ptw_jsa_template(TEXT) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.save_hiradc(TEXT, TEXT, BIGINT, JSONB, JSONB) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.revise_hiradc(TEXT, TEXT, BIGINT) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.propose_jsa_template(TEXT, TEXT, BIGINT, JSONB) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.get_jsa_template_usulan(TEXT) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.decide_jsa_template_usulan(TEXT, TEXT, BIGINT, BOOLEAN, TEXT) TO anon, authenticated;

NOTIFY pgrst, 'reload schema';

-- =====================================================================================
-- CEK SETELAH JALAN
-- SELECT column_name FROM information_schema.columns
--   WHERE table_name = 'hiradcItemTbl' AND column_name IN ('AsalJenisPekerjaan', 'AsalTemplateId');  -> 2 baris
-- SELECT relrowsecurity FROM pg_class WHERE relname = 'ptwJsaTemplateUsulanTbl';                    -> true
-- SELECT public.get_ptw_jsa_template('Hot Work')->0 ? 'id';                                         -> true
--
-- ROLLBACK (usulan hilang; HIRADC tetap jalan dengan versi 067 kalau 067 dijalankan ulang):
-- DROP FUNCTION IF EXISTS public.propose_jsa_template(TEXT, TEXT, BIGINT, JSONB),
--   public.get_jsa_template_usulan(TEXT), public.decide_jsa_template_usulan(TEXT, TEXT, BIGINT, BOOLEAN, TEXT),
--   public.hiradc_item_json("hiradcItemTbl"), public.usulan_jsa_template_json("ptwJsaTemplateUsulanTbl");
-- DROP TABLE IF EXISTS "ptwJsaTemplateUsulanTbl";
-- ALTER TABLE "hiradcItemTbl" DROP COLUMN IF EXISTS "AsalJenisPekerjaan", DROP COLUMN IF EXISTS "AsalTemplateId";
-- lalu jalankan ulang 067.
-- =====================================================================================
