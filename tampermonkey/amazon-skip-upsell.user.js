// ==UserScript==
// @name         Amazon: skip "Need anything else?" page
// @namespace    https://github.com/jra3/dotfiles
// @version      1.0
// @description  Clicks "Continue to checkout" on Amazon's upsell step automatically
// @match        https://www.amazon.com/checkout/byg/*
// @run-at       document-start
// @grant        none
// @updateURL    https://raw.githubusercontent.com/jra3/dotfiles/main/tampermonkey/amazon-skip-upsell.user.js
// @downloadURL  https://raw.githubusercontent.com/jra3/dotfiles/main/tampermonkey/amazon-skip-upsell.user.js
// ==/UserScript==

(function () {
  'use strict';

  const findButton = () =>
    document.querySelector('a[name="checkout-byg-ptc-button"]') ||
    [...document.querySelectorAll('a, input[type="submit"], button')]
      .find(el => /continue to checkout/i.test(el.textContent || el.value || ''));

  const go = () => {
    const btn = findButton();
    if (!btn) return false;
    if (btn.href) location.replace(btn.href); // no extra history entry
    else btn.click();
    return true;
  };

  if (go()) return;
  const obs = new MutationObserver(() => { if (go()) obs.disconnect(); });
  obs.observe(document.documentElement, { childList: true, subtree: true });
  setTimeout(() => obs.disconnect(), 10000); // give up after 10s
})();
