import Foundation
import Testing
@testable import SlotDockCore

@Suite("DropPathResolver")
struct DropPathResolverTests {
    @Test("empty rejects")
    func empty() {
        #expect(DropPathResolver.resolve("") == .reject("Empty drop"))
        #expect(DropPathResolver.resolve("   ") == .reject("Empty drop"))
    }

    @Test("https URL accepted with host label")
    func httpsURL() {
        let o = DropPathResolver.resolve("https://example.com/path")
        guard case .accept(let c) = o else {
            Issue.record("expected accept, got \(o)")
            return
        }
        #expect(c.label == "example.com")
        #expect(c.target == "https://example.com/path")
    }

    @Test("existing app path accepted")
    func appPath() {
        let path = "/System/Applications/Utilities/Terminal.app"
        guard FileManager.default.fileExists(atPath: path) else { return }
        let o = DropPathResolver.resolve(path)
        guard case .accept(let c) = o else {
            Issue.record("expected accept for Terminal.app")
            return
        }
        #expect(c.label == "Terminal")
        #expect(c.target.hasSuffix("Terminal.app"))
    }

    @Test("file URL form")
    func fileURL() {
        let path = "/System/Applications/Utilities/Terminal.app"
        guard FileManager.default.fileExists(atPath: path) else { return }
        let o = DropPathResolver.resolve(URL(fileURLWithPath: path).absoluteString)
        guard case .accept(let c) = o else {
            Issue.record("expected accept for file URL")
            return
        }
        #expect(c.label == "Terminal")
    }

    @Test("resolveFirst prefers first accept")
    func resolveFirst() {
        let path = "/System/Applications/Utilities/Terminal.app"
        guard FileManager.default.fileExists(atPath: path) else { return }
        let o = DropPathResolver.resolveFirst(of: ["", path, "https://x.test"])
        guard case .accept(let c) = o else {
            Issue.record("expected accept")
            return
        }
        #expect(c.label == "Terminal")
    }

    @Test("garbage rejects")
    func garbage() {
        let o = DropPathResolver.resolve("not-a-path-or-url")
        guard case .reject = o else {
            Issue.record("expected reject")
            return
        }
    }
}
