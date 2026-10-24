//
//  OrientationLock.swift
//  Roamory
//

import RoamoryKit
import UIKit

/// Asks the app's orientation lock which way the interface may turn.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        OrientationLock.mask
    }
}

/// The app is portrait, except the recording screen of a 16:9 trip, which turns to the side the camera records.
@MainActor
enum OrientationLock {
    static private(set) var mask: UIInterfaceOrientationMask = .portrait

    static func set(_ side: InterfaceSide) {
        let mask: UIInterfaceOrientationMask = switch side {
        case .portrait: .portrait
        case .landscapeLeft: .landscapeLeft
        case .landscapeRight: .landscapeRight
        }
        guard mask != self.mask else { return }
        self.mask = mask
        for case let scene as UIWindowScene in UIApplication.shared.connectedScenes {
            scene.keyWindow?.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
            scene.requestGeometryUpdate(.iOS(interfaceOrientations: mask))
        }
    }
}
