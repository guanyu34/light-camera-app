import SwiftUI

struct ContentView: View {
    @StateObject private var cameraService = CameraService()

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color.black.ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 20) {
                        previewSection
                        controlSection
                        photoSection
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, proxy.safeAreaInsets.top + 8)
                    .padding(.bottom, max(proxy.safeAreaInsets.bottom, 20) + 8)
                }
            }
        }
        .onAppear {
            cameraService.startSession()
        }
        .onDisappear {
            cameraService.stopSession()
        }
    }

    private var previewSection: some View {
        ZStack(alignment: .topLeading) {
            ZStack {
                if cameraService.authorizationStatus == .authorized {
                    CameraPreviewView(session: cameraService.session)
                } else {
                    Color.black.opacity(0.55)
                }

                Color.white
                    .opacity(cameraService.authorizationStatus == .authorized ? cameraService.lightIntensity * 0.35 : 0)
                    .blendMode(.screen)

                previewStatusOverlay
            }
            .frame(maxWidth: .infinity)
            .frame(height: 420)
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            )

            Label("补光相机", systemImage: "sun.max.fill")
                .font(.headline)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial, in: Capsule())
                .padding(.top, 18)
                .padding(.leading, 16)
        }
    }

    @ViewBuilder
    private var previewStatusOverlay: some View {
        if cameraService.authorizationStatus != .authorized || !cameraService.isSessionReady || cameraService.errorMessage != nil {
            VStack(spacing: 12) {
                Image(systemName: cameraService.authorizationStatus == .authorized ? "camera.aperture" : "camera.fill")
                    .font(.system(size: 38))
                    .foregroundStyle(.white)

                Text(cameraService.errorMessage ?? cameraService.statusText)
                    .font(.headline)
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)

                if cameraService.authorizationStatus == .authorized, cameraService.errorMessage == nil {
                    ProgressView()
                        .tint(.white)
                } else {
                    Text("请在设置中开启相机权限后重新进入应用")
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.72))
                        .multilineTextAlignment(.center)
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black.opacity(0.3))
        }
    }

    private var controlSection: some View {
        VStack(spacing: 18) {
            sliderCard(
                title: "补光强度",
                value: cameraService.lightIntensity,
                range: 0...1,
                accentColor: .yellow,
                leadingIcon: "sun.min.fill",
                trailingIcon: "sun.max.fill"
            ) {
                cameraService.lightIntensity = $0
            }

            sliderCard(
                title: "照片亮度",
                value: cameraService.brightnessAdjustment,
                range: -0.2...0.45,
                accentColor: .orange,
                leadingIcon: "moon.fill",
                trailingIcon: "sparkles"
            ) {
                cameraService.brightnessAdjustment = $0
            }

            Button {
                cameraService.capturePhoto()
            } label: {
                HStack(spacing: 12) {
                    if cameraService.isCapturingPhoto {
                        ProgressView()
                            .tint(.black)
                    } else {
                        Image(systemName: "camera.circle.fill")
                            .font(.system(size: 24))
                    }

                    Text(cameraService.isCapturingPhoto ? "拍照中…" : "立即拍照")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
                .background(
                    LinearGradient(
                        colors: [Color.yellow, Color.orange],
                        startPoint: .leading,
                        endPoint: .trailing
                    ),
                    in: RoundedRectangle(cornerRadius: 20, style: .continuous)
                )
                .foregroundStyle(.black)
            }
            .disabled(!cameraService.isSessionReady || cameraService.isCapturingPhoto)
            .opacity((!cameraService.isSessionReady || cameraService.isCapturingPhoto) ? 0.65 : 1)
        }
    }

    private var photoSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("最新照片")
                    .font(.headline)
                    .foregroundStyle(.white)
                Spacer()
                Text(cameraService.capturedImage == nil ? "等待拍摄" : cameraService.statusText)
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.6))
            }

            Group {
                if let image = cameraService.capturedImage {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    VStack(spacing: 10) {
                        Image(systemName: "photo.on.rectangle.angled")
                            .font(.system(size: 30))
                        Text(cameraService.isSessionReady ? "拍完会在这里预览处理后的照片" : "等待相机准备完成后即可拍照")
                            .font(.subheadline)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .foregroundStyle(.white.opacity(0.75))
                    .background(Color.white.opacity(0.06))
                }
            }
            .frame(height: 180)
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            )
        }
    }

    private func sliderCard(title: String,
                            value: Double,
                            range: ClosedRange<Double>,
                            accentColor: Color,
                            leadingIcon: String,
                            trailingIcon: String,
                            action: @escaping (Double) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.white)
                Spacer()
                Text(value.formatted(.number.precision(.fractionLength(2))))
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.white.opacity(0.7))
            }

            HStack(spacing: 12) {
                Image(systemName: leadingIcon)
                    .foregroundStyle(accentColor)
                Slider(value: Binding(get: { value }, set: action), in: range)
                    .tint(accentColor)
                Image(systemName: trailingIcon)
                    .foregroundStyle(accentColor)
            }
        }
        .padding(18)
        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

#Preview {
    ContentView()
}
