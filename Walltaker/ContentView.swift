//
//  ContentView.swift
//  Walltaker
//
//  Created by Callie Dunn on 6/25/25.
//

import SwiftUI
import Wallpaper

struct ContentView: View {
    @AppStorage("linkID") private var linkID = "42632"
    @AppStorage("wallpaperScale") private var wallpaperScale: Wallpaper.Scale = .auto
    @AppStorage("wallpaperScreen") private var wallpaperScreen = "all"
    var body: some View {
        VStack(alignment: .center) {
            HStack(alignment: .center) {
                Form {
                    TextField("Link ID", text: $linkID)
                    Picker("Screen", selection: $wallpaperScreen) {
                        Text("All").tag("all")
                        Text("Main").tag("main")
                    }
                    Picker("Scale", selection: $wallpaperScale) {
                        ForEach(Wallpaper.Scale.allCases, id: \.rawValue) { value in
                            Text(value.rawValue).tag(value)
                        }
                    }
                    .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)) { _ in

                    }
                }
                .formStyle(.grouped)
            }
        }
    }
}

#Preview {
    ContentView()
}
