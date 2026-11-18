import Foundation
import Network

struct AirportConfig: Codable {
    var name: String = ""
    var targetName: String = ""
    var targetUrl: String = ""
    var subUrl: String = ""
    var refreshMinutes: Int = 60
    var refreshSeconds: Int = 30
    var pingHost: String = ""
    var pingPort: Int = 443
    var pingAuto: Bool = true

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = (try? c.decode(String.self, forKey: .name)) ?? ""
        targetName = (try? c.decode(String.self, forKey: .targetName)) ?? ""
        targetUrl = (try? c.decode(String.self, forKey: .targetUrl)) ?? ""
        subUrl = (try? c.decode(String.self, forKey: .subUrl)) ?? ""
        refreshMinutes = (try? c.decode(Int.self, forKey: .refreshMinutes)) ?? 60
        refreshSeconds = (try? c.decode(Int.self, forKey: .refreshSeconds)) ?? 30
        pingHost = (try? c.decode(String.self, forKey: .pingHost)) ?? ""
        pingPort = (try? c.decode(Int.self, forKey: .pingPort)) ?? 443
        pingAuto = (try? c.decode(Bool.self, forKey: .pingAuto)) ?? true
    }
}

struct Usage {
    var total: Double = 0
    var used: Double = 0
    var remain: Double = 0
    var expire: Int = 0
}

struct NodeServer {
    var host: String
    var port: Int
}

struct ExitInfo {
    var ip: String = ""
    var location: String = ""
    var ok: Bool { !ip.isEmpty }
}

enum SharedStore {
    static let appGroup = "group.com.example.airportwidget"
    static let configKey = "airportConfig"

    static var defaults: UserDefaults {
        UserDefaults(suiteName: appGroup) ?? UserDefaults.standard
    }

    static func load() -> AirportConfig {
        guard let data = defaults.data(forKey: configKey),
              let cfg = try? JSONDecoder().decode(AirportConfig.self, from: data) else {
            return AirportConfig()
        }
        return cfg
    }

    static func save(_ cfg: AirportConfig) {
        if let data = try? JSONEncoder().encode(cfg) {
            defaults.set(data, forKey: configKey)
        }
    }
}

enum Net {
    static func clean(_ u: String) -> String {
        u.components(separatedBy: .whitespacesAndNewlines).joined()
    }

    static func unwrap(_ u: String) -> String {
        guard let range = u.range(of: "url=") else { return u }
        let tail = String(u[range.upperBound...])
        let piece = tail.components(separatedBy: "&").first ?? ""
        guard let inner = piece.removingPercentEncoding, inner.hasPrefix("http") else { return u }
        return inner
    }

    static func parseUserInfo(_ raw: String?) -> Usage? {
        guard let raw = raw else { return nil }
        func num(_ key: String) -> Double {
            guard let r = raw.range(of: key + "=") else { return 0 }
            let tail = raw[r.upperBound...]
            let digits = tail.prefix { $0.isNumber }
            return Double(digits) ?? 0
        }
        let total = num("total")
        if total <= 0 { return nil }
        let used = num("upload") + num("download")
        return Usage(total: total, used: used, remain: max(0, total - used), expire: Int(num("expire")))
    }

    static func parseNodes(_ body: String) -> [NodeServer] {
        var list: [NodeServer] = []
        var host: String?
        for rawLine in body.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if let r = line.range(of: "server:") {
                let tail = line[r.upperBound...].trimmingCharacters(in: .whitespaces)
                let h = tail.prefix { !$0.isWhitespace && $0 != "," && $0 != "}" && $0 != "\"" && $0 != "'" }
                if !h.isEmpty { host = String(h) }
            }
            if let r = line.range(of: "port:") , let h = host {
                let tail = line[r.upperBound...].trimmingCharacters(in: .whitespaces)
                let digits = tail.prefix { $0.isNumber }
                if let p = Int(digits), p > 0, p < 65536 {
                    list.append(NodeServer(host: h, port: p))
                }
                host = nil
            }
        }
        return list
    }

    static func fetchSubscription(_ url: String) async -> (Usage?, String) {
        let cleaned = clean(url)
        guard !cleaned.isEmpty else { return (nil, "") }
        let candidates = [unwrap(cleaned), cleaned]
        let agents = ["ClashforWindows/0.20.39", "Shadowrocket/1.0", "Mozilla/5.0 (iPhone)"]

        for cand in candidates {
            for ua in agents {
                var req = URLRequest(url: URL(string: cand) ?? URL(string: "https://127.0.0.1")!)
                req.setValue(ua, forHTTPHeaderField: "User-Agent")
                req.timeoutInterval = 20
                do {
                    let (data, resp) = try await URLSession.shared.data(for: req)
                    let body = String(data: data, encoding: .utf8) ?? ""
                    let header = (resp as? HTTPURLResponse)?.value(forHTTPHeaderField: "subscription-userinfo")
                    if let usage = parseUserInfo(header) {
                        return (usage, body)
                    }
                    if !parseNodes(body).isEmpty {
                        return (nil, body)
                    }
                } catch {
                    continue
                }
            }
        }
        return (nil, "")
    }

    static func fetchExit() async -> ExitInfo {
        for u in ["https://ipinfo.io/json", "https://ipapi.co/json/"] {
            guard let url = URL(string: u) else { continue }
            var req = URLRequest(url: url)
            req.timeoutInterval = 10
            req.setValue("Mozilla/5.0 (iPhone)", forHTTPHeaderField: "User-Agent")
            guard let (data, _) = try? await URLSession.shared.data(for: req),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
            let ip = (obj["ip"] as? String) ?? ""
            let city = (obj["city"] as? String) ?? ""
            let region = (obj["region"] as? String) ?? (obj["region_name"] as? String) ?? ""
            let country = (obj["country_name"] as? String) ?? (obj["country"] as? String) ?? ""
            if !ip.isEmpty {
                let parts = [country, region, city].filter { !$0.isEmpty }
                return ExitInfo(ip: ip, location: parts.joined(separator: " · "))
            }
        }
        return ExitInfo()
    }

    static func httpPing(_ raw: String, timeout: Double = 12) async -> Int? {
        var t = clean(raw)
        guard !t.isEmpty else { return nil }
        if !t.lowercased().hasPrefix("http") { t = "https://" + t }
        guard let url = URL(string: t) else { return nil }
        var req = URLRequest(url: url)
        req.timeoutInterval = timeout
        req.cachePolicy = .reloadIgnoringLocalCacheData
        req.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 16_0 like Mac OS X)", forHTTPHeaderField: "User-Agent")
        let start = DispatchTime.now()
        do {
            _ = try await URLSession.shared.data(for: req)
            let ns = DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds
            return Int(ns / 1_000_000)
        } catch {
            return nil
        }
    }

    static func tcpPing(host: String, port: Int, timeout: Double = 6) async -> Int? {
        guard let nwPort = NWEndpoint.Port(rawValue: UInt16(clamping: port)) else { return nil }
        return await withCheckedContinuation { (cont: CheckedContinuation<Int?, Never>) in
            let start = DispatchTime.now()
            let conn = NWConnection(host: NWEndpoint.Host(host), port: nwPort, using: .tcp)
            var finished = false
            let lock = NSLock()

            func finish(_ value: Int?) {
                lock.lock()
                if finished { lock.unlock(); return }
                finished = true
                lock.unlock()
                conn.cancel()
                cont.resume(returning: value)
            }

            conn.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    let ms = Int(Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000)
                    finish(ms)
                case .failed, .cancelled:
                    finish(nil)
                default:
                    break
                }
            }
            conn.start(queue: .global())
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) { finish(nil) }
        }
    }

    static func formatBytes(_ b: Double) -> String {
        let gb = b / 1024 / 1024 / 1024
        if gb >= 1024 { return String(format: "%.2f TB", gb / 1024) }
        if gb >= 100 { return String(format: "%.0f GB", gb) }
        return String(format: "%.1f GB", gb)
    }

    static func formatDate(_ ts: Int) -> String {
        guard ts > 0 else { return "不限" }
        let date = Date(timeIntervalSince1970: TimeInterval(ts))
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }
}
