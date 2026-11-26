import UIKit
import SwiftUI
import UniformTypeIdentifiers
import PLACore

/// P-06: Native iOS Share Extension for offline Apple Vision OCR receipt capture (PRD §18 P-06 & §13.4).
/// Uses cascading iOS 17/18 image loading (`loadFileRepresentation` -> `loadDataRepresentation` -> `UIImage` -> security-scoped `loadItem`)
/// + memory-safe downscaling (<= 1800px) to avoid Share Extension RAM limits, discards image bytes immediately,
/// and hands off text-only metadata via App Group + `pla://ocr-draft` deep link.
@objc(ShareViewController)
final class ShareViewController: UIViewController {
    private let viewModel = ShareExtensionViewModel()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemGroupedBackground

        let rootView = ShareOCRReviewView(
            viewModel: viewModel,
            onSaveAndHandoff: { [weak self] payload in
                self?.handoffDraft(payload: payload)
            },
            onDone: { [weak self] in
                self?.extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
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
            viewModel.setError("Tidak ada konten gambar yang diterima dari Share Sheet.")
            return
        }

        let providers = items.compactMap(\.attachments).flatMap { $0 }
        guard let provider = providers.first(where: { p in
            p.hasItemConformingToTypeIdentifier(UTType.image.identifier) ||
            p.hasItemConformingToTypeIdentifier(UTType.jpeg.identifier) ||
            p.hasItemConformingToTypeIdentifier(UTType.png.identifier) ||
            p.hasItemConformingToTypeIdentifier(UTType.heic.identifier) ||
            p.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier)
        }) else {
            viewModel.setError("Konten yang dibagikan bukan gambar. Bagikan screenshot atau foto bukti transfer.")
            return
        }

        loadImageData(from: provider) { [weak self] imageData in
            guard let self else { return }
            guard let data = imageData, !data.isEmpty else {
                _Concurrency.Task { @MainActor in
                    self.viewModel.setError("Gambar tidak dapat dibaca dari aplikasi pengirim. Coba simpan ke Photos lalu pilih dari tombol Scan Struk OCR di dalam Life Assistant.")
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

    /// 4-tier iOS 17/18 safe image loader handling Photos HEIC/JPEG/PNG, Screenshot Editor UIImage, WhatsApp, and Files.
    private func loadImageData(from provider: NSItemProvider, completion: @escaping (Data?) -> Void) {
        let imageTypeId: String
        if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
            imageTypeId = UTType.image.identifier
        } else if provider.hasItemConformingToTypeIdentifier(UTType.jpeg.identifier) {
            imageTypeId = UTType.jpeg.identifier
        } else if provider.hasItemConformingToTypeIdentifier(UTType.png.identifier) {
            imageTypeId = UTType.png.identifier
        } else if provider.hasItemConformingToTypeIdentifier(UTType.heic.identifier) {
            imageTypeId = UTType.heic.identifier
        } else {
            imageTypeId = UTType.fileURL.identifier
        }

        // Tier 1: loadFileRepresentation (preferred by iOS Photos & HEIC; copy bytes before callback exits)
        provider.loadFileRepresentation(forTypeIdentifier: imageTypeId) { url, _ in
            if let url {
                let accessed = url.startAccessingSecurityScopedResource()
                defer { if accessed { url.stopAccessingSecurityScopedResource() } }
                if let data = try? Data(contentsOf: url), !data.isEmpty {
                    completion(data)
                    return
                }
            }

            // Tier 2: loadDataRepresentation (direct raw bytes)
            provider.loadDataRepresentation(forTypeIdentifier: imageTypeId) { data, _ in
                if let data, !data.isEmpty {
                    completion(data)
                    return
                }

                // Tier 3: UIImage object (iOS Screenshot preview / clipboard share)
                if provider.canLoadObject(ofClass: UIImage.self) {
                    _ = provider.loadObject(ofClass: UIImage.self) { obj, _ in
                        if let image = obj as? UIImage,
                           let jpeg = image.jpegData(compressionQuality: 0.85) {
                            completion(jpeg)
                            return
                        }
                        Self.loadFallbackItem(provider: provider, typeId: imageTypeId, completion: completion)
                    }
                } else {
                    Self.loadFallbackItem(provider: provider, typeId: imageTypeId, completion: completion)
                }
            }
        }
    }

    private static func loadFallbackItem(
        provider: NSItemProvider,
        typeId: String,
        completion: @escaping (Data?) -> Void
    ) {
        provider.loadItem(forTypeIdentifier: typeId, options: nil) { item, _ in
            if let url = item as? URL {
                let accessed = url.startAccessingSecurityScopedResource()
                defer { if accessed { url.stopAccessingSecurityScopedResource() } }
                completion(try? Data(contentsOf: url))
            } else if let image = item as? UIImage {
                completion(image.jpegData(compressionQuality: 0.85))
            } else if let data = item as? Data {
                completion(data)
            } else {
                completion(nil)
            }
        }
    }

    private func handoffDraft(payload: SharedOCRReceiptPayload) {
        let savedToAppGroup = PLASharedContainer.savePendingOCRDraft(payload)
        let deepLinkURL = PLAURLRoute.makeOCRDraftURL(payload)

        if let url = deepLinkURL {
            extensionContext?.open(url) { [weak self] opened in
                DispatchQueue.main.async {
                    if opened {
                        self?.extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
                    } else if savedToAppGroup {
                        self?.viewModel.markSavedWaitingForManualOpen(
                            "Draft struk sudah tersimpan aman! Buka aplikasi Life Assistant sekarang — layar tinjau transaksi akan langsung muncul otomatis."
                        )
                    } else {
                        self?.viewModel.markSavedWaitingForManualOpen(
                            "App Group tidak tersedia di profil sideload ini. Gunakan tombol Scan Struk OCR di dalam Life Assistant atau Shortcut 'Scan Struk ke Life Assistant'."
                        )
                    }
                }
            }
        } else if savedToAppGroup {
            viewModel.markSavedWaitingForManualOpen(
                "Draft struk sudah tersimpan! Buka Life Assistant untuk menyelesaikan simpan transaksi."
            )
        } else {
            extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
        }
    }
}

// MARK: - Formatting Helper (Dot Thousand Separators: 1.000.000)

private enum ShareNumberFormat {
    static func formatDots(_ raw: String) -> String {
        let digits = raw.filter(\.isNumber)
        guard !digits.isEmpty else { return "" }
        let trimmedLeading = String(digits.drop(while: { $0 == "0" }))
        let clean = trimmedLeading.isEmpty ? "0" : String(trimmedLeading.prefix(12))
        let chars = Array(clean)
        var out = ""
        for idx in chars.indices {
            if idx > 0 && (chars.count - idx) % 3 == 0 { out.append(".") }
            out.append(chars[idx])
        }
        return out
    }
}

// MARK: - ViewModel & SwiftUI Share Sheet UI

@MainActor
@Observable
private final class ShareExtensionViewModel {
    enum Phase {
        case scanning
        case ready
        case savedWaiting
        case failed(String)
    }

    var phase: Phase = .scanning
    var amountText: String = ""
    var merchantText: String = ""
    var detectedDate: LocalDate = LocalDate.from(date: Date(), timeZone: .current)
    var detectedSourceApp: String?
    var rawLineCount: Int = 0
    var statusMessage: String?

    func applyParsedResult(_ parsed: ParsedReceiptOCR, fallbackDate: LocalDate) {
        self.detectedDate = parsed.date ?? fallbackDate
        self.detectedSourceApp = parsed.detectedSourceApp
        self.rawLineCount = parsed.rawLineCount
        self.merchantText = parsed.merchant ?? ""
        if let amt = parsed.amount {
            self.amountText = ShareNumberFormat.formatDots(String(amt))
        } else {
            self.amountText = ""
        }
        self.phase = .ready
    }

    func setError(_ message: String) {
        self.phase = .failed(message)
    }

    func markSavedWaitingForManualOpen(_ message: String) {
        self.statusMessage = message
        self.phase = .savedWaiting
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
    let onSaveAndHandoff: (SharedOCRReceiptPayload) -> Void
    let onDone: () -> Void
    let onCancel: () -> Void

    @Environment(\.openURL) private var openURL
    private let brandTeal = Color(red: 0.06, green: 0.46, blue: 0.43)

    var body: some View {
        NavigationStack {
            Group {
                switch viewModel.phase {
                case .scanning:
                    VStack(spacing: 16) {
                        ZStack {
                            Circle()
                                .fill(brandTeal.opacity(0.14))
                                .frame(width: 72, height: 72)
                            ProgressView()
                                .controlSize(.large)
                                .tint(brandTeal)
                        }
                        Text("Membaca struk secara offline...")
                            .font(.headline)
                        Text("Apple Vision memproses gambar di memori perangkat. Foto tidak pernah disimpan.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                case .savedWaiting:
                    VStack(spacing: 16) {
                        ZStack {
                            Circle()
                                .fill(Color.green.opacity(0.16))
                                .frame(width: 72, height: 72)
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 36))
                                .foregroundStyle(.green)
                        }
                        Text("Draft Struk Siap")
                            .font(.title3.weight(.bold))
                        Text(viewModel.statusMessage ?? "Buka Life Assistant untuk menyelesaikan simpan transaksi.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                        Button("Selesai", action: onDone)
                            .buttonStyle(.borderedProminent)
                            .tint(brandTeal)
                            .frame(minHeight: 44)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                case .failed(let message):
                    VStack(spacing: 14) {
                        ZStack {
                            Circle()
                                .fill(Color.orange.opacity(0.16))
                                .frame(width: 72, height: 72)
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 32))
                                .foregroundStyle(.orange)
                        }
                        Text("Tidak Dapat Memproses Gambar")
                            .font(.headline)
                        Text(message)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                        Button("Tutup", action: onCancel)
                            .buttonStyle(.borderedProminent)
                            .tint(brandTeal)
                            .frame(minHeight: 44)
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
                                        .background(brandTeal.opacity(0.15))
                                        .foregroundStyle(brandTeal)
                                        .clipShape(Capsule())
                                }
                            }

                            HStack(spacing: 8) {
                                Text("Rp")
                                    .font(.headline)
                                    .foregroundStyle(brandTeal)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(brandTeal.opacity(0.12), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                                TextField("Contoh: 45.000", text: $viewModel.amountText)
                                    .font(.title3.weight(.bold))
                                    .monospacedDigit()
                                    .keyboardType(.numberPad)
                                    .onChange(of: viewModel.amountText) { _, newVal in
                                        let formatted = ShareNumberFormat.formatDots(newVal)
                                        if formatted != newVal {
                                            viewModel.amountText = formatted
                                        }
                                    }
                            }

                            TextField("Merchant / Catatan", text: $viewModel.merchantText)

                            HStack {
                                Text("Tanggal Terbaca")
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text(viewModel.detectedDate.isoString)
                                    .font(.subheadline.weight(.medium))
                                    .monospacedDigit()
                            }
                        } header: {
                            Text("Hasil OCR Lokal (Apple Vision)")
                        } footer: {
                            Text("Hanya teks nominal, tanggal, dan merchant yang dikirim ke Life Assistant. Gambar struk langsung dihapus dari memori.")
                        }

                        Section {
                            Button {
                                let payload = viewModel.makePayload()
                                PLASharedContainer.savePendingOCRDraft(payload)
                                if let url = PLAURLRoute.makeOCRDraftURL(payload) {
                                    openURL(url)
                                }
                                onSaveAndHandoff(payload)
                            } label: {
                                HStack {
                                    Spacer()
                                    Label("Simpan Draft & Buka Life Assistant", systemImage: "arrow.up.forward.app.fill")
                                        .font(.headline)
                                    Spacer()
                                }
                                .frame(minHeight: 46)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(brandTeal)
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
