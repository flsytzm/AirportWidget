import SwiftUI
import WidgetKit

@main
struct AirportWidgetApp: App {
    var body: some Scene {
        WindowGroup {
            SettingsView()
        }
    }
}

struct SettingsView: View {
    @State private var cfg = SharedStore.load()
    @State private var usage: Usage?
    @State private var pingMs: Int?
    @State private var pingTarget: String = ""
    @State private var status: String = ""
    @State private var busy = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("显示名称", text: $cfg.name)
                        .textInputAutocapitalization(.never)
                    TextField("订阅链接", text: $cfg.subUrl)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                }

                Section {
                    Stepper("刷新间隔：\(cfg.refreshMinutes) 分钟", value: $cfg.refreshMinutes, in: 15...720, step: 15)
                }

                Section("测速目标") {
                    Toggle("自动选取订阅内节点", isOn: $cfg.pingAuto)
                    if !cfg.pingAuto {
                        TextField("节点地址", text: $cfg.pingHost)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        TextField("端口", value: $cfg.pingPort, format: .number)
                            .keyboardType(.numberPad)
                    }
                }

                Section("当前数据") {
                    row("剩余流量", usage.map { Net.formatBytes($0.remain) } ?? "—")
                    row("已用 / 总量", usage.map { "\(Net.formatBytes($0.used)) / \(Net.formatBytes($0.total))" } ?? "—")
                    row("到期", usage.map { Net.formatDate($0.expire) } ?? "—")
                    row("节点延迟", pingMs.map { "\($0) ms" } ?? "—")
                }

                Section {
                    Button("保存并刷新小组件") { Task { await saveAndRefresh() } }
                        .disabled(busy)
                    Button("立即测一次") { Task { await probe() } }
                        .disabled(busy)
                } footer: {
                    Text(status.isEmpty ? "就绪" : status)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("机场流量")
            .onAppear {
                Task { await probe() }
            }
        }
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title).foregroundStyle(.secondary)
            Spacer()
            Text(value)
        }
    }

    private func saveAndRefresh() async {
        busy = true
        cfg.subUrl = Net.clean(cfg.subUrl)
        cfg.pingHost = Net.clean(cfg.pingHost)
        SharedStore.save(cfg)
        await probe()
        WidgetCenter.shared.reloadAllTimelines()
        busy = false
    }

    private func probe() async {
        busy = true
        status = "请求订阅…"

        let result = await Net.fetchSubscription(cfg.subUrl)
        usage = result.0

        if cfg.pingAuto {
            let nodes = Net.parseNodes(result.1)
            if let first = nodes.first {
                pingTarget = "\(first.host):\(first.port)"
                status = "探测 \(pingTarget)"
                pingMs = await Net.tcpPing(host: first.host, port: first.port)
            } else {
                pingTarget = ""
                pingMs = nil
                status = usage == nil ? "订阅解析失败" : "订阅内没有节点"
            }
        } else if !cfg.pingHost.isEmpty {
            pingTarget = "\(cfg.pingHost):\(cfg.pingPort)"
            status = "探测 \(pingTarget)"
            pingMs = await Net.tcpPing(host: cfg.pingHost, port: cfg.pingPort)
        } else {
            pingMs = nil
            status = "未设置测速节点"
        }

        if usage == nil && pingMs != nil {
            status = "有延迟，但订阅取不到流量头"
        }
        busy = false
    }
}
