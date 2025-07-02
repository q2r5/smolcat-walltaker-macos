import Cocoa
import ActionCableSwift
import Wallpaper
import OSLog
import SwiftUI
import UserNotifications


class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    var statusItem: NSStatusItem!
    var windowController: NSWindowController!
    let wsLogger = Logger(subsystem: "online.smolcat.walltaker", category: "WebSocket")

    var client: ACClient? = nil
    var channel: ACChannel? = nil

    var currentWallpaper = ""
    var wallpaperPath: URL? = nil

    var canNotify = false
    var forceChange = false
    var skipNotif = false

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

        UserDefaults.standard.addObserver(self, forKeyPath: "linkID", options: .new, context: nil)
        UserDefaults.standard.addObserver(self, forKeyPath: "wallpaperScale", options: .new, context: nil)
        UserDefaults.standard.addObserver(self, forKeyPath: "wallpaperScreen", options: .new, context: nil)
        UserDefaults.standard.addObserver(self, forKeyPath: "apiKey", options: .new, context: nil)

        NSWorkspace.shared.notificationCenter.addObserver(self,
                                                          selector: #selector(wakeFromSleep),
                                                          name: NSWorkspace.didWakeNotification,
                                                          object: nil)

        NSWorkspace.shared.notificationCenter.addObserver(self,
                                                          selector: #selector(willSwitchScenes),
                                                          name: NSWorkspace.activeSpaceDidChangeNotification,
                                                          object: nil)

        windowController = NSWindowController()
        setupMenus()
        createFolders()
        connectToWebsocket()
    }

    func applicationWillTerminate(_ aNotification: Notification) {
        client?.disconnect()

        // Clean up old wallpapers on close
        guard let wallpaperPath else { return }
        let files = try? FileManager.default.contentsOfDirectory(at: wallpaperPath,
                                                                 includingPropertiesForKeys: [])
        files?.forEach {
            if $0.lastPathComponent == currentWallpaper { return }
            try? FileManager.default.removeItem(at: $0)
        }
    }

    override func observeValue(forKeyPath keyPath: String?,
                               of object: Any?,
                               change: [NSKeyValueChangeKey : Any]?,
                               context: UnsafeMutableRawPointer?) {
        if keyPath == "linkID" {
            client?.disconnect()
            connectToWebsocket()
        } else if keyPath == "wallpaperScale" || keyPath == "wallpaperScreen" {
            forceChange = true
            try? channel?.sendMessage(actionName: "check")
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

    func connectToWebsocket() {
        let clientOptions = ACClientOptions(debug: false, reconnect: true)
        let client = ACClient(stringURL: "wss://walltaker.joi.how/cable", options: clientOptions)

        let channelOptions = ACChannelOptions(buffering: false, autoSubscribe: true)
        let channel = client.makeChannel(name: "LinkChannel",
                                         identifier: ["id": linkID],
                                         options: channelOptions)

        channel.addOnSubscribe { (channel, optionalMessage) in
            try? channel.sendMessage(actionName: "announce_client", data: ["client": "CFNetwork/smoltaker"])
            try? channel.sendMessage(actionName: "check")
        }

        channel.addOnMessage { (channel, optionalMessage) in
            guard let message = optionalMessage?.message else { return }
            self.wsLogger.log("\(message, privacy: .public)")

            // If for some reason we get an error, force a recheck.
            // (temp workaround for: https://github.com/pupgray/walltaker/pull/65)
            if message["success"] as? Int == 0 {
                try? channel.sendMessage(actionName: "check")
            } else {
                self.updateWallpaper(for: message)
            }
        }

        self.client = client
        self.channel = channel
        self.client?.connect()
    }

    func updateWallpaper(for message: [String: Any]) {
        guard let urlString = message["post_url"] as? String,
              let url = URL(string: urlString) else { return }

        let wallpaperFileName = url.lastPathComponent

        guard !wallpaperFileName.isEmpty,
            let wallpaperPath else { return }

        // Make sure the wallpaper actually changed (or on a fresh launch)
        if forceChange || wallpaperFileName != currentWallpaper {
            // If the file already exists, there's no need to redownload it
            if !FileManager.default.fileExists(atPath: wallpaperPath.appending(path: wallpaperFileName).path()) {
                let imageData = try? Data(contentsOf: url)
                if let imageData = imageData {
                    try? imageData.write(to: wallpaperPath.appending(path: url.lastPathComponent),
                                         options: .atomic)
                }
            }

            if !forceChange,
               let wallpapers = try? Wallpaper.get(),
               wallpapers.contains(where: { $0 == wallpaperPath.appending(path: wallpaperFileName) }) {
                // This image is already set as the wallpaper, don't bother resetting
                return
            }

            var screen = Wallpaper.Screen.all
            if let wallpaperScreen {
                switch wallpaperScreen {
                case "all":
                    screen = .all
                case "main":
                    screen = .main
                default:
                    if let screenNumber = Int(wallpaperScreen) {
                        screen = .index(screenNumber)
                    } else {
                        screen = .all
                    }
                }
            }

            // Set the wallpaper in any case
            do {
                try Wallpaper.set(wallpaperPath.appending(path: wallpaperFileName),
                                  screen: screen,
                                  scale: Wallpaper.Scale(rawValue: wallpaperScale ?? "auto") ?? .auto)
                currentWallpaper = wallpaperFileName

                if canNotify, !skipNotif {
                    let notifContent = UNMutableNotificationContent()
                    notifContent.title = "Wallpaper Set"
                    notifContent.body = "Set by: \(message["set_by"] ?? "anon")"
                    notifContent.categoryIdentifier = "WALLPAPER_CHANGED"
                    UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "online.smolcat.walltaker.set",
                                                                                 content: notifContent,
                                                                                 trigger: nil))
                }

                skipNotif = false
                forceChange = false
            } catch {
                wsLogger.error("\(error.localizedDescription)")
            }
        }
    }

    // MARK: - Selectors

    @objc
    func showSettings() {
        guard windowController.window == nil else {
            windowController.window?.makeKeyAndOrderFront(nil)
            return
        }

        let window = NSWindow(contentViewController: NSHostingController(rootView: ContentView()))
        window.styleMask = [.titled, .closable]
        window.contentViewController?.preferredContentSize = NSSize(width: 300, height: 400)
        window.title = "Settings"
        window.center()
        windowController.window = window
        windowController.showWindow(nil)
        window.makeKeyAndOrderFront(nil)
    }

    @objc
    func wakeFromSleep() {
        guard let client,
              client.isConnected,
              let channel  else { return }

        try? channel.sendMessage(actionName: "check")
    }

    @objc
    func willSwitchScenes() {
        guard let client,
              client.isConnected,
              let channel,
              channel.isSubscribed,
              let wallpaperPath,
              let wallpapers = try? Wallpaper.get(),
              wallpapers.contains(where: { $0 == wallpaperPath.appending(path: currentWallpaper) }) else { return }

        skipNotif = true
        try? channel.sendMessage(actionName: "check")
    }

    // MARK: - Response

    enum ResponseType: String {
        case horny
        case disgust
        case came
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

        let hornyAction = UNNotificationAction(identifier: "HORNY_ACTION",
                                               title: "Love it")
        let disgustAction = UNNotificationAction(identifier: "DISGUST_ACTION",
                                                 title: "Hate it",
                                                 options: [.destructive])
        let cameAction = UNNotificationAction(identifier: "CAME_ACTION",
                                              title: "Came")

        let wallpaperChangedCategory =
              UNNotificationCategory(identifier: "WALLPAPER_CHANGED",
              actions: [hornyAction, disgustAction, cameAction],
              intentIdentifiers: [],
              hiddenPreviewsBodyPlaceholder: "",
              options: .customDismissAction)

        UNUserNotificationCenter.current().setNotificationCategories([wallpaperChangedCategory])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
       switch response.actionIdentifier {
       case "HORNY_ACTION":
           postResponse(response: .horny)
           break

       case "DISGUST_ACTION":
           postResponse(response: .disgust)
           break

       case "CAME_ACTION":
           postResponse(response: .came)
           break

       default:
           break
       }

       completionHandler()
    }
}
