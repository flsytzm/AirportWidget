import WidgetKit
import SwiftUI

struct FlowEntry: TimelineEntry {
    let date: Date
    let targetName: String
    let usage: Usage?
    let pingMs: Int?
    let exit: ExitInfo
}

struct FlowProvider: TimelineProvider {
    func placeholder(in context: Context) -> FlowEntry {
        FlowEntry(date: Date(),
                  targetName: "YouTube",
                  usage: Usage(total: 161061273600, used: 13444123862, remain: 147617149738, expire: 1796745600),
                  pingMs: 253,
                  exit: ExitInfo(ip: "212.107.30.199", location: "United States · Missouri · Kansas City"))
    }

    func getSnapshot(in context: Context, completion: @escaping (FlowEntry) -> Void) {
        completion(placeholder(in: context))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<FlowEntry>) -> Void) {
        Task {
            let cfg = SharedStore.load()
            let targetName = cfg.targetName.isEmpty ? (cfg.name.isEmpty ? "YouTube" : cfg.name) : cfg.targetName
            let targetUrl = cfg.targetUrl.isEmpty ? "www.youtube.com" : cfg.targetUrl

            async let exitTask = Net.fetchExit()
            async let subTask = Net.fetchSubscription(cfg.subUrl)

            var ms: Int?
            ms = await Net.httpPing(targetUrl)

            let exitInfo = await exitTask
            let sub = await subTask

            if ms == nil {
                if cfg.pingAuto {
                    if let first = Net.parseNodes(sub.1).first {
                        ms = await Net.tcpPing(host: first.host, port: first.port)
                    }
                } else if !cfg.pingHost.isEmpty {
                    ms = await Net.tcpPing(host: cfg.pingHost, port: cfg.pingPort)
                }
            }

            let entry = FlowEntry(date: Date(),
                                  targetName: targetName,
                                  usage: sub.0,
                                  pingMs: ms,
                                  exit: exitInfo)
            let minutes = max(15, max(1, cfg.refreshSeconds) / 60)
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
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(entry.targetName)
                    .font(.subheadline.bold())
                    .foregroundStyle(.blue)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text(entry.exit.ok ? entry.exit.ip : "IP —")
                    .font(.system(size: 11, weight: .semibold))
                    .monospacedDigit()
                    .lineLimit(1)
            }

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(entry.pingMs.map { "\($0)" } ?? "—")
                    .font(.system(size: 26, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(pingColor)
                Text("ms")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Text(entry.date, format: .dateTime.hour().minute())
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Text(entry.exit.location.isEmpty ? "归属地 —" : entry.exit.location)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)

            if let u = entry.usage, u.total > 0 {
                HStack(spacing: 6) {
                    ProgressView(value: u.used, total: u.total)
                        .progressViewStyle(.linear)
                        .tint(ratioColor)
                    Text("剩 " + Net.formatBytes(u.remain))
                        .font(.caption2)
                        .monospacedDigit()
                        .foregroundStyle(ratioColor)
                        .lineLimit(1)
                }
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
        .configurationDisplayName("代理 IP 监测")
        .description("出口 IP、归属地、目标延迟")
        .supportedFamilies([.systemMedium])
    }
}
