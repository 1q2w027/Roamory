//
//  TripleClickGuide.swift
//  Roamory
//

import SwiftUI

/// Looping animation of a phone whose side button is clicked three times, to show how to start Guided Access.
struct TripleClickGuide: View {
    /// Number of clicks shown so far in the current loop (0...3).
    @State private var clicks = 0
    @State private var pressed = false

    var body: some View {
        HStack(spacing: 14) {
            phone
            VStack(spacing: 4) {
                Text("Triple-click the side button")
                    .font(.subheadline.bold())
                    .multilineTextAlignment(.center)
                HStack(spacing: 6) {
                    ForEach(1...3, id: \.self) { n in
                        Circle()
                            .fill(n <= clicks ? Color.white : Color.white.opacity(0.25))
                            .frame(width: 10, height: 10)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .task { await loop() }
    }

    private var phone: some View {
        ZStack(alignment: .trailing) {
            RoundedRectangle(cornerRadius: 10)
                .stroke(.white, lineWidth: 2)
                .frame(width: 34, height: 64)
                .padding(.trailing, 3)
            // Side button, sitting on the right edge.
            Capsule()
                .fill(pressed ? Color.yellow : Color.white)
                .frame(width: pressed ? 3 : 5, height: 18)
                .offset(y: -10)
            // Ripple from the button on each click.
            Circle()
                .stroke(Color.yellow, lineWidth: 2)
                .frame(width: 20, height: 20)
                .scaleEffect(pressed ? 1.6 : 0.5)
                .opacity(pressed ? 0 : 0.9)
                .offset(x: 8, y: -10)
        }
        .frame(width: 48, height: 64)
    }

    private func loop() async {
        while !Task.isCancelled {
            clicks = 0
            for n in 1...3 {
                withAnimation(.easeOut(duration: 0.12)) { pressed = true }
                clicks = n
                try? await Task.sleep(for: .milliseconds(120))
                withAnimation(.easeIn(duration: 0.25)) { pressed = false }
                try? await Task.sleep(for: .milliseconds(230))
            }
            try? await Task.sleep(for: .seconds(1.2))
        }
    }
}

#Preview {
    TripleClickGuide()
        .padding()
        .background(.black)
        .foregroundStyle(.white)
}
