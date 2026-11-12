//
//  ArisHelperEntry.swift
//  Aris
//
//  The XPC service's entry point: listen as the bundle's service and never return.
//

import Foundation

@main
enum ArisHelperEntry {
    static func main() {
        let delegate = ArisHelperListener()
        let listener = NSXPCListener.service()
        listener.delegate = delegate
        listener.resume()
        withExtendedLifetime(delegate) { dispatchMain() }
    }
}
