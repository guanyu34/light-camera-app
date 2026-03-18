# LightCameraApp

一个用 SwiftUI + AVFoundation 编写的 iOS 补光相机示例，提供：

- 实时相机预览
- 补光强度调节（支持设备手电筒时会同步调节 torch）
- 拍照功能
- 拍照后的亮度增强与预览

## 打开方式

1. 使用 Xcode 16+ 打开 `LightCameraApp.xcodeproj`
2. 选择 iPhone 真机运行（手电筒能力需要真机）
3. 首次启动时授予相机权限

## 说明

- `补光强度`：控制预览上的补光叠加效果，并在设备支持时同步调节 torch 亮度。
- `照片亮度`：对拍照后的图像应用亮度增强，便于弱光环境下拍摄。
