import Wallpaper
import Cocoa

struct ScreenInfo: Codable, Equatable {
    var linkID = 0
    var screenName = ""
    var currentWallpaper = ""
    var currentScale: Wallpaper.Scale = .auto

    enum CodingKeys: String, CodingKey {
        case linkID
        case screenName
        case currentWallpaper
        case currentScale
    }

    var screen: NSScreen? {
        NSScreen.screens.first(where: { $0.localizedName == screenName})
    }

    init(linkID: Int, screenName: String, currentWallpaper: String, currentScale: Wallpaper.Scale) {
        self.linkID = linkID
        self.screenName = screenName
        self.currentWallpaper = currentWallpaper
        self.currentScale = currentScale
    }

    init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)

        linkID = try values.decode(Int.self, forKey: .linkID)
        screenName = try values.decode(String.self, forKey: .screenName)
        currentWallpaper = try values.decode(String.self, forKey: .currentWallpaper)

        let scale = try values.decode(String.self, forKey: .currentScale)
        currentScale = Wallpaper.Scale(rawValue: scale) ?? .auto
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        try container.encode(linkID, forKey: .linkID)
        try container.encode(screenName, forKey: .screenName)
        try container.encode(currentWallpaper, forKey: .currentWallpaper)
        try container.encode(currentScale.rawValue, forKey: .currentScale)
    }
}

actor WallpaperHelper {
}
