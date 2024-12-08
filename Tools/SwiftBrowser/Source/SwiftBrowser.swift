//
//  SwiftBrowserApp.swift
//  SwiftBrowser
//
//  Created by Richard Robinson on 12/6/24.
//

import SwiftUI
@_spi(Private) import WebKit

@main
struct SwiftBrowserApp: App {
    @FocusedValue(BrowserViewModel.self) var focusedBrowserViewModel

    var body: some Scene {
        WindowGroup {
            BrowserView()
        }
        .commands {
            CommandGroup(after: .sidebar) {
                Button("Reload Page") {
                    focusedBrowserViewModel?.page.reload()
                }
                .keyboardShortcut("r")
            }

            CommandGroup(replacing: .importExport) {
                Button("Export as PDF…") {
                    focusedBrowserViewModel?.exportAsPDF()
                }
            }
        }
    }
}
