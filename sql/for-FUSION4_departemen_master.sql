-- =====================================================================================
-- PENTING: file ini jalanin di project FUSION4 (nhmpwjriextmbotmvvbu.supabase.co),
-- BUKAN di HSSE-Fusion4! Makanya nama filenya beda sendiri (bukan format 00X biasa),
-- biar gak ketuker pas kamu buka folder sql/.
--
-- Tujuan: bikin SATU sumber kebenaran untuk nama Divisi & Departemen, dipakai bareng
-- oleh Fusion4 sendiri, SMMS, dan HSSE-Fusion4 (baca-saja lewat RPC di bawah) -- biar
-- penamaan Dept selalu SERAGAM di semua sistem, gak ada lagi yang diketik manual beda
-- -beda di tiap tempat (misal "Equipment" vs "equipment" vs "Divisi Equipment").
--
-- Isi awal diambil dari struktur Divisi/Departemen yang kamu kasih:
--   Finance          -> Accounts Receivable (AR), Treasury & Cash Management,
--                        Financial Planning & Analysis (FP&A),
--                        Accounting & Financial Reporting, Taxation (Perpajakan),
--                        Payroll (Penggajian)
--   Operation        -> Engineering, HSE, Project Control, Project, QAC,
--                        Business Development
--   Human Resources  -> Talent Acquisition / Recruitment,
--                        Compensation & Benefits (CompBen),
--                        Learning & Development (L&D), Employee Relations (ER),
--                        Performance Management, HR Operations / HR Admin
--
-- Kalau ada Divisi/Departemen lain yang belum kesebut, tinggal INSERT baris baru
-- lewat Table Editor atau nambah VALUES di bawah nanti.
-- =====================================================================================

CREATE TABLE IF NOT EXISTS "departemenTbl" (
    "Id" BIGSERIAL PRIMARY KEY,
    "Divisi" TEXT NOT NULL,
    "NamaDept" TEXT NOT NULL,
    "Status" TEXT NOT NULL DEFAULT 'Aktif' CHECK ("Status" IN ('Aktif', 'Non-Aktif')),
    "CreatedAt" TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE ("Divisi", "NamaDept")
);

INSERT INTO "departemenTbl" ("Divisi", "NamaDept") VALUES
    ('Finance', 'Accounts Receivable (AR)'),
    ('Finance', 'Treasury & Cash Management'),
    ('Finance', 'Financial Planning & Analysis (FP&A)'),
    ('Finance', 'Accounting & Financial Reporting'),
    ('Finance', 'Taxation (Perpajakan)'),
    ('Finance', 'Payroll (Penggajian)'),
    ('Operation', 'Engineering'),
    ('Operation', 'HSE'),
    ('Operation', 'Project Control'),
    ('Operation', 'Project'),
    ('Operation', 'QAC'),
    ('Operation', 'Business Development'),
    ('Human Resources', 'Talent Acquisition / Recruitment'),
    ('Human Resources', 'Compensation & Benefits (CompBen)'),
    ('Human Resources', 'Learning & Development (L&D)'),
    ('Human Resources', 'Employee Relations (ER)'),
    ('Human Resources', 'Performance Management'),
    ('Human Resources', 'HR Operations / HR Admin')
ON CONFLICT ("Divisi", "NamaDept") DO NOTHING;


-- -------------------------------------------------------------------------------------
-- RPC baca-saja -- aman dipanggil dari HSSE-Fusion4 pakai publishable/anon key yang
-- sama kayak get_all_face_data(). Gak ada tulis-menulis ke tabel apa pun selain baca.
-- -------------------------------------------------------------------------------------
DROP FUNCTION IF EXISTS get_departemen_list();
CREATE OR REPLACE FUNCTION get_departemen_list()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_result JSONB;
BEGIN
    SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'id', "Id",
        'divisi', "Divisi",
        'namaDept', "NamaDept"
    ) ORDER BY "Divisi", "NamaDept"), '[]'::JSONB)
    INTO v_result
    FROM "departemenTbl"
    WHERE "Status" = 'Aktif';

    RETURN v_result;
END;
$$;
