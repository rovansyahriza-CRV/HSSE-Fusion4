-- Management Review: sequential report document numbers.
-- Run after 052. Safe to rerun.
--
-- R suffix is the sequential report/bundle number, independent from the
-- managementReviewTbl identity. The advisory lock prevents duplicate numbers
-- when two authors create reviews at the same time.

CREATE TABLE IF NOT EXISTS public."managementReviewDocumentSequence" (
    "Id" BOOLEAN PRIMARY KEY DEFAULT TRUE CHECK ("Id"),
    "LastNumber" BIGINT NOT NULL DEFAULT 0 CHECK ("LastNumber" >= 0),
    "UpdatedAt" TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

INSERT INTO public."managementReviewDocumentSequence" ("Id", "LastNumber")
VALUES (
    TRUE,
    COALESCE((
        SELECT MAX((substring("DocumentNo" FROM '-R([0-9]+)$'))::BIGINT)
        FROM public."managementReviewTbl"
        WHERE "DocumentNo" ~ '-R[0-9]+$'
    ), 0)
)
ON CONFLICT ("Id") DO UPDATE
SET "LastNumber" = GREATEST(
    public."managementReviewDocumentSequence"."LastNumber",
    EXCLUDED."LastNumber"
);

CREATE OR REPLACE FUNCTION public.save_management_review(
    p_id BIGINT DEFAULT NULL,
    p_project_id BIGINT DEFAULT NULL,
    p_tanggal_review DATE DEFAULT NULL,
    p_agenda TEXT DEFAULT '',
    p_review_inputs TEXT DEFAULT '',
    p_decisions TEXT DEFAULT '',
    p_status TEXT DEFAULT 'Draft',
    p_created_by_nama TEXT DEFAULT '',
    p_created_by_qrcode TEXT DEFAULT '',
    p_participants JSONB DEFAULT '[]'::jsonb,
    p_attachments JSONB DEFAULT '[]'::jsonb,
    p_document_no TEXT DEFAULT ''
) RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_id BIGINT;
    v_document_no TEXT;
    v_report_number BIGINT;
BEGIN
    IF p_project_id IS NULL OR p_tanggal_review IS NULL
       OR NULLIF(TRIM(p_agenda), '') IS NULL
       OR NULLIF(TRIM(p_created_by_nama), '') IS NULL THEN
        RAISE EXCEPTION 'Project, tanggal, agenda, dan identitas Author wajib diisi.';
    END IF;
    IF p_status NOT IN ('Draft', 'Scheduled', 'In Progress', 'Completed', 'Cancelled') THEN
        RAISE EXCEPTION 'Status Management Review tidak valid.';
    END IF;

    IF p_id IS NULL THEN
        PERFORM pg_advisory_xact_lock(hashtextextended('management-review-report-number', 0));

        INSERT INTO public."managementReviewDocumentSequence" ("Id", "LastNumber")
        VALUES (TRUE, 0)
        ON CONFLICT ("Id") DO NOTHING;

        UPDATE public."managementReviewDocumentSequence"
        SET "LastNumber" = "LastNumber" + 1, "UpdatedAt" = NOW()
        WHERE "Id" = TRUE
        RETURNING "LastNumber" INTO v_report_number;

        INSERT INTO public."managementReviewTbl" (
            "ProjectId", "TanggalReview", "DocumentNo", "Agenda", "ReviewInputs", "Decisions", "Status",
            "CreatedByNama", "CreatedByQrCodeId", "Participants", "Attachments"
        ) VALUES (
            p_project_id, p_tanggal_review,
            'MR-' || TO_CHAR(p_tanggal_review, 'YYYYMMDD') || '-P' || p_project_id
                || '-R' || LPAD(v_report_number::TEXT, 6, '0'),
            TRIM(p_agenda), COALESCE(p_review_inputs, ''), COALESCE(p_decisions, ''), p_status,
            TRIM(p_created_by_nama), COALESCE(p_created_by_qrcode, ''),
            COALESCE(p_participants, '[]'::jsonb), COALESCE(p_attachments, '[]'::jsonb)
        ) RETURNING "Id", "DocumentNo" INTO v_id, v_document_no;
    ELSE
        UPDATE public."managementReviewTbl"
        SET "ProjectId" = p_project_id,
            "TanggalReview" = p_tanggal_review,
            "DocumentNo" = CASE
                WHEN NULLIF(TRIM(p_document_no), '') IS NOT NULL
                     AND TRIM(p_document_no) !~ '^MR-[0-9]{8}-P[0-9]+(-R[0-9]+)?$'
                    THEN TRIM(p_document_no)
                ELSE "DocumentNo"
            END,
            "Agenda" = TRIM(p_agenda),
            "ReviewInputs" = COALESCE(p_review_inputs, ''),
            "Decisions" = COALESCE(p_decisions, ''),
            "Status" = p_status,
            "Participants" = COALESCE(p_participants, '[]'::jsonb),
            "Attachments" = COALESCE(p_attachments, '[]'::jsonb),
            "UpdatedAt" = NOW()
        WHERE "Id" = p_id
        RETURNING "Id", "DocumentNo" INTO v_id, v_document_no;
        IF v_id IS NULL THEN
            RAISE EXCEPTION 'Management Review tidak ditemukan.';
        END IF;
    END IF;

    RETURN jsonb_build_object('success', true, 'id', v_id, 'documentNo', v_document_no);
END;
$$;

GRANT EXECUTE ON FUNCTION public.save_management_review(
    BIGINT, BIGINT, DATE, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, JSONB, JSONB, TEXT
) TO anon, authenticated;
