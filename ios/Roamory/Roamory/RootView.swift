import SwiftUI

/// The app's two tabs, chosen from the glass bar at the bottom.
enum AppTab: String, CaseIterable {
    case gallery, create

    var title: String { rawValue.capitalized }

    var icon: String {
        switch self {
        case .gallery: "square.grid.2x2.fill"
        case .create: "video.badge.plus"
        }
    }
}

/// The intro on first launch, then Create. Create runs trip setup full screen (the tab bar slides away; its X goes to
/// the Gallery), then the camera; the camera starts only after Start, because the chosen style sets its orientation
/// when it is prepared.
struct RootView: View {
    /// Delete the app to see the intro again.
    @AppStorage("welcomeSeen") private var welcomeSeen = false
    @State private var tab: AppTab = .create
    @State private var recording = false

    var body: some View {
        ZStack {
            if !welcomeSeen {
                WelcomeView {
                    tab = .create
                    withAnimation(.easeInOut(duration: 0.5)) { welcomeSeen = true }
                }
                .transition(.opacity)
            } else if recording {
                ContentView { withAnimation(.easeInOut(duration: 0.6)) { recording = false } }
                    .transition(.opacity.combined(with: .scale(scale: 1.05)))
            } else {
                Group {
                    switch tab {
                    case .gallery:
                        GalleryView { select(.create) }
                    case .create:
                        OnboardingView(onStart: { withAnimation(.easeInOut(duration: 0.6)) { recording = true } },
                                       onClose: { select(.gallery) })
                    }
                }
                .transition(.opacity)
                .safeAreaInset(edge: .bottom) {
                    if tab != .create {
                        GlassTabBar(tab: Binding(get: { tab }, set: select))
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
            }
        }
        .background(Color.black.ignoresSafeArea())
        .preferredColorScheme(.dark)
    }

    private func select(_ next: AppTab) {
        withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) { tab = next }
    }
}

/// A floating Liquid Glass capsule with one button per tab; the chosen one sits on a green pill.
struct GlassTabBar: View {
    @Binding var tab: AppTab
    @Namespace private var pill

    var body: some View {
        HStack(spacing: 4) {
            ForEach(AppTab.allCases, id: \.self) { item in
                let on = tab == item
                Button { tab = item } label: {
                    VStack(spacing: 3) {
                        Image(systemName: item.icon).font(.system(size: 18, weight: .semibold))
                        Text(item.title).font(.system(.caption2, design: .rounded).weight(.bold))
                    }
                    .foregroundStyle(on ? Theme.accentInk : .white.opacity(0.6))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
                    .background {
                        if on {
                            Capsule().fill(Theme.accent)
                                .shadow(color: Theme.accent.opacity(0.5), radius: 10)
                                .matchedGeometryEffect(id: "pill", in: pill)
                        }
                    }
                    .contentShape(Capsule())
                }
                .buttonStyle(PressableStyle(scale: 0.92))
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(6)
        .glassEffect(.regular.tint(Theme.accent.opacity(0.08)), in: .capsule)
        .padding(.horizontal, 24)
        .padding(.bottom, 4)
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: tab)
        .sensoryFeedback(.selection, trigger: tab)
    }
}
