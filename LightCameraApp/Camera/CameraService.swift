import AVFoundation
import CoreImage
import CoreImage.CIFilterBuiltins
import UIKit

final class CameraService: NSObject, ObservableObject {
    @Published var authorizationStatus: AVAuthorizationStatus = AVCaptureDevice.authorizationStatus(for: .video)
    @Published var capturedImage: UIImage?
    @Published var lightIntensity: Double = 0.35 {
        didSet {
            guard oldValue != lightIntensity else { return }
            updateTorchLevel()
        }
    }
    @Published var brightnessAdjustment: Double = 0.1
    @Published var errorMessage: String?
    @Published var statusText: String = "正在准备相机…"
    @Published var isSessionReady = false
    @Published var isCapturingPhoto = false

    let session = AVCaptureSession()

    private let sessionQueue = DispatchQueue(label: "camera.session.queue")
    private let photoOutput = AVCapturePhotoOutput()
    private let context = CIContext()
    private var videoDeviceInput: AVCaptureDeviceInput?
    private var isConfigured = false
    private var isSessionRunning = false

    override init() {
        super.init()
        requestAccessAndConfigureIfNeeded()
    }

    func requestAccessAndConfigureIfNeeded() {
        let currentStatus = AVCaptureDevice.authorizationStatus(for: .video)
        authorizationStatus = currentStatus

        switch currentStatus {
        case .authorized:
            statusText = "正在加载相机画面…"
            configureSessionIfNeeded()
        case .notDetermined:
            statusText = "等待相机权限…"
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.authorizationStatus = AVCaptureDevice.authorizationStatus(for: .video)
                    if granted {
                        self.statusText = "正在加载相机画面…"
                        self.configureSessionIfNeeded()
                    } else {
                        self.errorMessage = "请在系统设置里允许相机访问。"
                        self.statusText = "请开启相机权限后再试。"
                    }
                }
            }
        default:
            errorMessage = "当前没有相机权限，请先到系统设置开启。"
            statusText = "请开启相机权限后再试。"
        }
    }

    func startSession() {
        guard authorizationStatus == .authorized else { return }
        statusText = isSessionReady ? statusText : "正在启动相机…"
        configureSessionIfNeeded { [weak self] success in
            guard let self, success else { return }
            self.sessionQueue.async {
                guard !self.isSessionRunning else { return }
                self.session.startRunning()
                self.isSessionRunning = self.session.isRunning
                self.updateTorchLevelOnQueue()
                DispatchQueue.main.async {
                    self.isSessionReady = self.session.isRunning
                    self.statusText = self.session.isRunning ? "实时画面已就绪" : "相机启动失败，请重试。"
                }
            }
        }
    }

    func stopSession() {
        sessionQueue.async { [weak self] in
            guard let self, self.isSessionRunning else { return }
            self.disableTorchOnQueue()
            self.session.stopRunning()
            self.isSessionRunning = false
            DispatchQueue.main.async {
                self.isSessionReady = false
                self.statusText = "相机已停止"
            }
        }
    }

    func capturePhoto() {
        guard authorizationStatus == .authorized else {
            errorMessage = "当前没有相机权限，请先到系统设置开启。"
            return
        }

        guard isSessionReady else {
            errorMessage = "相机还没准备好，请稍候再拍。"
            statusText = "相机正在准备中…"
            startSession()
            return
        }

        isCapturingPhoto = true
        statusText = "正在拍照…"

        sessionQueue.async { [weak self] in
            guard let self else { return }
            let settings = AVCapturePhotoSettings()
            settings.photoQualityPrioritization = .quality
            settings.flashMode = .off
            self.photoOutput.capturePhoto(with: settings, delegate: self)
        }
    }

    private func configureSessionIfNeeded(completion: ((Bool) -> Void)? = nil) {
        sessionQueue.async { [weak self] in
            guard let self else {
                completion?(false)
                return
            }

            if self.isConfigured {
                completion?(true)
                return
            }

            self.session.beginConfiguration()
            self.session.sessionPreset = .photo

            defer {
                self.session.commitConfiguration()
            }

            do {
                guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
                    self.publishError("未找到可用的后置摄像头。")
                    self.publishStatus("当前设备没有可用的后置摄像头。")
                    completion?(false)
                    return
                }

                let input = try AVCaptureDeviceInput(device: camera)
                guard self.session.canAddInput(input) else {
                    self.publishError("无法将摄像头接入当前会话。")
                    self.publishStatus("摄像头接入失败。")
                    completion?(false)
                    return
                }
                self.session.addInput(input)
                self.videoDeviceInput = input

                guard self.session.canAddOutput(self.photoOutput) else {
                    self.publishError("无法启用拍照输出。")
                    self.publishStatus("拍照输出初始化失败。")
                    completion?(false)
                    return
                }
                self.session.addOutput(self.photoOutput)
                self.photoOutput.maxPhotoQualityPrioritization = .quality
                self.photoOutput.isHighResolutionCaptureEnabled = true
                self.isConfigured = true

                self.publishStatus("相机配置完成，正在启动预览…")
                completion?(true)
            } catch {
                self.publishError("相机初始化失败：\(error.localizedDescription)")
                self.publishStatus("相机初始化失败，请重试。")
                completion?(false)
            }
        }
    }

    private func updateTorchLevel() {
        sessionQueue.async { [weak self] in
            self?.updateTorchLevelOnQueue()
        }
    }

    private func updateTorchLevelOnQueue() {
        guard let device = videoDeviceInput?.device, device.hasTorch else { return }

        do {
            try device.lockForConfiguration()
            defer { device.unlockForConfiguration() }

            let level = Float(lightIntensity)
            if level > 0.01 {
                let clampedLevel = min(max(level, AVCaptureDevice.minAvailableTorchLevel), AVCaptureDevice.maxAvailableTorchLevel)
                try device.setTorchModeOn(level: clampedLevel)
            } else {
                device.torchMode = .off
            }
        } catch {
            publishError("补光灯调节失败：\(error.localizedDescription)")
        }
    }

    private func disableTorchOnQueue() {
        guard let device = videoDeviceInput?.device, device.hasTorch else { return }
        do {
            try device.lockForConfiguration()
            defer { device.unlockForConfiguration() }
            device.torchMode = .off
        } catch {
            publishError("关闭补光灯失败：\(error.localizedDescription)")
        }
    }

    private func applyBrightness(to image: UIImage) -> UIImage {
        guard let inputImage = CIImage(image: image) else { return image }

        let filter = CIFilter.colorControls()
        filter.inputImage = inputImage
        filter.brightness = Float(brightnessAdjustment)
        filter.contrast = 1.05
        filter.saturation = 1.0

        guard let outputImage = filter.outputImage,
              let cgImage = context.createCGImage(outputImage, from: outputImage.extent) else {
            return image
        }

        return UIImage(cgImage: cgImage, scale: image.scale, orientation: image.imageOrientation)
    }

    private func publishError(_ message: String) {
        DispatchQueue.main.async {
            self.errorMessage = message
        }
    }

    private func publishStatus(_ message: String) {
        DispatchQueue.main.async {
            self.statusText = message
        }
    }
}

extension CameraService: AVCapturePhotoCaptureDelegate {
    func photoOutput(_ output: AVCapturePhotoOutput,
                     didFinishProcessingPhoto photo: AVCapturePhoto,
                     error: Error?) {
        if let error {
            publishError("拍照失败：\(error.localizedDescription)")
            publishStatus("拍照失败，请重试。")
            DispatchQueue.main.async {
                self.isCapturingPhoto = false
            }
            return
        }

        guard let data = photo.fileDataRepresentation(), let image = UIImage(data: data) else {
            publishError("照片处理失败，请重试。")
            publishStatus("照片处理失败，请重试。")
            DispatchQueue.main.async {
                self.isCapturingPhoto = false
            }
            return
        }

        let processedImage = applyBrightness(to: image)
        DispatchQueue.main.async {
            self.capturedImage = processedImage
            self.isCapturingPhoto = false
            self.statusText = "已拍到最新照片"
            self.errorMessage = nil
        }
    }
}
