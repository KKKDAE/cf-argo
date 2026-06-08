#!/bin/bash
# ============================================================
# 一键安装脚本：Cloudflare Argo 隧道 + VLESS 代理全自动部署
# 使用：
#   curl -fsSL https://yourserver.com/install.sh | bash
#   或
#   wget -qO- https://yourserver.com/install.sh | bash
# ============================================================
set -e

export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$PATH"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
print_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
print_ok()   { echo -e "${GREEN}[OK]${NC} $1"; }
print_err()  { echo -e "${RED}[ERR]${NC} $1"; }

# 检查root
if [[ $EUID -ne 0 ]]; then
    print_err "请使用root权限运行 (sudo bash install.sh)"
    exit 1
fi

# 安装依赖
print_info "安装依赖..."
if command -v apt-get &>/dev/null; then
    apt-get update -qq && apt-get install -y curl wget tar python3
elif command -v yum &>/dev/null; then
    yum install -y curl wget tar python3
elif command -v apk &>/dev/null; then
    apk add curl wget tar python3
else
    print_err "不支持的包管理器，请手动安装: curl wget tar python3"
    exit 1
fi
print_ok "依赖安装完成"

# 安装全自动部署脚本 cf-auto
print_info "安装 cf-auto 管理工具..."
cat > /usr/local/bin/cf-auto << 'CFAUTO_EOF'
#!/bin/bash
# ============================================================
# Cloudflare Argo + Sing-box 全自动部署脚本 v1.0
# 使用方式：
#   export CF_EMAIL=your@email.com
#   export CF_API_KEY=your-global-api-key
#   export DOMAIN=your-domain.example.com
#   cf-auto --deploy
# ============================================================
set -e
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$PATH"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
print_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
print_ok()   { echo -e "${GREEN}[OK]${NC} $1"; }
print_err()  { echo -e "${RED}[ERR]${NC} $1"; }

CONFIG_DIR="$HOME/.cloudflare-config"
LOG_DIR="$CONFIG_DIR/logs"
mkdir -p "$CONFIG_DIR" "$LOG_DIR"

has_systemd() { [[ -d /run/systemd/system || $(ps --no-headers -o comm 1 2>/dev/null) == "systemd" ]]; }

# 安装 cloudflared
install_cloudflared() {
    if command -v cloudflared &>/dev/null; then
        print_ok "cloudflared 已安装"
        return
    fi
    local arch=$(uname -m)
    case $arch in x86_64|amd64) arch="amd64";; aarch64|arm64) arch="arm64";; armv7l) arch="arm";; *) print_err "不支持的架构"; exit 1;; esac
    local os=$(uname -s | tr '[:upper:]' '[:lower:]')
    local dl="https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-${os}-${arch}"
    print_info "下载 cloudflared..."
    local tmp=$(mktemp)
    curl -fsSL -o "$tmp" "$dl" || { print_err "下载失败"; exit 1; }
    chmod +x "$tmp"
    mv "$tmp" /usr/local/bin/cloudflared
    print_ok "cloudflared 安装完成"
}

# 安装 Sing-box
install_singbox() {
    if command -v sing-box &>/dev/null; then
        print_ok "Sing-box 已安装"
        return
    fi
    local arch=$(uname -m)
    case $arch in x86_64) arch="amd64";; aarch64) arch="arm64";; *) print_err "不支持的架构"; exit 1;; esac
    cd /tmp
    local ver=$(curl -s https://api.github.com/repos/SagerNet/sing-box/releases/latest | grep tag_name | cut -d '"' -f 4)
    local dl="https://github.com/SagerNet/sing-box/releases/download/${ver}/sing-box-${ver#v}-linux-${arch}.tar.gz"
    curl -L -o sb.tar.gz "$dl" || { print_err "下载失败"; exit 1; }
    tar -xzf sb.tar.gz
    mv sing-box-*/sing-box /usr/local/bin/
    chmod +x /usr/local/bin/sing-box
    rm -rf sing-box-* sb.tar.gz
    print_ok "Sing-box 安装完成"
}

# 启动代理
start_proxy() {
    UUID=$(cat /proc/sys/kernel/random/uuid 2>/dev/null || uuidgen)
    PORT=8443
    WSPATH="/${UUID//-/}"
    mkdir -p /etc/sing-box
    cat > /etc/sing-box/config.json <<EOF
{
  "log": {"level": "info"},
  "inbounds": [{
    "type": "vless",
    "listen": "127.0.0.1",
    "listen_port": ${PORT},
    "users": [{"uuid": "${UUID}"}],
    "transport": {"type": "ws", "path": "${WSPATH}"}
  }],
  "outbounds": [{"type": "direct"}]
}
EOF

    if has_systemd; then
        cat > /etc/systemd/system/sing-box.service <<SVC
[Unit]
Description=Sing-box
After=network.target
[Service]
Type=simple
ExecStart=/usr/local/bin/sing-box run -c /etc/sing-box/config.json
Restart=on-failure
[Install]
WantedBy=multi-user.target
SVC
        systemctl daemon-reload
        systemctl restart sing-box
        systemctl enable sing-box
        print_ok "Sing-box 已启动 (systemd)"
    else
        pkill sing-box 2>/dev/null || true
        nohup /usr/local/bin/sing-box run -c /etc/sing-box/config.json > /var/log/sing-box.log 2>&1 &
        print_ok "Sing-box 已启动 (nohup)"
    fi
    # 保存代理信息
    cat > "$CONFIG_DIR/proxy_info.txt" <<EOF
UUID=${UUID}
PORT=${PORT}
WSPATH=${WSPATH}
EOF
}

# 配置隧道
setup_tunnel() {
    local cf_email="$1"
    local cf_apikey="$2"
    local domain="$3"

    print_info "登录 Cloudflare..."
    cloudflared tunnel login --email "$cf_email" --api-key "$cf_apikey"

    print_info "创建隧道..."
    local tname="auto-$(date +%s)"
    cloudflared tunnel create "$tname"
    local tid=$(cloudflared tunnel list | grep "$tname" | awk '{print $1}')

    print_info "配置 DNS: $domain"
    cloudflared tunnel route dns "$tid" "$domain"

    local cfg="$CONFIG_DIR/${tid}.yml"
    cat > "$cfg" <<EOF
tunnel: ${tid}
credentials-file: ${HOME}/.cloudflared/${tid}.json
ingress:
  - hostname: ${domain}
    service: http://127.0.0.1:8443
  - service: http_status:404
EOF

    # 保存信息
    cat > "$CONFIG_DIR/tunnel_info.txt" <<EOF
TUNNEL_ID=${tid}
TUNNEL_NAME=${tname}
TUNNEL_DOMAIN=${domain}
CONFIG_FILE=${cfg}
EOF

    # 重启隧道
    pkill cloudflared 2>/dev/null || true
    nohup cloudflared tunnel --config "$cfg" run "$tid" > /var/log/cloudflared.log 2>&1 &
    print_ok "隧道已启动"
}

# 生成链接
generate_link() {
    source "$CONFIG_DIR/proxy_info.txt"
    source "$CONFIG_DIR/tunnel_info.txt"
    local ip="${1:-$TUNNEL_DOMAIN}"
    local encoded_path=$(python3 -c "import urllib.parse; print(urllib.parse.quote('${WSPATH}'))" 2>/dev/null || echo "$WSPATH")
    echo -e "\n${GREEN}========== VLESS 客户端链接 ==========${NC}"
    echo "vless://${UUID}@${ip}:${PORT}?encryption=none&security=tls&sni=${TUNNEL_DOMAIN}&type=ws&host=${TUNNEL_DOMAIN}&path=${encoded_path}#Auto-${TUNNEL_DOMAIN}"
}

# 主部署流程
deploy() {
    # 检查环境变量
    if [[ -z "$CF_EMAIL" || -z "$CF_API_KEY" || -z "$DOMAIN" ]]; then
        print_err "请设置环境变量:"
        echo "  export CF_EMAIL=your@email.com"
        echo "  export CF_API_KEY=your-global-api-key"
        echo "  export DOMAIN=your-domain.example.com"
        echo "  export PREFERRED_IP=1.2.3.4   # 可选，优选IP"
        echo "  然后运行: cf-auto --deploy"
        exit 1
    fi

    install_cloudflared
    install_singbox
    start_proxy
    setup_tunnel "$CF_EMAIL" "$CF_API_KEY" "$DOMAIN"
    generate_link "${PREFERRED_IP:-}"
}

case "${1:-}" in
    --deploy|deploy) deploy ;;
    *) echo "用法: cf-auto --deploy   # 全自动部署"
       echo "请先设置环境变量: CF_EMAIL, CF_API_KEY, DOMAIN" ;;
esac
CFAUTO_EOF

chmod +x /usr/local/bin/cf-auto
print_ok "cf-auto 安装完成！"

# 输出使用说明
echo ""
echo -e "${GREEN}============================================${NC}"
echo -e "  安装成功！全自动部署只需三步："
echo -e ""
echo -e "  1. 设置环境变量"
echo -e "     ${CYAN}export CF_EMAIL=your@email.com${NC}"
echo -e "     ${CYAN}export CF_API_KEY=your-global-api-key${NC}"
echo -e "     ${CYAN}export DOMAIN=your-domain.example.com${NC}"
echo -e "     ${CYAN}# export PREFERRED_IP=1.2.3.4  # 可选${NC}"
echo -e ""
echo -e "  2. 执行部署"
echo -e "     ${CYAN}cf-auto --deploy${NC}"
echo -e ""
echo -e "  3. 获取链接并导入客户端"
echo -e ""
echo -e "  安装目录: /usr/local/bin/cf-auto"
echo -e "  配置文件: ~/.cloudflare-config/"
echo -e "${GREEN}============================================${NC}"
