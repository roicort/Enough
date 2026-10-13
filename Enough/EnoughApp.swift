//
//  EnoughApp.swift
//  Enough
//
//  Created by Rodrigo Cortez on 07/10/26.
//

import SwiftUI

@main
struct EnoughApp: App {
    var body: some Scene {
        WindowGroup("Enough!") {
#if os(macOS)
            ContentView()
                .frame(minWidth: 520, minHeight: 620)
#else
            ContentView()
#endif
        }
#if os(macOS)
        .defaultSize(width: 520, height: 620)
#endif
    }
}
