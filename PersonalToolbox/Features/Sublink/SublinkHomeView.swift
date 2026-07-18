import SwiftUI

struct SublinkHomeView: View {
    @EnvironmentObject private var settings: AppSettings
    @StateObject private var viewModel = SublinkViewModel()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if viewModel.isLoggedIn {
                    dashboardSection
                    nodesSection
                    subsSection
                    Button("退出登录", role: .destructive) {
                        viewModel.logout()
                    }
                    .buttonStyle(PressableButtonStyle())
                } else {
                    loginSection
                }
                if let err = viewModel.errorMessage {
                    Text(err)
                        .font(.subheadline)
                        .foregroundStyle(.red)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                }
            }
            .padding(16)
        }
        .background(AppleTheme.canvas)
        .navigationTitle("SublinkX")
        .refreshable {
            if viewModel.isLoggedIn {
                await viewModel.refresh(settings: settings)
            } else {
                await viewModel.refreshCaptcha(settings: settings)
            }
        }
        .task {
            await viewModel.bootstrap(settings: settings)
        }
    }

    private var loginSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("登录 SublinkX")
                .font(.headline)
            Text("\(settings.sublinkBaseURL)")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("用户 \(settings.sublinkUsername)")
                .font(.subheadline)

            if let img = viewModel.captchaImage {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFit()
                    .frame(height: 56)
                    .frame(maxWidth: .infinity)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .onTapGesture {
                        Task { await viewModel.refreshCaptcha(settings: settings) }
                    }
                    .accessibilityLabel("验证码图片，点按刷新")
            }

            HStack {
                TextField("验证码", text: $viewModel.captchaCode)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .textFieldStyle(.roundedBorder)
                Button("刷新") {
                    Task { await viewModel.refreshCaptcha(settings: settings) }
                }
            }

            Button {
                Task { await viewModel.login(settings: settings) }
            } label: {
                PrimaryButtonLabel(title: "登录", systemImage: "person.badge.key", isBusy: viewModel.isLoading)
            }
            .buttonStyle(PressableButtonStyle())
            .disabled(viewModel.captchaCode.isEmpty || viewModel.isLoading)

            Text("账号密码请在「设置 → SublinkX」中配置。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: AppleTheme.cornerRadius, style: .continuous))
    }

    private var dashboardSection: some View {
        let d = viewModel.dashboard
        return LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            metric("订阅", "\(d?.subscriptions ?? 0)")
            metric("节点", "\(d?.nodes ?? 0)")
            metric("分组", "\(d?.groups ?? 0)")
            metric("访问量", "\(d?.accessCount ?? 0)")
        }
    }

    private func metric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title3.weight(.semibold))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var nodesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("节点 (\(viewModel.nodes.count))")
                .font(.headline)
            ForEach(viewModel.nodes.prefix(30)) { n in
                VStack(alignment: .leading, spacing: 4) {
                    Text(n.name ?? "未命名")
                        .font(.subheadline.weight(.medium))
                    Text(n.link ?? "")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                .padding(.vertical, 4)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: AppleTheme.cornerRadius, style: .continuous))
    }

    private var subsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("订阅 (\(viewModel.subscriptions.count))")
                .font(.headline)
            ForEach(viewModel.subscriptions.prefix(30)) { s in
                Text(s.name ?? "未命名")
                    .font(.subheadline)
                    .padding(.vertical, 2)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: AppleTheme.cornerRadius, style: .continuous))
    }
}
