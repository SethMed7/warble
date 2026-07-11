import XCTest
@testable import Shared

/// The resumable-download decision logic (ROADMAP 0.4 "engine setup friction") — pure and
/// network-free. The wire-level behavior (206 append, 200 restart, 416 verify, .part promotion)
/// is proven end-to-end by scripts/regression.sh's setup-resume check against a loopback fixture
/// server; the file:// tests here cover the fetcher's file plumbing with no server at all.
final class ResumableFetchTests: XCTestCase {

    // MARK: decide() — the resume decision matrix

    func testHonoredRangeAppends() {
        XCTAssertEqual(ResumableFetch.decide(status: 206, partialBytes: 100, contentRangeStart: 100),
                       .append(from: 100))
    }

    func testMismatchedRangeRestartsInsteadOfCorrupting() {
        // A 206 that doesn't start exactly at our partial would interleave wrong bytes — restart.
        XCTAssertEqual(ResumableFetch.decide(status: 206, partialBytes: 100, contentRangeStart: 50), .restart)
        XCTAssertEqual(ResumableFetch.decide(status: 206, partialBytes: 100, contentRangeStart: nil), .restart)
        XCTAssertEqual(ResumableFetch.decide(status: 206, partialBytes: 0, contentRangeStart: 0), .restart)
    }

    func testIgnoredRangeRestarts() {
        // A server that ignores Range sends the whole file (200) — the honest move is a restart.
        XCTAssertEqual(ResumableFetch.decide(status: 200, partialBytes: 100, contentRangeStart: nil), .restart)
        XCTAssertEqual(ResumableFetch.decide(status: 200, partialBytes: 0, contentRangeStart: nil), .restart)
    }

    func testUnsatisfiableRangeVerifiesInsteadOfRefetching() {
        // 416 with a partial: the partial may already hold every byte — verify, never refetch.
        XCTAssertEqual(ResumableFetch.decide(status: 416, partialBytes: 100, contentRangeStart: nil),
                       .verifyComplete)
        // 416 with no partial is just a broken request.
        XCTAssertEqual(ResumableFetch.decide(status: 416, partialBytes: 0, contentRangeStart: nil), .fail(416))
    }

    func testRealFailuresFail() {
        XCTAssertEqual(ResumableFetch.decide(status: 404, partialBytes: 0, contentRangeStart: nil), .fail(404))
        XCTAssertEqual(ResumableFetch.decide(status: 500, partialBytes: 100, contentRangeStart: nil), .fail(500))
    }

    // MARK: Content-Range parsing

    func testContentRangeParsing() {
        XCTAssertEqual(ResumableFetch.contentRangeStart("bytes 102400-262143/262144"), 102_400)
        XCTAssertEqual(ResumableFetch.contentRangeTotal("bytes 102400-262143/262144"), 262_144)
        XCTAssertNil(ResumableFetch.contentRangeStart("bytes */262144")) // no start on a 416
        XCTAssertEqual(ResumableFetch.contentRangeTotal("bytes */262144"), 262_144)
        XCTAssertNil(ResumableFetch.contentRangeStart(nil))
        XCTAssertNil(ResumableFetch.contentRangeTotal("bytes 0-99/*")) // unknown total
        XCTAssertNil(ResumableFetch.contentRangeStart("garbage"))
    }

    // MARK: file:// plumbing — no server, no network

    private func tempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("warble-fetch-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        return dir
    }

    func testFetchWritesDestAndClearsPartial() throws {
        let dir = try tempDir()
        let src = dir.appendingPathComponent("src.bin")
        let body = Data((0..<10_000).map { UInt8($0 % 251) })
        try body.write(to: src)
        let dest = dir.appendingPathComponent("out.bin")

        var lastWritten: Int64 = 0
        let outcome = try ResumableFetch().run(src, to: dest) { written, _ in lastWritten = written }
        XCTAssertEqual(outcome, .fetched(Int64(body.count)))
        XCTAssertEqual(try Data(contentsOf: dest), body)
        XCTAssertEqual(lastWritten, Int64(body.count)) // progress reported real bytes
        XCTAssertFalse(FileManager.default.fileExists(atPath: dest.path + ".part"),
                       "the partial must be promoted, not copied")
    }

    func testExistingDestIsNeverRefetched() throws {
        let dir = try tempDir()
        let src = dir.appendingPathComponent("src.bin")
        let body = Data(repeating: 7, count: 4_096)
        try body.write(to: src)
        let dest = dir.appendingPathComponent("out.bin")
        try body.write(to: dest) // already present and valid

        let outcome = try ResumableFetch().run(src, to: dest) { _, _ in }
        XCTAssertEqual(outcome, .alreadyComplete(Int64(body.count)))
    }
}
