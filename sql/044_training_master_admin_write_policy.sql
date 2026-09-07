-- =====================================================================================
-- HSSE-Fusion4 - MIGRASI #44: TRAINING/POSITION MASTER ADMIN WRITE POLICY
-- Jalankan setelah sql/043_training_matrix_anon_write_policy.sql.
--
-- GitHub Pages menggunakan publishable/anon client. Author "Training Matrix Admin"
-- tetap diverifikasi di sisi client sebelum operasi admin, mengikuti modul existing.
-- =====================================================================================

ALTER TABLE "trainingMasterTbl" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "positionMasterTbl" ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "training_master_public_insert" ON "trainingMasterTbl";
CREATE POLICY "training_master_public_insert"
    ON "trainingMasterTbl" FOR INSERT TO anon, authenticated WITH CHECK (TRUE);

DROP POLICY IF EXISTS "training_master_public_update" ON "trainingMasterTbl";
CREATE POLICY "training_master_public_update"
    ON "trainingMasterTbl" FOR UPDATE TO anon, authenticated USING (TRUE) WITH CHECK (TRUE);

DROP POLICY IF EXISTS "position_master_public_insert" ON "positionMasterTbl";
CREATE POLICY "position_master_public_insert"
    ON "positionMasterTbl" FOR INSERT TO anon, authenticated WITH CHECK (TRUE);

DROP POLICY IF EXISTS "position_master_public_update" ON "positionMasterTbl";
CREATE POLICY "position_master_public_update"
    ON "positionMasterTbl" FOR UPDATE TO anon, authenticated USING (TRUE) WITH CHECK (TRUE);

GRANT SELECT, INSERT, UPDATE ON "trainingMasterTbl", "positionMasterTbl" TO anon, authenticated;
