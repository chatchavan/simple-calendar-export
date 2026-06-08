import EventKit
import Foundation

// Shared between GUI and CLI
final class ExportEngine {

    // MARK: – Authorization

    static func requestAccess() async throws {
        let store = EKEventStore()
        let granted = try await store.requestFullAccessToEvents()
        guard granted else {
            throw ExportError.accessDenied
        }
    }

    // MARK: – Calendar list

    struct CalendarGroup: Encodable {
        let accountName: String
        let calendars: [String]
    }

    static func calendarNames() -> [String] {
        let store = EKEventStore()
        return store.calendars(for: .event).map { $0.title }.sorted()
    }

    /// Returns calendars grouped by account, ordered: On My Mac → iCloud → others (alphabetical).
    static func calendarGroups() -> [CalendarGroup] {
        let store = EKEventStore()
        var buckets: [String: (order: Int, cals: [String])] = [:]

        for cal in store.calendars(for: .event) {
            guard let src = cal.source else { continue }
            let name: String
            let order: Int
            switch src.sourceType {
            case .local:
                name = "On My Mac"; order = 0
            case .calDAV where src.title.caseInsensitiveCompare("iCloud") == .orderedSame:
                name = "iCloud"; order = 1
            default:
                name = src.title; order = 2
            }
            if buckets[name] == nil { buckets[name] = (order, []) }
            buckets[name]!.cals.append(cal.title)
        }

        return buckets
            .map { (key, val) in (name: key, order: val.order, cals: val.cals.sorted()) }
            .sorted { a, b in a.order != b.order ? a.order < b.order : a.name < b.name }
            .map { CalendarGroup(accountName: $0.name, calendars: $0.cals) }
    }

    // MARK: – Export

    struct Options {
        var start: Date
        var end: Date
        var calendarNames: [String]   // empty = all
        var format: ExportFormat
        var outputURL: URL
    }

    static func export(_ options: Options) throws {
        let store = EKEventStore()

        let allCals = store.calendars(for: .event)
        let targetCals: [EKCalendar]
        if options.calendarNames.isEmpty {
            targetCals = allCals
        } else {
            targetCals = options.calendarNames.compactMap { name in
                allCals.first { $0.title == name }
            }
        }

        let endOfDay = options.end.addingTimeInterval(86399)
        let pred = store.predicateForEvents(withStart: options.start, end: endOfDay, calendars: targetCals)
        let events = store.events(matching: pred)
            .filter { !$0.isAllDay } // BusyCal CSV focus on timed events; ICS includes all-day
            .sorted { $0.startDate < $1.startDate }

        let content: String
        switch options.format {
        case .busyCalCSV:
            content = buildBusyCalCSV(events: events)
        case .ics:
            content = buildICS(events: events)
        }

        try content.write(to: options.outputURL, atomically: true, encoding: .utf8)
    }

    // MARK: – BusyCal CSV

    private static let CSV_HEADER = "Type,Title,All Day,Start Date,Start Time,End Date,End Time,Due Date,Duration,Is Done,Completion Time,Busy,Priority,Is Starred,Travel Time,Time Zone,Calendar,Location,Location URL,URL,My URL,Tags,My Tags,Attendees,My Status,Notes,My Notes,Recurrence,Sequence Number,Created,Modified,Modified By"

    private static func buildBusyCalCSV(events: [EKEvent]) -> String {
        var rows = [CSV_HEADER]
        let tz = TimeZone.current
        let tzDisplay = tzDisplayName(tz)

        for ev in events {
            let startDate = ev.startDate!
            let endDate   = ev.endDate!
            let duration  = endDate.timeIntervalSince(startDate)

            let row = [
                "Event",
                ev.title ?? "",
                "0",
                formatDMY(startDate),
                formatHHMM(startDate),
                formatDMY(endDate),
                formatHHMM(endDate),
                "",            // Due Date
                formatDuration(duration),
                "",            // Is Done
                "",            // Completion Time
                "1",           // Busy
                "",            // Priority
                "",            // Is Starred
                "",            // Travel Time
                tzDisplay,
                ev.calendar?.title ?? "",
                ev.location ?? "",
                "",            // Location URL
                ev.url?.absoluteString ?? "",
                "",            // My URL
                "",            // Tags
                "",            // My Tags
                "",            // Attendees
                "",            // My Status
                ev.notes ?? "",
                "",            // My Notes
                "",            // Recurrence
                "",            // Sequence Number
                ev.creationDate.map { formatCreated($0) } ?? "",
                ev.lastModifiedDate.map { formatCreated($0) } ?? "",
                "",            // Modified By
            ].map { escapeCSV($0) }.joined(separator: ",")
            rows.append(row)
        }
        return rows.joined(separator: "\n") + "\n"
    }

    // MARK: – ICS

    private static func buildICS(events: [EKEvent]) -> String {
        var lines = [
            "BEGIN:VCALENDAR",
            "VERSION:2.0",
            "PRODID:-//CalendarExportGUI//EN",
            "CALSCALE:GREGORIAN",
        ]
        for ev in events {
            lines += buildVEVENT(ev)
        }
        lines.append("END:VCALENDAR")
        return lines.joined(separator: "\r\n") + "\r\n"
    }

    private static func buildVEVENT(_ ev: EKEvent) -> [String] {
        var lines = ["BEGIN:VEVENT"]
        lines.append("UID:\(ev.calendarItemIdentifier)")
        lines.append("SUMMARY:\(icsEscape(ev.title ?? ""))")
        if ev.isAllDay {
            lines.append("DTSTART;VALUE=DATE:\(formatYMD(ev.startDate))")
            lines.append("DTEND;VALUE=DATE:\(formatYMD(ev.endDate))")
        } else {
            let tzId = TimeZone.current.identifier
            lines.append("DTSTART;TZID=\(tzId):\(formatDTSTAMP(ev.startDate))")
            lines.append("DTEND;TZID=\(tzId):\(formatDTSTAMP(ev.endDate))")
        }
        if let notes = ev.notes, !notes.isEmpty {
            lines.append("DESCRIPTION:\(icsEscape(notes))")
        }
        if let url = ev.url {
            lines.append("URL:\(url.absoluteString)")
        }
        lines.append("END:VEVENT")
        return lines
    }

    // MARK: – Formatters

    private static func formatDMY(_ d: Date) -> String {
        let c = Calendar.current.dateComponents([.day, .month, .year], from: d)
        return String(format: "%02d.%02d.%04d", c.day!, c.month!, c.year!)
    }

    private static func formatHHMM(_ d: Date) -> String {
        let c = Calendar.current.dateComponents([.hour, .minute], from: d)
        return String(format: "%02d:%02d", c.hour!, c.minute!)
    }

    private static func formatDuration(_ seconds: TimeInterval) -> String {
        let h = Int(seconds) / 3600
        let m = (Int(seconds) % 3600) / 60
        return String(format: "%02d:%02d", h, m)
    }

    private static func formatCreated(_ d: Date) -> String {
        let c = Calendar.current.dateComponents([.day, .month, .year, .hour, .minute], from: d)
        return String(format: "%02d.%02d.%04d, %02d:%02d", c.day!, c.month!, c.year!, c.hour!, c.minute!)
    }

    private static func formatYMD(_ d: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: d)
        return String(format: "%04d%02d%02d", c.year!, c.month!, c.day!)
    }

    private static func formatDTSTAMP(_ d: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: d)
        return String(format: "%04d%02d%02dT%02d%02d%02d", c.year!, c.month!, c.day!, c.hour!, c.minute!, c.second!)
    }

    private static func tzDisplayName(_ tz: TimeZone) -> String {
        let city = tz.identifier.split(separator: "/").last.map(String.init) ?? tz.identifier
        let name = tz.localizedName(for: .standard, locale: .current) ?? tz.identifier
        return "\(city), \(name)"
    }

    private static func escapeCSV(_ val: String) -> String {
        let s = val
        if s.contains(",") || s.contains("\"") || s.contains("\n") || s.contains("\r") {
            return "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return s
    }

    private static func icsEscape(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\")
         .replacingOccurrences(of: ";", with: "\\;")
         .replacingOccurrences(of: ",", with: "\\,")
         .replacingOccurrences(of: "\n", with: "\\n")
    }
}

enum ExportFormat: String {
    case busyCalCSV = "csv"
    case ics = "ics"

    var fileExtension: String { rawValue }
}

enum ExportError: LocalizedError {
    case accessDenied

    var errorDescription: String? {
        switch self {
        case .accessDenied:
            return "Calendar access was denied.\n\nGo to System Settings → Privacy & Security → Calendars and set:\n• CalendarExportGUI → Full Access\n• Terminal → Full Access (if using the CLI)"
        }
    }
}
