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

    @Test("HTTP URL without a host is rejected")
    func malformedHTTP() {
        #expect(DropPathResolver.resolve("https://") == .reject("URL needs a host"))
    }

    @Test("application suffix matching is case insensitive")
    func uppercaseApplicationSuffix() {
        let o = DropPathResolver.resolve("/tmp/Example.APP")
        guard case .accept(let candidate) = o else {
            Issue.record("expected uppercase app suffix to be accepted")
            return
        }
        #expect(candidate.label == "Example")
    }

    @Test("existing regular file named app is rejected")
    func regularAppFileRejected() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("slot-dock-not-an-app-\(UUID().uuidString).app")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data("not an application bundle".utf8).write(to: url)
        #expect(DropPathResolver.resolve(url.path) == .reject("Application bundle is not a directory: \(url.lastPathComponent)"))
    }

    @Test("UTF-8 Internet Shortcut resolves to its URL")
    func internetShortcut() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("slot-dock-shortcut-\(UUID().uuidString).url")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data("[InternetShortcut]\nURL=https://example.com/docs\n".utf8).write(to: url)
        #expect(DropPathResolver.resolve(url.path) == .accept(.init(
            label: url.deletingPathExtension().lastPathComponent,
            target: "https://example.com/docs"
        )))
    }

    @Test("non-UTF-8 Internet Shortcut is rejected explicitly")
    func invalidInternetShortcutEncoding() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("slot-dock-shortcut-\(UUID().uuidString).url")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data([0xFF, 0xFE, 0x00, 0x01]).write(to: url)
        #expect(DropPathResolver.resolve(url.path) == .reject("Internet Shortcut is not valid UTF-8: \(url.lastPathComponent)"))
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
