import XCTest
import CryptoKit
@testable import VolumeCore

final class MockHTTP: URLProtocol {
    static var handler: ((URL) throws -> (Int, String))!
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let (status, body) = try Self.handler(request.url!)
            client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: status,
                httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(body.utf8)); client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}
final class MiTVClientTests: XCTestCase {
    @MainActor func client() -> MiTVClient {
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [MockHTTP.self]
        return MiTVClient(host: "192.168.1.50", session: URLSession(configuration: config))
    }
    @MainActor func testStructuredJSONAndDeviceScale() async throws {
        MockHTTP.handler = { url in
            XCTAssertEqual(url.port, 6095); XCTAssertEqual(url.path, "/controller")
            XCTAssertEqual(url.query, "action=getvolume")
            return (200, "{\"msg\": \"success\", \"data\": {\"volume\": 7, \"maxVolume\": 30}}")
        }
        let value = try await client().read(); XCTAssertEqual(value.value, 7); XCTAssertEqual(value.maximum, 30)
    }
    @MainActor func testSignedAbsoluteUsesValidMACAndRawTVUnits() async throws {
        MockHTTP.handler = { url in
            if url.query == "action=getsysteminfo" {
                return (200, "{\"msg\":\"success\",\"data\":{\"ethmac\":\"\",\"wifimac\":\"AA:BB:CC:DD:EE:FF\"}}")
            }
            let query = Dictionary(uniqueKeysWithValues: URLComponents(url: url, resolvingAgainstBaseURL: false)!.queryItems!.map { ($0.name, $0.value!) })
            XCTAssertEqual(url.path, "/general"); XCTAssertEqual(query["action"], "setVolum")
            XCTAssertEqual(query["volum"], "7")
            let expected = Insecure.MD5.hash(data: Data("mitvsignsalt&7&aabbccddeeff&\(query["ts"]!)".utf8)).map { String(format: "%02x", $0) }.joined()
            XCTAssertEqual(query["sign"], expected)
            return (200, "{\"msg\":\"success\"}")
        }
        let accepted = try await client().setAbsolute(7); XCTAssertTrue(accepted)
    }
    @MainActor func testUnsupportedAbsoluteCanFallback() async throws {
        MockHTTP.handler = { _ in (404, "missing") }
        let accepted = try await client().setAbsolute(7); XCTAssertFalse(accepted)
    }
    @MainActor func testNetworkFailureDoesNotTriggerFallback() async {
        MockHTTP.handler = { _ in throw URLError(.timedOut) }
        do { _ = try await client().setAbsolute(7); XCTFail("Must throw on network failure") } catch {}
    }
}
