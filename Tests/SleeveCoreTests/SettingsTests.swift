import Foundation
import Testing
@testable import AfterglowCore

struct SettingsTests {
    @Test func roundTripsAllFields() throws {
        var settings = AppSettings()
        settings.glow.isEnabled = true
        settings.glow.style.preset = .spectrum
        settings.glow.displays = .specific([1, 2])
        settings.glow.customPresets = [CustomGlowPreset(name: "Night", style: GlowStyle())]
        settings.sources.priority = [.appleMusic, .spotify]
        let data = try JSONEncoder().encode(settings)
        #expect(try JSONDecoder().decode(AppSettings.self, from: data) == settings)
    }

    @Test func partialAndMistypedDocumentsKeepValidFields() throws {
        let json = """
        {"glow": {"isEnabled": true, "style": {"intensity": "loud", "spread": 200}, "futureField": 1}}
        """
        let decoded = try JSONDecoder().decode(AppSettings.self, from: Data(json.utf8))
        #expect(decoded.glow.isEnabled)
        #expect(decoded.glow.style.spread == 200)
        #expect(decoded.glow.style.intensity == GlowStyle().intensity)
        #expect(decoded.sources == SourceSettings())
    }

    @Test func newSourcesAreAppendedToSavedPriority() throws {
        let json = #"{"priority": ["appleMusic"]}"#
        let decoded = try JSONDecoder().decode(SourceSettings.self, from: Data(json.utf8))
        #expect(decoded.priority == [.appleMusic, .spotify])
    }

    @MainActor @Test func persistsToDisk() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString).appendingPathComponent("settings.json")
        let manager = SettingsManager(fileURL: url)
        manager.settings.glow.style.thickness = 21
        manager.saveNow()
        #expect(SettingsManager(fileURL: url).settings.glow.style.thickness == 21)
        try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
    }
}
