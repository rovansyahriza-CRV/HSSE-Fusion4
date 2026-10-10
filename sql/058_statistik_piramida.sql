-- =====================================================================================
-- MIGRASI #058 (HSSE): RPC get_statistik_piramida buat Piramida Keselamatan
-- Jalankan di Supabase project **HSSE-Fusion4**, SETELAH migrasi Statistik (056/057).
-- Aman dijalankan ulang (CREATE OR REPLACE). Cuma baca, gak ngubah data.
--
-- Lapisan (atas -> bawah) dan sumbernya:
--   Fatality            = incidentTbl.Klasifikasi 'Fatality'
--   Lost Time Injury    = incidentTbl.Klasifikasi 'Lost Time Injury'
--   Restricted Work     = incidentTbl.Klasifikasi 'Restricted Work Case'
--   Medical Treatment   = incidentTbl.Klasifikasi 'Medical Treatment Case'
--   First Aid           = incidentTbl.Klasifikasi 'First Aid Case'
--   Near Miss           = incidentTbl 'Near Miss' + cermatTbl JenisTemuan 'Near Miss'
--   Unsafe Act/Condition= cermatTbl Sifat 'Negatif' selain Near Miss
--                         (CERMAT yang dibuat otomatis dari inspeksi gak dihitung, biar gak dobel)
--                         + inspeksiTbl.JumlahTidakSesuai (jumlah item checklist "Tidak Sesuai")
-- Di luar piramida (info aja): Kerusakan Properti, Lingkungan, Keamanan/Security.
-- Semua dihitung dari tanggal kejadian/laporan ("TanggalWaktu"), semua status.
-- p_project_id NULL = semua project digabung.
-- p_bulan_dari / p_bulan_sampai = rentang bulan di tahun itu (default Jan-Des).
-- =====================================================================================

DROP FUNCTION IF EXISTS public.get_statistik_piramida(BIGINT, INT, INT, INT);

CREATE OR REPLACE FUNCTION public.get_statistik_piramida(
    p_project_id BIGINT,
    p_tahun INT,
    p_bulan_dari INT DEFAULT 1,
    p_bulan_sampai INT DEFAULT 12
)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_dari INT := LEAST(GREATEST(COALESCE(p_bulan_dari, 1), 1), 12);
    v_sampai INT := LEAST(GREATEST(COALESCE(p_bulan_sampai, 12), 1), 12);
    v_awal TIMESTAMPTZ;
    v_akhir TIMESTAMPTZ;
    v_inc RECORD;
    v_cer RECORD;
    v_ins RECORD;
BEGIN
    IF v_dari > v_sampai THEN
        v_dari := v_sampai;
    END IF;
    v_awal := make_date(p_tahun, v_dari, 1)::TIMESTAMPTZ;
    v_akhir := (make_date(p_tahun, v_sampai, 1) + INTERVAL '1 month')::TIMESTAMPTZ;

    SELECT COUNT(*) FILTER (WHERE "Klasifikasi" = 'Fatality') AS fatality,
           COUNT(*) FILTER (WHERE "Klasifikasi" = 'Lost Time Injury') AS lti,
           COUNT(*) FILTER (WHERE "Klasifikasi" = 'Restricted Work Case') AS rwc,
           COUNT(*) FILTER (WHERE "Klasifikasi" = 'Medical Treatment Case') AS mtc,
           COUNT(*) FILTER (WHERE "Klasifikasi" = 'First Aid Case') AS fac,
           COUNT(*) FILTER (WHERE "Klasifikasi" = 'Near Miss') AS near_miss,
           COUNT(*) FILTER (WHERE "Klasifikasi" = 'Kerusakan Properti') AS properti,
           COUNT(*) FILTER (WHERE "Klasifikasi" = 'Lingkungan') AS lingkungan,
           COUNT(*) FILTER (WHERE "Klasifikasi" = 'Keamanan/Security') AS keamanan
    INTO v_inc
    FROM "incidentTbl"
    WHERE "TanggalWaktu" >= v_awal AND "TanggalWaktu" < v_akhir
      AND (p_project_id IS NULL OR "ProjectId" = p_project_id);

    SELECT COUNT(*) FILTER (WHERE "JenisTemuan" = 'Near Miss') AS near_miss,
           COUNT(*) FILTER (WHERE "Sifat" = 'Negatif' AND COALESCE("JenisTemuan", '') <> 'Near Miss'
                              AND "SourceInspeksiId" IS NULL) AS unsafe,
           COUNT(*) FILTER (WHERE "Sifat" = 'Negatif' AND COALESCE("JenisTemuan", '') <> 'Near Miss'
                              AND "SourceInspeksiId" IS NOT NULL) AS dari_inspeksi
    INTO v_cer
    FROM "cermatTbl"
    WHERE "TanggalWaktu" >= v_awal AND "TanggalWaktu" < v_akhir
      AND (p_project_id IS NULL OR "ProjectId" = p_project_id);

    SELECT COUNT(*) AS jml, COALESCE(SUM("JumlahTidakSesuai"), 0) AS tidak_sesuai
    INTO v_ins
    FROM "inspeksiTbl"
    WHERE "TanggalWaktu" >= v_awal AND "TanggalWaktu" < v_akhir
      AND (p_project_id IS NULL OR "ProjectId" = p_project_id);

    RETURN jsonb_build_object(
        'projectId', p_project_id,
        'tahun', p_tahun,
        'bulanDari', v_dari,
        'bulanSampai', v_sampai,
        'lapisan', jsonb_build_array(
            jsonb_build_object('kode', 'FAT', 'nama', 'Fatality', 'jumlah', v_inc.fatality),
            jsonb_build_object('kode', 'LTI', 'nama', 'Lost Time Injury', 'jumlah', v_inc.lti),
            jsonb_build_object('kode', 'RWC', 'nama', 'Restricted Work Case', 'jumlah', v_inc.rwc),
            jsonb_build_object('kode', 'MTC', 'nama', 'Medical Treatment Case', 'jumlah', v_inc.mtc),
            jsonb_build_object('kode', 'FAC', 'nama', 'First Aid Case', 'jumlah', v_inc.fac),
            jsonb_build_object('kode', 'NM', 'nama', 'Near Miss', 'jumlah', v_inc.near_miss + v_cer.near_miss,
                               'rincian', jsonb_build_object('incident', v_inc.near_miss, 'cermat', v_cer.near_miss)),
            jsonb_build_object('kode', 'UA', 'nama', 'Unsafe Act / Unsafe Condition', 'jumlah', v_cer.unsafe + v_ins.tidak_sesuai,
                               'rincian', jsonb_build_object('cermat', v_cer.unsafe, 'inspeksi', v_ins.tidak_sesuai))
        ),
        'diLuarPiramida', jsonb_build_object(
            'kerusakanProperti', v_inc.properti,
            'lingkungan', v_inc.lingkungan,
            'keamanan', v_inc.keamanan
        ),
        'info', jsonb_build_object(
            'jumlahInspeksi', v_ins.jml,
            'cermatDariInspeksi', v_cer.dari_inspeksi
        ),
        'dihitungPada', NOW()
    );
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_statistik_piramida(BIGINT, INT, INT, INT) TO anon, authenticated;

-- Cek (opsional):
-- SELECT public.get_statistik_piramida(NULL, 2026);
-- SELECT public.get_statistik_piramida(NULL, 2026, 1, 6);
