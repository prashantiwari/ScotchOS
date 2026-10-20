---
name: new-widget
description: Scaffold a new ScotchOS desktop widget (a Quickshell card on the desktop layer) wired into shell.qml and scotchos.conf. Use when the user wants a new widget, card or panel on the desktop.
---

# New ScotchOS widget

Read `CLAUDE.md` first. Use an existing widget as the template: `widgets/hourlyQuote/` is the smallest, `widgets/nowPlaying/` shows a helper process, `widgets/systemDashboard/` shows layouts and a Python collector.

## 1. Settle the design with the user

Ask only what you can't infer: what it shows, where the data comes from (API, D-Bus/MPRIS, `/proc`, a command), how often it updates, default position. Propose a conf key (lowercase), a folder (camelCase) and the settings it should have.

## 2. Files

`widgets/<folder>/`:

- `<Name>Widget.qml`: root `DesktopWidget { id: w; section: "<key>" }`, `import "../../common"`. Settings as readonly bindings (`placeSetting("…")`, `num`, `flag`, `str` with an allowed list). State and data sources. Then:

  ```qml
  Variants {
      model: Quickshell.screens
      DesktopPanel {
          layerName: "scotchos-<key>"
          visible: w.workspaceEmpty(modelData)
          place: w.place
          marginX: w.marginX
          marginY: w.marginY
          implicitWidth: card.width
          implicitHeight: card.height
          <Name>Card { id: card; shell: w }
      }
  }
  ```

- `<Name>Card.qml`: `Rectangle { id: card; required property var shell; … }` in the shared card style (see `QuoteCard.qml`).
- Helpers (scripts, conf files) next to them, referenced with `Quickshell.shellDir + "/widgets/<folder>/…"`.
- `README.md` with the sections listed in `CLAUDE.md`.

## 3. Wire it in

- `shell.qml`: `import "widgets/<folder>"` and a `LazyLoader { active: root.enabled("<key>"); <Name>Widget { core: root } }`.
- `scotchos.conf`: `<key> = yes   # one-line description` under `[enabled]`, and a `[<key>]` section with commented settings.
- `settings/SettingsWindow.qml`: an entry in `items` with its settings, so it shows in the settings window.
- Root `README.md`: a row in the table.

## 4. Verify

Follow the `check-shell` skill: no new warnings in the log, the `scotchos-<key>` layer shows on an empty workspace, a screenshot looks right in the card style, `scotchos disable <key>` removes it (and stops its processes), memory is still reasonable. Then commit.
