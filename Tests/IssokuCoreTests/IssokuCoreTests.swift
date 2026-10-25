import Testing

@testable import IssokuCore

@Suite("Smoke")
internal struct SmokeTests {
    @Test("Version is non-empty")
    internal func versionIsSet() {
        #expect(!IssokuCore.version.isEmpty)
    }
}
