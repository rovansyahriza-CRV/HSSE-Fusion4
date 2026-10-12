-- =====================================================================================
-- MIGRASI #061 (HSSE): man-hours ikut kode project KARYAWAN (TYPE di SmartGate)
-- Jalankan di Supabase project **HSSE-Fusion4**, SETELAH 060.
-- Pasangannya: sql/for-FUSION4_man_hours_rpc.sql versi terbaru di **Fusion4 SmartGate**
-- (get_hsse_man_hours ngisi "KodeProject" dari karyawanTbl."Type"; kalau kosong, dari
-- kode project lokasi). Aman dijalankan ulang (CREATE OR REPLACE).
--
-- Urutan baru penentuan project buat tiap baris man-hours (keputusan CRV 2026-10-12):
--   1. Lokasi diset "Gak dihitung"           -> gak dihitung
--   2. Kode project dari SmartGate (karyawan) -> project HSSE dengan kode itu
--   3. Pemetaan manual lokasi                 -> project pilihan
--   4. Kode project lokasi (KodeSmartGate)    -> project HSSE dengan kode itu
-- Dulu (060) pemetaan manual menang di atas kode; sekarang kode karyawan yang menang.
-- =====================================================================================

CREATE OR REPLACE FUNCTION public.man_hours_project_efektif(p_lokasi TEXT, p_kode TEXT)
RETURNS BIGINT
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT CASE
        WHEN COALESCE(m."Abaikan", FALSE) THEN NULL
        WHEN NULLIF(trim(p_kode), '') IS NOT NULL
             AND EXISTS (SELECT 1 FROM "projectTbl" p WHERE p."KodeOperational" = trim(p_kode))
            THEN (SELECT p."Id" FROM "projectTbl" p WHERE p."KodeOperational" = trim(p_kode) LIMIT 1)
        WHEN m."ProjectId" IS NOT NULL THEN m."ProjectId"
        ELSE (SELECT p."Id" FROM "projectTbl" p WHERE p."KodeOperational" = m."KodeSmartGate" LIMIT 1)
    END
    FROM (SELECT 1) d
    LEFT JOIN "manHoursProjectMapTbl" m ON m."LokasiSmartGate" = trim(p_lokasi);
$$;
REVOKE ALL ON FUNCTION public.man_hours_project_efektif(TEXT, TEXT) FROM PUBLIC, anon, authenticated;

-- -------------------------------------------------------------------------------------
-- CEK (jalanin manual kalau mau):
-- 1. Tarik ulang sekarang (sekalian sinkron project):
--      SELECT public.man_hours_tarik_otomatis(true);
-- 2. Man-hours per kode:
--      SELECT p."KodeOperational", m."Bulan", COALESCE(m."ManHoursKoreksi", m."ManHoursSmartGate") AS mh
--      FROM "manHoursTbl" m JOIN "projectTbl" p ON p."Id" = m."ProjectId"
--      WHERE m."Tahun" = 2026 ORDER BY 1, 2;
-- -------------------------------------------------------------------------------------
