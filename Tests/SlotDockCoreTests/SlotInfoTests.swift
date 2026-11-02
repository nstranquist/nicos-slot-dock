import Foundation
import Testing
@testable import SlotDockCore

@Suite("SlotInfoSnapshotBuilder")
struct SlotInfoTests {
    @Test("application snapshot reads injected plist")
    func appFromPlist() {
        let info = SlotInfoSnapshotBuilder.build(
            label: "Safari",
            kind: .application,
            path: "/Applications/Safari.app",
            fileExists: { _ in true },
            fileByteCount: { _ in 1_048_576 },
            infoDictionary: { _ in
                [
                    "CFBundleIdentifier": "com.apple.Safari",
                    "CFBundleShortVersionString": "17.6",
                    "CFBundleVersion": "20621",
                ]
            }
        )
        #expect(info.exists)
        #expect(info.bundleIdentifier == "com.apple.Safari")
        #expect(info.version == "17.6")
        #expect(info.build == "20621")
        #expect(info.byteCount == 1_048_576)
        let text = SlotInfoFormatting.displayText(info)
        #expect(text.contains("Kind: Application"))
        #expect(text.contains("Version: 17.6 (20621)"))
        #expect(text.contains("Bundle ID: com.apple.Safari"))
        #expect(text.contains("Path: /Applications/Safari.app"))
        #expect(text.contains("Size:"))
    }

    @Test("missing file is marked and has no size")
    func missingFile() {
        let info = SlotInfoSnapshotBuilder.build(
            label: "Notes",
            kind: .file,
            path: "/tmp/missing.txt",
            fileExists: { _ in false },
            fileByteCount: { _ in 12 },
            infoDictionary: { _ in nil }
        )
        #expect(!info.exists)
        #expect(info.byteCount == nil)
        #expect(SlotInfoFormatting.displayText(info).contains("Missing on disk"))
        #expect(SlotInfoFormatting.kindLabel(.file) == "File")
    }

    @Test("info plist path is Contents/Info.plist")
    func plistPath() {
        #expect(
            SlotInfoSnapshotBuilder.infoPlistPath(appPath: "/Apps/X.app")
                == "/Apps/X.app/Contents/Info.plist"
        )
    }
}
