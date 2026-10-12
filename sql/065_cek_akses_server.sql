-- =====================================================================================
-- 065 -- PIC fase 2, tahap 3: server HSSE ngecek PIC/Author sendiri ke SmartGate.
-- Jalankan di project Supabase HSSE-Fusion4 (BUKAN Fusion4 SmartGate). Run after 064.
-- Tidak perlu ubah HTML.
--
-- Sebelumnya: RPC tulis cuma percaya nama + QrCodeId yang dikirim browser. Cek PIC/Author
--   cuma di JavaScript, jadi bisa dilewati dengan manggil RPC langsung pakai anon key.
-- Sekarang: sebelum nyimpan, RPC nanya SmartGate (get_person_face_data, pakai URL & key
--   yang sudah ada di manHoursAutoConfigTbl) tag PIC/Author pemilik QR itu, lalu dicek
--   dengan aturan yang SAMA PERSIS dengan hsseAccess.js:
--     - kode HSSE-xxx  -> PIC kode itu, atau HSSE-ALL, atau Author lama alias-nya
--     - "<Dept> Admin" -> PIC HSSE-CRM / HSSE-ALL, atau Author "<Dept> Admin"
--     - tag lain       -> Author tag itu
--     - tanpa tag      -> cukup QR-nya terdaftar di SmartGate (lapor CERMAT, check-in, scan TBM)
--   Kalau SmartGate gak bisa dihubungi -> aksi DITOLAK (fail closed).
--
-- Cara pasangnya: tiap RPC di daftar bawah di-rename jadi "<nama>__inti" (isi aslinya
-- utuh, gak bisa dipanggil browser), lalu dibuat RPC baru dengan nama & parameter yang sama
-- yang ngecek akses dulu baru manggil __inti.
-- PENTING buat migrasi berikutnya: kalau mau ubah isi salah satu RPC ini, ubah
-- "<nama>__inti"-nya, jangan CREATE OR REPLACE nama aslinya (cek-nya bakal hilang).
-- Aman dijalankan ulang.
-- =====================================================================================

-- -------------------------------------------------------------------------------------
-- 1. Aturan tag (salinan hsseAccess.js)
-- -------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.hsse_tag_cocok(p_author TEXT, p_pic TEXT, p_tag TEXT)
RETURNS BOOLEAN LANGUAGE plpgsql IMMUTABLE AS $$
DECLARE
    v_author TEXT[] := ARRAY(SELECT lower(trim(x)) FROM regexp_split_to_table(COALESCE(p_author, ''), '[,;|]') x WHERE trim(x) <> '');
    v_pic    TEXT[] := ARRAY(SELECT lower(trim(x)) FROM regexp_split_to_table(COALESCE(p_pic, ''), '[,;|]') x WHERE trim(x) <> '');
    v_tag    TEXT   := trim(COALESCE(p_tag, ''));
    v_code   TEXT;
    v_alias  TEXT[];
    -- semua alias Author lama (huruf kecil), sama dengan PIC_ALIASES di hsseAccess.js
    v_semua_alias TEXT[] := ARRAY['investigate incident/accident', 'permit & jsa', 'leader toolbox meeting',
        'leader hse meeting', 'internal auditor', 'admin mwt', 'management walkthrough',
        'management review', 'training matrix admin'];
BEGIN
    IF v_tag = '' THEN
        RETURN TRUE;
    END IF;
    IF v_tag ~* '^HSSE-' THEN
        v_code := upper(v_tag);
        IF lower(v_code) = ANY (v_pic) OR 'hsse-all' = ANY (v_pic) THEN
            RETURN TRUE;
        END IF;
        v_alias := CASE v_code
            WHEN 'HSSE-INC' THEN ARRAY['investigate incident/accident']
            WHEN 'HSSE-PTW' THEN ARRAY['permit & jsa']
            WHEN 'HSSE-TBM' THEN ARRAY['leader toolbox meeting']
            WHEN 'HSSE-MTG' THEN ARRAY['leader hse meeting']
            WHEN 'HSSE-AUD' THEN ARRAY['internal auditor']
            WHEN 'HSSE-MWT' THEN ARRAY['admin mwt', 'management walkthrough']
            WHEN 'HSSE-MRV' THEN ARRAY['management review']
            WHEN 'HSSE-TRM' THEN ARRAY['training matrix admin']
            ELSE ARRAY[]::TEXT[] END;
        RETURN v_author && v_alias;
    END IF;
    IF v_tag ~ ' Admin$' AND NOT (lower(v_tag) = ANY (v_semua_alias)) THEN
        RETURN 'hsse-crm' = ANY (v_pic) OR 'hsse-all' = ANY (v_pic) OR lower(v_tag) = ANY (v_author);
    END IF;
    RETURN lower(v_tag) = ANY (v_author);
END;
$$;

-- -------------------------------------------------------------------------------------
-- 2. Cek akses ke SmartGate (ganti stub dari 064)
-- -------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.hsse_wajib_akses(p_nama TEXT, p_qr TEXT, p_tag TEXT)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, extensions AS $$
DECLARE
    v_url  TEXT;
    v_key  TEXT;
    v_resp RECORD;
    v_data JSONB;
    v_label TEXT;
BEGIN
    IF COALESCE(trim(p_qr), '') = '' THEN
        RAISE EXCEPTION 'Verifikasi identitas dulu (QR Code ID kosong).';
    END IF;

    SELECT "SmartGateUrl", "SmartGateKey" INTO v_url, v_key FROM "manHoursAutoConfigTbl" WHERE "Id" = 1;
    IF COALESCE(v_url, '') = '' OR COALESCE(v_key, '') = '' THEN
        RAISE EXCEPTION 'Setting koneksi SmartGate belum ada (manHoursAutoConfigTbl, migrasi 059).';
    END IF;

    BEGIN
        PERFORM http_set_curlopt('CURLOPT_TIMEOUT', '10');
        SELECT status, content INTO v_resp
        FROM http((
            'POST',
            rtrim(v_url, '/') || '/rest/v1/rpc/get_person_face_data',
            ARRAY[http_header('apikey', v_key), http_header('Authorization', 'Bearer ' || v_key)],
            'application/json',
            jsonb_build_object('p_qrcode', upper(trim(p_qr)))::TEXT
        )::http_request);
    EXCEPTION WHEN OTHERS THEN
        RAISE EXCEPTION 'SmartGate gak bisa dihubungi buat cek akses, coba lagi sebentar. (%)', SQLERRM;
    END;
    IF v_resp.status IS DISTINCT FROM 200 THEN
        RAISE EXCEPTION 'SmartGate gak bisa dihubungi buat cek akses (HTTP %), coba lagi sebentar.', v_resp.status;
    END IF;

    v_data := v_resp.content::JSONB;
    IF v_data->>'status' IS DISTINCT FROM 'OK' THEN
        RAISE EXCEPTION 'QR Code ID % tidak terdaftar di SmartGate.', upper(trim(p_qr));
    END IF;

    IF NOT public.hsse_tag_cocok(v_data->>'author', v_data->>'pic', p_tag) THEN
        v_label := CASE WHEN trim(p_tag) ~* '^HSSE-' THEN 'PIC "' || upper(trim(p_tag)) || '"'
                        WHEN trim(p_tag) ~ ' Admin$' THEN 'PIC "HSSE-CRM" / Author "' || trim(p_tag) || '"'
                        ELSE 'Author "' || trim(p_tag) || '"' END;
        RAISE EXCEPTION 'Akses ditolak: % tidak punya %.', COALESCE(v_data->>'nama', p_nama, p_qr), v_label;
    END IF;
END;
$$;
REVOKE EXECUTE ON FUNCTION public.hsse_wajib_akses(TEXT, TEXT, TEXT) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.hsse_tag_cocok(TEXT, TEXT, TEXT) FROM PUBLIC, anon, authenticated;

-- -------------------------------------------------------------------------------------
-- 3. Pasang cek ke RPC tulis
--    kolom: RPC, parameter nama, parameter QR, tag (ekspresi SQL; NULL = cukup terdaftar)
-- -------------------------------------------------------------------------------------
DO $do$
DECLARE
    m RECORD;
    f RECORD;
    v_inti_oid OID;
    v_call TEXT;
    v_grant BOOLEAN;
BEGIN
    FOR m IN SELECT * FROM (VALUES
        -- CERMAT
        ('submit_cermat_report',          'p_nama_pelapor',        'p_pelapor_qrcode',      'NULL'),
        ('cermat_assign_to_dept',         'p_verifikator_nama',    'p_verifikator_qrcode',  $t$'Verifikasi Cermat'$t$),
        ('cermat_submit_followup',        'p_followup_nama',       'p_followup_qrcode',
            $t$(SELECT COALESCE("AssignedDeptNama", '') || ' Admin' FROM "cermatTbl" WHERE "Id" = p_id)$t$),
        ('cermat_review_decision',        'p_reviewer_nama',       'p_reviewer_qrcode',     $t$'Verifikasi Cermat'$t$),
        ('cermat_reopen',                 'p_reopener_nama',       'p_reopener_qrcode',     $t$'Verifikasi Cermat'$t$),
        -- Incident
        ('submit_incident_report',        'p_nama_pelapor',        'p_pelapor_qrcode',      $t$'HSSE-INC'$t$),
        ('incident_submit_investigation', 'p_nama',                'p_qrcode',              $t$'HSSE-INC'$t$),
        ('incident_submit_review',        'p_nama',                'p_qrcode',              $t$'Review Incident/Accident'$t$),
        ('incident_review_decision',      'p_nama',                'p_qrcode',              $t$'Approved Incident/Accident'$t$),
        ('incident_reopen',               'p_nama',                'p_qrcode',              $t$'Approved Incident/Accident'$t$),
        -- Inspeksi
        ('submit_inspeksi_report',        'p_nama_inspektor',      'p_inspektor_qrcode',    $t$'HSSE-INS'$t$),
        -- PTW
        ('submit_ptw',                    'p_nama_requester',      'p_requester_qrcode',    $t$'HSSE-PTW'$t$),
        ('ptw_hse_review',                'p_nama',                'p_qrcode',              $t$'Review Permit to Work'$t$),
        ('ptw_area_authority_decision',   'p_nama',                'p_qrcode',              $t$'Approve Permit to Work'$t$),
        ('ptw_request_closing',           'p_nama',                'p_qrcode',              $t$'HSSE-PTW'$t$),
        ('ptw_closing_decision',          'p_nama',                'p_qrcode',              $t$'Review Permit to Work'$t$),
        ('ptw_reopen',                    'p_nama',                'p_qrcode',              $t$'Review Permit to Work'$t$),
        -- TBM
        ('submit_tbm_session',            'p_leader_nama',         'p_leader_qrcode',       $t$'HSSE-TBM'$t$),
        ('tbm_scan_peserta',              'p_nama',                'p_qrcode',              'NULL'),
        -- HSE Meeting
        ('start_hse_meeting_session',     'p_nama_pemimpin',       'p_pemimpin_qrcode',     $t$'HSSE-MTG'$t$),
        ('checkin_hse_meeting',           'p_nama',                'p_qrcode',              'NULL'),
        -- Internal Audit
        ('create_audit_plan',             'p_lead_auditor',        'p_lead_auditor_qrcode', $t$'HSSE-AUD'$t$),
        ('verify_close_audit_temuan',     'p_verifikator_nama',    'p_verifikator_qrcode',  $t$'Internal Auditor'$t$),
        -- MWT
        ('create_mwt_schedule',           'p_admin_nama',          'p_admin_qrcode',        $t$'HSSE-MWT'$t$),
        ('submit_mwt_kunjungan',          'p_management_nama',     'p_management_qrcode',   $t$'HSSE-MWT'$t$),
        ('close_mwt_session',             'p_admin_nama',          'p_admin_qrcode',        $t$'HSSE-MWT'$t$),
        -- Management Review (Completed/Cancelled butuh Author "Management Review", sama kayak halaman)
        ('save_management_review',        'p_created_by_nama',     'p_created_by_qrcode',
            $t$CASE WHEN p_status IN ('Completed', 'Cancelled') THEN 'Management Review' ELSE 'HSSE-MRV' END$t$),
        ('checkin_management_review',     'p_nama',                'p_qrcode',              'NULL'),
        -- Statistik / Man-hours
        ('save_man_hours_smartgate',      'p_nama',                'p_qr',                  $t$'HSSE-STA'$t$),
        ('save_man_hours_koreksi',        'p_nama',                'p_qr',                  $t$'HSSE-STA'$t$),
        ('save_man_hours_auto_config',    'p_nama',                'p_qr',                  $t$'HSSE-STA'$t$),
        ('save_man_hours_auto_project',   'p_nama',                'p_qr',                  $t$'HSSE-STA'$t$),
        ('sinkron_project_smartgate',     'p_nama',                'p_qr',                  $t$'HSSE-STA'$t$)
    ) AS t(fn, p_nama, p_qr, tag_expr)
    LOOP
        FOR f IN
            SELECT p.oid, oidvectortypes(p.proargtypes) AS argtypes
            FROM pg_proc p
            WHERE p.pronamespace = 'public'::regnamespace AND p.proname = m.fn
              AND m.p_qr = ANY (p.proargnames)
        LOOP
            -- RPC yang sebelumnya gak bisa dipanggil anon (misal overload lama yang dicabut 063) tetap tertutup
            v_grant := has_function_privilege('anon', f.oid, 'EXECUTE');
            v_inti_oid := to_regprocedure(format('public.%I(%s)', m.fn || '__inti', f.argtypes));
            IF v_inti_oid IS NULL THEN
                -- pertama kali: isi asli dipindah ke __inti
                EXECUTE format('ALTER FUNCTION %s RENAME TO %I', f.oid::regprocedure, m.fn || '__inti');
                v_inti_oid := f.oid;
            END IF;
            EXECUTE format('REVOKE EXECUTE ON FUNCTION %s FROM PUBLIC, anon, authenticated', v_inti_oid::regprocedure);

            SELECT string_agg(format('%1$I => %1$I', n), ', ' ORDER BY i) INTO v_call
            FROM unnest((SELECT proargnames FROM pg_proc WHERE oid = v_inti_oid)) WITH ORDINALITY AS a(n, i);

            EXECUTE format($f$
                CREATE OR REPLACE FUNCTION public.%I(%s)
                RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $w$
                BEGIN
                    PERFORM public.hsse_wajib_akses(%I, %I, %s);
                    RETURN public.%I(%s);
                END;
                $w$ $f$,
                m.fn, pg_get_function_arguments(v_inti_oid), m.p_nama, m.p_qr, m.tag_expr,
                m.fn || '__inti', v_call);
            IF v_grant THEN
                EXECUTE format('GRANT EXECUTE ON FUNCTION public.%I(%s) TO anon, authenticated', m.fn, f.argtypes);
            ELSE
                EXECUTE format('REVOKE EXECUTE ON FUNCTION public.%I(%s) FROM PUBLIC, anon, authenticated', m.fn, f.argtypes);
            END IF;
        END LOOP;
    END LOOP;
END $do$;

-- =====================================================================================
-- CEK SETELAH JALAN:
-- 1) RPC yang sudah dijaga (harusnya 34 baris, semua anon_inti = false):
-- SELECT replace(p.proname, '__inti', '') AS rpc, has_function_privilege('anon', p.oid, 'EXECUTE') AS anon_inti
-- FROM pg_proc p WHERE p.pronamespace = 'public'::regnamespace AND p.proname LIKE '%\_\_inti' ORDER BY 1;
-- 2) Tes aturan tag (harusnya semua true):
-- SELECT hsse_tag_cocok('', 'HSSE-ALL', 'HSSE-PTW'), hsse_tag_cocok('Permit & JSA', '', 'HSSE-PTW'),
--        NOT hsse_tag_cocok('', 'ALL', 'HSSE-PTW'), hsse_tag_cocok('', 'HSSE-CRM', 'Operation Admin'),
--        NOT hsse_tag_cocok('', 'HSSE-ALL', 'Review Permit to Work');
--
-- ROLLBACK satu RPC (contoh submit_ptw), balikin ke versi tanpa cek:
-- DROP FUNCTION public.submit_ptw(<tipe parameter>);
-- ALTER FUNCTION public.submit_ptw__inti(<tipe parameter>) RENAME TO submit_ptw;
-- GRANT EXECUTE ON FUNCTION public.submit_ptw(<tipe parameter>) TO anon, authenticated;
-- =====================================================================================
