import WidgetKit
import SwiftUI

struct FlowEntry: TimelineEntry {
    let date: Date
    let name: String
    let usage: Usage?
    let pingMs: Int?
}

struct FlowProvider: TimelineProvider {
    func placeholder(in context: Context) -> FlowEntry {
        FlowEntry(date: Date(), name: "机场", usage: Usage(total: 161061273600, used: 13444123862, remain: 147617149738, expire: 1796745600), pingMs: 253)
    }

    func getSnapshot(in context: Context, completion: @escaping (FlowEntry) -> Void) {
        completion(placeholder(in: context))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<FlowEntry>) -> Void) {
        Task {
            let cfg = SharedStore.load()
            let result = await Net.fetchSubscription(cfg.subUrl)
            var ms: Int?
            if cfg.pingAuto {
                if let first = Net.parseNodes(result.1).first {
                    ms = await Net.tcpPing(host: first.host, port: first.port)
                }
            } else if !cfg.pingHost.isEmpty {
                ms = await Net.tcpPing(host: cfg.pingHost, port: cfg.pingPort)
            }
            let entry = FlowEntry(date: Date(), name: cfg.name.isEmpty ? "机场" : cfg.name, usage: result.0, pingMs: ms)
            let minutes = max(1, cfg.refreshMinutes)
            let next = Calendar.current.date(byAdding: .minute, value: minutes, to: Date()) ?? Date().addingTimeInterval(3600)
            completion(Timeline(entries: [entry], policy: .after(next)))
        }
    }
}

struct FlowWidgetView: View {
    var entry: FlowEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(entry.name)
                    .font(.body)
                    .foregroundStyle(.blue)
                    .lineLimit(1)
                Spacer()
                Text(entry.usage.map { "可用 \(Int($0.remain / $0.total * 100))%" } ?? "—")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text(entry.usage.map { Net.formatBytes($0.remain) } ?? "—")
                .font(.system(size: 26, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(ratioColor)

            ProgressView(value: entry.usage?.used ?? 0, total: entry.usage?.total ?? 1)
                .progressViewStyle(.linear)

            Text(subText)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            HStack {
                Spacer()
                Text(entry.pingMs.map { "\($0) ms" } ?? "— ms")
                    .font(.caption2)
                    .foregroundStyle(pingColor)
                Text(" · \(entry.date, format: .dateTime.hour().minute())")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .containerBackground(.fill.tertiary, for: .widget)
    }

    private var ratioColor: Color {
        guard let u = entry.usage, u.total > 0 else { return .secondary }
        let r = u.remain / u.total
        if r >= 0.5 { return .green }
        if r >= 0.2 { return .orange }
        return .red
    }

    private var pingColor: Color {
        guard let p = entry.pingMs else { return .secondary }
        if p < 300 { return .green }
        if p < 600 { return .orange }
        return .red
    }

    private var subText: String {
        guard let u = entry.usage else { return "读取失败，到 App 里填订阅链接" }
        return "已用 \(Net.formatBytes(u.used)) / \(Net.formatBytes(u.total)) · 到期 \(Net.formatDate(u.expire))"
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
        .description("显示剩余流量与节点延迟")
        .supportedFamilies([.systemMedium])
    }
}
