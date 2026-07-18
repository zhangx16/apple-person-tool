import Foundation
import Combine

/// Drives mail tab: accounts → inbox → detail.
/// Uses session single-flight via `MailService.ensureSession` / `withSessionRetry`.
/// 429 rate limits are not retried (service throws message).
@MainActor
final class MailViewModel: ObservableObject {
    // MARK: - Accounts
    @Published private(set) var accounts: [MailAccount] = []
    @Published private(set) var isLoadingAccounts = false
    @Published private(set) var isLoadingMoreAccounts = false
    @Published private(set) var accountsHasMore = false
    @Published private(set) var accountsError: String?
    @Published private(set) var isUnconfigured = false

    // MARK: - Messages
    @Published private(set) var messages: [MailMessage] = []
    @Published private(set) var isLoadingMessages = false
    @Published private(set) var isLoadingMoreMessages = false
    @Published private(set) var messagesHasMore = false
    @Published private(set) var messagesError: String?
    @Published var selectedFolder: MailFolder = .inbox

    // MARK: - Detail
    @Published private(set) var detail: MailMessage?
    @Published private(set) var isLoadingDetail = false
    @Published private(set) var detailError: String?

    private let settings: AppSettings
    private let mail: MailService

    private var accountPage = 1
    private let accountPageSize = 50
    private var messageSkip = 0
    private let messageTop = 30
    private(set) var activeEmail: String?

    enum MailFolder: String, CaseIterable, Identifiable {
        case inbox
        case junkemail

        var id: String { rawValue }

        var title: String {
            switch self {
            case .inbox: return "收件箱"
            case .junkemail: return "垃圾邮件"
            }
        }
    }

    init(settings: AppSettings = .shared, mail: MailService = .shared) {
        self.settings = settings
        self.mail = mail
    }

    // MARK: - Accounts

    func loadAccounts(force: Bool = false) async {
        guard !isLoadingAccounts else { return }
        if !force, !accounts.isEmpty, accountsError == nil { return }

        let base = settings.mailBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !base.isEmpty else {
            isUnconfigured = true
            accountsError = "请先在设置中配置邮件服务地址"
            return
        }

        if settings.mailUseExternalAPI {
            await loadExternalAccountStub()
            return
        }

        let password = settings.mailPassword
        guard !password.isEmpty else {
            isUnconfigured = true
            accounts = []
            accountsError = nil
            return
        }

        isUnconfigured = false
        isLoadingAccounts = true
        accountsError = nil
        accountPage = 1

        do {
            let page = try await mail.listAccounts(
                baseURL: base,
                password: password,
                page: 1,
                pageSize: accountPageSize
            )
            accounts = page.accounts
            accountsHasMore = page.hasMore
            accountPage = page.page
            if accounts.isEmpty {
                // Empty pool is not an error — view shows empty state.
                accountsError = nil
            }
        } catch {
            accounts = []
            accountsHasMore = false
            accountsError = Self.chineseError(error)
            Haptics.error()
        }
        isLoadingAccounts = false
    }

    func refreshAccounts() async {
        await loadAccounts(force: true)
    }

    func loadMoreAccounts() async {
        guard !isLoadingAccounts, !isLoadingMoreAccounts, accountsHasMore else { return }
        guard !settings.mailUseExternalAPI else { return }
        let base = settings.mailBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let password = settings.mailPassword
        guard !base.isEmpty, !password.isEmpty else { return }

        isLoadingMoreAccounts = true
        let next = accountPage + 1
        do {
            let page = try await mail.listAccounts(
                baseURL: base,
                password: password,
                page: next,
                pageSize: accountPageSize
            )
            // Append unique by id
            let existing = Set(accounts.map(\.id))
            let fresh = page.accounts.filter { !existing.contains($0.id) }
            accounts.append(contentsOf: fresh)
            accountsHasMore = page.hasMore
            accountPage = page.page
        } catch {
            accountsError = Self.chineseError(error)
            Haptics.error()
        }
        isLoadingMoreAccounts = false
    }

    private func loadExternalAccountStub() async {
        isUnconfigured = false
        isLoadingAccounts = true
        accountsError = nil
        defer { isLoadingAccounts = false }

        let email = settings.mailDefaultEmail.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = settings.mailExternalAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else {
            isUnconfigured = true
            accounts = []
            return
        }
        guard !email.isEmpty else {
            accounts = []
            accountsError = "外部 API 模式需在设置中填写默认邮箱"
            return
        }
        accounts = [MailAccount(email: email, status: "external", provider: "external", remark: "默认邮箱")]
        accountsHasMore = false
        accountPage = 1
    }

    // MARK: - Messages

    func selectAccount(_ account: MailAccount) {
        activeEmail = account.email
        messages = []
        messagesError = nil
        messageSkip = 0
        messagesHasMore = false
        detail = nil
        detailError = nil
        selectedFolder = .inbox
    }

    func loadMessages(force: Bool = true) async {
        guard let email = activeEmail else { return }
        guard !isLoadingMessages else { return }

        let base = settings.mailBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !base.isEmpty else {
            messagesError = "请先在设置中配置邮件服务地址"
            return
        }

        isLoadingMessages = true
        messagesError = nil
        if force {
            messageSkip = 0
        }

        do {
            let page: MailMessagesPage
            if settings.mailUseExternalAPI {
                let key = settings.mailExternalAPIKey
                page = try await mail.externalMessages(
                    baseURL: base,
                    apiKey: key,
                    email: email,
                    folder: selectedFolder.rawValue,
                    skip: 0,
                    top: messageTop
                )
            } else {
                let password = settings.mailPassword
                page = try await mail.listMessages(
                    baseURL: base,
                    password: password,
                    email: email,
                    folder: selectedFolder.rawValue,
                    skip: 0,
                    top: messageTop
                )
            }
            messages = page.messages
            messagesHasMore = page.hasMore
            messageSkip = page.messages.count
        } catch {
            messages = []
            messagesHasMore = false
            messageSkip = 0
            messagesError = Self.chineseError(error)
            Haptics.error()
        }
        isLoadingMessages = false
    }

    func refreshMessages() async {
        await loadMessages(force: true)
    }

    func changeFolder(_ folder: MailFolder) async {
        guard selectedFolder != folder else { return }
        selectedFolder = folder
        await loadMessages(force: true)
    }

    func loadMoreMessages() async {
        guard let email = activeEmail else { return }
        guard !isLoadingMessages, !isLoadingMoreMessages, messagesHasMore else { return }

        let base = settings.mailBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !base.isEmpty else { return }

        isLoadingMoreMessages = true
        do {
            let page: MailMessagesPage
            if settings.mailUseExternalAPI {
                page = try await mail.externalMessages(
                    baseURL: base,
                    apiKey: settings.mailExternalAPIKey,
                    email: email,
                    folder: selectedFolder.rawValue,
                    skip: messageSkip,
                    top: messageTop
                )
            } else {
                page = try await mail.listMessages(
                    baseURL: base,
                    password: settings.mailPassword,
                    email: email,
                    folder: selectedFolder.rawValue,
                    skip: messageSkip,
                    top: messageTop
                )
            }
            let existing = Set(messages.map(\.id))
            let fresh = page.messages.filter { !existing.contains($0.id) }
            messages.append(contentsOf: fresh)
            messagesHasMore = page.hasMore
            messageSkip += page.messages.count
        } catch {
            messagesError = Self.chineseError(error)
            Haptics.error()
        }
        isLoadingMoreMessages = false
    }

    // MARK: - Detail

    func loadDetail(messageID: String) async {
        guard let email = activeEmail else { return }
        let base = settings.mailBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !base.isEmpty else {
            detailError = "请先在设置中配置邮件服务地址"
            return
        }

        isLoadingDetail = true
        detailError = nil
        // Keep list preview while loading full body if we already have a stub.
        if detail?.id != messageID {
            detail = messages.first(where: { $0.id == messageID })
        }

        do {
            let full: MailMessage
            if settings.mailUseExternalAPI {
                full = try await mail.externalMessageDetail(
                    baseURL: base,
                    apiKey: settings.mailExternalAPIKey,
                    email: email,
                    messageID: messageID,
                    folder: selectedFolder.rawValue
                )
            } else {
                full = try await mail.messageDetail(
                    baseURL: base,
                    password: settings.mailPassword,
                    email: email,
                    messageID: messageID
                )
            }
            detail = full
        } catch {
            detailError = Self.chineseError(error)
            Haptics.error()
        }
        isLoadingDetail = false
    }

    func clearDetail() {
        detail = nil
        detailError = nil
        isLoadingDetail = false
    }

    // MARK: - Errors

    static func chineseError(_ error: Error) -> String {
        if let net = error as? NetworkError {
            return net.errorDescription ?? "网络错误"
        }
        let ns = error as NSError
        if ns.domain == NSURLErrorDomain {
            switch ns.code {
            case NSURLErrorNotConnectedToInternet: return "无网络连接"
            case NSURLErrorTimedOut: return "请求超时"
            case NSURLErrorCannotFindHost, NSURLErrorCannotConnectToHost: return "无法连接服务器"
            case NSURLErrorSecureConnectionFailed: return "安全连接失败"
            default: break
            }
        }
        let text = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? "未知错误" : text
    }
}
