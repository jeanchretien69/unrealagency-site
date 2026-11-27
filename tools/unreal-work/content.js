// Counts activity on the page (numbers only, never what is typed) and hands it to the background every 10 s.
(() => {
  let c = { clicks: 0, keys: 0, scrolls: 0 }, lastScroll = 0;
  addEventListener('click', () => c.clicks++, true);
  addEventListener('keydown', () => c.keys++, true);
  addEventListener('scroll', () => { const n = Date.now(); if (n - lastScroll > 400) { c.scrolls++; lastScroll = n; } }, { capture: true, passive: true });
  setInterval(() => {
    if (!c.clicks && !c.keys && !c.scrolls) return;
    const send = c; c = { clicks: 0, keys: 0, scrolls: 0 };
    try { chrome.runtime.sendMessage({ t: 'act', ...send }); } catch (e) {}
  }, 10000);
})();
