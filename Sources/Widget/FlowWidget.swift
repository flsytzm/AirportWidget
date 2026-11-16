import WidgetKit
import SwiftUI

struct FlowEntry: TimelineEntry {
    let date: Date
    let name: String
    let usage: Usage?
    let pingMs: Int?
    let exit: ExitInfo
}

struct FlowProvider: TimelineProvider {
    func placeholder(in context: Context) -> FlowEntry {
        FlowEntry(date: Date(),
                  name: "机场",
                  usage: Usage(total: 161061273600, used: 13444123862, remain: 147617149738, expire: 1796745600),
                  pingMs: 253,
                  exit: ExitInfo(ip: "202.214.238.85", location: "日本 · 东京"))
    }

    func getSnapshot(in context: Context, completion: @escaping (FlowEntry) -> Void) {
        completion(placeholder(in: context))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<FlowEntry>) -> Void) {
        Task {
            let cfg = SharedStore.load()
            async let sub = Net.fetchSubscription(cfg.subUrl)
            async let exit = Net.fetchExit()
            let result = await sub
            let exitInfo = await exit

            var ms: Int?
            if cfg.pingAuto {
                if let first = Net.parseNodes(result.1).first {
                    ms = await Net.tcpPing(host: first.host, port: first.port)
                }
            } else if !cfg.pingHost.isEmpty {
                ms = await Net.tcpPing(host: cfg.pingHost, port: cfg.pingPort)
            }
            let entry = FlowEntry(date: Date(),
                                  name: cfg.name.isEmpty ? "机场" : cfg.name,
                                  usage: result.0,
                                  pingMs: ms,
                                  exit: exitInfo)
            let minutes = max(1, cfg.refreshMinutes)
            let next = Calendar.current.date(byAdding: .minute, value: minutes, to: Date()) ?? Date().addingTimeInterval(3600)
            completion(Timeline(entries: [entry], policy: .after(next)))
        }
    }
}

struct FlowWidgetView: View {
    var entry: FlowEntry

    var body: some View {
        if #available(iOS 17.0, *) {
            content.containerBackground(.fill.tertiary, for: .widget)
        } else {
            content.background(Color(uiColor: .systemBackground))
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(entry.name)
                    .font(.subheadline.bold())
                    .foregroundStyle(.blue)
                    .lineLimit(1)
                Spacer()
                Text(entry.usage.map { "可用 \(Int($0.remain / $0.total * 100))%" } ?? "—")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(entry.usage.map { Net.formatBytes($0.remain) } ?? "—")
                    .font(.system(size: 24, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(ratioColor)
                Text("剩余")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            ProgressView(value: entry.usage?.used ?? 0, total: entry.usage?.total ?? 1)
                .progressViewStyle(.linear)
                .tint(ratioColor)

            HStack(spacing: 5) {
                Text(entry.exit.ok ? "IP \(entry.exit.ip)" : "IP —")
                    .font(.system(size: 12, weight: .semibold))
                    .monospacedDigit()
                Text(entry.exit.location)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
            }

            HStack {
                Text("延迟")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(entry.pingMs.map { "\($0) ms" } ?? "— ms")
                    .font(.system(size: 13, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(pingColor)
                Spacer()
                Text("\(entry.date, format: .dateTime.hour().minute())")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 16)
    }

    private var ratioColor: Color {
        guard let u = entry.usage, u.total > 0 else { return .gray }
        let r = u.remain / u.total
        if r >= 0.5 { return .green }
        if r >= 0.2 { return .orange }
        return .red
    }

    private var pingColor: Color {
        guard let p = entry.pingMs else { return .gray }
        if p < 300 { return .green }
        if p < 600 { return .orange }
        return .red
    }
}

@main
struct AirportWidgetBundle: WidgetBundle {
    var body: some Widget {
        AirportFlowWidget()
    }
}

struct AirportFlowWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "AirportFlowWidget", provider: FlowProvider()) { entry in
            FlowWidgetView(entry: entry)
        }
        .configurationDisplayName("机场流量")
        .description("剩余流量、出口 IP、节点延迟")
        .supportedFamilies([.systemMedium])
    }
}
