import SwiftUI

/// Trip setup first, then the camera. The camera starts only after Start, because the chosen style sets its
/// orientation when it is prepared.
struct RootView: View {
    @State private var setupDone = false

    var body: some View {
        ZStack {
            if setupDone {
                ContentView()
                    .transition(.opacity.combined(with: .scale(scale: 1.05)))
            } else {
                OnboardingView { withAnimation(.easeInOut(duration: 0.6)) { setupDone = true } }
                    .transition(.opacity)
            }
        }
        .background(Color.black.ignoresSafeArea())
    }
}
