import Foundation
import Testing

/// The app and the Get Model Dimensions shortcut read the same default.
@Suite struct MeasurementUnitsTests {
    let suite = "FacetsTests-\(UUID().uuidString)"

    @Test func unsetFollowsTheLocale() throws {
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        #expect(MeasurementUnits.saved(in: defaults, locale: Locale(identifier: "en_US")) == .inches)
        #expect(MeasurementUnits.saved(in: defaults, locale: Locale(identifier: "de_DE")) == .millimetres)
    }

    @Test func setWinsOverTheLocale() throws {
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("millimetres", forKey: "viewer.units")
        #expect(MeasurementUnits.saved(in: defaults, locale: Locale(identifier: "en_US")) == .millimetres)
    }
}
