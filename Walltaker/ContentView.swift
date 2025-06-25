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

    var body: some View {
        HStack {
            Form {
                TextField("Link ID", text: $linkID)
                Picker("Scale", selection: $wallpaperScale) {
                    ForEach(Wallpaper.Scale.allCases, id: \.rawValue) { value in
                        Text(value.rawValue).tag(value)
                    }
                }
            }
        }
    }
}

#Preview {
    ContentView()
}
