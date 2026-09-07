-- Add structured Management Review topics to action plans.
-- Run after 046/047. Safe to rerun.

ALTER TABLE "managementReviewActionTbl"
    ADD COLUMN IF NOT EXISTS "Topic" TEXT NOT NULL DEFAULT 'Tindak lanjut review sebelumnya';

CREATE OR REPLACE FUNCTION public.save_management_review_action(
    p_id BIGINT DEFAULT NULL,
    p_review_id BIGINT DEFAULT NULL,
    p_topic TEXT DEFAULT 'Tindak lanjut review sebelumnya',
    p_action_item TEXT DEFAULT '',
    p_pic_nama TEXT DEFAULT '',
    p_pic_qrcode TEXT DEFAULT '',
    p_due_date DATE DEFAULT NULL,
    p_status TEXT DEFAULT 'Open',
    p_notes TEXT DEFAULT '',
    p_attachments JSONB DEFAULT '[]'::jsonb
) RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_id BIGINT;
BEGIN
    IF p_review_id IS NULL OR NULLIF(TRIM(p_action_item), '') IS NULL
       OR NULLIF(TRIM(p_pic_nama), '') IS NULL THEN
        RAISE EXCEPTION 'Review, action item, dan PIC wajib diisi.';
    END IF;
    IF p_status NOT IN ('Open', 'In Progress', 'Blocked', 'Completed', 'Cancelled') THEN
        RAISE EXCEPTION 'Status action item tidak valid.';
    END IF;
    IF p_id IS NULL THEN
        INSERT INTO "managementReviewActionTbl" (
            "ReviewId", "Topic", "ActionItem", "PicNama", "PicQrCodeId", "DueDate", "Status",
            "Notes", "Attachments"
        ) VALUES (
            p_review_id, COALESCE(NULLIF(TRIM(p_topic), ''), 'Tindak lanjut review sebelumnya'),
            TRIM(p_action_item), TRIM(p_pic_nama), COALESCE(p_pic_qrcode, ''),
            p_due_date, p_status, COALESCE(p_notes, ''), COALESCE(p_attachments, '[]'::jsonb)
        ) RETURNING "Id" INTO v_id;
    ELSE
        UPDATE "managementReviewActionTbl"
        SET "Topic" = COALESCE(NULLIF(TRIM(p_topic), ''), 'Tindak lanjut review sebelumnya'),
            "ActionItem" = TRIM(p_action_item), "PicNama" = TRIM(p_pic_nama),
            "PicQrCodeId" = COALESCE(p_pic_qrcode, ''), "DueDate" = p_due_date,
            "Status" = p_status, "Notes" = COALESCE(p_notes, ''),
            "Attachments" = COALESCE(p_attachments, '[]'::jsonb), "UpdatedAt" = NOW()
        WHERE "Id" = p_id AND "ReviewId" = p_review_id
        RETURNING "Id" INTO v_id;
        IF v_id IS NULL THEN RAISE EXCEPTION 'Action item tidak ditemukan.'; END IF;
    END IF;
    UPDATE "managementReviewTbl" SET "UpdatedAt" = NOW() WHERE "Id" = p_review_id;
    RETURN jsonb_build_object('success', true, 'id', v_id);
END;
$$;

CREATE OR REPLACE FUNCTION public.get_management_review_list(
    p_project_id BIGINT DEFAULT NULL,
    p_status TEXT DEFAULT NULL,
    p_search TEXT DEFAULT NULL
) RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_result JSONB;
BEGIN
    SELECT COALESCE(jsonb_agg(row_data ORDER BY review_date DESC, id DESC), '[]'::jsonb)
    INTO v_result
    FROM (
        SELECT jsonb_build_object(
            'id', r."Id", 'projectId', r."ProjectId", 'tanggalReview', r."TanggalReview",
            'documentNo', r."DocumentNo", 'agenda', r."Agenda", 'reviewInputs', r."ReviewInputs",
            'decisions', r."Decisions", 'status', r."Status", 'createdByNama', r."CreatedByNama",
            'createdByQrCodeId', r."CreatedByQrCodeId", 'participants', r."Participants",
            'attachments', r."Attachments", 'createdAt', r."CreatedAt", 'updatedAt', r."UpdatedAt",
            'namaProject', p."NamaProject", 'noKontrak', p."NoKontrak",
            'actions', COALESCE((
                SELECT jsonb_agg(jsonb_build_object(
                    'id', a."Id", 'reviewId', a."ReviewId", 'topic', a."Topic",
                    'actionItem', a."ActionItem", 'picNama', a."PicNama", 'picQrCodeId', a."PicQrCodeId",
                    'dueDate', a."DueDate", 'status', a."Status", 'notes', a."Notes",
                    'attachments', a."Attachments", 'createdAt', a."CreatedAt", 'updatedAt', a."UpdatedAt"
                ) ORDER BY a."DueDate" NULLS LAST, a."Id")
                FROM "managementReviewActionTbl" a WHERE a."ReviewId" = r."Id"
            ), '[]'::jsonb)
        ) AS row_data, r."TanggalReview" AS review_date, r."Id" AS id
        FROM "managementReviewTbl" r
        JOIN "projectTbl" p ON p."Id" = r."ProjectId"
        WHERE (p_project_id IS NULL OR r."ProjectId" = p_project_id)
          AND (p_status IS NULL OR p_status = '' OR r."Status" = p_status)
          AND (
            p_search IS NULL OR p_search = '' OR r."Agenda" ILIKE '%' || p_search || '%'
            OR r."ReviewInputs" ILIKE '%' || p_search || '%'
            OR r."Decisions" ILIKE '%' || p_search || '%'
            OR EXISTS (
                SELECT 1 FROM "managementReviewActionTbl" ax
                WHERE ax."ReviewId" = r."Id"
                  AND (ax."ActionItem" ILIKE '%' || p_search || '%' OR ax."PicNama" ILIKE '%' || p_search || '%')
            )
          )
    ) q;
    RETURN v_result;
END;
$$;

GRANT EXECUTE ON FUNCTION public.save_management_review_action(BIGINT, BIGINT, TEXT, TEXT, TEXT, TEXT, DATE, TEXT, TEXT, JSONB)
TO anon, authenticated;
