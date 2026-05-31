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

## 常见问题

### 为什么下载速度比较慢？

轻小说站点通常存在频率限制，请保持较低并发。Web 队列默认按顺序执行。

### 为什么偶尔下载失败？

源站可能更新反爬策略、限流或临时不可用。失败任务可以在 Web 控制台中重试。

### EPUB 文件在哪里？

Docker 部署时文件在 `data/outputs/<任务ID>/` 下，也可以直接在 Web 控制台点击“下载 EPUB”。
