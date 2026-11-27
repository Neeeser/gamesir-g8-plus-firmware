import SwiftUI

struct LogsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        List {
            ForEach(model.logs, id: \.1) { log, url in
                NavigationLink {
                    LogDetailView(log: log, url: url)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(log.title).font(.headline)
                        Text("\(log.date.formatted(date: .abbreviated, time: .shortened)) · \(log.firmware.isEmpty ? "firmware not set" : log.firmware)")
                            .font(.footnote).foregroundStyle(.secondary)
                        if let line = LogDetailView.headline(log) { Text(line).font(.footnote) }
                    }
                }
                .swipeActions { Button("Delete", role: .destructive) { model.delete(url) } }
            }
        }
        .overlay {
            if model.logs.isEmpty {
                ContentUnavailableView("No saved results", systemImage: "tray",
                                       description: Text("Save a controller check, a timing recording or a stick return test and it shows up here."))
            }
        }
        .navigationTitle("Logs")
        .refreshable { model.reloadLogs() }
        .toolbar {
            #if os(macOS)
            Button("Show in Finder") { NSWorkspace.shared.open(model.store.folder) }
            #endif
        }
        .onAppear { model.reloadLogs() }
    }
}

struct LogDetailView: View {
    @Environment(AppModel.self) private var model
    let log: RunLog
    let url: URL
    @State private var compareWith: UUID?

    var body: some View {
        let others = model.logs.map(\.0).filter { $0.kind == log.kind && $0.id != log.id }
        Form {
            Section {
                LabeledContent("Firmware", value: log.firmware.isEmpty ? "not set" : log.firmware)
                LabeledContent("Device", value: "\(log.device), \(log.system)")
                if let c = log.controller { LabeledContent("Controller", value: "\(c.name), \(c.category)") }
                ShareLink(item: url) { Label("Share file", systemImage: "square.and.arrow.up") }
            }
            if !others.isEmpty {
                Section("Compare") {
                    Picker("With", selection: $compareWith) {
                        Text("None").tag(UUID?.none)
                        ForEach(others) { o in Text("\(o.firmware.isEmpty ? "?" : o.firmware), \(o.date.formatted(date: .numeric, time: .shortened))").tag(Optional(o.id)) }
                    }
                    if let other = others.first(where: { $0.id == compareWith }) {
                        CompareTable(a: log, b: other)
                    }
                }
            }
            Section("Results") {
                if let line = Self.headline(log) { Text(line) }
                ForEach(log.notes, id: \.self) { Text($0) }
                DisclosureGroup("Raw file") {
                    Text(Self.text(log))
                        .font(.footnote.monospaced())
                        .textSelection(.enabled)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(log.title)
    }

    static func headline(_ log: RunLog) -> String? {
        if let t = log.timing { return String(format: "typical gap %.1f ms, longest %.1f ms", t.medianMs, t.maxMs) }
        if let l = log.leftRelease?.medianMs ?? log.rightRelease?.medianMs { return String(format: "stick return %.0f ms", l) }
        if let m = log.buttonsMissing { return m.isEmpty ? "all buttons worked" : "never pressed: \(m.map(shortName).joined(separator: ", "))" }
        return log.notes.first
    }

    static func text(_ log: RunLog) -> String {
        guard let data = try? LogStore.encoder.encode(log) else { return "" }
        return String(decoding: data, as: UTF8.self)
    }
}

/// Key numbers of two runs side by side.
struct CompareTable: View {
    let a: RunLog
    let b: RunLog

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 4) {
            GridRow { Text(""); Text(a.firmware.isEmpty ? "this" : a.firmware).bold(); Text(b.firmware.isEmpty ? "other" : b.firmware).bold() }
            ForEach(rows, id: \.0) { r in GridRow { Text(r.0).foregroundStyle(.secondary); Text(r.1); Text(r.2) } }
        }
        .font(.callout.monospacedDigit())
    }

    private var rows: [(String, String, String)] {
        func ms(_ v: Double?) -> String { v.map { String(format: "%.1f ms", $0) } ?? "-" }
        func num(_ v: Double?) -> String { v.map { String(format: "%.4f", $0) } ?? "-" }
        var out: [(String, String, String)] = []
        if a.timing != nil || b.timing != nil {
            out.append(("Per second", a.timing.map { String(format: "%.0f", $0.perSecond) } ?? "-", b.timing.map { String(format: "%.0f", $0.perSecond) } ?? "-"))
            out.append(("Typical gap", ms(a.timing?.medianMs), ms(b.timing?.medianMs)))
            out.append(("99% under", ms(a.timing?.p99Ms), ms(b.timing?.p99Ms)))
            out.append(("Longest", ms(a.timing?.maxMs), ms(b.timing?.maxMs)))
        }
        if a.leftStick != nil || b.leftStick != nil {
            out.append(("Left noise x", num(a.leftStick?.spread.x), num(b.leftStick?.spread.x)))
            out.append(("Left noise y", num(a.leftStick?.spread.y), num(b.leftStick?.spread.y)))
            out.append(("Right noise x", num(a.rightStick?.spread.x), num(b.rightStick?.spread.x)))
            out.append(("Right noise y", num(a.rightStick?.spread.y), num(b.rightStick?.spread.y)))
            out.append(("Left smallest", num(a.leftStick?.smallestNonzero), num(b.leftStick?.smallestNonzero)))
        }
        if a.leftRelease != nil || b.leftRelease != nil {
            out.append(("Left return", ms(a.leftRelease?.medianMs), ms(b.leftRelease?.medianMs)))
            out.append(("Right return", ms(a.rightRelease?.medianMs), ms(b.rightRelease?.medianMs)))
        }
        if a.buttonsMissing != nil || b.buttonsMissing != nil {
            out.append(("Never pressed", "\(a.buttonsMissing?.count ?? 0)", "\(b.buttonsMissing?.count ?? 0)"))
        }
        return out
    }
}
