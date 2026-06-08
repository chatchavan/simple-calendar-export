# calendar-export-app

A macOS .app bundle (no Xcode) that exports Apple Calendar events as BusyCal CSV or ICS. GUI + CLI in one binary.

## How to build

```bash
bash build.sh   # creates ~/Applications/Simple Calendar Export.app
```

The script hashes `Sources/*.swift` and skips compile + codesign when sources are unchanged. This preserves the macOS TCC permission entry — re-signing invalidates it and requires the user to re-grant Full Access.

## Architecture

| File | Role |
|---|---|
| `Sources/main.swift` | Entry point: CLI mode if `--list/--start/--end/--format/--output` present, else GUI |
| `Sources/AppDelegate.swift` | NSWindow (fixed 530 px width), menu bar (File/Edit/Window), `windowWillResize` delegate |
| `Sources/MainWindowView.swift` | SwiftUI layout; `DatePickerWebView` and `CalendarListController`/`CalendarListWebView` wrappers |
| `Sources/ExportEngine.swift` | EventKit access, `calendarGroups()`, BusyCal CSV, ICS |
| `Sources/CLIRunner.swift` | Headless export; shares `ExportEngine` with the GUI |
| `Resources/date_picker.html` | Self-contained HTML/JS two-month date-range picker |
| `Resources/calendar_list.html` | Self-contained HTML/JS calendar checkboxes, grouped by account |

## Key design decisions

- **No Xcode project** — compiled with `swiftc` in `build.sh`. All frameworks linked with `-framework` flags.
- **WKWebView loaded via `loadHTMLString`** (not `loadFileURL`) to avoid macOS prompting for Documents/filesystem access.
- **Calendar list is HTML** — makes it easy to style and add interactivity (select all/none, grouping). Swift populates it via `evaluateJavaScript("setCalendars(...)")` after the page loads; reads back state at export time via `evaluateJavaScript("getChecked()")`.
- **Fixed window width** enforced in `windowWillResize` delegate (not via `minSize`/`maxSize`, which proved insufficient).
- **BusyCal CSV format** — 31-column header matching `week-planner/js/app.js` `CSV_HEADER` so exports can be loaded directly into the week-planner tool.

## TCC (Calendar permission)

- Bundle ID: `local.calendar-export-gui`
- Each codesign creates a new TCC entry. After any build that re-signs, the user must re-grant Full Access in System Settings → Privacy & Security → Calendars.
- CLI users also need Terminal → Full Access in the same panel.

## Account grouping order

`calendarGroups()` in `ExportEngine.swift` orders: `EKSourceType.local` ("On My Mac") → iCloud (`calDAV` source titled "iCloud") → all others alphabetically by account title.

## Syncing with week-planner

`app.js` and `style.css` in `week-planner/` are copies of the root repo files. `ExportEngine.swift`'s CSV output matches the same 31-column BusyCal format. If the CSV header in `week-planner/js/app.js` changes, update `CSV_HEADER` in `ExportEngine.swift` to match.
