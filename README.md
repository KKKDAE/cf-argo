# cf-argo

Cloudflared + Argo 隧道 + 优选 IP + 代理内核 全功能管理脚本

## 🚀 快速开始

### 一键安装

```bash
sudo bash -c "$(curl -fsSL https://raw.githubusercontent.com/KKKDAE/cf-argo/main/install.sh)"
```

### 安装后使用

```bash
# 进入交互式菜单
cf-complete

# 或直接运行特定功能
cf-complete 1    # 安装 cloudflared
cf-complete 3    # 优选 IP 测速
cf-complete 9    # 查看系统状态
```

## 📋 主要功能

### 1️⃣ 安装/更新 cloudflared
- 自动检测系统架构和操作系统
- 从官方 GitHub Release 下载最新版本
- 支持多种架构：x86_64, arm64, arm, 386
- 支持系统：Linux, macOS

### 2️⃣ 配置 Argo 隧道
- 交互式 Cloudflare 认证
- 创建或使用现有隧道
- 自动生成隧道配置文件
- 配置 DNS 路由
- 本地测试启动

### 3️⃣ Cloudflare 优选 IP 测速
- **内置 1000+ Cloudflare IP 地址**
- 并发多线程测速（支持自定义线程数）
- 综合评分算法（延迟 60% + 速度 40%）
- 丢包率检测
- 可视化结果展示

### 4️⃣ Cloudflare DNS 更新
- 支持 API Token 和 Global API Key 认证
- 自动创建/更新 A 记录
- 凭证本地持久化
- 操作日志记录

### 5️⃣ 本地 hosts 绑定
- 自动写入 /etc/hosts
- 备份原始文件
- 支持多域名绑定

### 6️⃣ Argo 隧道 + CNAME 优选路由
- 将优选 IP 写入本地 hosts
- 通过 CNAME 指向 Argo 隧道
- 实现最优路由效果

### 7️⃣ 代理内核集成（Xray/Sing-box）
- **Xray 支持**：VLESS + WebSocket, VMess + WebSocket
- **Sing-box 支持**：轻量级多协议代理
- 自动生成 UUID 和配置
- 自动对接现有 Argo 隧道
- systemd 服务管理

### 8️⃣ 定时自动优选
- Cron 定时任务设置
- 自定义执行间隔
- 自动测速和 DNS 更新
- 非交互模式支持

### 9️⃣ 系统状态查看
- 查看已安装组件版本
- 隧道配置信息
- 优选 IP 结果
- API 凭证状态
- 代理内核信息
- 定时任务列表

## 📁 脚本详解

### cf-complete 主脚本

主脚本提供完整的交互式命令行界面，包含所有功能菜单。

**位置**：`/opt/cf-argo/cf-complete`

**主要功能框架**：

```bash
#!/bin/bash
# ============================================================
# Cloudflared + Argo 隧道 + 优选 IP + 代理内核 全功能管理脚本
# ============================================================
```

**关键变量**：

```bash
# 配置路径
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="$SCRIPT_DIR/.cloudflare-config"
LOG_DIR="$CONFIG_DIR/logs"
RESULT_FILE="$CONFIG_DIR/best_ip.txt"

# Cloudflare 优选 IP 列表（1000+ 个 IP）
declare -a CF_IP_LIST=(
    "104.16.0.0" "104.16.1.0" ... "198.41.255.0"
)
```

**核心函数**：

```bash
# 1. 安装 cloudflared
install_cloudflared()
  - 自动检测架构和系统
  - 从 GitHub Release 下载
  - 处理权限和路径问题

# 2. Argo 隧道配置
setup_argo_tunnel()
  - 交互式认证和隧道创建
  - 配置本地服务代理
  - DNS 路由设置

# 3. IP 测速
run_speed_test()
  - 并发 Ping 和速度测试
  - 综合评分计算
  - 结果可视化展示

# 4. DNS 更新
update_cloudflare_dns()
  - API 认证处理
  - A 记录创建/更新
  - 凭证持久化

# 5. Hosts 写入
write_hosts_file()
  - /etc/hosts 操作
  - 自动备份
  - 重复检测

# 6. CNAME 路由
setup_argo_cname()
  - CNAME 记录管理
  - 本地 hosts 配置
  - Argo 隧道对接

# 7. 代理内核安装
install_proxy_core()
  - Xray/Sing-box 选择
  - 配置生成
  - 隧道自动对接

# 8. 定时任务
setup_cron()
  - Crontab 管理
  - 自动测速脚本
  - DNS 更新脚本

# 9. 状态查看
show_status()
  - 组件版本信息
  - 配置信息汇总
  - 日志查看

# 辅助函数
speed_test_ip()       # 单个 IP 测速
print_banner()        # 横幅显示
print_info/ok/warn() # 信息提示
```

**菜单系统**：

```
【主菜单】
1. 安装/更新 cloudflared
2. 配置 Argo 隧道
3. 优选 IP 测速
4. Cloudflare DNS 更新 (A 记录)
5. 写入 /etc/hosts
6. Argo 隧道 + CNAME 优选路由
7. 安装代理内核 (Xray/Sing-box) 并自动对接隧道
8. 设置定时自动优选
9. 查看系统状态
0. 退出
```

**非交互模式**：

```bash
cf-complete --auto-test    # 自动测速（用于 cron）
cf-complete --auto-dns     # 自动更新 DNS（用于 cron）
```

## 🛠️ 安装脚本详解

### install.sh 一键安装脚本

自动化安装程序，负责环境检查和初始化。

**功能**：

```bash
1. 系统检查
   ✓ 检查 root 权限
   ✓ 检查系统依赖 (curl, wget, git, ping, sed, awk)
   ✓ 自动安装缺失依赖 (apt/yum/apk)

2. 下载安装
   ✓ 从 GitHub 下载 cf-complete 主脚本
   ✓ 自动安装 cloudflared 二进制
   ✓ 支持多架构检测

3. 配置初始化
   ✓ 创建 /opt/cf-argo 目录
   ✓ 创建 .cloudflare-config 配置目录
   ✓ 创建 logs 日志目录
   ✓ 设置正确的权限

4. 快捷命令
   ✓ 创建全局 cf-complete 命令
   ✓ 设置 systemd 服务模板
   ✓ 添加 PATH 环境变量

5. 验证与提示
   ✓ 验证所有组件安装
   ✓ 显示使用说明
   ✓ 提示配置文件位置
```

**安装检查项**：

```
✓ cloudflared 版本验证
✓ cf-complete 脚本位置
✓ cf-complete 全局命令
✓ 配置目录权限
✓ 日志目录设置
```

## 📊 配置文件结构

```
/opt/cf-argo/
├── cf-complete                      # 主脚本
├── install.sh                       # 安装脚本
└── .cloudflare-config/
    ├── logs/                        # 日志目录
    │   └── dns_updates.log
    ├── best_ip.txt                  # 优选 IP 结果
    ├── tunnel_info.txt              # 隧道信息
    ├── proxy_info.txt               # 代理信息
    ├── argo_cname.conf              # CNAME 配置
    ├── cf_credentials.conf          # API 凭证（权限 600）
    └── [TUNNEL_ID].yml              # 隧道配置文件
```

## 🔐 安全性

- **凭证保护**：API 凭证文件权限设置为 600（仅所有者可读写）
- **备份机制**：修改 hosts 前自动备份原文件
- **配置隔离**：所有配置存储在 .cloudflare-config 目录
- **日志记录**：所有 DNS 更新操作都记录在案

## 🌐 支持的系统

| 系统 | 架构 | 状态 |
|------|------|------|
| Linux | x86_64 | ✅ 完全支持 |
| Linux | arm64 | ✅ 完全支持 |
| Linux | arm | ✅ 完全支持 |
| Linux | 386 | ✅ 完全支持 |
| macOS | x86_64 | ✅ 完全支持 |
| macOS | arm64 | ✅ 完全支持 |

## 📋 依赖要求

- **必需**：bash, curl/wget, ping, sed, awk, sort
- **可选**：git (用于克隆仓库)
- **包管理器**：apt-get (Debian/Ubuntu) / yum (CentOS/RHEL) / apk (Alpine)

## 🚀 使用案例

### 案例 1：快速部署 Argo 隧道

```bash
# 1. 一键安装
sudo bash -c "$(curl -fsSL https://raw.githubusercontent.com/KKKDAE/cf-argo/main/install.sh)"

# 2. 进入菜单
cf-complete

# 3. 选择 2：配置 Argo 隧道
# 4. 选择 3：运行优选 IP 测速
# 5. 选择 4：更新 DNS A 记录
```

### 案例 2：代理服务器配置

```bash
cf-complete          # 进入菜单
# 选择 7：安装代理内核 (Xray/Sing-box)
# 选择 VLESS + WebSocket
# 自动对接现有隧道
```

### 案例 3：定时自动优选

```bash
cf-complete          # 进入菜单
# 选择 8：设置定时自动优选
# 输入间隔时间（小时）
# Cron 任务自动设置
```

## 📝 常见问题

### Q：如何更新脚本？
```bash
sudo bash -c "$(curl -fsSL https://raw.githubusercontent.com/KKKDAE/cf-argo/main/install.sh)"
```

### Q：如何查看日志？
```bash
tail -f /opt/cf-argo/.cloudflare-config/logs/dns_updates.log
```

### Q：如何卸载？
```bash
bash install.sh uninstall
```

### Q：脚本支持非交互模式吗？
```bash
# 自动测速（用于 cron）
cf-complete --auto-test

# 自动更新 DNS（用于 cron）
cf-complete --auto-dns
```

## 🔗 相关资源

- [Cloudflare 官网](https://www.cloudflare.com)
- [Cloudflared GitHub](https://github.com/cloudflare/cloudflared)
- [Xray 项目](https://github.com/XTLS/Xray-core)
- [Sing-box 项目](https://github.com/SagerNet/sing-box)

## 📄 许可证

MIT License

## 🙋 贡献

欢迎提交 Issue 和 Pull Request！

---

**最后更新**：2026-06-07
