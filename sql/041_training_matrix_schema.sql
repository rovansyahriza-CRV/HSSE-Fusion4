-- =====================================================================================
-- HSSE-Fusion4 - MIGRASI #41: TRAINING MATRIX & TRAINING RECORDS
-- Jalankan setelah sql/040_jsa_risk_assessment.sql di project HSSE-Fusion4.
--
-- Catatan penting:
-- * "Fusion4KaryawanId" adalah referensi lintas project ke Fusion4."karyawanTbl"."Id".
--   Tidak dibuat FOREIGN KEY karena tabel karyawan berada di project Supabase lain.
-- * Posisi dan training di bawah adalah master HSSE-Fusion4, bukan salinan employee rows.
-- * Seed matrix memakai asumsi kerja dari matrix yang disuplai: semua posisi wajib mengikuti
--   induction, MCU, budaya HSSE, dan fire fighting; pelatihan teknis hanya diwajibkan atau
--   dikondisikan untuk posisi yang relevan. Kombinasi lain sengaja disimpan sebagai N/A.
-- =====================================================================================

-- -------------------------------------------------------------------------------------
-- 1. MASTER TRAINING
-- -------------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS "trainingMasterTbl" (
    "Id" BIGSERIAL PRIMARY KEY,
    "KodeTraining" TEXT NOT NULL UNIQUE,
    "NamaTraining" TEXT NOT NULL UNIQUE,
    "Deskripsi" TEXT NOT NULL DEFAULT '',
    "TargetPeserta" TEXT NOT NULL DEFAULT '',
    "FrekuensiBerlaku" TEXT NOT NULL DEFAULT '',
    "Penyedia" TEXT NOT NULL DEFAULT '',
    "IsActive" BOOLEAN NOT NULL DEFAULT TRUE,
    "Urutan" INT NOT NULL DEFAULT 0,
    "CreatedAt" TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    "UpdatedAt" TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

INSERT INTO "trainingMasterTbl"
    ("KodeTraining", "NamaTraining", "Deskripsi", "TargetPeserta", "FrekuensiBerlaku", "Penyedia", "IsActive", "Urutan")
VALUES
    ('SAFETY_INDUCTION', 'Safety Induction', 'Pengenalan aturan HSSE, bahaya, dan tata tertib kerja/project.', 'Seluruh pekerja, tamu, dan personel baru sebelum mulai bekerja.', 'Saat onboarding dan refresh sesuai kebutuhan project.', 'Internal HSSE / Project', TRUE, 10),
    ('MCU', 'MCU (Medical Check-Up)', 'Pemeriksaan kesehatan untuk memastikan fitness to work.', 'Seluruh pekerja sesuai ketentuan perusahaan/project.', 'Sesuai program MCU dan masa berlaku hasil pemeriksaan.', 'Klinik/rumah sakit/provider kesehatan resmi', TRUE, 20),
    ('HSSE_CULTURE', 'HSSE Culture Training', 'Pembentukan perilaku, kepemimpinan, dan budaya HSSE.', 'Seluruh pekerja dan pimpinan project.', 'Tahunan atau saat program budaya HSSE diperbarui.', 'Internal HSSE / provider kompeten', TRUE, 30),
    ('FIRST_AID_P3K', 'First Aid / P3K', 'Pertolongan pertama pada kecelakaan dan kondisi darurat medis.', 'Petugas P3K, medic, supervisor, dan personel yang ditunjuk.', 'Sesuai masa berlaku sertifikat atau refresh provider.', 'Provider P3K/medis kompeten', TRUE, 40),
    ('FIRE_FIGHTING', 'Fire Fighting', 'Pencegahan dan penanggulangan kebakaran serta penggunaan APAR.', 'Seluruh pekerja dan personel tanggap darurat.', 'Tahunan atau sesuai ketentuan project.', 'Internal HSSE / provider fire safety', TRUE, 50),
    ('WORKING_AT_HEIGHT', 'Working at Height', 'Pengendalian risiko pekerjaan di ketinggian dan penggunaan fall protection.', 'Personel yang bekerja atau mengawasi pekerjaan di ketinggian.', 'Sesuai masa berlaku sertifikat dan refresh requirement.', 'Provider kerja di ketinggian kompeten', TRUE, 60),
    ('CONFINED_SPACE', 'Confined Space', 'Pengenalan bahaya, izin masuk, gas test, dan rescue ruang terbatas.', 'Personel yang masuk, menjaga, mengawasi, atau merescue dari ruang terbatas.', 'Sesuai masa berlaku sertifikat dan refresh requirement.', 'Provider confined space kompeten', TRUE, 70),
    ('LIFTING_RIGGING', 'Lifting & Rigging', 'Perencanaan pengangkatan, inspeksi rigging, dan komunikasi lifting.', 'Rigger, operator, supervisor, dan personel lifting terkait.', 'Sesuai masa berlaku sertifikat dan refresh requirement.', 'Provider lifting kompeten', TRUE, 80),
    ('ELECTRICAL_LOTO', 'Electrical Safety / LOTO', 'Keselamatan listrik, isolasi energi, dan lockout/tagout.', 'Electrician, mechanic, supervisor, dan personel berwenang.', 'Sesuai masa berlaku sertifikat dan refresh requirement.', 'Provider electrical safety kompeten', TRUE, 90),
    ('SIA_SIO_HEAVY_EQUIPMENT', 'SIA/SIO Alat Berat', 'Kompetensi dan izin operator alat berat sesuai jenis alat.', 'Operator alat berat dan personel yang diwajibkan oleh regulasi.', 'Sesuai masa berlaku SIA/SIO dan ketentuan regulator.', 'Lembaga/provider sertifikasi berwenang', TRUE, 100)
ON CONFLICT ("KodeTraining") DO UPDATE SET
    "NamaTraining" = EXCLUDED."NamaTraining",
    "Deskripsi" = EXCLUDED."Deskripsi",
    "TargetPeserta" = EXCLUDED."TargetPeserta",
    "FrekuensiBerlaku" = EXCLUDED."FrekuensiBerlaku",
    "Penyedia" = EXCLUDED."Penyedia",
    "IsActive" = EXCLUDED."IsActive",
    "Urutan" = EXCLUDED."Urutan",
    "UpdatedAt" = NOW();

-- -------------------------------------------------------------------------------------
-- 2. MASTER POSISI (bukan employee master dari project Fusion4)
-- -------------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS "positionMasterTbl" (
    "Id" BIGSERIAL PRIMARY KEY,
    "NamaPosisi" TEXT NOT NULL UNIQUE,
    "Kategori" TEXT NOT NULL DEFAULT 'Field/Project Team'
        CHECK ("Kategori" IN ('Head Office', 'Project Team', 'Field/Project Team')),
    "IsActive" BOOLEAN NOT NULL DEFAULT TRUE,
    "Urutan" INT NOT NULL DEFAULT 0,
    "CreatedAt" TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    "UpdatedAt" TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

INSERT INTO "positionMasterTbl" ("NamaPosisi", "Kategori", "Urutan") VALUES
    ('Head Office', 'Head Office', 10),
    ('Project Management Team', 'Project Team', 20),
    ('Supervisor', 'Project Team', 30),
    ('Foreman', 'Project Team', 40),
    ('Medic', 'Field/Project Team', 50),
    ('Safetyman', 'Field/Project Team', 60),
    ('Rigger', 'Field/Project Team', 70),
    ('Welder', 'Field/Project Team', 80),
    ('Fitter', 'Field/Project Team', 90),
    ('Blaster', 'Field/Project Team', 100),
    ('Painter', 'Field/Project Team', 110),
    ('Scaffolder', 'Field/Project Team', 120),
    ('Operator Heavy Equipment', 'Field/Project Team', 130),
    ('HSE Officer / Safety Man', 'Field/Project Team', 140),
    ('Electrician', 'Field/Project Team', 150),
    ('Mechanic', 'Field/Project Team', 160),
    ('Mason', 'Field/Project Team', 170),
    ('Carpenter', 'Field/Project Team', 180),
    ('Security', 'Field/Project Team', 190),
    ('Helper / General Worker', 'Field/Project Team', 200),
    ('Driver', 'Field/Project Team', 210)
ON CONFLICT ("NamaPosisi") DO UPDATE SET
    "Kategori" = EXCLUDED."Kategori",
    "IsActive" = EXCLUDED."IsActive",
    "Urutan" = EXCLUDED."Urutan",
    "UpdatedAt" = NOW();

-- -------------------------------------------------------------------------------------
-- 3. MATRIX POSISI x TRAINING (satu baris per kombinasi, bukan training columns)
-- -------------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS "trainingMatrixTbl" (
    "Id" BIGSERIAL PRIMARY KEY,
    "PositionId" BIGINT NOT NULL REFERENCES "positionMasterTbl"("Id") ON DELETE CASCADE,
    "TrainingId" BIGINT NOT NULL REFERENCES "trainingMasterTbl"("Id") ON DELETE CASCADE,
    "RequirementStatus" TEXT NOT NULL DEFAULT 'N/A'
        CHECK ("RequirementStatus" IN ('Wajib', 'Kondisional', 'N/A')),
    "Catatan" TEXT NOT NULL DEFAULT '',
    "CreatedAt" TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    "UpdatedAt" TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT "trainingMatrixTbl_position_training_key" UNIQUE ("PositionId", "TrainingId")
);

CREATE INDEX IF NOT EXISTS idx_training_matrix_position ON "trainingMatrixTbl" ("PositionId");
CREATE INDEX IF NOT EXISTS idx_training_matrix_training ON "trainingMatrixTbl" ("TrainingId");

-- Daftar berikut adalah pengecualian dari default N/A. Cross join di bawah tetap
-- membuat seluruh 21 x 10 kombinasi sehingga matrix selalu lengkap dan mudah diedit.
WITH "Required" ("KodeTraining", "NamaPosisi", "RequirementStatus") AS (
    VALUES
    -- Common onboarding and emergency training
    ('SAFETY_INDUCTION', 'Head Office', 'Wajib'), ('SAFETY_INDUCTION', 'Project Management Team', 'Wajib'),
    ('SAFETY_INDUCTION', 'Supervisor', 'Wajib'), ('SAFETY_INDUCTION', 'Foreman', 'Wajib'),
    ('SAFETY_INDUCTION', 'Medic', 'Wajib'), ('SAFETY_INDUCTION', 'Safetyman', 'Wajib'),
    ('SAFETY_INDUCTION', 'Rigger', 'Wajib'), ('SAFETY_INDUCTION', 'Welder', 'Wajib'),
    ('SAFETY_INDUCTION', 'Fitter', 'Wajib'), ('SAFETY_INDUCTION', 'Blaster', 'Wajib'),
    ('SAFETY_INDUCTION', 'Painter', 'Wajib'), ('SAFETY_INDUCTION', 'Scaffolder', 'Wajib'),
    ('SAFETY_INDUCTION', 'Operator Heavy Equipment', 'Wajib'), ('SAFETY_INDUCTION', 'HSE Officer / Safety Man', 'Wajib'),
    ('SAFETY_INDUCTION', 'Electrician', 'Wajib'), ('SAFETY_INDUCTION', 'Mechanic', 'Wajib'),
    ('SAFETY_INDUCTION', 'Mason', 'Wajib'), ('SAFETY_INDUCTION', 'Carpenter', 'Wajib'),
    ('SAFETY_INDUCTION', 'Security', 'Wajib'), ('SAFETY_INDUCTION', 'Helper / General Worker', 'Wajib'),
    ('SAFETY_INDUCTION', 'Driver', 'Wajib'),
    ('MCU', 'Head Office', 'Wajib'), ('MCU', 'Project Management Team', 'Wajib'), ('MCU', 'Supervisor', 'Wajib'),
    ('MCU', 'Foreman', 'Wajib'), ('MCU', 'Medic', 'Wajib'), ('MCU', 'Safetyman', 'Wajib'),
    ('MCU', 'Rigger', 'Wajib'), ('MCU', 'Welder', 'Wajib'), ('MCU', 'Fitter', 'Wajib'), ('MCU', 'Blaster', 'Wajib'),
    ('MCU', 'Painter', 'Wajib'), ('MCU', 'Scaffolder', 'Wajib'), ('MCU', 'Operator Heavy Equipment', 'Wajib'),
    ('MCU', 'HSE Officer / Safety Man', 'Wajib'), ('MCU', 'Electrician', 'Wajib'), ('MCU', 'Mechanic', 'Wajib'),
    ('MCU', 'Mason', 'Wajib'), ('MCU', 'Carpenter', 'Wajib'), ('MCU', 'Security', 'Wajib'),
    ('MCU', 'Helper / General Worker', 'Wajib'), ('MCU', 'Driver', 'Wajib'),
    ('HSSE_CULTURE', 'Head Office', 'Wajib'), ('HSSE_CULTURE', 'Project Management Team', 'Wajib'),
    ('HSSE_CULTURE', 'Supervisor', 'Wajib'), ('HSSE_CULTURE', 'Foreman', 'Wajib'), ('HSSE_CULTURE', 'Medic', 'Wajib'),
    ('HSSE_CULTURE', 'Safetyman', 'Wajib'), ('HSSE_CULTURE', 'Rigger', 'Wajib'), ('HSSE_CULTURE', 'Welder', 'Wajib'),
    ('HSSE_CULTURE', 'Fitter', 'Wajib'), ('HSSE_CULTURE', 'Blaster', 'Wajib'), ('HSSE_CULTURE', 'Painter', 'Wajib'),
    ('HSSE_CULTURE', 'Scaffolder', 'Wajib'), ('HSSE_CULTURE', 'Operator Heavy Equipment', 'Wajib'),
    ('HSSE_CULTURE', 'HSE Officer / Safety Man', 'Wajib'), ('HSSE_CULTURE', 'Electrician', 'Wajib'),
    ('HSSE_CULTURE', 'Mechanic', 'Wajib'), ('HSSE_CULTURE', 'Mason', 'Wajib'), ('HSSE_CULTURE', 'Carpenter', 'Wajib'),
    ('HSSE_CULTURE', 'Security', 'Wajib'), ('HSSE_CULTURE', 'Helper / General Worker', 'Wajib'), ('HSSE_CULTURE', 'Driver', 'Wajib'),
    ('FIRE_FIGHTING', 'Head Office', 'Wajib'), ('FIRE_FIGHTING', 'Project Management Team', 'Wajib'),
    ('FIRE_FIGHTING', 'Supervisor', 'Wajib'), ('FIRE_FIGHTING', 'Foreman', 'Wajib'), ('FIRE_FIGHTING', 'Medic', 'Wajib'),
    ('FIRE_FIGHTING', 'Safetyman', 'Wajib'), ('FIRE_FIGHTING', 'Rigger', 'Wajib'), ('FIRE_FIGHTING', 'Welder', 'Wajib'),
    ('FIRE_FIGHTING', 'Fitter', 'Wajib'), ('FIRE_FIGHTING', 'Blaster', 'Wajib'), ('FIRE_FIGHTING', 'Painter', 'Wajib'),
    ('FIRE_FIGHTING', 'Scaffolder', 'Wajib'), ('FIRE_FIGHTING', 'Operator Heavy Equipment', 'Wajib'),
    ('FIRE_FIGHTING', 'HSE Officer / Safety Man', 'Wajib'), ('FIRE_FIGHTING', 'Electrician', 'Wajib'),
    ('FIRE_FIGHTING', 'Mechanic', 'Wajib'), ('FIRE_FIGHTING', 'Mason', 'Wajib'), ('FIRE_FIGHTING', 'Carpenter', 'Wajib'),
    ('FIRE_FIGHTING', 'Security', 'Wajib'), ('FIRE_FIGHTING', 'Helper / General Worker', 'Wajib'), ('FIRE_FIGHTING', 'Driver', 'Wajib'),
    -- Role-specific training
    ('FIRST_AID_P3K', 'Project Management Team', 'Kondisional'), ('FIRST_AID_P3K', 'Supervisor', 'Kondisional'),
    ('FIRST_AID_P3K', 'Foreman', 'Kondisional'), ('FIRST_AID_P3K', 'Medic', 'Wajib'),
    ('FIRST_AID_P3K', 'Safetyman', 'Wajib'), ('FIRST_AID_P3K', 'HSE Officer / Safety Man', 'Wajib'),
    ('WORKING_AT_HEIGHT', 'Supervisor', 'Kondisional'), ('WORKING_AT_HEIGHT', 'Foreman', 'Kondisional'),
    ('WORKING_AT_HEIGHT', 'Safetyman', 'Kondisional'), ('WORKING_AT_HEIGHT', 'Rigger', 'Wajib'),
    ('WORKING_AT_HEIGHT', 'Welder', 'Kondisional'), ('WORKING_AT_HEIGHT', 'Fitter', 'Kondisional'),
    ('WORKING_AT_HEIGHT', 'Blaster', 'Kondisional'), ('WORKING_AT_HEIGHT', 'Painter', 'Kondisional'),
    ('WORKING_AT_HEIGHT', 'Scaffolder', 'Wajib'), ('WORKING_AT_HEIGHT', 'Operator Heavy Equipment', 'Kondisional'),
    ('WORKING_AT_HEIGHT', 'HSE Officer / Safety Man', 'Kondisional'), ('WORKING_AT_HEIGHT', 'Electrician', 'Kondisional'),
    ('WORKING_AT_HEIGHT', 'Mechanic', 'Kondisional'), ('WORKING_AT_HEIGHT', 'Mason', 'Kondisional'),
    ('WORKING_AT_HEIGHT', 'Carpenter', 'Kondisional'), ('WORKING_AT_HEIGHT', 'Helper / General Worker', 'Kondisional'),
    ('CONFINED_SPACE', 'Supervisor', 'Kondisional'), ('CONFINED_SPACE', 'Foreman', 'Kondisional'),
    ('CONFINED_SPACE', 'Safetyman', 'Wajib'), ('CONFINED_SPACE', 'Rigger', 'Kondisional'),
    ('CONFINED_SPACE', 'Welder', 'Kondisional'), ('CONFINED_SPACE', 'Fitter', 'Kondisional'),
    ('CONFINED_SPACE', 'Blaster', 'Kondisional'), ('CONFINED_SPACE', 'Painter', 'Kondisional'),
    ('CONFINED_SPACE', 'Scaffolder', 'Kondisional'), ('CONFINED_SPACE', 'HSE Officer / Safety Man', 'Wajib'),
    ('CONFINED_SPACE', 'Electrician', 'Kondisional'), ('CONFINED_SPACE', 'Mechanic', 'Kondisional'),
    ('CONFINED_SPACE', 'Mason', 'Kondisional'), ('CONFINED_SPACE', 'Carpenter', 'Kondisional'),
    ('CONFINED_SPACE', 'Helper / General Worker', 'Kondisional'),
    ('LIFTING_RIGGING', 'Project Management Team', 'Kondisional'), ('LIFTING_RIGGING', 'Supervisor', 'Kondisional'),
    ('LIFTING_RIGGING', 'Foreman', 'Kondisional'), ('LIFTING_RIGGING', 'Safetyman', 'Kondisional'),
    ('LIFTING_RIGGING', 'Rigger', 'Wajib'), ('LIFTING_RIGGING', 'Operator Heavy Equipment', 'Wajib'),
    ('LIFTING_RIGGING', 'HSE Officer / Safety Man', 'Kondisional'), ('LIFTING_RIGGING', 'Mechanic', 'Kondisional'),
    ('ELECTRICAL_LOTO', 'Project Management Team', 'Kondisional'), ('ELECTRICAL_LOTO', 'Supervisor', 'Kondisional'),
    ('ELECTRICAL_LOTO', 'Foreman', 'Kondisional'), ('ELECTRICAL_LOTO', 'Safetyman', 'Kondisional'),
    ('ELECTRICAL_LOTO', 'HSE Officer / Safety Man', 'Kondisional'), ('ELECTRICAL_LOTO', 'Electrician', 'Wajib'),
    ('ELECTRICAL_LOTO', 'Mechanic', 'Wajib'),
    ('SIA_SIO_HEAVY_EQUIPMENT', 'Operator Heavy Equipment', 'Wajib'), ('SIA_SIO_HEAVY_EQUIPMENT', 'Rigger', 'Kondisional'),
    ('SIA_SIO_HEAVY_EQUIPMENT', 'Mechanic', 'Kondisional'), ('SIA_SIO_HEAVY_EQUIPMENT', 'Supervisor', 'Kondisional'),
    ('SIA_SIO_HEAVY_EQUIPMENT', 'Foreman', 'Kondisional')
)
INSERT INTO "trainingMatrixTbl" ("PositionId", "TrainingId", "RequirementStatus")
SELECT p."Id", t."Id", COALESCE(r."RequirementStatus", 'N/A')
FROM "positionMasterTbl" p
CROSS JOIN "trainingMasterTbl" t
LEFT JOIN "Required" r ON r."NamaPosisi" = p."NamaPosisi" AND r."KodeTraining" = t."KodeTraining"
ON CONFLICT ("PositionId", "TrainingId") DO UPDATE SET
    "RequirementStatus" = EXCLUDED."RequirementStatus",
    "UpdatedAt" = NOW();

-- -------------------------------------------------------------------------------------
-- 4. INDIVIDUAL TRAINING RECORDS
-- -------------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS "trainingRecordTbl" (
    "Id" BIGSERIAL PRIMARY KEY,
    "Fusion4KaryawanId" BIGINT NOT NULL,
    "NamaKaryawanSnapshot" TEXT NOT NULL DEFAULT '',
    "NamaPosisiSnapshot" TEXT NOT NULL DEFAULT '',
    "TrainingId" BIGINT NOT NULL REFERENCES "trainingMasterTbl"("Id"),
    "TanggalTraining" DATE NOT NULL,
    "BerlakuMulai" DATE,
    "TanggalKadaluarsa" DATE,
    "Penyedia" TEXT NOT NULL DEFAULT '',
    "NomorSertifikat" TEXT NOT NULL DEFAULT '',
    "CertificateFileName" TEXT,
    "CertificateFileUrl" TEXT,
    "CertificateFileId" TEXT,
    "Status" TEXT NOT NULL DEFAULT 'Valid'
        CHECK ("Status" IN ('Valid', 'Expired', 'Pending', 'Revoked')),
    "Catatan" TEXT NOT NULL DEFAULT '',
    "CreatedAt" TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    "UpdatedAt" TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT "trainingRecordTbl_date_order_check"
        CHECK ("BerlakuMulai" IS NULL OR "TanggalKadaluarsa" IS NULL OR "TanggalKadaluarsa" >= "BerlakuMulai")
);

CREATE INDEX IF NOT EXISTS idx_training_record_employee ON "trainingRecordTbl" ("Fusion4KaryawanId");
CREATE INDEX IF NOT EXISTS idx_training_record_training ON "trainingRecordTbl" ("TrainingId");
CREATE INDEX IF NOT EXISTS idx_training_record_expiry ON "trainingRecordTbl" ("TanggalKadaluarsa");
CREATE UNIQUE INDEX IF NOT EXISTS uq_training_record_identical
    ON "trainingRecordTbl" ("Fusion4KaryawanId", "TrainingId", "TanggalTraining", COALESCE("NomorSertifikat", ''));

COMMENT ON COLUMN "trainingRecordTbl"."Fusion4KaryawanId" IS
    'External reference to Fusion4 project karyawanTbl.Id; intentionally no cross-project foreign key.';

-- -------------------------------------------------------------------------------------
-- 5. RLS: MASTER/MATRIX READ-ONLY PUBLIC, PERSONNEL RECORDS AUTHENTICATED ONLY
-- -------------------------------------------------------------------------------------
ALTER TABLE "trainingMasterTbl" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "positionMasterTbl" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "trainingMatrixTbl" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "trainingRecordTbl" ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "training_master_public_read" ON "trainingMasterTbl";
CREATE POLICY "training_master_public_read" ON "trainingMasterTbl" FOR SELECT TO anon, authenticated USING (TRUE);
DROP POLICY IF EXISTS "position_master_public_read" ON "positionMasterTbl";
CREATE POLICY "position_master_public_read" ON "positionMasterTbl" FOR SELECT TO anon, authenticated USING (TRUE);
DROP POLICY IF EXISTS "training_matrix_public_read" ON "trainingMatrixTbl";
CREATE POLICY "training_matrix_public_read" ON "trainingMatrixTbl" FOR SELECT TO anon, authenticated USING (TRUE);

DROP POLICY IF EXISTS "training_record_authenticated_read" ON "trainingRecordTbl";
CREATE POLICY "training_record_authenticated_read" ON "trainingRecordTbl" FOR SELECT TO authenticated USING (TRUE);
DROP POLICY IF EXISTS "training_record_authenticated_insert" ON "trainingRecordTbl";
CREATE POLICY "training_record_authenticated_insert" ON "trainingRecordTbl" FOR INSERT TO authenticated WITH CHECK (TRUE);
DROP POLICY IF EXISTS "training_record_authenticated_update" ON "trainingRecordTbl";
CREATE POLICY "training_record_authenticated_update" ON "trainingRecordTbl" FOR UPDATE TO authenticated USING (TRUE) WITH CHECK (TRUE);
DROP POLICY IF EXISTS "training_record_authenticated_delete" ON "trainingRecordTbl";
CREATE POLICY "training_record_authenticated_delete" ON "trainingRecordTbl" FOR DELETE TO authenticated USING (TRUE);

GRANT SELECT ON "trainingMasterTbl", "positionMasterTbl", "trainingMatrixTbl" TO anon, authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON "trainingRecordTbl" TO authenticated;
GRANT USAGE, SELECT ON SEQUENCE "trainingMasterTbl_Id_seq", "positionMasterTbl_Id_seq",
    "trainingMatrixTbl_Id_seq", "trainingRecordTbl_Id_seq" TO authenticated;
