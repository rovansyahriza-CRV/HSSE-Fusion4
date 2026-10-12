-- =====================================================================================
-- 063 -- PIC fase 2, tahap 1: tutup akses langsung ke tabel HSSE (semua lewat RPC).
-- Jalankan di project Supabase HSSE-Fusion4 (BUKAN Fusion4 SmartGate). Run after 062.
--
-- Masalah: 16 tabel HSSE masih punya policy "allow_all_<tabel>" buat anon. Anon key ada
-- di config.js (publik), jadi siapa pun bisa INSERT/UPDATE/DELETE langsung ke tabel
-- (misal ubah Status incident jadi Closed) tanpa lewat RPC dan tanpa cek PIC/Author.
-- Halaman HSSE sudah 100% lewat RPC (SECURITY DEFINER, owner postgres = bypass RLS),
-- kecuali Training Matrix -- itu dikerjakan di tahap 2, tabelnya TIDAK disentuh di sini.
--
-- Yang diubah:
-- 1. Policy allow_all_* diganti policy "<tabel>_no_direct" (false), pola sama dengan
--    Management Review (046) & Man-Hours (056). Edit lewat Table Editor Supabase tetap
--    bisa (pakai role postgres/service).
-- 2. managementReviewDocumentSequence: RLS dinyalakan (sebelumnya mati).
-- 3. RPC tulis yang sudah tidak dipanggil halaman mana pun dicabut dari anon/authenticated
--    (fungsinya tetap ada, cuma tidak bisa dipanggil dari browser):
--    update_cermat_status, update_incident_fields, incident_start_investigation,
--    submit_hse_meeting, save_man_hours_project_map, overload lama incident_submit_review
--    (tanpa lesson learned) & save_management_review_action (tanpa topic).
-- Tabel tender_* bukan punya HSSE, tidak disentuh.
-- Aman dijalankan ulang.
-- =====================================================================================

DO $$
DECLARE
    t TEXT;
    v_tabel TEXT[] := ARRAY[
        'auditKriteriaTemplateTbl', 'auditTbl', 'cermatTbl', 'departemenTbl',
        'hseMeetingTbl', 'hseProgramMasterItemTbl', 'hseProgramTbl', 'incidentTbl',
        'inspeksiChecklistTemplateTbl', 'inspeksiTbl', 'mwtTbl', 'projectTbl',
        'ptwHazardChecklistTemplateTbl', 'ptwJsaTemplateTbl', 'ptwTbl', 'tbmTbl'
    ];
BEGIN
    FOREACH t IN ARRAY v_tabel LOOP
        EXECUTE format('ALTER TABLE %I ENABLE ROW LEVEL SECURITY', t);
        EXECUTE format('DROP POLICY IF EXISTS %I ON %I', 'allow_all_' || t, t);
        EXECUTE format('DROP POLICY IF EXISTS %I ON %I', t || '_no_direct', t);
        EXECUTE format('CREATE POLICY %I ON %I FOR ALL TO anon, authenticated USING (false) WITH CHECK (false)',
                       t || '_no_direct', t);
    END LOOP;
END $$;

ALTER TABLE "managementReviewDocumentSequence" ENABLE ROW LEVEL SECURITY;

DO $$
DECLARE
    f TEXT;
BEGIN
    FOR f IN
        SELECT p.oid::regprocedure::text
        FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
        WHERE n.nspname = 'public'
          AND (
              p.proname IN ('update_cermat_status', 'update_incident_fields',
                            'incident_start_investigation', 'submit_hse_meeting',
                            'save_man_hours_project_map')
              OR (p.proname = 'incident_submit_review'
                  AND pg_get_function_identity_arguments(p.oid) = 'p_id bigint, p_nama text, p_qrcode text')
              OR (p.proname = 'save_management_review_action'
                  AND pg_get_function_identity_arguments(p.oid) NOT LIKE '%p_topic%')
          )
    LOOP
        EXECUTE format('REVOKE EXECUTE ON FUNCTION %s FROM PUBLIC, anon, authenticated', f);
    END LOOP;
END $$;

-- =====================================================================================
-- CEK SETELAH JALAN (harusnya 0 baris):
-- SELECT c.relname, p.polname
-- FROM pg_policy p JOIN pg_class c ON c.oid = p.polrelid
-- WHERE p.polname LIKE 'allow_all_%' AND c.relname NOT LIKE 'tender_%';
--
-- ROLLBACK darurat (kalau ada halaman yang ternyata error "row-level security"):
-- buka lagi satu tabel saja, contoh incidentTbl:
-- DROP POLICY IF EXISTS "incidentTbl_no_direct" ON "incidentTbl";
-- CREATE POLICY "allow_all_incidentTbl" ON "incidentTbl" FOR ALL TO anon, authenticated USING (true) WITH CHECK (true);
-- =====================================================================================
