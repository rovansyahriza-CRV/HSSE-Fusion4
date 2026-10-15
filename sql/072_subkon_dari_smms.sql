-- =====================================================================================
-- HSSE-Fusion4 -- 072: register subkon diambil dari SMMS BIMA (vendor Approved di SmartGate)
-- Jalankan di project Supabase: HSSE-Fusion4 (BUKAN Fusion4 SmartGate). SmartGate tidak perlu diubah.
-- Butuh: 071 (modul subkon), 059 (manHoursAutoConfigTbl: URL + key SmartGate), extension http (065).
--
-- Cara kerja:
--   * Daftar perusahaan diambil dari tabel public.vendor di SmartGate (SMMS BIMA), hanya Status = 'Approved'.
--     Kolom bank / rekening tidak diambil.
--   * Tambah subkon = pilih vendor SMMS. Server sendiri yang tarik data vendornya (browser tidak bisa
--     mengarang data). Nama, bidang, alamat, kontak, telepon, email, NPWP dikunci ikut SMMS.
--   * Yang tetap diisi di HSSE: Status HSSE (Aktif / Tidak Aktif / Daftar Hitam), jabatan kontak, No. NIB,
--     keterangan, plus dokumen, pekerjaan dan evaluasi CSMS seperti biasa.
--   * Data SMMS disalin saat subkon dipilih, dan diperbarui lewat tombol "Sinkron dari SMMS"
--     (sinkron_subkon_smms) atau saat subkon itu disimpan ulang. Vendor yang tidak Approved lagi di SMMS
--     ditandai, tapi status HSSE-nya tidak diubah otomatis.
-- Aman dijalankan ulang.
-- =====================================================================================

-- -------------------------------------------------------------------------------------
-- 1. Kolom tambahan di subkonTbl
-- -------------------------------------------------------------------------------------
ALTER TABLE "subkonTbl" ADD COLUMN IF NOT EXISTS "VendorIdSmms"  BIGINT;
ALTER TABLE "subkonTbl" ADD COLUMN IF NOT EXISTS "NPWP"          TEXT;
ALTER TABLE "subkonTbl" ADD COLUMN IF NOT EXISTS "KategoriSmms"  TEXT;
ALTER TABLE "subkonTbl" ADD COLUMN IF NOT EXISTS "StatusSmms"    TEXT;          -- 'Approved' / 'Tidak ada di SMMS'
ALTER TABLE "subkonTbl" ADD COLUMN IF NOT EXISTS "SinkronSmmsAt" TIMESTAMPTZ;
CREATE UNIQUE INDEX IF NOT EXISTS uq_subkon_vendor_smms ON "subkonTbl" ("VendorIdSmms") WHERE "VendorIdSmms" IS NOT NULL;

-- -------------------------------------------------------------------------------------
-- 2. Tarik vendor dari SmartGate (internal, tidak bisa dipanggil dari browser)
--    p_vendor_id NULL = semua vendor Approved. Hasil: array JSON
--    [{VendorID, VendorName, AuthorizeName, Specialist, Address, ContactNo, NPWP, Catagory, Email, Status}]
-- -------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.subkon_smms_ambil(p_vendor_id BIGINT DEFAULT NULL)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, extensions AS $$
DECLARE
    v_url  TEXT;
    v_key  TEXT;
    v_resp RECORD;
BEGIN
    SELECT "SmartGateUrl", "SmartGateKey" INTO v_url, v_key FROM "manHoursAutoConfigTbl" WHERE "Id" = 1;
    IF COALESCE(v_url, '') = '' OR COALESCE(v_key, '') = '' THEN
        RAISE EXCEPTION 'Setting koneksi SmartGate belum ada (manHoursAutoConfigTbl, migrasi 059).';
    END IF;

    BEGIN
        PERFORM http_set_curlopt('CURLOPT_TIMEOUT', '15');
        SELECT status, content INTO v_resp
        FROM http((
            'GET',
            rtrim(v_url, '/') || '/rest/v1/vendor?select=VendorID,VendorName,AuthorizeName,Specialist,Address,'
                || 'ContactNo,NPWP,Catagory,Email,Status&Status=eq.Approved&order=VendorName.asc'
                || CASE WHEN p_vendor_id IS NULL THEN '' ELSE '&VendorID=eq.' || p_vendor_id END,
            ARRAY[http_header('apikey', v_key), http_header('Authorization', 'Bearer ' || v_key)],
            NULL, NULL
        )::http_request);
    EXCEPTION WHEN OTHERS THEN
        RAISE EXCEPTION 'SMMS (SmartGate) gak bisa dihubungi, coba lagi sebentar. (%)', SQLERRM;
    END;
    IF v_resp.status IS DISTINCT FROM 200 THEN
        RAISE EXCEPTION 'SMMS (SmartGate) gak bisa dihubungi (HTTP %), coba lagi sebentar.', v_resp.status;
    END IF;
    RETURN COALESCE(v_resp.content::JSONB, '[]'::JSONB);
END;
$$;
REVOKE EXECUTE ON FUNCTION public.subkon_smms_ambil(BIGINT) FROM PUBLIC, anon, authenticated;

-- Salin data satu vendor SMMS ke baris subkon (kolom yang dikunci)
CREATE OR REPLACE FUNCTION public.subkon_smms_terapkan(p_subkon_id BIGINT, v JSONB)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
    v_nama TEXT := NULLIF(trim(v->>'VendorName'), '');
BEGIN
    IF v_nama IS NULL THEN
        RAISE EXCEPTION 'Vendor SMMS % tidak punya nama.', v->>'VendorID';
    END IF;
    IF EXISTS (SELECT 1 FROM "subkonTbl" WHERE lower(trim("NamaPerusahaan")) = lower(v_nama) AND "Id" <> p_subkon_id) THEN
        RAISE EXCEPTION 'Nama "%" sudah dipakai subkon lain di HSSE. Hubungkan subkon itu ke vendor SMMS-nya saja.', v_nama;
    END IF;
    UPDATE "subkonTbl" SET
        "VendorIdSmms"  = (v->>'VendorID')::BIGINT,
        "NamaPerusahaan" = v_nama,
        "BidangUsaha"   = COALESCE(NULLIF(trim(v->>'Specialist'), ''), NULLIF(trim(v->>'Catagory'), '')),
        "KategoriSmms"  = NULLIF(trim(v->>'Catagory'), ''),
        "Alamat"        = NULLIF(trim(v->>'Address'), ''),
        "NamaKontak"    = NULLIF(trim(v->>'AuthorizeName'), ''),
        "Telepon"       = NULLIF(trim(v->>'ContactNo'), ''),
        "Email"         = NULLIF(trim(v->>'Email'), ''),
        "NPWP"          = NULLIF(trim(v->>'NPWP'), ''),
        "StatusSmms"    = 'Approved',
        "SinkronSmmsAt" = now()
    WHERE "Id" = p_subkon_id;
END;
$$;
REVOKE EXECUTE ON FUNCTION public.subkon_smms_terapkan(BIGINT, JSONB) FROM PUBLIC, anon, authenticated;

-- -------------------------------------------------------------------------------------
-- 3. Header subkon: tambah info SMMS
-- -------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.subkon_header_json(s "subkonTbl")
RETURNS JSONB LANGUAGE sql STABLE SET search_path = public AS $$
    WITH dok AS (
        SELECT count(*) FILTER (WHERE d."BerlakuSampai" < (now() AT TIME ZONE 'Asia/Jakarta')::DATE) AS habis,
               count(*) FILTER (WHERE d."BerlakuSampai" >= (now() AT TIME ZONE 'Asia/Jakarta')::DATE
                                  AND d."BerlakuSampai" - (now() AT TIME ZONE 'Asia/Jakarta')::DATE <= 30) AS segera,
               count(*) AS jumlah
        FROM public.subkon_dokumen_terkini(s."Id") d
    ), pk AS (
        SELECT count(*) AS jumlah, count(*) FILTER (WHERE p."Status" = 'Berjalan') AS berjalan,
               string_agg(DISTINCT COALESCE(pr."KodeOperational", pr."NamaProject"), ', ') AS project
        FROM "subkonPekerjaanTbl" p JOIN "projectTbl" pr ON pr."Id" = p."ProjectId"
        WHERE p."SubkonId" = s."Id" AND p."Status" <> 'Dibatalkan'
    ), fin AS (
        SELECT e."NilaiPersen", e."Hasil", e."TanggalEvaluasi"
        FROM "subkonEvaluasiTbl" e
        WHERE e."SubkonId" = s."Id" AND e."Tahap" = 'Final Evaluation' AND e."Status" = 'Disetujui'
        ORDER BY e."TanggalEvaluasi" DESC, e."Id" DESC LIMIT 1
    ), pq AS (
        SELECT e."NilaiPersen", e."Hasil", e."TanggalEvaluasi"
        FROM "subkonEvaluasiTbl" e
        WHERE e."SubkonId" = s."Id" AND e."Tahap" = 'Prakualifikasi' AND e."Status" = 'Disetujui'
        ORDER BY e."TanggalEvaluasi" DESC, e."Id" DESC LIMIT 1
    ), ev AS (
        SELECT count(*) FILTER (WHERE e."Status" = 'Menunggu Approval') AS menunggu
        FROM "subkonEvaluasiTbl" e WHERE e."SubkonId" = s."Id"
    )
    SELECT jsonb_build_object(
        'id', s."Id", 'kodeSubkon', s."KodeSubkon", 'namaPerusahaan', s."NamaPerusahaan",
        'bidangUsaha', s."BidangUsaha", 'alamat', s."Alamat", 'noNIB', s."NoNIB",
        'namaKontak', s."NamaKontak", 'jabatanKontak', s."JabatanKontak", 'telepon', s."Telepon", 'email', s."Email",
        'status', s."Status", 'keterangan', s."Keterangan",
        'vendorIdSmms', s."VendorIdSmms", 'npwp', s."NPWP", 'kategoriSmms', s."KategoriSmms",
        'statusSmms', s."StatusSmms", 'sinkronSmmsAt', s."SinkronSmmsAt",
        'dibuatOleh', s."DibuatOleh", 'diubahOleh', s."DiubahOleh", 'createdAt', s."CreatedAt", 'updatedAt', s."UpdatedAt",
        'jumlahDokumen', dok.jumlah, 'dokumenKedaluwarsa', dok.habis, 'dokumenSegeraHabis', dok.segera,
        'jumlahPekerjaan', pk.jumlah, 'pekerjaanBerjalan', pk.berjalan, 'project', pk.project,
        'evaluasiMenunggu', ev.menunggu,
        'prakualifikasiTerakhir', (SELECT jsonb_build_object('nilai', pq."NilaiPersen", 'hasil', pq."Hasil", 'tanggal', pq."TanggalEvaluasi") FROM pq),
        'finalTerakhir', (SELECT jsonb_build_object('nilai', fin."NilaiPersen", 'hasil', fin."Hasil", 'tanggal', fin."TanggalEvaluasi") FROM fin))
    FROM dok, pk, ev;
$$;

-- -------------------------------------------------------------------------------------
-- 4. Baca: daftar vendor SMMS untuk dipilih (tanpa data bank/rekening)
--    Hasil: [{vendorId, nama, bidang, kategori, alamat, kontak, telepon, email, npwp, subkonId, kodeSubkon}]
--    subkonId terisi kalau vendor itu sudah jadi subkon di HSSE.
-- -------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_smms_vendor_list()
RETURNS JSONB LANGUAGE sql SECURITY DEFINER SET search_path = public AS $$
    SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'vendorId', (v->>'VendorID')::BIGINT, 'nama', v->>'VendorName',
        'bidang', NULLIF(trim(v->>'Specialist'), ''), 'kategori', v->>'Catagory',
        'alamat', v->>'Address', 'kontak', v->>'AuthorizeName', 'telepon', v->>'ContactNo',
        'email', v->>'Email', 'npwp', v->>'NPWP',
        'subkonId', s."Id", 'kodeSubkon', s."KodeSubkon") ORDER BY lower(v->>'VendorName')), '[]'::JSONB)
    FROM jsonb_array_elements(public.subkon_smms_ambil(NULL)) v
    LEFT JOIN "subkonTbl" s ON s."VendorIdSmms" = (v->>'VendorID')::BIGINT;
$$;

-- -------------------------------------------------------------------------------------
-- 5. Tulis
-- -------------------------------------------------------------------------------------
-- p_data: {vendorIdSmms, jabatanKontak, noNIB, status, keterangan}
--   Subkon baru wajib pilih vendorIdSmms. Subkon lama (dibuat manual di 071) bisa dihubungkan ke vendor
--   SMMS dengan mengirim vendorIdSmms. Kolom perusahaan lain diabaikan: diisi dari SMMS oleh server.
--   Setiap simpan subkon yang terhubung juga memperbarui data SMMS-nya.
CREATE OR REPLACE FUNCTION public.save_subkon(p_aktor_nama TEXT, p_aktor_qr TEXT, p_id BIGINT, p_data JSONB)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
    v_id     BIGINT := p_id;
    v_vendor BIGINT := NULLIF(p_data->>'vendorIdSmms', '')::BIGINT;
    v_lama   "subkonTbl";
    v_smms   JSONB;
    v_seq    INT;
    v_status TEXT := COALESCE(NULLIF(p_data->>'status', ''), 'Aktif');
    v_nama   TEXT := COALESCE(NULLIF(trim(p_aktor_nama), ''), upper(trim(p_aktor_qr)));
BEGIN
    PERFORM public.hsse_wajib_akses(p_aktor_nama, p_aktor_qr, 'HSSE-SUB');

    IF v_id IS NOT NULL THEN
        SELECT * INTO v_lama FROM "subkonTbl" WHERE "Id" = v_id;
        IF NOT FOUND THEN
            RAISE EXCEPTION 'Subkon % tidak ditemukan.', v_id;
        END IF;
        IF v_lama."VendorIdSmms" IS NOT NULL AND v_vendor IS NOT NULL AND v_vendor <> v_lama."VendorIdSmms" THEN
            RAISE EXCEPTION 'Subkon ini sudah terhubung ke vendor SMMS lain, tidak bisa diganti.';
        END IF;
        v_vendor := COALESCE(v_lama."VendorIdSmms", v_vendor);
    ELSIF v_vendor IS NULL THEN
        RAISE EXCEPTION 'Pilih perusahaan dari daftar vendor SMMS BIMA dulu.';
    END IF;

    IF v_vendor IS NOT NULL THEN
        IF EXISTS (SELECT 1 FROM "subkonTbl" WHERE "VendorIdSmms" = v_vendor AND "Id" IS DISTINCT FROM v_id) THEN
            RAISE EXCEPTION 'Vendor SMMS ini sudah terdaftar sebagai subkon.';
        END IF;
        v_smms := public.subkon_smms_ambil(v_vendor) -> 0;
        IF v_smms IS NULL AND (v_lama."Id" IS NULL OR v_lama."VendorIdSmms" IS NULL) THEN
            RAISE EXCEPTION 'Vendor % tidak ada (atau belum Approved) di SMMS BIMA.', v_vendor;
        END IF;
    END IF;

    IF v_id IS NULL THEN
        PERFORM pg_advisory_xact_lock(hashtext('subkon_kode'));
        SELECT COALESCE(max(substring("KodeSubkon" FROM '(\d+)$')::INT), 0) + 1 INTO v_seq FROM "subkonTbl";
        INSERT INTO "subkonTbl" ("KodeSubkon", "NamaPerusahaan", "VendorIdSmms", "Status", "DibuatOleh", "DibuatQrCodeId", "DiubahOleh")
        VALUES ('SUB-' || lpad(v_seq::TEXT, 4, '0'), '(vendor ' || v_vendor || ')', v_vendor, v_status,
                v_nama, upper(trim(p_aktor_qr)), v_nama)
        RETURNING "Id" INTO v_id;
    END IF;

    UPDATE "subkonTbl" SET
        "JabatanKontak" = NULLIF(trim(p_data->>'jabatanKontak'), ''),
        "NoNIB"         = NULLIF(trim(p_data->>'noNIB'), ''),
        "Status"        = v_status,
        "Keterangan"    = NULLIF(trim(p_data->>'keterangan'), ''),
        "DiubahOleh"    = v_nama, "UpdatedAt" = now()
    WHERE "Id" = v_id;

    IF v_smms IS NOT NULL THEN
        PERFORM public.subkon_smms_terapkan(v_id, v_smms);
    ELSIF v_vendor IS NOT NULL THEN
        -- sudah terhubung, tapi vendornya tidak Approved lagi di SMMS: data lama dipertahankan
        UPDATE "subkonTbl" SET "StatusSmms" = 'Tidak ada di SMMS', "SinkronSmmsAt" = now() WHERE "Id" = v_id;
    END IF;
    RETURN public.get_subkon_detail(v_id);
END;
$$;

-- Perbarui semua subkon yang terhubung dari SMMS sekaligus.
-- Hasil: {diperbarui, tidakAdaDiSmms: [nama...], belumTerhubung}
CREATE OR REPLACE FUNCTION public.sinkron_subkon_smms(p_aktor_nama TEXT, p_aktor_qr TEXT)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
    v_list   JSONB;
    v        JSONB;
    s        RECORD;
    v_ok     INT := 0;
    v_hilang TEXT[] := '{}';
BEGIN
    PERFORM public.hsse_wajib_akses(p_aktor_nama, p_aktor_qr, 'HSSE-SUB');
    v_list := public.subkon_smms_ambil(NULL);
    FOR s IN SELECT "Id", "VendorIdSmms", "NamaPerusahaan" FROM "subkonTbl" WHERE "VendorIdSmms" IS NOT NULL LOOP
        SELECT x INTO v FROM jsonb_array_elements(v_list) x WHERE (x->>'VendorID')::BIGINT = s."VendorIdSmms";
        IF v IS NULL THEN
            UPDATE "subkonTbl" SET "StatusSmms" = 'Tidak ada di SMMS', "SinkronSmmsAt" = now() WHERE "Id" = s."Id";
            v_hilang := v_hilang || s."NamaPerusahaan";
        ELSE
            PERFORM public.subkon_smms_terapkan(s."Id", v);
            v_ok := v_ok + 1;
        END IF;
    END LOOP;
    RETURN jsonb_build_object('diperbarui', v_ok, 'tidakAdaDiSmms', to_jsonb(v_hilang),
        'belumTerhubung', (SELECT count(*) FROM "subkonTbl" WHERE "VendorIdSmms" IS NULL));
END;
$$;

REVOKE EXECUTE ON FUNCTION public.get_smms_vendor_list() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.sinkron_subkon_smms(TEXT, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_smms_vendor_list() TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.sinkron_subkon_smms(TEXT, TEXT) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.save_subkon(TEXT, TEXT, BIGINT, JSONB) TO anon, authenticated;

NOTIFY pgrst, 'reload schema';

-- =====================================================================================
-- CEK SETELAH JALAN (di HSSE-Fusion4)
-- =====================================================================================
-- 1) Harus keluar daftar vendor Approved SMMS (8 vendor per 15 Okt 2026), tanpa kolom bank/rekening:
-- SELECT jsonb_array_length(public.get_smms_vendor_list()), public.get_smms_vendor_list() -> 0;
-- 2) Kolom baru ada:
-- SELECT column_name FROM information_schema.columns WHERE table_name = 'subkonTbl' AND column_name ILIKE '%smms%' OR column_name = 'NPWP';

-- =====================================================================================
-- ROLLBACK (kalau perlu balik ke input manual 071): jalankan ulang bagian save_subkon + subkon_header_json
-- dari 071, lalu:
-- DROP FUNCTION IF EXISTS public.sinkron_subkon_smms(TEXT, TEXT), public.get_smms_vendor_list(),
--   public.subkon_smms_terapkan(BIGINT, JSONB), public.subkon_smms_ambil(BIGINT);
-- (kolom VendorIdSmms, NPWP, KategoriSmms, StatusSmms, SinkronSmmsAt boleh dibiarkan)
-- =====================================================================================
