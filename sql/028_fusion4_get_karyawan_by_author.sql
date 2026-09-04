-- =====================================================================================
-- MIGRASI #28: RPC BARU get_karyawan_by_author() -- DAFTAR KARYAWAN BY AUTHOR TAG
-- Jalankan di Supabase project FUSION4 (BUKAN HSSE-Fusion4!), sama kayak migrasi
-- #008/#021/#025 -- ini nyentuh Fusion4 karena karyawanTbl cuma ada di sana.
-- READ-ONLY: cuma bikin RPC baca-saja (SELECT), gak ada perubahan data sama sekali.
--
-- Kenapa perlu: Tim Auditor di audit-report.html tadinya pakai roster dari
-- get_all_face_data(), tapi RPC itu SUMBERNYA dari tabel "faceData" -- jadi cuma
-- nampilin orang yang UDAH PERNAH daftar wajah. Auditor yang cuma terdaftar QR/PIN
-- tanpa pernah scan wajah jadi gak pernah muncul, walaupun Author tag-nya udah bener.
--
-- get_karyawan_by_author() ini baca LANGSUNG dari "karyawanTbl" (bukan lewat "faceData"),
-- jadi nangkep SEMUA karyawan yang punya tag itu di kolom "Author", apapun metode
-- identifikasinya (QR/Wajah/PIN).
-- =====================================================================================

CREATE OR REPLACE FUNCTION public.get_karyawan_by_author(p_author_tag TEXT)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $function$
DECLARE
    v_result JSONB;
BEGIN
    SELECT COALESCE(
        jsonb_agg(
            jsonb_build_object(
                'nama', "NamaPersonnel",
                'qrCodeId', UPPER(TRIM("QrCodeId"))
            ) ORDER BY "NamaPersonnel"
        ),
        '[]'::JSONB
    )
    INTO v_result
    FROM "karyawanTbl"
    WHERE "Author" ILIKE '%' || p_author_tag || '%';

    RETURN v_result;
END;
$function$;
