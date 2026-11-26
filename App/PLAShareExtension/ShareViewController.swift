import UIKit
import SwiftUI
import UniformTypeIdentifiers
import PLACore

/// P-06: Native iOS Share Extension for offline Apple Vision OCR receipt capture (PRD §18 P-06 & §13.4).
/// Processes shared receipt images strictly in memory, discards image bytes immediately,
/// and hands off only text metadata via App Group + `pla://ocr-draft` deep link fallback.
@objc(ShareViewController)
final class ShareViewController: UIViewController {
    private let viewModel = ShareExtensionViewModel()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        let rootView = ShareOCRReviewView(
            viewModel: viewModel,
            onContinueToApp: { [weak self] payload in
                self?.handoffAndDismiss(payload: payload)
            },
            onCancel: { [weak self] in
                self?.extensionContext?.cancelRequest(
                    withError: NSError(domain: "id.revand.pla.share", code: 0, userInfo: nil)
                )
            }
        )

        let hosting = UIHostingController(rootView: rootView)
        addChild(hosting)
        hosting.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(hosting.view)
        NSLayoutConstraint.activate([
            hosting.view.topAnchor.constraint(equalTo: view.topAnchor),
            hosting.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            hosting.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hosting.view.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
        hosting.didMove(toParent: self)

        extractAndProcessSharedImage()
    }

    private func extractAndProcessSharedImage() {
        guard let items = extensionContext?.inputItems as? [NSExtensionItem] else {
            viewModel.setError("Tidak ada gambar struk yang diterima dari Share Sheet.")
            return
        }

        let imageProviders: [NSItemProvider] = items
            .compactMap(\.attachments)
            .flatMap { $0 }
            .filter { $0.hasItemConformingToTypeIdentifier(UTType.image.identifier) }

        guard let provider = imageProviders.first else {
            viewModel.setError("Konten yang dibagikan bukan gambar. Bagikan foto atau screenshot bukti transfer.")
            return
        }

        provider.loadItem(forTypeIdentifier: UTType.image.identifier, options: nil) { [weak self] item, error in
            guard let self else { return }
            if let error {
                _Concurrency.Task { @MainActor in
                    self.viewModel.setError("Gagal memuat gambar: \(error.localizedDescription)")
                }
                return
            }

            let imageData: Data?
            if let url = item as? URL {
                imageData = try? Data(contentsOf: url)
            } else if let image = item as? UIImage {
                imageData = image.jpegData(compressionQuality: 0.9)
            } else if let rawData = item as? Data {
                imageData = rawData
            } else {
                imageData = nil
            }

            guard let data = imageData, !data.isEmpty else {
                _Concurrency.Task { @MainActor in
                    self.viewModel.setError("Format gambar tidak dapat dibaca oleh Apple Vision.")
                }
                return
            }

            let today = LocalDate.from(date: Date(), timeZone: .current)
            _Concurrency.Task {
                let parsed = await PLASharedOCR.recognizeAndParse(imageData: data, fallbackDate: today)
                await MainActor.run {
                    self.viewModel.applyParsedResult(parsed, fallbackDate: today)
                }
            }
        }
    }

    private func handoffAndDismiss(payload: SharedOCRReceiptPayload) {
        let savedToAppGroup = PLASharedContainer.savePendingOCRDraft(payload)
        let deepLinkURL = PLAURLRoute.makeOCRDraftURL(payload)

        if let url = deepLinkURL {
            extensionContext?.open(url) { [weak self] opened in
                DispatchQueue.main.async {
                    if opened || savedToAppGroup {
                        self?.extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
                    } else {
                        self?.viewModel.setManualOpenHint(
                            "Draft teks siap. Buka aplikasi Life Assistant secara manual untuk menyimpan transaksi."
                        )
                    }
                }
            }
        } else {
            extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
        }
    }
}

// MARK: - ViewModel & SwiftUI Share Sheet UI

@MainActor
@Observable
private final class ShareExtensionViewModel {
    enum Phase {
        case scanning
        case ready
        case failed(String)
    }

    var phase: Phase = .scanning
    var amountText: String = ""
    var merchantText: String = ""
    var detectedDate: LocalDate = LocalDate.from(date: Date(), timeZone: .current)
    var detectedSourceApp: String?
    var rawLineCount: Int = 0
    var manualOpenHint: String?

    func applyParsedResult(_ parsed: ParsedReceiptOCR, fallbackDate: LocalDate) {
        self.detectedDate = parsed.date ?? fallbackDate
        self.detectedSourceApp = parsed.detectedSourceApp
        self.rawLineCount = parsed.rawLineCount
        self.merchantText = parsed.merchant ?? ""
        if let amt = parsed.amount {
            self.amountText = String(amt)
        } else {
            self.amountText = ""
        }
        self.phase = .ready
    }

    func setError(_ message: String) {
        self.phase = .failed(message)
    }

    func setManualOpenHint(_ hint: String) {
        self.manualOpenHint = hint
    }

    func makePayload() -> SharedOCRReceiptPayload {
        let finalAmount: Int64?
        switch AmountParser.parse(amountText) {
        case .success(let money):
            finalAmount = money.rupiah
        case .failure:
            finalAmount = nil
        }

        let trimmedMerchant = merchantText.trimmingCharacters(in: .whitespacesAndNewlines)
        return SharedOCRReceiptPayload(
            amount: finalAmount,
            date: detectedDate,
            merchant: trimmedMerchant.isEmpty ? nil : trimmedMerchant,
            detectedSourceApp: detectedSourceApp,
            rawLineCount: rawLineCount,
            createdAt: Date()
        )
    }
}

private struct ShareOCRReviewView: View {
    @Bindable var viewModel: ShareExtensionViewModel
    let onContinueToApp: (SharedOCRReceiptPayload) -> Void
    let onCancel: () -> Void

    @Environment(\.openURL) private var openURL

    var body: some View {
        NavigationStack {
            Group {
                switch viewModel.phase {
                case .scanning:
                    VStack(spacing: 16) {
                        ProgressView()
                            .controlSize(.large)
                        Text("Membaca struk secara offline...")
                            .font(.headline)
                        Text("Apple Vision memproses gambar di memori perangkat. Foto tidak pernah disimpan.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                case .failed(let message):
                    VStack(spacing: 14) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.largeTitle)
                            .foregroundStyle(.orange)
                        Text("Tidak Dapat Memproses Gambar")
                            .font(.headline)
                        Text(message)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                        Button("Tutup", action: onCancel)
                            .buttonStyle(.borderedProminent)
                            .tint(Color(red: 0.06, green: 0.46, blue: 0.43))
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                case .ready:
                    Form {
                        Section {
                            HStack(spacing: 8) {
                                Label("Teks terbaca (\(viewModel.rawLineCount) baris)", systemImage: "checkmark.seal.fill")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.green)
                                Spacer()
                                if let app = viewModel.detectedSourceApp {
                                    Text(app)
                                        .font(.caption.weight(.semibold))
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 3)
                                        .background(Color.teal.opacity(0.15))
                                        .foregroundStyle(.teal)
                                        .clipShape(Capsule())
                                }
                            }

                            HStack {
                                Text("Rp")
                                    .font(.headline)
                                    .foregroundStyle(.secondary)
                                TextField("Nominal (mis. 45000)", text: $viewModel.amountText)
                                    .keyboardType(.numberPad)
                            }

                            TextField("Merchant / Catatan", text: $viewModel.merchantText)

                            HStack {
                                Text("Tanggal Terbaca")
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text(viewModel.detectedDate.isoString)
                                    .font(.subheadline.weight(.medium))
                            }
                        } header: {
                            Text("Hasil OCR Lokal (Apple Vision)")
                        } footer: {
                            Text("Hanya teks nominal, tanggal, dan merchant yang dikirim ke Life Assistant. Gambar struk langsung dihapus dari memori.")
                        }

                        if let hint = viewModel.manualOpenHint {
                            Section {
                                Label(hint, systemImage: "info.circle.fill")
                                    .font(.footnote)
                                    .foregroundStyle(.teal)
                            }
                        }

                        Section {
                            Button {
                                let payload = viewModel.makePayload()
                                // Attempt SwiftUI openURL first alongside extensionContext handoff
                                if let url = PLAURLRoute.makeOCRDraftURL(payload) {
                                    PLASharedContainer.savePendingOCRDraft(payload)
                                    openURL(url)
                                }
                                onContinueToApp(payload)
                            } label: {
                                HStack {
                                    Spacer()
                                    Label("Buka & Simpan di Life Assistant", systemImage: "arrow.up.forward.app.fill")
                                        .font(.headline)
                                    Spacer()
                                }
                                .frame(minHeight: 44)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(Color(red: 0.06, green: 0.46, blue: 0.43))
                            .listRowBackground(Color.clear)
                            .listRowInsets(EdgeInsets())
                        }
                    }
                }
            }
            .navigationTitle("Catat Struk (OCR)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Batal", action: onCancel)
                }
            }
        }
    }
}
