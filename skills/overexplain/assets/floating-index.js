/* overexplain — floating index scrollspy.
   Highlights the nav.toc entry for the section currently being scrolled through.
   Expects: <nav class="toc"> containing <a href="#id"> links, in document order,
   each pointing at a heading id that exists on the page. */
(function () {
  const nav = document.querySelector("nav.toc");
  if (!nav) return;

  const entries = [...nav.querySelectorAll("a[href^='#']")]
    .map(a => ({ a, el: document.getElementById(decodeURIComponent(a.hash.slice(1))) }))
    .filter(e => e.el);
  if (!entries.length) return;

  let current;

  function activate(entry) {
    if (entry === current) return;
    current = entry;
    for (const e of entries) e.a.classList.toggle("active", e === entry);
    if (!entry) return;
    // Keep the active link visible when the index itself is scrollable.
    const nb = nav.getBoundingClientRect(), lb = entry.a.getBoundingClientRect();
    if (lb.top < nb.top + 8) nav.scrollTop -= nb.top + 8 - lb.top;
    else if (lb.bottom > nb.bottom - 8) nav.scrollTop += lb.bottom - (nb.bottom - 8);
  }

  function update() {
    const line = 140; // a section becomes "current" once its heading passes here
    let found = null;
    for (const e of entries) {
      if (e.el.getBoundingClientRect().top <= line) found = e;
      else break;
    }
    // Past the end of the page, pin the last section.
    if (window.scrollY + window.innerHeight >= document.documentElement.scrollHeight - 4) {
      found = entries[entries.length - 1];
    }
    activate(found);
  }

  let queued = false;
  function onScroll() {
    if (queued) return;
    queued = true;
    requestAnimationFrame(() => { queued = false; update(); });
  }

  addEventListener("scroll", onScroll, { passive: true });
  addEventListener("resize", onScroll);
  update();
})();
