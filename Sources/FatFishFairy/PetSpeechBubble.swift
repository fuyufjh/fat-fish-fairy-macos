import SwiftUI

struct PetSpeechBubble: View {
    let text: String
    var body: some View {
        Text(text).font(.system(size: 13, weight: .medium)).foregroundStyle(.primary)
            .lineLimit(5).padding(14).frame(maxWidth: 280, alignment: .leading)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(.primary.opacity(0.18)))
            .shadow(color: .black.opacity(0.1), radius: 10, y: 3)
    }
}
