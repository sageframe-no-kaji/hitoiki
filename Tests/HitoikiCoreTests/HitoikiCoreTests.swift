import Testing

@testable import HitoikiCore

@Suite("Smoke")
internal struct SmokeTests {
    @Test("Version is non-empty")
    internal func versionIsSet() {
        #expect(!HitoikiCore.version.isEmpty)
    }
}
