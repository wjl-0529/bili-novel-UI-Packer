# Bili Novel Packer · iOS

原生 SwiftUI iOS 应用，目标 iOS 26+（兼容 iOS 27），使用 Liquid Glass 原生 API 并提供旧系统 fallback。参考 `Montaro2017/bili_novel_packer`，支持 linovelib、bilinovel 和 wenku8 的目录读取、章节选择、限速请求、插图下载、EPUB 3 导出和系统分享。

## 构建

仓库使用 XcodeGen 生成 Xcode 工程。GitHub Actions 在 macOS 26 上运行单元测试、归档，并通过 `CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO` 生成无签名 IPA。无签名 IPA 不能直接在普通设备安装，需要用户自行签名或使用适配的侧载工具。

本项目不绕过站点登录、验证码或访问控制；遇到 chapterlog 段落混淆时会停止导出，避免生成错序内容。
