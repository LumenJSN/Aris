//
//  ArisNotchSpace.swift
//  Aris
//
//  A private window space at the highest absolute level, shown for the app's life, that every notch window joins so
//  the notch draws over full-screen apps. Built on CoreGraphics Services' private space calls.
//

import AppKit

@_silgen_name("_CGSDefaultConnection") private func ArisCGSDefaultConnection() -> Int32
@_silgen_name("CGSSpaceCreate") private func ArisCGSSpaceCreate(_ connection: Int32, _ flag: Int32, _ options: CFDictionary?) -> UInt64
@_silgen_name("CGSSpaceSetAbsoluteLevel") private func ArisCGSSpaceSetAbsoluteLevel(_ connection: Int32, _ space: UInt64, _ level: Int32) -> Int32
@_silgen_name("CGSShowSpaces") private func ArisCGSShowSpaces(_ connection: Int32, _ spaces: CFArray) -> Int32
@_silgen_name("CGSHideSpaces") private func ArisCGSHideSpaces(_ connection: Int32, _ spaces: CFArray) -> Int32
@_silgen_name("CGSSpaceDestroy") private func ArisCGSSpaceDestroy(_ connection: Int32, _ space: UInt64) -> Int32
@_silgen_name("CGSAddWindowsToSpaces") private func ArisCGSAddWindowsToSpaces(_ connection: Int32, _ windows: CFArray, _ spaces: CFArray) -> Int32
@_silgen_name("CGSRemoveWindowsFromSpaces") private func ArisCGSRemoveWindowsFromSpaces(_ connection: Int32, _ windows: CFArray, _ spaces: CFArray) -> Int32

@MainActor
final class ArisNotchSpace {
    static let shared = ArisNotchSpace(level: Int32.max)

    private let connection: Int32
    private let space: UInt64
    private var destroyed = false

    private init(level: Int32) {
        connection = ArisCGSDefaultConnection()
        space = ArisCGSSpaceCreate(connection, 1, nil)
        _ = ArisCGSSpaceSetAbsoluteLevel(connection, space, level)
        _ = ArisCGSShowSpaces(connection, [space] as CFArray)
    }

    func add(_ window: NSWindow) {
        guard !destroyed else { return }
        _ = ArisCGSAddWindowsToSpaces(connection, [window.windowNumber] as CFArray, [space] as CFArray)
    }

    func remove(_ window: NSWindow) {
        guard !destroyed else { return }
        _ = ArisCGSRemoveWindowsFromSpaces(connection, [window.windowNumber] as CFArray, [space] as CFArray)
    }

    /// Hides and destroys the space (at quit).
    func destroy() {
        guard !destroyed else { return }
        destroyed = true
        _ = ArisCGSHideSpaces(connection, [space] as CFArray)
        _ = ArisCGSSpaceDestroy(connection, space)
    }
}
