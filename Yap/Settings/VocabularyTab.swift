import SwiftUI

struct VocabularyTab: View {
    var wordBank: WordBank

    @State private var newWord: String = ""
    @FocusState private var isInputFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "plus.circle.fill")
                    .foregroundStyle(newWord.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Color.secondary.opacity(0.4) : Color.accentColor)
                    .font(.system(size: 15))
                    .animation(.easeInOut(duration: 0.15), value: newWord.isEmpty)

                TextField("Add a word or phrase…", text: $newWord)
                    .focused($isInputFocused)
                    .onSubmit { addCurrentWord() }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(.quaternary.opacity(0.3))
                    .overlay(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .strokeBorder(
                                isInputFocused ? Color.accentColor.opacity(0.6) : Color.secondary.opacity(0.2),
                                lineWidth: isInputFocused ? 1.5 : 1
                            )
                    )
            )
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 12)

            Divider()

            if wordBank.words.isEmpty {
                emptyState
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(Array(wordBank.words.enumerated()), id: \.offset) { index, word in
                            wordRow(word, at: index)
                            if index < wordBank.words.count - 1 {
                                Divider().padding(.leading, 38)
                            }
                        }
                    }
                    .background(.quaternary.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(.separator, lineWidth: 1)
                    )
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 4)
                }

                Divider()

                HStack {
                    Text("\(wordBank.words.count) \(wordBank.words.count == 1 ? "word" : "words")")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 7)
            }
        }
    }


    private var emptyState: some View {
        VStack {
            Spacer()
            VStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(.quaternary.opacity(0.5))
                        .frame(width: 52, height: 52)
                    Image(systemName: "character.book.closed.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(.secondary)
                }
                VStack(spacing: 4) {
                    Text("Your dictionary is empty")
                        .font(.system(size: 13, weight: .medium))
                    Text("Add names, jargon, or anything Yap\nkeeps getting wrong.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            Spacer()
        }
    }


    private func wordRow(_ word: String, at index: Int) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "text.quote")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .frame(width: 16)

            Text(word)
                .font(.system(size: 13))
                .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                wordBank.remove(at: IndexSet([index]))
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 18, height: 18)
                    .background(.quaternary.opacity(0.6), in: Circle())
            }
            .buttonStyle(.borderless)
            .help("Remove word")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
    }


    private func addCurrentWord() {
        let trimmed = newWord.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        wordBank.add(trimmed)
        newWord = ""
        isInputFocused = true
    }
}
