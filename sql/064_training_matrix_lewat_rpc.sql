-- =====================================================================================
-- 064 -- PIC fase 2, tahap 2: Training Matrix nulis lewat RPC, bukan langsung ke tabel.
-- Jalankan di project Supabase HSSE-Fusion4 (BUKAN Fusion4 SmartGate). Run after 063.
-- Pasang bareng training-matrix.html versi baru (halaman lama akan gagal simpan).
--
-- Sebelumnya: 043/044 kasih anon INSERT/UPDATE langsung ke trainingMatrixTbl,
--   trainingMasterTbl, positionMasterTbl. Cek PIC HSSE-TRM cuma di browser.
--   trainingRecordTbl cuma buat role authenticated (gak ada yang login), jadi tab
--   Records gak pernah bisa simpan/tampil (0 baris).
-- Sekarang:
--   - Baca master/posisi/matrix tetap publik (dipakai training-matrix-pdf.html).
--   - Semua tulis lewat RPC save_training_* dan nyatat siapa yang ngubah.
--   - Training Records (data personal + link sertifikat) dibaca lewat get_training_records,
--     cuma setelah verifikasi PIC (sesuai maksud 041: records tidak publik).
--   - Helper hsse_wajib_akses(nama, qr, tag): sekarang baru wajib nama + QR terisi.
--     Tahap 3 (065) ganti isinya jadi cek PIC/Author ke SmartGate, RPC lain tinggal ikut.
-- Aman dijalankan ulang.
-- =====================================================================================

-- -------------------------------------------------------------------------------------
-- 1. Helper cek akses (stub tahap 2; diisi cek SmartGate di 065)
-- -------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.hsse_wajib_akses(p_nama TEXT, p_qr TEXT, p_tag TEXT)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
    IF COALESCE(trim(p_nama), '') = '' OR COALESCE(trim(p_qr), '') = '' THEN
        RAISE EXCEPTION 'Verifikasi % dulu (nama & QR Code ID wajib).', p_tag;
    END IF;
END;
$$;
REVOKE EXECUTE ON FUNCTION public.hsse_wajib_akses(TEXT, TEXT, TEXT) FROM PUBLIC, anon, authenticated;

-- -------------------------------------------------------------------------------------
-- 2. Kolom jejak perubahan
-- -------------------------------------------------------------------------------------
ALTER TABLE "trainingMatrixTbl"  ADD COLUMN IF NOT EXISTS "DiubahOleh" TEXT NOT NULL DEFAULT '';
ALTER TABLE "trainingMatrixTbl"  ADD COLUMN IF NOT EXISTS "DiubahQrCodeId" TEXT NOT NULL DEFAULT '';
ALTER TABLE "trainingMasterTbl"  ADD COLUMN IF NOT EXISTS "DiubahOleh" TEXT NOT NULL DEFAULT '';
ALTER TABLE "trainingMasterTbl"  ADD COLUMN IF NOT EXISTS "DiubahQrCodeId" TEXT NOT NULL DEFAULT '';
ALTER TABLE "positionMasterTbl"  ADD COLUMN IF NOT EXISTS "DiubahOleh" TEXT NOT NULL DEFAULT '';
ALTER TABLE "positionMasterTbl"  ADD COLUMN IF NOT EXISTS "DiubahQrCodeId" TEXT NOT NULL DEFAULT '';
ALTER TABLE "trainingRecordTbl"  ADD COLUMN IF NOT EXISTS "DiubahOleh" TEXT NOT NULL DEFAULT '';
ALTER TABLE "trainingRecordTbl"  ADD COLUMN IF NOT EXISTS "DiubahQrCodeId" TEXT NOT NULL DEFAULT '';

-- -------------------------------------------------------------------------------------
-- 3. Tutup tulis langsung (hapus policy 043/044 + policy authenticated 041)
-- -------------------------------------------------------------------------------------
DROP POLICY IF EXISTS "training_matrix_public_insert" ON "trainingMatrixTbl";
DROP POLICY IF EXISTS "training_matrix_public_update" ON "trainingMatrixTbl";
DROP POLICY IF EXISTS "training_master_public_insert" ON "trainingMasterTbl";
DROP POLICY IF EXISTS "training_master_public_update" ON "trainingMasterTbl";
DROP POLICY IF EXISTS "position_master_public_insert" ON "positionMasterTbl";
DROP POLICY IF EXISTS "position_master_public_update" ON "positionMasterTbl";
DROP POLICY IF EXISTS "training_record_authenticated_read"   ON "trainingRecordTbl";
DROP POLICY IF EXISTS "training_record_authenticated_insert" ON "trainingRecordTbl";
DROP POLICY IF EXISTS "training_record_authenticated_update" ON "trainingRecordTbl";
DROP POLICY IF EXISTS "training_record_authenticated_delete" ON "trainingRecordTbl";
DROP POLICY IF EXISTS "trainingRecordTbl_no_direct" ON "trainingRecordTbl";
CREATE POLICY "trainingRecordTbl_no_direct" ON "trainingRecordTbl"
    FOR ALL TO anon, authenticated USING (false) WITH CHECK (false);
-- policy *_public_read (SELECT) di matrix/master/posisi sengaja dibiarkan.

REVOKE INSERT, UPDATE, DELETE ON "trainingMatrixTbl", "trainingMasterTbl", "positionMasterTbl", "trainingRecordTbl"
    FROM anon, authenticated;

-- -------------------------------------------------------------------------------------
-- 4. RPC tulis
-- -------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.save_training_matrix_status(
    p_position_id BIGINT, p_training_id BIGINT, p_status TEXT, p_nama TEXT, p_qr TEXT
) RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_row "trainingMatrixTbl"%ROWTYPE;
BEGIN
    PERFORM public.hsse_wajib_akses(p_nama, p_qr, 'HSSE-TRM');
    IF p_status NOT IN ('Wajib', 'Kondisional', 'N/A') THEN
        RAISE EXCEPTION 'Status harus Wajib / Kondisional / N/A.';
    END IF;
    INSERT INTO "trainingMatrixTbl" ("PositionId", "TrainingId", "RequirementStatus", "DiubahOleh", "DiubahQrCodeId", "UpdatedAt")
    VALUES (p_position_id, p_training_id, p_status, trim(p_nama), trim(p_qr), NOW())
    ON CONFLICT ("PositionId", "TrainingId") DO UPDATE SET
        "RequirementStatus" = EXCLUDED."RequirementStatus",
        "DiubahOleh" = EXCLUDED."DiubahOleh",
        "DiubahQrCodeId" = EXCLUDED."DiubahQrCodeId",
        "UpdatedAt" = NOW()
    RETURNING * INTO v_row;
    RETURN jsonb_build_object('Id', v_row."Id", 'PositionId', v_row."PositionId",
        'TrainingId', v_row."TrainingId", 'RequirementStatus', v_row."RequirementStatus");
END;
$$;

CREATE OR REPLACE FUNCTION public.save_training_master(
    p_kode TEXT, p_nama_training TEXT, p_deskripsi TEXT, p_target_peserta TEXT,
    p_frekuensi TEXT, p_penyedia TEXT, p_urutan INT, p_aktif BOOLEAN, p_nama TEXT, p_qr TEXT
) RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_id BIGINT;
BEGIN
    PERFORM public.hsse_wajib_akses(p_nama, p_qr, 'HSSE-TRM');
    IF COALESCE(trim(p_kode), '') = '' OR COALESCE(trim(p_nama_training), '') = '' THEN
        RAISE EXCEPTION 'Kode dan nama training wajib diisi.';
    END IF;
    INSERT INTO "trainingMasterTbl" ("KodeTraining", "NamaTraining", "Deskripsi", "TargetPeserta",
        "FrekuensiBerlaku", "Penyedia", "Urutan", "IsActive", "DiubahOleh", "DiubahQrCodeId", "UpdatedAt")
    VALUES (upper(trim(p_kode)), trim(p_nama_training), COALESCE(trim(p_deskripsi), ''),
        COALESCE(trim(p_target_peserta), ''), COALESCE(trim(p_frekuensi), ''), COALESCE(trim(p_penyedia), ''),
        COALESCE(p_urutan, 0), COALESCE(p_aktif, TRUE), trim(p_nama), trim(p_qr), NOW())
    RETURNING "Id" INTO v_id;
    RETURN jsonb_build_object('ok', true, 'Id', v_id);
END;
$$;

CREATE OR REPLACE FUNCTION public.save_position_master(
    p_nama_posisi TEXT, p_kategori TEXT, p_urutan INT, p_aktif BOOLEAN, p_nama TEXT, p_qr TEXT
) RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_id BIGINT;
BEGIN
    PERFORM public.hsse_wajib_akses(p_nama, p_qr, 'HSSE-TRM');
    IF COALESCE(trim(p_nama_posisi), '') = '' THEN
        RAISE EXCEPTION 'Nama posisi wajib diisi.';
    END IF;
    INSERT INTO "positionMasterTbl" ("NamaPosisi", "Kategori", "Urutan", "IsActive", "DiubahOleh", "DiubahQrCodeId", "UpdatedAt")
    VALUES (trim(p_nama_posisi), p_kategori, COALESCE(p_urutan, 0), COALESCE(p_aktif, TRUE), trim(p_nama), trim(p_qr), NOW())
    RETURNING "Id" INTO v_id;
    RETURN jsonb_build_object('ok', true, 'Id', v_id);
END;
$$;

-- p_record: field sama dengan kolom trainingRecordTbl (Fusion4KaryawanId, TrainingId, TanggalTraining, dst).
CREATE OR REPLACE FUNCTION public.save_training_record(p_record JSONB, p_nama TEXT, p_qr TEXT)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_id BIGINT;
BEGIN
    PERFORM public.hsse_wajib_akses(p_nama, p_qr, 'HSSE-TRM');
    IF NULLIF(p_record->>'Fusion4KaryawanId', '') IS NULL OR NULLIF(p_record->>'TanggalTraining', '') IS NULL
       OR NULLIF(p_record->>'TrainingId', '') IS NULL THEN
        RAISE EXCEPTION 'Karyawan, training, dan tanggal training wajib diisi.';
    END IF;
    INSERT INTO "trainingRecordTbl" ("Fusion4KaryawanId", "NamaKaryawanSnapshot", "NamaPosisiSnapshot",
        "TrainingId", "TanggalTraining", "BerlakuMulai", "TanggalKadaluarsa", "Penyedia", "NomorSertifikat",
        "CertificateFileName", "CertificateFileUrl", "CertificateFileId", "Status", "Catatan",
        "DiubahOleh", "DiubahQrCodeId", "UpdatedAt")
    VALUES ((p_record->>'Fusion4KaryawanId')::BIGINT,
        COALESCE(p_record->>'NamaKaryawanSnapshot', ''), COALESCE(p_record->>'NamaPosisiSnapshot', ''),
        (p_record->>'TrainingId')::BIGINT, (p_record->>'TanggalTraining')::DATE,
        NULLIF(p_record->>'BerlakuMulai', '')::DATE, NULLIF(p_record->>'TanggalKadaluarsa', '')::DATE,
        COALESCE(p_record->>'Penyedia', ''), COALESCE(p_record->>'NomorSertifikat', ''),
        NULLIF(p_record->>'CertificateFileName', ''), NULLIF(p_record->>'CertificateFileUrl', ''),
        NULLIF(p_record->>'CertificateFileId', ''), COALESCE(NULLIF(p_record->>'Status', ''), 'Valid'),
        COALESCE(p_record->>'Catatan', ''), trim(p_nama), trim(p_qr), NOW())
    RETURNING "Id" INTO v_id;
    RETURN jsonb_build_object('ok', true, 'Id', v_id);
END;
$$;

-- -------------------------------------------------------------------------------------
-- 5. RPC baca records (setelah verifikasi PIC)
-- -------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_training_records(p_nama TEXT, p_qr TEXT, p_limit INT DEFAULT 100)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
    PERFORM public.hsse_wajib_akses(p_nama, p_qr, 'HSSE-TRM');
    RETURN COALESCE((
        SELECT jsonb_agg(to_jsonb(x) ORDER BY x."TanggalTraining" DESC, x."Id" DESC)
        FROM (
            SELECT r.*, jsonb_build_object('NamaTraining', t."NamaTraining") AS "trainingMasterTbl"
            FROM "trainingRecordTbl" r
            LEFT JOIN "trainingMasterTbl" t ON t."Id" = r."TrainingId"
            ORDER BY r."TanggalTraining" DESC, r."Id" DESC
            LIMIT LEAST(GREATEST(COALESCE(p_limit, 100), 1), 500)
        ) x
    ), '[]'::jsonb);
END;
$$;

GRANT EXECUTE ON FUNCTION public.save_training_matrix_status(BIGINT, BIGINT, TEXT, TEXT, TEXT) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.save_training_master(TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, INT, BOOLEAN, TEXT, TEXT) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.save_position_master(TEXT, TEXT, INT, BOOLEAN, TEXT, TEXT) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.save_training_record(JSONB, TEXT, TEXT) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.get_training_records(TEXT, TEXT, INT) TO anon, authenticated;

-- =====================================================================================
-- CEK SETELAH JALAN:
-- SELECT has_table_privilege('anon', '"trainingMatrixTbl"', 'UPDATE');   -- false
-- SELECT has_table_privilege('anon', '"trainingMatrixTbl"', 'SELECT');   -- true (PDF)
-- SELECT polname FROM pg_policy WHERE polrelid = '"trainingRecordTbl"'::regclass; -- cuma _no_direct
-- =====================================================================================
