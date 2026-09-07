-- =====================================================================================
-- HSSE-Fusion4 - MIGRASI #43: TRAINING MATRIX CLIENT-WRITE POLICY
-- Jalankan setelah sql/042_hse_program_training_master_alignment.sql.
--
-- Modul GitHub Pages memakai publishable/anon Supabase client dan melakukan verifikasi
-- Author Fusion4 di sisi client, sama seperti modul HSSE existing. Karena itu policy
-- matrix perlu mengizinkan anon untuk membaca dan menyimpan status setelah verifikasi
-- tersebut; tidak ada credential/service_role baru yang dipakai.
-- =====================================================================================

ALTER TABLE "trainingMatrixTbl" ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "training_matrix_public_read" ON "trainingMatrixTbl";
CREATE POLICY "training_matrix_public_read"
    ON "trainingMatrixTbl"
    FOR SELECT
    TO anon, authenticated
    USING (TRUE);

DROP POLICY IF EXISTS "training_matrix_public_insert" ON "trainingMatrixTbl";
CREATE POLICY "training_matrix_public_insert"
    ON "trainingMatrixTbl"
    FOR INSERT
    TO anon, authenticated
    WITH CHECK (TRUE);

DROP POLICY IF EXISTS "training_matrix_public_update" ON "trainingMatrixTbl";
CREATE POLICY "training_matrix_public_update"
    ON "trainingMatrixTbl"
    FOR UPDATE
    TO anon, authenticated
    USING (TRUE)
    WITH CHECK (TRUE);

GRANT SELECT, INSERT, UPDATE ON "trainingMatrixTbl" TO anon, authenticated;
