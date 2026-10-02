// ==UserScript==
// @name         Amazon: skip "Need anything else?" page
// @namespace    https://github.com/jra3/dotfiles
// @version      2.0
// @description  Auto-continues past Amazon's upsell step to checkout
// @match        https://www.amazon.com/checkout/*
// @run-at       document-end
// @grant        none
// @updateURL    https://raw.githubusercontent.com/jra3/dotfiles/main/tampermonkey/amazon-skip-upsell.user.js
// @downloadURL  https://raw.githubusercontent.com/jra3/dotfiles/main/tampermonkey/amazon-skip-upsell.user.js
// ==/UserScript==

(function () {
  'use strict';

  const isByg = () => location.pathname.includes('/checkout/byg');

  const findButton = () =>
    document.querySelector('a[name="checkout-byg-ptc-button"]') ||
    [...document.querySelectorAll('a, button, input[type="submit"]')]
      .find(el => /continue to checkout/i.test(el.textContent || el.value || ''));

  let lastTried = 0;
  const tick = () => {
    if (!isByg()) return;
    // loop guard: don't fire more than once every 5s
    if (Date.now() - lastTried < 5000) return;
    const btn = findButton();
    if (!btn) return;
    lastTried = Date.now();
    const href = btn.getAttribute('href');
    if (href && !href.startsWith('#') && !href.startsWith('javascript')) {
      location.replace(btn.href);
    } else {
      btn.click();
    }
  };

  const start = Date.now();
  const timer = setInterval(() => {
    tick();
    if (Date.now() - start > 15000) clearInterval(timer);
  }, 250);

  // catch in-page (no reload) navigation to the upsell step
  let lastPath = location.pathname;
  setInterval(() => {
    if (location.pathname !== lastPath) {
      lastPath = location.pathname;
      const s = Date.now();
      const t = setInterval(() => { tick(); if (Date.now() - s > 15000) clearInterval(t); }, 250);
    }
  }, 500);
})();
