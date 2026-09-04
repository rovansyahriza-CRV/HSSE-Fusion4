-- =====================================================================================
-- HSSE-Fusion4 — MIGRASI #26: MODUL INTERNAL AUDIT
-- Jalankan SETELAH 001-025, di Supabase project HSSE-Fusion4 (BUKAN Fusion4).
--
-- Konsep (udah disepakati di chat):
-- 1. Audit TERJADWAL FORMAL -- ada tahap Rencana Audit dulu (Judul, Standar Acuan,
--    Scope/Area, Tanggal Rencana, Lead Auditor + Tim Auditor, Auditee), baru pas
--    hari-H pelaksanaan diisi Temuan per kriteria checklist.
-- 2. Alur status: Direncanakan -> Berlangsung (lagi diisi temuan hari-H) ->
--    Selesai Audit (temuan udah disubmit, masih ada NC yang perlu ditindaklanjuti)
--    -> Ditutup (semua NC udah diverifikasi closure-nya, ATAU dari awal gak ada NC).
-- 3. Temuan Non-Conformity (hasil "Tidak Sesuai") PUNYA CAPA SENDIRI (akar masalah,
--    rencana tindakan, PIC, tenggat) -- gak digabung/auto-generate ke modul CERMAT,
--    karena audit formal butuh tracking closure lebih detail per temuan.
--    Field "Kategori Temuan" (Major NC / Minor NC / Observasi) juga disimpan biar
--    bisa dibedain tingkat keparahannya pas riwayat/PDF.
-- 4. Closure per temuan lewat tahap terpisah "Verifikasi Closure" -- PIC/HSE upload
--    bukti tindak lanjut + catatan, org yang verifikasi harus punya Author tag
--    "Internal Auditor" (dicek lewat scan wajah/PIN, mirip pola verifikasi CERMAT).
-- 5. Cuma yang punya Author tag "Internal Auditor" yang boleh bikin Rencana Audit &
--    isi Temuan (Lead Auditor), sama kayak pola PTW/TBM/HSE Meeting.
-- 6. Master kriteria checklist disimpan di tabel sendiri (auditKriteriaTemplateTbl),
--    BUKAN di-hardcode -- biar bisa diedit/ditambah lewat SQL/Table Editor tanpa
--    ubah kode frontend. Isinya draft ringkasan klausul ISO 45001 -- SESUAIKAN lagi
--    sama standar/SOP HSSE PT BIMA yang asli lewat Table Editor Supabase.
-- =====================================================================================


-- -------------------------------------------------------------------------------------
-- 1. TABEL MASTER KRITERIA AUDIT (draft -- edit/tambah baris ini kapan aja lewat
--    Table Editor Supabase, gak perlu ubah kode).
-- -------------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS "auditKriteriaTemplateTbl" (
    "Id" BIGSERIAL PRIMARY KEY,
    "Klausul" TEXT NOT NULL,
    "Kriteria" TEXT NOT NULL,
    "Urutan" INT NOT NULL DEFAULT 0,
    "Status" TEXT NOT NULL DEFAULT 'Aktif' CHECK ("Status" IN ('Aktif', 'Non-Aktif')),
    "CreatedAt" TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_audit_kriteria_status ON "auditKriteriaTemplateTbl" ("Status");

-- Seed draft (ringkasan klausul ISO 45001) -- HANYA kalau tabelnya masih kosong.
INSERT INTO "auditKriteriaTemplateTbl" ("Klausul", "Kriteria", "Urutan")
SELECT * FROM (VALUES
    ('4. Konteks Organisasi', 'Ruang lingkup sistem manajemen HSSE proyek terdefinisi jelas (area, jenis pekerjaan, pihak terkait)', 10),
    ('4. Konteks Organisasi', 'Persyaratan Pertamina Hulu & regulasi K3L terkait sudah diidentifikasi & dipenuhi', 11),
    ('5. Kepemimpinan & Komitmen', 'Kebijakan HSSE tersedia, terkomunikasi, dan dipahami pekerja di lapangan', 20),
    ('5. Kepemimpinan & Komitmen', 'Peran, tanggung jawab & wewenang HSSE terdefinisi jelas (struktur organisasi proyek)', 21),
    ('5. Kepemimpinan & Komitmen', 'Manajemen terlihat aktif terlibat dalam program HSSE (safety walk, HSE meeting, dll)', 22),
    ('6. Perencanaan (Risiko & Peluang)', 'JSA/HIRADC tersedia & sesuai untuk setiap jenis pekerjaan yang sedang berjalan', 30),
    ('6. Perencanaan (Risiko & Peluang)', 'Tujuan & sasaran HSSE proyek terukur dan dipantau progressnya', 31),
    ('7. Dukungan (Kompetensi & Pelatihan)', 'Pekerja memiliki sertifikat/kompetensi sesuai jenis pekerjaan (rigger, welder, scaffolder, dll)', 40),
    ('7. Dukungan (Kompetensi & Pelatihan)', 'Toolbox Meeting/induction HSSE dilakukan sebelum pekerjaan dimulai', 41),
    ('7. Dukungan (Komunikasi & Dokumentasi)', 'Rekaman HSSE (permit, JSA, inspeksi, pelatihan) terdokumentasi & mudah ditelusuri', 42),
    ('8. Operasi (Kontrol Operasional)', 'Permit to Work & izin kerja lain (hot work, confined space, dll) diterapkan konsisten', 50),
    ('8. Operasi (Kontrol Operasional)', 'APD yang dipakai pekerja sesuai standar dan jenis pekerjaannya', 51),
    ('8. Operasi (Kontrol Operasional)', 'Peralatan kerja/alat berat terinspeksi berkala & memiliki sertifikasi yang berlaku', 52),
    ('8. Operasi (Kesiapsiagaan Darurat)', 'Prosedur tanggap darurat tersedia, teruji (drill), dan dipahami pekerja', 53),
    ('8. Operasi (Kesiapsiagaan Darurat)', 'APAR, jalur evakuasi & titik kumpul tersedia, mudah diakses, tidak terhalang', 54),
    ('9. Evaluasi Kinerja', 'Temuan inspeksi/observasi sebelumnya ditindaklanjuti sampai closed', 60),
    ('9. Evaluasi Kinerja', 'Insiden/kecelakaan (jika ada) diinvestigasi dengan akar masalah & lesson learned yang jelas', 61),
    ('9. Evaluasi Kinerja', 'Indikator kinerja HSSE (man-hours, temuan terbuka/tertutup) dipantau & dilaporkan', 62),
    ('10. Peningkatan', 'Tindakan korektif dari audit/inspeksi sebelumnya efektif mencegah temuan berulang', 70),
    ('10. Peningkatan', 'Ada proses continual improvement yang terlihat (revisi prosedur, program HSSE baru, dll)', 71)
) AS v("Klausul", "Kriteria", "Urutan")
WHERE NOT EXISTS (SELECT 1 FROM "auditKriteriaTemplateTbl");


-- -------------------------------------------------------------------------------------
-- 2. TABEL INTERNAL AUDIT (satu row per audit -- dari Rencana sampai Ditutup, mirip
--    pola hseMeetingTbl: row dibuat duluan lalu di-update statusnya lewat RPC).
--    TemuanList JSONB shape per item:
--    { "id": "AFxxxxx", "klausul":.., "kriteria":.., "hasil": "Sesuai"|"Tidak Sesuai"|"N/A",
--      "keterangan":.., "fotoList": [{url,fileId}],
--      "kategoriTemuan": "Major NC"|"Minor NC"|null, -- diisi kalau hasil "Tidak Sesuai"
--      "capa": { "akarMasalah":.., "rencanaTindakan":.., "picNama":.., "picQrCodeId":.., "tenggat":.. (date),
--                "status": "Open"|"Ditutup", "buktiFotoList":[...], "catatanVerifikasi":..,
--                "verifikatorNama":.., "verifikatorQrCodeId":.., "tanggalVerifikasi":.. } | null }
-- -------------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS "auditTbl" (
    "Id" BIGSERIAL PRIMARY KEY,
    "NoAudit" TEXT UNIQUE NOT NULL,
    "ProjectId" BIGINT NOT NULL REFERENCES "projectTbl"("Id"),
    "JudulAudit" TEXT NOT NULL,
    "StandarAcuan" TEXT DEFAULT '',
    "ScopeArea" TEXT DEFAULT '',
    "TanggalRencana" DATE,
    "LeadAuditor" TEXT NOT NULL,
    "LeadAuditorQrCodeId" TEXT DEFAULT '',
    "TimAuditorList" JSONB NOT NULL DEFAULT '[]'::jsonb, -- [{nama}]
    "AuditeeNama" TEXT DEFAULT '',
    "AuditeeDept" TEXT DEFAULT '',
    "Status" TEXT NOT NULL DEFAULT 'Direncanakan' CHECK ("Status" IN ('Direncanakan', 'Berlangsung', 'Selesai Audit', 'Ditutup')),
    "TanggalPelaksanaan" TIMESTAMPTZ,
    "TemuanList" JSONB NOT NULL DEFAULT '[]'::jsonb,
    "CatatanUmum" TEXT DEFAULT '',
    "FotoUmumList" JSONB NOT NULL DEFAULT '[]'::jsonb,
    "JumlahSesuai" INT NOT NULL DEFAULT 0,
    "JumlahTidakSesuai" INT NOT NULL DEFAULT 0,
    "JumlahNA" INT NOT NULL DEFAULT 0,
    "SkorPersen" NUMERIC(5,2),
    "TanggalSelesaiAudit" TIMESTAMPTZ,
    "TanggalDitutup" TIMESTAMPTZ,
    "CreatedAt" TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_audit_project ON "auditTbl" ("ProjectId");
CREATE INDEX IF NOT EXISTS idx_audit_status ON "auditTbl" ("Status");


-- -------------------------------------------------------------------------------------
-- 3. RPC: GENERATE NOMOR AUDIT
-- -------------------------------------------------------------------------------------
DROP FUNCTION IF EXISTS generate_no_audit();
CREATE OR REPLACE FUNCTION generate_no_audit()
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_date_str TEXT := TO_CHAR(NOW() AT TIME ZONE 'Asia/Makassar', 'YYYYMMDD');
    v_rand TEXT := LPAD(FLOOR(RANDOM() * 9000 + 1000)::TEXT, 4, '0');
BEGIN
    RETURN 'BIMA/AUDIT/' || v_date_str || '-' || v_rand;
END;
$$;


-- -------------------------------------------------------------------------------------
-- 4. RPC: AMBIL MASTER KRITERIA AUDIT AKTIF (dipakai form Pelaksanaan)
-- -------------------------------------------------------------------------------------
DROP FUNCTION IF EXISTS get_audit_checklist_template();
CREATE OR REPLACE FUNCTION get_audit_checklist_template()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_result JSONB;
BEGIN
    SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'id', "Id",
        'klausul', "Klausul",
        'kriteria', "Kriteria"
    ) ORDER BY "Urutan"), '[]'::jsonb)
    INTO v_result
    FROM "auditKriteriaTemplateTbl"
    WHERE "Status" = 'Aktif';

    RETURN v_result;
END;
$$;


-- -------------------------------------------------------------------------------------
-- 5. RPC: BIKIN RENCANA AUDIT (Status awal 'Direncanakan')
-- -------------------------------------------------------------------------------------
DROP FUNCTION IF EXISTS create_audit_plan(BIGINT, TEXT, TEXT, TEXT, TEXT, TEXT, DATE, JSONB, TEXT, TEXT);
CREATE OR REPLACE FUNCTION create_audit_plan(
    p_project_id BIGINT,
    p_judul_audit TEXT,
    p_lead_auditor TEXT,
    p_lead_auditor_qrcode TEXT,
    p_standar_acuan TEXT DEFAULT '',
    p_scope_area TEXT DEFAULT '',
    p_tanggal_rencana DATE DEFAULT NULL,
    p_tim_auditor_list JSONB DEFAULT '[]'::jsonb,
    p_auditee_nama TEXT DEFAULT '',
    p_auditee_dept TEXT DEFAULT ''
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_no_audit TEXT;
    v_id BIGINT;
BEGIN
    v_no_audit := generate_no_audit();

    INSERT INTO "auditTbl" (
        "NoAudit", "ProjectId", "JudulAudit", "StandarAcuan", "ScopeArea", "TanggalRencana",
        "LeadAuditor", "LeadAuditorQrCodeId", "TimAuditorList", "AuditeeNama", "AuditeeDept"
    ) VALUES (
        v_no_audit, p_project_id, p_judul_audit, p_standar_acuan, p_scope_area, p_tanggal_rencana,
        p_lead_auditor, p_lead_auditor_qrcode, p_tim_auditor_list, p_auditee_nama, p_auditee_dept
    )
    RETURNING "Id" INTO v_id;

    RETURN jsonb_build_object('success', true, 'id', v_id, 'noAudit', v_no_audit);
END;
$$;


-- -------------------------------------------------------------------------------------
-- 6. RPC: MULAI PELAKSANAAN (Direncanakan -> Berlangsung). Idempotent kalau dipanggil
--    ulang pas masih Berlangsung (buat kasus resume), tapi nolak kalau udah lewat tahap itu.
-- -------------------------------------------------------------------------------------
DROP FUNCTION IF EXISTS start_audit_pelaksanaan(BIGINT);
CREATE OR REPLACE FUNCTION start_audit_pelaksanaan(p_id BIGINT)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_status TEXT;
BEGIN
    SELECT "Status" INTO v_status FROM "auditTbl" WHERE "Id" = p_id;
    IF v_status IS NULL THEN
        RETURN jsonb_build_object('success', false, 'message', 'Rencana Audit tidak ditemukan.');
    END IF;
    IF v_status = 'Direncanakan' THEN
        UPDATE "auditTbl" SET "Status" = 'Berlangsung', "TanggalPelaksanaan" = NOW() WHERE "Id" = p_id;
    ELSIF v_status <> 'Berlangsung' THEN
        RETURN jsonb_build_object('success', false, 'message', 'Audit ini sudah ' || v_status || ', gak bisa dibuka lagi buat pelaksanaan.');
    END IF;
    RETURN jsonb_build_object('success', true);
END;
$$;


-- -------------------------------------------------------------------------------------
-- 7. RPC: SUBMIT TEMUAN AUDIT (finalize pelaksanaan). Kalau gak ada temuan yang butuh
--    CAPA (semua Sesuai/N/A/Observasi tanpa status NC), langsung Status='Ditutup'.
--    Kalau ada >=1 "Tidak Sesuai", Status='Selesai Audit' sampai semua CAPA-nya
--    diverifikasi closure lewat verify_close_audit_temuan().
-- -------------------------------------------------------------------------------------
DROP FUNCTION IF EXISTS submit_audit_temuan(BIGINT, JSONB, TEXT, JSONB);
CREATE OR REPLACE FUNCTION submit_audit_temuan(
    p_id BIGINT,
    p_temuan_list JSONB,
    p_catatan_umum TEXT DEFAULT '',
    p_foto_umum_list JSONB DEFAULT '[]'::jsonb
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_status TEXT;
    v_sesuai INT := 0;
    v_tidak INT := 0;
    v_na INT := 0;
    v_skor NUMERIC(5,2);
    v_item JSONB;
    v_final_status TEXT;
BEGIN
    SELECT "Status" INTO v_status FROM "auditTbl" WHERE "Id" = p_id;
    IF v_status IS NULL THEN
        RAISE EXCEPTION 'Rencana Audit tidak ditemukan.';
    END IF;
    IF v_status NOT IN ('Direncanakan', 'Berlangsung') THEN
        RAISE EXCEPTION 'Audit ini sudah % -- temuan tidak bisa disubmit ulang.', v_status;
    END IF;
    IF p_temuan_list IS NULL OR jsonb_array_length(p_temuan_list) = 0 THEN
        RAISE EXCEPTION 'Temuan tidak boleh kosong';
    END IF;

    FOR v_item IN SELECT * FROM jsonb_array_elements(p_temuan_list) LOOP
        IF v_item->>'hasil' = 'Sesuai' THEN
            v_sesuai := v_sesuai + 1;
        ELSIF v_item->>'hasil' = 'Tidak Sesuai' THEN
            v_tidak := v_tidak + 1;
        ELSE
            v_na := v_na + 1;
        END IF;
    END LOOP;

    v_skor := CASE WHEN (v_sesuai + v_tidak) > 0
        THEN ROUND((v_sesuai::NUMERIC / (v_sesuai + v_tidak)) * 100, 2)
        ELSE NULL END;

    -- Kalau gak ada NC sama sekali, audit langsung Ditutup (gak ada CAPA yang perlu diverifikasi).
    v_final_status := CASE WHEN v_tidak = 0 THEN 'Ditutup' ELSE 'Selesai Audit' END;

    UPDATE "auditTbl" SET
        "TemuanList" = p_temuan_list,
        "CatatanUmum" = p_catatan_umum,
        "FotoUmumList" = p_foto_umum_list,
        "JumlahSesuai" = v_sesuai,
        "JumlahTidakSesuai" = v_tidak,
        "JumlahNA" = v_na,
        "SkorPersen" = v_skor,
        "Status" = v_final_status,
        "TanggalSelesaiAudit" = NOW(),
        "TanggalDitutup" = CASE WHEN v_final_status = 'Ditutup' THEN NOW() ELSE NULL END
    WHERE "Id" = p_id;

    RETURN jsonb_build_object(
        'success', true,
        'status', v_final_status,
        'skorPersen', v_skor,
        'jumlahSesuai', v_sesuai,
        'jumlahTidakSesuai', v_tidak,
        'jumlahNA', v_na
    );
END;
$$;


-- -------------------------------------------------------------------------------------
-- 8. RPC: VERIFIKASI & TUTUP SATU TEMUAN NC (dipanggil dari audit-list.html per temuan).
--    Kalau ini temuan NC terakhir yang masih Open, audit induk otomatis ikut Ditutup.
-- -------------------------------------------------------------------------------------
DROP FUNCTION IF EXISTS verify_close_audit_temuan(BIGINT, TEXT, TEXT, TEXT, JSONB, TEXT);
CREATE OR REPLACE FUNCTION verify_close_audit_temuan(
    p_audit_id BIGINT,
    p_temuan_id TEXT,
    p_verifikator_nama TEXT,
    p_verifikator_qrcode TEXT DEFAULT '',
    p_bukti_foto_list JSONB DEFAULT '[]'::jsonb,
    p_catatan_verifikasi TEXT DEFAULT ''
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_temuan_list JSONB;
    v_new_list JSONB := '[]'::jsonb;
    v_item JSONB;
    v_found BOOLEAN := FALSE;
    v_all_closed BOOLEAN := TRUE;
BEGIN
    SELECT "TemuanList" INTO v_temuan_list FROM "auditTbl" WHERE "Id" = p_audit_id;
    IF v_temuan_list IS NULL THEN
        RETURN jsonb_build_object('success', false, 'message', 'Audit tidak ditemukan.');
    END IF;

    FOR v_item IN SELECT * FROM jsonb_array_elements(v_temuan_list) LOOP
        IF v_item->>'id' = p_temuan_id THEN
            v_found := TRUE;
            v_item := v_item || jsonb_build_object(
                'capa', COALESCE(v_item->'capa', '{}'::jsonb) || jsonb_build_object(
                    'status', 'Ditutup',
                    'buktiFotoList', p_bukti_foto_list,
                    'catatanVerifikasi', p_catatan_verifikasi,
                    'verifikatorNama', p_verifikator_nama,
                    'verifikatorQrCodeId', p_verifikator_qrcode,
                    'tanggalVerifikasi', to_jsonb(NOW())
                )
            );
        END IF;
        v_new_list := v_new_list || jsonb_build_array(v_item);
        IF v_item->>'hasil' = 'Tidak Sesuai' AND COALESCE(v_item->'capa'->>'status', 'Open') <> 'Ditutup' THEN
            v_all_closed := FALSE;
        END IF;
    END LOOP;

    IF NOT v_found THEN
        RETURN jsonb_build_object('success', false, 'message', 'Temuan tidak ditemukan di audit ini.');
    END IF;

    UPDATE "auditTbl" SET
        "TemuanList" = v_new_list,
        "Status" = CASE WHEN v_all_closed THEN 'Ditutup' ELSE "Status" END,
        "TanggalDitutup" = CASE WHEN v_all_closed THEN NOW() ELSE "TanggalDitutup" END
    WHERE "Id" = p_audit_id;

    RETURN jsonb_build_object('success', true, 'allClosed', v_all_closed);
END;
$$;


-- -------------------------------------------------------------------------------------
-- 9. RPC: RIWAYAT AUDIT -- p_status: NULL = semua
-- -------------------------------------------------------------------------------------
DROP FUNCTION IF EXISTS get_audit_list(TEXT);
CREATE OR REPLACE FUNCTION get_audit_list(p_status TEXT DEFAULT NULL)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_result JSONB;
BEGIN
    SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'id', a."Id",
        'noAudit', a."NoAudit",
        'judulAudit', a."JudulAudit",
        'standarAcuan', a."StandarAcuan",
        'scopeArea', a."ScopeArea",
        'tanggalRencana', a."TanggalRencana",
        'leadAuditor', a."LeadAuditor",
        'leadAuditorQrCodeId', a."LeadAuditorQrCodeId",
        'timAuditorList', a."TimAuditorList",
        'auditeeNama', a."AuditeeNama",
        'auditeeDept', a."AuditeeDept",
        'status', a."Status",
        'tanggalPelaksanaan', a."TanggalPelaksanaan",
        'temuanList', a."TemuanList",
        'catatanUmum', a."CatatanUmum",
        'fotoUmumList', a."FotoUmumList",
        'jumlahSesuai', a."JumlahSesuai",
        'jumlahTidakSesuai', a."JumlahTidakSesuai",
        'jumlahNA', a."JumlahNA",
        'skorPersen', a."SkorPersen",
        'tanggalSelesaiAudit', a."TanggalSelesaiAudit",
        'tanggalDitutup', a."TanggalDitutup",
        'namaProject', p."NamaProject",
        'noKontrak', p."NoKontrak"
    ) ORDER BY a."CreatedAt" DESC), '[]'::JSONB)
    INTO v_result
    FROM "auditTbl" a
    JOIN "projectTbl" p ON p."Id" = a."ProjectId"
    WHERE p_status IS NULL OR a."Status" = p_status;

    RETURN v_result;
END;
$$;


-- -------------------------------------------------------------------------------------
-- 10. RPC: DETAIL 1 AUDIT BY ID (dipakai resume pelaksanaan & audit-pdf.html)
-- -------------------------------------------------------------------------------------
DROP FUNCTION IF EXISTS get_audit_by_id(BIGINT);
CREATE OR REPLACE FUNCTION get_audit_by_id(p_id BIGINT)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_result JSONB;
BEGIN
    SELECT jsonb_build_object(
        'id', a."Id",
        'noAudit', a."NoAudit",
        'projectId', a."ProjectId",
        'judulAudit', a."JudulAudit",
        'standarAcuan', a."StandarAcuan",
        'scopeArea', a."ScopeArea",
        'tanggalRencana', a."TanggalRencana",
        'leadAuditor', a."LeadAuditor",
        'leadAuditorQrCodeId', a."LeadAuditorQrCodeId",
        'timAuditorList', a."TimAuditorList",
        'auditeeNama', a."AuditeeNama",
        'auditeeDept', a."AuditeeDept",
        'status', a."Status",
        'tanggalPelaksanaan', a."TanggalPelaksanaan",
        'temuanList', a."TemuanList",
        'catatanUmum', a."CatatanUmum",
        'fotoUmumList', a."FotoUmumList",
        'jumlahSesuai', a."JumlahSesuai",
        'jumlahTidakSesuai', a."JumlahTidakSesuai",
        'jumlahNA', a."JumlahNA",
        'skorPersen', a."SkorPersen",
        'tanggalSelesaiAudit', a."TanggalSelesaiAudit",
        'tanggalDitutup', a."TanggalDitutup",
        'namaProject', p."NamaProject",
        'noKontrak', p."NoKontrak",
        'tipeKonstruksi', p."TipeKonstruksi"
    )
    INTO v_result
    FROM "auditTbl" a
    JOIN "projectTbl" p ON p."Id" = a."ProjectId"
    WHERE a."Id" = p_id;

    RETURN v_result;
END;
$$;
