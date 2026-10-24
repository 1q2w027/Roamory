import SwiftUI

/// Step 5: an optional note about the trip. Evaluate sends it to the model along with the frames.
struct TripDetailsStep: View {
    @Binding var details: String
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ZStack(alignment: .topLeading) {
                TextEditor(text: $details)
                    .focused($focused)
                    .scrollContentBackground(.hidden)
                    .foregroundStyle(.white)
                    .padding(10)
                    .onChange(of: details) { _, new in
                        if new.count > TripSettings.detailsLimit { details = String(new.prefix(TripSettings.detailsLimit)) }
                    }
                if details.isEmpty {
                    Text("Who is with you, what you are celebrating, places or things to catch...")
                        .foregroundStyle(Theme.secondaryText)
                        .padding(.horizontal, 15)
                        .padding(.vertical, 18)
                        .allowsHitTesting(false)
                }
            }
            .frame(maxHeight: 220)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 18))
            HStack {
                Text("Optional. Used when Evaluate describes what the camera sees.")
                Spacer(minLength: 8)
                Text("\(details.count)/\(TripSettings.detailsLimit)").monospacedDigit()
            }
            .font(.footnote)
            .foregroundStyle(Theme.secondaryText)
            Spacer(minLength: 0)
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { focused = false }
            }
        }
    }
}
