-- =====================================================================================
-- HSSE-Fusion4 - MIGRASI #42: ALIGN HSE PROGRAM TRAINING MASTER
-- Jalankan setelah sql/041_training_matrix_schema.sql.
--
-- HSE Program tetap mempertahankan perilaku existing: item training adalah item MANUAL
-- yang dapat di-toggle Use/N/A dan diisi target/realisasi bulanan. Migrasi ini hanya
-- menyamakan daftar generic Training & Kompetensi dengan trainingMasterTbl:
-- Safety Induction, MCU, HSSE Culture Training, First Aid / P3K, Fire Fighting,
-- Working at Height, Confined Space, Lifting & Rigging, Electrical Safety / LOTO,
-- dan SIA/SIO Alat Berat. DDT (Defensive Driving Training) tetap dipertahankan
-- sebagai item tambahan HSE Program, sehingga total generic training HSE Program
-- menjadi 11 item.
--
-- Item lama yang sudah dipakai hseProgramTbl tidak dihapus langsung. Kode
-- SERTIFIKASI_KOMPETENSI dipindahkan ke item SIA/SIO agar target/realisasi
-- project-tahun tetap aman. DDT dipertahankan sebagai item tambahan. Seed dibuat
-- idempotent.
-- =====================================================================================

-- -------------------------------------------------------------------------------------
-- 1. Pastikan kolom grouping/realisasi dari migrasi #39 tersedia
-- -------------------------------------------------------------------------------------
ALTER TABLE "hseProgramMasterItemTbl"
    ADD COLUMN IF NOT EXISTS "Kategori" TEXT NOT NULL DEFAULT 'Lainnya';
ALTER TABLE "hseProgramMasterItemTbl"
    ADD COLUMN IF NOT EXISTS "SumberRealisasi" TEXT NOT NULL DEFAULT 'OTOMATIS'
        CHECK ("SumberRealisasi" IN ('OTOMATIS', 'MANUAL'));

-- -------------------------------------------------------------------------------------
-- 2. Tambahkan item yang belum ada, memakai kode trainingMasterTbl yang sama
-- -------------------------------------------------------------------------------------
INSERT INTO "hseProgramMasterItemTbl"
    ("KodeItem", "NamaItem", "SatuanTarget", "Urutan", "Kategori", "SumberRealisasi", "Keterangan")
VALUES
    ('SAFETY_INDUCTION', 'Safety Induction', 'kali', 200, 'Training & Kompetensi', 'MANUAL', 'Realisasi diisi manual; selaras dengan trainingMasterTbl'),
    ('MCU', 'MCU (Medical Check-Up)', 'kali', 210, 'Training & Kompetensi', 'MANUAL', 'Realisasi diisi manual; selaras dengan trainingMasterTbl'),
    ('HSSE_CULTURE', 'HSSE Culture Training', 'kali', 220, 'Training & Kompetensi', 'MANUAL', 'Realisasi diisi manual; selaras dengan trainingMasterTbl'),
    ('FIRST_AID_P3K', 'First Aid / P3K', 'kali', 230, 'Training & Kompetensi', 'MANUAL', 'Realisasi diisi manual; selaras dengan trainingMasterTbl'),
    ('FIRE_FIGHTING', 'Fire Fighting', 'kali', 240, 'Training & Kompetensi', 'MANUAL', 'Realisasi diisi manual; selaras dengan trainingMasterTbl'),
    ('WORKING_AT_HEIGHT', 'Working at Height', 'kali', 250, 'Training & Kompetensi', 'MANUAL', 'Realisasi diisi manual; selaras dengan trainingMasterTbl'),
    ('CONFINED_SPACE', 'Confined Space', 'kali', 260, 'Training & Kompetensi', 'MANUAL', 'Realisasi diisi manual; selaras dengan trainingMasterTbl'),
    ('LIFTING_RIGGING', 'Lifting & Rigging', 'kali', 270, 'Training & Kompetensi', 'MANUAL', 'Realisasi diisi manual; selaras dengan trainingMasterTbl'),
    ('ELECTRICAL_LOTO', 'Electrical Safety / LOTO', 'kali', 280, 'Training & Kompetensi', 'MANUAL', 'Realisasi diisi manual; selaras dengan trainingMasterTbl'),
    ('SIA_SIO_HEAVY_EQUIPMENT', 'SIA/SIO Alat Berat', 'kali', 290, 'Training & Kompetensi', 'MANUAL', 'Realisasi diisi manual; selaras dengan trainingMasterTbl'),
    ('DDT', 'Defensive Driving Training (DDT)', 'kali', 300, 'Training & Kompetensi', 'MANUAL', 'Realisasi diisi manual; item tambahan HSE Program di luar Training Matrix')
ON CONFLICT ("KodeItem") DO UPDATE SET
    "NamaItem" = EXCLUDED."NamaItem",
    "SatuanTarget" = EXCLUDED."SatuanTarget",
    "Urutan" = EXCLUDED."Urutan",
    "Kategori" = EXCLUDED."Kategori",
    "SumberRealisasi" = EXCLUDED."SumberRealisasi",
    "Keterangan" = EXCLUDED."Keterangan";

-- -------------------------------------------------------------------------------------
-- 3. Migrate legacy aliases without losing project/year targets or manual realization
-- -------------------------------------------------------------------------------------
DO $$
DECLARE
    v_target_id BIGINT;
    v_legacy_id BIGINT;
BEGIN
    SELECT "Id" INTO v_target_id
    FROM "hseProgramMasterItemTbl"
    WHERE "KodeItem" = 'SIA_SIO_HEAVY_EQUIPMENT';

    FOR v_legacy_id IN
        SELECT "Id"
        FROM "hseProgramMasterItemTbl"
        WHERE "KodeItem" = 'SERTIFIKASI_KOMPETENSI'
    LOOP
        UPDATE "hseProgramTbl" AS hp
        SET "ItemId" = v_target_id,
            "UpdatedAt" = NOW()
        WHERE hp."ItemId" = v_legacy_id
          AND NOT EXISTS (
              SELECT 1
              FROM "hseProgramTbl" AS existing
              WHERE existing."ProjectId" = hp."ProjectId"
                AND existing."Tahun" = hp."Tahun"
                AND existing."ItemId" = v_target_id
          );

        DELETE FROM "hseProgramTbl" AS hp
        WHERE hp."ItemId" = v_legacy_id;

        DELETE FROM "hseProgramMasterItemTbl"
        WHERE "Id" = v_legacy_id;
    END LOOP;
END $$;

-- Normalize the original training rows from migration #39 and keep all shared items
-- in one group. DDT remains an additional, separate HSE Program item.
UPDATE "hseProgramMasterItemTbl"
SET "NamaItem" = CASE "KodeItem"
        WHEN 'SAFETY_INDUCTION' THEN 'Safety Induction'
        WHEN 'MCU' THEN 'MCU (Medical Check-Up)'
        WHEN 'HSSE_CULTURE_TRAINING' THEN 'HSSE Culture Training'
        WHEN 'DDT' THEN 'Defensive Driving Training (DDT)'
        ELSE "NamaItem"
    END,
    "Kategori" = 'Training & Kompetensi',
    "SumberRealisasi" = 'MANUAL'
WHERE "KodeItem" IN ('SAFETY_INDUCTION', 'MCU', 'HSSE_CULTURE_TRAINING');

-- If both old and new HSSE Culture rows existed, retain the canonical row and remove
-- the obsolete one after moving any non-duplicate project/year records.
DO $$
DECLARE
    v_old_id BIGINT;
    v_new_id BIGINT;
BEGIN
    SELECT "Id" INTO v_old_id FROM "hseProgramMasterItemTbl" WHERE "KodeItem" = 'HSSE_CULTURE_TRAINING';
    SELECT "Id" INTO v_new_id FROM "hseProgramMasterItemTbl" WHERE "KodeItem" = 'HSSE_CULTURE';
    IF v_old_id IS NOT NULL AND v_new_id IS NOT NULL THEN
        UPDATE "hseProgramTbl" AS hp
        SET "ItemId" = v_new_id, "UpdatedAt" = NOW()
        WHERE hp."ItemId" = v_old_id
          AND NOT EXISTS (
              SELECT 1 FROM "hseProgramTbl" existing
              WHERE existing."ProjectId" = hp."ProjectId"
                AND existing."Tahun" = hp."Tahun"
                AND existing."ItemId" = v_new_id
          );
        DELETE FROM "hseProgramTbl" WHERE "ItemId" = v_old_id;
        DELETE FROM "hseProgramMasterItemTbl" WHERE "Id" = v_old_id;
    END IF;
END $$;

UPDATE "hseProgramMasterItemTbl"
SET "Kategori" = 'Training & Kompetensi', "SumberRealisasi" = 'MANUAL'
WHERE "KodeItem" IN (
    'SAFETY_INDUCTION', 'MCU', 'HSSE_CULTURE', 'FIRST_AID_P3K',
    'FIRE_FIGHTING', 'WORKING_AT_HEIGHT', 'CONFINED_SPACE',
    'LIFTING_RIGGING', 'ELECTRICAL_LOTO', 'SIA_SIO_HEAVY_EQUIPMENT', 'DDT'
);
