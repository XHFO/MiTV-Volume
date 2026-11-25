import Foundation
import VolumeCore

/// Reads the active television input through XHFlow on the TV. No ADB is used.
actor TVInputReader {
    private let session = XHFlowClient.session()

    func read(host: String, token: String) async throws -> (current: TVInputState, inputs: [TVInputState]) {
        try await XHFlowClient.read(host: host, token: token, session: session)
    }
}
