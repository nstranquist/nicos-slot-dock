import Foundation
import Testing
@testable import SlotDockCore

@Suite("Single instance + process identity")
struct SingleInstanceAndProcessTests {
    @Test("claim when no live peers")
    func claimAlone() {
        let d = SingleInstancePolicy.decide(selfPID: 100, peers: [])
        #expect(d == .claim)
        let d2 = SingleInstancePolicy.decide(
            selfPID: 100,
            peers: [(pid: 100, isFinished: false), (pid: 99, isFinished: true)]
        )
        #expect(d2 == .claim)
    }

    @Test("handoff to lowest live peer PID")
    func handoffOldest() {
        let d = SingleInstancePolicy.decide(
            selfPID: 300,
            peers: [
                (pid: 200, isFinished: false),
                (pid: 100, isFinished: false),
                (pid: 50, isFinished: true),
            ]
        )
        #expect(d == .handoff(existingPID: 100))
    }

    @Test("process identity matches SlotDock binary paths")
    func processIdentity() {
        #expect(SlotDockProcessIdentity.matchesProcessCommand(
            "/Users/example/src/nicos-slot-dock/.build/app/Nicos Slot Dock.app/Contents/MacOS/SlotDock"
        ))
        #expect(SlotDockProcessIdentity.matchesProcessCommand(
            "/Applications/Nicos Slot Dock.app/Contents/MacOS/SlotDock"
        ))
        #expect(SlotDockProcessIdentity.matchesProcessCommand(
            "/Applications/Slot Dock.app/Contents/MacOS/SlotDock"
        ))
        #expect(!SlotDockProcessIdentity.matchesProcessCommand(
            "rg SlotDock apps/desktop/nicos-slot-dock"
        ))
        #expect(!SlotDockProcessIdentity.matchesProcessCommand(
            "/usr/bin/swift test --package-path apps/desktop/nicos-slot-dock"
        ))
        #expect(!SlotDockProcessIdentity.matchesProcessCommand("/tmp/SlotDock"))
        #expect(!SlotDockProcessIdentity.matchesProcessCommand("SlotDock"))
        #expect(SlotDockProcessIdentity.bundleIdentifier == "com.nstranquist.nicos-slot-dock")
        #expect(SlotDockProcessIdentity.processMatchKeys.allSatisfy { $0.contains(".app/Contents/MacOS/SlotDock") })
    }
}

@Suite("Hotkey registration report")
struct HotkeyRegistrationTests {
    @Test("userSummary surfaces failures for Settings")
    func summary() {
        var report = HotkeyRegistrationReport(globalEnabled: true, registeredCount: 1)
        #expect(report.hasProblems == false)
        #expect(report.userSummary.isEmpty)

        report.failures.append(
            HotkeyRegistrationFailure(
                actionID: 1,
                actionLabel: HotkeyRegistrationReport.label(forActionID: 1),
                statusCode: -9878,
                message: HotkeyRegistrationReport.explainStatus(-9878)
            )
        )
        #expect(report.hasProblems)
        #expect(report.userSummary.contains("Show / hide dock"))
        #expect(report.userSummary.contains("already in use") || report.userSummary.contains("-9878"))
        #expect(HotkeyRegistrationReport.label(forActionID: 12) == "Launch slot 2")
    }

    @Test("handler install failure alone is a problem")
    func handlerFail() {
        let report = HotkeyRegistrationReport(
            globalEnabled: true,
            handlerInstallFailed: true,
            handlerStatusCode: -50
        )
        #expect(report.hasProblems)
        #expect(report.userSummary.contains("handler"))
    }

    @Test("unsupported and duplicate shortcut statuses are explicit")
    func unsupportedAndDuplicateStatuses() {
        #expect(HotkeyRegistrationReport.explainStatus(-10001).contains("not supported"))
        #expect(HotkeyRegistrationReport.explainStatus(-10002).contains("conflicts"))
    }
}
