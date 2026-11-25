import Foundation

/// Reads the television input source from XHFlow (电视端 XH 光流) over LAN.
/// XHFlow listens on port 8768 and requires the pairing token from the TV QR code.
public enum XHFlowClient {
    public static let port = 8768
    public static let tokenHeader = "x-tvwled-token"

    public static func validatedToken(_ raw: String) throws -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let url = URL(string: trimmed),
           let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
           let token = items.first(where: { $0.name == "token" })?.value {
            return try validatedToken(token)
        }
        let token = trimmed.lowercased()
        guard token.range(of: #"^[a-f0-9]{32}$"#, options: .regularExpression) != nil else {
            throw VolumeError("请粘贴电视 XH 光流二维码里的完整链接，或 32 位配对码")
        }
        return token
    }

    public static func session() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 1.5
        config.timeoutIntervalForResource = 2
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.connectionProxyDictionary = [:]
        return URLSession(configuration: config)
    }

    public static func read(host: String, token: String, session: URLSession = session()) async throws
        -> (current: TVInputState, inputs: [TVInputState]) {
        let parts = host.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4, parts.allSatisfy({ UInt8($0) != nil }) else {
            throw VolumeError("电视地址无效")
        }
        let secret = try validatedToken(token)
        var components = URLComponents()
        components.scheme = "http"
        components.host = host
        components.port = port
        components.path = "/api/status"
        guard let url = components.url else { throw VolumeError("电视地址无效") }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue(secret, forHTTPHeaderField: tokenHeader)
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw VolumeError("无法连接电视上的 XH 光流（端口 \(port)），请确认应用在运行且配置后台已开启")
        }
        guard let http = response as? HTTPURLResponse else { throw VolumeError("XH 光流响应无效") }
        switch http.statusCode {
        case 200:
            break
        case 401:
            throw VolumeError("XH 光流配对无效，请重新粘贴电视上的配对链接")
        case 403:
            throw VolumeError("XH 光流拒绝了本机请求，请确认访问的是电视局域网地址")
        default:
            throw VolumeError("XH 光流 HTTP 请求失败（\(http.statusCode)）")
        }
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw VolumeError("XH 光流响应格式无效")
        }
        return try TVInputState.parseStatus(root)
    }
}
