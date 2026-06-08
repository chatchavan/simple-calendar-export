import EventKit
import Foundation

struct CLIRunner {
    func run() {
        let args = Array(CommandLine.arguments.dropFirst())

        // Parse flags
        var listMode = false
        var startStr: String? = nil
        var endStr: String? = nil
        var outputPath: String? = nil
        var formatStr = "csv"
        var calendarNames: [String] = []

        var i = 0
        while i < args.count {
            switch args[i] {
            case "--list":
                listMode = true
            case "--start" where i + 1 < args.count:
                i += 1; startStr = args[i]
            case "--end" where i + 1 < args.count:
                i += 1; endStr = args[i]
            case "--output" where i + 1 < args.count:
                i += 1; outputPath = args[i]
            case "--format" where i + 1 < args.count:
                i += 1; formatStr = args[i]
            default:
                if !args[i].hasPrefix("--") { calendarNames.append(args[i]) }
            }
            i += 1
        }

        // Request access synchronously
        let store = EKEventStore()
        let sema = DispatchSemaphore(value: 0)
        store.requestFullAccessToEvents { _, _ in sema.signal() }
        sema.wait()

        let status = EKEventStore.authorizationStatus(for: .event)
        if status != .fullAccess {
            fputs("Calendar access not granted (status=\(status.rawValue)).\n", stderr)
            fputs("Fix: System Settings → Privacy & Security → Calendars\n", stderr)
        fputs("  • CalendarExportGUI → Full Access\n", stderr)
        fputs("  • Terminal → Full Access\n", stderr)
            exit(1)
        }

        if listMode {
            let names = ExportEngine.calendarNames()
            print(names.joined(separator: "\n"))
            return
        }

        // Date parsing
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"

        guard let startStr, let endStr else {
            fputs("Usage: CalendarExportGUI --start YYYY-MM-DD --end YYYY-MM-DD [--format csv|ics] [--output PATH] [cal1 ...]\n", stderr)
            exit(1)
        }
        guard let start = fmt.date(from: startStr) else {
            fputs("ERROR: --start must be YYYY-MM-DD, got: \(startStr)\n", stderr); exit(1)
        }
        guard let end = fmt.date(from: endStr) else {
            fputs("ERROR: --end must be YYYY-MM-DD, got: \(endStr)\n", stderr); exit(1)
        }
        guard start <= end else {
            fputs("ERROR: --start must not be after --end\n", stderr); exit(1)
        }

        let format: ExportFormat = formatStr == "ics" ? .ics : .busyCalCSV
        let ext = format.fileExtension
        let defaultName = "\(startStr)_\(endStr).\(ext)"
        let downloadsDir = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!
        let outputURL: URL
        if let op = outputPath {
            outputURL = URL(fileURLWithPath: (op as NSString).expandingTildeInPath)
        } else {
            outputURL = downloadsDir.appendingPathComponent(defaultName)
        }

        do {
            let opts = ExportEngine.Options(
                start: start,
                end: end,
                calendarNames: calendarNames,
                format: format,
                outputURL: outputURL
            )
            try ExportEngine.export(opts)
            print("Exported to: \(outputURL.path)")
        } catch {
            fputs("ERROR: \(error.localizedDescription)\n", stderr)
            exit(1)
        }
    }
}
