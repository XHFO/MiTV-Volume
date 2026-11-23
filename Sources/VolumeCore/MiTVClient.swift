import Foundation
import CryptoKit

@MainActor public final class MiTVClient: VolumeTV {
    private let host: String
    private let session: URLSession
    private var mac: String?
    public init(host: String, session: URLSession? = nil) {
        self.host = host
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 1.5
        config.timeoutIntervalForResource = 2
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.connectionProxyDictionary = [:]
        self.session = session ?? URLSession(configuration: config)
    }
    private struct Rejected: Error {}
    private func request(_ path: String, _ query: [URLQueryItem]) async throws -> [String: Any] {
        var parts = URLComponents()
        parts.scheme = "http"; parts.host = host; parts.port = 6095
        parts.path = path; parts.queryItems = query
        guard let url = parts.url else { throw VolumeError("电视 IP 无效") }
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw VolumeError("电视响应无效") }
        if [404, 405, 501].contains(response.statusCode) { throw Rejected() }
        guard response.statusCode == 200 else { throw VolumeError("电视 HTTP 请求失败（\(response.statusCode)）") }
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw VolumeError("电视响应格式无效")
        }
        guard (root["msg"] as? String)?.lowercased() == "success" else { throw Rejected() }
        return root["data"] as? [String: Any] ?? [:]
    }
    public func read() async throws -> TVVolume {
        let data = try await request("/controller", [.init(name: "action", value: "getvolume")])
        guard let value = data["volume"] as? Int, let maximum = data["maxVolume"] as? Int else {
            throw VolumeError("电视不支持读取当前音量")
        }
        return try TVVolume(value: value, maximum: maximum)
    }
    public func setAbsolute(_ value: Int) async throws -> Bool {
        do {
            if mac == nil {
                let data = try await request("/controller", [.init(name: "action", value: "getsysteminfo")])
                mac = [data["ethmac"], data["wifimac"]].compactMap { $0 as? String }
                    .map { $0.replacingOccurrences(of: ":", with: "").replacingOccurrences(of: "-", with: "").lowercased() }
                    .first { $0.count == 12 && $0.allSatisfy(\.isHexDigit) && $0 != "000000000000" }
            }
            guard let mac else { return false }
            let timestamp = String(Int(Date().timeIntervalSince1970))
            let digest = Insecure.MD5.hash(data: Data("mitvsignsalt&\(value)&\(mac)&\(timestamp)".utf8))
            let signature = digest.map { String(format: "%02x", $0) }.joined()
            _ = try await request("/general", [.init(name: "action", value: "setVolum"),
                .init(name: "volum", value: String(value)), .init(name: "ts", value: timestamp),
                .init(name: "sign", value: signature)])
            return true
        } catch is Rejected { return false }
    }
    public func step(up: Bool) async throws {
        _ = try await request("/controller", [.init(name: "action", value: "keyevent"),
            .init(name: "keycode", value: up ? "volumeup" : "volumedown")])
    }
}
