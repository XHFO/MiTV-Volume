import XCTest
@testable import VolumeCore

final class TVDiscoveryTests: XCTestCase {
    func testSubnetBoundsAndNoSelfProbe() {
        let hosts = TVDiscovery.hosts(address: 0xc0a80102, netmask: 0xfffffffc)
        XCTAssertEqual(hosts, ["192.168.1.1"])
        XCTAssertEqual(TVDiscovery.hosts(address: 0x0a000002, netmask: 0xffff0000).count, 253)
        XCTAssertTrue(TVDiscovery.hosts(address: 0xc0a80102, netmask: 0xffffffff).isEmpty)
    }
    func testReconnectFollowsIdentityAcrossIPChange() {
        let tv = DiscoveredTV(host: "192.168.1.80", name: "电视", identity: "aabbccddeeff")
        XCTAssertEqual(TVDiscovery.matching([tv], identity: tv.identity,
            previousHost: "192.168.1.50", previousName: tv.name), tv)
    }
    func testReconnectRejectsWrongTVAtOldIPAndAmbiguousIdentity() {
        let wrong = DiscoveredTV(host: "192.168.1.50", name: "电视", identity: "111111111111")
        XCTAssertNil(TVDiscovery.matching([wrong], identity: "aabbccddeeff",
            previousHost: wrong.host, previousName: wrong.name))
        XCTAssertNil(TVDiscovery.matching([wrong, wrong], identity: wrong.identity,
            previousHost: wrong.host, previousName: wrong.name))
    }
    func testWithoutIdentityDoesNotGuessAcrossIPs() {
        let tv = DiscoveredTV(host: "192.168.1.80", name: "电视", identity: nil)
        XCTAssertNil(TVDiscovery.matching([tv], identity: nil,
            previousHost: "192.168.1.50", previousName: tv.name))
    }
    func testDiscoveryRequiresReadableVolumeAndOnlyUsesReadEndpoints() async {
        MockHTTP.handler = { url in
            let action = URLComponents(url: url, resolvingAgainstBaseURL: false)!.queryItems!.first!.value!
            XCTAssertTrue(["isalive", "getvolume", "getsysteminfo"].contains(action))
            if action == "isalive" { return (200, "{\"msg\":\"success\",\"data\":{\"devicename\":\"客厅电视\"}}") }
            if action == "getvolume" {
                return (200, url.host == "192.168.1.2"
                    ? "{\"msg\":\"success\",\"data\":{\"volume\":10,\"maxVolume\":100}}"
                    : "{\"msg\":\"success\",\"data\":{\"volume\":10,\"maxVolume\":0}}")
            }
            return (200, "{\"msg\":\"success\",\"data\":{\"ethmac\":\"AA:BB:CC:DD:EE:FF\"}}")
        }
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [MockHTTP.self]
        let devices = await TVDiscovery.discover(hosts: ["192.168.1.2", "192.168.1.3", "192.168.1.2"],
            session: URLSession(configuration: config))
        XCTAssertEqual(devices, [DiscoveredTV(host: "192.168.1.2", name: "客厅电视", identity: "aabbccddeeff")])
    }
}
