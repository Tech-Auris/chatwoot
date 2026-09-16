/*
 * AurisChat GCLID → WhatsApp bridge
 *
 * Drop this on any landing page that runs a Google Ads campaign whose
 * conversion is a click on a "Fale no WhatsApp" button. It reads the
 * gclid the ad appended to the URL, caches it per browser for 90 days,
 * and appends `gclid=<token>` to the prefilled text of every WhatsApp
 * chat link on the page (wa.me / api.whatsapp.com / web.whatsapp.com).
 *
 * When that message reaches an AurisChat inbox, the extractor pulls the
 * token from the body and the contact's Origem do lead is stamped
 * "Google" automatically, closing the loop back to the ad click.
 *
 * Usage: paste ONE of the following inside <body> (before your WhatsApp
 * buttons ideally, though the snippet also handles buttons rendered
 * later):
 *
 *   <script src="https://<your-aurischat-host>/downloads/gclid-to-whatsapp.js" defer></script>
 *
 * Or self-host by copying this file to your own static server.
 *
 * No external requests. No cookies. localStorage only.
 */
(function () {
  'use strict';

  var STORAGE_KEY = '_aurischat_gclid';
  var TTL_MS = 90 * 24 * 60 * 60 * 1000;
  var WA_HOST_RE = /^(?:(?:api|web|chat)\.whatsapp\.com|wa\.me)$/i;

  function readFromUrl() {
    try {
      var params = new URLSearchParams(window.location.search);
      var token = params.get('gclid');
      return token && /^[\w-]+$/.test(token) ? token : null;
    } catch (_e) {
      return null;
    }
  }

  function readFromStorage() {
    try {
      var raw = window.localStorage.getItem(STORAGE_KEY);
      if (!raw) return null;
      var parsed = JSON.parse(raw);
      if (!parsed || !parsed.token || !parsed.expiresAt) return null;
      if (Date.now() > parsed.expiresAt) {
        window.localStorage.removeItem(STORAGE_KEY);
        return null;
      }
      return parsed.token;
    } catch (_e) {
      return null;
    }
  }

  function persist(token) {
    try {
      window.localStorage.setItem(
        STORAGE_KEY,
        JSON.stringify({ token: token, expiresAt: Date.now() + TTL_MS })
      );
    } catch (_e) {
      /* private mode / storage disabled — silently continue */
    }
  }

  function resolveToken() {
    var fresh = readFromUrl();
    if (fresh) {
      persist(fresh);
      return fresh;
    }
    return readFromStorage();
  }

  function isWhatsappLink(anchor) {
    if (!anchor || !anchor.href) return false;
    try {
      var url = new URL(anchor.href, window.location.href);
      return WA_HOST_RE.test(url.hostname);
    } catch (_e) {
      return false;
    }
  }

  function appendGclidToText(url, token) {
    var current = url.searchParams.get('text') || '';
    if (/(?:^|[\s?&])gclid=/i.test(current)) return false;
    var suffix = (current ? ' ' : '') + 'gclid=' + token;
    url.searchParams.set('text', current + suffix);
    return true;
  }

  function rewriteAnchor(anchor, token) {
    if (!isWhatsappLink(anchor)) return;
    if (anchor.dataset && anchor.dataset.aurischatGclid === '1') return;
    try {
      var url = new URL(anchor.href, window.location.href);
      var changed = appendGclidToText(url, token);
      if (changed) anchor.href = url.toString();
      if (anchor.dataset) anchor.dataset.aurischatGclid = '1';
    } catch (_e) {
      /* malformed href — skip */
    }
  }

  function rewriteAll(root, token) {
    if (!root || !root.querySelectorAll) return;
    var anchors = root.querySelectorAll('a[href]');
    for (var i = 0; i < anchors.length; i += 1) rewriteAnchor(anchors[i], token);
  }

  function watchForNewAnchors(token) {
    if (typeof MutationObserver !== 'function') return;
    var observer = new MutationObserver(function (mutations) {
      for (var i = 0; i < mutations.length; i += 1) {
        var added = mutations[i].addedNodes;
        for (var j = 0; j < added.length; j += 1) {
          var node = added[j];
          if (node.nodeType !== 1) continue;
          if (node.tagName === 'A') rewriteAnchor(node, token);
          else rewriteAll(node, token);
        }
      }
    });
    observer.observe(document.body, { childList: true, subtree: true });
  }

  function init() {
    var token = resolveToken();
    if (!token) return;
    rewriteAll(document, token);
    watchForNewAnchors(token);
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init, { once: true });
  } else {
    init();
  }
})();
