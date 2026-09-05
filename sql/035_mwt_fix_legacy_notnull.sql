-- =====================================================================================
-- HSSE-Fusion4 -- MIGRASI #35: MWT -- LEPAS NOT NULL DARI KOLOM SKEMA PERTAMA (LAMA)
-- Jalankan SETELAH sql/033_mwt_schema.sql (v2) dan sql/034_mwt_admin_close.sql.
--
-- Latar belakang: mwtTbl di database ini sempat ke-create dari VERSI PERTAMA sql/033
-- (desain submit tunggal, sebelum direvisi jadi 2 tahap jadwal+kunjungan). Versi pertama
-- itu kemungkinan bikin beberapa kolom lama (TanggalKunjungan, AreaKunjungan,
-- NamaManagement, dst) sebagai NOT NULL. Kolom-kolom itu SUDAH GAK DIPAKAI lagi sama RPC
-- versi 2 (create_mwt_schedule, submit_mwt_kunjungan) -- tapi kalau masih NOT NULL,
-- INSERT dari create_mwt_schedule() bakal GAGAL karena kolom lama itu gak diisi.
--
-- Migrasi ini cuma lepas constraint NOT NULL-nya (data lama kalau ada tetap aman, gak
-- ada yang dihapus) -- dicek dulu satu-satu pakai DO block biar aman dijalankan
-- berkali-kali dan gak error walau kolomnya udah nullable atau gak ada.
-- =====================================================================================

DO $$
DECLARE
    v_col TEXT;
BEGIN
    FOREACH v_col IN ARRAY ARRAY[
        'TanggalKunjungan', 'AreaKunjungan', 'NamaManagement', 'ManagementQrCodeId',
        'PendampingList', 'JumlahPekerjaDiskusi', 'CatatanObservasi', 'FotoList'
    ]
    LOOP
        IF EXISTS (
            SELECT 1 FROM information_schema.columns
            WHERE table_name = 'mwtTbl' AND column_name = v_col AND is_nullable = 'NO'
        ) THEN
            EXECUTE format('ALTER TABLE "mwtTbl" ALTER COLUMN %I DROP NOT NULL', v_col);
        END IF;
    END LOOP;
END $$;

-- Cek hasilnya -- kalau query ini kosong, berarti udah gak ada kolom lama yang masih NOT NULL.
SELECT column_name, is_nullable
FROM information_schema.columns
WHERE table_name = 'mwtTbl'
  AND column_name IN ('TanggalKunjungan', 'AreaKunjungan', 'NamaManagement', 'ManagementQrCodeId',
                       'PendampingList', 'JumlahPekerjaDiskusi', 'CatatanObservasi', 'FotoList')
  AND is_nullable = 'NO';
