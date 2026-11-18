// =====================================================================================
// HSSE-Fusion4 — Modul bersama SCAN WAJAH (dipakai semua form & modal verifikasi).
// Dulu kode ini dicopy terpisah di ~18 halaman dan perilakunya beda-beda. Sekarang semua
// halaman manggil helper di sini, jadi perbaikan cukup sekali.
//
// Wajib dimuat SETELAH face-api.js:
//   <script src="https://cdn.jsdelivr.net/npm/face-api.js@0.22.2/dist/face-api.min.js"></script>
//   <script src="faceScan.js"></script>
//
// API:
//   await HsseFace.loadModels()                 -> muat model (sekali, ada fallback CDN + timeout)
//   await HsseFace.openCamera(video, facing)    -> buka kamera dgn pesan error yang jelas
//   HsseFace.stopCamera(video)
//   await HsseFace.fetchFaceData(fusion4Client) -> get_all_face_data + timeout + normalisasi descriptor
//   await HsseFace.detect(video[, {frames}])    -> ambil 5 frame wajah (atau null)
//   HsseFace.match(detection|descriptor, list)  -> { best, second, withinThreshold, isAmbiguous }
//   HsseFace.autoScan(video, scanButton)        -> deteksi otomatis tanpa klik; kalau cocok
//                                                  stabil, tombol Scan Wajah "ditekan" sendiri
//   HsseFace.lastHint()                         -> saran kenapa wajah gak kedeteksi
//
// ATURAN COCOK (konsensus beberapa frame) -- lebih baik MENOLAK daripada salah orang:
//   - wajah diambil 5 frame berturut-turut;
//   - orang yang sama harus jadi kandidat #1 di minimal 4 dari 5 frame;
//   - rata-rata jarak ke orang itu <= 0.45 (ambang sama dgn SmartGate Fusion4);
//   - rata-rata jarak ke orang #2 (BEDA orang) harus lebih jauh minimal 0.10.
// Kenapa: data wajah terdaftar di Fusion4 saling berdekatan (cek 18-11-2026: dari 105 orang,
// 33 orang punya "kembaran" dgn jarak < 0.35), jadi 1 frame saja sering ragu-ragu. Rata-rata
// 5 frame mengurangi noise kamera, sehingga selisih 0.10 di sini setara/lebih ketat dari
// selisih 0.12 di 1 frame.
// =====================================================================================
(function () {
  const THRESHOLD = 0.45;        // sama dgn Fusion4 SmartGate
  const AMBIGUITY_MARGIN = 0.12; // selisih minimal #1 vs #2 kalau cuma 1 frame
  const MULTI_MARGIN = 0.10;     // selisih minimal #1 vs #2 dari rata-rata beberapa frame
  const CONSENSUS_FRAMES = 5;    // jumlah frame per keputusan
  const CONSENSUS_AGREE = 0.8;   // orang yang sama jadi #1 di >= 80% frame (4 dari 5)
  const MAX_FRAME_DISTANCE = 0.52; // tiap frame yg "setuju" gak boleh terlalu jauh
  const AUTO_TIMEOUT_MS = 30000; // auto-detect berhenti sendiri kalau 30 dtk gak dikenali
  const MODEL_URLS = [
    'https://cdn.jsdelivr.net/gh/justadudewhohacks/face-api.js/weights',
    'https://cdn.jsdelivr.net/gh/justadudewhohacks/face-api.js@master/weights',
    'https://raw.githubusercontent.com/justadudewhohacks/face-api.js/master/weights',
  ];
  const MODEL_TIMEOUT_MS = 45000;
  const RPC_TIMEOUT_MS = 20000;
  const FACE_CACHE_MS = 5 * 60 * 1000;

  let modelsPromise = null;
  let lastHintText = '';
  let lastList = null;      // daftar wajah terakhir dari fetchFaceData (dipakai autoScan)
  let autoResult = null;    // { video, result, at } hasil autoScan yang siap dipakai detect()
  let manualBusy = false;
  const openVideos = new Set();
  const faceCache = new WeakMap(); // client -> { at, data }

  function withTimeout(promise, ms, message) {
    let timer;
    return Promise.race([
      promise,
      new Promise((_, reject) => { timer = setTimeout(() => reject(new Error(message)), ms); }),
    ]).finally(() => clearTimeout(timer));
  }

  function isNetworkError(e) {
    const msg = String((e && e.message) || e || '');
    return /failed to fetch|networkerror|load failed|network request failed|fetch failed/i.test(msg);
  }

  // ---------------------------------------------------------------------------------
  // MODEL
  // ---------------------------------------------------------------------------------
  function allLoaded() {
    const n = faceapi.nets;
    return n.tinyFaceDetector.isLoaded && n.faceLandmark68Net.isLoaded && n.faceRecognitionNet.isLoaded;
  }

  async function loadFrom(url) {
    const n = faceapi.nets;
    const jobs = [];
    if (!n.tinyFaceDetector.isLoaded) jobs.push(n.tinyFaceDetector.loadFromUri(url));
    if (!n.faceLandmark68Net.isLoaded) jobs.push(n.faceLandmark68Net.loadFromUri(url));
    if (!n.faceRecognitionNet.isLoaded) jobs.push(n.faceRecognitionNet.loadFromUri(url));
    await Promise.all(jobs);
  }

  function loadModels() {
    if (typeof faceapi === 'undefined') {
      return Promise.reject(new Error('Library pengenal wajah gagal dimuat. Cek koneksi internet lalu muat ulang halaman.'));
    }
    if (allLoaded()) return Promise.resolve();
    if (modelsPromise) return modelsPromise;
    modelsPromise = (async () => {
      let lastErr = null;
      for (const url of MODEL_URLS) {
        try {
          await withTimeout(loadFrom(url), MODEL_TIMEOUT_MS, 'timeout');
          if (allLoaded()) return;
        } catch (e) {
          lastErr = e;
          console.warn('[HsseFace] gagal muat model dari', url, e);
        }
      }
      throw new Error('Model wajah gagal diunduh' +
        (lastErr && lastErr.message === 'timeout' ? ' (koneksi terlalu lambat)' : '') +
        '. Cek sinyal/internet lalu coba lagi, atau pakai QR Code/PIN.');
    })();
    modelsPromise.catch(() => { modelsPromise = null; }); // boleh dicoba ulang
    return modelsPromise;
  }

  // ---------------------------------------------------------------------------------
  // KAMERA
  // ---------------------------------------------------------------------------------
  function cameraError(e) {
    const name = (e && e.name) || '';
    if (name === 'NotAllowedError' || name === 'PermissionDeniedError' || name === 'SecurityError') {
      return new Error('Izin kamera ditolak. Izinkan akses Kamera untuk situs ini di pengaturan browser (ikon gembok di address bar), lalu muat ulang halaman.');
    }
    if (name === 'NotFoundError' || name === 'DevicesNotFoundError' || name === 'OverconstrainedError') {
      return new Error('Kamera tidak ditemukan di perangkat ini.');
    }
    if (name === 'NotReadableError' || name === 'TrackStartError' || name === 'AbortError') {
      return new Error('Kamera sedang dipakai aplikasi/tab lain. Tutup dulu aplikasi itu lalu coba lagi.');
    }
    return new Error((e && e.message) || 'Kamera gagal dibuka.');
  }

  function stopCamera(video) {
    if (!video) return;
    const s = video.srcObject;
    if (s && s.getTracks) s.getTracks().forEach(t => t.stop());
    video.srcObject = null;
    openVideos.delete(video);
    removeOverlay(video);
  }

  function waitForVideo(video) {
    if (video.readyState >= 1 && video.videoWidth) return Promise.resolve();
    return withTimeout(new Promise(resolve => {
      const done = () => { video.removeEventListener('loadedmetadata', done); resolve(); };
      video.addEventListener('loadedmetadata', done);
    }), 10000, 'Kamera tidak merespon. Tutup aplikasi lain yang pakai kamera lalu coba lagi.');
  }

  async function openCamera(video, facingMode) {
    stopCamera(video);
    if (!window.isSecureContext) {
      throw new Error('Kamera hanya bisa dipakai lewat alamat HTTPS. Buka aplikasi dari link resmi (https://...).');
    }
    if (!navigator.mediaDevices || !navigator.mediaDevices.getUserMedia) {
      throw new Error('Browser ini tidak mendukung kamera. Buka link di Chrome atau Safari (bukan browser bawaan WhatsApp/Instagram/Facebook).');
    }
    const facing = facingMode || 'user';
    const attempts = [
      { video: { facingMode: { ideal: facing }, width: { ideal: 1280 }, height: { ideal: 720 } }, audio: false },
      { video: { facingMode: { ideal: facing } }, audio: false },
      { video: true, audio: false },
    ];
    let stream = null, lastErr = null;
    for (const c of attempts) {
      try { stream = await navigator.mediaDevices.getUserMedia(c); break; }
      catch (e) {
        lastErr = e;
        // Izin ditolak / gak aman: percuma dicoba ulang dgn constraint lain.
        if (e && (e.name === 'NotAllowedError' || e.name === 'PermissionDeniedError' || e.name === 'SecurityError')) break;
      }
    }
    if (!stream) throw cameraError(lastErr);

    video.setAttribute('playsinline', '');
    video.setAttribute('muted', '');
    video.muted = true;
    video.srcObject = stream;
    openVideos.add(video);
    try {
      await waitForVideo(video);
      try { await video.play(); } catch (e) { /* autoplay muted -- biasanya tetap jalan */ }
    } catch (e) {
      stopCamera(video);
      throw e;
    }
    // Kamera depan ditampilkan seperti cermin biar gampang posisiin wajah (cuma tampilan,
    // snapshot ke canvas tetap gambar asli).
    video.style.transform = facing === 'user' ? 'scaleX(-1)' : '';
    return stream;
  }

  // Matikan kamera kalau halaman ditutup / pindah halaman (biar lampu kamera gak nyala terus).
  window.addEventListener('pagehide', () => { openVideos.forEach(v => stopCamera(v)); });

  // ---------------------------------------------------------------------------------
  // DATA WAJAH (Fusion4, read-only)
  // ---------------------------------------------------------------------------------
  function toDescriptor(raw) {
    if (!raw) return null;
    let d = raw;
    if (typeof d === 'string') { try { d = JSON.parse(d); } catch (e) { return null; } }
    if (d && !Array.isArray(d) && !(d instanceof Float32Array) && typeof d === 'object') {
      if (Array.isArray(d.descriptor)) d = d.descriptor;
      else d = Object.keys(d).sort((a, b) => Number(a) - Number(b)).map(k => d[k]);
    }
    if (!d || d.length !== 128) return null;
    const out = new Float32Array(128);
    for (let i = 0; i < 128; i++) {
      const v = Number(d[i]);
      if (!isFinite(v)) return null;
      out[i] = v;
    }
    return out;
  }

  async function fetchFaceData(client, opts) {
    const force = opts && opts.force;
    const cached = faceCache.get(client);
    if (!force && cached && Date.now() - cached.at < FACE_CACHE_MS) { lastList = cached.data; return cached.data; }

    let res;
    try {
      res = await withTimeout(client.rpc('get_all_face_data'), RPC_TIMEOUT_MS, '__timeout__');
    } catch (e) {
      if (e && e.message === '__timeout__') {
        throw new Error('Server data karyawan (Fusion4) tidak merespon. Mungkin sedang sibuk atau di-pause. Coba lagi beberapa saat, atau pakai QR Code/PIN.');
      }
      if (isNetworkError(e)) throw new Error('Tidak bisa terhubung ke server data karyawan. Cek koneksi internet lalu coba lagi.');
      throw e;
    }
    const { data, error } = res || {};
    if (error) {
      if (isNetworkError(error)) throw new Error('Tidak bisa terhubung ke server data karyawan. Cek koneksi internet lalu coba lagi.');
      throw new Error(error.message || 'Gagal ambil data wajah.');
    }
    const list = (Array.isArray(data) ? data : []).map(p => {
      const out = Object.assign({}, p);
      out.descriptor = toDescriptor(p.descriptor || p.facecode);
      return out;
    });
    faceCache.set(client, { at: Date.now(), data: list });
    lastList = list;
    return list;
  }

  // ---------------------------------------------------------------------------------
  // DETEKSI & PENCOCOKAN
  // ---------------------------------------------------------------------------------
  const sleep = ms => new Promise(r => setTimeout(r, ms));

  function snapshot(video) {
    // Snapshot ke canvas 2D dulu (fix Samsung Exynos/Safari) sebelum dikasih ke face-api.
    const w = video.videoWidth, h = video.videoHeight;
    const scale = Math.min(1, 960 / Math.max(w, h));
    const c = document.createElement('canvas');
    c.width = Math.round(w * scale);
    c.height = Math.round(h * scale);
    c.getContext('2d', { willReadFrequently: true }).drawImage(video, 0, 0, c.width, c.height);
    return c;
  }

  const detectorOptions = () => new faceapi.TinyFaceDetectorOptions({ inputSize: 416, scoreThreshold: 0.3 });

  // Deteksi 1 frame. Return { det } / { small: true } / {} (gak ada wajah).
  async function detectOneFrame(video) {
    const canvas = snapshot(video);
    const det = await faceapi.detectSingleFace(canvas, detectorOptions()).withFaceLandmarks().withFaceDescriptor();
    if (!det) return {};
    // Wajah terlalu kecil (jauh) -> descriptor gak akurat, rawan salah kenali.
    if (det.detection.box.width < canvas.width * 0.10) return { small: true };
    return { det };
  }

  const NO_FACE_HINT = 'Pastikan wajah terlihat jelas di dalam oval, cahaya cukup (jangan membelakangi lampu/jendela), lepas masker/kacamata hitam.';
  const SMALL_FACE_HINT = 'Wajah terlalu jauh, dekatkan wajah ke kamera sampai mengisi oval.';

  // Ambil beberapa frame berturut-turut. Hasilnya bawa SEMUA descriptor per frame
  // (`descriptors`) supaya match() bisa pakai aturan konsensus.
  async function detect(video, opts) {
    // Kalau autoScan barusan sudah dapat hasil yang lolos, pakai itu (gak deteksi ulang).
    if (autoResult && autoResult.video === video && Date.now() - autoResult.at < 4000) {
      const r = autoResult.result; autoResult = null; lastHintText = '';
      return r;
    }
    const frames = Math.max(1, (opts && opts.frames) || CONSENSUS_FRAMES);
    if (!video || !video.videoWidth || !video.srcObject) {
      lastHintText = 'Kamera belum siap, tunggu sebentar lalu coba lagi.';
      return null;
    }
    await loadModels();
    manualBusy = true;
    try {
      const found = [];
      let sawSmall = false;
      const maxTries = frames === 1 ? 1 : frames + 3;
      for (let i = 0; i < maxTries && found.length < frames; i++) {
        if (i > 0) await sleep(80);
        const r = await detectOneFrame(video);
        if (r.small) sawSmall = true;
        if (r.det) found.push(r.det);
      }
      // Multi-frame: minimal 3 frame wajah, kalau kurang anggap gagal (lebih aman).
      const minNeeded = frames === 1 ? 1 : Math.min(3, frames);
      if (found.length < minNeeded) {
        lastHintText = sawSmall ? SMALL_FACE_HINT : (found.length ? 'Wajah sempat hilang dari kamera. Tahan posisi, jangan bergerak, lalu coba lagi.' : NO_FACE_HINT);
        return null;
      }
      lastHintText = '';
      const best = found.reduce((a, b) => (b.detection.score > a.detection.score ? b : a));
      return {
        detection: best.detection, landmarks: best.landmarks, descriptor: best.descriptor,
        descriptors: found.map(d => d.descriptor), frames: found.length,
      };
    } finally {
      manualBusy = false;
    }
  }

  // Jarak dari 1 descriptor ke tiap ORANG (bukan tiap baris). Satu orang bisa punya >1 baris
  // faceData (daftar ulang) -- ambil yang terdekat, biar "mirip lebih dari satu orang" gak
  // kepicu cuma gara-gara orangnya sendiri.
  function distancesPerPerson(q, list) {
    const perPerson = new Map();
    (list || []).forEach(p => {
      const d = p && toDescriptor(p.descriptor);
      if (!q || !d) return;
      const key = String(p.qrCodeId || p.nama || '').trim().toUpperCase() || Math.random().toString();
      const distance = faceapi.euclideanDistance(q, d);
      const prev = perPerson.get(key);
      if (!prev || distance < prev.distance) {
        perPerson.set(key, { key, person: p, qrCodeId: p.qrCodeId, nama: p.nama, distance });
      }
    });
    return Array.from(perPerson.values()).sort((a, b) => a.distance - b.distance);
  }

  const EMPTY_BEST = { person: null, qrCodeId: null, nama: null, distance: 9.999 };

  function matchSingle(q, list) {
    const sorted = distancesPerPerson(q, list);
    const best = sorted[0] || EMPTY_BEST;
    const second = sorted[1] || null;
    const withinThreshold = !!sorted[0] && best.distance <= THRESHOLD;
    const isAmbiguous = !!second && (second.distance - best.distance) < AMBIGUITY_MARGIN;
    return { best, second, withinThreshold, isAmbiguous, ok: withinThreshold && !isAmbiguous, candidates: sorted.length, frames: 1 };
  }

  // Aturan konsensus beberapa frame (lihat penjelasan di atas file).
  function matchFrames(descriptors, list) {
    const agg = new Map();
    const tops = new Map();
    const topDist = new Map();
    let used = 0;
    descriptors.forEach(raw => {
      const sorted = distancesPerPerson(toDescriptor(raw), list);
      if (!sorted.length) return;
      used++;
      const top = sorted[0];
      tops.set(top.key, (tops.get(top.key) || 0) + 1);
      topDist.set(top.key, Math.max(topDist.get(top.key) || 0, top.distance));
      sorted.forEach(r => {
        const a = agg.get(r.key) || { key: r.key, person: r.person, qrCodeId: r.qrCodeId, nama: r.nama, sum: 0, n: 0 };
        a.sum += r.distance; a.n++;
        agg.set(r.key, a);
      });
    });
    const avg = Array.from(agg.values())
      .map(a => ({ key: a.key, person: a.person, qrCodeId: a.qrCodeId, nama: a.nama, distance: a.sum / a.n }))
      .sort((a, b) => a.distance - b.distance);
    const best = avg[0] || EMPTY_BEST;
    const second = avg[1] || null;
    const agree = avg[0] ? (tops.get(best.key) || 0) : 0;
    const consistent = used > 0 && agree >= Math.ceil(used * CONSENSUS_AGREE) && (topDist.get(best.key) || 9) <= MAX_FRAME_DISTANCE;
    const withinThreshold = !!avg[0] && best.distance <= THRESHOLD;
    const clearMargin = !second || (second.distance - best.distance) >= MULTI_MARGIN;
    const isAmbiguous = withinThreshold && (!clearMargin || !consistent);
    return {
      best, second, withinThreshold, isAmbiguous, ok: withinThreshold && clearMargin && consistent,
      candidates: avg.length, frames: used, agree,
    };
  }

  // match(detection, list)  -> konsensus kalau detection bawa beberapa frame
  // match(descriptor, list) -> 1 frame (aturan lama, selisih 0.12)
  function match(input, list) {
    if (input && Array.isArray(input.descriptors) && input.descriptors.length >= 2) {
      return matchFrames(input.descriptors, list);
    }
    const q = toDescriptor(input && input.descriptor ? input.descriptor : input);
    return matchSingle(q, list);
  }

  // ---------------------------------------------------------------------------------
  // AUTO-DETECT (tanpa klik)
  // ---------------------------------------------------------------------------------
  function debugOn() { try { return localStorage.getItem('hsseFaceDebug') === '1'; } catch (e) { return false; } }

  function getOverlay(video) {
    const parent = video.parentElement;
    if (!parent) return null;
    let el = parent.querySelector(':scope > .hsse-face-overlay');
    if (!el) {
      if (getComputedStyle(parent).position === 'static') parent.style.position = 'relative';
      el = document.createElement('div');
      el.className = 'hsse-face-overlay';
      el.style.cssText = 'position:absolute;left:8px;right:8px;bottom:8px;z-index:5;padding:7px 10px;border-radius:10px;' +
        'font:600 12.5px/1.35 inherit;font-family:inherit;color:#fff;text-align:center;background:rgba(11,13,16,.72);pointer-events:none;';
      parent.appendChild(el);
    }
    return el;
  }

  function showOverlay(video, text, kind) {
    const el = getOverlay(video);
    if (!el) return;
    el.textContent = text;
    el.style.background = kind === 'ok' ? 'rgba(22,128,72,.88)' : kind === 'warn' ? 'rgba(160,98,0,.85)' : 'rgba(11,13,16,.72)';
    el.style.display = text ? 'block' : 'none';
  }

  function removeOverlay(video) {
    const parent = video && video.parentElement;
    const el = parent && parent.querySelector(':scope > .hsse-face-overlay');
    if (el) el.remove();
  }

  // Jalan terus selama kamera nyala & tombol Scan Wajah kelihatan. Begitu 5 frame terakhir
  // lolos aturan konsensus, hasilnya disimpan lalu tombol "ditekan" otomatis -> halaman
  // memproses persis seperti klik manual (termasuk cek izin/Author). Tombol tetap bisa
  // ditekan manual kapan saja.
  function autoScan(video, button) {
    if (!video || !button) return;
    const token = {};
    video.__hsseAuto = token;
    const start = Date.now();
    const win = [];
    (async () => {
      try { await loadModels(); } catch (e) { return; }
      await sleep(500);
      while (video.__hsseAuto === token) {
        // Berhenti kalau tombol Scan Wajah disembunyikan (kamera ditutup / sudah teridentifikasi).
        if (button.offsetParent === null) { removeOverlay(video); break; }
        if (!lastList || !lastList.length) break;
        // Lagi ganti kamera depan/belakang -> tunggu.
        if (!video.srcObject) { win.length = 0; await sleep(300); continue; }
        if (Date.now() - start > AUTO_TIMEOUT_MS) {
          showOverlay(video, 'Belum dikenali. Tekan "Scan Wajah" untuk coba lagi, atau pakai QR Code/PIN.', 'warn');
          break;
        }
        if (manualBusy || button.disabled || !video.videoWidth) { win.length = 0; await sleep(300); continue; }

        let r = {};
        try { r = await detectOneFrame(video); } catch (e) { r = {}; }
        if (video.__hsseAuto !== token) break;

        if (!r.det) {
          win.length = 0;
          showOverlay(video, r.small ? 'Dekatkan wajah ke kamera' : 'Mencari wajah... posisikan wajah di oval', 'info');
          await sleep(200);
          continue;
        }
        win.push(r.det.descriptor);
        if (win.length > CONSENSUS_FRAMES) win.shift();
        if (win.length < CONSENSUS_FRAMES) {
          showOverlay(video, `Tahan posisi... ${win.length}/${CONSENSUS_FRAMES}`, 'info');
          await sleep(60);
          continue;
        }
        const m = matchFrames(win, lastList);
        const dbg = debugOn() ? ` [#1 ${m.best.distance.toFixed(3)}${m.second ? ' #2 ' + m.second.distance.toFixed(3) : ''} ${m.agree}/${m.frames}]` : '';
        if (m.ok) {
          autoResult = {
            video, at: Date.now(),
            result: { detection: r.det.detection, landmarks: r.det.landmarks, descriptor: r.det.descriptor, descriptors: win.slice(), frames: win.length },
          };
          showOverlay(video, '✅ Wajah dikenali' + dbg, 'ok');
          video.__hsseAuto = null;
          button.click();
          break;
        }
        showOverlay(video, (m.withinThreshold
          ? 'Wajah mirip beberapa orang... hadap lurus ke kamera, cahaya dari depan'
          : 'Belum dikenali... tahan posisi, hadap lurus ke kamera') + dbg, 'warn');
        await sleep(150);
      }
    })();
  }

  function stopAuto(video) { if (video) video.__hsseAuto = null; }

  window.HsseFace = {
    THRESHOLD, AMBIGUITY_MARGIN, MULTI_MARGIN,
    loadModels, openCamera, stopCamera, fetchFaceData, detect, match, autoScan, stopAuto, toDescriptor,
    lastHint: () => lastHintText || 'Coba lagi.',
  };
})();
