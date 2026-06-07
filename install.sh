#!/bin/bash
# ============================================================
# install.sh - 一键安装 Cloudflared + Argo 隧道 + 代理内核管理工具
# 版本: 2.0 (修复版)
# 功能: 自动安装依赖、cloudflared 和 cf-manager 管理工具
# ============================================================

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

print_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
print_ok()   { echo -e "${GREEN}[OK]${NC} $1"; }
print_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
print_err()  { echo -e "${RED}[ERR]${NC} $1"; }

# ---------- 检查 root 权限 ----------
check_root() {
    if [[ $EUID -eq 0 ]]; then
        print_warn "检测到 root 用户，建议使用普通用户运行"
        print_info "如需安装到系统目录，部分步骤会使用 sudo"
    fi
}

# ---------- 安装系统依赖 ----------
install_deps() {
    print_info "检查并安装系统依赖..."
    local deps=(curl wget jq tar gzip)
    local to_install=()
    
    for cmd in "${deps[@]}"; do
        if ! command -v "$cmd" &>/dev/null; then
            to_install+=("$cmd")
        fi
    done
    
    if [[ ${#to_install[@]} -gt 0 ]]; then
        print_warn "需要安装: ${to_install[*]}"
        if command -v apt-get &>/dev/null; then
            sudo apt-get update -qq
            sudo apt-get install -y "${to_install[@]}"
        elif command -v yum &>/dev/null; then
            sudo yum install -y "${to_install[@]}"
        elif command -v dnf &>/dev/null; then
            sudo dnf install -y "${to_install[@]}"
        elif command -v apk &>/dev/null; then
            sudo apk add "${to_install[@]}"
        elif command -v pacman &>/dev/null; then
            sudo pacman -S --noconfirm "${to_install[@]}"
        else
            print_err "无法自动安装依赖，请手动安装: ${to_install[*]}"
            exit 1
        fi
    fi
    
    # 安装 Python3（用于 URL 编码）
    if ! command -v python3 &>/dev/null; then
        print_warn "安装 python3..."
        if command -v apt-get &>/dev/null; then
            sudo apt-get install -y python3
        elif command -v yum &>/dev/null; then
            sudo yum install -y python3
        elif command -v dnf &>/dev/null; then
            sudo dnf install -y python3
        fi
    fi
    
    print_ok "依赖检查完成"
}

# ---------- 安装 cloudflared ----------
install_cloudflared() {
    print_info "检查 cloudflared..."
    
    if command -v cloudflared &>/dev/null; then
        print_ok "cloudflared 已安装: $(cloudflared --version 2>/dev/null | head -1)"
        return 0
    fi
    
    print_info "安装 cloudflared..."
    local arch=$(uname -m)
    local os=$(uname -s | tr '[:upper:]' '[:lower:]')
    
    case "$arch" in
        x86_64|amd64)  arch="amd64" ;;
        aarch64|arm64) arch="arm64" ;;
        armv7l|armv7)  arch="arm" ;;
        i386|i686)     arch="386" ;;
        *) print_err "不支持的架构: $arch"; return 1 ;;
    esac
    
    local download_url="https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-${os}-${arch}"
    print_info "下载: $download_url"
    
    local tmpfile=$(mktemp)
    if curl -fsSL -o "$tmpfile" "$download_url"; then
        chmod +x "$tmpfile"
        if [[ "$os" == "linux" ]]; then
            sudo mv "$tmpfile" /usr/local/bin/cloudflared 2>/dev/null || {
                mkdir -p ~/.local/bin
                mv "$tmpfile" ~/.local/bin/cloudflared
                export PATH="$HOME/.local/bin:$PATH"
                echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc
                print_warn "已安装到 ~/.local/bin，请执行: source ~/.bashrc"
            }
        else
            sudo mv "$tmpfile" /usr/local/bin/cloudflared 2>/dev/null || mv "$tmpfile" /usr/local/bin/cloudflared
        fi
        print_ok "cloudflared 安装完成"
    else
        print_err "cloudflared 下载失败"
        rm -f "$tmpfile"
        return 1
    fi
}

# ---------- 安装 cf-manager 主程序 ----------
install_cf_manager() {
    local install_path="/usr/local/bin/cf-manager"
    
    print_info "安装 cf-manager 到 $install_path ..."
    
    sudo tee "$install_path" > /dev/null << 'CFMANAGER_EOF'
#!/bin/bash
# ============================================================
# Cloudflared + Argo 隧道 + 代理内核 全功能管理脚本 v2.0
# ============================================================

set -e

# ---------- 颜色定义 ----------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# ---------- 配置变量 ----------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="$HOME/.cloudflare-config"
LOG_DIR="$CONFIG_DIR/logs"
CF_API_URL="https://api.cloudflare.com/client/v4"
MAX_RETRIES=5
RETRY_DELAY=2

# ---------- 工具函数 ----------
print_banner() {
    echo -e "${CYAN}"
    echo "╔════════════════════════════════════════════════════════════╗"
    echo "║   Cloudflared + Argo 隧道 + 代理内核 管理工具 v2.0          ║"
    echo "╚════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}
print_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
print_ok()   { echo -e "${GREEN}[OK]${NC} $1"; }
print_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
print_err()  { echo -e "${RED}[ERR]${NC} $1"; }

require_cmd() {
    if ! command -v "$1" &>/dev/null; then
        print_err "缺少命令: $1，请先安装"
        return 1
    fi
    return 0
}

ensure_dirs() {
    mkdir -p "$CONFIG_DIR" "$LOG_DIR"
}

# ---------- API 请求重试函数 ----------
curl_with_retry() {
    local method="$1"
    local url="$2"
    local headers=()
    local data=""
    local retry_count=0

    shift 2
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -H) headers+=("$2"); shift 2 ;;
            -d) data="$2"; shift 2 ;;
            *) shift ;;
        esac
    done

    while (( retry_count < MAX_RETRIES )); do
        local cmd="curl -fsSL -X $method '$url'"
        for header in "${headers[@]}"; do
            cmd="$cmd -H '$header'"
        done
        [[ -n "$data" ]] && cmd="$cmd -d '$data'"
        
        local response=$(eval "$cmd" 2>/dev/null)
        
        if echo "$response" | grep -q '"success":true'; then
            echo "$response"
            return 0
        fi
        
        print_warn "API 请求失败，重试 ($((retry_count + 1))/$MAX_RETRIES)"
        ((retry_count++))
        sleep "$RETRY_DELAY"
    done
    
    print_err "API 请求失败"
    return 1
}

# ---------- 1. 安装 cloudflared ----------
install_cloudflared() {
    echo -e "\n${CYAN}========== 安装 cloudflared ==========${NC}"
    if command -v cloudflared &>/dev/null; then
        print_ok "已安装: $(cloudflared --version | head -1)"
        read -rp "重新安装? [y/N]: " c; [[ "$c" =~ ^[Yy]$ ]] || return 0
    fi

    local arch=$(uname -m); local os=$(uname -s | tr '[:upper:]' '[:lower:]')
    case "$arch" in
        x86_64|amd64) arch="amd64";; aarch64|arm64) arch="arm64";; armv7l) arch="arm";;
        *) print_err "不支持的架构"; return 1;;
    esac

    local dl="https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-${os}-${arch}"
    local tmp=$(mktemp)
    curl -fsSL -o "$tmp" "$dl" || { print_err "下载失败"; return 1; }
    chmod +x "$tmp"
    sudo mv "$tmp" /usr/local/bin/cloudflared 2>/dev/null || {
        mkdir -p ~/.local/bin; mv "$tmp" ~/.local/bin/cloudflared
        export PATH="$HOME/.local/bin:$PATH"
    }
    print_ok "安装完成"; cloudflared --version
}

# ---------- 2. 配置 Argo 隧道 ----------
setup_argo_tunnel() {
    echo -e "\n${CYAN}========== 配置 Argo 隧道 ==========${NC}"
    require_cmd cloudflared || return 1

    # 认证
    print_info "步骤 1: 认证"
    local auth=""
    if [[ -f "$HOME/.cloudflared/cert.pem" ]]; then
        print_ok "已有证书"; read -rp "重新认证? [y/N]: " r; [[ "$r" =~ ^[Yy]$ ]] || auth="skip"
    fi
    if [[ "$auth" != "skip" ]]; then
        echo "1) 浏览器认证  2) Email + Global API Key"
        read -rp "选择 [1-2]: " a
        case $a in
        2) read -rp "邮箱: " e; read -rsp "API Key: " k; echo
           cloudflared tunnel login --email "$e" --api-key "$k";;
        *) cloudflared tunnel login;;
        esac
    fi

    # 创建/选择隧道
    print_info "步骤 2: 隧道"
    echo "1) 新建  2) 列出  3) 手动输入"
    read -rp "选择 [1-3]: " c
    local id="" name=""
    case $c in
    1) read -rp "名称: " name; cloudflared tunnel create "$name"
       id=$(cloudflared tunnel list | grep "$name" | awk '{print $1}');;
    2) cloudflared tunnel list; read -rp "ID: " id;;
    3) read -rp "ID: " id;;
    *) print_err "无效"; return 1;;
    esac
    [[ -z "$id" ]] && { print_err "ID 无效"; return 1; }

    # 配置路由
    read -rp "本地服务地址 (默认 http://localhost:8080): " svc
    svc=${svc:-http://localhost:8080}
    read -rp "域名: " domain
    [[ -z "$domain" ]] && { print_err "域名必填"; return 1; }

    local cfg="$CONFIG_DIR/${id}.yml"
    cat > "$cfg" <<EOF
tunnel: ${id}
credentials-file: ${HOME}/.cloudflared/${id}.json
ingress:
  - hostname: ${domain}
    service: ${svc}
  - service: http_status:404
EOF
    print_info "配置: $cfg"; cat "$cfg"

    cloudflared tunnel route dns "$id" "$domain"
    print_ok "DNS 路由: $domain -> $id"

    cat > "$CONFIG_DIR/tunnel_info.txt" <<EOF
TUNNEL_ID=${id}
TUNNEL_NAME=${name:-unknown}
TUNNEL_DOMAIN=${domain}
LOCAL_SERVICE=${svc}
CONFIG_FILE=${cfg}
EOF

    read -rp "启动测试? [Y/n]: " s
    [[ ! "$s" =~ ^[Nn]$ ]] && cloudflared tunnel --config "$cfg" run "$id"
    print_ok "配置完成"
}

# ---------- 3. DNS 更新 ----------
update_cloudflare_dns() {
    echo -e "\n${CYAN}========== DNS 更新 ==========${NC}"
    require_cmd curl || return 1
    read -rp "IP: " ip; [[ -z "$ip" ]] && return 1
    
    local cred="$CONFIG_DIR/cf_credentials.conf"
    local token="" key="" email="" zone="" rec=""
    
    if [[ -f "$cred" ]]; then
        source "$cred"
        print_ok "已加载凭证"
        read -rp "使用已有凭证? [Y/n]: " use; [[ "$use" =~ ^[Nn]$ ]] && { token=""; key=""; }
    fi
    
    if [[ -z "$token" && -z "$key" ]]; then
        echo "1) API Token  2) Global API Key + Email"
        read -rp "选择 [1-2]: " a
        case $a in
        1) read -rsp "API Token: " token; echo ;;
        2) read -rp "Email: " email; read -rsp "API Key: " key; echo ;;
        esac
        read -rp "Zone ID: " zone
        read -rp "域名记录: " rec
    fi
    
    local auth=""
    [[ -n "$token" ]] && auth="Authorization: Bearer ${token}" || auth="X-Auth-Key: ${key}"
    
    # 保存凭证
    cat > "$cred" <<EOF
API_TOKEN=${token}
API_KEY=${key}
EMAIL=${email}
ZONE_ID=${zone}
RECORD_NAME=${rec}
EOF
    chmod 600 "$cred"

    local list_url="${CF_API_URL}/zones/${zone}/dns_records?type=A&name=${rec}"
    local resp=$(curl_with_retry "GET" "$list_url" -H "Content-Type: application/json" -H "$auth" ${email:+-H "X-Auth-Email: ${email}"}) || return 1
    local rid=$(echo "$resp" | grep -oP '"id":"[^"]+"' | head -1 | cut -d'"' -f4)
    
    local payload="{\"type\":\"A\",\"name\":\"${rec}\",\"content\":\"${ip}\",\"ttl\":120,\"proxied\":false}"
    if [[ -n "$rid" ]]; then
        curl_with_retry "PUT" "${CF_API_URL}/zones/${zone}/dns_records/${rid}" -H "Content-Type: application/json" -H "$auth" ${email:+-H "X-Auth-Email: ${email}"} -d "$payload" > /dev/null
    else
        curl_with_retry "POST" "${CF_API_URL}/zones/${zone}/dns_records" -H "Content-Type: application/json" -H "$auth" ${email:+-H "X-Auth-Email: ${email}"} -d "$payload" > /dev/null
    fi
    print_ok "DNS 更新: $rec -> $ip"
}

# ---------- 4. hosts 写入 ----------
write_hosts_file() {
    local ip=${1:-}; local domain=${2:-}
    [[ -z "$ip" ]] && read -rp "IP: " ip
    [[ -z "$domain" ]] && read -rp "域名: " domain
    [[ -z "$ip" || -z "$domain" ]] && return 1
    
    sudo sed -i "/${domain}.*# CF/d" /etc/hosts 2>/dev/null
    echo "${ip} ${domain} # CF" | sudo tee -a /etc/hosts >/dev/null
    print_ok "已写入: $ip $domain"
}

# ---------- 5. CNAME 优选 ----------
setup_argo_cname() {
    [[ ! -f "$CONFIG_DIR/tunnel_info.txt" ]] && { print_err "请先配置隧道"; return 1; }
    source "$CONFIG_DIR/tunnel_info.txt"
    
    read -rp "优选 IP: " ip; [[ -z "$ip" ]] && return 1
    read -rp "写入 hosts? [Y/n]: " h; [[ ! "$h" =~ ^[Nn]$ ]] && write_hosts_file "$ip" "$TUNNEL_DOMAIN"
    
    read -rp "CNAME 域名: " cname; [[ -z "$cname" ]] && return 1
    [[ ! -f "$CONFIG_DIR/cf_credentials.conf" ]] && { print_err "请先配置 API 凭证"; return 1; }
    source "$CONFIG_DIR/cf_credentials.conf"
    
    local auth=""; [[ -n "$API_TOKEN" ]] && auth="Authorization: Bearer ${API_TOKEN}" || auth="X-Auth-Key: ${API_KEY}"
    local target="${TUNNEL_ID}.cfargotunnel.com"
    local payload="{\"type\":\"CNAME\",\"name\":\"${cname}\",\"content\":\"${target}\",\"ttl\":120,\"proxied\":true}"
    local list_url="${CF_API_URL}/zones/${ZONE_ID}/dns_records?type=CNAME&name=${cname}"
    local resp=$(curl_with_retry "GET" "$list_url" -H "Content-Type: application/json" -H "$auth" ${EMAIL:+-H "X-Auth-Email: ${EMAIL}"}) || return 1
    local rid=$(echo "$resp" | grep -oP '"id":"[^"]+"' | head -1 | cut -d'"' -f4)
    
    if [[ -n "$rid" ]]; then
        curl_with_retry "PUT" "${CF_API_URL}/zones/${ZONE_ID}/dns_records/${rid}" -H "Content-Type: application/json" -H "$auth" ${EMAIL:+-H "X-Auth-Email: ${EMAIL}"} -d "$payload" > /dev/null
    else
        curl_with_retry "POST" "${CF_API_URL}/zones/${ZONE_ID}/dns_records" -H "Content-Type: application/json" -H "$auth" ${EMAIL:+-H "X-Auth-Email: ${EMAIL}"} -d "$payload" > /dev/null
    fi
    print_ok "CNAME: $cname -> $target"
}

# ---------- 6. 安装代理内核（修复版）----------
install_proxy_core() {
    echo -e "\n${CYAN}========== 安装代理内核 ==========${NC}"
    echo "1) Xray  2) Sing-box"
    read -rp "选择 [1-2]: " core
    echo "1) VLESS+WS  2) VMess+WS"
    read -rp "协议 [1-2]: " proto
    
    local uuid=$(cat /proc/sys/kernel/random/uuid)
    local port=8443
    local path="/${uuid//-/}"
    local pt="vless"
    [[ "$proto" == "2" ]] && pt="vmess"
    
    print_info "UUID: $uuid  路径: $path"
    
    if [[ "$core" == "1" ]]; then
        print_info "安装 Xray..."
        command -v xray &>/dev/null || bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install
        sudo mkdir -p /usr/local/etc/xray
        
        if [[ "$pt" == "vless" ]]; then
            sudo tee /usr/local/etc/xray/config.json > /dev/null <<EOF
{"log":{"loglevel":"info"},"inbounds":[{"listen":"127.0.0.1","port":$port,"protocol":"vless","settings":{"clients":[{"id":"$uuid"}],"decryption":"none"},"streamSettings":{"network":"ws","wsSettings":{"path":"$path"}}}],"outbounds":[{"protocol":"freedom"}]}
EOF
        else
            sudo tee /usr/local/etc/xray/config.json > /dev/null <<EOF
{"log":{"loglevel":"info"},"inbounds":[{"listen":"127.0.0.1","port":$port,"protocol":"vmess","settings":{"clients":[{"id":"$uuid"}]},"streamSettings":{"network":"ws","wsSettings":{"path":"$path"}}}],"outbounds":[{"protocol":"freedom"}]}
EOF
        fi
        sudo systemctl restart xray && sudo systemctl enable xray
    else
        print_info "安装 Sing-box..."
        if ! command -v sing-box &>/dev/null; then
            local arch=$(uname -m)
            case "$arch" in x86_64) arch="amd64";; aarch64) arch="arm64";; *) print_err "不支持的架构"; return 1;; esac
            
            cd /tmp
            local ver=$(curl -s https://api.github.com/repos/SagerNet/sing-box/releases/latest | grep -oP '"tag_name": "\K[^"]+')
            local dl="https://github.com/SagerNet/sing-box/releases/download/${ver}/sing-box-${ver#v}-linux-${arch}.tar.gz"
            
            print_info "下载: $dl"
            curl -L -o sb.tar.gz "$dl" || {
                print_warn "尝试备用下载..."; curl -L -o sb.tar.gz "https://ghproxy.com/$dl"
            } || { print_err "下载失败"; return 1; }
            
            tar -xzf sb.tar.gz
            sudo mv sing-box-*/sing-box /usr/local/bin/
            sudo chmod +x /usr/local/bin/sing-box
            rm -rf sing-box-* sb.tar.gz
        fi
        
        sudo mkdir -p /etc/sing-box
        if [[ "$pt" == "vless" ]]; then
            sudo tee /etc/sing-box/config.json > /dev/null <<EOF
{"log":{"level":"info"},"inbounds":[{"type":"vless","listen":"127.0.0.1","listen_port":$port,"users":[{"uuid":"$uuid"}],"transport":{"type":"ws","path":"$path"}}],"outbounds":[{"type":"direct"}]}
EOF
        else
            sudo tee /etc/sing-box/config.json > /dev/null <<EOF
{"log":{"level":"info"},"inbounds":[{"type":"vmess","listen":"127.0.0.1","listen_port":$port,"users":[{"uuid":"$uuid","alterId":0}],"transport":{"type":"ws","path":"$path"}}],"outbounds":[{"type":"direct"}]}
EOF
        fi
        
        if [[ ! -f /etc/systemd/system/sing-box.service ]]; then
            sudo tee /etc/systemd/system/sing-box.service > /dev/null <<SVC
[Unit]
Description=Sing-box Service
After=network.target
[Service]
Type=simple
User=root
ExecStart=/usr/local/bin/sing-box run -c /etc/sing-box/config.json
Restart=on-failure
[Install]
WantedBy=multi-user.target
SVC
        fi
        sudo systemctl daemon-reload
        sudo systemctl restart sing-box && sudo systemctl enable sing-box
    fi
    
    cat > "$CONFIG_DIR/proxy_info.txt" <<EOF
协议=${pt}
端口=${port}
UUID=${uuid}
WebSocket 路径=${path}
EOF
    
    print_ok "安装完成"
    cat "$CONFIG_DIR/proxy_info.txt"
    
    if [[ -f "$CONFIG_DIR/tunnel_info.txt" ]]; then
        source "$CONFIG_DIR/tunnel_info.txt"
        read -rp "修改隧道服务端口为 $port? [Y/n]: " m
        if [[ ! "$m" =~ ^[Nn]$ ]]; then
            sed -i "s|service: .*|service: http://127.0.0.1:${port}|" "$CONFIG_FILE"
            print_ok "隧道配置已更新"
            pkill cloudflared 2>/dev/null || true
            nohup cloudflared tunnel --config "$CONFIG_FILE" run "$TUNNEL_ID" > /dev/null 2>&1 &
            print_ok "隧道已重启"
        fi
    fi
}

# ---------- 7. 定时任务 ----------
setup_cron() {
    read -rp "执行间隔 (小时，默认 6): " i; i=${i:-6}
    local s="$CONFIG_DIR/auto_optimize.sh"
    cat > "$s" <<'EOF'
#!/bin/bash
export PATH=/usr/local/bin:/usr/bin:/bin
EOF
    chmod +x "$s"
    (crontab -l 2>/dev/null | grep -v "$s"; echo "0 */${i} * * * $s") | crontab -
    print_ok "定时任务已设置"
}

# ---------- 8. 查看状态 ----------
show_status() {
    echo -e "\n${CYAN}========== 系统状态 ==========${NC}"
    echo -e "\n${YELLOW}[cloudflared]${NC}"
    command -v cloudflared &>/dev/null && cloudflared --version || echo "未安装"
    echo -e "\n${YELLOW}[隧道]${NC}"
    [[ -f "$CONFIG_DIR/tunnel_info.txt" ]] && cat "$CONFIG_DIR/tunnel_info.txt" || echo "未配置"
    echo -e "\n${YELLOW}[代理]${NC}"
    [[ -f "$CONFIG_DIR/proxy_info.txt" ]] && cat "$CONFIG_DIR/proxy_info.txt" || echo "未安装"
    echo -e "\n${YELLOW}[进程]${NC}"
    pgrep -f "cloudflared tunnel" > /dev/null && print_ok "隧道运行中" || print_warn "隧道未运行"
}

# ---------- 9. 生成客户端连接 ----------
generate_v2ray_link() {
    [[ ! -f "$CONFIG_DIR/proxy_info.txt" ]] && { print_err "请先安装代理内核"; return 1; }
    source "$CONFIG_DIR/proxy_info.txt"
    source "$CONFIG_DIR/tunnel_info.txt" 2>/dev/null || true
    
    local domain="${TUNNEL_DOMAIN}"
    read -rp "域名 [$domain]: " d; domain="${d:-$domain}"
    read -rp "优选 IP: " ip; [[ -z "$ip" ]] && { print_err "必填"; return 1; }
    read -rp "备注: " remark; remark="${remark:-$domain}"
    
    local epath=$(python3 -c "import urllib.parse; print(urllib.parse.quote('${WebSocket 路径}'))" 2>/dev/null || echo "${WebSocket 路径}")
    
    echo -e "\n${GREEN}========== 客户端连接 ==========${NC}"
    if [[ "${协议}" == "vless" ]]; then
        echo -e "${GREEN}VLESS 链接:${NC}"
        echo "vless://${UUID}@${ip}:${端口}?encryption=none&security=tls&sni=${domain}&type=ws&host=${domain}&path=${epath}#${remark}"
    else
        local json='{"v":"2","ps":"'${remark}'","add":"'${ip}'","port":"'${端口}'","id":"'${UUID}'","aid":"0","net":"ws","type":"none","host":"'${domain}'","path":"'${WebSocket 路径}'","tls":"tls"}'
        echo -e "${GREEN}VMess 链接:${NC}"
        echo "vmess://$(echo -n "$json" | base64 -w 0)"
    fi
    
    echo -e "\n${YELLOW}参数: 地址=$ip 端口=$端口 UUID=$UUID SNI=$domain${NC}"
    
    read -rp "写入 hosts? [y/N]: " h; [[ "$h" =~ ^[Yy]$ ]] && write_hosts_file "$ip" "$domain"
}

# ---------- 主菜单 ----------
show_menu() {
    echo -e "\n${CYAN}1.安装cloudflared 2.Argo隧道 3.DNS更新 4.hosts写入${NC}"
    echo -e "${CYAN}5.CNAME优选 6.代理内核 7.定时 8.状态 9.生成链接 0.退出${NC}"
}

main() {
    ensure_dirs
    print_banner
    while true; do
        show_menu
        read -rp "选择 [0-9]: " c
        case $c in
            1) install_cloudflared;; 2) setup_argo_tunnel;; 3) update_cloudflare_dns;;
            4) write_hosts_file;; 5) setup_argo_cname;; 6) install_proxy_core;;
            7) setup_cron;; 8) show_status;; 9) generate_v2ray_link;;
            0) print_ok "再见!"; exit 0;;
            *) print_err "无效选择";;
        esac
        read -rp "按回车继续..."
    done
}
main "$@"
CFMANAGER_EOF

    sudo chmod +x "$install_path"
    print_ok "cf-manager 安装完成"
}

# ---------- 创建快捷命令别名 ----------
setup_alias() {
    if ! grep -q "alias cf-manager=" "$HOME/.bashrc" 2>/dev/null; then
        echo "alias cf-manager='/usr/local/bin/cf-manager'" >> "$HOME/.bashrc"
        print_info "已添加别名到 ~/.bashrc"
    fi
    if [[ -f "$HOME/.zshrc" ]] && ! grep -q "alias cf-manager=" "$HOME/.zshrc" 2>/dev/null; then
        echo "alias cf-manager='/usr/local/bin/cf-manager'" >> "$HOME/.zshrc"
    fi
}

# ---------- 创建配置目录 ----------
init_config() {
    mkdir -p "$HOME/.cloudflare-config/logs"
    print_ok "配置目录已创建"
}

# ---------- 显示完成信息 ----------
show_complete() {
    echo ""
    echo -e "${GREEN}============================================${NC}"
    echo -e "${GREEN}  安装完成！${NC}"
    echo -e "${GREEN}============================================${NC}"
    echo -e "  运行管理工具: ${CYAN}cf-manager${NC}"
    echo -e ""
    echo -e "  快速开始:"
    echo -e "    1. ${CYAN}cf-manager${NC}  → 选择 2 配置 Argo 隧道"
    echo -e "    2. ${CYAN}cf-manager${NC}  → 选择 6 安装代理内核"
    echo -e "    3. ${CYAN}cf-manager${NC}  → 选择 9 生成客户端连接"
    echo -e ""
    echo -e "  如果命令未找到，请执行: ${CYAN}source ~/.bashrc${NC}"
    echo -e "${GREEN}============================================${NC}"
}

# ---------- 主流程 ----------
main() {
    clear
    echo -e "${CYAN}"
    echo "╔════════════════════════════════════════════════════════════╗"
    echo "║   Cloudflared + Argo 隧道 + 代理内核 一键安装脚本 v2.0      ║"
    echo "╚════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
    
    check_root
    install_deps
    install_cloudflared
    install_cf_manager
    setup_alias
    init_config
    show_complete
}

main "$@"
