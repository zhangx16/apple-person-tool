import UIKit
import UniformTypeIdentifiers
import MobileCoreServices

/// System Share Sheet extension: capture text/URL → App Group → open host app.
final class ShareViewController: UIViewController {
    private let statusLabel = UILabel()
    private let spinner = UIActivityIndicatorView(style: .large)

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.textAlignment = .center
        statusLabel.numberOfLines = 0
        statusLabel.font = .preferredFont(forTextStyle: .body)
        statusLabel.text = "正在交给 XIN's Tool…"

        spinner.translatesAutoresizingMaskIntoConstraints = false
        spinner.startAnimating()

        view.addSubview(statusLabel)
        view.addSubview(spinner)
        NSLayoutConstraint.activate([
            spinner.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: -24),
            statusLabel.topAnchor.constraint(equalTo: spinner.bottomAnchor, constant: 16),
            statusLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            statusLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24)
        ])
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        Task { await processSharedItems() }
    }

    private func processSharedItems() async {
        let items = extensionContext?.inputItems as? [NSExtensionItem] ?? []
        var texts: [String] = []
        var urls: [String] = []

        for item in items {
            guard let providers = item.attachments else { continue }
            for provider in providers {
                if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                    if let value = await loadItem(provider, type: UTType.url.identifier) {
                        if let u = value as? URL {
                            urls.append(u.absoluteString)
                        } else if let s = value as? String {
                            urls.append(s)
                        }
                    }
                } else if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                    if let value = await loadItem(provider, type: UTType.plainText.identifier) as? String {
                        texts.append(value)
                    }
                } else if provider.hasItemConformingToTypeIdentifier(UTType.text.identifier) {
                    if let value = await loadItem(provider, type: UTType.text.identifier) as? String {
                        texts.append(value)
                    }
                }
            }
        }

        let text = texts.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        // Also harvest URLs from free text
        if let extracted = extractURLs(from: text) {
            for u in extracted where !urls.contains(u) {
                urls.append(u)
            }
        }

        guard !text.isEmpty || !urls.isEmpty else {
            await MainActor.run {
                statusLabel.text = "未识别到文本或链接"
                spinner.stopAnimating()
            }
            try? await Task.sleep(nanoseconds: 900_000_000)
            extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
            return
        }

        let payload = ShareHandoffPayload(
            text: text,
            urls: urls,
            createdAt: Date().timeIntervalSince1970
        )
        guard let openURL = ShareHandoff.openURL(with: payload) else {
            extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
            return
        }

        await MainActor.run {
            statusLabel.text = "正在打开 XIN's Tool…"
        }

        openHostApp(openURL)
        try? await Task.sleep(nanoseconds: 350_000_000)
        extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
    }

    private func loadItem(_ provider: NSItemProvider, type: String) async -> Any? {
        await withCheckedContinuation { cont in
            provider.loadItem(forTypeIdentifier: type, options: nil) { item, _ in
                cont.resume(returning: item)
            }
        }
    }

    private func extractURLs(from text: String) -> [String]? {
        let pattern = #"https?://[^\s<>"']+"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        let matches = regex.matches(in: text, range: range)
        var out: [String] = []
        for m in matches {
            if let r = Range(m.range, in: text) {
                var s = String(text[r])
                while let last = s.last, ".,);]》」』".contains(last) { s.removeLast() }
                out.append(s)
            }
        }
        return out.isEmpty ? nil : out
    }

    private func openHostApp(_ url: URL) {
        var responder: UIResponder? = self
        let selector = sel_registerName("openURL:")
        while let r = responder {
            if r.responds(to: selector) {
                r.perform(selector, with: url)
                return
            }
            responder = r.next
        }
        // iOS 18+ share extensions
        extensionContext?.open(url, completionHandler: { _ in })
    }
}
