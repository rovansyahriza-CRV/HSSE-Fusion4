-- =====================================================================================
-- MIGRASI #36: FIX get_all_face_data() & get_person_face_data() -- IKUT BACA "paswordTbl"
-- Jalankan di Supabase project FUSION4 (BUKAN HSSE-Fusion4!), sama kayak migrasi
-- #008/#021/#025/#028/#029/#030 -- ini nyentuh Fusion4 karena karyawanTbl & paswordTbl
-- cuma ada di sana.
-- READ-ONLY: cuma redefine 2 RPC baca-saja (SELECT), gak ada perubahan data sama sekali.
--
-- Kenapa perlu: hasil audit nyeluruh atas semua query terkait "Author" dari Cermat sampai
-- MWT. Ketemu 2 RPC yang jadi GERBANG IDENTIFIKASI buat SEMUA modul HSSE-Fusion4
-- (Cermat, Incident, PTW, TBM, HSE Meeting, Internal Audit, MWT):
--   1. get_all_face_data()   -> dipakai buat Scan Wajah & Input PIN di semua modul.
--   2. get_person_face_data() -> dipakai buat Scan QR Code di semua modul.
-- Dua-duanya SELAMA INI cuma baca Author dari "karyawanTbl"."Author" -- gak pernah
-- nyentuh "paswordTbl" sama sekali. Padahal form "Edit Karyawan" bawaan Fusion4 (yang
-- dipakai admin buat nambah/edit Author tag orang) itu nulisnya ke "paswordTbl", BUKAN ke
-- "karyawanTbl". Akibatnya: siapapun yang Author tag-nya baru ditambah lewat form itu
-- (bukan lewat UPDATE SQL langsung ke karyawanTbl) bakal SELALU ketolak "tidak punya izin"
-- di modul MANAPUN yang makai Scan Wajah/PIN/QR -- ini yang kejadian ke Hairani & CRV pas
-- nyoba fitur MWT kemarin, tapi sebenernya bug-nya bukan cuma soal MWT.
--
-- Pola fix-nya SAMA PERSIS kayak yang udah kebukti jalan di migrasi #029
-- (get_karyawan_by_author) dan #030 (get_all_karyawan_author): LEFT JOIN ke "paswordTbl"
-- by "Id" (yang "IsActive" = TRUE), gabung (concat) Author dari "karyawanTbl" DAN semua
-- baris "paswordTbl" yang match jadi satu string, dipisah ", ". Gak ada JOIN yang
-- ngubah/hapus apa pun, murni nambah sumber baca -- field lain (nama, descriptor, fotoUrl,
-- digitalPin, kualifikasi, dst) semuanya tetap identik kayak sebelumnya.
--
-- Setelah migrasi ini jalan, tag Author yang ditambah lewat form "Edit Karyawan" Fusion4
-- ATAUPUN lewat UPDATE SQL manual ke karyawanTbl -- dua-duanya bakal langsung kebaca di
-- semua modul HSSE-Fusion4, gak perlu lagi UPDATE manual tambahan kayak kasus CRV/Hairani.
-- =====================================================================================

-- -------------------------------------------------------------------------------------
-- 1. get_all_face_data() -- dipakai Scan Wajah & Input PIN
-- -------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_all_face_data()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $function$
DECLARE
    v_result JSONB;
BEGIN
    WITH pw AS (
        SELECT "Id", string_agg(DISTINCT TRIM("Author"), ', ') AS all_author
        FROM "paswordTbl"
        WHERE "IsActive" = TRUE AND "Author" IS NOT NULL AND TRIM("Author") <> ''
        GROUP BY "Id"
    )
    SELECT COALESCE(
        jsonb_agg(
            jsonb_build_object(
                'qrCodeId', UPPER(TRIM(f."QrCodeId")),
                'nama', COALESCE(k."NamaPersonnel", f."Nama", f."QrCodeId"),
                'descriptor', f."Descriptor",
                'fotoUrl', COALESCE(f."FotoURL", k."FotoURL", ''),
                'digitalPin', k."DigitalPIN",
                'author', NULLIF(TRIM(BOTH ', ' FROM CONCAT_WS(', ', NULLIF(TRIM(k."Author"), ''), pw.all_author)), ''),
                'kualifikasi', k."Kualifikasi"
            )
        ),
        '[]'::JSONB
    )
    INTO v_result
    FROM "faceData" f
    LEFT JOIN "karyawanTbl" k ON UPPER(TRIM(k."QrCodeId")) = UPPER(TRIM(f."QrCodeId"))
    LEFT JOIN pw ON pw."Id" = k."Id"
    WHERE f."Descriptor" IS NOT NULL;

    RETURN v_result;
END;
$function$;

-- -------------------------------------------------------------------------------------
-- 2. get_person_face_data(p_qrcode) -- dipakai Scan QR Code
-- -------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_person_face_data(p_qrcode text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
    v_kar RECORD;
    v_face RECORD;
    v_author TEXT;
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

    -- Gabung Author dari karyawanTbl + semua baris paswordTbl yang match Id-nya (aktif aja).
    SELECT NULLIF(TRIM(BOTH ', ' FROM CONCAT_WS(', ', NULLIF(TRIM(v_kar."Author"), ''), string_agg(DISTINCT TRIM(p."Author"), ', '))), '')
    INTO v_author
    FROM "paswordTbl" p
    WHERE p."Id" = v_kar."Id" AND p."IsActive" = TRUE AND p."Author" IS NOT NULL AND TRIM(p."Author") <> '';

    RETURN jsonb_build_object(
        'status', 'OK',
        'valid', TRUE,
        'found', (v_face."Descriptor" IS NOT NULL),
        'descriptor', v_face."Descriptor",
        'qrCodeId', v_kar."QrCodeId",
        'nama', v_kar."NamaPersonnel",
        'kualifikasi', v_kar."Kualifikasi",
        'fotoUrl', COALESCE(v_face."FotoURL", v_kar."FotoURL", ''),
        'author', v_author,
        'digitalPin', v_kar."DigitalPIN",
        'person', jsonb_build_object(
            'nama', v_kar."NamaPersonnel",
            'qrCodeId', v_kar."QrCodeId",
            'kualifikasi', v_kar."Kualifikasi",
            'fotoUrl', COALESCE(v_face."FotoURL", v_kar."FotoURL", ''),
            'descriptor', v_face."Descriptor",
            'author', v_author,
            'digitalPin', v_kar."DigitalPIN"
        ),
        'authReq', jsonb_build_object(
            'needAuth', COALESCE(v_kar."AuthCheck", FALSE)
        )
    );
END;
$function$;

-- -------------------------------------------------------------------------------------
-- 3. Cek hasilnya (opsional) -- ganti '%CRV%' sesuai nama yang mau dicek.
-- -------------------------------------------------------------------------------------
-- SELECT jsonb_pretty(elem) FROM jsonb_array_elements(get_all_face_data()) elem
-- WHERE elem->>'nama' ILIKE '%CRV%';
--
-- SELECT get_person_face_data('QRCODE_NYA_DI_SINI');
