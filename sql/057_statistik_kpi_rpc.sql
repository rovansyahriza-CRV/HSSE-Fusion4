-- =====================================================================================
-- MIGRASI #057 (HSSE): RPC get_statistik_kpi buat dashboard Statistik & KPI
-- Jalankan di Supabase project **HSSE-Fusion4**, SETELAH 056 (statistik_manhours).
-- Aman dijalankan ulang (CREATE OR REPLACE). Cuma baca, gak ngubah data.
--
-- Rumus (N = p_basis, default 1.000.000 man-hours):
--   Recordable  = Medical Treatment Case + Restricted Work Case + Lost Time Injury + Fatality
--   TRIR        = Recordable x N / man-hours
--   LTIFR       = (Lost Time Injury + Fatality) x N / man-hours
--   Severity    = jumlah HariKerjaHilang x N / man-hours
--   Fatality R. = Fatality x N / man-hours
-- Man-hours = manHoursTbl (koreksi kalau ada, kalau nggak hasil SmartGate).
-- Rate = NULL kalau man-hours 0 / belum ditarik.
-- p_project_id NULL = semua project digabung (jumlah dulu, baru dihitung rate-nya).
-- Incident dihitung dari tanggal kejadian ("TanggalWaktu"), semua status.
-- Near Miss dihitung dari Incident DAN CERMAT (keputusan CRV), ditampilin terpisah.
-- =====================================================================================

CREATE OR REPLACE FUNCTION public.get_statistik_kpi(
    p_project_id BIGINT,
    p_tahun INT,
    p_basis NUMERIC DEFAULT 1000000
)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_bulan JSONB;
    v_ytd JSONB;
    v_rolling JSONB;
    v_klas JSONB;
    v_temuan JSONB;
    v_lti JSONB;
    v_basis NUMERIC := COALESCE(NULLIF(p_basis, 0), 1000000);
    v_akhir DATE;
    v_awal DATE;
BEGIN
    -- Periode rolling 12 bulan: tahun berjalan -> s/d bulan ini, tahun lalu -> s/d Desember.
    IF p_tahun = EXTRACT(YEAR FROM CURRENT_DATE)::INT THEN
        v_akhir := date_trunc('month', CURRENT_DATE)::DATE;
    ELSE
        v_akhir := make_date(p_tahun, 12, 1);
    END IF;
    v_awal := (v_akhir - INTERVAL '11 months')::DATE;

    WITH bln AS (SELECT generate_series(1, 12) AS b),
    mh AS (
        SELECT "Bulan" AS b,
               SUM(COALESCE("ManHoursKoreksi", "ManHoursSmartGate")) AS man_hours,
               SUM(COALESCE("JumlahPekerjaKoreksi", "JumlahPekerjaSmartGate")) AS pekerja
        FROM "manHoursTbl"
        WHERE "Tahun" = p_tahun AND (p_project_id IS NULL OR "ProjectId" = p_project_id)
        GROUP BY 1
    ),
    inc AS (
        SELECT EXTRACT(MONTH FROM "TanggalWaktu")::INT AS b,
               COUNT(*) FILTER (WHERE "Klasifikasi" = 'First Aid Case') AS fac,
               COUNT(*) FILTER (WHERE "Klasifikasi" = 'Medical Treatment Case') AS mtc,
               COUNT(*) FILTER (WHERE "Klasifikasi" = 'Restricted Work Case') AS rwc,
               COUNT(*) FILTER (WHERE "Klasifikasi" = 'Lost Time Injury') AS lti,
               COUNT(*) FILTER (WHERE "Klasifikasi" = 'Fatality') AS fatality,
               COUNT(*) FILTER (WHERE "Klasifikasi" = 'Near Miss') AS near_miss,
               COUNT(*) FILTER (WHERE "Klasifikasi" IN ('Kerusakan Properti', 'Lingkungan', 'Keamanan/Security')) AS non_injury,
               COALESCE(SUM("HariKerjaHilang") FILTER (WHERE "Klasifikasi" IN ('Restricted Work Case', 'Lost Time Injury', 'Fatality')), 0) AS hari_hilang
        FROM "incidentTbl"
        WHERE EXTRACT(YEAR FROM "TanggalWaktu") = p_tahun AND (p_project_id IS NULL OR "ProjectId" = p_project_id)
        GROUP BY 1
    ),
    cer AS (
        SELECT EXTRACT(MONTH FROM "TanggalWaktu")::INT AS b,
               COUNT(*) FILTER (WHERE "Sifat" = 'Positif') AS positif,
               COUNT(*) FILTER (WHERE "Sifat" = 'Negatif') AS negatif,
               COUNT(*) FILTER (WHERE "JenisTemuan" = 'Near Miss') AS near_miss
        FROM "cermatTbl"
        WHERE EXTRACT(YEAR FROM "TanggalWaktu") = p_tahun AND (p_project_id IS NULL OR "ProjectId" = p_project_id)
        GROUP BY 1
    ),
    ins AS (
        SELECT EXTRACT(MONTH FROM "TanggalWaktu")::INT AS b, COUNT(*) AS jml, ROUND(AVG("SkorPersen"), 1) AS skor
        FROM "inspeksiTbl"
        WHERE EXTRACT(YEAR FROM "TanggalWaktu") = p_tahun AND (p_project_id IS NULL OR "ProjectId" = p_project_id)
        GROUP BY 1
    ),
    tbm AS (
        SELECT EXTRACT(MONTH FROM "TanggalMulai")::INT AS b, COUNT(*) AS jml,
               COALESCE(SUM(jsonb_array_length(COALESCE("PesertaList", '[]'::jsonb))), 0) AS peserta
        FROM "tbmTbl"
        WHERE EXTRACT(YEAR FROM "TanggalMulai") = p_tahun AND (p_project_id IS NULL OR "ProjectId" = p_project_id)
        GROUP BY 1
    ),
    ptw AS (
        SELECT EXTRACT(MONTH FROM "TanggalWaktu")::INT AS b,
               COUNT(*) AS diajukan,
               COUNT(*) FILTER (WHERE "Status" IN ('Aktif', 'Menunggu Approval Penutupan', 'Ditutup')) AS disetujui
        FROM "ptwTbl"
        WHERE EXTRACT(YEAR FROM "TanggalWaktu") = p_tahun AND (p_project_id IS NULL OR "ProjectId" = p_project_id)
        GROUP BY 1
    ),
    mtg AS (
        SELECT EXTRACT(MONTH FROM "TanggalRapat")::INT AS b, COUNT(*) AS jml
        FROM "hseMeetingTbl"
        WHERE EXTRACT(YEAR FROM "TanggalRapat") = p_tahun AND (p_project_id IS NULL OR "ProjectId" = p_project_id)
        GROUP BY 1
    ),
    mwt AS (
        SELECT EXTRACT(MONTH FROM mv.tgl)::INT AS b, COUNT(*) AS jml
        FROM "mwtTbl" m
        CROSS JOIN LATERAL (
            SELECT MIN((elem->>'tanggalKunjungan')::timestamptz) AS tgl
            FROM jsonb_array_elements(COALESCE(m."KunjunganList", '[]'::jsonb)) elem
        ) mv
        WHERE mv.tgl IS NOT NULL AND EXTRACT(YEAR FROM mv.tgl) = p_tahun
          AND (p_project_id IS NULL OR m."ProjectId" = p_project_id)
        GROUP BY 1
    ),
    aud AS (
        SELECT EXTRACT(MONTH FROM COALESCE("TanggalSelesaiAudit", "TanggalDitutup"))::INT AS b, COUNT(*) AS jml
        FROM "auditTbl"
        WHERE "Status" IN ('Selesai Audit', 'Ditutup')
          AND EXTRACT(YEAR FROM COALESCE("TanggalSelesaiAudit", "TanggalDitutup")) = p_tahun
          AND (p_project_id IS NULL OR "ProjectId" = p_project_id)
        GROUP BY 1
    ),
    rows AS (
        SELECT bln.b,
               mh.man_hours, COALESCE(mh.pekerja, 0) AS pekerja,
               COALESCE(inc.fac, 0) AS fac, COALESCE(inc.mtc, 0) AS mtc, COALESCE(inc.rwc, 0) AS rwc,
               COALESCE(inc.lti, 0) AS lti, COALESCE(inc.fatality, 0) AS fatality,
               COALESCE(inc.near_miss, 0) AS nm_inc, COALESCE(cer.near_miss, 0) AS nm_cer,
               COALESCE(inc.non_injury, 0) AS non_injury, COALESCE(inc.hari_hilang, 0) AS hari_hilang,
               COALESCE(cer.positif, 0) AS positif, COALESCE(cer.negatif, 0) AS negatif,
               COALESCE(ins.jml, 0) AS inspeksi, ins.skor AS inspeksi_skor,
               COALESCE(tbm.jml, 0) AS tbm, COALESCE(tbm.peserta, 0) AS tbm_peserta,
               COALESCE(ptw.diajukan, 0) AS ptw_diajukan, COALESCE(ptw.disetujui, 0) AS ptw_disetujui,
               COALESCE(mtg.jml, 0) AS hse_meeting, COALESCE(mwt.jml, 0) AS mwt, COALESCE(aud.jml, 0) AS audit
        FROM bln
        LEFT JOIN mh ON mh.b = bln.b
        LEFT JOIN inc ON inc.b = bln.b
        LEFT JOIN cer ON cer.b = bln.b
        LEFT JOIN ins ON ins.b = bln.b
        LEFT JOIN tbm ON tbm.b = bln.b
        LEFT JOIN ptw ON ptw.b = bln.b
        LEFT JOIN mtg ON mtg.b = bln.b
        LEFT JOIN mwt ON mwt.b = bln.b
        LEFT JOIN aud ON aud.b = bln.b
    )
    SELECT
        jsonb_agg(jsonb_build_object(
            'bulan', b,
            'manHours', man_hours,
            'jumlahPekerja', pekerja,
            'fac', fac, 'mtc', mtc, 'rwc', rwc, 'lti', lti, 'fatality', fatality,
            'recordable', mtc + rwc + lti + fatality,
            'nearMissIncident', nm_inc, 'nearMissCermat', nm_cer, 'nearMiss', nm_inc + nm_cer,
            'nonInjury', non_injury, 'hariHilang', hari_hilang,
            'trir', CASE WHEN COALESCE(man_hours, 0) > 0 THEN ROUND((mtc + rwc + lti + fatality) * v_basis / man_hours, 2) END,
            'ltifr', CASE WHEN COALESCE(man_hours, 0) > 0 THEN ROUND((lti + fatality) * v_basis / man_hours, 2) END,
            'severityRate', CASE WHEN COALESCE(man_hours, 0) > 0 THEN ROUND(hari_hilang * v_basis / man_hours, 2) END,
            'cermatPositif', positif, 'cermatNegatif', negatif,
            'inspeksi', inspeksi, 'inspeksiSkorRata', inspeksi_skor,
            'tbm', tbm, 'tbmPeserta', tbm_peserta,
            'ptwDiajukan', ptw_diajukan, 'ptwDisetujui', ptw_disetujui,
            'hseMeeting', hse_meeting, 'mwt', mwt, 'auditSelesai', audit
        ) ORDER BY b),
        jsonb_build_object(
            'manHours', COALESCE(SUM(man_hours), 0),
            'bulanAdaManHours', COUNT(*) FILTER (WHERE COALESCE(man_hours, 0) > 0),
            'rataPekerja', ROUND(AVG(pekerja) FILTER (WHERE COALESCE(man_hours, 0) > 0), 0),
            'fac', SUM(fac), 'mtc', SUM(mtc), 'rwc', SUM(rwc), 'lti', SUM(lti), 'fatality', SUM(fatality),
            'recordable', SUM(mtc + rwc + lti + fatality),
            'nearMissIncident', SUM(nm_inc), 'nearMissCermat', SUM(nm_cer), 'nearMiss', SUM(nm_inc + nm_cer),
            'nonInjury', SUM(non_injury), 'hariHilang', SUM(hari_hilang),
            'trir', CASE WHEN COALESCE(SUM(man_hours), 0) > 0 THEN ROUND(SUM(mtc + rwc + lti + fatality) * v_basis / SUM(man_hours), 2) END,
            'ltifr', CASE WHEN COALESCE(SUM(man_hours), 0) > 0 THEN ROUND(SUM(lti + fatality) * v_basis / SUM(man_hours), 2) END,
            'severityRate', CASE WHEN COALESCE(SUM(man_hours), 0) > 0 THEN ROUND(SUM(hari_hilang) * v_basis / SUM(man_hours), 2) END,
            'fatalityRate', CASE WHEN COALESCE(SUM(man_hours), 0) > 0 THEN ROUND(SUM(fatality) * v_basis / SUM(man_hours), 2) END,
            'cermatPositif', SUM(positif), 'cermatNegatif', SUM(negatif),
            'inspeksi', SUM(inspeksi),
            'tbm', SUM(tbm), 'tbmPeserta', SUM(tbm_peserta),
            'ptwDiajukan', SUM(ptw_diajukan), 'ptwDisetujui', SUM(ptw_disetujui),
            'hseMeeting', SUM(hse_meeting), 'mwt', SUM(mwt), 'auditSelesai', SUM(audit)
        )
    INTO v_bulan, v_ytd
    FROM rows;

    -- Rata-rata skor inspeksi setahun (bukan rata-rata dari rata-rata bulanan)
    v_ytd := v_ytd || jsonb_build_object('inspeksiSkorRata', (
        SELECT ROUND(AVG("SkorPersen"), 1) FROM "inspeksiTbl"
        WHERE EXTRACT(YEAR FROM "TanggalWaktu") = p_tahun AND (p_project_id IS NULL OR "ProjectId" = p_project_id)
    ));

    -- Rolling 12 bulan
    WITH mh AS (
        SELECT COALESCE(SUM(COALESCE("ManHoursKoreksi", "ManHoursSmartGate")), 0) AS man_hours
        FROM "manHoursTbl"
        WHERE make_date("Tahun", "Bulan", 1) BETWEEN v_awal AND v_akhir
          AND (p_project_id IS NULL OR "ProjectId" = p_project_id)
    ),
    inc AS (
        SELECT COUNT(*) FILTER (WHERE "Klasifikasi" IN ('Medical Treatment Case', 'Restricted Work Case', 'Lost Time Injury', 'Fatality')) AS rec,
               COUNT(*) FILTER (WHERE "Klasifikasi" IN ('Lost Time Injury', 'Fatality')) AS lti,
               COALESCE(SUM("HariKerjaHilang") FILTER (WHERE "Klasifikasi" IN ('Restricted Work Case', 'Lost Time Injury', 'Fatality')), 0) AS hari
        FROM "incidentTbl"
        WHERE "TanggalWaktu" >= v_awal AND "TanggalWaktu" < (v_akhir + INTERVAL '1 month')
          AND (p_project_id IS NULL OR "ProjectId" = p_project_id)
    )
    SELECT jsonb_build_object(
        'dari', to_char(v_awal, 'YYYY-MM'), 'sampai', to_char(v_akhir, 'YYYY-MM'),
        'manHours', mh.man_hours, 'recordable', inc.rec, 'ltiFatality', inc.lti, 'hariHilang', inc.hari,
        'trir', CASE WHEN mh.man_hours > 0 THEN ROUND(inc.rec * v_basis / mh.man_hours, 2) END,
        'ltifr', CASE WHEN mh.man_hours > 0 THEN ROUND(inc.lti * v_basis / mh.man_hours, 2) END,
        'severityRate', CASE WHEN mh.man_hours > 0 THEN ROUND(inc.hari * v_basis / mh.man_hours, 2) END
    )
    INTO v_rolling
    FROM mh, inc;

    -- Klasifikasi incident setahun
    SELECT COALESCE(jsonb_object_agg(k, COALESCE(c.jml, 0)), '{}'::jsonb)
    INTO v_klas
    FROM unnest(ARRAY['Near Miss', 'First Aid Case', 'Medical Treatment Case', 'Restricted Work Case',
                      'Lost Time Injury', 'Fatality', 'Kerusakan Properti', 'Lingkungan', 'Keamanan/Security']) k
    LEFT JOIN (
        SELECT "Klasifikasi", COUNT(*) AS jml FROM "incidentTbl"
        WHERE EXTRACT(YEAR FROM "TanggalWaktu") = p_tahun AND (p_project_id IS NULL OR "ProjectId" = p_project_id)
        GROUP BY 1
    ) c ON c."Klasifikasi" = k;

    -- Temuan / tindak lanjut dari laporan tahun ini
    SELECT jsonb_build_array(
        (SELECT jsonb_build_object('modul', 'CERMAT (negatif)',
                'total', COUNT(*), 'closed', COUNT(*) FILTER (WHERE "Status" = 'Closed'),
                'open', COUNT(*) FILTER (WHERE "Status" <> 'Closed'),
                'overdue', COUNT(*) FILTER (WHERE "Status" <> 'Closed' AND "Tenggat" < CURRENT_DATE))
         FROM "cermatTbl"
         WHERE "Sifat" = 'Negatif' AND EXTRACT(YEAR FROM "TanggalWaktu") = p_tahun
           AND (p_project_id IS NULL OR "ProjectId" = p_project_id)),
        (SELECT jsonb_build_object('modul', 'Incident',
                'total', COUNT(*), 'closed', COUNT(*) FILTER (WHERE "Status" = 'Closed'),
                'open', COUNT(*) FILTER (WHERE "Status" <> 'Closed'),
                'overdue', COUNT(*) FILTER (WHERE "Status" <> 'Closed' AND "Tenggat" < CURRENT_DATE))
         FROM "incidentTbl"
         WHERE EXTRACT(YEAR FROM "TanggalWaktu") = p_tahun
           AND (p_project_id IS NULL OR "ProjectId" = p_project_id)),
        (SELECT jsonb_build_object('modul', 'Internal Audit (NC)',
                'total', COUNT(*),
                'closed', COUNT(*) FILTER (WHERE t->'capa'->>'status' = 'Ditutup'),
                'open', COUNT(*) FILTER (WHERE COALESCE(t->'capa'->>'status', 'Open') <> 'Ditutup'),
                'overdue', COUNT(*) FILTER (WHERE COALESCE(t->'capa'->>'status', 'Open') <> 'Ditutup'
                                             AND NULLIF(t->'capa'->>'tenggat', '')::DATE < CURRENT_DATE))
         FROM "auditTbl" a
         CROSS JOIN LATERAL jsonb_array_elements(COALESCE(a."TemuanList", '[]'::jsonb)) t
         WHERE t->>'hasil' = 'Tidak Sesuai'
           AND EXTRACT(YEAR FROM COALESCE(a."TanggalPelaksanaan", a."CreatedAt")) = p_tahun
           AND (p_project_id IS NULL OR a."ProjectId" = p_project_id))
    ) INTO v_temuan;

    -- LTI / Fatality terakhir (semua tahun)
    SELECT jsonb_build_object(
        'tanggal', x.tgl,
        'hari', CASE WHEN x.tgl IS NOT NULL THEN (CURRENT_DATE - x.tgl::DATE) END,
        'manHoursSejak', CASE WHEN x.tgl IS NOT NULL THEN (
            SELECT COALESCE(SUM(COALESCE("ManHoursKoreksi", "ManHoursSmartGate")), 0)
            FROM "manHoursTbl"
            WHERE make_date("Tahun", "Bulan", 1) > date_trunc('month', x.tgl)::DATE
              AND (p_project_id IS NULL OR "ProjectId" = p_project_id)
        ) END
    ) INTO v_lti
    FROM (
        SELECT MAX("TanggalWaktu") AS tgl FROM "incidentTbl"
        WHERE "Klasifikasi" IN ('Lost Time Injury', 'Fatality')
          AND (p_project_id IS NULL OR "ProjectId" = p_project_id)
    ) x;

    RETURN jsonb_build_object(
        'projectId', p_project_id,
        'tahun', p_tahun,
        'basis', v_basis,
        'bulan', v_bulan,
        'ytd', v_ytd,
        'rolling12', v_rolling,
        'klasifikasi', v_klas,
        'temuan', v_temuan,
        'ltiTerakhir', v_lti,
        'dihitungPada', NOW()
    );
END;
$$;
