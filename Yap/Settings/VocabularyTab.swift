import SwiftUI

struct VocabularyTab: View {
    var wordBank: WordBank

    @State private var newWord: String = ""
    @FocusState private var isInputFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                TextField("Add a word or phrase", text: $newWord)
                    .textFieldStyle(.roundedBorder)
                    .focused($isInputFocused)
                    .onSubmit {
                        addCurrentWord()
                    }

                Button("Add") {
                    addCurrentWord()
                }
                .controlSize(.small)
                .disabled(newWord.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .keyboardShortcut(.return, modifiers: .command)
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 10)

            Divider()

            if wordBank.words.isEmpty {
                Spacer()
                VStack(spacing: 8) {
                    Image(systemName: "text.book.closed")
                        .font(.system(size: 28))
                        .foregroundStyle(.quaternary)
                    Text("Your dictionary is empty")
                        .font(.body)
                        .foregroundStyle(.secondary)
                    Text("Add names, slang, or anything Yap\nkeeps getting wrong.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 20)
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(wordBank.words.enumerated()), id: \.offset) { index, word in
                            wordRow(word, at: index)

                            if index < wordBank.words.count - 1 {
                                Divider()
                                    .padding(.leading, 16)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 4)
                }

                Divider()

                HStack {
                    Text("\(wordBank.words.count) word\(wordBank.words.count == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
        }
    }

    private func addCurrentWord() {
        let trimmed = newWord.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        wordBank.add(trimmed)
        newWord = ""
        isInputFocused = true
    }

    private func wordRow(_ word: String, at index: Int) -> some View {
        HStack {
            Text(word)
                .font(.system(size: 13))
                .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                wordBank.remove(at: IndexSet([index]))
            } label: {
                Image(systemName: "trash")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .help("Remove word")
        }
        .padding(.vertical, 8)
    }
}
