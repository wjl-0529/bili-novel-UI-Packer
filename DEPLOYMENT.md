# 轻小说打包器 Web 部署说明

## 服务器要求

- Linux 服务器。
- 已安装 Docker 和 Docker Compose。
- 域名已经解析到服务器公网 IP。
- 服务器开放 `80` 和 `443` 端口。

## 配置

复制环境变量示例：

```bash
cp .env.example .env
```

编辑 `.env`：

```bash
DOMAIN=novel.example.com
ADMIN_PASSWORD=use-a-long-password
MAX_BATCH_SIZE=100
NODE_IMAGE=node:20-alpine
DART_IMAGE=dart:stable
NPM_REGISTRY=https://registry.npmjs.org
```

如果服务器访问 Docker Hub 或 npm 官方源较慢，可以把 `NODE_IMAGE`、`DART_IMAGE` 或 `NPM_REGISTRY` 改成可用镜像源。

## 启动

```bash
docker compose up -d --build
```

Caddy 会为 `DOMAIN` 自动申请并续期 HTTPS 证书。

数据目录：

- 任务记录：`./data/jobs.json`
- EPUB 文件：`./data/outputs/<任务ID>/`
- Caddy 数据：`./caddy_data`、`./caddy_config`

## Bark 通知

在 Web 控制台的新建任务区域启用 Bark，填写：

- Bark 服务地址，例如 `https://api.day.app`
- 设备 Key
- 要推送到手机的事件：开始、成功、失败、进度

进度通知建议保持关闭，避免频繁推送。

## 本地 HTTP 测试

不使用 Caddy 时可以直接运行容器：

```bash
docker build -t bili-novel-packer-web .
docker run --rm -p 8080:8080 \
  -e ADMIN_PASSWORD=admin \
  -e COOKIE_SECURE=false \
  -v "${PWD}/data:/data" \
  bili-novel-packer-web
```

打开 `http://localhost:8080`。

## 常用命令

查看日志：

```bash
docker compose logs -f app
```

重启：

```bash
docker compose restart
```

停止：

```bash
docker compose down
```
