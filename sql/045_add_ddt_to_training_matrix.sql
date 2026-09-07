-- =====================================================================================
-- HSSE-Fusion4 - MIGRASI #45: ADD DDT TO TRAINING MATRIX
-- Jalankan setelah sql/044_training_master_admin_write_policy.sql.
--
-- DDT (Defensive Driving Training) sudah menjadi item tambahan di HSE Program sejak
-- migrasi #042, tetapi sebelumnya belum ada di trainingMasterTbl sehingga tidak muncul
-- di matrix maupun PDF. Migration ini membuat DDT canonical di kedua sumber dan
-- menambahkan seluruh kombinasi posisi x DDT secara idempotent.
-- =====================================================================================

INSERT INTO "trainingMasterTbl" (
    "KodeTraining", "NamaTraining", "Deskripsi", "TargetPeserta",
    "FrekuensiBerlaku", "Penyedia", "IsActive", "Urutan"
)
VALUES (
    'DDT',
    'Defensive Driving Training (DDT)',
    'Pelatihan berkendara defensif, pengenalan bahaya jalan, dan pengendalian risiko perjalanan kerja.',
    'Driver dan personel yang mengemudikan kendaraan untuk pekerjaan; personel lain bila diwajibkan project.',
    'Sesuai masa berlaku sertifikat/provider dan refresh requirement project.',
    'Provider defensive driving kompeten / internal HSSE',
    TRUE,
    110
)
ON CONFLICT ("KodeTraining") DO UPDATE SET
    "NamaTraining" = EXCLUDED."NamaTraining",
    "Deskripsi" = EXCLUDED."Deskripsi",
    "TargetPeserta" = EXCLUDED."TargetPeserta",
    "FrekuensiBerlaku" = EXCLUDED."FrekuensiBerlaku",
    "Penyedia" = EXCLUDED."Penyedia",
    "IsActive" = EXCLUDED."IsActive",
    "Urutan" = EXCLUDED."Urutan",
    "UpdatedAt" = NOW();

-- Driver wajib; operator, supervisor/foreman, project management, security, dan
-- safetyman kondisional bila mereka mengemudikan/mengawasi perjalanan kerja.
WITH "DdtRequirement" ("NamaPosisi", "RequirementStatus") AS (
    VALUES
        ('Driver', 'Wajib'),
        ('Operator Heavy Equipment', 'Kondisional'),
        ('Supervisor', 'Kondisional'),
        ('Foreman', 'Kondisional'),
        ('Project Management Team', 'Kondisional'),
        ('Security', 'Kondisional'),
        ('Safetyman', 'Kondisional')
)
INSERT INTO "trainingMatrixTbl" ("PositionId", "TrainingId", "RequirementStatus", "Catatan")
SELECT p."Id", t."Id", COALESCE(d."RequirementStatus", 'N/A'),
    CASE WHEN d."RequirementStatus" IS NULL THEN '' ELSE 'Sesuai kebutuhan mengemudi/perjalanan kerja.' END
FROM "positionMasterTbl" p
CROSS JOIN "trainingMasterTbl" t
LEFT JOIN "DdtRequirement" d ON d."NamaPosisi" = p."NamaPosisi"
WHERE t."KodeTraining" = 'DDT'
ON CONFLICT ("PositionId", "TrainingId") DO UPDATE SET
    "RequirementStatus" = EXCLUDED."RequirementStatus",
    "Catatan" = EXCLUDED."Catatan",
    "UpdatedAt" = NOW();
