# QuickRun

A macOS menu-bar tool for instant word lookup. Select text in any app, press a
global hotkey, and QuickRun pops up a panel that looks the word up across
several dictionary/search sites at once — each in its own tab.

The default sources are **必应词典**, **有道词典**, and **Google**, all editable.

## Install

```sh
brew install sunfmin/tap/quickrun
```

The app is signed with a Developer ID and notarized by Apple, so it launches
without Gatekeeper warnings.

Or grab the `.zip` from the [latest release](https://github.com/sunfmin/quickrun/releases/latest).

## Usage

1. Select a word or phrase in any app.
2. Press the hotkey — **⌥D** by default.
3. The panel opens with the selection looked up; switch tabs to compare sources.
4. Press **Esc** or click away to dismiss; focus returns to the app you were in.

- Press the hotkey **while QuickRun is frontmost** to look up a word selected
  inside the panel itself.
- The panel remembers its size and position across launches.
- The menu-bar icon (🔍) opens **Settings** — edit the hotkey and the list of
  sources — or quits the app.

### Sources

A source is just a name and a URL template with `{q}` where the query goes, e.g.

```
https://cn.bing.com/dict/search?q={q}
https://dict.youdao.com/result?word={q}&lang=en
https://www.google.com/search?q={q}
```

### Permission

QuickRun needs **Accessibility** access (System Settings → Privacy & Security →
Accessibility) to register the global hotkey and read the selected text. It
prompts on first run.

## Build from source

```sh
git clone https://github.com/sunfmin/quickrun
cd quickrun
swift build          # debug binary
swift test           # run the QuickRunKit unit tests
```

To produce a signed, notarized `.app` (installs into `/Applications` and
launches it):

```sh
# local smoke test — signed only, no notarization:
SKIP_NOTARIZE=1 ./scripts/release.sh

# full release — requires a notarytool keychain profile:
NOTARY_PROFILE=QuickRunNotary ./scripts/release.sh
```

## Architecture

- **`QuickRunKit`** — pure, testable logic: URL building, the panel state
  machine, the selection-capture chain, and the `UserDefaults`-backed stores.
- **`QuickRun`** — the AppKit / Carbon / WebKit glue: the global hotkey, the
  panel, settings, and the Accessibility reader.

See `CONTEXT.md` for the domain glossary and `docs/adr/` for design decisions.
