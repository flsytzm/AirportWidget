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
    @State private var method: String = ""
    @State private var status: String = "没有读到网址"
    @State private var busy = false

    var body: some View {
        ZStack {
            Color(uiColor: .systemGroupedBackground)
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 13) {
                    Text("代理 IP 小组件")
                        .font(.system(size: 30, weight: .bold))
                        .padding(.top, 4)

                    card {
                        VStack(spacing: 0) {
                            TextField("名称", text: $cfg.targetName)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)
                            Divider().padding(.leading, 16)
                            TextField("网址", text: $cfg.targetUrl)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .keyboardType(.URL)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)
                        }
                    }

                    card {
                        HStack(spacing: 8) {
                            Text("刷新间隔")
                            Spacer(minLength: 8)
                            TextField("", value: $cfg.refreshSeconds, format: .number)
                                .keyboardType(.numberPad)
                                .multilineTextAlignment(.trailing)
                                .monospacedDigit()
                                .frame(width: 60)
                            Text("秒")
                            Stepper("", value: $cfg.refreshSeconds, in: 1...3600, step: 1)
                                .labelsHidden()
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 6)
                    }

                    card {
                        VStack(spacing: 0) {
                            row("出口 IP", exitInfo.ok ? exitInfo.ip : (busy ? "检测中…" : "—"))
                            Divider().padding(.leading, 16)
                            row("归属地", exitInfo.ok ? exitInfo.location : (busy ? "检测中…" : "—"))
                        }
                    }

                    card {
                        VStack(spacing: 0) {
                            row("\(cfg.targetName.isEmpty ? "YouTube" : cfg.targetName) 延迟",
                                pingMs.map { "\($0) ms" } ?? (busy ? "检测中…" : "—"))
                            Divider().padding(.leading, 16)
                            row("测法", method.isEmpty ? "—" : method)
                        }
                    }

                    Text(status)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .padding(.leading, 4)

                    card {
                        VStack(spacing: 0) {
                            Button {
                                Task { await saveAndRefresh() }
                            } label: {
                                HStack {
                                    Text("保存并刷新小组件").foregroundStyle(.blue)
                                    Spacer()
                                }
                                .contentShape(Rectangle())
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)

                            Divider().padding(.leading, 16)

                            Button {
                                Task { await probe(silent: false) }
                            } label: {
                                HStack {
                                    Text("立即刷新数据").foregroundStyle(.blue)
                                    Spacer()
                                }
                                .contentShape(Rectangle())
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                        }
                    }

                    DisclosureGroup("流量（可选）") {
                        VStack(spacing: 0) {
                            TextField("订阅链接", text: $cfg.subUrl)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .keyboardType(.URL)
                                .padding(.vertical, 8)
                            if let u = usage, u.total > 0 {
                                Divider()
                                row("剩余流量", Net.formatBytes(u.remain))
                                Divider()
                                row("已用 / 总量", "\(Net.formatBytes(u.used)) / \(Net.formatBytes(u.total))")
                                Divider()
                                row("到期", Net.formatDate(u.expire))
                            }
                        }
                    }
                    .font(.system(size: 15))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                    Text("小组件刷新由 iOS 调度，最快约 15 分钟；App 内按设定秒数实时刷新。")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 4)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .onAppear {
            if cfg.targetName.isEmpty { cfg.targetName = "YouTube" }
        }
        .task(id: cfg.refreshSeconds) {
            while !Task.isCancelled {
                await probe(silent: true)
                let sec = max(1, cfg.refreshSeconds)
                try? await Task.sleep(nanoseconds: UInt64(sec) * 1_000_000_000)
            }
        }
    }

    private func card<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        content()
            .frame(maxWidth: .infinity)
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value)
                .foregroundStyle(value == "—" ? Color.secondary : Color.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func saveAndRefresh() async {
        cfg.targetUrl = Net.clean(cfg.targetUrl)
        cfg.subUrl = Net.clean(cfg.subUrl)
        cfg.pingHost = Net.clean(cfg.pingHost)
        SharedStore.save(cfg)
        await probe(silent: false)
        WidgetCenter.shared.reloadAllTimelines()
    }

    private func probe(silent: Bool) async {
        if !silent {
            busy = true
            status = "检测中…"
        }

        let snap = cfg

        async let exitTask = Net.fetchExit()
        async let pingTask = Self.measurePing(snap)

        let measured = await pingTask
        exitInfo = await exitTask

        pingMs = measured.value
        method = measured.method

        if snap.targetUrl.isEmpty {
            status = "没有读到网址"
        } else if let ms = measured.value {
            status = "完成：\(ms) ms"
        } else {
            status = "测速失败（目标不可达）"
        }

        if !silent { busy = false }
    }

    private struct PingResult {
        var value: Int?
        var method: String
    }

    private static func measurePing(_ cfg: AirportConfig) async -> PingResult {
        if !cfg.targetUrl.isEmpty {
            return PingResult(value: await Net.httpPing(cfg.targetUrl), method: "HTTP")
        }
        if cfg.pingAuto, !cfg.subUrl.isEmpty {
            let sub = await Net.fetchSubscription(cfg.subUrl)
            if let first = Net.parseNodes(sub.1).first {
                return PingResult(value: await Net.tcpPing(host: first.host, port: first.port), method: "TCP")
            }
        }
        if !cfg.pingHost.isEmpty {
            return PingResult(value: await Net.tcpPing(host: cfg.pingHost, port: cfg.pingPort), method: "TCP")
        }
        return PingResult(value: nil, method: "")
    }
}
