-- =====================================================================================
-- HSSE-Fusion4 — MIGRASI #8: FIX get_all_face_data() SUPAYA IKUT BALIKIN digitalPin & author
-- Jalankan di Supabase project FUSION4 (BUKAN HSSE-Fusion4!) — ini satu-satunya migrasi
-- yang nyentuh Fusion4, karena field yang dibutuhin (DigitalPIN & Author) memang cuma ada
-- di database Fusion4 (tabel "karyawanTbl").
--
-- Kenapa perlu: fitur verifikasi digital "Diperiksa/Disetujui" & "Assign ke Dept" di
-- HSSE-Fusion4 (cermat-list.html) butuh cek PIN & tag Author orang yang scan wajah/input
-- PIN. Sebelum migrasi ini, get_all_face_data() cuma balikin qrCodeId/nama/descriptor/
-- fotoUrl -- makanya verifikasi PIN selalu gagal ("PIN tidak dikenali").
--
-- Perubahan: nambah 2 field ke output JSON, "digitalPin" & "author", diambil dari
-- "karyawanTbl" yang MEMANG udah di-JOIN di function ini (alias k) -- gak ada JOIN baru,
-- gak ada tabel/kolom yang diubah/dihapus. Konsumen lain yang udah pakai RPC ini (kalau
-- ada) gak akan terpengaruh, karena field lama semua tetap ada persis sama.
-- =====================================================================================

CREATE OR REPLACE FUNCTION public.get_all_face_data()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $function$
DECLARE
    v_result JSONB;
BEGIN
    SELECT COALESCE(
        jsonb_agg(
            jsonb_build_object(
                'qrCodeId', UPPER(TRIM(f."QrCodeId")),
                'nama', COALESCE(k."NamaPersonnel", f."Nama", f."QrCodeId"),
                'descriptor', f."Descriptor",
                'fotoUrl', COALESCE(f."FotoURL", k."FotoURL", ''),
                'digitalPin', k."DigitalPIN",
                'author', k."Author"
            )
        ),
        '[]'::JSONB
    )
    INTO v_result
    FROM "faceData" f
    LEFT JOIN "karyawanTbl" k ON UPPER(TRIM(k."QrCodeId")) = UPPER(TRIM(f."QrCodeId"))
    WHERE f."Descriptor" IS NOT NULL;

    RETURN v_result;
END;
$function$;
