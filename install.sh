# Cloudflare Argo Tunnel + VLESS Proxy 一键部署脚本

本脚本用于在任意 Linux 服务器上快速部署 **Cloudflare Argo 隧道** 与 **VLESS + WebSocket + TLS** 代理，实现 Cloudflare CDN 加速和隐藏源站，无需公网 IP，零人工干预。

## ✨ 功能特性

- **全自动部署**：提供邮箱和 Global API Key 即可自动完成全部配置
- **Argo 隧道**：使用 Cloudflare 官方 cloudflared 建立安全隧道
- **代理内核**：默认部署 Sing‑box (VLESS + WebSocket)，兼容 Xray-core
- **TLS 加密**：利用 Cloudflare 边缘证书，无需自签
- **优选 IP**：支持手动指定 Cloudflare 优选 IP 提升速度
- **兼容性**：支持 systemd 和 nohup 守护进程
- **零交互**：部署过程中完全无需人工介入

## 📋 前置条件

1. **一个 Cloudflare 账号**，并将域名 DNS 托管在 Cloudflare  
2. **一台 Linux 服务器**（Debian/Ubuntu/CentOS/Alpine 均可，推荐 Debian 11+）  
3. **Root 权限** 或具有 sudo 权限的用户  
4. **获取 Global API Key**：访问 [Cloudflare API Tokens](https://dash.cloudflare.com/profile/api-tokens) 页面，找到 “Global API Key”

> ⚠️ Global API Key 具有账户完整权限，请仅在受信环境使用，避免泄露。

## 🚀 快速开始

### 1. 下载并执行安装脚本

```bash
# 方式一：使用 curl
curl -fsSL https://raw.githubusercontent.com/your/repo/main/install.sh | sudo bash

# 方式二：使用 wget
wget -qO- https://raw.githubusercontent.com/your/repo/main/install.sh | sudo bash
