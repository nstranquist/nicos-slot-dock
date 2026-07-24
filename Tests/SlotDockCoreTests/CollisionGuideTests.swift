import Foundation
import Testing
@testable import SlotDockCore

@Suite("CollisionGuide")
struct CollisionGuideTests {
    @Test("default guide is complete with topics and actionable helpers")
    func complete() {
        #expect(CollisionGuide.isComplete(.default) == true)
        let g = CollisionGuide.default
        #expect(g.topics.count >= 5)
        #expect(g.actions.contains { $0.kind == .openSystemSettings })
        #expect(g.actions.contains { $0.kind == .appleScript && $0.payload.contains("autohide") })
        #expect(g.actions.contains { $0.kind == .defaultsCommand && $0.payload.contains("com.apple.dock") })
        #expect(!g.summary.isEmpty)
        for t in g.topics {
            #expect(!t.title.isEmpty)
            #expect(!t.recommendation.isEmpty)
        }
    }

    @Test("AppleScript helpers toggle autohide true and false")
    func scripts() {
        let enable = CollisionGuide.default.actions.first { $0.id == "enable-system-autohide" }
        let disable = CollisionGuide.default.actions.first { $0.id == "disable-system-autohide" }
        #expect(enable != nil)
        #expect(disable != nil)
        #expect(enable!.payload.contains("autohide of dock preferences to true"))
        #expect(disable!.payload.contains("autohide of dock preferences to false"))
    }

    @Test("show-delay helpers set autohide-delay and restart Dock")
    func showDelayHelpers() {
        let five = CollisionGuide.default.actions.first { $0.id == "raise-dock-delay-5s" }
        let never = CollisionGuide.default.actions.first { $0.id == "raise-dock-delay-never" }
        let reset = CollisionGuide.default.actions.first { $0.id == "reset-dock-delay" }
        #expect(five != nil)
        #expect(never != nil)
        #expect(reset != nil)
        #expect(five!.payload.contains("autohide-delay -float 5"))
        #expect(five!.payload.contains("killall Dock"))
        #expect(never!.payload.contains("autohide-delay -float 1000"))
        #expect(reset!.payload.contains("delete com.apple.dock autohide-delay"))
        let built = CollisionGuide.scriptRaiseDelay(seconds: 5)
        #expect(built.contains("autohide -bool true"))
        #expect(built.contains("autohide-delay -float 5"))
    }

    @Test("guide explains auto-hide still peeks on hover")
    func hoverStillShows() {
        let topic = CollisionGuide.default.topics.first { $0.id == "autohide-still-on-hover" }
        #expect(topic != nil)
        #expect(topic!.systemDockSide.lowercased().contains("hover") || topic!.systemDockSide.lowercased().contains("bottom"))
        #expect(CollisionGuide.hideDockShortcutGuide.contains("STILL shows")
            || CollisionGuide.hideDockShortcutGuide.contains("still peeks")
            || CollisionGuide.hideDockShortcutGuide.contains("STILL"))
    }

    @Test("shouldPrompt when autoHide pin or edgeHover")
    func shouldPrompt() {
        var p = DockPreferences.default
        p.autoHide = false
        p.pinOpen = false
        p.edgeHover = false
        #expect(CollisionGuide.shouldPrompt(for: p) == false)
        p.edgeHover = true
        #expect(CollisionGuide.shouldPrompt(for: p) == true)
        p.edgeHover = false
        p.pinOpen = true
        #expect(CollisionGuide.shouldPrompt(for: p) == true)
    }

    @Test("fullGuidanceText includes topic titles")
    func guidanceText() {
        let text = CollisionGuide.fullGuidanceText
        #expect(text.contains("Auto-hide"))
        #expect(text.contains("Edge hover"))
        #expect(text.contains("safe-area") || text.contains("Safe-area") || text.contains("Window safe-area"))
        #expect(text.contains("Turn Hiding On") || text.contains("hide"))
    }

    @Test("hideDockShortcutGuide has UI and terminal steps")
    func hideShortcutGuide() {
        let g = CollisionGuide.hideDockShortcutGuide
        #expect(g.contains("Turn Hiding On"))
        #expect(g.contains("Desktop & Dock"))
        #expect(g.contains("defaults write com.apple.dock autohide"))
        #expect(CollisionGuide.default.topics.contains { $0.id == "hide-system-dock" })
        #expect(CollisionGuide.default.actions.contains { $0.id == "enable-system-autohide" })
        #expect(CollisionGuide.default.actions.contains { $0.id == "shortcut-copy-hide-guide" })
    }
}
