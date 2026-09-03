-- =====================================================================================
-- HSSE-Fusion4 — MIGRASI #15: INSPEKSI/OBSERVASI -- FOTO PER ITEM JADI SAMPAI 3 (dulu 1),
-- DAN HASIL DIPILIH LEWAT DROPDOWN (bukan 3 tombol) -- keterangan & foto sekarang selalu
-- ada per item (gak cuma muncul pas "Tidak Sesuai").
-- Jalankan SETELAH 001-014, di Supabase project HSSE-Fusion4.
--
-- Perubahan struktur JSONB tiap item di ChecklistItems:
--   SEBELUM: { "id":.., "kategori":.., "item":.., "hasil":.., "keterangan":.., "foto": {url,fileId}|null }
--   SESUDAH: { "id":.., "kategori":.., "item":.., "hasil":.., "keterangan":.., "fotoList": [{url,fileId}, ...] }
-- (field lama "foto" tetap dibaca sbg fallback biar data lama yang udah kesimpen gak error
-- pas ditampilin, tapi laporan BARU pakai "fotoList").
--
-- Cuma submit_inspeksi_report yang perlu diganti (baca "fotoList", bukan "foto" tunggal) --
-- signature parameternya SAMA (p_checklist_items masih JSONB), jadi CREATE OR REPLACE aja.
-- =====================================================================================

CREATE OR REPLACE FUNCTION submit_inspeksi_report(
    p_jenis TEXT,
    p_project_id BIGINT,
    p_nama_inspektor TEXT,
    p_lokasi_area TEXT,
    p_checklist_items JSONB,
    p_inspektor_qrcode TEXT DEFAULT '',
    p_catatan_umum TEXT DEFAULT '',
    p_foto_umum_list JSONB DEFAULT '[]'::jsonb
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_no_laporan TEXT;
    v_id BIGINT;
    v_sesuai INT := 0;
    v_tidak INT := 0;
    v_na INT := 0;
    v_skor NUMERIC(5,2);
    v_item JSONB;
    v_deskripsi TEXT := '';
    v_foto_cermat JSONB := '[]'::jsonb;
    v_cermat_result JSONB;
    v_cermat_id BIGINT;
    v_cermat_no TEXT;
BEGIN
    IF p_jenis NOT IN ('Inspeksi', 'Observasi') THEN
        RAISE EXCEPTION 'Jenis harus Inspeksi atau Observasi';
    END IF;
    IF p_checklist_items IS NULL OR jsonb_array_length(p_checklist_items) = 0 THEN
        RAISE EXCEPTION 'Checklist tidak boleh kosong';
    END IF;

    FOR v_item IN SELECT * FROM jsonb_array_elements(p_checklist_items) LOOP
        IF v_item->>'hasil' = 'Sesuai' THEN
            v_sesuai := v_sesuai + 1;
        ELSIF v_item->>'hasil' = 'Tidak Sesuai' THEN
            v_tidak := v_tidak + 1;
            v_deskripsi := v_deskripsi || '- [' || COALESCE(v_item->>'kategori', '') || '] ' || COALESCE(v_item->>'item', '')
                || CASE WHEN COALESCE(v_item->>'keterangan', '') <> '' THEN ' — ' || (v_item->>'keterangan') ELSE '' END
                || E'\n';
            -- fotoList (array, baru) -- fallback ke "foto" tunggal (data lama) kalau fotoList gak ada.
            IF v_item->'fotoList' IS NOT NULL AND jsonb_typeof(v_item->'fotoList') = 'array' THEN
                v_foto_cermat := v_foto_cermat || (v_item->'fotoList');
            ELSIF v_item->'foto' IS NOT NULL AND v_item->'foto' <> 'null'::jsonb THEN
                v_foto_cermat := v_foto_cermat || jsonb_build_array(v_item->'foto');
            END IF;
        ELSE
            v_na := v_na + 1;
        END IF;
    END LOOP;

    v_skor := CASE WHEN (v_sesuai + v_tidak) > 0
        THEN ROUND((v_sesuai::NUMERIC / (v_sesuai + v_tidak)) * 100, 2)
        ELSE NULL END;

    v_no_laporan := generate_no_inspeksi(p_jenis);

    INSERT INTO "inspeksiTbl" (
        "NoLaporan", "Jenis", "ProjectId", "NamaInspektor", "InspektorQrCodeId", "LokasiArea",
        "ChecklistItems", "CatatanUmum", "FotoUmumList", "JumlahSesuai", "JumlahTidakSesuai", "JumlahNA", "SkorPersen"
    ) VALUES (
        v_no_laporan, p_jenis, p_project_id, p_nama_inspektor, p_inspektor_qrcode, p_lokasi_area,
        p_checklist_items, p_catatan_umum, p_foto_umum_list, v_sesuai, v_tidak, v_na, v_skor
    )
    RETURNING "Id" INTO v_id;

    IF v_tidak > 0 THEN
        v_cermat_result := submit_cermat_report(
            p_project_id,
            p_nama_inspektor,
            'Negatif',
            'Unsafe Condition',
            p_lokasi_area,
            'Temuan dari ' || p_jenis || ' Lapangan No. ' || v_no_laporan || ':' || E'\n' || v_deskripsi,
            p_inspektor_qrcode,
            v_foto_cermat,
            '',
            ''
        );
        v_cermat_id := (v_cermat_result->>'id')::BIGINT;
        v_cermat_no := v_cermat_result->>'noLaporan';

        UPDATE "cermatTbl" SET "SourceInspeksiId" = v_id WHERE "Id" = v_cermat_id;
        UPDATE "inspeksiTbl" SET "CermatId" = v_cermat_id, "CermatNoLaporan" = v_cermat_no WHERE "Id" = v_id;
    END IF;

    RETURN jsonb_build_object(
        'success', true,
        'id', v_id,
        'noLaporan', v_no_laporan,
        'skorPersen', v_skor,
        'jumlahSesuai', v_sesuai,
        'jumlahTidakSesuai', v_tidak,
        'jumlahNA', v_na,
        'cermatId', v_cermat_id,
        'cermatNoLaporan', v_cermat_no
    );
END;
$$;
