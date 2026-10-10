#if DEBUG
import Foundation

/// Opens a specific screen at launch for App Store screenshots, e.g. `-TueScreenshotScene detail`.
enum ScreenshotScene: String {
    case list
    case detail
    case filter
    case search
    case editor
    case labels

    static var current: ScreenshotScene? {
        UserDefaults.standard.string(forKey: "TueScreenshotScene").flatMap(ScreenshotScene.init(rawValue:))
    }
}
#endif
