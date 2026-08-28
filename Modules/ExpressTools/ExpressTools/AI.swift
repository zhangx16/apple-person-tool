import Foundation
import SwiftUI

struct AIClient {
    func complete(messages: [ChatMessage], parcels: [Parcel]) async throws -> String {
        let base = Secrets.get("ai.base").isEmpty ? "https://api.deepseek.com" : Secrets.get("ai.base")
        guard let url = URL(string: base.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/chat/completions") else { throw QueryError.message("AI 地址无效") }
        let key = Secrets.get("ai.key"); guard !key.isEmpty else { throw QueryError.message("请先在设置中配置 AI") }
        let context = parcels.map { "\($0.title) \($0.number) \($0.statusText) \($0.summary)" }.joined(separator: "\n")
        let payload: [String: Any] = ["model": Secrets.get("ai.model").isEmpty ? "deepseek-chat" : Secrets.get("ai.model"), "messages": [["role":"system", "content":"你是快递助手云雀。根据本机包裹回答，简洁可靠。包裹：\n\(context)"]] + messages.map { ["role":$0.role.rawValue, "content":$0.content] }]
        var request = URLRequest(url: url); request.httpMethod = "POST"; request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization"); request.setValue("application/json", forHTTPHeaderField: "Content-Type"); request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        let (data, response) = try await URLSession.shared.data(for: request); guard (response as? HTTPURLResponse)?.statusCode == 200, let root = try JSONSerialization.jsonObject(with: data) as? [String: Any], let choices = root["choices"] as? [[String: Any]], let message = choices.first?["message"] as? [String: Any], let content = message["content"] as? String else { throw QueryError.message("AI 请求失败") }; return content
    }
}

struct LarkChatView: View {
    @StateObject private var repository = AppRepository.shared
    @EnvironmentObject private var store: ParcelStore
    @State private var input = ""; @State private var loading = false; @State private var error: String?
    let presets = ["今天有哪些快递到？", "哪个包裹正在派送？", "汇总异常包裹", "生成今日快递日报"]
    var body: some View { VStack(spacing: 0) {
        ScrollView { LazyVStack(spacing: 12) {
            if repository.chat.isEmpty { ContentUnavailableView("你好，我是云雀", systemImage: "bird.fill", description: Text("我可以读取本机包裹并回答物流问题")); ForEach(presets, id: \.self) { prompt in Button(prompt) { send(prompt) }.buttonStyle(.bordered) } }
            ForEach(repository.chat) { message in HStack { if message.role == .user { Spacer() }; Text(message.content).padding(12).background(message.role == .user ? Color.orange : Color.secondary.opacity(0.13), in: RoundedRectangle(cornerRadius: 16)).foregroundStyle(message.role == .user ? .white : .primary); if message.role == .assistant { Spacer() } }.padding(.horizontal) }
            if loading { ProgressView("云雀正在整理物流…") }
        }.padding(.vertical) }
        HStack { TextField("问问云雀…", text: $input, axis: .vertical).textFieldStyle(.roundedBorder); Button { send(input) } label: { Image(systemName: "arrow.up.circle.fill").font(.title) }.disabled(input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || loading) }.padding().background(.bar)
    }.navigationTitle("云雀").toolbar { if !repository.chat.isEmpty { Button("清空") { repository.chat = [] } } }.alert("请求失败", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) { Button("好") {} } message: { Text(error ?? "") } }
    private func send(_ text: String) { let clean = text.trimmingCharacters(in: .whitespacesAndNewlines); guard !clean.isEmpty else { return }; repository.chat.append(ChatMessage(role: .user, content: clean)); input = ""; loading = true; Task { do { let reply = try await AIClient().complete(messages: repository.chat, parcels: store.parcels); repository.chat.append(ChatMessage(role: .assistant, content: reply)) } catch { self.error = error.localizedDescription }; loading = false } }
}
