//
//  ArisGlassPrivate.swift
//  Aris
//
//  PRIVATE AppKit API, and the only file that names any. The shipped look, `private-glass` (ArisGlassLook), makes
//  its notch glass with these calls; no other look reaches this file. Private API can change or vanish in any macOS
//  update and is not allowed in the App Store. So every call is made only when the object answers to it
//  (`responds(to:)`) and still takes the kind of value it took in macOS 26 (its argument's type is read from the
//  runtime first), each reports whether it took, and a part that did not take turns the notch to the public look
//  `clear-glass` (ArisGlassFallback): never a crash, a blank or a grey notch.
//
//  What each call does:
//    -[NSGlassEffectView set_variant:] 11         the variant that lets the screen show through the regular glass
//    -[NSGlassEffectView set_contentLensing:] 3   the lensing that bends the screen at the glass's edge
//    -[NSGlassEffectView _setPath:]               the notch's outline as a CGPath, again on every frame of a morph
//                                                 (the glass has the notch's own shape, not a rounded rectangle)
//    hasActiveAppearance, _hasActiveAppearance    the notch window's class gets getters that answer YES for that
//                                                 window (and the class's own answer for any other), then
//                                                 -[NSWindow _setHasActiveAppearance:] YES; again when the app
//                                                 becomes active or resigns and when the space changes
//  The override is per window: the class's getters are replaced once, and they answer YES only for a window that
//  carries the mark, which is taken off again when the look or the window goes.
//

import AppKit
import ObjectiveC

@MainActor
enum ArisGlassPrivate {
    private typealias SetInteger = @convention(c) (AnyObject, Selector, Int) -> Void
    private typealias GetInteger = @convention(c) (AnyObject, Selector) -> Int
    private typealias SetFlag = @convention(c) (AnyObject, Selector, Bool) -> Void
    private typealias SetPath = @convention(c) (AnyObject, Selector, CGPath?) -> Void
    private typealias GetFlag = @convention(c) (AnyObject, Selector) -> Bool

    /// Marks a window whose active appearance is forced (an NSNumber true).
    private static let forcedKey = UnsafeRawPointer(UnsafeMutablePointer<UInt8>.allocate(capacity: 1))
    /// "class.selector" for each getter already installed, so a class gets each once.
    private static var installedGetters: Set<String> = []
    private static let forcedWindows = NSHashTable<NSWindow>.weakObjects()
    private static var observers: [NSObjectProtocol] = []

    /// Which private parts this macOS has, asked of a glass view that is never shown: each call is made for real and
    /// read back where AppKit lets it be.
    static func probe() -> ArisGlassParts {
        guard #available(macOS 26.0, *) else { return .none }
        let glass = NSGlassEffectView(frame: NSRect(x: 0, y: 0, width: 8, height: 8))
        let took = configure(glass)
        // Without `_setPath:` the glass cannot have the notch's outline.
        let path = setPath(glass, CGPath(rect: glass.bounds, transform: nil))
        // Forcing the active appearance needs the window's own getter and setter.
        let active = NSWindow.instancesRespond(to: NSSelectorFromString("_hasActiveAppearance"))
            && NSWindow.instancesRespond(to: NSSelectorFromString("_setHasActiveAppearance:"))
        return ArisGlassParts(glassView: true, variant: took.variant, lensing: took.lensing, path: path, activeAppearance: active)
    }

    /// The glass variant and content lensing on an `NSGlassEffectView` (variant 11, content lensing 3). What took.
    @discardableResult
    static func configure(_ glass: NSView) -> (variant: Bool, lensing: Bool) {
        (setInteger(glass, "set_variant:", readBack: "_variant", ArisGlassLook.privateVariant),
         setInteger(glass, "set_contentLensing:", readBack: "_contentLensing", ArisGlassLook.privateContentLensing))
    }

    /// Gives the glass the notch's own outline, in the glass view's coordinates, every frame. False when the system
    /// has no such call.
    @discardableResult
    static func setPath(_ glass: NSView, _ path: CGPath?) -> Bool {
        let selector = NSSelectorFromString("_setPath:")
        guard glass.responds(to: selector), takes(glass, selector, "^{CGPath=}"), let imp = glass.method(for: selector) else { return false }
        unsafeBitCast(imp, to: SetPath.self)(glass, selector, path)
        return true
    }

    /// Keeps `window`'s glass in its active look while it isn't the key window (`on`), or gives that back to AppKit.
    /// Only this window is touched: the getters answer for a marked window alone. False when it could not be forced.
    @discardableResult
    static func forceActiveAppearance(_ window: NSWindow, on: Bool) -> Bool {
        objc_setAssociatedObject(window, forcedKey, on ? NSNumber(value: true) : nil, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        if on {
            guard let windowClass: AnyClass = object_getClass(window) else { return false }
            installGetter(on: windowClass, "hasActiveAppearance")
            installGetter(on: windowClass, "_hasActiveAppearance")
            forcedWindows.add(window)
            watchActivation()
            return setFlag(window, "_setHasActiveAppearance:", true) && isForced(window)
        }
        forcedWindows.remove(window)
        return setFlag(window, "_setHasActiveAppearance:", window.isKeyWindow)
    }

    /// Whether `window` now answers that its appearance is active whatever its key state: the mark is on it and its
    /// class has the getter (the tests and the fallback read it).
    static func isForced(_ window: NSWindow) -> Bool {
        let selector = NSSelectorFromString("_hasActiveAppearance")
        guard (objc_getAssociatedObject(window, forcedKey) as? NSNumber)?.boolValue == true,
              window.responds(to: selector), returns(window, selector, "B"), let imp = window.method(for: selector) else { return false }
        return unsafeBitCast(imp, to: GetFlag.self)(window, selector)
    }

    /// Sets an integer through `name` and, where the object can be asked through `readBack`, checks that it held.
    private static func setInteger(_ object: NSObject, _ name: String, readBack: String, _ value: Int) -> Bool {
        let selector = NSSelectorFromString(name)
        guard object.responds(to: selector), takes(object, selector, "q"), let imp = object.method(for: selector) else { return false }
        unsafeBitCast(imp, to: SetInteger.self)(object, selector, value)
        let getter = NSSelectorFromString(readBack)
        guard object.responds(to: getter), returns(object, getter, "q"), let read = object.method(for: getter) else { return true }
        return unsafeBitCast(read, to: GetInteger.self)(object, getter) == value
    }

    @discardableResult
    private static func setFlag(_ object: NSObject, _ name: String, _ value: Bool) -> Bool {
        let selector = NSSelectorFromString(name)
        guard object.responds(to: selector), takes(object, selector, "B"), let imp = object.method(for: selector) else { return false }
        unsafeBitCast(imp, to: SetFlag.self)(object, selector, value)
        return true
    }

    /// Whether `selector` on `object` still takes one argument of the Objective-C type `type` (qualifiers such as
    /// const aside): a private method whose argument changed kind is treated as gone, not called with the wrong one.
    private static func takes(_ object: NSObject, _ selector: Selector, _ type: String) -> Bool {
        guard let method = class_getInstanceMethod(object_getClass(object), selector), method_getNumberOfArguments(method) == 3,
              let argument = method_copyArgumentType(method, 2) else { return false }
        defer { free(argument) }
        return String(cString: argument).drop { "rnNoORV".contains($0) } == type
    }

    /// Whether `selector` on `object` still returns the Objective-C type `type`.
    private static func returns(_ object: NSObject, _ selector: Selector, _ type: String) -> Bool {
        guard let method = class_getInstanceMethod(object_getClass(object), selector) else { return false }
        let result = method_copyReturnType(method)
        defer { free(result) }
        return String(cString: result).drop { "rnNoORV".contains($0) } == type
    }

    /// On `windowClass`: `name` answers true for a window marked forced, and what it answered before for any other
    /// (class_addMethod, else class_replaceMethod).
    private static func installGetter(on windowClass: AnyClass, _ name: String) {
        let id = "\(ObjectIdentifier(windowClass).hashValue).\(name)"
        guard !installedGetters.contains(id) else { return }
        installedGetters.insert(id)
        let selector = NSSelectorFromString(name)
        let method = class_getInstanceMethod(windowClass, selector)
        let original = method.map { method_getImplementation($0) }
        let key = forcedKey
        let block: @convention(block) (AnyObject) -> Bool = { window in
            if (objc_getAssociatedObject(window, key) as? NSNumber)?.boolValue == true { return true }
            guard let original else { return false }
            return unsafeBitCast(original, to: GetFlag.self)(window, selector)
        }
        let imp = imp_implementationWithBlock(block)
        if let method, let types = method_getTypeEncoding(method) {
            if !class_addMethod(windowClass, selector, imp, types) { class_replaceMethod(windowClass, selector, imp, types) }
        } else {
            class_addMethod(windowClass, selector, imp, "B@:")
        }
    }

    /// AppKit sets a window's active appearance again when the app comes forward or steps back and when the space
    /// changes: say it again each time.
    private static func watchActivation() {
        guard observers.isEmpty else { return }
        let reassert: @Sendable (Notification) -> Void = { _ in
            Task { @MainActor in
                for window in forcedWindows.allObjects { setFlag(window, "_setHasActiveAppearance:", true) }
            }
        }
        let center = NotificationCenter.default
        observers = [
            center.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main, using: reassert),
            center.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main, using: reassert),
            NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil,
                                                              queue: .main, using: reassert),
        ]
    }
}
