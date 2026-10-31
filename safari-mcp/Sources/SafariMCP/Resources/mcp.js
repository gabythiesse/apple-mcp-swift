// Bibliothèque du serveur MCP Safari, injectée une fois par page (window.__mcp).
// Le serveur envoie ensuite des scripts minuscules : window.__mcp&&__mcp.v===V ? __mcp.run(op, args) : "\u0000nolib".
// Chaque opération renvoie un objet JSON (chaîne) ; une opération asynchrone renvoie {job: id}, que le serveur
// sonde toutes les 30 ms avec run('poll', {id}). Les dialogues (alert, confirm, prompt, beforeunload) sont
// interceptés et rendus dans la réponse de l'appel suivant, pour que Safari ne gèle jamais.
// Embarquée dans le binaire (ressource SwiftPM embedInCode) ; V est remplacé à l'injection par l'empreinte du fichier.
(function () {
  'use strict';
  var V = 0;
  if (window.__mcp && window.__mcp.v === V) return;

  var M = {
    v: V,
    refs: new Map(),      // "e12" -> WeakRef(élément)
    ids: new WeakMap(),   // élément -> "e12"
    next: 1,
    jobs: new Map(),
    jobNext: 1,
    dialogs: [],
    policy: { accept: true, prompt: null },
    net: { inflight: 0, last: Date.now() }
  };
  var ops = {};
  M.ops = ops;

  // ---------------------------------------------------------------- utilitaires

  function now() { return Date.now(); }
  function clip(s, n) { s = String(s == null ? '' : s); return s.length > n ? s.slice(0, n - 1) + '…' : s; }
  function squash(s) { return String(s == null ? '' : s).replace(/\s+/g, ' ').trim(); }
  // Comparaison insensible à la casse et aux accents
  function fold(s) { return squash(s).normalize('NFD').replace(/[̀-ͯ]/g, '').toLowerCase(); }
  M.fold = fold;
  function errInfo(e) {
    if (!e || typeof e !== 'object') return { message: String(e) };
    var o = { message: (e.name && e.name !== 'Error' ? e.name + ': ' : '') + (e.message || String(e)) };
    if (e.line) o.line = e.line;
    return o;
  }
  function sleep(ms) { return new Promise(function (r) { setTimeout(r, ms); }); }
  M.sleep = sleep;

  // ---------------------------------------------------------------- références d'éléments

  function refOf(el) {
    var id = M.ids.get(el);
    if (!id) { id = 'e' + (M.next++); M.ids.set(el, id); M.refs.set(id, new WeakRef(el)); }
    return id;
  }
  M.refOf = refOf;
  function byRef(id) {
    var w = M.refs.get(id);
    if (!w) throw new Error('unknown ref ' + id + ' (refs are reset when the page reloads: take a new snapshot)');
    var el = w.deref();
    if (!el || !el.isConnected) throw new Error('stale ref ' + id + ': the element left the page (take a new snapshot)');
    return el;
  }
  M.byRef = byRef;

  // ---------------------------------------------------------------- description d'une valeur quelconque

  function describeEl(el) {
    var s = '<' + el.tagName.toLowerCase();
    if (el.id) s += '#' + el.id;
    if (typeof el.className === 'string' && el.className.trim()) s += '.' + el.className.trim().split(/\s+/).slice(0, 3).join('.');
    s += '>';
    var t = squash(el.innerText || el.value || el.getAttribute('aria-label') || '');
    if (t) s += ' "' + clip(t, 60) + '"';
    return s + ' ' + refOf(el);
  }
  M.describeEl = describeEl;
  function ser(v, depth, seen) {
    depth = depth || 0; seen = seen || new Set();
    var t = typeof v;
    if (v === null || t === 'string' || t === 'boolean') return v;
    if (t === 'undefined') return undefined;
    if (t === 'number') return isFinite(v) ? v : String(v);
    if (t === 'bigint') return String(v) + 'n';
    if (t === 'symbol') return v.toString();
    if (t === 'function') return 'function ' + (v.name || 'anonymous') + '()';
    if (typeof Node !== 'undefined' && v instanceof Node || (v && v.nodeType && v.nodeName)) {
      if (v.nodeType === 1) return describeEl(v);
      if (v.nodeType === 3) return '#text "' + clip(squash(v.data), 80) + '"';
      if (v.nodeType === 9) return '#document ' + (v.URL || '');
      return v.nodeName;
    }
    if (v === window || (v && v.window === v)) return 'Window ' + (function () { try { return v.location.href; } catch (e) { return '(cross-origin)'; } })();
    if (v instanceof Error) return v.name + ': ' + v.message;
    if (v instanceof Date) return isNaN(v) ? 'Invalid Date' : v.toISOString();
    if (v instanceof RegExp) return String(v);
    if (typeof Promise !== 'undefined' && v instanceof Promise) return 'Promise';
    if (seen.has(v)) return '[Circular]';
    if (depth > 5) return Array.isArray(v) ? '[Array(' + v.length + ')]' : '[Object]';
    seen.add(v);
    var out;
    if (typeof v.toJSON === 'function' && !(v instanceof Map) && !(v instanceof Set)) {
      try { out = ser(v.toJSON(), depth + 1, seen); seen.delete(v); return out; } catch (e) { /* objet ordinaire */ }
    }
    if (Array.isArray(v) || v instanceof Set || (typeof NodeList !== 'undefined' && v instanceof NodeList) ||
        (typeof HTMLCollection !== 'undefined' && v instanceof HTMLCollection) || ArrayBuffer.isView(v)) {
      var arr = Array.from(v);
      out = arr.slice(0, 500).map(function (x) { var r = ser(x, depth + 1, seen); return r === undefined ? null : r; });
      if (arr.length > 500) out.push('… ' + (arr.length - 500) + ' more');
    } else if (v instanceof Map) {
      out = {};
      Array.from(v.entries()).slice(0, 200).forEach(function (e) { out[String(e[0])] = ser(e[1], depth + 1, seen); });
    } else {
      out = {};
      var keys = Object.keys(v);
      keys.slice(0, 200).forEach(function (k) {
        var x;
        try { x = ser(v[k], depth + 1, seen); } catch (e) { x = '[unreadable]'; }
        if (x !== undefined) out[k] = x;
      });
      if (keys.length > 200) out['…'] = (keys.length - 200) + ' more keys';
    }
    seen.delete(v);
    return out;
  }
  M.ser = ser;

  // ---------------------------------------------------------------- dialogues, réseau, beforeunload

  M.dialogCount = 0;
  function logDialog(type, message, answer) {
    M.dialogCount++;
    var d = { type: type, message: clip(message == null ? '' : message, 300) };
    if (answer !== undefined) d.answer = answer;
    M.dialogs.push(d);
    if (M.dialogs.length > 50) M.dialogs.shift();
  }
  function patchWindow(w) {
    try { if (w.__mcpPatched) return; w.__mcpPatched = true; } catch (e) { return; }
    w.alert = function (m) { logDialog('alert', m); };
    w.confirm = function (m) { var r = M.policy.accept !== false; logDialog('confirm', m, r); return r; };
    w.prompt = function (m, d) {
      var r = M.policy.accept === false ? null : (M.policy.prompt != null ? String(M.policy.prompt) : (d == null ? '' : String(d)));
      logDialog('prompt', m, r); return r;
    };
    w.print = function () { logDialog('print', ''); };
    // beforeunload : notre écouteur en capture passe avant ceux de la page et les arrête (aucune feuille « Quitter la page ? »)
    w.addEventListener('beforeunload', function (e) { e.stopImmediatePropagation(); M.unloading = true; }, true);
    w.addEventListener('pagehide', function () { M.unloading = true; }, true);
    try { Object.defineProperty(w, 'onbeforeunload', { configurable: true, get: function () { return null; }, set: function () {} }); } catch (e) { /* ignoré */ }
    // fetch et XHR comptés pour wait network_idle
    var net = M.net;
    function start() { net.inflight++; net.last = now(); }
    function end() { net.inflight = Math.max(0, net.inflight - 1); net.last = now(); }
    if (w.fetch) {
      var f = w.fetch;
      w.fetch = function () { start(); var p; try { p = f.apply(this, arguments); } catch (e) { end(); throw e; } p.then(end, end); return p; };
    }
    if (w.XMLHttpRequest) {
      var send = w.XMLHttpRequest.prototype.send;
      w.XMLHttpRequest.prototype.send = function () { start(); this.addEventListener('loadend', end, { once: true }); return send.apply(this, arguments); };
    }
  }
  M.patchWindow = patchWindow;
  patchWindow(window);
  // Les iframes de même origine reçoivent les mêmes protections dès qu'on les parcourt
  M.patchFrames = function (doc) {
    var fr = (doc || document).querySelectorAll('iframe,frame');
    for (var i = 0; i < fr.length; i++) { try { if (fr[i].contentWindow && fr[i].contentDocument) patchWindow(fr[i].contentWindow); } catch (e) { /* autre origine */ } }
  };
  M.patchFrames(document);

  // ---------------------------------------------------------------- exécution

  function finish(o) {
    if (o === undefined || o === null || typeof o !== 'object') o = {};
    if (M.dialogs.length) { o = Object.assign({}, o); o.dialogs = M.dialogs.splice(0); }
    try { return JSON.stringify(o); } catch (e) { return JSON.stringify({ error: 'result not serializable: ' + e.message }); }
  }
  function startJob(p, map) {
    var id = M.jobNext++, job = { done: false, t0: now() };
    M.jobs.set(id, job);
    p.then(function (v) { job.done = true; job.value = map ? map(v) : v; },
           function (e) { job.done = true; job.error = errInfo(e); });
    return { job: id };
  }
  M.startJob = startJob;

  M.run = function (op, args) {
    args = args || {};
    if (args.dialogs) { M.policy.accept = args.dialogs.accept !== false; M.policy.prompt = args.dialogs.prompt; }
    var f = ops[op];
    if (!f) return finish({ error: 'unknown operation ' + op });
    try {
      var r = f(args);
      if (r && typeof r.then === 'function') return finish(startJob(r));
      return finish(r);
    } catch (e) {
      var o = errInfo(e);
      return finish({ error: o.message });
    }
  };

  // Job « sondé » : sa fonction check est réévaluée à chaque sonde du serveur (aucune minuterie de la page :
  // Safari les bride dans un onglet masqué ou quand l'écran est verrouillé). undefined = pas encore.
  function checkJob(check) {
    var id = M.jobNext++;
    M.jobs.set(id, { done: false, check: check, t0: now() });
    return { job: id };
  }
  M.checkJob = checkJob;

  ops.poll = function (a) {
    var j = M.jobs.get(a.id);
    if (!j) return { error: 'job lost', lost: true };
    if (j.check && !j.done) {
      try { var v = j.check(); if (v !== undefined) { j.done = true; j.value = v; } } catch (e) { j.done = true; j.error = errInfo(e); }
    }
    if (!j.done) return { pending: true };
    M.jobs.delete(a.id);
    if (j.error) { var o = { error: j.error.message }; if (j.error.line) o.line = j.error.line; return o; }
    return j.value;
  };

  // run_js : la fonction de l'appelant arrive en littéral dans le script de l'Apple Event (aucun eval, CSP sans effet).
  // Résultat synchrone rendu tout de suite ; une promesse devient un job sondé par le serveur.
  M.js = function (fn) {
    var r;
    try { r = fn(); } catch (e) { return finish({ error: errInfo(e).message, line: e && e.line }); }
    if (r && typeof r.then === 'function') {
      return finish(startJob(Promise.resolve(r), function (v) { var x = ser(v); return x === undefined ? {} : { value: x }; }));
    }
    var x = ser(r);
    return finish(x === undefined ? {} : { value: x });
  };

  ops.ping = function () { return { url: location.href, ready: document.readyState }; };

  // Lecture d'une valeur au-delà de max_chars : le texte complet reste dans la page jusqu'au prochain appel
  M.store = {};
  M.slice = function (key, text, offset, max) {
    if (text != null) M.store[key] = String(text);
    var s = M.store[key] || '';
    offset = Math.max(0, offset || 0);
    var o = { text: s.slice(offset, offset + max) };
    if (offset + max < s.length || offset > 0) { o.length = s.length; if (offset) o.offset = offset; }
    return o;
  };

  // ================================================================ PERCEPTION (phase B)

  // ---------------------------------------------------------------- parcours : Shadow DOM ouvert et iframes de même origine

  // visit(el, depth, frameEl) renvoie false pour ne pas descendre dans l'élément
  function walk(root, visit, depth0) {
    var stack = [[root, depth0 || 0]];
    while (stack.length) {
      var it = stack.pop(), node = it[0], depth = it[1];
      var kids = [];
      if (node.nodeType === 1) {
        if (visit(node, depth) === false) continue;
        if (node.shadowRoot) kids.push(node.shadowRoot);
        var tag = node.tagName;
        if (tag === 'IFRAME' || tag === 'FRAME') {
          var doc = null;
          try { doc = node.contentDocument; } catch (e) { doc = null; }
          if (doc && doc.documentElement) { M.patchWindow(node.contentWindow); kids.push(doc.documentElement); }
        }
      }
      var c = node.children || (node.nodeType === 11 ? node.children : null);
      if (c) for (var i = 0; i < c.length; i++) kids.push(c[i]);
      for (var k = kids.length - 1; k >= 0; k--) stack.push([kids[k], node.nodeType === 1 ? depth + 1 : depth]);
    }
  }
  M.walk = walk;

  // Rectangle dans le repère de la fenêtre principale (iframes : décalage des cadres ajouté)
  function rectOf(el) {
    var r = el.getBoundingClientRect(), x = r.left, y = r.top, w = el.ownerDocument.defaultView;
    try {
      while (w && w !== window && w.frameElement) {
        var fr = w.frameElement.getBoundingClientRect(), cs = getComputedStyle(w.frameElement);
        x += fr.left + (parseFloat(cs.borderLeftWidth) || 0) + (parseFloat(cs.paddingLeft) || 0);
        y += fr.top + (parseFloat(cs.borderTopWidth) || 0) + (parseFloat(cs.paddingTop) || 0);
        w = w.parent;
      }
    } catch (e) { /* cadre d'une autre origine */ }
    return { x: x, y: y, w: r.width, h: r.height };
  }
  M.rectOf = rectOf;
  function rectArr(r) { return [Math.round(r.x), Math.round(r.y), Math.round(r.w), Math.round(r.h)]; }

  function isVisible(el) {
    if (el.checkVisibility) { if (!el.checkVisibility({ opacityProperty: true, visibilityProperty: true })) return false; }
    else { var cs = getComputedStyle(el); if (cs.display === 'none' || cs.visibility === 'hidden') return false; }
    var r = el.getBoundingClientRect();
    return r.width > 0 || r.height > 0 || el.tagName === 'OPTION';
  }
  M.isVisible = isVisible;
  function inViewport(r) { return r.x + r.w > 0 && r.y + r.h > 0 && r.x < innerWidth && r.y < innerHeight; }

  // ---------------------------------------------------------------- rôles et noms accessibles

  var INPUT_ROLES = { checkbox: 'checkbox', radio: 'radio', range: 'slider', number: 'spinbutton', button: 'button', submit: 'button',
    reset: 'button', image: 'button', file: 'button', search: 'searchbox', color: 'button', hidden: null };
  var TAG_ROLES = { BUTTON: 'button', TEXTAREA: 'textbox', H1: 'heading', H2: 'heading', H3: 'heading', H4: 'heading', H5: 'heading', H6: 'heading',
    NAV: 'navigation', MAIN: 'main', ASIDE: 'complementary', FORM: 'form', DIALOG: 'dialog', TABLE: 'table', UL: 'list', OL: 'list',
    LI: 'listitem', SUMMARY: 'button', DETAILS: 'group', OPTION: 'option', PROGRESS: 'progressbar', METER: 'meter', FIELDSET: 'group',
    ARTICLE: 'article', HR: 'separator', VIDEO: 'video', AUDIO: 'audio', IFRAME: 'iframe', FRAME: 'iframe', P: 'paragraph',
    TH: 'columnheader', TD: 'cell', TR: 'row', BLOCKQUOTE: 'blockquote', PRE: 'code', FIGURE: 'figure', HEADER: 'banner', FOOTER: 'contentinfo' };
  var INTERACTIVE = { link: 1, button: 1, textbox: 1, searchbox: 1, checkbox: 1, radio: 1, combobox: 1, listbox: 1, option: 1, menuitem: 1,
    menuitemcheckbox: 1, menuitemradio: 1, tab: 1, switch: 1, slider: 1, spinbutton: 1, treeitem: 1, clickable: 1 };
  M.INTERACTIVE = INTERACTIVE;

  function roleOf(el) {
    var r = el.getAttribute('role');
    if (r) { r = r.trim().split(/\s+/)[0]; if (r !== 'presentation' && r !== 'none' && r !== 'generic') return r; }
    var t = el.tagName;
    if (t === 'A' || t === 'AREA') return el.hasAttribute('href') ? 'link' : (el.hasAttribute('tabindex') || el.hasAttribute('onclick') ? 'link' : null);
    if (t === 'INPUT') {
      var ty = (el.type || 'text').toLowerCase();
      if (ty in INPUT_ROLES) return INPUT_ROLES[ty];
      return el.hasAttribute('list') ? 'combobox' : 'textbox';
    }
    if (t === 'SELECT') return el.multiple || el.size > 1 ? 'listbox' : 'combobox';
    if (t === 'IMG') return el.getAttribute('alt') === '' ? null : 'img';
    if (t === 'SECTION') return el.hasAttribute('aria-label') || el.hasAttribute('aria-labelledby') ? 'region' : null;
    if (el.isContentEditable && (!el.parentElement || !el.parentElement.isContentEditable)) return 'textbox';
    return TAG_ROLES[t] || null;
  }
  M.roleOf = roleOf;

  function textOf(el, n) {
    var t = squash(el.textContent);
    if (!t) {
      var img = el.querySelector && el.querySelector('img[alt],svg title,[aria-label]');
      if (img) t = squash(img.getAttribute('alt') || img.getAttribute('aria-label') || img.textContent);
    }
    return clip(t, n || 80);
  }
  // Texte d'un label sans celui du champ qu'il contient (les options d'un select, la valeur d'un input)
  function labelText(lab, field) {
    var t = '';
    for (var c = lab.firstChild; c; c = c.nextSibling) {
      if (c === field || (c.nodeType === 1 && (c.contains(field) || /^(SELECT|INPUT|TEXTAREA)$/.test(c.tagName)))) continue;
      t += c.textContent;
    }
    return squash(t);
  }
  function nameOf(el, role) {
    var v = el.getAttribute('aria-labelledby');
    if (v) {
      var doc = el.getRootNode && el.getRootNode() || el.ownerDocument, parts = [];
      v.split(/\s+/).forEach(function (id) { var x = doc.getElementById ? doc.getElementById(id) : el.ownerDocument.getElementById(id); if (x) parts.push(squash(x.textContent)); });
      if (parts.join('')) return clip(parts.join(' '), 80);
    }
    v = el.getAttribute('aria-label');
    if (v && v.trim()) return clip(squash(v), 80);
    var t = el.tagName;
    if (t === 'INPUT' || t === 'TEXTAREA' || t === 'SELECT') {
      if (el.labels && el.labels.length) { var l = labelText(el.labels[0], el); if (l) return clip(l, 80); }
      if (t === 'INPUT' && /^(button|submit|reset)$/i.test(el.type)) return clip(el.value || el.type, 80);
      return clip(squash(el.getAttribute('placeholder') || el.getAttribute('title') || el.getAttribute('name') || ''), 80);
    }
    if (t === 'IMG' || t === 'AREA') return clip(squash(el.getAttribute('alt') || el.getAttribute('title') || ''), 80);
    if (t === 'IFRAME' || t === 'FRAME') return clip(el.getAttribute('title') || el.getAttribute('name') || el.src || '', 80);
    if (role === 'textbox' || role === 'searchbox' || role === 'combobox' || role === 'listbox' || role === 'dialog' || role === 'form' ||
        role === 'list' || role === 'table' || role === 'navigation' || role === 'main' || role === 'group' || role === 'region' || role === 'menu' ||
        role === 'banner' || role === 'contentinfo' || role === 'complementary' || role === 'article' || role === 'figure') {
      return clip(squash(el.getAttribute('title') || el.getAttribute('placeholder') || el.getAttribute('aria-placeholder') || ''), 80);
    }
    return textOf(el, 80) || clip(squash(el.getAttribute('title') || ''), 80);
  }
  M.nameOf = nameOf;

  function valueOf(el, role) {
    var t = el.tagName;
    if (t === 'INPUT') {
      if (/^(checkbox|radio|button|submit|reset|image|file|hidden)$/i.test(el.type)) return el.type === 'file' && el.files && el.files.length ? el.files[0].name : null;
      if (el.type === 'password') return el.value ? '••••' : '';
      return el.value;
    }
    if (t === 'TEXTAREA') return el.value;
    if (t === 'SELECT') { var o = el.selectedOptions; return o && o.length ? Array.from(o).map(function (x) { return squash(x.text); }).join(', ') : ''; }
    if (el.isContentEditable && role === 'textbox') return textOf(el, 200);
    var v = el.getAttribute('aria-valuetext') || el.getAttribute('aria-valuenow');
    return v;
  }

  function statesOf(el, role) {
    var s = [], a;
    if (el.disabled || el.getAttribute('aria-disabled') === 'true') s.push('disabled');
    if (role === 'checkbox' || role === 'radio' || role === 'switch' || role === 'menuitemcheckbox' || role === 'menuitemradio') {
      a = el.getAttribute('aria-checked');
      if (el.checked || a === 'true') s.push('checked'); else if (a === 'mixed' || el.indeterminate) s.push('mixed'); else s.push('unchecked');
    }
    a = el.getAttribute('aria-expanded');
    if (a === 'true' || (el.tagName === 'DETAILS' && el.open)) s.push('expanded'); else if (a === 'false') s.push('collapsed');
    a = el.getAttribute('aria-selected');
    if (a === 'true' || (el.tagName === 'OPTION' && el.selected)) s.push('selected');
    if (el.getAttribute('aria-pressed') === 'true') s.push('pressed');
    if (el.getAttribute('aria-current') && el.getAttribute('aria-current') !== 'false') s.push('current');
    if (el.required || el.getAttribute('aria-required') === 'true') s.push('required');
    if (el.ownerDocument.activeElement === el) s.push('focused');
    return s;
  }

  // Élément cliquable sans rôle : onclick, tabindex, ou curseur main (posé par la page, pas hérité du parent)
  function clickable(el) {
    if (el.hasAttribute('onclick') || el.hasAttribute('jsaction') || el.hasAttribute('ng-click') || el.hasAttribute('@click')) return true;
    var ti = el.getAttribute('tabindex');
    if (ti !== null && ti !== '-1' && el.tagName !== 'BODY' && el.tagName !== 'HTML') return true;
    var t = el.tagName;
    if (t !== 'DIV' && t !== 'SPAN' && t !== 'LI' && t !== 'TD' && t !== 'TR' && t !== 'IMG' && t !== 'svg' && t !== 'I' && t !== 'P' && t !== 'LABEL') return false;
    var w = el.ownerDocument.defaultView, cs = w.getComputedStyle(el);
    if (cs.cursor !== 'pointer') return false;
    var p = el.parentElement;
    return !p || w.getComputedStyle(p).cursor !== 'pointer';
  }

  // Une ligne d'élément : "e12 button "Envoyer" [disabled] = valeur"
  function line(el, role, opts) {
    var name = role === 'paragraph' || role === 'text' || role === 'cell' || role === 'listitem' || role === 'blockquote' || role === 'code'
      ? clip(squash(el.innerText !== undefined ? el.innerText : el.textContent), opts.textMax || 160) : nameOf(el, role);
    var label = role === 'heading' ? 'h' + (el.tagName.match(/^H(\d)$/) ? el.tagName[1] : (el.getAttribute('aria-level') || '2')) : role;
    var s = refOf(el) + ' ' + label;
    if (name) s += ' ' + JSON.stringify(name);
    var st = statesOf(el, role);
    if (st.length) s += ' [' + st.join(', ') + ']';
    var v = valueOf(el, role);
    if (v != null && v !== '' && v !== name) s += ' = ' + JSON.stringify(clip(v, 120));
    if (role === 'link' && opts.urls) { var h = el.getAttribute('href'); if (h && !/^(#|javascript:)/.test(h)) s += ' → ' + clip(shortUrl(el.href), 100); }
    return s;
  }

  function shortUrl(u) {
    var r;
    try { var x = new URL(u, location.href); r = x.origin === location.origin ? x.pathname + x.search + x.hash : x.href; } catch (e) { return u; }
    try { r = decodeURI(r); } catch (e) { /* garder l'encodage */ }
    return r.replace(/[ ()]/g, function (c) { return encodeURIComponent(c); });
  }
  M.shortUrl = shortUrl;

  function crossOrigin(el) {
    try { return !el.contentDocument; } catch (e) { return true; }
  }

  // ---------------------------------------------------------------- snapshot

  ops.snapshot = function (a) {
    if (document.contentType === 'application/pdf') throw new Error('this tab shows a PDF: no controls to snapshot; read_page returns its text');
    var t0 = now();
    var all = !!a.all, vpOnly = !!a.viewport_only, max = a.max_chars || 8000, offset = a.offset || 0;
    var key = 'snapshot';
    if (offset > 0 && M.store[key] != null && !a.refresh) {
      var o0 = M.slice(key, null, offset, max);
      return { text: cutLines(o0.text, offset, M.store[key]), length: o0.length, offset: offset };
    }
    var root = document.documentElement;
    if (a.selector) { root = a.ref ? byRef(a.ref) : document.querySelector(a.selector); if (!root) throw new Error('no element matches ' + a.selector); }
    else if (a.ref) root = byRef(a.ref);
    var out = [], count = 0, depthOf = new Map(), stats = { frames: 0, cross: 0, shadow: 0 };
    walk(root, function (el, depth) {
      var t = el.tagName;
      if (t === 'SCRIPT' || t === 'STYLE' || t === 'NOSCRIPT' || t === 'TEMPLATE' || t === 'HEAD' || t === 'svg' && !el.hasAttribute('role')) return false;
      if (el.getAttribute('aria-hidden') === 'true' && !all) return false;
      if (el.shadowRoot) stats.shadow++;
      var role = roleOf(el);
      var isFrame = t === 'IFRAME' || t === 'FRAME';
      var want = isFrame || (role && (INTERACTIVE[role] || role === 'heading' || role === 'dialog' || role === 'alertdialog' || role === 'menu' ||
        role === 'listbox' || role === 'tablist' || role === 'alert')) || (all && (role || hasOwnText(el)));
      if (!want && !role && !all && clickable(el)) { role = 'clickable'; want = true; }
      if (!want) return;
      if (!isVisible(el)) return false;
      var r = rectOf(el);
      if (vpOnly && !inViewport(r)) return isFrame ? false : undefined;
      if (!role && all) role = 'text';
      var ind = 0, p = el.parentElement;
      // indentation : nombre d'ancêtres déjà émis (au plus 6 niveaux)
      for (var n = 0; p && n < 12; n++, p = p.parentElement || (p.getRootNode && p.getRootNode().host)) { if (depthOf.has(p)) { ind = depthOf.get(p) + 1; break; } }
      depthOf.set(el, ind);
      var pad = '  '.repeat(Math.min(ind, 6));
      if (isFrame) {
        stats.frames++;
        if (crossOrigin(el)) { stats.cross++; out.push(pad + refOf(el) + ' iframe ' + JSON.stringify(clip(el.src || el.getAttribute('srcdoc') ? (el.src || 'srcdoc') : '', 100)) + ' [cross-origin: not readable from this page; open its URL in a tab]'); return false; }
        out.push(pad + refOf(el) + ' iframe ' + JSON.stringify(nameOf(el, 'iframe')) + ' [same-origin]');
        return;
      }
      count++;
      out.push(pad + line(el, role, { urls: !!a.urls, textMax: 160 }));
    });
    var text = out.join('\n');
    var o = M.slice(key, text, 0, max);
    var res = { url: location.href, title: document.title, elements: count, text: cutLines(o.text, 0, text) };
    if (o.length) { res.length = o.length; res.next_offset = res.text.length + 1; }
    if (stats.frames) res.iframes = stats.frames;
    if (stats.cross) res.cross_origin_iframes = stats.cross;
    if (stats.shadow) res.shadow_roots = stats.shadow;
    res.ms = now() - t0;
    return res;
  };
  // Coupe à la dernière ligne complète
  function cutLines(part, offset, full) {
    if (offset + part.length >= full.length) return part;
    var i = part.lastIndexOf('\n');
    return i > 0 ? part.slice(0, i) : part;
  }
  function hasOwnText(el) {
    for (var c = el.firstChild; c; c = c.nextSibling) if (c.nodeType === 3 && c.data.trim().length > 1) return true;
    return false;
  }

  // ---------------------------------------------------------------- find

  function hiddenReason(el) {
    if (!el.isConnected) return 'removed from the page';
    var w = el.ownerDocument.defaultView, cs = w.getComputedStyle(el);
    if (cs.display === 'none') return 'display:none';
    if (el.checkVisibility && !el.checkVisibility()) return 'display:none on an ancestor (closed menu, collapsed section, inactive tab…)';
    if (cs.visibility === 'hidden') return 'visibility:hidden';
    if (el.checkVisibility && !el.checkVisibility({ opacityProperty: true })) return 'opacity:0';
    var r = el.getBoundingClientRect();
    if (r.width === 0 && r.height === 0) return 'zero size';
    return null;
  }
  M.hiddenReason = hiddenReason;
  // Ce qui recouvre le centre de l'élément (null si rien, ou hors écran)
  function coveredBy(el) {
    var r = el.getBoundingClientRect(), doc = el.ownerDocument;
    var cx = r.left + r.width / 2, cy = r.top + r.height / 2, w = doc.defaultView;
    if (cx < 0 || cy < 0 || cx > w.innerWidth || cy > w.innerHeight) return null;
    var hit = (el.getRootNode && el.getRootNode().elementFromPoint ? el.getRootNode() : doc).elementFromPoint(cx, cy);
    if (!hit || hit === el || el.contains(hit) || hit.contains(el)) return null;
    // label associé : un clic dessus vaut un clic sur le champ
    if (hit.tagName === 'LABEL' && hit.control === el) return null;
    return hit;
  }
  M.coveredBy = coveredBy;

  function describeMatch(el, extra) {
    var role = roleOf(el) || (clickable(el) ? 'clickable' : el.tagName.toLowerCase());
    var r = rectOf(el), o = { ref: refOf(el), role: role };
    var n = nameOf(el, role); if (n) o.name = n;
    var v = valueOf(el, role); if (v != null && v !== '' && v !== n) o.value = clip(v, 120);
    var st = statesOf(el, role); if (st.length) o.states = st;
    o.rect = rectArr(r);
    var why = hiddenReason(el);
    if (why) { o.visible = false; o.hidden = why; }
    else if (!inViewport(r)) { o.visible = true; o.in_viewport = false; }
    else { var c = coveredBy(el); o.visible = true; if (c) o.covered_by = describeEl(c); }
    if (extra) for (var k in extra) o[k] = extra[k];
    return o;
  }

  function interactiveAncestor(el, levels) {
    for (var p = el, n = 0; p && n <= levels; p = p.parentElement || (p.getRootNode && p.getRootNode().host), n++) {
      var r = roleOf(p);
      if (r && INTERACTIVE[r]) return p;
    }
    return null;
  }

  // Score de correspondance texte : 3 égal, 2 commence par, 1 contient, 0.5 tous les mots ; 0 sinon
  function textScore(hay, q) {
    if (!hay || !q) return 0;
    if (hay === q) return 3;
    if (hay.indexOf(q) === 0) return 2;
    if (hay.indexOf(q) >= 0) return 1;
    var words = q.split(' ');
    if (words.length > 1 && words.every(function (w) { return hay.indexOf(w) >= 0; })) return 0.5;
    return 0;
  }

  // Cherche des éléments ; renvoie [{el, score}] trié. Utilisé par find et pour cibler click/type par texte.
  function search(a) {
    var q = a.text != null ? fold(a.text) : null, lq = a.label != null ? fold(a.label) : null;
    var wantRole = a.role || null, sel = a.selector || null;
    var found = [], seen = new Set();
    var root = a.within ? (typeof a.within === 'string' && /^e\d+$/.test(a.within) ? byRef(a.within) : document.querySelector(a.within)) : document.documentElement;
    if (!root) throw new Error('no element matches ' + a.within);
    walk(root, function (el) {
      var t = el.tagName;
      if (t === 'SCRIPT' || t === 'STYLE' || t === 'NOSCRIPT' || t === 'TEMPLATE' || t === 'HEAD') return false;
      if ((t === 'HTML' || t === 'BODY') && !sel) return;
      if (sel && !el.matches(sel)) return;
      var role = null;
      if (wantRole) { role = roleOf(el) || (clickable(el) ? 'clickable' : null); if (role !== wantRole) return; }
      var score = 1;
      if (lq != null) {
        var f = fold(nameOf(el, role || roleOf(el)) + ' ' + (el.getAttribute('placeholder') || '') + ' ' + (el.getAttribute('title') || ''));
        if (!/^(INPUT|TEXTAREA|SELECT)$/.test(t) && !el.isContentEditable && roleOf(el) !== 'textbox' && roleOf(el) !== 'combobox') return;
        score = textScore(f, lq); if (!score) return;
      }
      if (q != null) {
        // texte visible, nom accessible, aria-label, title, placeholder, alt, valeur d'un bouton
        var own = fold(el.textContent);
        var attrs = fold((el.getAttribute('aria-label') || '') + ' ' + (el.getAttribute('title') || '') + ' ' + (el.getAttribute('placeholder') || '') + ' ' + (el.getAttribute('alt') || '') + (t === 'INPUT' && /^(button|submit|reset)$/i.test(el.type) ? ' ' + el.value : ''));
        var sText = textScore(own, q), sAttr = textScore(attrs.trim(), q);
        if (!sText && !sAttr) return;
        // le plus précis : on ne garde pas un parent si un enfant contient aussi le texte
        if (sText && !sAttr) {
          var kids = el.children;
          for (var i = 0; i < kids.length; i++) if (kids[i].tagName !== 'BR' && textScore(fold(kids[i].textContent), q) >= sText) return;
          if (el.shadowRoot && textScore(fold(el.shadowRoot.textContent), q) >= sText) return;
          // tous les mots mais dans un long bloc : bruit
          if (sText < 1 && own.length > q.length * 4 + 40) return;
        }
        score = Math.max(sText, sAttr);
      }
      var target = el;
      if (q != null && !sel && !wantRole) { var ia = interactiveAncestor(el, 4); if (ia) target = ia; }
      if (seen.has(target)) return;
      seen.add(target);
      var vis = isVisible(target);
      var r2 = roleOf(target);
      found.push({ el: target, base: score, score: score + (vis ? 10 : 0) + (r2 && INTERACTIVE[r2] ? 1 : 0) + (target.ownerDocument === document ? 0.1 : 0), visible: vis });
    });
    if (a.near != null) {
      var anchors = search({ text: a.near }).filter(function (x) { return x.visible; });
      if (!anchors.length) throw new Error('near: no visible element with the text "' + a.near + '"');
      var ar = rectOf(anchors[0].el);
      var acx = ar.x + ar.w / 2, acy = ar.y + ar.h / 2;
      var cands = found.length || q != null || sel || wantRole ? found : [];
      if (!cands.length) {
        walk(document.documentElement, function (el) {
          var role = roleOf(el);
          if (role && INTERACTIVE[role] && el !== anchors[0].el && isVisible(el)) cands.push({ el: el, score: 10, visible: true });
        });
      }
      cands = cands.filter(function (c) { return c.el !== anchors[0].el && !c.el.contains(anchors[0].el); });
      cands.forEach(function (c) {
        var r = rectOf(c.el), cx = r.x + r.w / 2, cy = r.y + r.h / 2;
        var dx = cx - acx, dy = cy - acy;
        // même ligne d'abord, puis à droite ou en dessous : la position habituelle d'un champ par rapport à son libellé
        var d = Math.abs(dx) + Math.abs(dy) * 2 + (dx < 0 ? -dx / 2 : 0) + (dy < -ar.h / 2 ? -dy : 0);
        c.dist = d; c.score = c.score - d / 10000;
      });
      found = cands.sort(function (x, y) { return x.dist - y.dist; });
      return found;
    }
    // une correspondance exacte, en début ou partielle écarte les « tous les mots » épars
    if (found.some(function (x) { return x.base >= 1; })) found = found.filter(function (x) { return x.base >= 1; });
    found.sort(function (x, y) { return y.score - x.score; });
    return found;
  }
  M.search = search;

  ops.find = function (a) {
    if (a.text == null && a.role == null && a.selector == null && a.label == null && a.near == null) throw new Error('give text, role, selector, label or near');
    var res = search(a), lim = a.limit || 10;
    var o = { matches: res.slice(0, lim).map(function (x) { return describeMatch(x.el); }) };
    if (res.length > lim) o.total = res.length;
    return o;
  };

  // Cible d'une action : ref, sélecteur, texte (+ rôle), label ou coordonnées. Erreur claire sinon.
  function target(a) {
    if (a.ref) return byRef(a.ref);
    if (a.x != null && a.y != null && a.selector == null && a.text == null) {
      var el = document.elementFromPoint(a.x, a.y);
      if (!el) throw new Error('nothing at ' + a.x + ',' + a.y);
      return el;
    }
    if (a.selector && a.text == null && a.label == null && a.role == null) {
      var e = document.querySelector(a.selector);
      if (!e) {
        var deep = search({ selector: a.selector });
        if (!deep.length) throw new Error('no element matches ' + a.selector);
        e = deep[0].el;
      }
      return e;
    }
    if (a.text == null && a.label == null && a.role == null && a.near == null) throw new Error('give a target: ref, selector, text, label or x/y');
    var r = search({ text: a.text, label: a.label, role: a.role, selector: a.selector, near: a.near, within: a.within });
    if (!r.length) throw new Error('no element found for ' + JSON.stringify({ text: a.text, label: a.label, role: a.role, selector: a.selector, near: a.near }));
    var vis = r.filter(function (x) { return x.visible; });
    return (vis.length ? vis : r)[0].el;
  }
  M.target = target;

  // ---------------------------------------------------------------- markdown (read_page)

  var SKIP_TAGS = { SCRIPT: 1, STYLE: 1, NOSCRIPT: 1, TEMPLATE: 1, SVG: 1, svg: 1, CANVAS: 1, IFRAME: 1, BUTTON: 1, SELECT: 1, INPUT: 1, TEXTAREA: 1, OBJECT: 1, EMBED: 1, HEAD: 1, DIALOG: 0 };
  var BOILER = /(^|[\s_-])(cookie|consent|gdpr|newsletter|share|sharing|social|advert|ads|ad-|banner|promo|related|recommend|comments?|breadcrumb|skip|sidebar|navbox|navbar|menu|footer|toolbar|popup|modal|subscribe|paywall)([\s_-]|$)/i;
  var NOISE_SEL = '.mw-editsection,.reference,.noprint,.navbox,.mw-jump-link,#toc,.toc,.metadata,.hatnote,.printfooter,.catlinks,.mw-indicators,#coordinates,.bandeau-container,[role=navigation],[role=banner],[role=contentinfo],[role=search],[aria-hidden=true]';

  function mainRoot() {
    var cands = Array.from(document.querySelectorAll('main,[role=main],article,#content,#main,#main-content,.mw-parser-output,.post,.entry-content,.article-body'));
    var best = null, bestLen = 0;
    cands.forEach(function (c) { var n = (c.innerText || '').length; if (n > bestLen * 1.2 || (c.tagName === 'ARTICLE' && n > bestLen * 0.7)) { best = c; bestLen = n; } });
    if (best && bestLen > 400) return best;
    // densité de texte : chaque paragraphe donne des points à son parent et à son grand-parent
    var score = new Map();
    document.querySelectorAll('p,pre,blockquote,li,td').forEach(function (p) {
      var n = (p.textContent || '').trim().length; if (n < 40) return;
      var a = p.parentElement, b = a && a.parentElement;
      if (a) score.set(a, (score.get(a) || 0) + n);
      if (b) score.set(b, (score.get(b) || 0) + n / 2);
    });
    var top = null, s = 0;
    score.forEach(function (v, k) { if (v > s) { s = v; top = k; } });
    return top && s > 300 ? top : document.body;
  }

  function mdInline(node, ctx) {
    var out = '';
    for (var c = node.firstChild; c; c = c.nextSibling) out += mdNode(c, ctx, true);
    return out;
  }
  function escCell(s) { return s.replace(/\|/g, '\\|').replace(/\s*\n+\s*/g, ' ').trim(); }
  function skip(el, ctx) {
    if (SKIP_TAGS[el.tagName]) return true;
    if (el.getAttribute('aria-hidden') === 'true' || el.hidden) return true;
    if (!ctx.full) {
      if (ctx.noise && el.matches(NOISE_SEL)) return true;
      var t = el.tagName;
      if ((t === 'NAV' || t === 'ASIDE' || t === 'FOOTER' || (t === 'HEADER' && !el.querySelector('h1'))) && el !== ctx.root) return true;
      var idc = (el.id || '') + ' ' + (typeof el.className === 'string' ? el.className : '');
      if (idc.length > 1 && BOILER.test(idc) && el !== ctx.root && (el.textContent || '').length < 3000) return true;
    }
    if (!isVisible(el) && el.tagName !== 'BR' && el.tagName !== 'WBR') return true;
    return false;
  }
  function mdTable(el, ctx) {
    var rows = Array.from(el.rows || []).filter(function (r) { return r.closest('table') === el; });
    if (!rows.length) return '';
    var grid = rows.map(function (r) {
      var cells = [];
      Array.from(r.cells).forEach(function (c) {
        if (!isVisible(c) && c.textContent.trim() === '') return;
        var t = escCell(mdInline(c, Object.assign({}, ctx, { inTable: true })));
        cells.push(t);
        for (var k = 1; k < Math.min(c.colSpan || 1, 10); k++) cells.push('');
      });
      return cells;
    }).filter(function (c) { return c.length && c.some(function (x) { return x; }); });
    if (!grid.length) return '';
    var cols = Math.max.apply(null, grid.map(function (r) { return r.length; }));
    if (cols === 1) return grid.map(function (r) { return r[0]; }).join('\n\n');   // tableau de mise en page
    grid.forEach(function (r) { while (r.length < cols) r.push(''); });
    var lines = ['| ' + grid[0].join(' | ') + ' |', '|' + ' --- |'.repeat(cols)];
    for (var i = 1; i < grid.length; i++) lines.push('| ' + grid[i].join(' | ') + ' |');
    var cap = el.caption ? squash(el.caption.textContent) : '';
    return (cap ? '**' + cap + '**\n\n' : '') + lines.join('\n');
  }
  function mdList(el, ctx) {
    var ordered = el.tagName === 'OL', n = el.start || 1, out = [], depth = (ctx.listDepth || 0);
    var pad = '  '.repeat(depth);
    Array.from(el.children).forEach(function (li) {
      if (li.tagName !== 'LI' || skip(li, ctx)) return;
      var inner = mdBlocks(li, Object.assign({}, ctx, { listDepth: depth + 1 })).trim();
      if (!inner) return;
      var bullet = ordered ? (n++) + '. ' : '- ';
      var ls = inner.split('\n');
      out.push(pad + bullet + ls[0] + (ls.length > 1 ? '\n' + ls.slice(1).map(function (l) { return l.match(/^\s*([-*]|\d+\.) /) ? l : pad + '  ' + l; }).join('\n') : ''));
    });
    return out.join('\n');
  }
  var BLOCK = { P: 1, DIV: 1, SECTION: 1, ARTICLE: 1, MAIN: 1, HEADER: 1, FOOTER: 1, ASIDE: 1, NAV: 1, FIGURE: 1, FIGCAPTION: 1, BLOCKQUOTE: 1,
    UL: 1, OL: 1, LI: 1, TABLE: 1, PRE: 1, H1: 1, H2: 1, H3: 1, H4: 1, H5: 1, H6: 1, HR: 1, DL: 1, DT: 1, DD: 1, DETAILS: 1, SUMMARY: 1,
    FORM: 1, FIELDSET: 1, ADDRESS: 1, CENTER: 1, BODY: 1, HTML: 1, DIALOG: 1 };
  function mdBlocks(node, ctx) {
    var parts = [], inline = '';
    function flush() { var t = inline.replace(/[ \t]+/g, ' ').replace(/ ?\n ?/g, '\n').trim(); if (t) parts.push(t); inline = ''; }
    var kids = [];
    for (var c = node.firstChild; c; c = c.nextSibling) kids.push(c);
    if (node.shadowRoot) { kids = []; for (var s = node.shadowRoot.firstChild; s; s = s.nextSibling) kids.push(s); }
    kids.forEach(function (c) {
      if (c.nodeType === 1 && (BLOCK[c.tagName] || c.tagName === 'TABLE') && !ctx.inTable) {
        flush();
        var b = mdNode(c, ctx, false);
        if (b && b.trim()) parts.push(b.trim());
      } else inline += mdNode(c, ctx, true);
    });
    flush();
    return parts.join('\n\n');
  }
  // **gras** sans avaler les espaces autour (« <b>France</b>, » → « **France**, »)
  function wrap(t, m) {
    if (!t.trim()) return t;
    return (/^\s/.test(t) ? ' ' : '') + m + t.trim() + m + (/\s$/.test(t) ? ' ' : '');
  }
  function mdNode(n, ctx, inl) {
    if (n.nodeType === 3) return n.data.replace(/\s+/g, ' ');
    if (n.nodeType !== 1) return '';
    var el = n, t = el.tagName;
    if (skip(el, ctx)) return '';
    // encadré de résumé (infobox) : placé après l'introduction, pour que le début se lise comme l'article
    if (ctx.defer && !ctx.inTable && typeof el.className === 'string' && /infobox/i.test(el.className)) {
      ctx.defer.push(mdNode(el, Object.assign({}, ctx, { defer: null }), false)); return '';
    }
    switch (t) {
      case 'BR': return '\n';
      case 'H1': case 'H2': case 'H3': case 'H4': case 'H5': case 'H6':
        var h = squash(mdInline(el, ctx)); return h ? '#'.repeat(+t[1]) + ' ' + h : '';
      case 'P': case 'FIGCAPTION': case 'DT': case 'SUMMARY': return mdBlocks(el, ctx);
      case 'DD': return ': ' + mdBlocks(el, ctx);
      case 'HR': return '---';
      case 'PRE':
        var lang = ((el.querySelector('code') || el).className.match(/language-(\w+)/) || [])[1] || '';
        return '```' + lang + '\n' + el.textContent.replace(/\n$/, '') + '\n```';
      case 'CODE': return inl ? '`' + el.textContent + '`' : '```\n' + el.textContent + '\n```';
      case 'BLOCKQUOTE': return mdBlocks(el, ctx).split('\n').map(function (l) { return '> ' + l; }).join('\n');
      case 'UL': case 'OL': return mdList(el, ctx);
      case 'TABLE': return ctx.inTable ? squash(el.innerText) : mdTable(el, ctx);
      case 'IMG': var alt = squash(el.getAttribute('alt') || ''); return alt ? '![' + alt + ']' : '';
      case 'STRONG': case 'B': return wrap(mdInline(el, ctx), '**');
      case 'EM': case 'I': return wrap(mdInline(el, ctx), '_');
      case 'A':
        var href = el.getAttribute('href');
        // lien qui n'entoure qu'une image (vignette, drapeau, icône) : rien
        if (!squash(el.textContent) && el.querySelector('img')) return '';
        var txt = mdInline(el, ctx);
        if (!txt.trim()) return '';
        if (!href || /^(#|javascript:)/i.test(href) || !ctx.links) return txt;
        return '[' + squash(txt) + '](' + shortUrl(el.href) + ')';
      case 'SUP': case 'SUB': return mdInline(el, ctx);
    }
    if (BLOCK[t] && !inl) return mdBlocks(el, ctx);
    if (el.shadowRoot) return mdBlocks(el, ctx);
    return mdInline(el, ctx);
  }

  ops.markdown = function (a) {
    if (document.contentType === 'application/pdf') return { pdf: true };
    var t0 = now(), max = a.max_chars || 8000, offset = a.offset || 0, key = 'md';
    if (offset > 0 && M.store[key] != null) { var o0 = M.slice(key, null, offset, max); o0.title = document.title; o0.url = location.href; return o0; }
    var root = a.ref ? byRef(a.ref) : a.selector ? document.querySelector(a.selector) : (a.full ? document.body : mainRoot());
    if (!root) throw new Error('no element matches ' + a.selector);
    var ctx = { full: !!a.full || !!a.selector, noise: true, links: a.links !== false, root: root, defer: a.full || a.selector ? null : [] };
    var md = mdBlocks(root, ctx).replace(/\n{3,}/g, '\n\n').trim();
    if (ctx.defer && ctx.defer.length) {
      var box = ctx.defer.join('\n\n').trim(), at = md.search(/\n## /);
      md = at > 0 ? md.slice(0, at) + '\n\n' + box + md.slice(at) : md + '\n\n' + box;
    }
    if (!md && root !== document.body) { root = document.body; ctx.root = root; md = mdBlocks(root, ctx).replace(/\n{3,}/g, '\n\n').trim(); }
    var h1 = document.querySelector('h1');
    if (!a.selector && !/^# /.test(md) && document.title && !(h1 && root.contains(h1))) md = '# ' + document.title + '\n\n' + md;
    var o = M.slice(key, md, 0, max);
    o.title = document.title; o.url = location.href;
    if (root !== document.body && !a.selector && !a.full) o.main = root.tagName.toLowerCase() + (root.id ? '#' + root.id : '') + (typeof root.className === 'string' && root.className.trim() ? '.' + root.className.trim().split(/\s+/)[0] : '');
    o.ms = now() - t0;
    return o;
  };

  // PDF affiché par Safari : les octets du fichier, relus depuis la page (mêmes cookies), en base64 pour PDFKit côté serveur
  ops.pdf_data = function () {
    return fetch(location.href, { credentials: 'include' }).then(function (r) { return r.arrayBuffer(); }).then(function (buf) {
      if (buf.byteLength > 30e6) throw new Error('PDF too large to read (' + Math.round(buf.byteLength / 1e6) + ' MB)');
      var u = new Uint8Array(buf), parts = [];
      for (var i = 0; i < u.length; i += 0x8000) parts.push(String.fromCharCode.apply(null, u.subarray(i, i + 0x8000)));
      return { b64: btoa(parts.join('')), size: u.length };
    });
  };

  // ---------------------------------------------------------------- page_info

  ops.page_info = function () {
    var d = document, de = d.documentElement, b = d.body;
    var o = { url: location.href, title: d.title, ready_state: d.readyState };
    var ct = d.contentType || '';
    if (ct && ct !== 'text/html') o.content_type = ct;
    // frameworks et éditeurs
    var fw = [];
    var any = function (sel) { try { return !!d.querySelector(sel); } catch (e) { return false; } };
    var reactKey = function () {
      var els = [b, d.getElementById('root'), d.getElementById('__next'), d.getElementById('app'), b && b.firstElementChild];
      for (var i = 0; i < els.length; i++) { var e = els[i]; if (!e) continue; if (e._reactRootContainer) return true; for (var k in e) if (k.indexOf('__react') === 0) return true; }
      return false;
    };
    if (window.React || window.__REACT_DEVTOOLS_GLOBAL_HOOK__ && window.__REACT_DEVTOOLS_GLOBAL_HOOK__.renderers && window.__REACT_DEVTOOLS_GLOBAL_HOOK__.renderers.size || any('[data-reactroot]') || reactKey()) fw.push('React');
    if (window.__NEXT_DATA__) fw.push('Next.js');
    if (window.Vue || window.__VUE__ || any('[data-v-app]') || (d.getElementById('app') && d.getElementById('app').__vue_app__)) fw.push('Vue');
    if (window.ng || window.getAllAngularRootElements || any('[ng-version]')) fw.push('Angular');
    if (any('[class*="svelte-"]')) fw.push('Svelte');
    if (window.mxGraph || window.Graph || any('.geDiagramContainer')) fw.push('mxGraph (draw.io)');
    if (window.monaco || any('.monaco-editor')) fw.push('Monaco');
    if (any('.CodeMirror,.cm-editor')) fw.push('CodeMirror');
    if (any('.ProseMirror')) fw.push('ProseMirror');
    if (any('.kix-appview-editor,.docs-texteventtarget-iframe,.kix-canvas-tile-content')) fw.push('Google Docs (canvas)');
    if (window.jQuery) fw.push('jQuery');
    if (window.Polymer || any('ytd-app')) fw.push('Polymer/web components');
    if (fw.length) o.frameworks = fw;
    // éléments
    var nIframes = 0, nCross = 0, nShadow = 0, nEls = 0, canvasArea = 0, nInputs = 0, nPassword = 0, nInteractive = 0;
    walk(de, function (el) {
      nEls++;
      if (el.shadowRoot) nShadow++;
      var t = el.tagName;
      if (t === 'IFRAME' || t === 'FRAME') { nIframes++; if (crossOrigin(el)) nCross++; }
      if (t === 'CANVAS') { var r = el.getBoundingClientRect(); canvasArea += r.width * r.height; }
      if (t === 'INPUT' || t === 'TEXTAREA' || t === 'SELECT') { if (el.type !== 'hidden' && isVisible(el)) { nInputs++; if (el.type === 'password') nPassword++; } }
    });
    o.elements = nEls;
    if (nIframes) { o.iframes = nIframes; if (nCross) o.cross_origin_iframes = nCross; }
    if (nShadow) o.shadow_roots = nShadow;
    // type de page
    var text = (b && b.innerText) || '', title = (d.title + ' ' + ((d.querySelector('h1') || {}).textContent || '')).toLowerCase();
    var types = [];
    if (ct === 'application/pdf' || /\.pdf($|\?)/i.test(location.pathname) && (!b || b.children.length <= 1 && any('embed'))) types.push('pdf');
    if (any('iframe[src*="recaptcha"],iframe[src*="hcaptcha"],iframe[src*="challenges.cloudflare"],.g-recaptcha,.h-captcha,#cf-challenge-running') || /captcha|vérifiez que vous êtes humain|verify you are human/.test(text.slice(0, 3000).toLowerCase())) types.push('captcha');
    if (nPassword) types.push('login');
    if (/\b(404|403|500|502|503)\b|not found|page introuvable|introuvable|error|erreur/.test(title) && text.length < 5000) types.push('error');
    if (canvasArea > innerWidth * innerHeight * 0.4) types.push('canvas app');
    var art = d.querySelector('article,[role=main] p,main p,.mw-parser-output');
    if (art && text.length > 3000 && nInputs < 10) types.push('article');
    if (nInputs >= 3 && !nPassword && text.length < 6000) types.push('form');
    if (!types.length || (fw.length && types.indexOf('article') < 0 && types.indexOf('pdf') < 0)) types.push('application');
    o.page_type = types.filter(function (x, i) { return types.indexOf(x) === i; }).join(', ');
    // défilement
    var sh = Math.max(de.scrollHeight, b ? b.scrollHeight : 0);
    o.scroll = { y: Math.round(scrollY), height: sh, viewport: innerHeight };
    if (any('[role=feed],ytd-rich-grid-renderer,ytd-continuation-item-renderer,[data-testid*=infinite],.infinite-scroll') || (sh > innerHeight * 4 && any('[aria-busy=true],.loading,.spinner') )) o.scroll.infinite_likely = true;
    // dialogues ouverts
    var dl = [];
    d.querySelectorAll('dialog[open],[role=dialog],[role=alertdialog],[aria-modal=true]').forEach(function (x) { if (isVisible(x)) dl.push(refOf(x) + ' ' + (roleOf(x) || 'dialog') + ' ' + JSON.stringify(nameOf(x, 'dialog') || textOf(x, 60))); });
    if (dl.length) o.open_dialogs = dl.slice(0, 5);
    var ae = d.activeElement;
    while (ae && ae.shadowRoot && ae.shadowRoot.activeElement) ae = ae.shadowRoot.activeElement;
    if (ae && ae !== b && ae !== de) { var ar = roleOf(ae) || ae.tagName.toLowerCase(); o.focused = refOf(ae) + ' ' + ar + (nameOf(ae, ar) ? ' ' + JSON.stringify(nameOf(ae, ar)) : ''); }
    var sel = String(window.getSelection ? window.getSelection() : '');
    if (sel.trim()) o.selection = clip(sel, 300);
    if (M.dialogs.length) o.intercepted_dialogs = M.dialogs.length;
    return o;
  };

  // ================================================================ ACTION (phase C)

  function deepActive(doc) {
    var a = (doc || document).activeElement;
    for (var n = 0; a && n < 10; n++) {
      if (a.shadowRoot && a.shadowRoot.activeElement) { a = a.shadowRoot.activeElement; continue; }
      if ((a.tagName === 'IFRAME' || a.tagName === 'FRAME')) { try { if (a.contentDocument && a.contentDocument.activeElement) { a = a.contentDocument.activeElement; continue; } } catch (e) { /* autre origine */ } }
      break;
    }
    return a;
  }
  M.deepActive = deepActive;
  function brief(el) {
    if (!el || el === document.body || el === document.documentElement) return null;
    var r = roleOf(el) || (clickable(el) ? 'clickable' : el.tagName.toLowerCase());
    return line(el, r, { textMax: 80 });
  }

  // ---------------------------------------------------------------- observation des effets (attente implicite)

  // Démarre l'observation : mutations (document, racine shadow et cadre de la cible), URL, focus, requêtes, état de la cible
  M.watches = new Map(); M.watchNext = 1;
  function watch(el) {
    var w = { added: [], attrs: [], n: 0, t0: now(), last: now(), url: location.href, focus: deepActive(), net: M.net.inflight, netLast: M.net.last, el: el, dlg: M.dialogCount, sel: selKey() };
    if (el) w.state = stateKey(el);
    var cb = function (list) {
      w.n += list.length; w.last = now();
      for (var i = 0; i < list.length; i++) {
        var m = list[i];
        if (m.type === 'childList') { for (var j = 0; j < m.addedNodes.length && w.added.length < 300; j++) if (m.addedNodes[j].nodeType === 1) w.added.push(m.addedNodes[j]); }
        else if (m.type === 'attributes' && w.attrs.length < 300) w.attrs.push(m.target);
      }
    };
    var roots = [document.documentElement];
    if (el) {
      var rn = el.getRootNode && el.getRootNode();
      if (rn && rn !== document && roots.indexOf(rn) < 0) roots.push(rn.nodeType === 9 ? rn.documentElement : rn);
    }
    w.obs = roots.map(function (r) { var o = new MutationObserver(cb); o.observe(r, { childList: true, subtree: true, attributes: true, characterData: true }); return o; });
    var id = M.watchNext++;
    M.watches.set(id, w);
    return id;
  }
  M.watch = watch;
  // Sélection courante (Cmd+A, flèches : la page change sans muter le DOM)
  function selKey() {
    try { var s = deepActive() && deepActive().ownerDocument.getSelection(); return s ? [String(s).length, s.anchorOffset, s.focusOffset, s.anchorNode && s.anchorNode.nodeName].join('|') : ''; } catch (e) { return ''; }
  }
  function stateKey(el) {
    try { return [el.checked, el.value, clip(el.textContent, 100), el.getAttribute('aria-checked'), el.getAttribute('aria-expanded'), el.getAttribute('aria-pressed'), el.getAttribute('aria-selected'), el.isConnected].join('|'); } catch (e) { return ''; }
  }

  // Éléments apparus et visibles : menus, dialogues, listes… (lignes de snapshot, 15 au plus)
  function appeared(w) {
    var roots = [], out = [], seen = new Set();
    w.added.forEach(function (n) { if (n.isConnected) roots.push(n); });
    w.attrs.forEach(function (n) {
      if (!n.isConnected || n === w.el) return;
      var r = roleOf(n);
      if (r === 'menu' || r === 'dialog' || r === 'alertdialog' || r === 'listbox' || r === 'tooltip' || r === 'alert' || r === 'menubar' && false) { roots.push(n); return; }
      var cs = n.ownerDocument.defaultView.getComputedStyle(n);
      if ((cs.position === 'absolute' || cs.position === 'fixed') && n.querySelector('a,button,[role=menuitem],[role=option],input')) roots.push(n);
    });
    roots = roots.filter(function (r) { return !roots.some(function (o) { return o !== r && o.contains(r); }); });
    var count = 0;
    roots.forEach(function (root) {
      if (!isVisible(root) && !(root.children && root.children.length)) return;
      walk(root, function (el) {
        if (out.length >= 15) { count++; return false; }
        var t = el.tagName;
        if (t === 'SCRIPT' || t === 'STYLE' || t === 'TEMPLATE') return false;
        var role = roleOf(el);
        var want = role && (INTERACTIVE[role] || role === 'heading' || role === 'dialog' || role === 'alertdialog' || role === 'menu' || role === 'listbox' || role === 'alert' || role === 'tooltip');
        if (!want && !role && clickable(el)) { role = 'clickable'; want = true; }
        if (!want || seen.has(el) || !isVisible(el)) return;
        seen.add(el);
        out.push(line(el, role, { textMax: 80 }));
      });
      // bloc sans élément interactif (toast, message) : son texte
      if (!out.length && isVisible(root)) { var tx = clip(squash(root.innerText || ''), 120); if (tx) out.push(refOf(root) + ' text ' + JSON.stringify(tx)); }
    });
    if (count) out.push('… ' + count + ' more');
    return out;
  }

  function expectMet(x) {
    if (!x) return true;
    if (typeof x === 'string') {
      var p = x.match(/^(url|text|selector|gone):\s*(.*)$/);
      if (p) { var o = {}; o[p[1]] = p[2]; x = o; }
      else if (/^(https?:|\/)/.test(x)) x = { url: x };
      else if (/^[#.\[]|^[a-z][a-z0-9-]*[#.\[:]/i.test(x)) x = { selector: x };
      else x = { text: x };
    }
    if (x.url && location.href.indexOf(x.url) < 0) return false;
    if (x.selector) { var e = document.querySelector(x.selector) || (search({ selector: x.selector })[0] || {}).el; if (!e || !isVisible(e)) return false; }
    if (x.gone) { var g = document.querySelector(x.gone); if (g && isVisible(g)) return false; }
    if (x.text) { var r = search({ text: x.text }); if (!r.length || !r[0].visible) return false; }
    return true;
  }
  M.expectMet = expectMet;

  // Attend la stabilité (aucune mutation pendant `quiet` ms, au plus `max` ms) puis résume ce qui a changé.
  // Renvoie une fonction de sonde (undefined tant que ce n'est pas stable), évaluée par le serveur toutes les 30 ms.
  function settleCheck(id, opts) {
    var w = M.watches.get(id);
    if (!w) return function () { return { error: 'watch lost' }; };
    var quiet = opts.quiet || 150, max = opts.max || 2000, expect = opts.expect, emax = opts.expect_timeout || 2000;
    return function () {
      var t = now(), calm = t - w.last >= quiet && t - M.net.last >= Math.min(quiet, 100);
      var met = expect ? expectMet(expect) : true;
      // un lien suivi : la page se décharge, le serveur attendra la suivante
      if (M.unloading) { w.obs.forEach(function (o) { o.disconnect(); }); M.watches.delete(id); return { navigating: true, reacted: true }; }
      if (!((calm && (met || t - w.t0 >= emax)) || t - w.t0 >= Math.max(max, expect ? emax : 0))) return undefined;
      w.obs.forEach(function (o) { o.disconnect(); });
      M.watches.delete(id);
      var o = { mutations: w.n };
      var ap = appeared(w); if (ap.length) o.appeared = ap;
      if (location.href !== w.url) o.url = location.href;
      var f = deepActive();
      if (f !== w.focus && f && f !== document.body) o.focus = brief(f);
      var stateChanged = w.el && stateKey(w.el) !== w.state;
      if (w.el) { if (!w.el.isConnected) o.target_removed = true; else if (stateChanged) o.target = brief(w.el); }
      var netActivity = M.net.inflight !== w.net || M.net.last !== w.netLast;
      if (netActivity) o.network = true;
      if (expect) o.expect_met = met;
      var selChanged = selKey() !== w.sel;
      if (selChanged) { var sx = String(deepActive().ownerDocument.getSelection() || ''); if (sx) o.selection = clip(sx, 120); }
      o.reacted = expect ? met : (w.n > 0 || o.url !== undefined || stateChanged || netActivity || M.dialogCount > w.dlg || selChanged);
      return o;
    };
  }
  function settle(id, opts) { return checkJob(settleCheck(id, opts)); }
  M.settle = settle;
  ops.watch = function (a) { return { watch: watch(a.ref ? byRef(a.ref) : null) }; };
  ops.settle = function (a) { return settle(a.watch, a); };
  // Enchaîne une sonde de stabilité après une action synchrone et complète son résultat
  function settleThen(id, a, extra) {
    var chk = settleCheck(id, a);
    return checkJob(function () { var o = chk(); if (o === undefined) return undefined; return extra(o) || o; });
  }

  // ---------------------------------------------------------------- localisation (pour l'Accessibilité et les clics natifs)

  function center(el, a) {
    var r = rectOf(el);
    return { x: r.x + r.w / 2, y: r.y + r.h / 2, r: r };
  }
  function bringIntoView(el) {
    var r = el.getBoundingClientRect(), w = el.ownerDocument.defaultView;
    if (r.top < 0 || r.left < 0 || r.bottom > w.innerHeight || r.right > w.innerWidth) {
      if (el.scrollIntoViewIfNeeded) el.scrollIntoViewIfNeeded(true); else el.scrollIntoView({ block: 'center', inline: 'center' });
    }
    // dans une iframe : amener aussi le cadre à l'écran
    try { var fe = w.frameElement; if (fe) bringIntoView(fe); } catch (e) { /* autre origine */ }
  }
  ops.locate = function (a) {
    var el = target(a);
    bringIntoView(el);
    var c = a.x != null && a.y != null && !a.ref && !a.selector && a.text == null ? { x: a.x, y: a.y } : center(el);
    var o = { x: c.x, y: c.y, vw: innerWidth, vh: innerHeight, target: brief(el), ref: refOf(el) };
    if (a.watch !== false) o.watch = watch(el);
    var h = hiddenReason(el); if (h) o.hidden = h;
    return o;
  };

  // ---------------------------------------------------------------- click

  function mods(a) {
    var m = (a.modifiers || []).map(function (x) { return String(x).toLowerCase(); });
    return { metaKey: m.some(function (x) { return /cmd|command|meta|⌘/.test(x); }), ctrlKey: m.some(function (x) { return /ctrl|control/.test(x); }),
      altKey: m.some(function (x) { return /alt|option|⌥/.test(x); }), shiftKey: m.some(function (x) { return /shift|⇧/.test(x); }) };
  }
  function fire(dest, type, base, extra) {
    var w = dest.ownerDocument.defaultView, o = Object.assign({ bubbles: true, cancelable: true, composed: true, view: w }, base, extra || {});
    var ev;
    if (/^pointer/.test(type) && w.PointerEvent) ev = new w.PointerEvent(type, Object.assign({ pointerId: 1, pointerType: 'mouse', isPrimary: true, width: 1, height: 1, pressure: /down/.test(type) ? 0.5 : 0 }, o));
    else ev = new w.MouseEvent(type, o);
    if (type === 'pointerenter' || type === 'mouseenter' || type === 'pointerleave' || type === 'mouseleave') Object.defineProperty(ev, 'bubbles', { value: false });
    return dest.dispatchEvent(ev);
  }
  // Point du clic dans le repère du cadre de l'élément, et l'élément réellement touché à ce point (overlay compris)
  function hitAt(el, a) {
    var doc = el.ownerDocument, r = el.getBoundingClientRect();
    var x = a.x != null && a.y != null && !a.ref && !a.selector && a.text == null ? a.x : r.left + r.width / 2;
    var y = a.x != null && a.y != null && !a.ref && !a.selector && a.text == null ? a.y : r.top + r.height / 2;
    var hit = doc.elementFromPoint(x, y);
    for (var n = 0; hit && hit.shadowRoot && n < 10; n++) { var h2 = hit.shadowRoot.elementFromPoint(x, y); if (!h2 || h2 === hit) break; hit = h2; }
    return { x: x, y: y, hit: hit };
  }
  function clickSeq(el, a) {
    var p = hitAt(el, a), dest = el, covered = null;
    if (p.hit && (p.hit === el || el.contains(p.hit) || (p.hit.tagName === 'LABEL' && p.hit.control === el))) dest = p.hit;
    else if (p.hit && p.hit.contains(el)) dest = el;
    else if (p.hit) covered = p.hit;
    var w = dest.ownerDocument.defaultView, m = mods(a);
    var btn = a.button === 'right' ? 2 : a.button === 'middle' ? 1 : 0;
    var base = Object.assign({ clientX: p.x, clientY: p.y, screenX: p.x + (w.screenX || 0), screenY: p.y + (w.screenY || 0) + 80, button: btn }, m);
    fire(dest, 'pointerover', base, { buttons: 0 }); fire(dest, 'pointerenter', base, { buttons: 0 });
    fire(dest, 'mouseover', base, { buttons: 0 }); fire(dest, 'mouseenter', base, { buttons: 0 });
    fire(dest, 'pointermove', base, { buttons: 0 }); fire(dest, 'mousemove', base, { buttons: 0 });
    var count = a.double ? 2 : 1;
    for (var i = 1; i <= count; i++) {
      var downOk = fire(dest, 'pointerdown', base, { buttons: btn === 2 ? 2 : 1, detail: i }) & fire(dest, 'mousedown', base, { buttons: btn === 2 ? 2 : 1, detail: i });
      if (downOk && i === 1) {
        var f = dest.closest && dest.closest('a[href],button,input,textarea,select,summary,[tabindex],[contenteditable=""],[contenteditable=true]');
        if (f && f.focus) try { f.focus({ preventScroll: true }); } catch (e) { /* ignoré */ }
      }
      fire(dest, 'pointerup', base, { buttons: 0, detail: i }); fire(dest, 'mouseup', base, { buttons: 0, detail: i });
      if (btn === 2) { fire(dest, 'contextmenu', base, { buttons: 0, detail: i }); break; }
      if (btn === 0) fire(dest, 'click', base, { buttons: 0, detail: i });
    }
    if (a.double && btn === 0) fire(dest, 'dblclick', base, { buttons: 0, detail: 2 });
    return covered;
  }
  ops.click = function (a) {
    var el = target(a);
    var hidden = hiddenReason(el);
    if (hidden && !a.force) throw new Error('target is hidden (' + hidden + '): ' + brief(el));
    // désactivé : le serveur réessaie jusqu'au délai (un menu se remplit pendant que l'app démarre)
    if (!a.force && (el.disabled || el.getAttribute('aria-disabled') === 'true')) throw new Error('target is disabled: ' + brief(el));
    bringIntoView(el);
    var id = watch(el), before = brief(el);
    var covered = clickSeq(el, a);
    // lien suivi sans écouteur qui l'empêche : la navigation est l'effet attendu
    return settleThen(id, a, function (o) {
      o.clicked = before;
      if (covered) o.covered_by = describeEl(covered);
      return o;
    });
  };

  // ---------------------------------------------------------------- hover

  ops.hover = function (a) {
    var el = target(a);
    bringIntoView(el);
    var id = watch(el), p = hitAt(el, a), dest = p.hit && (p.hit === el || el.contains(p.hit)) ? p.hit : el;
    var base = { clientX: p.x, clientY: p.y, button: 0, buttons: 0 };
    ['pointerover', 'pointerenter', 'mouseover', 'mouseenter', 'pointermove', 'mousemove'].forEach(function (t) { fire(dest, t, base); });
    return settleThen(id, a, function (o) { o.hovered = brief(el); return o; });
  };

  // ---------------------------------------------------------------- type

  function editableOf(el) {
    if (!el) return null;
    if (el.tagName === 'LABEL' && el.control) return el.control;
    if (/^(INPUT|TEXTAREA)$/.test(el.tagName) || el.isContentEditable) return el;
    var inner = el.querySelector && el.querySelector('input:not([type=hidden]),textarea,[contenteditable=""],[contenteditable=true]');
    return inner || el;
  }
  function setNativeValue(el, v) {
    var w = el.ownerDocument.defaultView;
    var proto = el.tagName === 'TEXTAREA' ? w.HTMLTextAreaElement.prototype : el.tagName === 'SELECT' ? w.HTMLSelectElement.prototype : w.HTMLInputElement.prototype;
    var d = Object.getOwnPropertyDescriptor(proto, 'value');
    // setter du prototype : React, Vue et Angular voient la nouvelle valeur (leur setter d'instance est contourné)
    if (d && d.set) d.set.call(el, v); else el.value = v;
  }
  M.setNativeValue = setNativeValue;
  function inputEv(el, type, data, inputType) {
    var w = el.ownerDocument.defaultView;
    var ev = w.InputEvent ? new w.InputEvent(type, { bubbles: true, cancelable: type === 'beforeinput', composed: true, data: data, inputType: inputType || 'insertText' }) : new w.Event(type, { bubbles: true });
    return el.dispatchEvent(ev);
  }
  ops.type = function (a) {
    var el = a.ref || a.selector || a.text != null || a.label != null || a.near != null ? editableOf(target(a)) : deepActive();
    if (!el || el === document.body) throw new Error('no target: give ref, selector, label or text, or focus a field first');
    if (el.disabled || el.readOnly) throw new Error('field is ' + (el.disabled ? 'disabled' : 'read-only') + ': ' + brief(el));
    bringIntoView(el);
    var text = a.value != null ? String(a.value) : '';
    var id = watch(el);
    if (el.focus) el.focus({ preventScroll: true });
    var doc = el.ownerDocument, expected;
    if (/^(INPUT|TEXTAREA)$/.test(el.tagName)) {
      var cur = a.clear ? '' : el.value;
      expected = cur + text;
      if (a.clear && el.value) { setNativeValue(el, ''); inputEv(el, 'input', null, 'deleteContentBackward'); }
      if (inputEv(el, 'beforeinput', text)) {
        setNativeValue(el, expected);
        try { el.setSelectionRange(expected.length, expected.length); } catch (e) { /* type sans sélection */ }
        inputEv(el, 'input', text);
      }
      el.dispatchEvent(new (doc.defaultView.Event)('change', { bubbles: true }));
    } else if (el.isContentEditable) {
      var sel = doc.getSelection(), range = doc.createRange();
      range.selectNodeContents(el);
      if (!a.clear) range.collapse(false);
      sel.removeAllRanges(); sel.addRange(range);
      if (a.clear) doc.execCommand('delete', false);
      // insertText déclenche beforeinput et input comme une vraie frappe (ProseMirror, Lexical, Draft les écoutent)
      var ok = text ? doc.execCommand('insertText', false, text) : true;
      if (!ok) { range = sel.getRangeAt(0); range.insertNode(doc.createTextNode(text)); range.collapse(false); inputEv(el, 'input', text); }
      expected = null;
    } else throw new Error('not a text field: ' + brief(el) + ' (use click, select or check)');
    return settleThen(id, Object.assign({ quiet: 100 }, a), function (o) {
      o.field = brief(el);
      var v = /^(INPUT|TEXTAREA)$/.test(el.tagName) ? el.value : squash(el.innerText);
      o.value = clip(el.type === 'password' ? '••••' : v, 300);
      o.ok = expected != null ? v === expected : v.indexOf(squash(text)) >= 0;
      return o;
    });
  };

  // ---------------------------------------------------------------- press (touches et raccourcis)

  var KEYS = { enter: ['Enter', 'Enter', 13], return: ['Enter', 'Enter', 13], tab: ['Tab', 'Tab', 9], escape: ['Escape', 'Escape', 27], esc: ['Escape', 'Escape', 27],
    backspace: ['Backspace', 'Backspace', 8], delete: ['Delete', 'Delete', 46], space: [' ', 'Space', 32], arrowleft: ['ArrowLeft', 'ArrowLeft', 37],
    arrowup: ['ArrowUp', 'ArrowUp', 38], arrowright: ['ArrowRight', 'ArrowRight', 39], arrowdown: ['ArrowDown', 'ArrowDown', 40], left: ['ArrowLeft', 'ArrowLeft', 37],
    up: ['ArrowUp', 'ArrowUp', 38], right: ['ArrowRight', 'ArrowRight', 39], down: ['ArrowDown', 'ArrowDown', 40], home: ['Home', 'Home', 36], end: ['End', 'End', 35],
    pageup: ['PageUp', 'PageUp', 33], pagedown: ['PageDown', 'PageDown', 34] };
  function parseKey(k) {
    var parts = String(k).split('+').map(function (x) { return x.trim(); }).filter(Boolean);
    var key = parts.pop() || '', m = mods({ modifiers: parts });
    var low = key.toLowerCase(), d = KEYS[low];
    if (!d && /^f([1-9]|1[0-2])$/.test(low)) d = [key.toUpperCase(), key.toUpperCase(), 111 + +low.slice(1)];
    if (!d) {
      if (key.length !== 1) throw new Error('unknown key ' + key + ' (Enter, Tab, Escape, Backspace, Delete, Space, Arrow*, Home, End, PageUp, PageDown, F1-F12, a letter or digit, with Cmd/Ctrl/Alt/Shift+)');
      var up = key.toUpperCase(), code = /[a-z]/i.test(key) ? 'Key' + up : /\d/.test(key) ? 'Digit' + key : '';
      d = [m.shiftKey ? up : key.toLowerCase() === key ? key : key, code, up.charCodeAt(0)];
      if (/[a-z]/i.test(key)) d[0] = m.shiftKey ? up : key.toLowerCase();
    }
    return { key: d[0], code: d[1], keyCode: d[2], m: m, name: key };
  }
  function keyEv(el, type, k) {
    var w = el.ownerDocument.defaultView;
    var ev = new w.KeyboardEvent(type, Object.assign({ key: k.key, code: k.code, bubbles: true, cancelable: true, composed: true, view: w }, k.m));
    // keyCode et which ne passent pas par le constructeur : posés sur l'instance (vieux gestionnaires)
    try { Object.defineProperty(ev, 'keyCode', { value: k.keyCode }); Object.defineProperty(ev, 'which', { value: k.keyCode }); Object.defineProperty(ev, 'charCode', { value: type === 'keypress' ? k.key.charCodeAt(0) : 0 }); } catch (e) { /* ignoré */ }
    return el.dispatchEvent(ev);
  }
  var EDIT_CMDS = { a: 'selectAll', z: 'undo', b: 'bold', i: 'italic', u: 'underline', c: 'copy', x: 'cut' };
  // Action par défaut que le navigateur aurait faite pour une vraie touche (les événements synthétiques n'en font aucune)
  function defaultAction(el, k) {
    var doc = el.ownerDocument, editable = /^(INPUT|TEXTAREA)$/.test(el.tagName) || el.isContentEditable;
    var cmd = k.m.metaKey || k.m.ctrlKey, low = k.key.toLowerCase();
    if (cmd && editable && EDIT_CMDS[low]) {
      var c = low === 'z' && k.m.shiftKey ? 'redo' : EDIT_CMDS[low];
      if (c === 'selectAll' && el.select) { el.select(); return c; }
      return doc.execCommand(c, false) ? c : null;
    }
    if (cmd) return null;
    if (k.key === 'Enter') {
      if (el.tagName === 'INPUT' && el.form) { if (el.form.requestSubmit) el.form.requestSubmit(); else el.form.submit(); return 'submit'; }
      if (el.tagName === 'TEXTAREA') { inputEv(el, 'beforeinput', '\n', 'insertLineBreak'); setNativeValue(el, el.value + '\n'); inputEv(el, 'input', '\n', 'insertLineBreak'); return 'newline'; }
      if (el.isContentEditable) return doc.execCommand('insertParagraph', false) ? 'newline' : null;
      if (/^(BUTTON|A|SUMMARY)$/.test(el.tagName) || roleOf(el) === 'button' || roleOf(el) === 'link') { el.click(); return 'activate'; }
    }
    if (k.key === ' ' && (/^(BUTTON|SUMMARY)$/.test(el.tagName) || /^(checkbox|radio)$/i.test(el.type) || roleOf(el) === 'button' || roleOf(el) === 'checkbox')) { el.click(); return 'activate'; }
    if (k.key === 'Tab') {
      var f = Array.from(doc.querySelectorAll('a[href],button,input:not([type=hidden]),textarea,select,[tabindex]:not([tabindex="-1"]),[contenteditable=true]')).filter(function (x) { return !x.disabled && isVisible(x); });
      var i = f.indexOf(el), nx = f[(i + (k.m.shiftKey ? -1 : 1) + f.length) % f.length];
      if (nx) { nx.focus(); return 'focus'; }
    }
    if (k.key === 'Backspace' && /^(INPUT|TEXTAREA)$/.test(el.tagName) && el.value) { setNativeValue(el, el.value.slice(0, -1)); inputEv(el, 'input', null, 'deleteContentBackward'); return 'delete'; }
    if (k.key === 'Backspace' && el.isContentEditable) return doc.execCommand('delete', false) ? 'delete' : null;
    return null;
  }
  ops.press = function (a) {
    var keys = Array.isArray(a.keys) ? a.keys : [a.keys || a.key];
    var el = a.ref || a.selector || a.text != null || a.label != null ? target(a) : deepActive();
    if (!el) el = document.body;
    if ((a.ref || a.selector || a.text != null) && el.focus) el.focus({ preventScroll: true });
    var id = watch(el), done = [];
    keys.forEach(function (raw) {
      var k = parseKey(raw), cur = a.ref || a.selector ? el : (deepActive() || el);
      var ok = keyEv(cur, 'keydown', k);
      if (ok && k.key.length === 1 && !k.m.metaKey && !k.m.ctrlKey) keyEv(cur, 'keypress', k);
      var act = ok ? defaultAction(cur, k) : null;
      keyEv(cur, 'keyup', k);
      done.push(raw + (act ? ' → ' + act : ok ? '' : ' (handled by the page)'));
      if (!ok || act) done.handled = true;
    });
    return settleThen(id, a, function (o) {
      o.keys = done;
      if (done.handled) o.reacted = true;
      return o;
    });
  };

  // ---------------------------------------------------------------- select, check

  ops.select = function (a) {
    var el = target(a);
    if (el.tagName === 'LABEL' && el.control) el = el.control;
    if (el.tagName !== 'SELECT') {
      var inner = el.querySelector && el.querySelector('select');
      if (!inner) throw new Error('not a <select>: ' + brief(el) + ' — for a custom dropdown, click it then click the option');
      el = inner;
    }
    var wanted = [].concat(a.option != null ? a.option : a.values || []).map(String);
    if (!wanted.length) throw new Error('give option: the value or visible text of the option');
    var id = watch(el), picked = [];
    Array.from(el.options).forEach(function (o) {
      var hit = wanted.some(function (w) { return o.value === w || fold(o.text) === fold(w); }) ||
        (!picked.length && wanted.some(function (w) { return fold(o.text).indexOf(fold(w)) >= 0; }));
      if (hit && (el.multiple || !picked.length)) { picked.push(o); }
    });
    if (!picked.length) throw new Error('no option matches ' + JSON.stringify(wanted) + ' in ' + brief(el) + '; options: ' + Array.from(el.options).slice(0, 20).map(function (o) { return JSON.stringify(squash(o.text)); }).join(', '));
    el.focus();
    if (el.multiple) Array.from(el.options).forEach(function (o) { o.selected = picked.indexOf(o) >= 0; });
    else setNativeValue(el, picked[0].value);
    el.dispatchEvent(new (el.ownerDocument.defaultView.Event)('input', { bubbles: true }));
    el.dispatchEvent(new (el.ownerDocument.defaultView.Event)('change', { bubbles: true }));
    return settleThen(id, a, function (o) { o.selected = picked.map(function (x) { return squash(x.text); }); o.field = brief(el); return o; });
  };

  function isChecked(el) { var a = el.getAttribute('aria-checked') || el.getAttribute('aria-pressed'); return a != null && el.type !== 'checkbox' && el.type !== 'radio' ? a === 'true' : !!el.checked; }
  ops.check = function (a) {
    var el = target(a);
    if (el.tagName === 'LABEL' && el.control) el = el.control;
    else if (!/^(checkbox|radio|switch|menuitemcheckbox|menuitemradio)$/.test(roleOf(el) || '')) {
      var inner = el.querySelector && el.querySelector('input[type=checkbox],input[type=radio],[role=checkbox],[role=switch],[role=radio]');
      if (inner) el = inner;
    }
    var want = a.checked !== false;
    if (isChecked(el) === want) return { field: brief(el), checked: want, changed: false };
    var id = watch(el);
    // une case native masquée par un style personnalisé : clic sur son label, sinon sur elle-même
    var clickEl = el, lab = el.labels && el.labels[0];
    if (!isVisible(el) && lab) clickEl = lab;
    bringIntoView(clickEl);
    clickSeq(clickEl, {});
    if (isChecked(el) !== want && el.click) el.click();
    return settleThen(id, a, function (o) { o.field = brief(el); o.checked = isChecked(el); o.changed = true; o.ok = o.checked === want; return o; });
  };

  // ---------------------------------------------------------------- scroll

  // Élément qui défile vraiment : le document, sinon le plus grand conteneur défilant (Gmail, Notion, apps)
  function scroller() {
    var se = document.scrollingElement || document.documentElement;
    if (se.scrollHeight > innerHeight + 10) return se;
    var best = se, area = 0;
    walk(document.body || se, function (el) {
      if (el.scrollHeight > el.clientHeight + 20 && el.clientHeight > 100) {
        var o = getComputedStyle(el).overflowY;
        if ((o === 'auto' || o === 'scroll') && el.clientWidth * el.clientHeight > area) { area = el.clientWidth * el.clientHeight; best = el; }
      }
    });
    return best;
  }
  ops.scroll = function (a) {
    var t0 = now();
    if (a.ref || a.selector || a.text != null) {
      var el = target(a);
      el.scrollIntoView({ block: a.block || 'center', inline: 'nearest' });
      return { scrolled_to: brief(el), rect: rectArr(rectOf(el)) };
    }
    var sc = scroller(), isDoc = sc === document.scrollingElement || sc === document.documentElement;
    var before = { top: sc.scrollTop, h: sc.scrollHeight, n: document.getElementsByTagName('*').length };
    var to = a.to || (a.by != null ? null : 'bottom');
    var id = watch(null);
    if (to === 'top') sc.scrollTop = 0;
    else if (to === 'bottom') sc.scrollTop = sc.scrollHeight;
    else sc.scrollBy ? sc.scrollBy(a.x || 0, a.by || 0) : (sc.scrollTop += a.by || 0);
    if (isDoc) window.dispatchEvent(new Event('scroll'));
    function result(extra) {
      var o = Object.assign({ y: Math.round(sc.scrollTop), height: sc.scrollHeight, viewport: isDoc ? innerHeight : sc.clientHeight }, extra);
      if (!isDoc) o.container = brief(sc) || describeEl(sc);
      if (sc.scrollTop + (isDoc ? innerHeight : sc.clientHeight) >= sc.scrollHeight - 2) o.at_bottom = true;
      return o;
    }
    if (to !== 'bottom' || a.wait_more === false) { var w0 = M.watches.get(id); w0.obs.forEach(function (o) { o.disconnect(); }); M.watches.delete(id); return result({}); }
    // défilement infini : attendre l'arrivée de nouveaux éléments (au plus timeout ms), puis redescendre une fois
    var limit = a.timeout || 4000;
    return checkJob(function () {
      var grown = sc.scrollHeight > before.h + 5 || document.getElementsByTagName('*').length > before.n + 5;
      var w = M.watches.get(id), quiet = w && now() - w.last > 300;
      if (!((grown && (quiet || now() - t0 > 1500)) || now() - t0 > limit)) return undefined;
      if (w) { w.obs.forEach(function (o) { o.disconnect(); }); M.watches.delete(id); }
      var added = document.getElementsByTagName('*').length - before.n;
      if (grown) sc.scrollTop = sc.scrollHeight;
      return result({ loaded_more: grown, new_elements: Math.max(0, added) });
    });
  };

  // ---------------------------------------------------------------- wait (une sonde : le serveur répète toutes les 30 ms)

  ops.probe = function (a) {
    var o = { ready_state: document.readyState, url: location.href };
    var met = true;
    if (a.selector) { var r = search({ selector: a.selector }).filter(function (x) { return x.visible; }); met = met && r.length > 0; if (r.length) o.found = brief(r[0].el); }
    if (a.text != null) { var t = search({ text: a.text }).filter(function (x) { return x.visible; }); met = met && t.length > 0; if (t.length) o.found = brief(t[0].el); }
    if (a.gone) { var g = search({ selector: a.gone }).filter(function (x) { return x.visible; }); met = met && !g.length; }
    if (a.text_gone != null) { var tg = search({ text: a.text_gone }).filter(function (x) { return x.visible; }); met = met && !tg.length; }
    if (a.url) met = met && location.href.indexOf(a.url) >= 0;
    if (a.ready_state) met = met && (document.readyState === a.ready_state || (a.ready_state === 'interactive' && document.readyState === 'complete'));
    if (a.network_idle) { var idle = a.idle_ms || 500; met = met && M.net.inflight === 0 && now() - M.net.last >= idle; o.inflight = M.net.inflight; }
    o.met = met;
    return o;
  };
  M.probeWith = function (a, fn) {
    var o = JSON.parse(M.run('probe', a));
    if (o.error) return JSON.stringify(o);
    try { var v = fn(); if (!v) o.met = false; else if (v !== true) o.value = ser(v); } catch (e) { o.met = false; o.js_error = errInfo(e).message; }
    return JSON.stringify(o);
  };

  // ---------------------------------------------------------------- read (étape d'act)

  ops.read = function (a) {
    var max = a.max_chars || 4000;
    if (!(a.ref || a.selector || a.text != null || a.label != null)) return ops.markdown({ max_chars: max });
    var el = target(a);
    var v = /^(INPUT|TEXTAREA|SELECT)$/.test(el.tagName) ? (el.tagName === 'SELECT' ? valueOf(el, 'combobox') : el.value) : (el.innerText || el.textContent || '');
    var o = M.slice('read', v, a.offset || 0, max);
    o.element = brief(el);
    return o;
  };

  window.__mcp = M;
})();
