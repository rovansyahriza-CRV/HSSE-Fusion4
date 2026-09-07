-- Management Review follow-up frame RPC.
-- Run this after the Management Review schema migration (046).
-- Safe to rerun; it only creates/replaces the RPC used by the browser client.

CREATE OR REPLACE FUNCTION public.get_management_review_open_followups(p_project_id BIGINT)
RETURNS JSONB
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT COALESCE(jsonb_agg(item ORDER BY module, title), '[]'::jsonb)
    FROM (
        SELECT jsonb_build_object(
            'module', 'HSE Meeting',
            'title', COALESCE(t->>'item', 'Tindak lanjut HSE Meeting'),
            'detail', t->>'topikTerkait',
            'status', COALESCE(t->>'status', 'Open'),
            'pic', t->>'pic'
        ) AS item,
        COALESCE(t->>'item', 'Tindak lanjut HSE Meeting') AS title,
        'HSE Meeting' AS module
        FROM "hseMeetingTbl" h
        CROSS JOIN LATERAL jsonb_array_elements(COALESCE(h."TindakLanjutList", '[]'::jsonb)) t
        WHERE h."ProjectId" = p_project_id
          AND COALESCE(t->>'status', 'Open') <> 'Selesai'

        UNION ALL

        SELECT jsonb_build_object(
            'module', 'CERMAT',
            'title', COALESCE(c."NoLaporan", 'Laporan CERMAT'),
            'detail', COALESCE(c."Rekomendasi", c."TindakanLangsung", ''),
            'status', c."Status",
            'pic', c."PenanggungJawab"
        ), COALESCE(c."NoLaporan", 'Laporan CERMAT'), 'CERMAT'
        FROM "cermatTbl" c
        WHERE c."ProjectId" = p_project_id
          AND c."Status" <> 'Closed'

        UNION ALL

        SELECT jsonb_build_object(
            'module', 'Incident',
            'title', COALESCE(i."NoLaporan", 'Incident'),
            'detail', COALESCE(i."TindakanKorektif", i."TindakanLangsung", ''),
            'status', i."Status",
            'pic', i."PenanggungJawab"
        ), COALESCE(i."NoLaporan", 'Incident'), 'Incident'
        FROM "incidentTbl" i
        WHERE i."ProjectId" = p_project_id
          AND i."Status" <> 'Closed'

        UNION ALL

        SELECT jsonb_build_object(
            'module', 'Internal Audit',
            'title', COALESCE(a."NoAudit", 'Internal Audit'),
            'detail', a."JudulAudit",
            'status', a."Status",
            'pic', a."LeadAuditor"
        ), COALESCE(a."NoAudit", 'Internal Audit'), 'Internal Audit'
        FROM "auditTbl" a
        WHERE a."ProjectId" = p_project_id
          AND a."Status" <> 'Ditutup'
          AND a."JumlahTidakSesuai" > 0
    ) followups;
$$;

GRANT EXECUTE ON FUNCTION public.get_management_review_open_followups(BIGINT)
TO anon, authenticated;
