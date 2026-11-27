import SwiftUI
import PLACore

/// P-01: Bilingual Indonesian + English natural-language quick-add bar with crisp White & Blue styling and live parsed preview chips.
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
        PLACard(padding: PLATokens.Spacing.md, cornerRadius: 18) {
            VStack(alignment: .leading, spacing: PLATokens.Spacing.sm) {
                HStack(spacing: PLATokens.Spacing.sm) {
                    PLAIconBadge(
                        systemName: "text.badge.plus",
                        color: PLATokens.Colors.accent,
                        size: 34,
                        iconFont: .subheadline.weight(.semibold)
                    )

                    TextField("Ketik cepat: rapat besok jam 3 sore / meeting at 3pm", text: $phrase)
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
                        .frame(minHeight: 36)
                        .background(PLATokens.Colors.primaryBlue, in: Capsule())
                        .buttonStyle(.plain)
                    }
                }

                if canSubmit {
                    VStack(alignment: .leading, spacing: PLATokens.Spacing.xs) {
                        Text("Pratinjau: \(preview.title)")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(PLATokens.Colors.textPrimary)

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: PLATokens.Spacing.xs) {
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
                        }
                    }
                    .padding(.top, 2)
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
