import Foundation
import Testing
@testable import SlotDockCore

@Suite("LaunchResolver")
struct LaunchRequestTests {
    @Test("resolves application path when file exists")
    func resolvesApplication() {
        let slot = Slot(id: "1", label: "Safari", target: "/Applications/Safari.app")
        let request = LaunchResolver.resolve(slot: slot) { path in
            path == "/Applications/Safari.app"
        } fileIsDirectory: { _ in
            true
        }
        #expect(request.kind == .application)
        #expect(request.resolvedTarget == "/Applications/Safari.app")
        #expect(request.isValid == true)
        #expect(request.slotID == "1")
        #expect(request.label == "Safari")

        let payload = LaunchResolver.openPayload(for: request)
        #expect(payload != nil)
        #expect(payload?.kind == .application)
        #expect(payload?.path == "/Applications/Safari.app")
        #expect(payload?.url.isFileURL == true)
        #expect(payload?.url.path == "/Applications/Safari.app")
    }

    @Test("resolves file path")
    func resolvesFile() {
        let slot = Slot(id: "f", label: "Readme", target: "/Users/me/readme.md")
        let request = LaunchResolver.resolve(slot: slot) { $0 == "/Users/me/readme.md" }
        #expect(request.kind == .file)
        #expect(request.isValid == true)
        let payload = LaunchResolver.openPayload(for: request)
        #expect(payload?.path == "/Users/me/readme.md")
    }

    @Test("resolves https URL")
    func resolvesURL() {
        let slot = Slot(id: "u", label: "Docs", target: "https://example.com/path")
        let request = LaunchResolver.resolve(slot: slot) { _ in false }
        #expect(request.kind == .url)
        #expect(request.isValid == true)
        #expect(request.resolvedTarget == "https://example.com/path")

        let payload = LaunchResolver.openPayload(for: request)
        #expect(payload != nil)
        #expect(payload?.kind == .url)
        #expect(payload?.url.absoluteString == "https://example.com/path")
        #expect(payload?.path == nil)
    }

    @Test("empty target is invalid unknown")
    func emptyTargetInvalid() {
        let slot = Slot(id: "e", label: "Empty", target: "   ")
        let request = LaunchResolver.resolve(slot: slot)
        #expect(request.kind == .unknown)
        #expect(request.isValid == false)
        #expect(LaunchResolver.openPayload(for: request) == nil)
    }

    @Test("missing file is invalid but still classified")
    func missingFileInvalid() {
        let slot = Slot(id: "m", label: "Missing", target: "/no/such/App.app")
        let request = LaunchResolver.resolve(slot: slot) { _ in false }
        #expect(request.kind == .application)
        #expect(request.isValid == false)
        #expect(LaunchResolver.openPayload(for: request) == nil)
    }

    @Test("tilde expands in path")
    func tildeExpands() {
        let slot = Slot(id: "t", label: "Home", target: "~/Documents/file.txt")
        let request = LaunchResolver.resolve(slot: slot) { path in
            path.contains("/Documents/file.txt") && !path.hasPrefix("~")
        }
        #expect(request.kind == .file)
        #expect(request.resolvedTarget.hasPrefix("/"))
        #expect(request.resolvedTarget.hasSuffix("/Documents/file.txt"))
        #expect(request.isValid == true)
    }

    @Test("file URL scheme resolves to path")
    func fileURLScheme() {
        let slot = Slot(id: "fu", label: "FU", target: "file:///Applications/Safari.app")
        let request = LaunchResolver.resolve(
            slot: slot,
            fileExists: { $0 == "/Applications/Safari.app" },
            fileIsDirectory: { _ in true }
        )
        #expect(request.kind == .application)
        #expect(request.resolvedTarget == "/Applications/Safari.app")
        #expect(request.isValid == true)
    }

    @Test("file URL application suffix is case insensitive and strips trailing slash")
    func uppercaseFileURLApplication() {
        let request = LaunchResolver.resolve(
            slot: Slot(id: "upper", label: "Example", target: "file:///Applications/Example.APP/"),
            fileExists: { $0 == "/Applications/Example.APP" },
            fileIsDirectory: { _ in true }
        )
        #expect(request.kind == .application)
        #expect(request.resolvedTarget == "/Applications/Example.APP")
        #expect(request.isValid == true)
    }

    @Test("relative file paths are rejected")
    func relativePathRejected() {
        let request = LaunchResolver.resolve(
            slot: Slot(id: "relative", label: "Relative", target: "Notes.app")
        ) { _ in true }
        #expect(request.kind == .application)
        #expect(request.isValid == false)
        #expect(request.resolvedTarget.hasPrefix("/"))
    }

    @Test("malformed HTTP URL is invalid")
    func malformedHTTP() {
        let request = LaunchResolver.resolve(slot: Slot(id: "bad", label: "Bad", target: "https://"))
        #expect(request.isValid == false)
    }

    @Test("regular file with app suffix is not classified as application")
    func regularAppFile() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("slot-dock-regular-\(UUID().uuidString).app")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data("not an app".utf8).write(to: url)
        let request = LaunchResolver.resolve(slot: Slot(id: "regular", label: "Regular", target: url.path))
        #expect(request.kind == .file)
        #expect(request.isValid == true)
    }
}
