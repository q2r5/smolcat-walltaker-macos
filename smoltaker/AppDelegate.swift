import Cocoa
import ActionCableSwift
import Wallpaper
import OSLog
import SwiftUI
import UserNotifications
import UniformTypeIdentifiers

@main
class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    var statusItem: NSStatusItem!
    var windowController: NSWindowController!
    let wsLogger = Logger(subsystem: "online.smolcat.walltaker", category: "WebSocket")

    var client: ACClient? = nil
    var channel: ACChannel? = nil

    var currentWallpaper = ""
    var wallpaperPath: URL? = nil

    var vlcInstance: NSRunningApplication? = nil

    var canNotify = false

    var screens: [ScreenInfo] {
        get {
            let data = UserDefaults.standard.object(forKey: "screens") as? Data
            return (try? JSONDecoder().decode([ScreenInfo].self, from: data ?? Data())) ?? []
        }
        set {
            let encodedData = try? JSONEncoder().encode(newValue)
            UserDefaults.standard.set(encodedData, forKey: "screens")
        }
    }
    var linkID: Int {
        UserDefaults.standard.integer(forKey: "linkID")
    }
    var wallpaperScale: String? {
        UserDefaults.standard.string(forKey: "wallpaperScale")
    }
    var wallpaperScreen: String? {
        UserDefaults.standard.string(forKey: "wallpaperScreen")
    }
    var apiKey: String? {
        UserDefaults.standard.string(forKey: "apiKey")
    }
    var muted: Bool? {
        UserDefaults.standard.bool(forKey: "muted")
    }

    // MARK: - Lifecycle
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "photo.circle", accessibilityDescription: "smoltaker")
        }

        UNUserNotificationCenter.current().delegate = self

        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .provisional]) { allow, error in
            if let error {
                self.wsLogger.error("\(error.localizedDescription)")
            } else {
                self.canNotify = allow
                self.registerNotifications()
            }
        }

        if screens.isEmpty {
           screens = migrate()
        } else {
            screens = []
            screens = migrate()
        }

        UserDefaults.standard.addObserver(self, forKeyPath: "linkID", options: .new, context: nil)
        UserDefaults.standard.addObserver(self, forKeyPath: "wallpaperScale", options: .new, context: nil)
        UserDefaults.standard.addObserver(self, forKeyPath: "wallpaperScreen", options: .new, context: nil)
        UserDefaults.standard.addObserver(self, forKeyPath: "apiKey", options: .new, context: nil)

//        NSWorkspace.shared.notificationCenter.addObserver(self,
//                                                          selector: #selector(wakeFromSleep),
//                                                          name: NSWorkspace.didWakeNotification,
//                                                          object: nil)

        NSWorkspace.shared.notificationCenter.addObserver(self,
                                                          selector: #selector(willSwitchScenes),
                                                          name: NSWorkspace.activeSpaceDidChangeNotification,
                                                          object: nil)

        windowController = NSWindowController()
        setupMenus()
        createFolders()
        initClient()
        if screens.isEmpty {
            subscribeToChannel(for: linkID)
        } else {
            for screen in screens {
                subscribeToChannel(for: screen.linkID)
            }
        }
    }

    func applicationWillTerminate(_ aNotification: Notification) {
        try? channel?.unsubscribe()
        client?.disconnect()

        vlcInstance?.terminate()

        // Clean up old wallpapers on close
        guard let wallpaperPath else { return }
        let files = try? FileManager.default.contentsOfDirectory(at: wallpaperPath,
                                                                 includingPropertiesForKeys: [])

        var currentWallpapers: [String] = []
        screens.forEach {
            currentWallpapers.append($0.currentWallpaper)
        }

        files?.forEach {
            if currentWallpapers.contains($0.lastPathComponent) { return }
            if $0.lastPathComponent == currentWallpaper { return }
            try? FileManager.default.removeItem(at: $0)
        }
    }

    override func observeValue(forKeyPath keyPath: String?,
                               of object: Any?,
                               change: [NSKeyValueChangeKey : Any]?,
                               context: UnsafeMutableRawPointer?) {
        if keyPath == "linkID" {
            try? channel?.unsubscribe()
            subscribeToChannel(for: linkID)
        } else if keyPath == "wallpaperScale" || keyPath == "wallpaperScreen" {
            try? setWallpaper(to: currentWallpaper, for: linkID, force: true)
        } else if keyPath == "apiKey" {
            registerNotifications()
        } else {
            super.observeValue(forKeyPath: keyPath, of: object, change: change, context: context)
        }
    }

    // MARK: - Setup

    func setupMenus() {
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Settings", action: #selector(showSettings), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: ""))
        statusItem.menu = menu
    }

    func createFolders() {
        wallpaperPath = URL(filePath: NSTemporaryDirectory()).appending(path: "wallpapers",
                                                                        directoryHint: .isDirectory)
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: wallpaperPath!.path(),
                                          isDirectory: &isDirectory), isDirectory.boolValue {
            return
        } else {
            try? FileManager.default.createDirectory(at: wallpaperPath!,
                                                     withIntermediateDirectories: false)
        }
    }

    func migrate() -> [ScreenInfo] {
        guard let wallpaperScale,
              let wallpaperScreen else {
            return []
        }

        return [ScreenInfo(linkID: linkID,
                           screenName: wallpaperScreen,
                           currentWallpaper: "",
                           currentScale: Wallpaper.Scale(rawValue: wallpaperScale) ?? .auto)]
    }

    func initClient() {
        guard client == nil else {
            return
        }

        let clientOptions = ACClientOptions(debug: true, reconnect: true)
        client = ACClient(stringURL: "wss://walltaker.joi.how/cable", options: clientOptions)
    }

    func subscribeToChannel(for linkID: Int) {
        guard let client else {
            wsLogger.error("Attempting to subscribe without a client!")
            return
        }

        // Okay for now, will need rethinking for multi-screen (don't want multiple subscriptions to one channel)
        if let currentChannel = channel {
            if linkID == currentChannel.identifier["id"] as? Int {
                return
            } else {
                try? currentChannel.unsubscribe()
            }
        }

        let channelOptions = ACChannelOptions(buffering: true, autoSubscribe: true)
        let channel = client.makeChannel(name: "LinkChannel",
                                         identifier: ["id": linkID],
                                         options: channelOptions)

        channel.addOnSubscribe { (channel, optionalMessage) in
            do {
                try channel.sendMessage(actionName: "announce_client", data: ["client": "smoltaker"])
                try channel.sendMessage(actionName: "check")
            } catch {
                self.wsLogger.error("\(error.localizedDescription)")
            }
        }

        channel.addOnMessage { (channel, optionalMessage) in
            guard let message = optionalMessage?.message else { return }
            self.wsLogger.log("\(message, privacy: .public)")

            // If for some reason we get an error, force a recheck.
            // (temp workaround for until https://github.com/pupgray/walltaker/pull/65 lands)
            if message["success"] as? Int == 0 {
                try? channel.sendMessage(actionName: "check")
            } else {
                self.parse(message)
            }
        }
        self.channel = channel
    }

    func parse(_ message: [String: Any]) {
        guard let urlString = message["post_url"] as? String,
              let url = URL(string: urlString),
              let linkID = message["id"] as? Int else { return }

        let originalWallpaper = currentWallpaper
        let wallpaperFileName = url.lastPathComponent

        guard !wallpaperFileName.isEmpty,
              let wallpaperPath else { return }

        let fullPath = wallpaperPath.appending(path: wallpaperFileName)

        do {
            // If the file already exists, there's no need to redownload it
            if !FileManager.default.fileExists(atPath: fullPath.path()) {
                let imageData = try? Data(contentsOf: url)
                if let imageData = imageData {
                    try imageData.write(to: fullPath)
                }
            }

            vlcInstance?.terminate()

            let utis = UTType.types(tag: fullPath.pathExtension, tagClass: .filenameExtension, conformingTo: nil)

            if utis.contains(UTType.jpeg) ||
                utis.contains(UTType.png) ||
                utis.contains(UTType.bmp) {
                try setWallpaper(to: wallpaperFileName, for: linkID)
            } else {
                playVideoWallpaper(fileName: fullPath.path(), isGif: utis.contains(UTType.gif))
            }

            if canNotify,
               originalWallpaper != wallpaperFileName {
                let notifContent = UNMutableNotificationContent()
                notifContent.title = "Wallpaper Set"
                notifContent.body = "Set by: \(message["set_by"] ?? "anon")"
                notifContent.categoryIdentifier = "WALLPAPER_CHANGED"
                UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "online.smolcat.walltaker.set",
                                                                             content: notifContent,
                                                                             trigger: nil))
            }
        } catch {
            wsLogger.error("\(error.localizedDescription)")
        }
    }

    func setWallpaper(to fileName: String, for linkID: Int, force: Bool = false) throws {
        guard let wallpaperPath else {
            return
        }

        guard !screens.isEmpty else { return }
        let idx = 0

//        guard let idx = screens.firstIndex(where: { $0.linkID == linkID }) else {
//            return
//        }

        let wallpapers = try Wallpaper.get()
        if !force,
           wallpapers.contains(where: { $0 == wallpaperPath.appending(path: fileName) }) {
            // This image is already set as the wallpaper, don't bother resetting
            if currentWallpaper.isEmpty {
                currentWallpaper = fileName
            }
            return
        }

        var screen = Wallpaper.Screen.all
        switch screens[idx].screenName {
        case "all":
            screen = .all
        case "main":
            screen = .main
        default:
            if let selectedScreen = NSScreen.screens.first(where: { $0.localizedName == screens[idx].screenName} ) {
                screen = .nsScreens([selectedScreen])
            } else {
                screen = .all
            }
        }

        try Wallpaper.set(wallpaperPath.appending(path: fileName),
                          screen: screen,
                          scale: screens[idx].currentScale,
                          fillColor: .black)
        screens[idx].currentWallpaper = fileName
        currentWallpaper = fileName
    }

    func playVideoWallpaper(fileName: String, isGif: Bool = false) {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "org.videolan.vlc") else { return }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        configuration.hides = true
        configuration.addsToRecentItems = false
        var arguments = ["--loop",
                         "--video-wallpaper",
                         "--no-mouse-events",
                         "--no-video-title-show",
                         "--no-macosx-nativefullscreenmode",
                         "--no-macosx-statusicon",
                         "--macosx-continue-playback=2",
                         "--no-macosx-recentitems",
                         "--no-embedded-video",
                         "--no-keyboard-events",
                         "--video-title-timeout=0",
                         "--mouse-hide-timeout=0",
                         fileName]
        if muted ?? false {
            arguments.append("--no-audio")
        }

        if isGif {
            arguments.append("--demux avcodec")
        }
        configuration.arguments = arguments
        NSWorkspace.shared.openApplication(at: url, configuration: configuration) { app, err in
            if let err {
                self.wsLogger.error("\(err)")
                return
            }

            if let app {
                self.vlcInstance = app
            }
        }
        screens[0].currentWallpaper = fileName
        currentWallpaper = fileName
    }

    // MARK: - Selectors

    @objc
    func showSettings() {
        guard windowController.window == nil else {
            windowController.window?.makeKeyAndOrderFront(nil)
            return
        }

        let window = NSWindow(contentViewController: NSHostingController(rootView: ContentView(editingLinkID: String(linkID))))
        window.styleMask = [.titled, .closable]
        window.contentViewController?.preferredContentSize = NSSize(width: 300, height: 400)
        window.title = "Settings"
        window.center()
        windowController.window = window
        windowController.showWindow(nil)
        window.makeKeyAndOrderFront(nil)
    }

//    @objc
//    func wakeFromSleep() {
//        guard let client,
//              client.isConnected,
//              let channel else {
//            if screens.isEmpty {
//                subscribeToChannel(for: linkID)
//            } else {
//                for screen in screens {
//                    subscribeToChannel(for: screen.linkID)
//                }
//            }
//            return
//        }
//
//        try? channel.sendMessage(actionName: "check")
//    }

    @objc
    func willSwitchScenes() {
        guard !currentWallpaper.isEmpty,
              vlcInstance == nil else { return }

        do {
            try setWallpaper(to: currentWallpaper, for: linkID)
        } catch {
            wsLogger.error("\(error.localizedDescription)")
        }
    }

    // MARK: - Response

    enum ResponseType: String {
        case horny
        case disgust
        case came
        case ok

        var actionIdentifier: String {
            switch self {
            case .horny:
                return "HORNY_ACTION"
            case .disgust:
                return "DISGUST_ACTION"
            case .came:
                return "CAME_ACTION"
            case .ok:
                return "THANKS_ACTION"
            }
        }
    }

    func postResponse(response: ResponseType) {
        guard let url = URL(string: "https://walltaker.joi.how/api/links/\(linkID)/response.json"),
              let apiKey else { return }

        let postArray: [String:String] = ["api_key": apiKey,
                                          "type": response.rawValue,
                                          "text": ""]

        guard let postData = try? JSONEncoder().encode(postArray) else {
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        URLSession.shared.uploadTask(with: request, from: postData).resume()
    }

    // MARK: - Notifications

    func registerNotifications() {
        guard let apiKey,
              !apiKey.isEmpty else { return }

        let hornyAction = UNNotificationAction(identifier: ResponseType.horny.actionIdentifier,
                                               title: "Love it")
        let disgustAction = UNNotificationAction(identifier: ResponseType.disgust.actionIdentifier,
                                                 title: "Hate it",
                                                 options: [.destructive])
        let cameAction = UNNotificationAction(identifier: ResponseType.came.actionIdentifier,
                                              title: "Came")
        let thanksAction = UNNotificationAction(identifier: ResponseType.ok.actionIdentifier,
                                                title: "Thanks")

        let wallpaperChangedCategory =
              UNNotificationCategory(identifier: "WALLPAPER_CHANGED",
              actions: [hornyAction, disgustAction, cameAction, thanksAction],
              intentIdentifiers: [],
              hiddenPreviewsBodyPlaceholder: "",
              options: .customDismissAction)

        UNUserNotificationCenter.current().setNotificationCategories([wallpaperChangedCategory])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
       switch response.actionIdentifier {
       case ResponseType.horny.actionIdentifier:
           postResponse(response: .horny)
       case ResponseType.disgust.actionIdentifier:
           postResponse(response: .disgust)
       case ResponseType.came.actionIdentifier:
           postResponse(response: .came)
       case ResponseType.ok.actionIdentifier:
           postResponse(response: .ok)

       default:
           break
       }

       completionHandler()
    }
}
