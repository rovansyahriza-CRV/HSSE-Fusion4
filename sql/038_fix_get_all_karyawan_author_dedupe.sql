-- =====================================================================================
-- MIGRASI #38: FIX get_all_karyawan_author() -- DEDUPE tag Author, bukan cuma gabung string
-- Jalankan di Supabase project FUSION4 (BUKAN HSSE-Fusion4!), sama kayak migrasi
-- #008/#021/#025/#028/#029/#030/#036 -- ini nyentuh karyawanTbl & paswordTbl.
-- READ-ONLY: cuma redefine 1 RPC baca-saja (SELECT), gak ada perubahan data sama sekali.
--
-- Kenapa perlu: begitu migrasi #036 dijalankan (get_all_face_data/get_person_face_data
-- ikut baca paswordTbl), ketauan efek samping di get_all_karyawan_author() (migrasi #030,
-- dipakai buat nampilin kolom "Author" di TTD Digital & Riwayat Proses semua modul lewat
-- authorFor()) -- kalau seseorang KEBETULAN punya tag Author yang SAMA PERSIS di
-- karyawanTbl.Author DAN paswordTbl.Author (misal karena pernah di-fix manual via SQL
-- langsung ke karyawanTbl, PADAHAL tag itu juga udah ada di paswordTbl dari form Edit
-- Karyawan Fusion4), teksnya kegabung 2x jadi dobel-dobel, contoh:
-- "Verifikasi Cermat, Investigate Incident/Accident, Permit & JSA, Verifikasi Cermat,
-- Investigate Incident/Accident, Permit & JSA" -- kejadian ke Anelka Bugihadinata Hariyono
-- di Riwayat Proses PTW. Sebabnya: query lama CONCAT_WS gabung 2 STRING UTUH
-- (karyawanTbl.Author sama hasil string_agg(DISTINCT ...) dari paswordTbl) -- dedupe-nya
-- cuma di level STRING PERSIS SAMA, bukan di level TAG INDIVIDUAL, jadi kalau ternyata
-- ada satu tag yang muncul di kedua sumber, tetep kebawa dobel pas digabung.
--
-- Perubahan: sekarang PECAH dulu Author dari SEMUA sumber (karyawanTbl.Author + semua
-- baris paswordTbl.Author yang aktif) jadi tag-tag individual (split by koma, trim),
-- kumpulin ke satu SET pakai array_agg(DISTINCT ...), baru digabung lagi jadi 1 string --
-- jadi tag yang sama dari sumber manapun cuma keitung/tampil sekali.
-- =====================================================================================

CREATE OR REPLACE FUNCTION public.get_all_karyawan_author()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $function$
DECLARE
    v_result JSONB;
BEGIN
    WITH kar_tags AS (
        SELECT k."Id", array_agg(DISTINCT TRIM(tag)) FILTER (WHERE TRIM(tag) <> '') AS tags
        FROM "karyawanTbl" k
        LEFT JOIN LATERAL unnest(string_to_array(COALESCE(k."Author", ''), ',')) AS tag ON TRUE
        GROUP BY k."Id"
    ),
    pw_tags AS (
        SELECT p."Id", array_agg(DISTINCT TRIM(tag)) FILTER (WHERE TRIM(tag) <> '') AS tags
        FROM "paswordTbl" p
        LEFT JOIN LATERAL unnest(string_to_array(COALESCE(p."Author", ''), ',')) AS tag ON TRUE
        WHERE p."IsActive" = TRUE
        GROUP BY p."Id"
    )
    SELECT COALESCE(
        jsonb_agg(
            jsonb_build_object(
                'qrCodeId', UPPER(TRIM(k."QrCodeId")),
                'nama', k."NamaPersonnel",
                'author', (
                    SELECT NULLIF(string_agg(DISTINCT t, ', '), '')
                    FROM unnest(COALESCE(kt.tags, ARRAY[]::text[]) || COALESCE(pw.tags, ARRAY[]::text[])) AS t
                )
            )
        ),
        '[]'::JSONB
    )
    INTO v_result
    FROM "karyawanTbl" k
    LEFT JOIN kar_tags kt ON kt."Id" = k."Id"
    LEFT JOIN pw_tags pw ON pw."Id" = k."Id";

    RETURN v_result;
END;
$function$;

-- Cek hasilnya (opsional) -- ganti '%Anelka%' sesuai nama yang mau dicek, Author-nya
-- harusnya udah gak dobel lagi.
-- SELECT nama, author FROM jsonb_to_recordset(get_all_karyawan_author())
--   AS x(nama TEXT, author TEXT) WHERE nama ILIKE '%Anelka%';
