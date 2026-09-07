-- Management Review structured discussion frame RPC.
-- Run after 046-048. Safe to rerun.
--
-- Menghasilkan data otomatis per topik pembahasan Management Review sesuai
-- kesepakatan (7 topik): HSE Program, Incident & Near Miss, Audit/Inspeksi/
-- Compliance (CERMAT + Inspeksi), Partisipasi Pekerja (dari MWT), lalu Risiko,
-- Sumber Daya, dan Kesiapsiagaan Darurat diisi manual (belum ada sumber modul
-- terstruktur untuk 3 topik terakhir).

CREATE OR REPLACE FUNCTION public.get_management_review_frame(p_project_id BIGINT, p_tahun INT DEFAULT NULL)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_tahun INT := COALESCE(p_tahun, EXTRACT(YEAR FROM NOW())::INT);
    v_result JSONB;
BEGIN
    SELECT jsonb_build_object(
        'tahun', v_tahun,

        'hseProgram', COALESCE((
            SELECT jsonb_agg(jsonb_build_object(
                'namaItem', mi."NamaItem",
                'targetTotal', COALESCE((
                    SELECT SUM(v.value::text::int) FROM jsonb_each(COALESCE(hp."TargetBulanan", '{}'::jsonb)) v
                ), 0),
                'realisasiTotal', 0
            ) ORDER BY mi."Urutan")
            FROM "hseProgramMasterItemTbl" mi
            JOIN "hseProgramTbl" hp ON hp."ItemId" = mi."Id"
                AND hp."ProjectId" = p_project_id AND hp."Tahun" = v_tahun
            WHERE hp."StatusPakai" = 'Use'
        ), '[]'::jsonb),

        'incidentNearMiss', COALESCE((
            SELECT jsonb_agg(jsonb_build_object(
                'noLaporan', i."NoLaporan", 'klasifikasi', i."Klasifikasi",
                'lokasiArea', i."LokasiArea", 'status', i."Status"
            ) ORDER BY i."TanggalWaktu" DESC)
            FROM "incidentTbl" i
            WHERE i."ProjectId" = p_project_id AND i."Status" <> 'Closed'
        ), '[]'::jsonb),

        'cermat', jsonb_build_object(
            'totalOpen', (SELECT COUNT(*) FROM "cermatTbl" WHERE "ProjectId" = p_project_id AND "Status" <> 'Closed'),
            'totalClosed', (SELECT COUNT(*) FROM "cermatTbl" WHERE "ProjectId" = p_project_id AND "Status" = 'Closed'),
            'openList', COALESCE((
                SELECT jsonb_agg(jsonb_build_object(
                    'noLaporan', c."NoLaporan", 'deskripsi', c."Deskripsi",
                    'status', c."Status", 'penanggungJawab', c."PenanggungJawab", 'tenggat', c."Tenggat"
                ) ORDER BY c."TanggalWaktu" DESC)
                FROM "cermatTbl" c WHERE c."ProjectId" = p_project_id AND c."Status" <> 'Closed'
            ), '[]'::jsonb)
        ),

        'inspeksi', jsonb_build_object(
            'totalOpen', (
                SELECT COUNT(*) FROM "inspeksiTbl"
                WHERE "ProjectId" = p_project_id AND "JumlahTidakSesuai" > 0 AND "CermatId" IS NULL
            ),
            'totalClosed', (
                SELECT COUNT(*) FROM "inspeksiTbl"
                WHERE "ProjectId" = p_project_id AND ("JumlahTidakSesuai" = 0 OR "CermatId" IS NOT NULL)
            ),
            'openList', COALESCE((
                SELECT jsonb_agg(jsonb_build_object(
                    'noLaporan', ii."NoLaporan", 'jenis', ii."Jenis", 'lokasiArea', ii."LokasiArea",
                    'jumlahTidakSesuai', ii."JumlahTidakSesuai"
                ) ORDER BY ii."TanggalWaktu" DESC)
                FROM "inspeksiTbl" ii
                WHERE ii."ProjectId" = p_project_id AND ii."JumlahTidakSesuai" > 0 AND ii."CermatId" IS NULL
            ), '[]'::jsonb)
        ),

        'partisipasiPekerja', jsonb_build_object(
            'totalSesi', (SELECT COUNT(*) FROM "mwtTbl" WHERE "ProjectId" = p_project_id),
            'totalKunjungan', COALESCE((
                SELECT SUM(jsonb_array_length(COALESCE("KunjunganList", '[]'::jsonb)))
                FROM "mwtTbl" WHERE "ProjectId" = p_project_id
            ), 0),
            'totalPekerjaDiskusi', COALESCE((
                SELECT SUM((k->>'jumlahPekerjaDiskusi')::int)
                FROM "mwtTbl" m, jsonb_array_elements(COALESCE(m."KunjunganList", '[]'::jsonb)) k
                WHERE m."ProjectId" = p_project_id
            ), 0)
        )
    ) INTO v_result;

    RETURN v_result;
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_management_review_frame(BIGINT, INT) TO anon, authenticated;
