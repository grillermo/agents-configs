#!/usr/bin/env python3
"""Inline the floating-index CSS and scrollspy JS into an overexplain page.

Usage: add-floating-index.py path/to/page.html

Inserts the CSS before the last </style> in <head> (or adds a <style> block if the
page has none) and the JS as the last <script> before </body>. Self-contained: the
page keeps working from file:// and inside a gist. Idempotent — running it twice
replaces the previously injected blocks instead of duplicating them.
"""

import re
import sys
from pathlib import Path

ASSETS = Path(__file__).resolve().parent.parent / "assets"
START, END = "/* == floating-index (skill asset) == */", "/* == /floating-index == */"
JS_START, JS_END = "<!-- floating-index (skill asset) -->", "<!-- /floating-index -->"


def strip_previous(html: str) -> str:
    html = re.sub(re.escape(START) + r".*?" + re.escape(END), "", html, flags=re.S)
    return re.sub(re.escape(JS_START) + r".*?" + re.escape(JS_END), "", html, flags=re.S)


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: add-floating-index.py path/to/page.html", file=sys.stderr)
        return 2

    page = Path(sys.argv[1])
    html = strip_previous(page.read_text(encoding="utf-8"))
    css = (ASSETS / "floating-index.css").read_text(encoding="utf-8").rstrip()
    js = (ASSETS / "floating-index.js").read_text(encoding="utf-8").rstrip()

    block = f"{START}\n{css}\n{END}\n"
    if "</style>" in html:
        head, sep, tail = html.rpartition("</style>")
        html = head + block + sep + tail
    elif "</head>" in html:
        html = html.replace("</head>", f"<style>\n{block}</style>\n</head>", 1)
    else:
        print(f"{page}: no </style> or </head> to inject CSS into", file=sys.stderr)
        return 1

    script = f"{JS_START}\n<script>\n{js}\n</script>\n{JS_END}\n"
    if "</body>" not in html:
        print(f"{page}: no </body> to inject the scrollspy before", file=sys.stderr)
        return 1
    html = html.replace("</body>", script + "</body>", 1)

    page.write_text(html, encoding="utf-8")
    print(f"{page}: floating index injected ({len(css)} B CSS, {len(js)} B JS)")

    if not re.search(r"<nav[^>]*class=[\"'][^\"']*\btoc\b", html):
        print("warning: no <nav class=\"toc\"> found — add the markup from "
              "references/floating-index.md or the index won't render", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
