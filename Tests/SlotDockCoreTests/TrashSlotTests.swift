import Foundation
import Testing
@testable import SlotDockCore

@Suite("TrashSlot")
struct TrashSlotTests {
    private let homeTrash = "/Users/me/.Trash"
    private let otherTrash = "/Volumes/USB/.Trashes/501"

    @Test("matches home trash path spellings, not by label")
    func matchesPaths() {
        #expect(TrashSlot.matches(path: homeTrash, canonicalPath: homeTrash))
        #expect(TrashSlot.matches(path: "/Users/me/.Trash/", canonicalPath: homeTrash))
        #expect(TrashSlot.matches(path: "file:///Users/me/.Trash", canonicalPath: homeTrash))
        #expect(!TrashSlot.matches(path: "/Users/me/Documents", canonicalPath: homeTrash))
        #expect(!TrashSlot.matches(path: "/Users/me/Trash", canonicalPath: homeTrash))

        let composed = TrashSlot.slot(path: homeTrash)
        #expect(composed.id == "trash")
        #expect(composed.label == "Trash")
        #expect(TrashSlot.matches(slot: composed, canonicalPath: homeTrash))

        let custom = Slot(id: "abc", label: "Trash", target: homeTrash)
        #expect(TrashSlot.matches(slot: custom, canonicalPath: homeTrash))

        let notes = Slot(id: "notes", label: "Trash", target: "/System/Applications/Notes.app")
        #expect(!TrashSlot.matches(slot: notes, canonicalPath: homeTrash))
    }

    @Test("directoryPaths keeps home first and dedupes volumes")
    func directories() {
        let paths = TrashSlot.directoryPaths(
            homeTrash: homeTrash,
            volumeRoots: ["/", "/Volumes/USB"],
            trashDirectoryForVolume: { root in
                root == "/Volumes/USB" ? otherTrash : homeTrash
            }
        )
        #expect(paths == [homeTrash, otherTrash])
    }

    @Test("empty ignores Finder metadata names")
    func emptyListing() {
        #expect(
            TrashSlot.isEmpty(at: [homeTrash], contentsOfDirectory: { _ in [".DS_Store", ".localized"] })
        )
        #expect(
            !TrashSlot.isEmpty(at: [homeTrash], contentsOfDirectory: { _ in [".DS_Store", "Old.pdf"] })
        )
        #expect(
            !TrashSlot.isEmpty(
                at: [homeTrash, otherTrash],
                contentsOfDirectory: { path in
                    path == otherTrash ? ["from-usb.txt"] : []
                }
            )
        )
        #expect(TrashSlot.iconCacheKey(isEmpty: true) == "empty")
        #expect(TrashSlot.iconCacheKey(isEmpty: false) == "full")
    }

    @Test("itemsToRemove lists every child, including metadata")
    func itemsToRemove() {
        let items = TrashSlot.itemsToRemove(
            in: [homeTrash],
            contentsOfDirectory: { _ in [".DS_Store", "Old.pdf"] }
        )
        #expect(items == ["\(homeTrash)/.DS_Store", "\(homeTrash)/Old.pdf"])
    }

    @Test("recycle policy rejects trash itself and nested trash items")
    func recyclePolicy() {
        let accepted = TrashRecyclePolicy.acceptedPaths(
            [
                "/Users/me/Desktop/shot.png",
                homeTrash,
                "\(homeTrash)/already-trashed.txt",
                "~/Desktop/note.txt",
                "relative.txt",
                "",
            ],
            trashDirectories: [homeTrash]
        )
        #expect(accepted.contains("/Users/me/Desktop/shot.png"))
        #expect(!accepted.contains(homeTrash))
        #expect(!accepted.contains("\(homeTrash)/already-trashed.txt"))
        #expect(!accepted.contains("relative.txt"))
    }

    @Test("compose appends trash last and skips a custom trash slot")
    func composeTrash() {
        let custom = [Slot(id: "c1", label: "Notes", target: "/System/Applications/Notes.app", sortOrder: 0)]
        let system = [SystemDockEntry(label: "Safari", path: "/Applications/Safari.app")]
        let withTrash = SlotComposer.compose(
            custom: custom,
            system: system,
            mode: .merge,
            includeTrash: true,
            trashPath: homeTrash
        )
        #expect(withTrash.count == 3)
        #expect(withTrash.last?.origin == .trash)
        #expect(withTrash.last?.slot.id == "trash")
        #expect(withTrash.last?.slot.target == homeTrash)

        let customTrash = [
            Slot(id: "mine", label: "Trash", target: homeTrash, sortOrder: 0),
        ]
        let deduped = SlotComposer.compose(
            custom: customTrash,
            system: [],
            mode: .off,
            includeTrash: true,
            trashPath: homeTrash
        )
        #expect(deduped.count == 1)
        #expect(deduped[0].origin == .custom)
        #expect(deduped[0].slot.id == "mine")
    }

    @Test("compose without includeTrash matches prior membership")
    func composeDefaultOmitsTrash() {
        let items = SlotComposer.compose(
            custom: [Slot(id: "c1", label: "Notes", target: "/n", sortOrder: 0)],
            system: [],
            mode: .off
        )
        #expect(items.count == 1)
        #expect(items[0].origin == .custom)
    }
}
