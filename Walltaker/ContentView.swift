import SwiftUI
import Wallpaper

struct ContentView: View {
    @AppStorage("linkID") private var linkID = "0"
    @AppStorage("apiKey") private var apiKey = ""
    @AppStorage("wallpaperScale") private var wallpaperScale: Wallpaper.Scale = .auto
    @AppStorage("wallpaperScreen") private var wallpaperScreen = "all"
    @Environment(\.openURL) private var openURL

    var body: some View {
        Form {
            TextField("Link ID", text: $linkID)
                .lineLimit(1)
                .disableAutocorrection(true)
            TextField("API Key", text: $apiKey)
                .lineLimit(1)
                .disableAutocorrection(true)
            Picker("Screen", selection: $wallpaperScreen) {
                Text("All").tag("all")
                Text("Main").tag("main")
            }
            Picker("Scale", selection: $wallpaperScale) {
                ForEach(Wallpaper.Scale.allCases, id: \.rawValue) { value in
                    Text(value.rawValue).tag(value)
                }
            }
        }
        .formStyle(.grouped)
        Form {
            Label("\(Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? "App") v\(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown")", systemImage: "info.circle")
                .onTapGesture {
                    openURL(URL(string: "https://github.com/q2r5/smolcat-walltaker-macos")!)
                }
        }
        .formStyle(.grouped)
    }
}

#Preview {
    ContentView()
}
