import Foundation
import WeatherKit
import CoreLocation
import Observation

/// Today's weather from Apple Weather (WeatherKit), using your approximate location.
@MainActor @Observable
final class KeelWeather {
    static let shared = KeelWeather()

    struct Today {
        var temperature: String
        var high: String
        var low: String
        var symbol: String
        var condition: String
        var rainChance: Int
        var rainStartsAt: Date?
        /// One line for the planner, e.g. "18°, partly cloudy, rain likely from 3 PM".
        var plannerLine: String {
            var s = "\(temperature), \(condition.lowercased()), high \(high)"
            if let r = rainStartsAt { s += ", rain likely from \(r.formatted(date: .omitted, time: .shortened))" }
            return s
        }
    }

    var today: Today?
    var logoLight: URL?
    var logoDark: URL?
    var legalURL: URL?
    private let manager = CLLocationManager()
    private var lastFetch: Date?

    func refresh() async {
        if let last = lastFetch, Date().timeIntervalSince(last) < 30 * 60, today != nil { return }
        if manager.authorizationStatus == .notDetermined { manager.requestWhenInUseAuthorization() }
        guard let location = await currentLocation() else { return }
        do {
            let w = try await WeatherService.shared.weather(for: location)
            let style = Measurement<UnitTemperature>.FormatStyle(width: .narrow, usage: .weather, numberFormatStyle: .number.precision(.fractionLength(0)))
            let day = w.dailyForecast.first
            let rain = w.hourlyForecast.forecast.prefix(12).first { $0.precipitationChance >= 0.5 && $0.date > Date() }
            today = Today(
                temperature: w.currentWeather.temperature.formatted(style),
                high: day?.highTemperature.formatted(style) ?? "",
                low: day?.lowTemperature.formatted(style) ?? "",
                symbol: w.currentWeather.symbolName,
                condition: w.currentWeather.condition.description,
                rainChance: Int((day?.precipitationChance ?? 0) * 100),
                rainStartsAt: rain?.date)
            if logoLight == nil, let a = try? await WeatherService.shared.attribution {
                logoLight = a.combinedMarkLightURL
                logoDark = a.combinedMarkDarkURL
                legalURL = a.legalPageURL
            }
            lastFetch = Date()
        } catch {
            // Weather is a nice-to-have; Today simply hides it if unavailable.
        }
    }

    private func currentLocation() async -> CLLocation? {
        if let l = manager.location, Date().timeIntervalSince(l.timestamp) < 3 * 3600 { return l }
        do {
            for try await update in CLLocationUpdate.liveUpdates(.default) {
                if let l = update.location { return l }
                if update.authorizationDenied { return nil }
            }
        } catch {}
        return nil
    }
}
