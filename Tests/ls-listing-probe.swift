// ls-listing-proof.sh's probe: a program that sits in an app's Contents/MacOS as aris-agent does, settles its listing
// as aris-agent does first thing (argument "settled") or not ("bare"), then makes the AppKit calls measured to put a
// process into LaunchServices' list (the screens, NSApplication), prints its pid and waits a moment to be looked at.
// No window, no key, no other app touched.
import AppKit

if CommandLine.arguments.dropFirst().first == "settled" { ArisHelperListing.settle() }
_ = NSScreen.screens.count
_ = NSApplication.shared
print(getpid())
fflush(stdout)
Thread.sleep(forTimeInterval: 3)
