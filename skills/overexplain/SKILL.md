---
name: overexplain
description: >
  Produce a human-friendly, over-explained walkthrough of a codebase target (a feature, file,
  flow, concept, service, endpoint, bug, PR) and publish it as a standalone HTML page, uploaded
  as a secret gist and opened via a shareable gistpreview link. Assumes the reader knows nothing
  about the codebase or its domain. Use only when the user explicitly invokes /overexplain.
---

# /overexplain

The user gives you a `{target}` — a feature name, file, class, GraphQL field, ticket, error
message, or a vague "how does billing work". Your job: research it across the datacenters repos,
then write a page a smart newcomer could read cold and come away actually understanding it.

## 1. Locate the code

The relevant code may live in any repo under `~/c/datacenters`:

- `datacenters/` — Rails monolith, GraphQL API, models, policies, jobs, mailers
- `datacenters-ui-kit/` — shared React/TS component + GraphQL monorepo
- `datacenters-frontend/` — Next.js public site / vertical sites
- `datacenters-crm/` — CRM frontend
- `datacenters-ai/` — AI services
- `datacenters2/`, `docs/`, `QA/` — secondary

Pick one or more repos **before** investigating; say which and why in one line. If the target
obviously spans front and back end, take both. Use Explore/general-purpose agents in parallel
when the search is broad — you want the conclusion, not file dumps.

Read enough real code to be correct. Never describe behavior you have not seen in the source.
Cite `path/to/file.rb:42` for every non-obvious claim.

## 2. Write the explanation

**Priority: comprehension and clarity, NOT information density.** This is the whole point of the
skill. Do not write reference documentation. Write the thing you'd say out loud to a new hire at
a whiteboard.

Rules:

- Assume zero knowledge of the codebase **and** of the business domain. Datacenters.com is a
  marketplace for data center colocation/bandwidth — over-explain domain nouns (what a "quote"
  is, what "colo" means, what a "provider" vs "listing" vs "campus" is, what the sales pipeline
  stages mean) the first time each appears.
- Lead with the one-paragraph "what is this and why does it exist" before any mechanism.
- Then the mental model / big picture, then the walkthrough, then the details.
- Prefer concrete narrated examples ("a user clicks Request Quote, and here's what happens…")
  over abstract description.
- Short paragraphs. Plenty of headings. It's fine to repeat yourself for clarity.
- Explain jargon inline the first time: acronyms, framework magic, patterns, gem/library names.
- Include small, trimmed code excerpts — only the lines that matter, with a plain-English
  sentence above each explaining what it does.
- Call out the surprising bits: gotchas, legacy quirks, "you'd expect X but it's actually Y".
- End with "where to look next" — the 3–5 files that matter most, and open questions you
  couldn't resolve.
- Diagrams (Mermaid or simple inline SVG/HTML) whenever a flow, sequence, or hierarchy is
  involved. A picture beats three paragraphs.

### Link everything

**Every reference to something that lives at a URL must be a real `<a href>` in the HTML.** A
newcomer reading this page should be able to click straight through to the source of any claim.
Link, at minimum:

- **Code** — every `path/to/file.rb:42` citation becomes a link to that file and line on GitHub,
  pinned to the commit/branch you actually read (`https://github.com/datacenterscom/{repo}/blob/{sha}/{path}#L42`,
  or `#L42-L58` for a range). Get the sha with `git rev-parse HEAD` in the repo you read, and the
  repo/owner from `git remote -v` rather than assuming.
- **Pull requests** — `https://github.com/datacenterscom/{repo}/pull/{number}`, with the PR title
  as the link text where you know it.
- **Commits** — every sha you mention (from `git log`/`git blame`) links to
  `https://github.com/datacenterscom/{repo}/commit/{sha}`; show the short sha as link text.
- **Shortcut stories** — any `sc-12345` / `[sc-12345]` reference found in branch names, commit
  messages, or PR titles links to `https://app.shortcut.com/datacenterscom/story/12345`.
- **Issues, docs, dashboards** — GitHub issues, gem/npm package pages, framework and library docs
  for anything you name, and any internal doc or dashboard URL you come across.

Rules: link text is human-readable (the file path, the PR title, the story id), never a bare
"here" or a raw URL dumped mid-sentence. Add `target="_blank" rel="noopener"` so clicks don't
lose the page. Never invent a URL — if you can't verify the number or sha, mention the thing
without a link rather than guessing. When the same thing appears many times, linking the first
occurrence per section is enough.

### Tell a story when there is one

Wherever the target admits it, **ground the explanation in a narrative** rather than a list of
facts. Code exists because somebody needed something; find that somebody and start there.

Pick the story shape that fits:

- **A person with a problem** — "Maria runs a mid-size hosting company. She needs 40kW in
  Ashburn by Q3. She lands on the site and…" Follow her request all the way through the system:
  the click, the mutation, the record it writes, the email that fires, the salesperson who
  picks it up. Every layer you touch gets explained at the moment it enters her story.
- **A change over time** — for a PR, commit range, refactor, or migration: what the world
  looked like before, what hurt, what was tried, what it looks like now, and what's still
  half-migrated. Use `git log`/`git blame` to recover the actual history rather than guessing.
- **A bug's life** — for a defect: the symptom someone saw, the misleading first theory, the
  real mechanism, the fix, and the class of bug it belongs to.
- **An archaeology story** — for legacy code: why a reasonable team made this choice with the
  constraints they had, and what changed since. Be generous, never smug, about past decisions.

Rules for the storytelling:

- The story is a *vehicle for the code*, not decoration. Every beat should hand off to a real
  file, function, or record. If a paragraph of narrative teaches nothing about the system, cut it.
- Keep invented details minimal and plausible — names, numbers, and scenarios are fine; invented
  *behavior* is not. Anything the system actually does must come from the source.
- Mark clearly when you shift from story to mechanism, so nobody mistakes the illustrative
  customer for a real one.
- If the target genuinely has no story — a pure utility module, a config file, a type
  definition — skip it. A forced narrative is worse than none. Say what it does and move on.

## 3. Publish as HTML

Derive a `Title` for the page, then write it to `{title-in-kebab-case}.html` in the current
working directory.

Requirements for the HTML file:

- Single self-contained file. No build step, no local asset dependencies. CDN links are fine
  (e.g. Mermaid from a CDN for diagrams).
- Readable typography: max content width ~70–80ch, generous line-height (1.6+), system font
  stack, real font sizes (17–18px body).
- Light/dark respecting `prefers-color-scheme`.
- Syntax-highlighted code blocks (highlight.js from CDN is fine), with the file path shown
  above each block **as a GitHub link to those exact lines** (see "Link everything").
- Links visibly styled as links (underline or distinct color) in both light and dark mode.
- **A floating sticky index**, always: fixed in the left gutter on wide screens, scrolling
  independently when taller than the viewport, collapsing to an inline card on narrow ones, with
  the entry for the section currently being scrolled through highlighted. **The styling and the
  scrollspy are prewritten skill assets — never author them yourself.** Write only the
  `<nav class="toc">` markup (one `<li>` per `<h2>`, in document order), then inline the rest with
  `python3 ~/.claude/skills/overexplain/scripts/add-floating-index.py "{title-in-kebab-case}.html"`
  once the page is otherwise finished, and before the gist upload. See
  `references/floating-index.md` for the markup shape and what the assets assume.
- Every section the index links to needs a stable `id` on its `<h2>`, so deep links like
  `…#identity` work and the highlight has something to anchor to.
- Callout boxes for "Domain concept", "Gotcha", and "Why it's like this".
- Nothing that requires a server — it must work from `file://`.

Consult the `frontend-design` skill if you want a stronger visual result, and the `dataviz`
skill if the explanation contains charts.

## 4. Publish to a secret gist

Upload the finished HTML as a **secret** gist so it can be shared and rendered:

```bash
gh gist create --secret --desc "{Title} — overexplained" "{title-in-kebab-case}.html"
```

`gh gist create` prints the gist URL; the `{GIST_ID}` is the last path segment
(`https://gist.github.com/{user}/{GIST_ID}`). Capture it — don't guess it.

Internal source code in the page is fine — upload it. The **only** reason to skip this step is
if the HTML contains a live credential value: an API key, token, password, private key, or
connection string with real secrets in it. Variable names, key *names*, `ENV['STRIPE_KEY']`
references, and placeholder/example values are not secrets — those upload normally.

If you do find a real credential, don't upload. Strip it from the HTML and upload the cleaned
version, or if it's load-bearing to the explanation, skip the gist, tell the user exactly which
value stopped you, and open the local file instead:

```bash
open "{title-in-kebab-case}.html"
```

## 5. Open the shareable preview

gistpreview renders the gist's HTML instead of showing it as source. Open that, **not** the
local file:

```bash
open "https://gistpreview.github.io/?{GIST_ID}"
```

If the gist holds more than one file, or the file isn't named `index.html` and gistpreview
doesn't pick it up, append the filename: `https://gistpreview.github.io/?{GIST_ID}/{filename}.html`.
Verify the URL actually renders before handing it over.

Then tell the user, in 2–3 lines: which repo(s) you read, the local file path, the gistpreview
link, and the single most important thing they should know about the target. Don't restate the
document.
