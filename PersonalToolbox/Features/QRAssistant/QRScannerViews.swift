import SwiftUI
import AVFoundation
import UIKit

// MARK: - Camera scanner (AVFoundation metadata)

struct QRCameraScannerView: UIViewControllerRepresentable {
    var scanMode: QRScanMode
    var onCode: (String) -> Void
    var onDismiss: () -> Void

    func makeUIViewController(context: Context) -> QRScannerViewController {
        let vc = QRScannerViewController()
        vc.scanMode = scanMode
        vc.onCode = onCode
        vc.onDismiss = onDismiss
        return vc
    }

    func updateUIViewController(_ uiViewController: QRScannerViewController, context: Context) {
        uiViewController.scanMode = scanMode
        uiViewController.onCode = onCode
        uiViewController.onDismiss = onDismiss
    }
}

final class QRScannerViewController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    var scanMode: QRScanMode = .single
    var onCode: ((String) -> Void)?
    var onDismiss: (() -> Void)?

    private let session = AVCaptureSession()
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var isSessionRunning = false
    private var lastPayload: String?
    private var lastFireAt: TimeInterval = 0
    private let feedback = UINotificationFeedbackGenerator()

    private let statusLabel = UILabel()
    private let torchButton = UIButton(type: .system)
    private let closeButton = UIButton(type: .system)
    private let modeLabel = UILabel()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        setupChrome()
        checkPermissionAndConfigure()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        startSession()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        stopSession()
        setTorch(false)
    }

    private func setupChrome() {
        closeButton.setImage(UIImage(systemName: "xmark.circle.fill"), for: .normal)
        closeButton.tintColor = .white
        closeButton.contentHorizontalAlignment = .fill
        closeButton.contentVerticalAlignment = .fill
        closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(closeButton)

        torchButton.setImage(UIImage(systemName: "flashlight.off.fill"), for: .normal)
        torchButton.tintColor = .white
        torchButton.backgroundColor = UIColor.white.withAlphaComponent(0.18)
        torchButton.layer.cornerRadius = 22
        torchButton.addTarget(self, action: #selector(torchTapped), for: .touchUpInside)
        torchButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(torchButton)

        statusLabel.text = "将二维码放入取景框"
        statusLabel.textColor = .white
        statusLabel.font = .preferredFont(forTextStyle: .subheadline)
        statusLabel.textAlignment = .center
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(statusLabel)

        modeLabel.text = scanMode == .continuous ? "连续扫码" : "单次扫码"
        modeLabel.textColor = UIColor.white.withAlphaComponent(0.85)
        modeLabel.font = .preferredFont(forTextStyle: .caption1)
        modeLabel.textAlignment = .center
        modeLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(modeLabel)

        // Frame guide
        let guide = UIView()
        guide.layer.borderColor = UIColor(red: 71 / 255, green: 102 / 255, blue: 194 / 255, alpha: 1).cgColor
        guide.layer.borderWidth = 2
        guide.layer.cornerRadius = 16
        guide.backgroundColor = .clear
        guide.isUserInteractionEnabled = false
        guide.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(guide)

        NSLayoutConstraint.activate([
            closeButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            closeButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            closeButton.widthAnchor.constraint(equalToConstant: 36),
            closeButton.heightAnchor.constraint(equalToConstant: 36),

            torchButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 10),
            torchButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            torchButton.widthAnchor.constraint(equalToConstant: 44),
            torchButton.heightAnchor.constraint(equalToConstant: 44),

            guide.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            guide.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: -20),
            guide.widthAnchor.constraint(equalTo: view.widthAnchor, multiplier: 0.68),
            guide.heightAnchor.constraint(equalTo: guide.widthAnchor),

            statusLabel.topAnchor.constraint(equalTo: guide.bottomAnchor, constant: 20),
            statusLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            statusLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),

            modeLabel.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 6),
            modeLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor)
        ])
    }

    private func checkPermissionAndConfigure() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            configureSession()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    if granted {
                        self?.configureSession()
                        self?.startSession()
                    } else {
                        self?.statusLabel.text = "未获得相机权限"
                    }
                }
            }
        default:
            statusLabel.text = "请在设置中开启相机权限"
        }
    }

    private func configureSession() {
        session.beginConfiguration()
        session.sessionPreset = .high

        guard let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else {
            statusLabel.text = "无法打开相机"
            session.commitConfiguration()
            return
        }
        session.addInput(input)

        let output = AVCaptureMetadataOutput()
        guard session.canAddOutput(output) else {
            session.commitConfiguration()
            return
        }
        session.addOutput(output)
        output.setMetadataObjectsDelegate(self, queue: DispatchQueue.main)
        if output.availableMetadataObjectTypes.contains(.qr) {
            output.metadataObjectTypes = [.qr]
        } else {
            output.metadataObjectTypes = output.availableMetadataObjectTypes
        }

        session.commitConfiguration()

        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        layer.frame = view.bounds
        view.layer.insertSublayer(layer, at: 0)
        previewLayer = layer
    }

    private func startSession() {
        guard !isSessionRunning else { return }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            if !self.session.isRunning {
                self.session.startRunning()
            }
            DispatchQueue.main.async {
                self.isSessionRunning = self.session.isRunning
            }
        }
    }

    private func stopSession() {
        guard isSessionRunning else { return }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            if self.session.isRunning {
                self.session.stopRunning()
            }
            DispatchQueue.main.async {
                self.isSessionRunning = false
            }
        }
    }

    @objc private func closeTapped() {
        onDismiss?()
    }

    @objc private func torchTapped() {
        guard let device = AVCaptureDevice.default(for: .video), device.hasTorch else { return }
        let next = !(device.torchMode == .on)
        setTorch(next)
        let name = next ? "flashlight.on.fill" : "flashlight.off.fill"
        torchButton.setImage(UIImage(systemName: name), for: .normal)
    }

    private func setTorch(_ on: Bool) {
        guard let device = AVCaptureDevice.default(for: .video), device.hasTorch else { return }
        do {
            try device.lockForConfiguration()
            device.torchMode = on ? .on : .off
            device.unlockForConfiguration()
        } catch {}
    }

    func metadataOutput(
        _ output: AVCaptureMetadataOutput,
        didOutput metadataObjects: [AVMetadataObject],
        from connection: AVCaptureConnection
    ) {
        guard let object = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
              object.type == .qr,
              let value = object.stringValue,
              !value.isEmpty else { return }

        let now = Date().timeIntervalSince1970
        if scanMode == .continuous {
            // Debounce same payload
            if value == lastPayload, now - lastFireAt < 1.5 { return }
        } else {
            if lastPayload != nil { return }
        }

        lastPayload = value
        lastFireAt = now
        statusLabel.text = "已识别"
        feedback.notificationOccurred(.success)
        onCode?(value)

        if scanMode == .single {
            // Brief pause then dismiss
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
                self?.onDismiss?()
            }
        }
    }
}

// MARK: - Full screen scanner host

struct QRScannerSheet: View {
    @Binding var scanMode: QRScanMode
    var onCode: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack(alignment: .bottom) {
            QRCameraScannerView(
                scanMode: scanMode,
                onCode: onCode,
                onDismiss: { dismiss() }
            )
            .ignoresSafeArea()

            Picker("模式", selection: $scanMode) {
                ForEach(QRScanMode.allCases) { mode in
                    Text(mode.label).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 40)
            .padding(.bottom, 36)
        }
        .preferredColorScheme(.dark)
    }
}
