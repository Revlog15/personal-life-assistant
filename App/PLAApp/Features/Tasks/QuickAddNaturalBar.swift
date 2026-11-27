import SwiftUI
import PLACore

/// P-01: Minimalist single-line natural-language quick-add bar (no heavy outer card box).
/// Expands live parsed preview chips only while the user is typing.
struct QuickAddNaturalBar: View {
    @Environment(AppStore.self) private var store
    @State private var phrase: String = ""

    private var preview: ParsedQuickTask {
        NaturalLanguageTaskParser.parse(phrase, today: store.today, categories: store.categories)
    }

    private var canSubmit: Bool {
        PLATask.isValidTitle(preview.title) && !phrase.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: PLATokens.Spacing.sm) {
            HStack(spacing: PLATokens.Spacing.sm) {
                Image(systemName: "plus.circle.fill")
                    .font(.body)
                    .foregroundStyle(PLATokens.Colors.accent)
                    .accessibilityHidden(true)

                TextField("Ketik cepat: rapat besok jam 3 sore...", text: $phrase)
                    .font(.subheadline)
                    .foregroundStyle(PLATokens.Colors.textPrimary)
                    .submitLabel(.done)
                    .onSubmit {
                        submit()
                    }

                if canSubmit {
                    Button("Simpan") {
                        submit()
                    }
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color.white)
                    .padding(.horizontal, 12)
                    .frame(minHeight: 34)
                    .background(PLATokens.Colors.primaryBlue, in: Capsule())
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 46)
            .background(PLATokens.Colors.surface, in: Capsule())

            if canSubmit {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: PLATokens.Spacing.xs) {
                        Text(preview.title)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(PLATokens.Colors.textPrimary)
                            .padding(.trailing, 4)

                        if let due = preview.dueDate {
                            StatusBadge(
                                text: PLAFormatters.relativeDayLabel(due, today: store.today),
                                icon: "calendar",
                                color: PLATokens.Colors.accent
                            )
                        }
                        if let mins = preview.dueTimeMinutes {
                            StatusBadge(
                                text: PLAFormatters.time24(mins),
                                icon: "clock.fill",
                                color: PLATokens.Colors.accent
                            )
                        }
                        if preview.priorityExplicitlySet {
                            StatusBadge(
                                text: PLATokens.label(for: preview.priority),
                                icon: PLATokens.icon(for: preview.priority),
                                color: PLATokens.color(for: preview.priority)
                            )
                        }
                        if let catId = preview.matchedCategoryId {
                            StatusBadge(
                                text: store.categoryName(for: catId),
                                icon: "tag.fill",
                                color: PLATokens.Colors.accent
                            )
                        } else if let rawTag = preview.rawCategoryTag {
                            StatusBadge(
                                text: "#\(rawTag)",
                                icon: "tag",
                                color: PLATokens.Colors.textSecondary
                            )
                        }
                    }
                    .padding(.horizontal, 4)
                }
            }
        }
    }

    private func submit() {
        guard canSubmit else { return }
        store.createTaskFromNaturalLanguage(phrase)
        phrase = ""
    }
}
