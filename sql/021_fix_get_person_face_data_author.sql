-- =====================================================================================
-- HSSE-Fusion4 — MIGRASI #21: FIX get_person_face_data() SUPAYA IKUT BALIKIN author & digitalPin
-- Jalankan di Supabase project FUSION4 (BUKAN HSSE-Fusion4!) -- sama kayak migrasi #008,
-- ini nyentuh Fusion4 karena field yang dibutuhin (Author & DigitalPIN) cuma ada di sana.
--
-- Kenapa perlu: Author-gate di ptw-report.html (Author "Permit & JSA") dan
-- tbm-report.html (Author "Leader Toolbox Meeting") ngecek hasAuthorTag(data.person, ...)
-- dari hasil Scan QR Code. Tapi objek "person" di dalam get_person_face_data() SELAMA INI
-- cuma punya nama/qrCodeId/kualifikasi/fotoUrl/descriptor -- gak ada "author" sama sekali.
-- Akibatnya scan QR SELALU ketolak "tidak punya izin" walaupun Author-nya udah bener di
-- database (Scan Wajah & Input PIN gak kena masalah ini karena dua-duanya pakai fungsi
-- get_all_face_data() yang udah dibenerin di migrasi #008).
--
-- Perubahan: nambah 'author' & 'digitalPin' ke objek "person" (dan ke level atas juga
-- biar konsisten sama get_all_face_data). Gak ada JOIN baru, gak ada kolom yang
-- diubah/dihapus -- v_kar udah SELECT * dari karyawanTbl jadi field-nya udah ada.
-- =====================================================================================

CREATE OR REPLACE FUNCTION public.get_person_face_data(p_qrcode text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
    v_kar RECORD;
    v_face RECORD;
BEGIN
    SELECT * INTO v_kar
    FROM "karyawanTbl"
    WHERE UPPER(TRIM("QrCodeId")) = UPPER(TRIM(p_qrcode))
    LIMIT 1;

    IF v_kar."Id" IS NULL THEN
        RETURN jsonb_build_object('status', 'NOT_FOUND', 'valid', FALSE, 'message', 'Karyawan tidak ditemukan.');
    END IF;

    SELECT * INTO v_face
    FROM "faceData"
    WHERE UPPER(TRIM("QrCodeId")) = UPPER(TRIM(p_qrcode))
    LIMIT 1;

    RETURN jsonb_build_object(
        'status', 'OK',
        'valid', TRUE,
        'found', (v_face."Descriptor" IS NOT NULL),
        'descriptor', v_face."Descriptor",
        'qrCodeId', v_kar."QrCodeId",
        'nama', v_kar."NamaPersonnel",
        'kualifikasi', v_kar."Kualifikasi",
        'fotoUrl', COALESCE(v_face."FotoURL", v_kar."FotoURL", ''),
        'author', v_kar."Author",
        'digitalPin', v_kar."DigitalPIN",
        'person', jsonb_build_object(
            'nama', v_kar."NamaPersonnel",
            'qrCodeId', v_kar."QrCodeId",
            'kualifikasi', v_kar."Kualifikasi",
            'fotoUrl', COALESCE(v_face."FotoURL", v_kar."FotoURL", ''),
            'descriptor', v_face."Descriptor",
            'author', v_kar."Author",
            'digitalPin', v_kar."DigitalPIN"
        ),
        'authReq', jsonb_build_object(
            'needAuth', COALESCE(v_kar."AuthCheck", FALSE)
        )
    );
END;
$function$;
