-- =====================================================================================
-- MIGRASI #29: FIX get_karyawan_by_author() -- IKUT BACA "paswordTbl", BUKAN CUMA karyawanTbl
-- Jalankan di Supabase project FUSION4 (BUKAN HSSE-Fusion4!), sama kayak migrasi
-- #008/#021/#025/#028 -- ini nyentuh Fusion4 karena karyawanTbl & paswordTbl cuma ada di sana.
-- READ-ONLY: cuma bikin RPC baca-saja (SELECT), gak ada perubahan data sama sekali.
--
-- Kenapa perlu: migrasi #028 bikin get_karyawan_by_author() baca tag Author LANGSUNG dari
-- "karyawanTbl"."Author". Ternyata itu gak lengkap -- di Fusion4 ada tabel terpisah namanya
-- "paswordTbl" (perhatiin, cuma 1 huruf "s") yang isinya BANYAK baris per orang (satu
-- "Id" yang sama muncul berkali-kali), tiap baris nyimpen kombinasi tag Author yang beda.
-- Kesimpulannya: tag Author seseorang itu gabungan (union) dari SEMUA baris "paswordTbl"
-- yang "Id"-nya sama dengan "karyawanTbl"."Id" milik orang itu (yang "IsActive" = true),
-- DITAMBAH kolom "karyawanTbl"."Author" itu sendiri (buat kompatibel sama tag yang
-- kepatch manual lewat SQL sebelumnya, misalnya punya CRV).
--
-- Perubahan: get_karyawan_by_author() sekarang LEFT JOIN ke "paswordTbl" p ON p."Id" =
-- k."Id" AND p."IsActive" = TRUE, terus cek "Author" ILIKE di DUA-duanya (karyawanTbl.Author
-- ATAU paswordTbl.Author). Gak ada JOIN yang ngubah/hapus apa pun, murni nambah sumber baca.
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
                'nama', sub."NamaPersonnel",
                'qrCodeId', UPPER(TRIM(sub."QrCodeId"))
            ) ORDER BY sub."NamaPersonnel"
        ),
        '[]'::JSONB
    )
    INTO v_result
    FROM (
        SELECT DISTINCT k."NamaPersonnel", k."QrCodeId"
        FROM "karyawanTbl" k
        LEFT JOIN "paswordTbl" p ON p."Id" = k."Id" AND p."IsActive" = TRUE
        WHERE k."Author" ILIKE '%' || p_author_tag || '%'
           OR p."Author" ILIKE '%' || p_author_tag || '%'
    ) sub;

    RETURN v_result;
END;
$function$;
