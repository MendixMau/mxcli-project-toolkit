// geometry.js: the layout of a rendered Mendix page as data, so the old and new app can be compared by widget instead of by pixel.
// Why: LineApp 10.24.13 -> 11.12.6 React. The Task List gallery rendered at half the page width (a Dojo table rule
// left in the theme) and converted Image widgets grew to the width of their container (auto became 100%). Every journey
// PASSed (same data, same clicks) and the screenshot compare was too noisy to be read. Widget widths do not depend on data.
//
//   const { snapshot } = require('./geometry'); const geo = await snapshot(page);   // -> { viewport, widgets: [...] }
//   writeGeometry(page, pngPath)  writes <pngPath without .png>.geo.json next to a screenshot (layoutdiff.py pairs them)
//
// Per visible element with an mx-name-* class: key (the chain of mx-name-* names from the page down, plus the index among
// siblings with the same chain, so gallery items stay apart), x, y, w, h. Per leaf text: cut = the text is wider than its
// box (scrollWidth > clientWidth + 1 with overflow not visible, or the text box itself overflows a clipping parent).
// Per <img>: rendered w x h and the image's natural size.
const fs = require('fs');

async function snapshot(page) {
  return page.evaluate(() => {
    const vis = e => { const r = e.getBoundingClientRect(); const cs = getComputedStyle(e);
      return r.width > 0 && r.height > 0 && cs.visibility !== 'hidden' && cs.display !== 'none'; };
    const nameOf = e => { const m = (e.getAttribute('class') || '').match(/(?:^|\s)mx-name-([^\s]+)/); return m ? m[1] : null; };
    const chain = e => { const a = []; for (let p = e; p && p !== document.body; p = p.parentElement) { const n = nameOf(p); if (n) a.unshift(n); } return a.join('/'); };
    const seen = {}, widgets = [];
    for (const e of document.querySelectorAll('[class*="mx-name-"]')) {
      if (!vis(e)) continue;
      const c = chain(e); seen[c] = (seen[c] || 0) + 1;
      const r = e.getBoundingClientRect();
      widgets.push({ key: c + '#' + seen[c], x: Math.round(r.x), y: Math.round(r.y), w: Math.round(r.width), h: Math.round(r.height) });
    }
    const cuts = [];
    for (const e of document.querySelectorAll('span, label, div, td, th, p, a, button, h1, h2, h3, h4')) {
      if (e.children.length || !vis(e)) continue;
      const t = (e.textContent || '').trim(); if (t.length < 2) continue;
      const cs = getComputedStyle(e);
      const clipped = cs.overflow !== 'visible' || cs.textOverflow === 'ellipsis';
      if (clipped && e.scrollWidth > e.clientWidth + 1) { cuts.push({ key: chain(e), text: t.slice(0, 60) }); continue; }
      for (let p = e.parentElement, i = 0; p && i < 4; p = p.parentElement, i++) {          // text box sticking out of a clipping parent
        const pcs = getComputedStyle(p); if (pcs.overflow === 'visible' && pcs.overflowX === 'visible') continue;
        const pr = p.getBoundingClientRect(), er = e.getBoundingClientRect();
        if (er.right > pr.right + 2 && er.left < pr.right) cuts.push({ key: chain(e), text: t.slice(0, 60) });
        break;
      }
    }
    const images = [];
    for (const i of document.querySelectorAll('img')) { if (!vis(i)) continue; const r = i.getBoundingClientRect();
      images.push({ key: chain(i), src: (i.getAttribute('src') || '').replace(/^data:.*/, 'data:').replace(/^.*\/img\//, '').replace(/\?.*$/, ''),
        w: Math.round(r.width), h: Math.round(r.height), nw: i.naturalWidth, nh: i.naturalHeight }); }
    return { viewport: { w: innerWidth, h: innerHeight }, widgets, cuts, images };
  });
}

async function writeGeometry(page, pngPath) {
  try { fs.writeFileSync(pngPath.replace(/\.png$/, '') + '.geo.json', JSON.stringify(await snapshot(page))); } catch (e) { /* a page that is gone has no layout */ }
}

module.exports = { snapshot, writeGeometry };
