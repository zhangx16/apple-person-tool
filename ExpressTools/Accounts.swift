import SwiftUI

struct AccountBindingView: View {
    @StateObject private var repository = AppRepository.shared
    @State private var source = DeliverySource.jd; @State private var label = ""; @State private var credential = ""; @State private var showsAdd = false
    var body: some View { List {
        ForEach(DeliverySource.allCases.filter { $0 != .manual }) { channel in
            Section(channel.title) {
                ForEach(repository.accounts.filter { $0.source == channel }) { account in
                    HStack { Label(account.label, systemImage: channel.icon); Spacer(); Image(systemName: account.enabled ? "checkmark.circle.fill" : "pause.circle").foregroundStyle(account.enabled ? .green : .secondary) }
                        .swipeActions { Button(role: .destructive) { repository.removeAccount(account) } label: { Label("删除", systemImage: "trash") } }
                }
                Button { source = channel; showsAdd = true } label: { Label("绑定\(channel.title)账号", systemImage: "plus") }
            }
        }
    }.navigationTitle("多平台账号").sheet(isPresented: $showsAdd) { NavigationStack { Form {
        Section(source.title) { TextField("账号备注", text: $label); SecureField(source == .xiaomi ? "登录 Token / JSON" : "登录 Cookie", text: $credential) }
        Section { Text("凭证仅写入本机 Keychain。平台网页接口可能变化，失效后需重新绑定。") }
    }.navigationTitle("绑定账号").toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { showsAdd = false } }; ToolbarItem(placement: .confirmationAction) { Button("保存") { repository.addAccount(source: source, label: label, credential: credential); label = ""; credential = ""; showsAdd = false }.disabled(credential.isEmpty) } } } } }
}
