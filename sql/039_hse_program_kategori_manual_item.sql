-- =====================================================================================
-- MIGRASI #39: HSE Program -- kelompokkan item per KATEGORI (sinkron sama "Standard
-- Pelaporan" HSSE PT BIMA) + tambah 14 item standar yang modulnya belum ada, dengan
-- realisasi MANUAL INPUT (bukan auto dari tabel modul).
-- Jalankan di Supabase project HSSE-FUSION4 (BUKAN Fusion4) -- sama kayak #031/#032/#033/
-- #037, ini nyentuh hseProgramMasterItemTbl & hseProgramTbl doang.
--
-- Latar belakang (hasil diskusi bareng CRV): dari 23 item "Standard Pelaporan" HSSE
-- yang seharusnya ada, cuma 9 yang udah ke-cover modul otomatis (PTW&JSA, MWT, CERMAT,
-- Toolbox Meeting, HSE Weekly/Monthly, Incident/Accident, Inspeksi & Observasi, Internal
-- Audit, + Management Review yang dari #031 emang udah disiapin placeholder). 14 sisanya
-- (Emergency Preparedness x3, Training & Kompetensi x4, Safety Campaign, Compliance
-- Monitoring x4, P2K3 Meeting Bulanan, SWA Implementation) modulnya belum dibangun --
-- disepakati buat sementara realisasinya diisi MANUAL oleh HSE Admin (bukan ditinggal 0
-- selamanya), sambil nunggu modul masing-masing digarap belakangan. Kalau nanti Compliance
-- Monitoring ternyata kekonfirmasi gabung ke Inspeksi & Observasi, 4 item itu tinggal
-- DIHAPUS dari hseProgramMasterItemTbl -- berdiri sendiri, gak ngerusak item lain.
--
-- Perubahan:
--   1. Kolom baru "Kategori" (grouping tampilan) & "SumberRealisasi" ('OTOMATIS' /
--      'MANUAL') di hseProgramMasterItemTbl.
--   2. Kolom baru "RealisasiManualBulanan" (JSONB, format sama kayak TargetBulanan) di
--      hseProgramTbl -- tempat nyimpen realisasi yang diinput manual per bulan.
--   3. Recategorize + renumber Urutan 9 item existing (JSA digabung tampil 1 baris sama
--      PTW, namanya diubah jadi "Permit to Work & JSA"), Management Review ikutan
--      ditandain SumberRealisasi = MANUAL (dari awal emang udah placeholder realisasi 0).
--   4. Insert 14 item baru, semua default StatusPakai 'N/A' (gak keganggu laporan project
--      yang udah jalan sampe HSE Admin sengaja toggle "Use").
--   5. get_hse_program() -- tambah field kategori & sumberRealisasi; utk item MANUAL,
--      realisasiBulanan/realisasiTotal diambil dari RealisasiManualBulanan (bukan dari
--      UNION ALL tabel modul).
--   6. upsert_hse_program_item() -- terima parameter baru p_realisasi_manual_bulanan
--      (opsional, cuma dipakai/perlu diisi utk item MANUAL). Kalau NULL dikirim (item
--      OTOMATIS lagi disave), nilai RealisasiManualBulanan yang lama gak ketimpa.
-- =====================================================================================

-- -------------------------------------------------------------------------------------
-- 1. KOLOM BARU
-- -------------------------------------------------------------------------------------
ALTER TABLE "hseProgramMasterItemTbl" ADD COLUMN IF NOT EXISTS "Kategori" TEXT NOT NULL DEFAULT 'Lainnya';
ALTER TABLE "hseProgramMasterItemTbl" ADD COLUMN IF NOT EXISTS "SumberRealisasi" TEXT NOT NULL DEFAULT 'OTOMATIS'
    CHECK ("SumberRealisasi" IN ('OTOMATIS', 'MANUAL'));

ALTER TABLE "hseProgramTbl" ADD COLUMN IF NOT EXISTS "RealisasiManualBulanan" JSONB NOT NULL
    DEFAULT '{"1":0,"2":0,"3":0,"4":0,"5":0,"6":0,"7":0,"8":0,"9":0,"10":0,"11":0,"12":0}'::jsonb;

-- -------------------------------------------------------------------------------------
-- 2. RECATEGORIZE + RENUMBER 9 ITEM YANG UDAH ADA
--    Urutan dikasih jarak (kelipatan 10 dalam 1 kategori, kelipatan 100 antar kategori)
--    biar ada ruang nyisipin item baru belakangan tanpa perlu renumber ulang semua.
-- -------------------------------------------------------------------------------------
UPDATE "hseProgramMasterItemTbl" SET "Kategori" = 'Permit to Work (PTW) & JSA/HIRADC', "Urutan" = 10,
    "NamaItem" = 'Permit to Work & JSA', "Keterangan" = 'Realisasi dari modul PTW -- JSA/HIRADC sudah nempel jadi 1 alur di modul PTW'
    WHERE "KodeItem" = 'PTW';

UPDATE "hseProgramMasterItemTbl" SET "Kategori" = 'Observasi & Intervensi Perilaku', "Urutan" = 300 WHERE "KodeItem" = 'MWT';
UPDATE "hseProgramMasterItemTbl" SET "Kategori" = 'Observasi & Intervensi Perilaku', "Urutan" = 310 WHERE "KodeItem" = 'CERMAT';
UPDATE "hseProgramMasterItemTbl" SET "Kategori" = 'Observasi & Intervensi Perilaku', "Urutan" = 320 WHERE "KodeItem" = 'TBM';
UPDATE "hseProgramMasterItemTbl" SET "Kategori" = 'Observasi & Intervensi Perilaku', "Urutan" = 330 WHERE "KodeItem" = 'HSE_MEETING_MINGGUAN';
UPDATE "hseProgramMasterItemTbl" SET "Kategori" = 'Observasi & Intervensi Perilaku', "Urutan" = 340 WHERE "KodeItem" = 'HSE_MEETING_BULANAN';

UPDATE "hseProgramMasterItemTbl" SET "Kategori" = 'Administrasi & Evaluasi', "Urutan" = 510 WHERE "KodeItem" = 'INCIDENT';
UPDATE "hseProgramMasterItemTbl" SET "Kategori" = 'Administrasi & Evaluasi', "Urutan" = 520 WHERE "KodeItem" = 'INSPEKSI_OBSERVASI';
UPDATE "hseProgramMasterItemTbl" SET "Kategori" = 'Administrasi & Evaluasi', "Urutan" = 530 WHERE "KodeItem" = 'INTERNAL_AUDIT';
UPDATE "hseProgramMasterItemTbl" SET "Kategori" = 'Administrasi & Evaluasi', "Urutan" = 550, "SumberRealisasi" = 'MANUAL',
    "Keterangan" = 'Modul belum dibangun -- realisasi diisi manual'
    WHERE "KodeItem" = 'MANAGEMENT_REVIEW';

-- -------------------------------------------------------------------------------------
-- 3. INSERT 14 ITEM BARU (semua SumberRealisasi = MANUAL, default StatusPakai N/A)
-- -------------------------------------------------------------------------------------
INSERT INTO "hseProgramMasterItemTbl" ("KodeItem", "NamaItem", "SatuanTarget", "Urutan", "Kategori", "SumberRealisasi", "Keterangan") VALUES
    ('ERP_REVIEW', 'Emergency Response Plan Review', 'kali', 100, 'Emergency Preparedness', 'MANUAL', 'Modul belum dibangun -- realisasi diisi manual'),
    ('MEDICAL_DRILL', 'Medical Emergency Response Drill', 'kali', 110, 'Emergency Preparedness', 'MANUAL', 'Modul belum dibangun -- realisasi diisi manual'),
    ('SAFETY_DRILL', 'Safety Drill / Emergency Drill (fire, muster, spill)', 'kali', 120, 'Emergency Preparedness', 'MANUAL', 'Modul belum dibangun -- realisasi diisi manual'),

    ('SAFETY_INDUCTION', 'Safety Induction', 'kali', 200, 'Training & Kompetensi', 'MANUAL', 'Modul belum dibangun -- realisasi diisi manual'),
    ('MCU', 'MCU (Medical Check-Up)', 'kali', 210, 'Training & Kompetensi', 'MANUAL', 'Modul belum dibangun -- realisasi diisi manual'),
    ('SERTIFIKASI_KOMPETENSI', 'Sertifikasi Kompetensi (SIA/SIO, rigger, scaffolder, dll)', 'kali', 220, 'Training & Kompetensi', 'MANUAL', 'Modul belum dibangun -- realisasi diisi manual'),
    ('HSSE_CULTURE_TRAINING', 'HSSE Culture Training', 'kali', 230, 'Training & Kompetensi', 'MANUAL', 'Modul belum dibangun -- realisasi diisi manual'),

    ('SAFETY_CAMPAIGN', 'Safety Campaign', 'kali', 350, 'Observasi & Intervensi Perilaku', 'MANUAL', 'Modul belum dibangun -- realisasi diisi manual'),

    ('PPE_COMPLIANCE', 'PPE Compliance', 'kali', 400, 'Compliance Monitoring', 'MANUAL', 'Modul belum dibangun -- realisasi diisi manual; masih disounding apa perlu berdiri sendiri atau gabung ke Inspeksi & Observasi'),
    ('PTW_COMPLIANCE', 'PTW Compliance', 'kali', 410, 'Compliance Monitoring', 'MANUAL', 'Modul belum dibangun -- realisasi diisi manual; masih disounding apa perlu berdiri sendiri atau gabung ke Inspeksi & Observasi'),
    ('TOOLS_EQUIPMENT_COMPLIANCE', 'Tools & Equipment Compliance', 'kali', 420, 'Compliance Monitoring', 'MANUAL', 'Modul belum dibangun -- realisasi diisi manual; masih disounding apa perlu berdiri sendiri atau gabung ke Inspeksi & Observasi'),
    ('CLSR', 'CLSR (Corporate Life Saving Rules)', 'kali', 430, 'Compliance Monitoring', 'MANUAL', 'Modul belum dibangun -- realisasi diisi manual; masih disounding apa perlu berdiri sendiri atau gabung ke Inspeksi & Observasi'),

    ('P2K3_BULANAN', 'P2K3 Meeting Bulanan', 'kali', 500, 'Administrasi & Evaluasi', 'MANUAL', 'Modul belum dibangun -- realisasi diisi manual; berdiri sendiri dari HSE Meeting karena wajib dilaporkan ke Pemerintah/Disnaker'),
    ('SWA_IMPLEMENTATION', 'Stop Work Authority (SWA) Implementation', 'kali', 540, 'Administrasi & Evaluasi', 'MANUAL', 'Modul belum dibangun -- realisasi diisi manual')
ON CONFLICT ("KodeItem") DO NOTHING;

-- -------------------------------------------------------------------------------------
-- 4. get_hse_program() -- tambah field kategori & sumberRealisasi; item MANUAL ambil
--    realisasi dari RealisasiManualBulanan, item OTOMATIS tetap dari UNION ALL modul
--    (body UNION ALL disalin persis dari sql/037, TIDAK diubah).
-- -------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_hse_program(p_project_id BIGINT, p_tahun INT)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $function$
DECLARE
    v_result JSONB;
BEGIN
    WITH realisasi AS (
        SELECT 'TBM' AS kode, EXTRACT(MONTH FROM "TanggalMulai")::INT AS bulan, COUNT(*) AS jumlah
        FROM "tbmTbl"
        WHERE "ProjectId" = p_project_id AND EXTRACT(YEAR FROM "TanggalMulai") = p_tahun
        GROUP BY 2

        UNION ALL
        SELECT 'HSE_MEETING_MINGGUAN', EXTRACT(MONTH FROM "TanggalRapat")::INT, COUNT(*)
        FROM "hseMeetingTbl"
        WHERE "ProjectId" = p_project_id AND "TipeMeeting" = 'Mingguan'
          AND EXTRACT(YEAR FROM "TanggalRapat") = p_tahun
        GROUP BY 2

        UNION ALL
        SELECT 'HSE_MEETING_BULANAN', EXTRACT(MONTH FROM "TanggalRapat")::INT, COUNT(*)
        FROM "hseMeetingTbl"
        WHERE "ProjectId" = p_project_id AND "TipeMeeting" = 'Bulanan'
          AND EXTRACT(YEAR FROM "TanggalRapat") = p_tahun
        GROUP BY 2

        UNION ALL
        SELECT 'INSPEKSI_OBSERVASI', EXTRACT(MONTH FROM "TanggalWaktu")::INT, COUNT(*)
        FROM "inspeksiTbl"
        WHERE "ProjectId" = p_project_id AND EXTRACT(YEAR FROM "TanggalWaktu") = p_tahun
        GROUP BY 2

        UNION ALL
        SELECT 'CERMAT', EXTRACT(MONTH FROM "TanggalWaktu")::INT, COUNT(*)
        FROM "cermatTbl"
        WHERE "ProjectId" = p_project_id AND EXTRACT(YEAR FROM "TanggalWaktu") = p_tahun
        GROUP BY 2

        UNION ALL
        SELECT 'INTERNAL_AUDIT', EXTRACT(MONTH FROM COALESCE("TanggalSelesaiAudit", "TanggalDitutup"))::INT, COUNT(*)
        FROM "auditTbl"
        WHERE "ProjectId" = p_project_id
          AND "Status" IN ('Selesai Audit', 'Ditutup')
          AND EXTRACT(YEAR FROM COALESCE("TanggalSelesaiAudit", "TanggalDitutup")) = p_tahun
        GROUP BY 2

        UNION ALL
        SELECT 'PTW', EXTRACT(MONTH FROM "TanggalWaktu")::INT, COUNT(*)
        FROM "ptwTbl"
        WHERE "ProjectId" = p_project_id AND EXTRACT(YEAR FROM "TanggalWaktu") = p_tahun
        GROUP BY 2

        UNION ALL
        SELECT 'INCIDENT', EXTRACT(MONTH FROM "TanggalWaktu")::INT, COUNT(*)
        FROM "incidentTbl"
        WHERE "ProjectId" = p_project_id AND EXTRACT(YEAR FROM "TanggalWaktu") = p_tahun
        GROUP BY 2

        UNION ALL
        SELECT 'MWT', EXTRACT(MONTH FROM mv.tgl_kunjungan_pertama)::INT, COUNT(*)
        FROM "mwtTbl" m
        CROSS JOIN LATERAL (
            SELECT MIN((elem->>'tanggalKunjungan')::timestamptz) AS tgl_kunjungan_pertama
            FROM jsonb_array_elements(m."KunjunganList") elem
        ) mv
        WHERE m."ProjectId" = p_project_id
          AND mv.tgl_kunjungan_pertama IS NOT NULL
          AND EXTRACT(YEAR FROM mv.tgl_kunjungan_pertama) = p_tahun
        GROUP BY 2
    ),
    realisasi_agg AS (
        SELECT kode, jsonb_object_agg(bulan::text, jumlah) AS realisasi_bulanan, SUM(jumlah) AS realisasi_total
        FROM realisasi
        GROUP BY kode
    )
    SELECT COALESCE(jsonb_agg(
        jsonb_build_object(
            'itemId', mi."Id",
            'kodeItem', mi."KodeItem",
            'namaItem', mi."NamaItem",
            'kategori', mi."Kategori",
            'sumberRealisasi', mi."SumberRealisasi",
            'satuanTarget', mi."SatuanTarget",
            'urutan', mi."Urutan",
            'statusPakai', COALESCE(hp."StatusPakai", 'N/A'),
            'targetQty', hp."TargetQty",
            'frequency', hp."Frequency",
            'targetBulanan', COALESCE(hp."TargetBulanan", '{"1":0,"2":0,"3":0,"4":0,"5":0,"6":0,"7":0,"8":0,"9":0,"10":0,"11":0,"12":0}'::jsonb),
            'targetTotal', COALESCE((
                SELECT SUM(v.value::text::int)
                FROM jsonb_each(COALESCE(hp."TargetBulanan", '{}'::jsonb)) v
            ), 0),
            'realisasiBulanan', CASE WHEN mi."SumberRealisasi" = 'MANUAL'
                THEN COALESCE(hp."RealisasiManualBulanan", '{"1":0,"2":0,"3":0,"4":0,"5":0,"6":0,"7":0,"8":0,"9":0,"10":0,"11":0,"12":0}'::jsonb)
                ELSE COALESCE(ra.realisasi_bulanan, '{}'::jsonb) END,
            'realisasiTotal', CASE WHEN mi."SumberRealisasi" = 'MANUAL'
                THEN COALESCE((
                    SELECT SUM(v.value::text::int)
                    FROM jsonb_each(COALESCE(hp."RealisasiManualBulanan", '{}'::jsonb)) v
                ), 0)
                ELSE COALESCE(ra.realisasi_total, 0) END
        ) ORDER BY mi."Urutan"
    ), '[]'::jsonb)
    INTO v_result
    FROM "hseProgramMasterItemTbl" mi
    LEFT JOIN "hseProgramTbl" hp
        ON hp."ItemId" = mi."Id" AND hp."ProjectId" = p_project_id AND hp."Tahun" = p_tahun
    LEFT JOIN realisasi_agg ra ON ra.kode = mi."KodeItem";

    RETURN v_result;
END;
$function$;

-- -------------------------------------------------------------------------------------
-- 5. upsert_hse_program_item() -- tambah parameter p_realisasi_manual_bulanan (opsional).
--    Kalau NULL dikirim (item OTOMATIS lagi disave, atau caller lama yang belum update),
--    nilai RealisasiManualBulanan yang lama TETAP DIPERTAHANKAN, gak ketimpa jadi 0.
-- -------------------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.upsert_hse_program_item(BIGINT, INT, BIGINT, TEXT, JSONB, NUMERIC, TEXT);

CREATE OR REPLACE FUNCTION public.upsert_hse_program_item(
    p_project_id BIGINT,
    p_tahun INT,
    p_item_id BIGINT,
    p_status_pakai TEXT,
    p_target_bulanan JSONB,
    p_target_qty NUMERIC DEFAULT NULL,
    p_frequency TEXT DEFAULT NULL,
    p_realisasi_manual_bulanan JSONB DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $function$
DECLARE
    v_id BIGINT;
BEGIN
    IF p_status_pakai NOT IN ('Use', 'N/A') THEN
        RAISE EXCEPTION 'StatusPakai harus Use atau N/A';
    END IF;

    IF p_frequency IS NOT NULL AND p_frequency NOT IN ('Harian', 'Mingguan', 'Bulanan', 'Triwulan', 'Semester', 'Tahunan') THEN
        RAISE EXCEPTION 'Frequency tidak valid';
    END IF;

    INSERT INTO "hseProgramTbl" ("ProjectId", "Tahun", "ItemId", "StatusPakai", "TargetBulanan", "TargetQty", "Frequency", "RealisasiManualBulanan", "UpdatedAt")
    VALUES (
        p_project_id, p_tahun, p_item_id, p_status_pakai,
        COALESCE(p_target_bulanan, '{"1":0,"2":0,"3":0,"4":0,"5":0,"6":0,"7":0,"8":0,"9":0,"10":0,"11":0,"12":0}'::jsonb),
        p_target_qty, p_frequency,
        COALESCE(p_realisasi_manual_bulanan, '{"1":0,"2":0,"3":0,"4":0,"5":0,"6":0,"7":0,"8":0,"9":0,"10":0,"11":0,"12":0}'::jsonb),
        NOW()
    )
    ON CONFLICT ("ProjectId", "Tahun", "ItemId")
    DO UPDATE SET
        "StatusPakai" = EXCLUDED."StatusPakai",
        "TargetBulanan" = EXCLUDED."TargetBulanan",
        "TargetQty" = EXCLUDED."TargetQty",
        "Frequency" = EXCLUDED."Frequency",
        "RealisasiManualBulanan" = COALESCE(p_realisasi_manual_bulanan, "hseProgramTbl"."RealisasiManualBulanan"),
        "UpdatedAt" = NOW()
    RETURNING "Id" INTO v_id;

    RETURN jsonb_build_object('success', true, 'id', v_id);
END;
$function$;

-- -------------------------------------------------------------------------------------
-- 6. get_hse_program_master_items() -- ikutan tambah kategori & sumberRealisasi (gak
--    dipakai di halaman manapun saat ini, cuma disinkronin biar konsisten).
-- -------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_hse_program_master_items()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $function$
DECLARE
    v_result JSONB;
BEGIN
    SELECT COALESCE(jsonb_agg(
        jsonb_build_object(
            'itemId', "Id", 'kodeItem', "KodeItem", 'namaItem', "NamaItem",
            'kategori', "Kategori", 'sumberRealisasi', "SumberRealisasi",
            'satuanTarget', "SatuanTarget", 'urutan', "Urutan", 'keterangan', "Keterangan"
        ) ORDER BY "Urutan"
    ), '[]'::jsonb)
    INTO v_result
    FROM "hseProgramMasterItemTbl";
    RETURN v_result;
END;
$function$;

-- Cek hasilnya (opsional) -- 23 item, 6 kategori, urut sesuai Urutan.
-- SELECT "Kategori", "Urutan", "KodeItem", "NamaItem", "SumberRealisasi"
--   FROM "hseProgramMasterItemTbl" ORDER BY "Urutan";
