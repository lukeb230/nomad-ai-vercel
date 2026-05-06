//
//  WelcomeCard.swift
//  Top-of-AI-chat welcome — sets the tone, frames what NomadAI does, and
//  shows two example queries the user can lift verbatim. Always rendered at
//  the top of `aiPanel`'s scroll, even after the chat has started.
//

import SwiftUI

struct WelcomeCard: View {
    let onTryQuery: (String) -> Void

    private static let example1 = "Dispersed BLM spot near Moab, no fee"
    private static let example2 = "Camps along Highway 50 Nevada, 4x4 accessible"

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Text("NOMADAI").monoLabel()
                Image(systemName: "tent.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.clay)
            }

            Text(bodyAttributedString)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)

            Text(howToUseAttributedString)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 4) {
                exampleRow(Self.example1)
                exampleRow(Self.example2)
            }
            .padding(.top, 2)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.bark))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.line, lineWidth: 1))
    }

    /// Body line — plain utility statement.
    private var bodyAttributedString: AttributedString {
        var out = AttributedString("I help you plan ")
        out.font = .body(13)
        out.foregroundColor = Color.fgDim

        var emph = AttributedString("camping trips and overland routes")
        emph.font = .frauncesCard(13)
        emph.foregroundColor = Color.clay
        out += emph

        var tail = AttributedString(".")
        tail.font = .body(13)
        tail.foregroundColor = Color.fgDim
        out += tail

        return out
    }

    /// Second line — how to interact: questions or freeform.
    private var howToUseAttributedString: AttributedString {
        var head = AttributedString("Walk through the ")
        head.font = .body(13)
        head.foregroundColor = Color.fgDim

        var emph1 = AttributedString("questions below")
        emph1.font = .frauncesCard(13)
        emph1.foregroundColor = Color.clay
        head += emph1

        var mid = AttributedString(" to dial it in, or just ")
        mid.font = .body(13)
        mid.foregroundColor = Color.fgDim
        head += mid

        var emph2 = AttributedString("type whatever")
        emph2.font = .frauncesCard(13)
        emph2.foregroundColor = Color.clay
        head += emph2

        var tail = AttributedString(" you're looking for.")
        tail.font = .body(13)
        tail.foregroundColor = Color.fgDim
        head += tail

        return head
    }

    private func exampleRow(_ text: String) -> some View {
        Button { onTryQuery(text) } label: {
            HStack(spacing: 6) {
                Image(systemName: "sparkle")
                    .font(.system(size: 9))
                    .foregroundStyle(Color.clay)
                Text("“\(text)”")
                    .font(.frauncesCard(13))
                    .italic()
                    .foregroundStyle(Color.clay)
                    .multilineTextAlignment(.leading)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
        }
        .buttonStyle(.plain)
    }
}
