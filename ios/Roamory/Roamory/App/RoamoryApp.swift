//
//  RoamoryApp.swift
//  Roamory
//
//  Created by Yifan Liu on 10/23/26.
//

import SwiftUI

@main
struct RoamoryApp: App {
    /// Lets the recording screen of a 16:9 trip turn landscape (`OrientationLock`).
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}
