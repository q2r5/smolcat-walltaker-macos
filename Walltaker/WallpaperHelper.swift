import Wallpaper
import Cocoa

struct ScreenInfo {
    var linkID = "0"
    var screenName = ""
    var currentWallpaper = ""
    var currentScale: Wallpaper.Scale = .auto

    var screen: NSScreen? {
        NSScreen.screens.first(where: { $0.localizedName == screenName})
    }
}


actor WallpaperHelper {
}
