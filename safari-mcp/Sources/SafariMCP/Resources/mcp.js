// Bibliothèque du serveur MCP Safari, injectée une fois par page (window.__mcp).
// Le serveur envoie ensuite des scripts minuscules : window.__mcp&&__mcp.v===V ? __mcp.run(op, args) : "\u0000nolib".
// Chaque opération renvoie un objet JSON (chaîne) ; une opération asynchrone renvoie {job: id}, que le serveur
// sonde toutes les 30 ms avec run('poll', {id}). Les dialogues (alert, confirm, prompt, beforeunload) sont
// interceptés et rendus dans la réponse de l'appel suivant, pour que Safari ne gèle jamais.
// Embarquée dans le binaire (ressource SwiftPM embedInCode) : changer V à chaque modification.
(function () {
  'use strict';
  var V = 1;
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

  function logDialog(type, message, answer) {
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
    w.addEventListener('beforeunload', function (e) { e.stopImmediatePropagation(); logDialog('beforeunload', ''); }, true);
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

  ops.poll = function (a) {
    var j = M.jobs.get(a.id);
    if (!j) return { error: 'job lost', lost: true };
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

  window.__mcp = M;
})();
