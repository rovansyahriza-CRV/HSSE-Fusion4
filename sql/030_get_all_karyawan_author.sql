-- =====================================================================================
-- MIGRASI #30: RPC BARU get_all_karyawan_author() -- DAFTAR SEMUA ORANG + Author GABUNGAN
-- Jalankan di Supabase project FUSION4 (BUKAN HSSE-Fusion4!), sama kayak migrasi
-- #008/#021/#025/#028/#029.
-- READ-ONLY: cuma bikin RPC baca-saja (SELECT), gak ada perubahan data sama sekali.
--
-- Kenapa perlu: mau nampilin kolom "Author" di tabel/list peserta di berbagai modul
-- (HSE Meeting, TBM, PTW, Inspeksi, CERMAT, Incident, Internal Audit) -- biar keliatan
-- siapa yang punya izin apa. Daripada tiap halaman manggil RPC beda-beda per orang,
-- RPC ini balikin SEKALIGUS daftar semua karyawan + Author gabungan-nya (dari
-- karyawanTbl.Author DAN paswordTbl.Author, digabung kayak di get_karyawan_by_author()
-- migrasi #029) dalam SEKALI panggilan -- tiap halaman tinggal load sekali terus
-- lookup by qrCodeId di JS.
-- =====================================================================================

CREATE OR REPLACE FUNCTION public.get_all_karyawan_author()
RETURNS JSONB
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
                'qrCodeId', UPPER(TRIM(k."QrCodeId")),
                'nama', k."NamaPersonnel",
                'author', NULLIF(TRIM(BOTH ', ' FROM CONCAT_WS(', ', NULLIF(TRIM(k."Author"), ''), pw.all_author)), '')
            )
        ),
        '[]'::JSONB
    )
    INTO v_result
    FROM "karyawanTbl" k
    LEFT JOIN pw ON pw."Id" = k."Id";

    RETURN v_result;
END;
$function$;
