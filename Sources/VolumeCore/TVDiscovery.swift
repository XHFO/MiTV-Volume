import Foundation
import Darwin

public struct DiscoveredTV: Equatable, Sendable {
    public let host: String
    public let name: String
    public let identity: String?
    public init(host: String, name: String, identity: String?) {
        self.host = host; self.name = name; self.identity = identity
    }
    public var label: String { "\(name)（\(host)）" }
}

public enum TVDiscovery {
    /// Bounded to attached LANs; never scans VPN tunnels or arbitrary remote networks.
    /// Large subnets use the interface's /24 to keep discovery bounded.
    public static func hosts(address: UInt32, netmask: UInt32) -> [String] {
        let mask = netmask | 0xffffff00
        let network = address & mask
        let broadcast = network | ~mask
        guard broadcast > network + 1 else { return [] }
        return ((network + 1)..<broadcast).filter { $0 != address }.map {
            "\(($0 >> 24) & 255).\(($0 >> 16) & 255).\(($0 >> 8) & 255).\($0 & 255)"
        }
    }
    public static func localHosts() -> [String] {
        var first: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&first) == 0, let start = first else { return [] }
        defer { freeifaddrs(first) }
        var result = Set<String>()
        for pointer in sequence(first: start, next: { $0.pointee.ifa_next }) {
            let interface = pointer.pointee
            let name = String(cString: interface.ifa_name)
            guard (name.hasPrefix("en") || name.hasPrefix("bridge") || name.hasPrefix("bond")),
                  interface.ifa_flags & UInt32(IFF_UP) != 0,
                  interface.ifa_flags & UInt32(IFF_LOOPBACK) == 0,
                  let address = interface.ifa_addr, address.pointee.sa_family == UInt8(AF_INET),
                  let mask = interface.ifa_netmask else { continue }
            let ip = address.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { UInt32(bigEndian: $0.pointee.sin_addr.s_addr) }
            let netmask = mask.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { UInt32(bigEndian: $0.pointee.sin_addr.s_addr) }
            result.formUnion(hosts(address: ip, netmask: netmask))
        }
        return result.sorted()
    }
    private static func json(host: String, path: String, session: URLSession) async throws -> [String: Any] {
        guard let url = URL(string: "http://\(host):6095\(path)") else { throw URLError(.badURL) }
        var request = URLRequest(url: url); request.timeoutInterval = 0.7
        let (data, response) = try await session.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200,
              let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              (root["msg"] as? String)?.lowercased() == "success",
              let data = root["data"] as? [String: Any] else { throw VolumeError("不是可用的小米电视接口") }
        return data
    }
    public static func probe(host: String, session: URLSession) async -> DiscoveredTV? {
        do {
            try Task.checkCancellation()
            let alive = try await json(host: host, path: "/request?action=isalive", session: session)
            guard let name = alive["devicename"] as? String, !name.isEmpty else { return nil }
            let volume = try await json(host: host, path: "/controller?action=getvolume", session: session)
            guard let value = volume["volume"] as? Int, let maximum = volume["maxVolume"] as? Int,
                  (try? TVVolume(value: value, maximum: maximum)) != nil else { return nil }
            let info = try? await json(host: host, path: "/controller?action=getsysteminfo", session: session)
            let identity = [info?["ethmac"], info?["wifimac"]].compactMap { $0 as? String }
                .map { $0.replacingOccurrences(of: ":", with: "").replacingOccurrences(of: "-", with: "").lowercased() }
                .first { $0.count == 12 && $0.allSatisfy(\.isHexDigit) && $0 != "000000000000" && $0 != "ffffffffffff" }
            return DiscoveredTV(host: host, name: name, identity: identity)
        } catch { return nil }
    }
    public static func session() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 0.7; config.timeoutIntervalForResource = 1.2
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.connectionProxyDictionary = [:]
        return URLSession(configuration: config)
    }
    public static func discover(hosts: [String] = localHosts(), preferredHost: String? = nil,
                                session: URLSession? = nil) async -> [DiscoveredTV] {
        let session = session ?? Self.session()
        var candidates = Array(Set(hosts)).sorted()
        if let preferredHost { candidates.removeAll { $0 == preferredHost }; candidates.insert(preferredHost, at: 0) }
        return await withTaskGroup(of: DiscoveredTV?.self) { group in
            var iterator = candidates.makeIterator()
            for _ in 0..<48 {
                guard let host = iterator.next(), !Task.isCancelled else { break }
                group.addTask { await probe(host: host, session: session) }
            }
            var found: [DiscoveredTV] = []
            while let result = await group.next() {
                if let result { found.append(result) }
                if Task.isCancelled { group.cancelAll() }
                else if let host = iterator.next() { group.addTask { await probe(host: host, session: session) } }
            }
            return found.sorted { $0.host.localizedStandardCompare($1.host) == .orderedAscending }
        }
    }
    /// Reconnect only to the selected television, never whichever device answers first.
    public static func matching(_ devices: [DiscoveredTV], identity: String?, previousHost: String, previousName: String) -> DiscoveredTV? {
        let candidates = devices.filter { device in
            if let identity { return device.identity == identity }
            return device.host == previousHost && device.name == previousName
        }
        return candidates.count == 1 ? candidates[0] : nil
    }
}
