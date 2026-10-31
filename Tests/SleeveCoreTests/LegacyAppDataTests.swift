import Foundation
import Testing
@testable import SleeveCore

struct LegacyAppDataTests {
    @Test func movesOldDataOnlyWhenNothingIsInTheWay() throws {
        let fm = FileManager.default
        let base = fm.temporaryDirectory.appendingPathComponent("sleeve-migration-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: base) }
        let old = base.appendingPathComponent("Afterglow"), new = base.appendingPathComponent("Sleeve")
        try fm.createDirectory(at: old, withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: old.appendingPathComponent("settings.json"))

        #expect(LegacyAppData.move(old, to: new, fileManager: fm))
        #expect(fm.fileExists(atPath: new.appendingPathComponent("settings.json").path))
        #expect(!fm.fileExists(atPath: old.path))

        // A second copy of old data never replaces what Sleeve already has.
        try fm.createDirectory(at: old, withIntermediateDirectories: true)
        #expect(!LegacyAppData.move(old, to: new, fileManager: fm))
        #expect(fm.fileExists(atPath: new.appendingPathComponent("settings.json").path))
    }
}
