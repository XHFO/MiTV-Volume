import Foundation

/// Keeps reconnection separate from volume commands. A manual output selection
/// while unplugged cancels automatic restoration to the proxy.
public struct OutputRecovery {
    public private(set) var wasConnected: Bool?
    public private(set) var restorePending = false
    public private(set) var fallbackUID: String?
    private var lastConnectedDefault: String?
    public init() {}
    public mutating func disconnected(defaultUID: String?, proxyUID: String, preferredFallbackUID: String? = nil) -> Bool {
        let entering = wasConnected != false
        if entering {
            restorePending = lastConnectedDefault == proxyUID || defaultUID == proxyUID
            fallbackUID = defaultUID == proxyUID ? nil : defaultUID
        } else if let defaultUID, defaultUID != proxyUID {
            if let fallbackUID, fallbackUID != defaultUID { restorePending = false }
            else { fallbackUID = defaultUID }
        }
        wasConnected = false
        // macOS may already have chosen its own fallback before our next poll.
        // Retry a missing preferred device, but stop if the user chooses another output.
        return restorePending && (entering || defaultUID == proxyUID ||
            (preferredFallbackUID != nil && defaultUID == fallbackUID && defaultUID != preferredFallbackUID))
    }
    public mutating func usedFallback(_ uid: String) { fallbackUID = uid }
    public mutating func connected(defaultUID: String?, proxyUID: String, physicalUID: String) -> Bool {
        if wasConnected == false && restorePending, let defaultUID,
           defaultUID != proxyUID && defaultUID != physicalUID && defaultUID != fallbackUID {
            restorePending = false
        }
        wasConnected = true
        lastConnectedDefault = defaultUID
        return restorePending
    }
    public mutating func restored(proxyUID: String) {
        restorePending = false; fallbackUID = nil; lastConnectedDefault = proxyUID
    }
}
