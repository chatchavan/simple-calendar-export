# CalendarExportGUI

A macOS app for exporting Apple Calendar events to **BusyCal-compatible CSV** or **ICS** for a user-selected date range. Ships as both a GUI app and a command-line tool in one `.app` bundle.

## Setup

```bash
bash build.sh
```

This compiles the app, creates `~/Applications/CalendarExportGUI.app`, and installs the icon. On first launch macOS will ask for Calendar access — grant **Full Access** in System Settings → Privacy & Security → Calendars.

If using the CLI from Terminal, also grant Terminal **Full Access** in the same panel.

## GUI

Open the app from `~/Applications/` or Spotlight.

- **Date picker** — click to set start/end, drag for a range, or type `YYYY-MM-DD` in the fields
- **Calendar list** — grouped by account; use Select All / None for quick bulk changes
- **Format** — choose CSV (BusyCal-compatible) or ICS
- **Export…** — opens a save panel, defaulting to `~/Downloads/<start>_<end>.<ext>`

## CLI

```
CalendarExportGUI [options] [calendar1 calendar2 ...]

Options:
  --list                  List available calendar names
  --start YYYY-MM-DD      Start date (inclusive)
  --end   YYYY-MM-DD      End date (inclusive)
  --format csv|ics        Export format (default: csv)
  --output PATH           Output file path (default: ~/Downloads/<start>_<end>.<ext>)
```

Examples:

```bash
~/Applications/CalendarExportGUI.app/Contents/MacOS/CalendarExportGUI --list

~/Applications/CalendarExportGUI.app/Contents/MacOS/CalendarExportGUI \
  --start 2026-06-01 --end 2026-06-07 --format ics
```

## CSV format

Exports in BusyCal's 31-column CSV format — compatible with `parse_busycal_csv.js` in the `week-planner` tool. Key columns: `Title`, `Start Date` (DD.MM.YYYY), `Start Time` (HH:MM 24 h), `Calendar`.

## Project structure

```
Sources/
  main.swift               CLI/GUI mode detection
  AppDelegate.swift        NSWindow setup, menu bar
  MainWindowView.swift     SwiftUI layout, WKWebView wrappers, CalendarListController
  ExportEngine.swift       EventKit access, BusyCal CSV and ICS generation
  CLIRunner.swift          Headless CLI argument handling
Resources/
  date_picker.html         Two-month HTML/JS date-range picker
  calendar_list.html       Account-grouped calendar checkboxes
Design/
  1x/Artboard 1.png        1024×1024 app icon source
build.sh                   Compile, bundle, codesign, icon
```

## Rebuild notes

`build.sh` hashes the Swift sources and skips compile + codesign when nothing changed (preserving the TCC permission entry). HTML-only edits are always synced without re-signing.

---

*Built with [Claude Code](https://claude.ai/code)*
