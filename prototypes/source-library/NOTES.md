# Prototype: Source Library picker state model (PRD #27)

**Throwaway.** Branch: LOGIC (interactive terminal). Chosen over the UI branch
because QuickRun is a native macOS/AppKit app (the web-route UI harness doesn't
fit) and the UX shape (sidebar + checklist) was already decided in #27 — the open
risk was the *state model*, not the look.

## Run

```
swift prototypes/source-library/SourceLibraryPrototype.swift
```

Commands: `n`/`p` switch category · `1`-`9` toggle entry · `a` add selected ·
`dN` remove your-source N · `q` quit.

## Question

Does "Add from Library" feel right when driven by hand? Three decisions from
#27's Implementation Decisions:

1. Selection spans category switches (tick across categories, one Add commits all).
2. Dedup is by `urlTemplate`, not name — a renamed Source still counts as present.
3. Add mints a fresh `id` and appends; remove → re-add yields a new `id`.

## Verdict (observed this session)

All three hold up and feel right:

- **Cross-category selection** — toggled an 英文词典 entry, switched to 中文词典,
  toggled another, one `a` committed both (3 → 5 Sources). Selection surviving the
  category switch is the behaviour you want; nothing surprising.
- **Dedup by template, not name** — seed renamed 必应词典 to "必应词典 (我改的名字)";
  the catalog still showed 必应词典 as `(added)` and refused to re-select it
  (`按 urlTemplate 去重`). This is the correct call: keying on name would let a
  rename smuggle in a duplicate tab.
- **Remove → re-add → fresh id** — `d1` freed the template, the catalog entry
  flipped back to addable, and re-adding produced a new `id` (3 → 2 → 3). No id
  reuse, no clobber.

**One thing the prototype surfaced to decide for real:** dedup *silently* blocks
re-selection. That's right for "don't make accidental dupes", but a user who
*wants* a second copy at the same template (rare) has no path. Acceptable for v1
per #27 story 7 — noting it so it's a conscious choice, not an accident.

## Disposition

Lift the `SourceLibrary` enum (the portable logic block above the TUI banner) into
QuickRunKit as the real add/dedup operation — it matches #27's seam (mint fresh
`id`, append via the store, dedup by `urlTemplate`). Delete this whole directory
once that lands.
