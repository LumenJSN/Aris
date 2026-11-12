//
//  ArisPreferenceStorage.swift
//  Aris
//
//  How the choice preferences sit in the defaults, in the shapes older builds wrote (cleanroom-specs/QUESTIONS A16):
//  `displayMode` as a JSON string ("\"activeDisplay\""), the others as their raw strings. Both forms read.
//

import Defaults

struct ArisRawChoiceBridge<Value: RawRepresentable>: Defaults.Bridge where Value.RawValue == String {
    /// Write the JSON-string form instead of the raw string.
    var json = false

    func serialize(_ value: Value?) -> String? { value.flatMap { ArisRawChoice.encode($0, json: json) } }

    func deserialize(_ object: String?) -> Value? { object.flatMap(ArisRawChoice.decode) }
}

extension DisplayMode: Defaults.Serializable { static let bridge = ArisRawChoiceBridge<DisplayMode>(json: true) }
extension HideNotchOption: Defaults.Serializable { static let bridge = ArisRawChoiceBridge<HideNotchOption>() }
extension SneakPeekStyle: Defaults.Serializable { static let bridge = ArisRawChoiceBridge<SneakPeekStyle>() }
extension MediaControllerType: Defaults.Serializable { static let bridge = ArisRawChoiceBridge<MediaControllerType>() }
extension WindowHeightMode: Defaults.Serializable { static let bridge = ArisRawChoiceBridge<WindowHeightMode>() }
extension SliderColorEnum: Defaults.Serializable { static let bridge = ArisRawChoiceBridge<SliderColorEnum>() }
extension AppLanguage: Defaults.Serializable { static let bridge = ArisRawChoiceBridge<AppLanguage>() }
