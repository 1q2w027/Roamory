//
//  AskView.swift
//  Roamory
//

import SwiftUI

/// The Ask tab: a chat with Roamy, who answers questions about the app. Needs the Anthropic API key in the Keychain.
struct AskView: View {
    @State private var lines: [ChatLine] = []
    @State private var draft = ""
    @State private var waiting = false
    @State private var failure: String?
    @State private var showKeySheet = false
    @FocusState private var typing: Bool

    private static let starters = ["How do I save a moment?", "Why is the screen dark?", "How do I make a video?"]

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            VStack(spacing: 0) {
                header
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 14) {
                            RoamyLine(text: "Hi, I'm Roamy! Ask me anything about filming your trip.", mood: .wave)
                            ForEach(lines) { line in
                                if line.role == .user {
                                    UserLine(text: line.text)
                                } else {
                                    RoamyLine(text: line.text, mood: .happy)
                                }
                            }
                            if waiting {
                                RoamyLine(text: "…", mood: .excited)
                            }
                            if let failure {
                                Text(failure)
                                    .font(.footnote)
                                    .foregroundStyle(Theme.recording)
                            }
                            if lines.isEmpty { starters }
                            Color.clear.frame(height: 1).id("end")
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                    }
                    .scrollIndicators(.hidden)
                    .scrollDismissesKeyboard(.interactively)
                    .onChange(of: lines) { withAnimation { proxy.scrollTo("end", anchor: .bottom) } }
                    .onChange(of: waiting) { withAnimation { proxy.scrollTo("end", anchor: .bottom) } }
                }
                inputBar
            }
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showKeySheet) { APIKeySheet() }
    }

    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("ASK ROAMY")
                    .font(.caption.weight(.semibold))
                    .tracking(2)
                    .foregroundStyle(Theme.accent2)
                Text("Questions?")
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(.white)
            }
            Spacer()
            Button { showKeySheet = true } label: {
                Image(systemName: "key.fill")
                    .font(.footnote.bold())
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 32)
                    .background(Theme.chip, in: Circle())
            }
            .accessibilityLabel("API key")
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 4)
    }

    private var starters: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Self.starters, id: \.self) { question in
                Button { send(question) } label: {
                    Text(question)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.accent2)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .background(Theme.chip, in: Capsule())
                        .overlay(Capsule().strokeBorder(Theme.accent.opacity(0.3)))
                }
                .buttonStyle(PressableStyle())
            }
        }
        .padding(.leading, 56)
    }

    private var inputBar: some View {
        HStack(spacing: 10) {
            TextField("Ask a question", text: $draft, axis: .vertical)
                .lineLimit(1...4)
                .focused($typing)
                .submitLabel(.send)
                .onSubmit { send(draft) }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            Button { send(draft) } label: {
                Image(systemName: "arrow.up")
                    .font(.headline.bold())
                    .foregroundStyle(Theme.accentInk)
                    .frame(width: 44, height: 44)
                    .background(Theme.accentGradient, in: Circle())
            }
            .buttonStyle(PressableStyle(scale: 0.9))
            .disabled(!canSend)
            .opacity(canSend ? 1 : 0.4)
            .accessibilityLabel("Send")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private var canSend: Bool {
        !waiting && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func send(_ text: String) {
        let question = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty, !waiting else { return }
        // Without a saved API key, ask for one first.
        guard APIKeyStore.load() != nil else {
            showKeySheet = true
            return
        }
        draft = ""
        failure = nil
        lines.append(ChatLine(role: .user, text: question))
        waiting = true
        Task {
            defer { waiting = false }
            do {
                let answer = try await RoamyChatClient.reply(to: lines)
                lines.append(ChatLine(role: .assistant, text: answer))
            } catch {
                // Drop the unanswered question so the conversation stays user, assistant, user, …
                if lines.last?.role == .user { draft = lines.removeLast().text }
                failure = error.localizedDescription
            }
        }
    }
}

/// Roamy's answer: the mascot on the left, the text in a card beside it.
private struct RoamyLine: View {
    let text: String
    let mood: RoamyMascot.Mood

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            RoamyMascot(mood: mood, size: 30)
                .frame(width: 48, height: 40)
            Text(text)
                .font(.body)
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .textSelection(.enabled)
            Spacer(minLength: 32)
        }
        .transition(.opacity.combined(with: .offset(y: 8)))
    }
}

/// The user's question, on the right on the accent gradient.
private struct UserLine: View {
    let text: String

    var body: some View {
        HStack {
            Spacer(minLength: 56)
            Text(text)
                .font(.body)
                .foregroundStyle(Theme.accentInk)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Theme.accentGradient, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .transition(.opacity.combined(with: .offset(y: 8)))
    }
}

#Preview {
    AskView()
}
