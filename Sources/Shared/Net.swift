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
        if let data = defaults.data(forKey: configKey),
           let cfg = try? JSONDecoder().decode(AirportConfig.self, from: data) {
            return cfg
        }
        if let data = UserDefaults.standard.data(forKey: configKey),
           let cfg = try? JSONDecoder().decode(AirportConfig.self, from: data) {
            return cfg
        }
        return AirportConfig()
    }

    static func save(_ cfg: AirportConfig) {
        guard let data = try? JSONEncoder().encode(cfg) else { return }
        defaults.set(data, forKey: configKey)
        UserDefaults.standard.set(data, forKey: configKey)
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
        let urls = [
            "https://ipwho.is/",
            "https://ipinfo.io/json",
            "https://ipapi.co/json/",
            "https://api.ip.sb/geoip"
        ]
        return await withTaskGroup(of: ExitInfo?.self) { group in
            for u in urls {
                group.addTask { await probeExit(u) }
            }
            for await r in group {
                if let r = r {
                    group.cancelAll()
                    return r
                }
            }
            return ExitInfo()
        }
    }

    private static func probeExit(_ u: String) async -> ExitInfo? {
        guard let url = URL(string: u) else { return nil }
        var req = URLRequest(url: url)
        req.timeoutInterval = 8
        req.cachePolicy = .reloadIgnoringLocalCacheData
        req.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 16_0 like Mac OS X)", forHTTPHeaderField: "User-Agent")
        guard let (data, _) = try? await URLSession.shared.data(for: req),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }

        let ip = (obj["ip"] as? String) ?? (obj["query"] as? String) ?? ""
        guard !ip.isEmpty else { return nil }

        let countryRaw = (obj["country"] as? String) ?? (obj["country_name"] as? String) ?? ""
        let country: String
        if countryRaw.count == 2 {
            country = Locale(identifier: "en_US").localizedString(forRegionCode: countryRaw.uppercased()) ?? countryRaw
        } else {
            country = countryRaw
        }
        let region = (obj["region"] as? String) ?? (obj["region_name"] as? String) ?? ""
        let city = (obj["city"] as? String) ?? ""

        let parts = [country, region, city].filter { !$0.isEmpty }
        return ExitInfo(ip: ip, location: parts.joined(separator: " · "))
    }

    private static let netSession: URLSession = {
        let c = URLSessionConfiguration.default
        c.requestCachePolicy = .reloadIgnoringLocalCacheData
        c.httpMaximumConnectionsPerHost = 4
        c.timeoutIntervalForRequest = 12
        c.waitsForConnectivity = false
        return URLSession(configuration: c)
    }()

    private static let warmLock = NSLock()
    private static var warmedHosts: Set<String> = []

    static func httpPing(_ raw: String, timeout: Double = 12) async -> Int? {
        var t = clean(raw)
        guard !t.isEmpty else { return nil }
        if !t.lowercased().hasPrefix("http") { t = "https://" + t }
        guard let url = URL(string: t), let host = url.host, !host.isEmpty else { return nil }

        var req = URLRequest(url: url)
        req.timeoutInterval = timeout
        req.cachePolicy = .reloadIgnoringLocalCacheData
        req.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 16_0 like Mac OS X)", forHTTPHeaderField: "User-Agent")

        warmLock.lock()
        let needWarm = !warmedHosts.contains(host)
        if needWarm { warmedHosts.insert(host) }
        warmLock.unlock()
        if needWarm {
            _ = try? await netSession.data(for: req)
        }

        let start = DispatchTime.now()
        do {
            let (bytes, _) = try await netSession.bytes(for: req)
            var gotByte = false
            for try await _ in bytes {
                gotByte = true
                break
            }
            let ns = DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds
            return gotByte ? Int(ns / 1_000_000) : nil
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
