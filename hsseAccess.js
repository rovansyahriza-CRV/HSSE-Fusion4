// =====================================================================================
// HSSE-Fusion4 — Aturan akses PIC vs Author (sama kayak SMMS & SmartGate Fusion4)
//   PIC    = akses buat ngerjain/handle modul (lapor, isi, edit, tindak lanjut)
//   Author = review / approval (setujui, tolak, tutup, reopen)
// Dua-duanya dibaca dari "paswordTbl" Fusion4 lewat get_all_face_data /
// get_person_face_data (field "pic" & "author", lihat migrasi Fusion4 #051).
//
// Masa transisi: tag Author lama yang dulu dipakai buat aksi "ngerjain" tetap diterima
// sebagai alias PIC-nya, biar gak ada yang tiba-tiba ketolak sebelum PIC HSSE-…
// dikasih di Fusion4. PIC "ALL" dari SMMS sengaja TIDAK berlaku di HSSE -- pakai
// "HSSE-ALL" kalau butuh akses ke semua modul HSSE.
// =====================================================================================
(function (global) {
  const PIC_ALL = 'HSSE-ALL';

  // Kode PIC HSSE -> tag Author lama yang masih diterima selama transisi.
  const PIC_ALIASES = {
    'HSSE-CRM': [],                                   // + "<NamaDept> Admin", lihat allows()
    'HSSE-INC': ['Investigate Incident/Accident'],
    'HSSE-INS': [],
    'HSSE-PTW': ['Permit & JSA'],
    'HSSE-TBM': ['Leader Toolbox Meeting'],
    'HSSE-MTG': ['Leader HSE Meeting'],
    'HSSE-AUD': ['Internal Auditor'],
    'HSSE-MWT': ['Admin MWT', 'Management Walkthrough'],
    'HSSE-MRV': ['Management Review'],
    'HSSE-PRG': [],
    'HSSE-TRM': ['Training Matrix Admin']
  };

  function splitTags(raw) {
    if (raw === null || raw === undefined || raw === '') return [];
    const list = Array.isArray(raw) ? raw : String(raw).split(/[,;|]/);
    return list.map(s => String(s).trim().toLowerCase()).filter(Boolean);
  }

  function field(person, key) {
    if (!person) return null;
    const sources = [person, person.person, person.data];
    for (const src of sources) {
      if (!src || typeof src !== 'object') continue;
      for (const k of [key, key.toUpperCase(), key.charAt(0).toUpperCase() + key.slice(1)]) {
        if (src[k] !== undefined && src[k] !== null && src[k] !== '') return src[k];
      }
    }
    return null;
  }

  function hasAuthor(person, tag) {
    return splitTags(field(person, 'author')).includes(String(tag).trim().toLowerCase());
  }

  function hasPic(person, code, aliases) {
    const pics = splitTags(field(person, 'pic'));
    if (pics.includes(String(code).toLowerCase()) || pics.includes(PIC_ALL.toLowerCase())) return true;
    return (aliases || PIC_ALIASES[code] || []).some(tag => hasAuthor(person, tag));
  }

  function isPicCode(tag) {
    return /^HSSE-/i.test(String(tag || '').trim());
  }

  // Tag "<NamaDept> Admin" (followup CERMAT per Dept) = alias PIC HSSE-CRM.
  function isDeptAdminTag(tag) {
    const t = String(tag || '').trim();
    return / Admin$/.test(t) && !Object.values(PIC_ALIASES).some(list => list.includes(t));
  }

  // Pengganti hasAuthorTag() di semua halaman: kode PIC HSSE-… dicek sebagai PIC
  // (plus alias lama), tag lain dicek sebagai Author.
  function allows(person, tag) {
    if (!tag) return true;
    if (isPicCode(tag)) return hasPic(person, String(tag).trim().toUpperCase());
    if (isDeptAdminTag(tag)) return hasPic(person, 'HSSE-CRM', [tag]);
    return hasAuthor(person, tag);
  }

  // Teks buat pesan/izin, contoh: PIC "HSSE-PTW" (atau Author lama "Permit & JSA")
  function label(tag) {
    if (!tag) return '';
    if (isPicCode(tag)) {
      const code = String(tag).trim().toUpperCase();
      const aliases = PIC_ALIASES[code] || [];
      return aliases.length
        ? `PIC "${code}" (atau Author lama ${aliases.map(a => `"${a}"`).join(' / ')})`
        : `PIC "${code}"`;
    }
    if (isDeptAdminTag(tag)) return `PIC "HSSE-CRM" (atau Author lama "${tag}")`;
    return `Author "${tag}"`;
  }

  global.HSSEAccess = { PIC_ALL, PIC_ALIASES, splitTags, hasAuthor, hasPic, allows, label };
})(window);
