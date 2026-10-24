//
//  SentFramesSheet.swift
//  Roamory
//

import SwiftUI

/// The frames the last Evaluate sent, oldest first, as the model got them, with the details line sent along.
struct SentFramesSheet: View {
    let evaluation: SentEvaluation
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    if let details = evaluation.details {
                        Text(details)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    ForEach(Array(evaluation.frames.enumerated()), id: \.offset) { k, jpeg in
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Frame \(k)")
                                .font(.subheadline.weight(.semibold))
                            if let image = UIImage(data: jpeg) {
                                Image(uiImage: image)
                                    .resizable()
                                    .scaledToFit()
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                            }
                            Text("\(jpeg.count / 1024) KB")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("Frames sent")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }
}
