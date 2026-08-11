import UIKit
import UniformTypeIdentifiers
import OSLog

final class ShareViewController: UIViewController {
    private let appGroup = "group.net.vipertec.viperchat"
    private let pendingShareKey = "viper.pending-share"
    private let maximumFiles = 10
    private let logger = Logger(
        subsystem: "net.vipertec.viperchat.share",
        category: "ShareExtension"
    )

    private lazy var statusLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .preferredFont(forTextStyle: .body)
        label.text = "Preparando compartilhamento…"
        label.textAlignment = .center
        label.numberOfLines = 0
        return label
    }()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        view.addSubview(statusLabel)
        NSLayoutConstraint.activate([
            statusLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            statusLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            statusLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])

        Task { await importShare() }
    }

    @MainActor
    private func importShare() async {
        guard let container = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroup
        ) else {
            finishWithError("Não foi possível acessar o compartilhamento do ViperChat.")
            return
        }

        let shareDirectory = container.appendingPathComponent("shared", isDirectory: true)
        do {
            try FileManager.default.createDirectory(
                at: shareDirectory,
                withIntermediateDirectories: true
            )

            var files: [[String: Any]] = []
            var texts: [String] = []
            let providers = extensionContext?.inputItems
                .compactMap { $0 as? NSExtensionItem }
                .flatMap { $0.attachments ?? [] } ?? []

            for provider in providers {
                if files.count < maximumFiles,
                   let file = try await importFile(from: provider, into: shareDirectory) {
                    files.append(file)
                    continue
                }
                if let text = try await importText(from: provider), !text.isEmpty {
                    texts.append(text)
                }
            }

            let payload: [String: Any] = [
                "subject": extensionContext?.inputItems
                    .compactMap { ($0 as? NSExtensionItem)?.attributedTitle?.string }
                    .first ?? "",
                "text": texts.joined(separator: "\n"),
                "files": files
            ]
            let data = try JSONSerialization.data(withJSONObject: payload)
            UserDefaults(suiteName: appGroup)?.set(data, forKey: pendingShareKey)

            statusLabel.text = "Abrindo o ViperChat…"
            let appURL = URL(string: "viperchat://share")!
            extensionContext?.open(appURL) { [weak self] opened in
                guard let self else { return }
                if opened {
                    self.extensionContext?.completeRequest(returningItems: nil)
                    return
                }

                self.logger.notice("iOS retained the user in the share extension")
                DispatchQueue.main.async {
                    self.statusLabel.text = "Mídia preparada. Abra o ViperChat para escolher a conversa."
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        self.extensionContext?.completeRequest(returningItems: nil)
                    }
                }
            }
        } catch {
            logger.error("Share import failed: \(error.localizedDescription, privacy: .public)")
            finishWithError("Não foi possível importar este conteúdo.")
        }
    }

    private func importFile(
        from provider: NSItemProvider,
        into directory: URL
    ) async throws -> [String: Any]? {
        let identifier = provider.registeredTypeIdentifiers.first { identifier in
            guard let type = UTType(identifier) else { return false }
            return type.conforms(to: .image) || type.conforms(to: .movie) ||
                type.conforms(to: .audio) || type.conforms(to: .pdf) ||
                type.conforms(to: .data)
        }
        guard let identifier else { return nil }

        let type = UTType(identifier)
        let suggestedName = provider.suggestedName

        // The URL supplied by loadFileRepresentation is valid only while its
        // completion handler is running. Copy it into the App Group before
        // returning from the callback so Photos cannot remove the temporary
        // representation first.
        return try await withCheckedThrowingContinuation { continuation in
            provider.loadFileRepresentation(forTypeIdentifier: identifier) { url, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let url {
                    do {
                        var name = suggestedName ?? url.lastPathComponent
                        if URL(fileURLWithPath: name).pathExtension.isEmpty,
                           let extensionName = type?.preferredFilenameExtension {
                            name += ".\(extensionName)"
                        }
                        let safeName = name.replacingOccurrences(
                            of: "[^A-Za-z0-9._-]",
                            with: "_",
                            options: .regularExpression
                        )
                        let destination = directory.appendingPathComponent(
                            "\(UUID().uuidString)-\(safeName.isEmpty ? "arquivo" : safeName)"
                        )
                        try FileManager.default.copyItem(at: url, to: destination)
                        let size = (try? destination.resourceValues(
                            forKeys: [.fileSizeKey]
                        ).fileSize) ?? 0

                        continuation.resume(returning: [
                            "name": name,
                            "type": type?.preferredMIMEType ?? "application/octet-stream",
                            "size": size,
                            "path": destination.path,
                            "uri": destination.absoluteString
                        ])
                    } catch {
                        continuation.resume(throwing: error)
                    }
                } else {
                    continuation.resume(throwing: CocoaError(.fileReadUnknown))
                }
            }
        }
    }

    private func importText(from provider: NSItemProvider) async throws -> String? {
        let identifier: String
        if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
            identifier = UTType.url.identifier
        } else if provider.hasItemConformingToTypeIdentifier(UTType.text.identifier) {
            identifier = UTType.text.identifier
        } else {
            return nil
        }

        let item: NSSecureCoding = try await withCheckedThrowingContinuation { continuation in
            provider.loadItem(forTypeIdentifier: identifier) { item, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let item {
                    continuation.resume(returning: item)
                } else {
                    continuation.resume(throwing: CocoaError(.fileReadUnknown))
                }
            }
        }
        if let url = item as? URL { return url.absoluteString }
        return item as? String
    }

    @MainActor
    private func finishWithError(_ message: String) {
        statusLabel.text = message
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            let error = NSError(
                domain: "net.vipertec.viperchat.share",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: message]
            )
            self?.extensionContext?.cancelRequest(withError: error)
        }
    }
}
