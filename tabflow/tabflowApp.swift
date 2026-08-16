//
//  tabflowApp.swift
//  tabflow
//

import SwiftUI

@main
struct tabflowApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}
