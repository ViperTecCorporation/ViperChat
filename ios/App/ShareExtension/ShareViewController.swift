import UIKit
import UniformTypeIdentifiers
import OSLog
import Security

private struct SharedConversation {
    let id: Int
    let name: String
    let subtitle: String
    let avatarURL: URL?
}

private enum ShareExtensionError: LocalizedError {
    case invalidSession
    case unauthorized
    case invalidResponse
    case uploadFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidSession:
            return "Abra o ViperChat e entre novamente para compartilhar."
        case .unauthorized:
            return "Sua sessão expirou. Abra o ViperChat e entre novamente."
        case .invalidResponse:
            return "O servidor retornou uma resposta inválida."
        case .uploadFailed(let message):
            return message
        }
    }
}

@MainActor
final class ShareViewController: UIViewController {
    private let appGroup = "group.net.vipertec.viperchat"
    private let pendingShareKey = "viper.pending-share"
    private let shareContextKey = "viper:native:share-context"
    private let keychainService = "net.vipertec.viperchat.secure-storage"
    private let maximumFiles = 10
    private let logger = Logger(
        subsystem: "net.vipertec.viperchat.share",
        category: "ShareExtension"
    )

    private var context: [String: Any] = [:]
    private var session: [String: Any] = [:]
    private var sharedFiles: [[String: Any]] = []
    private var sharedText = ""
    private var conversations: [SharedConversation] = []
    private var selectedConversation: SharedConversation?
    private var searchTask: Task<Void, Never>?

    private lazy var titleLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .preferredFont(forTextStyle: .headline)
        label.text = "Compartilhar no ViperChat"
        return label
    }()

    private lazy var cancelButton: UIButton = {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setTitle("Cancelar", for: .normal)
        button.addTarget(self, action: #selector(cancelShare), for: .touchUpInside)
        return button
    }()

    private lazy var summaryLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .preferredFont(forTextStyle: .subheadline)
        label.textColor = .secondaryLabel
        label.numberOfLines = 2
        return label
    }()

    private lazy var searchBar: UISearchBar = {
        let search = UISearchBar()
        search.translatesAutoresizingMaskIntoConstraints = false
        search.placeholder = "Pesquisar conversa ou contato"
        search.autocapitalizationType = .none
        search.delegate = self
        return search
    }()

    private lazy var tableView: UITableView = {
        let table = UITableView(frame: .zero, style: .plain)
        table.translatesAutoresizingMaskIntoConstraints = false
        table.dataSource = self
        table.delegate = self
        table.keyboardDismissMode = .onDrag
        table.rowHeight = 60
        table.tableFooterView = UIView()
        return table
    }()

    private lazy var sendButton: UIButton = {
        var configuration = UIButton.Configuration.filled()
        configuration.title = "Selecione uma conversa"
        configuration.cornerStyle = .large
        configuration.baseBackgroundColor = UIColor(
            red: 0.09,
            green: 0.45,
            blue: 0.72,
            alpha: 1
        )
        let button = UIButton(configuration: configuration)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.isEnabled = false
        button.addTarget(self, action: #selector(sendShare), for: .touchUpInside)
        return button
    }()

    private lazy var statusLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .preferredFont(forTextStyle: .body)
        label.text = "Preparando compartilhamento…"
        label.textAlignment = .center
        label.numberOfLines = 0
        return label
    }()

    private lazy var activityIndicator: UIActivityIndicatorView = {
        let indicator = UIActivityIndicatorView(style: .medium)
        indicator.translatesAutoresizingMaskIntoConstraints = false
        indicator.startAnimating()
        return indicator
    }()

    override func viewDidLoad() {
        super.viewDidLoad()
        configureView()
        Task { await prepareShare() }
    }

    private func configureView() {
        view.backgroundColor = .systemBackground
        [titleLabel, cancelButton, summaryLabel, searchBar, tableView, sendButton,
         statusLabel, activityIndicator].forEach(view.addSubview)

        let guide = view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: guide.leadingAnchor, constant: 20),
            titleLabel.topAnchor.constraint(equalTo: guide.topAnchor, constant: 18),
            cancelButton.trailingAnchor.constraint(equalTo: guide.trailingAnchor, constant: -16),
            cancelButton.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: cancelButton.leadingAnchor, constant: -12),

            summaryLabel.leadingAnchor.constraint(equalTo: guide.leadingAnchor, constant: 20),
            summaryLabel.trailingAnchor.constraint(equalTo: guide.trailingAnchor, constant: -20),
            summaryLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 8),

            searchBar.leadingAnchor.constraint(equalTo: guide.leadingAnchor, constant: 8),
            searchBar.trailingAnchor.constraint(equalTo: guide.trailingAnchor, constant: -8),
            searchBar.topAnchor.constraint(equalTo: summaryLabel.bottomAnchor, constant: 8),

            tableView.leadingAnchor.constraint(equalTo: guide.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: guide.trailingAnchor),
            tableView.topAnchor.constraint(equalTo: searchBar.bottomAnchor),
            tableView.bottomAnchor.constraint(equalTo: sendButton.topAnchor, constant: -12),

            sendButton.leadingAnchor.constraint(equalTo: guide.leadingAnchor, constant: 20),
            sendButton.trailingAnchor.constraint(equalTo: guide.trailingAnchor, constant: -20),
            sendButton.bottomAnchor.constraint(equalTo: guide.bottomAnchor, constant: -14),
            sendButton.heightAnchor.constraint(equalToConstant: 48),

            statusLabel.leadingAnchor.constraint(equalTo: guide.leadingAnchor, constant: 28),
            statusLabel.trailingAnchor.constraint(equalTo: guide.trailingAnchor, constant: -28),
            statusLabel.centerYAnchor.constraint(equalTo: guide.centerYAnchor),
            activityIndicator.centerXAnchor.constraint(equalTo: guide.centerXAnchor),
            activityIndicator.bottomAnchor.constraint(equalTo: statusLabel.topAnchor, constant: -14)
        ])

        setPickerVisible(false)
    }

    private func setPickerVisible(_ visible: Bool) {
        titleLabel.isHidden = !visible
        summaryLabel.isHidden = !visible
        searchBar.isHidden = !visible
        tableView.isHidden = !visible
        sendButton.isHidden = !visible
        statusLabel.isHidden = visible
        activityIndicator.isHidden = visible
    }

    private func prepareShare() async {
        do {
            try await importShareItems()
            try loadCredentials()
            updateSummary()
            setPickerVisible(true)
            await loadConversations(query: nil)
        } catch {
            logger.error("Share preparation failed: \(error.localizedDescription, privacy: .public)")
            finishWithMessage(error.localizedDescription)
        }
    }

    private func updateSummary() {
        let fileCount = sharedFiles.count
        if fileCount > 0 && !sharedText.isEmpty {
            summaryLabel.text = "\(fileCount) mídia(s) e texto"
        } else if fileCount > 0 {
            summaryLabel.text = "\(fileCount) mídia(s) pronta(s) para enviar"
        } else {
            summaryLabel.text = "Texto pronto para enviar"
        }
    }

    private func loadCredentials() throws {
        guard let contextData = readKeychainData(account: shareContextKey),
              let contextObject = try JSONSerialization.jsonObject(with: contextData) as? [String: Any],
              let installationId = contextObject["installationId"] as? String,
              contextObject["baseUrl"] as? String != nil,
              number(from: contextObject["accountId"]) != nil else {
            throw ShareExtensionError.invalidSession
        }

        let sessionAccount = "viper:\(installationId):auth"
        guard let sessionData = readKeychainData(account: sessionAccount),
              let sessionObject = try JSONSerialization.jsonObject(with: sessionData) as? [String: Any],
              sessionObject["headers"] as? [String: Any] != nil else {
            throw ShareExtensionError.invalidSession
        }

        context = contextObject
        session = sessionObject
    }

    private func loadConversations(query: String?) async {
        activityIndicator.isHidden = false
        activityIndicator.startAnimating()
        tableView.isUserInteractionEnabled = false
        do {
            conversations = try await fetchConversations(query: query)
            selectedConversation = nil
            updateSendButton()
            tableView.reloadData()
        } catch {
            logger.error("Conversation lookup failed: \(error.localizedDescription, privacy: .public)")
            conversations = []
            tableView.reloadData()
            summaryLabel.text = error.localizedDescription
        }
        activityIndicator.stopAnimating()
        activityIndicator.isHidden = true
        tableView.isUserInteractionEnabled = true
    }

    private func fetchConversations(query: String?) async throws -> [SharedConversation] {
        let accountId = number(from: context["accountId"])!
        let path: String
        let parameters: [URLQueryItem]
        if let query, !query.isEmpty {
            path = "/api/v1/accounts/\(accountId)/search/conversations"
            parameters = [URLQueryItem(name: "q", value: query)]
        } else {
            path = "/api/v1/accounts/\(accountId)/conversations"
            parameters = [
                URLQueryItem(name: "assignee_type", value: "me"),
                URLQueryItem(name: "status", value: "all"),
                URLQueryItem(name: "sort_by", value: "last_activity_at_desc"),
                URLQueryItem(name: "page", value: "1")
            ]
        }

        let (data, response) = try await performRequest(path: path, queryItems: parameters)
        try ensureSuccess(response, data: data)
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ShareExtensionError.invalidResponse
        }

        let items: [[String: Any]]
        if query?.isEmpty == false {
            let payload = root["payload"] as? [String: Any]
            items = payload?["conversations"] as? [[String: Any]] ?? []
        } else {
            let wrapper = root["data"] as? [String: Any]
            items = wrapper?["payload"] as? [[String: Any]] ?? []
        }
        return items.prefix(30).compactMap(parseConversation)
    }

    private func parseConversation(_ object: [String: Any]) -> SharedConversation? {
        guard let id = number(from: object["id"]) else { return nil }
        let meta = object["meta"] as? [String: Any]
        let contact = (object["contact"] as? [String: Any]) ??
            (meta?["sender"] as? [String: Any]) ?? [:]
        let inbox = object["inbox"] as? [String: Any]
        let additional = object["additional_attributes"] as? [String: Any]

        let name = nonEmpty(object["group_title"] as? String) ??
            nonEmpty(contact["name"] as? String) ??
            nonEmpty(contact["phone_number"] as? String) ?? "Conversa"
        let inboxName = nonEmpty(inbox?["name"] as? String)
        let subtitle = inboxName.map { "#\(id) · \($0)" } ?? "#\(id)"
        let avatarValue = nonEmpty(object["group_picture"] as? String) ??
            nonEmpty(additional?["group_picture"] as? String) ??
            nonEmpty(contact["thumbnail"] as? String)

        return SharedConversation(
            id: id,
            name: name,
            subtitle: subtitle,
            avatarURL: resolveURL(avatarValue)
        )
    }

    @objc private func sendShare() {
        guard let selectedConversation else { return }
        searchBar.resignFirstResponder()
        setPickerVisible(false)
        statusLabel.text = "Enviando para \(selectedConversation.name)…"
        activityIndicator.startAnimating()
        Task {
            do {
                try await uploadShare(to: selectedConversation.id)
                clearPendingShare()
                statusLabel.text = "Enviado para \(selectedConversation.name)."
                activityIndicator.stopAnimating()
                activityIndicator.isHidden = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
                    self?.extensionContext?.completeRequest(returningItems: nil)
                }
            } catch {
                logger.error("Share upload failed: \(error.localizedDescription, privacy: .public)")
                setPickerVisible(true)
                summaryLabel.text = error.localizedDescription
            }
        }
    }

    private func uploadShare(to conversationId: Int) async throws {
        let accountId = number(from: context["accountId"])!
        let boundary = "ViperChat-\(UUID().uuidString)"
        let bodyURL = try buildMultipartBody(boundary: boundary)
        defer { try? FileManager.default.removeItem(at: bodyURL) }

        var request = try authenticatedRequest(
            path: "/api/v1/accounts/\(accountId)/conversations/\(conversationId)/messages"
        )
        request.httpMethod = "POST"
        request.timeoutInterval = 180
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        let (data, response) = try await URLSession.shared.upload(for: request, fromFile: bodyURL)
        persistRotatedHeaders(from: response)
        try ensureSuccess(response, data: data)
    }

    private func buildMultipartBody(boundary: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
        let url = directory.appendingPathComponent("viper-share-\(UUID().uuidString).multipart")
        FileManager.default.createFile(atPath: url.path, contents: nil)
        let output = try FileHandle(forWritingTo: url)
        defer { try? output.close() }

        func write(_ value: String) throws {
            if let data = value.data(using: .utf8) { try output.write(contentsOf: data) }
        }

        func writeField(_ name: String, _ value: String) throws {
            try write("--\(boundary)\r\n")
            try write("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n")
            try write("\(value)\r\n")
        }

        if !sharedText.isEmpty { try writeField("content", sharedText) }
        try writeField("private", "false")
        try writeField("echo_id", UUID().uuidString)

        for file in sharedFiles {
            guard let path = file["path"] as? String else { continue }
            let fileURL = URL(fileURLWithPath: path)
            let name = ((file["name"] as? String) ?? fileURL.lastPathComponent)
                .replacingOccurrences(of: "\"", with: "_")
            let mime = (file["type"] as? String) ?? "application/octet-stream"
            try write("--\(boundary)\r\n")
            try write("Content-Disposition: form-data; name=\"attachments[]\"; filename=\"\(name)\"\r\n")
            try write("Content-Type: \(mime)\r\n\r\n")

            let input = try FileHandle(forReadingFrom: fileURL)
            defer { try? input.close() }
            while let chunk = try input.read(upToCount: 256 * 1024), !chunk.isEmpty {
                try output.write(contentsOf: chunk)
            }
            try write("\r\n")
        }
        try write("--\(boundary)--\r\n")
        return url
    }

    private func performRequest(
        path: String,
        queryItems: [URLQueryItem]
    ) async throws -> (Data, URLResponse) {
        var request = try authenticatedRequest(path: path, queryItems: queryItems)
        request.httpMethod = "GET"
        let result = try await URLSession.shared.data(for: request)
        persistRotatedHeaders(from: result.1)
        return result
    }

    private func authenticatedRequest(
        path: String,
        queryItems: [URLQueryItem] = []
    ) throws -> URLRequest {
        guard let baseUrl = context["baseUrl"] as? String,
              let base = URL(string: baseUrl),
              var components = URLComponents(
                url: base.appendingPathComponent(path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))),
                resolvingAgainstBaseURL: false
              ),
              let headers = session["headers"] as? [String: Any] else {
            throw ShareExtensionError.invalidSession
        }
        components.queryItems = queryItems.isEmpty ? nil : queryItems
        guard let url = components.url else { throw ShareExtensionError.invalidResponse }

        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        for (name, value) in headers {
            if let value = value as? String { request.setValue(value, forHTTPHeaderField: name) }
        }
        return request
    }

    private func ensureSuccess(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else {
            throw ShareExtensionError.invalidResponse
        }
        if http.statusCode == 401 { throw ShareExtensionError.unauthorized }
        guard (200...299).contains(http.statusCode) else {
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            let message = (root?["error"] as? String) ??
                (root?["message"] as? String) ?? "Não foi possível concluir o envio."
            throw ShareExtensionError.uploadFailed(message)
        }
    }

    private func persistRotatedHeaders(from response: URLResponse) {
        guard let http = response as? HTTPURLResponse,
              let installationId = context["installationId"] as? String,
              var headers = session["headers"] as? [String: Any] else { return }
        for name in ["access-token", "token-type", "client", "expiry", "uid"] {
            if let value = http.value(forHTTPHeaderField: name), !value.isEmpty {
                headers[name] = value
            }
        }
        session["headers"] = headers
        guard let data = try? JSONSerialization.data(withJSONObject: session) else { return }
        writeKeychainData(data, account: "viper:\(installationId):auth")
    }

    private func importShareItems() async throws {
        guard let container = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroup
        ) else {
            throw ShareExtensionError.uploadFailed(
                "Não foi possível acessar o compartilhamento do ViperChat."
            )
        }

        let shareDirectory = container.appendingPathComponent("shared", isDirectory: true)
        try FileManager.default.createDirectory(at: shareDirectory, withIntermediateDirectories: true)
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

        sharedFiles = files
        sharedText = texts.joined(separator: "\n")
        let payload: [String: Any] = [
            "subject": extensionContext?.inputItems
                .compactMap { ($0 as? NSExtensionItem)?.attributedTitle?.string }
                .first ?? "",
            "text": sharedText,
            "files": sharedFiles
        ]
        let data = try JSONSerialization.data(withJSONObject: payload)
        UserDefaults(suiteName: appGroup)?.set(data, forKey: pendingShareKey)
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
                        let size = (try? destination.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
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

    private var sharedAccessGroup: String? {
        guard let prefix = Bundle.main.object(forInfoDictionaryKey: "AppIdentifierPrefix") as? String,
              !prefix.isEmpty else { return nil }
        return "\(prefix)net.vipertec.viperchat.shared"
    }

    private func keychainQuery(account: String) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: account
        ]
        if let sharedAccessGroup {
            query[kSecAttrAccessGroup as String] = sharedAccessGroup
        }
        return query
    }

    private func readKeychainData(account: String) -> Data? {
        var query = keychainQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess else { return nil }
        return item as? Data
    }

    private func writeKeychainData(_ data: Data, account: String) {
        let query = keychainQuery(account: account)
        let attributes = [kSecValueData as String: data]
        if SecItemUpdate(query as CFDictionary, attributes as CFDictionary) == errSecItemNotFound {
            var newItem = query
            newItem[kSecValueData as String] = data
            newItem[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            SecItemAdd(newItem as CFDictionary, nil)
        }
    }

    private func clearPendingShare() {
        for file in sharedFiles {
            if let path = file["path"] as? String { try? FileManager.default.removeItem(atPath: path) }
        }
        UserDefaults(suiteName: appGroup)?.removeObject(forKey: pendingShareKey)
    }

    private func resolveURL(_ value: String?) -> URL? {
        guard let value, !value.isEmpty else { return nil }
        if let absolute = URL(string: value), absolute.scheme != nil { return absolute }
        guard let baseUrl = context["baseUrl"] as? String,
              let base = URL(string: baseUrl) else { return nil }
        return URL(string: value, relativeTo: base)?.absoluteURL
    }

    private func number(from value: Any?) -> Int? {
        if let value = value as? Int { return value }
        if let value = value as? NSNumber { return value.intValue }
        if let value = value as? String { return Int(value) }
        return nil
    }

    private func nonEmpty(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else { return nil }
        return value
    }

    private func updateSendButton() {
        var configuration = sendButton.configuration
        if let selectedConversation {
            configuration?.title = "Enviar para \(selectedConversation.name)"
            sendButton.isEnabled = true
        } else {
            configuration?.title = "Selecione uma conversa"
            sendButton.isEnabled = false
        }
        sendButton.configuration = configuration
    }

    private func finishWithMessage(_ message: String) {
        setPickerVisible(false)
        activityIndicator.stopAnimating()
        activityIndicator.isHidden = true
        statusLabel.isHidden = false
        statusLabel.text = message
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            self?.extensionContext?.completeRequest(returningItems: nil)
        }
    }

    @objc private func cancelShare() {
        extensionContext?.completeRequest(returningItems: nil)
    }
}

extension ShareViewController: UITableViewDataSource, UITableViewDelegate {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        conversations.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let identifier = "ConversationCell"
        let cell = tableView.dequeueReusableCell(withIdentifier: identifier) ??
            UITableViewCell(style: .subtitle, reuseIdentifier: identifier)
        let conversation = conversations[indexPath.row]
        var content = cell.defaultContentConfiguration()
        content.text = conversation.name
        content.secondaryText = conversation.subtitle
        content.image = UIImage(systemName: "person.crop.circle.fill")
        content.imageProperties.maximumSize = CGSize(width: 38, height: 38)
        content.imageProperties.cornerRadius = 19
        cell.contentConfiguration = content
        cell.accessoryType = selectedConversation?.id == conversation.id ? .checkmark : .none

        if let avatarURL = conversation.avatarURL {
            Task {
                guard let (data, _) = try? await URLSession.shared.data(from: avatarURL),
                      let image = UIImage(data: data),
                      tableView.indexPath(for: cell) == indexPath else { return }
                var updated = cell.defaultContentConfiguration()
                updated.text = conversation.name
                updated.secondaryText = conversation.subtitle
                updated.image = image
                updated.imageProperties.maximumSize = CGSize(width: 38, height: 38)
                updated.imageProperties.cornerRadius = 19
                cell.contentConfiguration = updated
            }
        }
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        selectedConversation = conversations[indexPath.row]
        tableView.reloadData()
        updateSendButton()
    }
}

extension ShareViewController: UISearchBarDelegate {
    func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
        searchTask?.cancel()
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        searchTask = Task {
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled else { return }
            await loadConversations(query: query.isEmpty ? nil : query)
        }
    }

    func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
        searchBar.resignFirstResponder()
    }
}
