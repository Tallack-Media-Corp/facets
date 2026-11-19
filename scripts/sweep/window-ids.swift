// window-ids <pid>: the ids of a process's normal windows (layer 0, bigger than an
// icon), newest first, for `screencapture -l`. Lists windows on every Space, though
// screencapture may still fail on a window that isn't on the current one.
import CoreGraphics
import Foundation

guard CommandLine.arguments.count == 2, let pid = Int(CommandLine.arguments[1]) else {
    print("usage: window-ids <pid>"); exit(2)
}
let windows = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
for window in windows {
    guard window[kCGWindowOwnerPID as String] as? Int == pid,
          window[kCGWindowLayer as String] as? Int == 0,
          let bounds = window[kCGWindowBounds as String] as? [String: Double],
          (bounds["Width"] ?? 0) > 50, (bounds["Height"] ?? 0) > 50,
          let id = window[kCGWindowNumber as String] as? Int else { continue }
    print("\(id)\t\(window[kCGWindowName as String] as? String ?? "")")
}
