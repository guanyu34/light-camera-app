import AVFoundation
import CoreImage
import CoreImage.CIFilterBuiltins
import UIKit

final class CameraService: NSObject, ObservableObject {
    @Published var authorizationStatus: AVAuthorizationStatus = AVCaptureDevice.authorizationStatus(for: .video)
    @Published var capturedImage: UIImage?
    @Published var lightIntensity: Double = 0.35 {
        didSet {
            updateTorchLevel()
        }
    }
    @Published var brightnessAdjustment: Double = 0.1
    @Published var errorMessage: String?

    let session = AVCaptureSession()

    private let sessionQueue = DispatchQueue(label: "camera.session.queue")
    private let photoOutput = AVCapturePhotoOutput()
    private let context = CIContext()
    private var videoDeviceInput: AVCaptureDeviceInput?
    private var isConfigured = false

    override init() {
        super.init()
        requestAccessAndConfigureIfNeeded()
    }

    func requestAccessAndConfigureIfNeeded() {
        switch authorizationStatus {
        case .authorized:
            configureSessionIfNeeded()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.authorizationStatus = AVCaptureDevice.authorizationStatus(for: .video)
                    if granted {
                        self.configureSessionIfNeeded()
                    } else {
                        self.errorMessage = "请在系统设置里允许相机访问。"
                    }
                }
            }
        default:
            errorMessage = "当前没有相机权限，请先到系统设置开启。"
        }
    }

    func startSession() {
        guard authorizationStatus == .authorized else { return }
        configureSessionIfNeeded()
        sessionQueue.async { [weak self] in
            guard let self, !self.session.isRunning else { return }
            self.session.startRunning()
            self.updateTorchLevel()
        }
    }

    func stopSession() {
        sessionQueue.async { [weak self] in
            guard let self, self.session.isRunning else { return }
            self.disableTorch()
            self.session.stopRunning()
        }
    }

    func capturePhoto() {
        let settings = AVCapturePhotoSettings()
        settings.photoQualityPrioritization = .quality
        settings.flashMode = .off
        photoOutput.capturePhoto(with: settings, delegate: self)
    }

    private func configureSessionIfNeeded() {
        guard !isConfigured else { return }
        sessionQueue.async { [weak self] in
            guard let self else { return }
            self.session.beginConfiguration()
            self.session.sessionPreset = .photo

            defer {
                self.session.commitConfiguration()
            }

            do {
                guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
                    self.publishError("未找到可用的后置摄像头。")
                    return
                }

                let input = try AVCaptureDeviceInput(device: camera)
                guard self.session.canAddInput(input) else {
                    self.publishError("无法将摄像头接入当前会话。")
                    return
                }
                self.session.addInput(input)
                self.videoDeviceInput = input

                guard self.session.canAddOutput(self.photoOutput) else {
                    self.publishError("无法启用拍照输出。")
                    return
                }
                self.session.addOutput(self.photoOutput)
                self.photoOutput.maxPhotoQualityPrioritization = .quality
                self.isConfigured = true
            } catch {
                self.publishError("相机初始化失败：\(error.localizedDescription)")
            }
        }
    }

    private func updateTorchLevel() {
        sessionQueue.async { [weak self] in
            guard let self, let device = self.videoDeviceInput?.device, device.hasTorch else { return }

            do {
                try device.lockForConfiguration()
                defer { device.unlockForConfiguration() }

                let level = Float(self.lightIntensity)
                if level > 0.01 {
                    let clampedLevel = min(max(level, AVCaptureDevice.minAvailableTorchLevel), AVCaptureDevice.maxAvailableTorchLevel)
                    try device.setTorchModeOn(level: clampedLevel)
                } else {
                    device.torchMode = .off
                }
            } catch {
                self.publishError("补光灯调节失败：\(error.localizedDescription)")
            }
        }
    }

    private func disableTorch() {
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
}

extension CameraService: AVCapturePhotoCaptureDelegate {
    func photoOutput(_ output: AVCapturePhotoOutput,
                     didFinishProcessingPhoto photo: AVCapturePhoto,
                     error: Error?) {
        if let error {
            publishError("拍照失败：\(error.localizedDescription)")
            return
        }

        guard let data = photo.fileDataRepresentation(), let image = UIImage(data: data) else {
            publishError("照片处理失败，请重试。")
            return
        }

        let processedImage = applyBrightness(to: image)
        DispatchQueue.main.async {
            self.capturedImage = processedImage
        }
    }
}
