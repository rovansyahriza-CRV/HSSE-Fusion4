-- =====================================================================================
-- MIGRASI #25: FIX get_all_face_data() SUPAYA IKUT BALIKIN kualifikasi (buat Jabatan)
-- Jalankan di Supabase project FUSION4 (BUKAN HSSE-Fusion4!) -- sama kayak migrasi #8
-- dan #21, ini nyentuh Fusion4 karena field yang dibutuhin (Kualifikasi) cuma ada di sana.
--
-- Kenapa perlu: kolom "Jabatan" di tabel Daftar Peserta HSE Meeting (hse-meeting-pdf.html
-- & hse-meeting-list.html) selalu kosong ("-") buat peserta yang absen pakai Scan Wajah
-- atau Input PIN. Ternyata BUKAN karena data Kualifikasi-nya kosong di Fusion4 -- tapi
-- karena get_all_face_data() (dipakai buat identifikasi Wajah & PIN di seluruh
-- HSSE-Fusion4) SELAMA INI cuma balikin qrCodeId/nama/descriptor/fotoUrl/digitalPin/
-- author -- gak ada "kualifikasi" sama sekali. Makanya getPersonField(..., ['kualifikasi'])
-- di hse-meeting-checkin.html selalu jatuh ke default kosong ''.
-- (Absen lewat Scan QR Code gak kena masalah ini, karena pakai get_person_face_data()
-- yang udah dibenerin duluan di migrasi #21 dan MEMANG udah balikin kualifikasi.)
--
-- Perubahan: nambah 1 field ke output JSON, "kualifikasi", diambil dari "karyawanTbl"
-- yang MEMANG udah di-JOIN di function ini (alias k) -- gak ada JOIN baru, gak ada
-- kolom yang diubah/dihapus. Konsumen lain yang udah pakai RPC ini (kalau ada) gak akan
-- terpengaruh, field lama semua tetap ada persis sama.
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
                'author', k."Author",
                'kualifikasi', k."Kualifikasi"
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
