-- =====================================================================================
-- HSSE-Fusion4 — MIGRASI #27: AUDITEE BISA LEBIH DARI SATU DI INTERNAL AUDIT
-- Jalankan SETELAH 026, di Supabase project HSSE-Fusion4 (BUKAN Fusion4).
--
-- Kenapa perlu: "AuditeeNama"/"AuditeeDept" cuma nampung 1 orang, padahal 1 audit bisa
-- diikuti beberapa PIC/auditee sekaligus. Diganti jadi "AuditeeList" JSONB (array
-- {nama, dept}) -- kolom lama TETAP DIBIARKAN ADA (gak di-drop) biar aman, cuma udah
-- gak dipakai lagi sama RPC/frontend mulai migrasi ini.
-- =====================================================================================

-- 1) Tambah kolom baru.
ALTER TABLE "auditTbl" ADD COLUMN IF NOT EXISTS "AuditeeList" JSONB NOT NULL DEFAULT '[]'::jsonb;

-- 2) Backfill data lama (kalau ada row yang udah keburu dibuat sebelum migrasi ini).
UPDATE "auditTbl"
SET "AuditeeList" = jsonb_build_array(jsonb_build_object('nama', "AuditeeNama", 'dept', COALESCE("AuditeeDept", '')))
WHERE COALESCE(TRIM("AuditeeNama"), '') <> '' AND jsonb_array_length("AuditeeList") = 0;


-- -------------------------------------------------------------------------------------
-- 3. RPC: CREATE_AUDIT_PLAN -- ganti p_auditee_nama/p_auditee_dept jadi p_auditee_list.
-- -------------------------------------------------------------------------------------
DROP FUNCTION IF EXISTS create_audit_plan(BIGINT, TEXT, TEXT, TEXT, TEXT, TEXT, DATE, JSONB, TEXT, TEXT);
DROP FUNCTION IF EXISTS create_audit_plan(BIGINT, TEXT, TEXT, TEXT, TEXT, TEXT, DATE, JSONB, JSONB);
CREATE OR REPLACE FUNCTION create_audit_plan(
    p_project_id BIGINT,
    p_judul_audit TEXT,
    p_lead_auditor TEXT,
    p_lead_auditor_qrcode TEXT,
    p_standar_acuan TEXT DEFAULT '',
    p_scope_area TEXT DEFAULT '',
    p_tanggal_rencana DATE DEFAULT NULL,
    p_tim_auditor_list JSONB DEFAULT '[]'::jsonb,
    p_auditee_list JSONB DEFAULT '[]'::jsonb
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
        "LeadAuditor", "LeadAuditorQrCodeId", "TimAuditorList", "AuditeeList"
    ) VALUES (
        v_no_audit, p_project_id, p_judul_audit, p_standar_acuan, p_scope_area, p_tanggal_rencana,
        p_lead_auditor, p_lead_auditor_qrcode, p_tim_auditor_list, p_auditee_list
    )
    RETURNING "Id" INTO v_id;

    RETURN jsonb_build_object('success', true, 'id', v_id, 'noAudit', v_no_audit);
END;
$$;


-- -------------------------------------------------------------------------------------
-- 4. RPC: GET_AUDIT_LIST -- tukar auditeeNama/auditeeDept jadi auditeeList.
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
        'auditeeList', a."AuditeeList",
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
-- 5. RPC: GET_AUDIT_BY_ID -- tukar auditeeNama/auditeeDept jadi auditeeList.
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
        'auditeeList', a."AuditeeList",
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
