import SwiftUI
#if DEBUG
import RoamoryKit
#endif

extension View {
    /// Debug builds get a corner button that opens Render Lab, to try the on-phone and laptop renderers.
    func renderLabButton() -> some View {
        #if DEBUG
        modifier(RenderLabButton())
        #else
        self
        #endif
    }
}

#if DEBUG
private struct RenderLabButton: ViewModifier {
    @State private var showLab = false

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .topTrailing) {
                Button { showLab = true } label: {
                    Image(systemName: "film.stack")
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .background(.black.opacity(0.5), in: Circle())
                }
                .padding(.trailing, 16)
            }
            .sheet(isPresented: $showLab) {
                NavigationStack { RenderLabView() }
            }
    }
}
#endif
