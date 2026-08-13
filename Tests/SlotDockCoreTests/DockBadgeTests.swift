import Foundation
import Testing
@testable import SlotDockCore

@Suite("DockBadge")
struct DockBadgeTests {
    @Test("StatusLabel dictionaries parse counts and empty labels")
    func parseStatusLabel() {
        #expect(DockBadgeParser.parseStatusLabel(nil) == nil)
        #expect(DockBadgeParser.parseStatusLabel(NSNull()) == nil)
        #expect(DockBadgeParser.parseStatusLabel(["label": ""]) == nil)
        #expect(DockBadgeParser.parseStatusLabel(["label": NSNull()]) == nil)
        #expect(DockBadgeParser.parseStatusLabel(["label": 0]) == nil)

        #expect(DockBadgeParser.parseStatusLabel(["label": 1]) == DockBadge(kind: .count(1), rawLabel: "1"))
        #expect(DockBadgeParser.parseStatusLabel(["label": "12"]) == DockBadge(kind: .count(12), rawLabel: "12"))
        #expect(DockBadgeParser.parseStatusLabel(["label": NSNumber(value: 3)]) == DockBadge(kind: .count(3), rawLabel: "3"))
        #expect(DockBadgeParser.parseStatusLabel(["label": "•"])?.kind == .mark)
        #expect(DockBadgeParser.parseString("  ") == nil)
        #expect(DockBadgeParser.parseString("99")?.count == 99)
    }

    @Test("display text overflows at 99+")
    func displayText() {
        let nine = DockBadge(kind: .count(9), rawLabel: "9")
        let hundred = DockBadge(kind: .count(100), rawLabel: "100")
        let mark = DockBadge(kind: .mark, rawLabel: "•")
        #expect(DockBadgeFormatting.displayText(nine) == "9")
        #expect(DockBadgeFormatting.displayText(hundred) == "99+")
        #expect(DockBadgeFormatting.displayText(mark) == "")
        #expect(DockBadgeFormatting.accessibilityText(nine) == "9 notifications")
        #expect(DockBadgeFormatting.accessibilityText(DockBadge(kind: .count(1), rawLabel: "1")) == "1 notification")
        #expect(DockBadgeFormatting.accessibilityText(mark) == "unread notifications")
    }

    @Test("snapshot matches bundle, path, then title")
    func snapshotLookup() {
        let snapshot = DockBadgeSnapshot(
            byBundle: ["com.openai.codex": DockBadge(kind: .count(1), rawLabel: "1")],
            byPath: [
                "/Applications/ChatGPT.app": DockBadge(kind: .count(1), rawLabel: "1"),
                "/Applications/Mail.app": DockBadge(kind: .count(4), rawLabel: "4"),
            ],
            byTitle: ["messages": DockBadge(kind: .mark, rawLabel: "•")]
        )
        let chatgpt = Slot(
            id: "sysdock:com.openai.codex:/Applications/ChatGPT.app",
            label: "ChatGPT",
            target: "/Applications/ChatGPT.app"
        )
        #expect(snapshot.badge(for: chatgpt)?.count == 1)

        let customChatGPT = Slot(
            id: "custom-gpt",
            label: "Other",
            target: "/Applications/ChatGPT.app"
        )
        #expect(snapshot.badge(for: customChatGPT)?.count == 1)

        let mail = Slot(id: "custom-mail", label: "Mail", target: "/Applications/Mail.app")
        #expect(snapshot.badge(for: mail)?.count == 4)

        let messages = Slot(id: "custom-msg", label: "Messages", target: "/Applications/Messages.app")
        #expect(snapshot.badge(for: messages)?.kind == .mark)

        let none = Slot(id: "x", label: "Notes", target: "/System/Applications/Notes.app")
        #expect(snapshot.badge(for: none) == nil)
    }

    @Test("progress lookup uses path then bundle")
    func progressLookup() {
        let snapshot = DockBadgeSnapshot(
            progressByBundle: ["com.apple.Safari": 0.25],
            progressByPath: ["/Applications/Mail.app": 0.6]
        )
        let mail = Slot(id: "m", label: "Mail", target: "/Applications/Mail.app")
        #expect(snapshot.progress(for: mail) == 0.6)
        let safari = Slot(
            id: "sysdock:com.apple.Safari:/Applications/Safari.app",
            label: "Safari",
            target: "/Applications/Safari.app"
        )
        #expect(snapshot.progress(for: safari) == 0.25)
    }

    @Test("snapshot uniquing keeps the later badge for collapsed keys")
    func uniquingDoesNotTrap() {
        let snapshot = DockBadgeSnapshot(
            byPath: [
                "/Applications/Mail.app": DockBadge(kind: .count(4), rawLabel: "4"),
                "/Applications/Mail.app/": DockBadge(kind: .count(5), rawLabel: "5"),
            ],
            byTitle: [
                "Messages": DockBadge(kind: .count(1), rawLabel: "1"),
                "messages": DockBadge(kind: .count(2), rawLabel: "2"),
            ]
        )
        #expect(snapshot.byPath.count == 1)
        #expect(snapshot.badge(for: Slot(id: "m", label: "Mail", target: "/Applications/Mail.app")) != nil)
        #expect(snapshot.byTitle.count == 1)
        #expect(snapshot.byTitle["messages"] != nil)
    }

    @Test("AX titles fill holes that Launch Services left empty")
    func mergeAX() {
        let ls = DockBadgeSnapshot(
            byBundle: ["com.tinyspeck.slackmacgap": DockBadge(kind: .count(2), rawLabel: "2")]
        )
        let ax = ["Messages": DockBadge(kind: .count(1), rawLabel: "1")]
        let merged = DockBadgeMerge.merging(launchServices: ls, accessibilityByTitle: ax)
        #expect(merged.byBundle["com.tinyspeck.slackmacgap"]?.count == 2)
        #expect(merged.byTitle["messages"]?.count == 1)
    }

    @Test("missing showNotificationBadges decodes on")
    func badgePrefDefault() throws {
        let decoded = try JSONDecoder().decode(DockPreferences.self, from: Data(#"{"edgeHover":true}"#.utf8))
        #expect(decoded.showNotificationBadges == true)
        #expect(DockPreferences.default.showNotificationBadges == true)

        let off = try JSONDecoder().decode(
            DockPreferences.self,
            from: Data(#"{"showNotificationBadges":false}"#.utf8)
        )
        #expect(off.showNotificationBadges == false)
    }

    @Test("ChatGPT and Codex sidecar tokens pick the live artwork")
    func sidecarTokens() {
        let available: Set<String> = ["chatgpt", "codex-dark-color", "codex-light"]
        #expect(
            DockIconSidecar.preferredToken(titles: ["ChatGPT"], available: available, dark: true)
                == "chatgpt"
        )
        #expect(
            DockIconSidecar.preferredToken(titles: ["Codex"], available: available, dark: true)
                == "codex-dark-color"
        )
        #expect(
            DockIconSidecar.preferredToken(titles: ["Codex"], available: available, dark: false)
                == "codex-light"
        )
        #expect(
            DockIconSidecar.preferredToken(titles: ["Notes"], available: available, dark: true)
                .isEmpty
        )
        #expect(
            DockIconSidecar.preferredToken(
                titles: ["Codex", "ChatGPT"],
                available: available,
                dark: true
            ) == "codex-dark-color"
        )
        #expect(DockIconSidecar.token(fromResourceName: "icon-codex-light.png") == "codex-light")
        #expect(DockIconSidecar.token(fromResourceName: "icon-chatgpt.icns") == "chatgpt")
        #expect(
            DockIconSidecar.preferredToken(
                titles: ["codex-system"],
                available: available,
                dark: true
            ) == "codex-dark-color"
        )
        #expect(DockBadgeParser.parseProgress(0.4) == 0.4)
        #expect(DockBadgeParser.parseProgress(40) == 0.4)
        #expect(DockBadgeParser.parseProgress(0) == nil)
        #expect(DockBadgeParser.parseProgress(1) == nil)
        #expect(DockBadgeParser.parseProgress(100) == nil)
    }

    @Test("AppIdentity reads bundle id from a real app wrapper")
    func bundleFromAppPath() {
        let safari = "/System/Applications/Safari.app"
        guard FileManager.default.fileExists(atPath: safari) else { return }
        #expect(AppIdentity.bundleIdentifier(forAppPath: safari) == "com.apple.Safari")

        let slot = Slot(id: "custom", label: "Safari", target: safari)
        #expect(AppIdentity.from(slot: slot).bundleIdentifier == "com.apple.Safari")
    }
}
