//
//  ArisDisplayBrightness.swift
//  Aris
//
//  Screen brightness in the helper. DisplayServices (a private framework, its functions looked up at run time) works
//  on Apple displays; IOKit's display parameters are the fallback for displays that publish an IODisplayConnect
//  service. Which display: the main one if its brightness can be read, else the first built-in, else main.
//

import CoreGraphics
import Foundation
import IOKit
import IOKit.graphics

/// The brightness calls on one display, so the choice and the arithmetic can be checked without hardware.
protocol ArisBrightnessBackend {
    func level(of display: CGDirectDisplayID) -> Float?
    func setLevel(_ level: Float, of display: CGDirectDisplayID) -> Bool
    /// Moves the level by `delta` (the system's smooth change); nil when unsupported, so the caller does it by hand.
    func nudge(by delta: Float, of display: CGDirectDisplayID) -> Bool?
    func mainDisplay() -> CGDirectDisplayID
    func onlineDisplays() -> [CGDirectDisplayID]
    func isBuiltin(_ display: CGDirectDisplayID) -> Bool
    func supportsBrightness(_ display: CGDirectDisplayID) -> Bool
}

struct ArisDisplayBrightness {
    let backend: ArisBrightnessBackend

    /// The main display if it supports brightness, else the first online built-in display, else main.
    func display() -> CGDirectDisplayID {
        let main = backend.mainDisplay()
        if backend.supportsBrightness(main) { return main }
        return backend.onlineDisplays().first(where: backend.isBuiltin) ?? main
    }

    func level() -> Float? { backend.level(of: display()) }

    func set(_ level: Float) -> Bool { backend.setLevel(min(1, max(0, level)), of: display()) }

    /// The level after moving it by `delta`.
    func adjust(by delta: Float) -> Float? {
        let target = display()
        if backend.nudge(by: delta, of: target) == true { return backend.level(of: target) }
        guard let current = backend.level(of: target) else { return nil }
        let next = min(1, max(0, current + delta))
        return backend.setLevel(next, of: target) ? next : nil
    }
}

/// The real displays: DisplayServices first, IOKit second (on the IODisplayConnect service of the same display,
/// matched by vendor and product number).
struct ArisSystemBrightness: ArisBrightnessBackend {
    private typealias GetFunction = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
    private typealias SetFunction = @convention(c) (CGDirectDisplayID, Float) -> Int32
    private typealias CanFunction = @convention(c) (CGDirectDisplayID) -> Bool

    private static let framework = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_LAZY)

    private static func symbol<T>(_ name: String, as type: T.Type) -> T? {
        guard let framework, let pointer = dlsym(framework, name) else { return nil }
        return unsafeBitCast(pointer, to: type)
    }

    private static let getBrightness = symbol("DisplayServicesGetBrightness", as: GetFunction.self)
    private static let setBrightness = symbol("DisplayServicesSetBrightness", as: SetFunction.self)
    private static let setBrightnessSmooth = symbol("DisplayServicesSetBrightnessSmooth", as: SetFunction.self)
    private static let canChangeBrightness = symbol("DisplayServicesCanChangeBrightness", as: CanFunction.self)

    func level(of display: CGDirectDisplayID) -> Float? {
        var value: Float = 0
        if let get = Self.getBrightness, get(display, &value) == 0 { return value }
        return Self.ioDisplayLevel(display)
    }

    func setLevel(_ level: Float, of display: CGDirectDisplayID) -> Bool {
        if let set = Self.setBrightness, set(display, level) == 0 { return true }
        return Self.setIODisplayLevel(level, display)
    }

    func nudge(by delta: Float, of display: CGDirectDisplayID) -> Bool? {
        guard let smooth = Self.setBrightnessSmooth else { return nil }
        return smooth(display, delta) == 0 ? true : nil
    }

    func mainDisplay() -> CGDirectDisplayID { CGMainDisplayID() }

    func onlineDisplays() -> [CGDirectDisplayID] {
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(0, nil, &count) == .success, count > 0 else { return [] }
        var displays = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetOnlineDisplayList(count, &displays, &count) == .success else { return [] }
        return Array(displays.prefix(Int(count)))
    }

    func isBuiltin(_ display: CGDirectDisplayID) -> Bool { CGDisplayIsBuiltin(display) != 0 }

    /// DisplayServices can change it or read it, or the display has its own IODisplayConnect service.
    func supportsBrightness(_ display: CGDirectDisplayID) -> Bool {
        if let can = Self.canChangeBrightness, can(display) { return true }
        var value: Float = 0
        if let get = Self.getBrightness, get(display, &value) == 0 { return true }
        return Self.withDisplayService(display) { _ in true } ?? false
    }

    // MARK: IOKit

    /// Runs `body` on the IODisplayConnect service whose vendor and product match the display; nil when none does.
    private static func withDisplayService<T>(_ display: CGDirectDisplayID, _ body: (io_service_t) -> T?) -> T? {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IODisplayConnect"), &iterator) == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(iterator) }
        let vendor = CGDisplayVendorNumber(display), product = CGDisplayModelNumber(display)
        while case let service = IOIteratorNext(iterator), service != 0 {
            defer { IOObjectRelease(service) }
            let info = IODisplayCreateInfoDictionary(service, IOOptionBits(kIODisplayOnlyPreferredName)).takeRetainedValue() as NSDictionary
            let serviceVendor = (info[kDisplayVendorID] as? NSNumber)?.uint32Value
            let serviceProduct = (info[kDisplayProductID] as? NSNumber)?.uint32Value
            if serviceVendor == vendor && serviceProduct == product { return body(service) }
        }
        return nil
    }

    private static func ioDisplayLevel(_ display: CGDirectDisplayID) -> Float? {
        withDisplayService(display) { service in
            var value: Float = 0
            return IODisplayGetFloatParameter(service, 0, kIODisplayBrightnessKey as CFString, &value) == kIOReturnSuccess ? value : nil
        }
    }

    private static func setIODisplayLevel(_ level: Float, _ display: CGDirectDisplayID) -> Bool {
        withDisplayService(display) { service in
            IODisplaySetFloatParameter(service, 0, kIODisplayBrightnessKey as CFString, level) == kIOReturnSuccess
        } ?? false
    }
}
