# 轻小说打包器

一个用于将支持站点的轻小说打包为 EPUB 的工具。项目保留原有命令行入口，同时新增 Web 控制台，适合部署到个人服务器后批量提交下载任务。

## 功能

- 支持哔哩轻小说 / bilinovel 链接。
- 支持轻小说文库 / wenku8 链接。
- 支持按小说 ID 序列批量创建任务，例如 `1-100`。
- 支持选择分卷范围、合并分卷、为章节添加标题。
- Web 控制台可查看队列、进度、日志和 EPUB 下载文件。
- 每个批量任务可独立配置 Bark 通知，选择推送开始、成功、失败或进度事件。
- 提供 Docker Compose + Caddy 部署，支持域名 HTTPS。

## Web 控制台

本地或服务器启动后，在浏览器打开服务地址，使用管理密码登录。

新建任务时填写：

- URL 模板：例如 `https://www.bilinovel.com/novel/{id}.html`
- 小说 ID 范围：例如 `1-100`、`1,3,5-8`
- 分卷范围：留空表示全部分卷，填写 `1-3` 表示只下载对应分卷
- Bark 通知：填写 Bark 服务地址和设备 Key 后选择通知事件

任务按提交顺序依次执行，默认一次只运行一个任务，避免触发站点频率限制。

## Docker 部署

见 [DEPLOYMENT.md](./DEPLOYMENT.md)。

最简启动方式：

```bash
cp .env.example .env
docker compose up -d --build
```

## 命令行使用

原命令行入口仍然可用：

```bash
dart run bin/main.dart
```

Windows 编译：

```bash
dart compile exe bin/main.dart -o ./build/bili_novel_packer.exe
```

Linux/macOS 编译：

```bash
dart compile exe bin/main.dart -o ./build/bili_novel_packer
```

## Web 服务编译

```bash
dart compile exe bin/server.dart -o ./build/bili_novel_packer_server
```

## iOS IPA（未签名）

仓库的 `Build unsigned iOS IPA` GitHub Actions 会在 macOS runner 上构建 iPhone/iPad 安装包。`codex/ios-ipa`、`main` 分支的构建结果保存在 Actions Artifact 中 30 天；推送 `v*-ios*` 标签时，IPA 还会附加到对应的 GitHub 预发布版本。

该 IPA **没有 Apple 签名，不能直接点击安装**。安装时任选一种方式：

1. 在电脑上安装 AltStore 或 Sideloadly，或在设备上配置 SideStore。
2. 下载 Actions/Release 中名称以 `bili-novel-packer-ios-unsigned-` 开头的 IPA。
3. 在侧载工具中选择 IPA，使用自己的 Apple ID 完成重签并安装。

免费 Apple ID 的签名通常需要周期性刷新，具体周期以所用侧载工具和 Apple 当前规则为准。iOS App 首次打开时需要手动填写服务器地址，地址仅保存在设备本地，仓库和 IPA 不内置服务器、账号或密码。下载与 EPUB 打包任务在服务器持续执行，关闭 App 不会中断任务；重新打开后会恢复任务列表和实时进度。EPUB 生成后点击文件名会保存到 App 的 Documents 目录，并可继续通过系统分享面板保存到“文件”、AirDrop 或其他阅读器。

如后续提供付费 Apple Developer 证书和匹配 `com.bilinovelpacker.ios` 的描述文件，可以另加 Ad Hoc 或 TestFlight 签名工作流。

## 常见问题

### 为什么下载速度比较慢？

轻小说站点通常存在频率限制，请保持较低并发。Web 队列默认按顺序执行。

### 为什么偶尔下载失败？

源站可能更新反爬策略、限流或临时不可用。失败任务可以在 Web 控制台中重试。

### EPUB 文件在哪里？

Docker 部署时文件在 `data/outputs/<任务ID>/` 下，也可以直接在 Web 控制台点击“下载 EPUB”。
