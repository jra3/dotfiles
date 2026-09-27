'use strict';

/*
 * The parts of Shorts removal that CSS can't express: following a /shorts/ link
 * up to whatever renderer wraps it, matching a tab or chip by its label, and
 * catching YouTube's in-app navigations.
 *
 * rules.json already redirects real /shorts/ navigations at the network layer.
 * That never fires for YouTube's own pushState routing, which loads a Short
 * without a main_frame request, so the same redirect is repeated here.
 */

const SHORTS_VIDEO = /^\/shorts\/([\w-]+)/;
const CHANNEL_SHORTS = /^\/(@[^/]+|channel\/[^/]+|c\/[^/]+|user\/[^/]+)\/shorts\/?$/;

function shortsTarget(pathname) {
  const video = SHORTS_VIDEO.exec(pathname);
  if (video) return `https://www.youtube.com/watch?v=${video[1]}`;

  const channel = CHANNEL_SHORTS.exec(pathname);
  if (channel) return `https://www.youtube.com/${channel[1]}/videos`;

  if (pathname === '/shorts' || pathname === '/shorts/') return 'https://www.youtube.com/';
  return null;
}

function redirect() {
  const target = shortsTarget(location.pathname);
  // replace(), not assign(): a history entry here would bounce Back into the
  // Short we just left.
  if (target) location.replace(target);
}

/*
 * Renderers that wrap a single video. A /shorts/ link is followed up the tree
 * only as far as one of these, so a Short linked from a description or a comment
 * can't take its whole section down with it.
 */
const LOCKUPS = new Set([
  'YTD-RICH-ITEM-RENDERER',
  'YTD-VIDEO-RENDERER',
  'YTD-COMPACT-VIDEO-RENDERER',
  'YTD-GRID-VIDEO-RENDERER',
  'YTD-PLAYLIST-VIDEO-RENDERER',
  'YTD-REEL-ITEM-RENDERER',
  'YT-LOCKUP-VIEW-MODEL',
  'YTM-SHORTS-LOCKUP-VIEW-MODEL',
  'YTM-SHORTS-LOCKUP-VIEW-MODEL-V2',
  'YTD-GUIDE-ENTRY-RENDERER',
  'YTD-MINI-GUIDE-ENTRY-RENDERER',
]);

const SHORTS_LINK = 'a[href^="/shorts"], a[href*="youtube.com/shorts"]';

// Elements that carry a visible "Shorts" label rather than a /shorts/ href.
const LABELLED =
  'yt-tab-shape, tp-yt-paper-tab, yt-chip-cloud-chip-renderer, ' +
  'ytd-guide-entry-renderer, ytd-mini-guide-entry-renderer';

function hide(el) {
  if (el.style.display !== 'none') el.style.setProperty('display', 'none', 'important');
}

function sweep() {
  for (const link of document.querySelectorAll(SHORTS_LINK)) {
    let el = link;
    // Bounded walk: deep enough for YouTube's nesting, shallow enough that a
    // miss stays a miss instead of climbing into the page chrome.
    for (let depth = 0; el && depth < 12; depth++) {
      if (LOCKUPS.has(el.tagName)) {
        hide(el);
        break;
      }
      el = el.parentElement;
    }
  }

  for (const el of document.querySelectorAll(LABELLED)) {
    if (el.textContent.trim() === 'Shorts') hide(el);
  }
}

let scheduled = false;
let lastHref = location.href;

function schedule() {
  if (scheduled) return;
  scheduled = true;
  requestAnimationFrame(() => {
    scheduled = false;
    // Cheapest place to notice a pushState: YouTube always mutates the DOM when
    // it routes, so no history patching or guessing at event names is needed.
    if (location.href !== lastHref) {
      lastHref = location.href;
      redirect();
    }
    sweep();
  });
}

redirect();

// Only childList/subtree: observing attributes would refire on the inline
// styles hide() writes.
new MutationObserver(schedule).observe(document.documentElement, {
  childList: true,
  subtree: true,
});

document.addEventListener('yt-navigate-start', schedule, true);
document.addEventListener('yt-navigate-finish', schedule, true);
window.addEventListener('popstate', schedule, true);
