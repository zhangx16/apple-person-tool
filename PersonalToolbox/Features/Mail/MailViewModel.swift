import Foundation
import Combine

/// Drives mail tab: accounts → inbox → detail.
/// Uses session single-flight via `MailService.ensureSession` / `withSessionRetry`.
/// 429 rate limits are not retried (service throws message).
///
/// Load coalescing: each list/detail surface has a generation token. Newer requests
/// supersede in-flight ones; stale completions and `CancellationError` never clobber UI.
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

    /// Generation tokens: only the latest request may mutate published state.
    private var accountsLoadID = 0
    private var messagesLoadID = 0
    private var detailLoadID = 0

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
        // Non-force: skip if already happy or a load is in flight.
        if !force {
            if isLoadingAccounts { return }
            if !accounts.isEmpty, accountsError == nil { return }
        }

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

        accountsLoadID += 1
        let loadID = accountsLoadID

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
            guard loadID == accountsLoadID else { return }
            accounts = page.accounts
            accountsHasMore = page.hasMore
            accountPage = page.page
            accountsError = nil
        } catch is CancellationError {
            return
        } catch {
            guard loadID == accountsLoadID else { return }
            accounts = []
            accountsHasMore = false
            accountsError = Self.chineseError(error)
            Haptics.error()
        }
        if loadID == accountsLoadID {
            isLoadingAccounts = false
        }
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

        let loadID = accountsLoadID
        let next = accountPage + 1
        isLoadingMoreAccounts = true
        do {
            let page = try await mail.listAccounts(
                baseURL: base,
                password: password,
                page: next,
                pageSize: accountPageSize
            )
            guard loadID == accountsLoadID else { return }
            let existing = Set(accounts.map(\.id))
            let fresh = page.accounts.filter { !existing.contains($0.id) }
            accounts.append(contentsOf: fresh)
            accountsHasMore = page.hasMore
            accountPage = page.page
        } catch is CancellationError {
            return
        } catch {
            guard loadID == accountsLoadID else { return }
            accountsError = Self.chineseError(error)
            Haptics.error()
        }
        if loadID == accountsLoadID {
            isLoadingMoreAccounts = false
        }
    }

    private func loadExternalAccountStub() async {
        accountsLoadID += 1
        let loadID = accountsLoadID
        isUnconfigured = false
        isLoadingAccounts = true
        accountsError = nil
        defer {
            if loadID == accountsLoadID {
                isLoadingAccounts = false
            }
        }

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
        // Invalidate any in-flight message/detail loads for the previous mailbox.
        messagesLoadID += 1
        detailLoadID += 1
        activeEmail = account.email
        messages = []
        messagesError = nil
        messageSkip = 0
        messagesHasMore = false
        isLoadingMessages = false
        isLoadingMoreMessages = false
        detail = nil
        detailError = nil
        isLoadingDetail = false
        selectedFolder = .inbox
    }

    /// Loads the first page for the current `activeEmail` + `selectedFolder`.
    /// Always starts a new generation (does **not** drop when already loading) so folder
    /// switches and pull-to-refresh supersede stale in-flight requests.
    func loadMessages(force: Bool = true) async {
        guard let email = activeEmail else { return }

        let base = settings.mailBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !base.isEmpty else {
            messagesError = "请先在设置中配置邮件服务地址"
            return
        }

        let folder = selectedFolder
        messagesLoadID += 1
        let loadID = messagesLoadID

        isLoadingMessages = true
        isLoadingMoreMessages = false
        messagesError = nil
        if force {
            messageSkip = 0
        }

        // Capture request identity at start; apply only if still current.
        let folderRaw = folder.rawValue

        do {
            let page: MailMessagesPage
            if settings.mailUseExternalAPI {
                page = try await mail.externalMessages(
                    baseURL: base,
                    apiKey: settings.mailExternalAPIKey,
                    email: email,
                    folder: folderRaw,
                    skip: 0,
                    top: messageTop
                )
            } else {
                page = try await mail.listMessages(
                    baseURL: base,
                    password: settings.mailPassword,
                    email: email,
                    folder: folderRaw,
                    skip: 0,
                    top: messageTop
                )
            }
            guard isMessagesRequestCurrent(loadID: loadID, email: email, folder: folder) else { return }
            messages = page.messages
            messagesHasMore = page.hasMore
            messageSkip = page.messages.count
            messagesError = nil
        } catch is CancellationError {
            return
        } catch {
            guard isMessagesRequestCurrent(loadID: loadID, email: email, folder: folder) else { return }
            messages = []
            messagesHasMore = false
            messageSkip = 0
            messagesError = Self.chineseError(error)
            Haptics.error()
        }
        if loadID == messagesLoadID {
            isLoadingMessages = false
        }
    }

    func refreshMessages() async {
        await loadMessages(force: true)
    }

    func changeFolder(_ folder: MailFolder) async {
        guard selectedFolder != folder else { return }
        selectedFolder = folder
        // loadMessages always starts a new generation even if a load is in flight.
        await loadMessages(force: true)
    }

    func loadMoreMessages() async {
        guard let email = activeEmail else { return }
        guard !isLoadingMessages, !isLoadingMoreMessages, messagesHasMore else { return }

        let base = settings.mailBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !base.isEmpty else { return }

        // Tie load-more to the current list generation; folder/account change invalidates.
        let loadID = messagesLoadID
        let folder = selectedFolder
        let skip = messageSkip
        let folderRaw = folder.rawValue

        isLoadingMoreMessages = true
        do {
            let page: MailMessagesPage
            if settings.mailUseExternalAPI {
                page = try await mail.externalMessages(
                    baseURL: base,
                    apiKey: settings.mailExternalAPIKey,
                    email: email,
                    folder: folderRaw,
                    skip: skip,
                    top: messageTop
                )
            } else {
                page = try await mail.listMessages(
                    baseURL: base,
                    password: settings.mailPassword,
                    email: email,
                    folder: folderRaw,
                    skip: skip,
                    top: messageTop
                )
            }
            guard isMessagesRequestCurrent(loadID: loadID, email: email, folder: folder) else { return }
            let existing = Set(messages.map(\.id))
            let fresh = page.messages.filter { !existing.contains($0.id) }
            messages.append(contentsOf: fresh)
            messagesHasMore = page.hasMore
            messageSkip = skip + page.messages.count
        } catch is CancellationError {
            return
        } catch {
            guard isMessagesRequestCurrent(loadID: loadID, email: email, folder: folder) else { return }
            messagesError = Self.chineseError(error)
            Haptics.error()
        }
        if loadID == messagesLoadID {
            isLoadingMoreMessages = false
        }
    }

    private func isMessagesRequestCurrent(loadID: Int, email: String, folder: MailFolder) -> Bool {
        loadID == messagesLoadID
            && activeEmail == email
            && selectedFolder == folder
    }

    // MARK: - Detail

    func loadDetail(messageID: String) async {
        guard let email = activeEmail else { return }
        let base = settings.mailBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !base.isEmpty else {
            detailError = "请先在设置中配置邮件服务地址"
            return
        }

        detailLoadID += 1
        let loadID = detailLoadID
        let folder = selectedFolder

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
                    folder: folder.rawValue
                )
            } else {
                full = try await mail.messageDetail(
                    baseURL: base,
                    password: settings.mailPassword,
                    email: email,
                    messageID: messageID
                )
            }
            guard loadID == detailLoadID, activeEmail == email else { return }
            detail = full
            detailError = nil
        } catch is CancellationError {
            return
        } catch {
            guard loadID == detailLoadID, activeEmail == email else { return }
            detailError = Self.chineseError(error)
            Haptics.error()
        }
        if loadID == detailLoadID {
            isLoadingDetail = false
        }
    }

    func clearDetail() {
        detailLoadID += 1
        detail = nil
        detailError = nil
        isLoadingDetail = false
    }

    // MARK: - Errors

    static func chineseError(_ error: Error) -> String {
        if error is CancellationError {
            return ""
        }
        if let net = error as? NetworkError {
            return net.errorDescription ?? "网络错误"
        }
        let ns = error as NSError
        if ns.domain == NSURLErrorDomain {
            switch ns.code {
            case NSURLErrorCancelled:
                return ""
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
