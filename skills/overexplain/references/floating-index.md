# The floating index (sticky TOC + scrollspy)

The CSS and JS already exist as skill assets — **do not rewrite them**:

- `assets/floating-index.css` — the sticky sidebar styling and active-entry treatment
- `assets/floating-index.js` — the scrollspy
- `scripts/add-floating-index.py` — inlines both into a finished page

You write the markup; the script supplies everything else.

## 1. Write the markup

Keep the index in normal document order — first thing inside `<main>`, before the first `<h2>`. It
is only *visually* moved, so it stays in the tab order and reads fine with CSS and JS off.

```html
<nav class="toc">
  <p>On this page</p>
  <ol>
    <li><a href="#tldr">The one-paragraph version</a></li>
    <!-- one <li> per <h2 id="…"> on the page, in document order -->
  </ol>
</nav>
```

Every entry must point at an `id` that exists on an `<h2>`, and the list must be in the same order
as the headings — the scrollspy walks the list top-down and stops at the first heading below the
line.

## 2. Inject the CSS and JS

Once the page is written:

```bash
python3 ~/.claude/skills/overexplain/scripts/add-floating-index.py "{title-in-kebab-case}.html"
```

The CSS goes before the page's last `</style>`, the JS as the last `<script>` before `</body>` —
both inlined, so the page stays a single self-contained file that works from `file://` and inside a
gist. Re-running replaces the injected blocks rather than duplicating them, so it's safe to run
again after editing the page. It warns if it can't find a `<nav class="toc">`.

## 3. Check it

Load the page at ≥1300px wide and confirm two things: the sidebar doesn't overlap the text column,
and the highlight moves as you scroll.

## What the assets assume

- **Custom properties** `--card --rule --fg --muted --link --accent --code-bg` exist on the page.
  The skill's standard palette defines all of them; if you renamed any, edit the asset rather than
  hand-rolling a replacement.
- **A ~78ch centered content column.** The sidebar is 18rem in the left gutter above a 1240px
  breakpoint and an inline card below it. A wider column needs a higher breakpoint —
  content width + 2 × 20rem — changed in both media queries in the CSS asset.
- **Headings are `<h2>`.** Sub-entries for `<h3>`s work too (nest a second `<ol>`), but the flat
  `<h2>` list is the default; a 16-entry index is already near the height limit before the sidebar
  starts scrolling internally.

Scroll position is read on demand rather than cached, so late-loading Mermaid diagrams and images
reflowing the page don't desynchronise the highlight. No entry is active until the first heading
passes the line — that's intentional, the hero isn't a section.
