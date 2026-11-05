import Foundation
import Testing

@testable import HitoikiCore

/// sudo's real refusal when it has no terminal: 164 bytes from sudo 1.9.13p3.
internal func sudoFixtureURL() throws -> URL {
    try #require(Bundle.module.url(forResource: "sudo-no-terminal", withExtension: "txt", subdirectory: "Fixtures"))
}

internal func sudoFixture() throws -> [UInt8] {
    try [UInt8](Data(contentsOf: sudoFixtureURL()))
}

@Suite("Retry offer")
internal struct RetryTests {
    internal struct Case: Sendable, CustomTestStringConvertible {
        let line: String
        /// The offer when the exit is non-zero and the clause appeared; nil when the line never qualifies.
        let offer: String?
        var testDescription: String { line }
    }

    private static let cases: [Case] = [
        Case(line: "ssh h cmd", offer: "ssh -tt h cmd"),
        Case(line: "  ssh h cmd", offer: "ssh -tt h cmd"),
        Case(line: "\tssh h cmd", offer: "ssh -tt h cmd"),
        Case(line: "ssh -tt h cmd", offer: nil),
        Case(line: "ssh -t h cmd", offer: nil),
        Case(line: "ssh -At h cmd", offer: nil),
        Case(line: "ssh -tA h cmd", offer: nil),
        Case(line: "ssh h sudo ls -lt", offer: nil),
        Case(line: "ssh -o Foo=bar h cmd", offer: "ssh -tt -o Foo=bar h cmd"),
        Case(line: "ssh -p 22 h cmd", offer: "ssh -tt -p 22 h cmd"),
        Case(line: "ssh -4t h cmd", offer: "ssh -tt -4t h cmd"),
        Case(line: "ssh -o RequestTTY=yes h cmd", offer: "ssh -tt -o RequestTTY=yes h cmd"),
        Case(line: "ssh host 'sudo true'", offer: "ssh -tt host 'sudo true'"),
        Case(line: "ssh  h   'a  b'", offer: "ssh -tt  h   'a  b'"),
        Case(line: "sshfs h", offer: nil),
        Case(line: "scp h", offer: nil),
        Case(line: "ssh", offer: nil),
        Case(line: "ssh\th cmd", offer: nil),
    ]

    @Test("All four guards hold: the offer inserts -tt once", arguments: cases)
    internal func offered(_ testCase: Case) {
        #expect(Retry.offer(line: testCase.line, exit: .status(1), sawSudoRefusal: true) == testCase.offer)
    }

    @Test("Exit zero never offers", arguments: cases)
    internal func exitZero(_ testCase: Case) {
        #expect(Retry.offer(line: testCase.line, exit: .status(0), sawSudoRefusal: true) == nil)
    }

    @Test("Without the clause there is no offer", arguments: cases)
    internal func noClause(_ testCase: Case) {
        #expect(Retry.offer(line: testCase.line, exit: .status(1), sawSudoRefusal: false) == nil)
        #expect(Retry.offer(line: testCase.line, exit: .status(0), sawSudoRefusal: false) == nil)
    }

    @Test("A signal exit is not zero")
    internal func signalExit() {
        #expect(Retry.offer(line: "ssh h cmd", exit: .signal(2), sawSudoRefusal: true) == "ssh -tt h cmd")
    }

    @Test("The fixture is sudo's 164 bytes, the clause first")
    internal func fixture() throws {
        let bytes = try sudoFixture()
        #expect(bytes.count == 164)
        #expect(bytes.starts(with: Retry.clause))
    }

    @Test("The scanner finds the clause split at every byte boundary")
    internal func scannerAcrossChunks() throws {
        let bytes = try sudoFixture()
        for split in 0...bytes.count {
            var scanner = RefusalScanner()
            scanner.scan(Array(bytes[..<split]))
            scanner.scan(Array(bytes[split...]))
            #expect(scanner.sawRefusal, "split at \(split)")
        }
    }

    @Test("The scanner finds the clause one byte at a time, after other output")
    internal func scannerByteByByte() throws {
        var scanner = RefusalScanner()
        scanner.scan(Array(repeating: UInt8(ascii: "x"), count: 100))
        for byte in try sudoFixture() {
            scanner.scan([byte])
        }
        #expect(scanner.sawRefusal)
    }

    @Test("The scanner ignores sudo's other line and near misses")
    internal func scannerNoClause() throws {
        var scanner = RefusalScanner()
        let fixture = try sudoFixture()
        scanner.scan(Array(fixture[fixture.count - 29..<fixture.count]))
        scanner.scan(Array("sudo: a terminal is required to read the passwor".utf8))
        scanner.scan(Array("D".utf8))
        scanner.scan(Array("x sudo: a terminal is required".utf8))
        #expect(!scanner.sawRefusal)
    }
}
