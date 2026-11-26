import SwiftUI
import PLACore

/// P-01: Bilingual Indonesian + English natural-language quick-add bar with vibrant live parsed preview chips.
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
                PLAIconBadge(
                    systemName: "sparkles",
                    color: PLATokens.Colors.indigo,
                    size: 32,
                    iconFont: .caption.weight(.bold)
                )

                TextField("Ketik cepat: rapat besok jam 3 sore / meeting at 3pm", text: $phrase)
                    .submitLabel(.done)
                    .onSubmit {
                        submit()
                    }

                if canSubmit {
                    Button("Simpan") {
                        submit()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(PLATokens.Colors.indigo)
                    .controlSize(.small)
                    .frame(minHeight: 36)
                }
            }

            if canSubmit {
                VStack(alignment: .leading, spacing: PLATokens.Spacing.xs) {
                    Text("Pratinjau: \(preview.title)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.primary)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: PLATokens.Spacing.xs) {
                            if let due = preview.dueDate {
                                StatusBadge(
                                    text: PLAFormatters.relativeDayLabel(due, today: store.today),
                                    icon: "calendar",
                                    color: PLATokens.Colors.indigo
                                )
                            }
                            if let mins = preview.dueTimeMinutes {
                                StatusBadge(
                                    text: PLAFormatters.time24(mins),
                                    icon: "clock.fill",
                                    color: PLATokens.Colors.info
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
                                let cat = store.categories.first { $0.id == catId }
                                let color = cat.map { PLATokens.color(forToken: $0.colorToken) } ?? PLATokens.Colors.accent
                                StatusBadge(
                                    text: store.categoryName(for: catId),
                                    icon: "tag.fill",
                                    color: color
                                )
                            } else if let rawTag = preview.rawCategoryTag {
                                StatusBadge(
                                    text: "#\(rawTag)",
                                    icon: "tag",
                                    color: .secondary
                                )
                            }
                        }
                    }
                }
            }
        }
        .padding(.vertical, PLATokens.Spacing.xs)
    }

    private func submit() {
        guard canSubmit else { return }
        store.createTaskFromNaturalLanguage(phrase)
        phrase = ""
    }
}
