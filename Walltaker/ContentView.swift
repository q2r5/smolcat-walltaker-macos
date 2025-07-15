import SwiftUI
import Wallpaper
import DebouncedOnChange

struct ContentView: View {
    @AppStorage("linkID") private var linkID = "0"
    @State var editingLinkID = "0"
    @AppStorage("apiKey") private var apiKey = ""
    @AppStorage("wallpaperScale") private var wallpaperScale: Wallpaper.Scale = .auto
    @AppStorage("wallpaperScreen") private var wallpaperScreen = "all"
    @AppStorage("muted") private var muted = false
    @Environment(\.openURL) private var openURL

    var body: some View {
        Form {
            Section(header: Text("Settings")) {
                TextField("Link ID", text: $editingLinkID)
                    .lineLimit(1)
                    .disableAutocorrection(true)
                    .onChange(of: editingLinkID, debounceTime: .seconds(1)) { newValue in
                        if linkID != newValue {
                            linkID = newValue
                        }
                    }
                TextField("API Key", text: $apiKey)
                    .lineLimit(1)
                    .disableAutocorrection(true)
            }
            Section(header: Text("Screen and Scale")) {
                if NSScreen.screens.count > 1 {
                    Picker("Screen", selection: $wallpaperScreen) {
                        Text("All").tag("all")
                        Text("Main").tag("main")
                        ForEach(NSScreen.screens.map(\.localizedName), id: \.self) { name in
                            Text(name).tag(name)
                        }
                    }
                }
                Picker("Scale", selection: $wallpaperScale) {
                    ForEach(Wallpaper.Scale.allCases, id: \.rawValue) { value in
                        Text(value.rawValue).tag(value)
                    }
                }
            }
            Section(header: Text("Video")) {
                Toggle("Muted", isOn: $muted)
            }
            Section {
                Label("\(Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? "App") v\(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown")", systemImage: "info.circle")
                    .onTapGesture {
                        openURL(URL(string: "https://github.com/q2r5/smolcat-walltaker-macos")!)
                    }
            }
        }
        .formStyle(.grouped)
    }
}

#Preview {
    ContentView()
}
