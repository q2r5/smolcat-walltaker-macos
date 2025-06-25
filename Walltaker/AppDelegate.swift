import Cocoa
import ActionCableSwift
import Wallpaper
import OSLog

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    let wsLogger = Logger(subsystem: "online.smolcat.walltaker", category: "WebSocket")

    var client: ACClient? = nil
    var channel: ACChannel? = nil
    var currentWallpaper: String = ""
    var wallpaperPath: URL? = nil
    var linkID = 42632 //TODO: Settings screen to make this publically changable

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "photo.circle", accessibilityDescription: "smolcat")
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
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
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
                                         identifier: ["id": 42632],
                                         options: channelOptions)

        channel.addOnSubscribe { (channel, optionalMessage) in
            try? channel.sendMessage(actionName: "announce_client", data: ["client": "smolcat-macos"])
            try? channel.sendMessage(actionName: "check")
        }

        channel.addOnMessage { (channel, optionalMessage) in
            guard let message = optionalMessage?.message,
                  let wallpaperPath = self.wallpaperPath else { return }

            self.wsLogger.log("\(message, privacy: .public)")

            // Make sure it's a set or check response
            if let urlString = message["post_url"] as? String,
               let url = URL(string: urlString) {
                let wallpaperFileName = url.lastPathComponent

                guard !wallpaperFileName.isEmpty else { return }

                // Make sure the wallpaper actually changed (or on a fresh launch)
                if wallpaperFileName != self.currentWallpaper {
                    // If the file already exists, there's no need to redownload it
                    if !FileManager.default.fileExists(atPath: wallpaperPath.appending(path: wallpaperFileName).path()) {
                        let imageData = try? Data(contentsOf: url)
                        if let imageData = imageData {
                            try? imageData.write(to: wallpaperPath.appending(path: url.lastPathComponent),
                                                 options: .atomic)
                        }
                    }

                    // Set the wallpaper in any case, just in case it's been changed another way
                    try? Wallpaper.set(wallpaperPath.appending(path: wallpaperFileName))
                    self.currentWallpaper = wallpaperFileName
                }
            }
        }

        self.client = client
        self.channel = channel
        self.client?.connect()
    }
}

