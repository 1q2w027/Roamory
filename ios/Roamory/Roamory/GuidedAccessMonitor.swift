//
//  GuidedAccessMonitor.swift
//  Roamory
//

import Combine
import UIKit

/// Tracks whether Guided Access is on. An app cannot turn it on by itself on a normal device,
/// so the UI guides the user to do it; Guided Access keeps the app in the foreground while recording.
final class GuidedAccessMonitor: ObservableObject {
    @Published private(set) var isEnabled = UIAccessibility.isGuidedAccessEnabled

    private var observer: NSObjectProtocol?

    init() {
        observer = NotificationCenter.default.addObserver(
            forName: UIAccessibility.guidedAccessStatusDidChangeNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            self?.isEnabled = UIAccessibility.isGuidedAccessEnabled
        }
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }
}
