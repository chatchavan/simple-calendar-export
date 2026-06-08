import SwiftUI
import WebKit
import EventKit

// MARK: – CalendarListController

final class CalendarListController: NSObject, ObservableObject, WKNavigationDelegate {
    let webView: WKWebView
    private var pendingGroups: [ExportEngine.CalendarGroup]?
    private var isLoaded = false

    override init() {
        webView = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
        super.init()
        webView.navigationDelegate = self
        if let url = Self.resourceURL("calendar_list"),
           let html = try? String(contentsOf: url, encoding: .utf8) {
            webView.loadHTMLString(html, baseURL: nil)
        }
    }

    func populate(groups: [ExportEngine.CalendarGroup]) {
        if isLoaded {
            applyGroups(groups)
        } else {
            pendingGroups = groups
        }
    }

    func getChecked(completion: @escaping ([String]) -> Void) {
        webView.evaluateJavaScript("getChecked()") { result, _ in
            let checked = (result as? [Any])?.compactMap { $0 as? String } ?? []
            completion(checked)
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        isLoaded = true
        if let groups = pendingGroups {
            pendingGroups = nil
            applyGroups(groups)
        }
    }

    private func applyGroups(_ groups: [ExportEngine.CalendarGroup]) {
        guard let data = try? JSONEncoder().encode(groups),
              let json = String(data: data, encoding: .utf8) else { return }
        webView.evaluateJavaScript("setCalendars(\(json))") { _, _ in }
    }

    private static func resourceURL(_ name: String) -> URL? {
        if let u = Bundle.main.url(forResource: name, withExtension: "html") { return u }
        let execDir = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
        return execDir.appendingPathComponent("../Resources/\(name).html").standardized
    }
}

// MARK: – WKWebView wrappers

struct DatePickerWebView: NSViewRepresentable {
    @Binding var startDate: String
    @Binding var endDate: String

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.userContentController.add(context.coordinator, name: "dateRange")
        let wv = WKWebView(frame: .zero, configuration: config)
        if let url = resourceURL(),
           let html = try? String(contentsOf: url, encoding: .utf8) {
            wv.loadHTMLString(html, baseURL: nil)
        }
        return wv
    }

    func updateNSView(_ wv: WKWebView, context: Context) {}

    private func resourceURL() -> URL? {
        if let u = Bundle.main.url(forResource: "date_picker", withExtension: "html") { return u }
        let execDir = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
        return execDir.appendingPathComponent("../Resources/date_picker.html").standardized
    }

    class Coordinator: NSObject, WKScriptMessageHandler {
        var parent: DatePickerWebView
        init(_ parent: DatePickerWebView) { self.parent = parent }

        func userContentController(_ uc: WKUserContentController,
                                   didReceive message: WKScriptMessage) {
            guard message.name == "dateRange",
                  let body = message.body as? [String: Any] else { return }
            DispatchQueue.main.async {
                self.parent.startDate = body["start"] as? String ?? ""
                self.parent.endDate   = body["end"]   as? String ?? ""
            }
        }
    }
}

struct CalendarListWebView: NSViewRepresentable {
    let controller: CalendarListController
    func makeNSView(context: Context) -> WKWebView { controller.webView }
    func updateNSView(_ nsView: WKWebView, context: Context) {}
}

// MARK: – Main window

struct MainWindowView: View {
    @State private var startDate = ""
    @State private var endDate   = ""
    @StateObject private var calendarCtrl = CalendarListController()
    @State private var format: ExportFormat = .busyCalCSV
    @State private var accessError: String? = nil
    @State private var exportMessage: String? = nil
    @State private var isExporting = false

    var body: some View {
        VStack(spacing: 0) {
            // Date picker
            DatePickerWebView(startDate: $startDate, endDate: $endDate)
                .frame(minHeight: 320)

            Divider()

            // Calendar list
            if let err = accessError {
                VStack(alignment: .leading, spacing: 8) {
                    Text(err).foregroundColor(.red).font(.caption)
                    Button("Open System Settings") {
                        NSWorkspace.shared.open(
                            URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars")!)
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                CalendarListWebView(controller: calendarCtrl)
                    .frame(height: 180)
            }

            Divider()

            // Bottom bar: format radio + export
            HStack(spacing: 12) {
                Picker("", selection: $format) {
                    Text("CSV").tag(ExportFormat.busyCalCSV)
                    Text("ICS").tag(ExportFormat.ics)
                }
                .pickerStyle(.radioGroup)
                .labelsHidden()
                .fixedSize()

                Spacer()

                if let msg = exportMessage {
                    Text(msg)
                        .font(.caption)
                        .foregroundColor(msg.starts(with: "✓") ? .green : .red)
                }

                Button(action: doExport) {
                    if isExporting {
                        ProgressView().scaleEffect(0.7).frame(width: 60)
                    } else {
                        Text("Export…").frame(minWidth: 60)
                    }
                }
                .disabled(isExporting || startDate.isEmpty || endDate.isEmpty)
                .keyboardShortcut(.return, modifiers: .command)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .task { await loadCalendars() }
    }

    // MARK: – Helpers

    private func loadCalendars() async {
        do {
            try await ExportEngine.requestAccess()
            let groups = ExportEngine.calendarGroups()
            await MainActor.run {
                calendarCtrl.populate(groups: groups)
                accessError = nil
            }
        } catch {
            await MainActor.run {
                accessError = error.localizedDescription
            }
        }
    }

    private func doExport() {
        guard !startDate.isEmpty, !endDate.isEmpty else { return }
        calendarCtrl.getChecked { checked in
            performExport(checkedCalendars: checked)
        }
    }

    private func performExport(checkedCalendars: [String]) {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        guard let s = fmt.date(from: startDate), let e = fmt.date(from: endDate) else {
            exportMessage = "Invalid date range"; return
        }

        let ext = format.fileExtension
        let defaultName = "\(startDate)_\(endDate).\(ext)"

        let panel = NSSavePanel()
        panel.allowedContentTypes = format == .busyCalCSV
            ? [.commaSeparatedText]
            : [.init(filenameExtension: "ics")!]
        panel.nameFieldStringValue = defaultName
        panel.directoryURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first

        guard panel.runModal() == .OK, let url = panel.url else { return }

        isExporting = true
        exportMessage = nil

        let capturedFormat = format
        Task.detached {
            do {
                let opts = ExportEngine.Options(
                    start: s,
                    end: e,
                    calendarNames: checkedCalendars,
                    format: capturedFormat,
                    outputURL: url
                )
                try ExportEngine.export(opts)
                await MainActor.run {
                    isExporting = false
                    exportMessage = "✓ Saved to \(url.lastPathComponent)"
                }
            } catch {
                await MainActor.run {
                    isExporting = false
                    exportMessage = "Error: \(error.localizedDescription)"
                }
            }
        }
    }
}
