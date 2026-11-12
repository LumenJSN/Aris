//
//  ArisBriefCommand.swift
//  aris-tools
//
//  `brief`: the morning brief's facts as JSON for the notch (ArisBrief): home weather now, what's still due on
//  Canvas (soonest three) and unread announcements. A part that can't be read is left out, not an error.
//

import Foundation

func brief(_ args: [String]) {
    var weather: [String: Any]?
    // Home, or on a new Mac the time zone's city (never stopping: no weather is a brief without it).
    if let home = homePlace(korean: true, stopping: false)?.place,
       let forecast = tryFetch(ArisWeather.forecastURL(latitude: home.latitude, longitude: home.longitude, timezone: home.timezone, days: 1),
                               as: ArisWeather.Forecast.self) {
        weather = ["place": home.name, "temp": Int(forecast.current.temperature.rounded()),
                   "sky": ArisWeather.describe(code: forecast.current.code, korean: true),
                   // The sky's code too: the notch names it in English on an English Mac (ArisBrief).
                   "code": forecast.current.code,
                   "rain": (forecast.daily.rainChances.first ?? nil) ?? 0]
    }
    // Canvas that doesn't answer (or refuses its token) is left out; the weather stays (audit tools-11).
    let canvas = canvasIsSetUp() ? try? readCanvas().get() : nil
    let data = (try? JSONSerialization.data(withJSONObject: ArisCanvas.brief(weather: weather, canvas: canvas, now: Date()), options: [.sortedKeys])) ?? Data("{}".utf8)
    print(String(decoding: data, as: UTF8.self))
}

private func canvasIsSetUp() -> Bool {
    let folder = arisFolder.deletingLastPathComponent()
    return ["canvas-key", "canvas-host"].allSatisfy { FileManager.default.fileExists(atPath: folder.appendingPathComponent($0).path) }
}
