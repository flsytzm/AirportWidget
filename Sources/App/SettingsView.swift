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
    @State private var exitInfo = ExitInfo()
    @State private var pingTarget: String = ""
    @State private var method: String = ""
    @State private var status: String = ""
    @State private var busy = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("名称", text: $cfg.targetName)
                        .textInputAutocapitalization(.never)
                    TextField("网址", text: $cfg.targetUrl)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                }

                Section {
                    Stepper("刷新间隔：\(cfg.refreshMinutes) 分钟", value: $cfg.refreshMinutes, in: 15...720, step: 15)
                }

                Section("当前数据") {
                    row("出口 IP", exitInfo.ok ? exitInfo.ip : "—")
                    row("归属地", exitInfo.ok ? exitInfo.location : "—")
                    row("延迟", pingMs.map { "\($0) ms" } ?? "—")
                    row("测法", method.isEmpty ? "—" : method)
                }

                Section {
                    TextField("订阅链接（可选，用于显示剩余流量）", text: $cfg.subUrl)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                    if let u = usage, u.total > 0 {
                        row("剩余流量", Net.formatBytes(u.remain))
                        row("已用 / 总量", "\(Net.formatBytes(u.used)) / \(Net.formatBytes(u.total))")
                        row("到期", Net.formatDate(u.expire))
                    }
                } header: {
                    Text("流量（可选）")
                }

                Section {
                    Toggle("自动选取订阅内节点测延迟", isOn: $cfg.pingAuto)
                    if !cfg.pingAuto && cfg.targetUrl.isEmpty {
                        TextField("节点地址", text: $cfg.pingHost)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        TextField("端口", value: $cfg.pingPort, format: .number)
                            .keyboardType(.numberPad)
                    }
                } footer: {
                    Text("填了网址时，延迟按该网址的 HTTP 请求耗时计算；网址留空才用节点 TCP 探测。")
                        .font(.caption2)
                }

                Section {
                    Button("保存并刷新小组件") { Task { await saveAndRefresh() } }
                        .disabled(busy)
                    Button("立即刷新数据") { Task { await probe() } }
                        .disabled(busy)
                } footer: {
                    Text(status.isEmpty ? "就绪" : status)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("代理 IP 小组件")
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
        cfg.targetUrl = Net.clean(cfg.targetUrl)
        cfg.subUrl = Net.clean(cfg.subUrl)
        cfg.pingHost = Net.clean(cfg.pingHost)
        SharedStore.save(cfg)
        await probe()
        WidgetCenter.shared.reloadAllTimelines()
        busy = false
    }

    private func probe() async {
        busy = true
        status = "检测中…"

        async let exitTask = Net.fetchExit()

        var sub: (Usage?, String) = (nil, "")
        if !cfg.subUrl.isEmpty {
            sub = await Net.fetchSubscription(cfg.subUrl)
            usage = sub.0
        }

        if !cfg.targetUrl.isEmpty {
            pingTarget = cfg.targetUrl
            method = "HTTP"
            status = "请求 \(pingTarget)"
            pingMs = await Net.httpPing(cfg.targetUrl)
        } else if cfg.pingAuto {
            let nodes = Net.parseNodes(sub.1)
            if let first = nodes.first {
                pingTarget = "\(first.host):\(first.port)"
                method = "TCP"
                status = "探测 \(pingTarget)"
                pingMs = await Net.tcpPing(host: first.host, port: first.port)
            } else {
                pingTarget = ""
                method = ""
                pingMs = nil
            }
        } else if !cfg.pingHost.isEmpty {
            pingTarget = "\(cfg.pingHost):\(cfg.pingPort)"
            method = "TCP"
            status = "探测 \(pingTarget)"
            pingMs = await Net.tcpPing(host: cfg.pingHost, port: cfg.pingPort)
        } else {
            pingMs = nil
            method = ""
        }

        exitInfo = await exitTask

        if pingMs == nil {
            status = "延迟检测失败（目标不可达）"
        } else {
            status = "完成：\(pingMs!) ms"
        }
        busy = false
    }
}
