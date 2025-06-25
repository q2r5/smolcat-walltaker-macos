import Cocoa
import ActionCableSwift
import Wallpaper
import OSLog
import SwiftUI
import UserNotifications

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var window: NSWindow!
    let wsLogger = Logger(subsystem: "online.smolcat.walltaker", category: "WebSocket")
    let center = UNUserNotificationCenter.current()
    var canNotify: Bool = false

    var client: ACClient? = nil
    var channel: ACChannel? = nil
    var currentWallpaper: String = ""
    var wallpaperPath: URL? = nil

    var linkID = UserDefaults.standard.integer(forKey: "linkID")
    var wallpaperScale = UserDefaults.standard.string(forKey: "wallpaperScale")
    var wallpaperScreen = UserDefaults.standard.string(forKey: "wallpaperScreen")

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "photo.circle", accessibilityDescription: "smolcat")
        }

        center.requestAuthorization(options: [.alert, .sound, .provisional]) { allow, error in
            if let error {
                self.wsLogger.error("\(error.localizedDescription)")
            } else {
                self.canNotify = allow
            }
        }

        setupMenus()
        createFolders()
        connectToWebsocket()
    }

    func applicationWillTerminate(_ aNotification: Notification) {
        // Clean up old wallpapers on close
        guard let wallpaperPath else { return }
        let files = try? FileManager.default.contentsOfDirectory(at: wallpaperPath,
                                                                 includingPropertiesForKeys: [])
        files?.forEach {
            if $0.lastPathComponent == currentWallpaper { return }
            try? FileManager.default.removeItem(at: $0)
        }
    }

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

        let channelOptions = ACChannelOptions(buffering: true, autoSubscribe: true)
        let channel = client.makeChannel(name: "LinkChannel",
                                         identifier: ["id": linkID],
                                         options: channelOptions)

        channel.addOnSubscribe { (channel, optionalMessage) in
            try? channel.sendMessage(actionName: "announce_client", data: ["client": "smoltaker"])
            try? channel.sendMessage(actionName: "check")
        }

        channel.addOnMessage { (channel, optionalMessage) in
            guard let message = optionalMessage?.message else { return }
            self.wsLogger.log("\(message, privacy: .public)")
            self.updateWallpaper(for: message)
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
        if wallpaperFileName != currentWallpaper {
            // If the file already exists, there's no need to redownload it
            if !FileManager.default.fileExists(atPath: wallpaperPath.appending(path: wallpaperFileName).path()) {
                let imageData = try? Data(contentsOf: url)
                if let imageData = imageData {
                    try? imageData.write(to: wallpaperPath.appending(path: url.lastPathComponent),
                                         options: .atomic)
                }
            }

            if let wallpapers = try? Wallpaper.get(),
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

            // Set the wallpaper in any case, just in case it's been changed another way
            do {
                try Wallpaper.set(wallpaperPath.appending(path: wallpaperFileName),
                                  screen: screen,
                                  scale: Wallpaper.Scale(rawValue: self.wallpaperScale ?? "auto") ?? .auto)
                currentWallpaper = wallpaperFileName

                if canNotify {
                    let notifContent = UNMutableNotificationContent()
                    notifContent.title = "Wallpaper Set"
                    notifContent.body = "Set by: \(message["set_by"] ?? "anon")"
                    center.add(UNNotificationRequest(identifier: "online.smolcat.walltaker.set",
                                                     content: notifContent,
                                                     trigger: nil))
                }
            } catch {
                wsLogger.error("\(error.localizedDescription)")
            }
        }
    }

    @objc func showSettings() {
        window = NSWindow(contentRect: NSMakeRect(0, 0, 300, 300),
            styleMask: [.closable, .titled],
            backing: .buffered,
            defer: false)

        window.title = "Settings"
        window.center()
        window.contentView = NSHostingView(rootView: ContentView())
        window.orderFrontRegardless()
    }
}
