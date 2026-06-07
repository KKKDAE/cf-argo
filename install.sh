#!/bin/bash
# ============================================================
# Cloudflared + Argo 隧道 + 优选 IP + 代理内核 一键安装脚本
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
SCRIPT_NAME="cf-complete"
REPO_URL="https://github.com/KKKDAE/cf-argo"
SCRIPT_DIR="/opt/cf-argo"
CONFIG_DIR="${SCRIPT_DIR}/.cloudflare-config"
LOG_DIR="${CONFIG_DIR}/logs"

# ---------- 工具函数 ----------
print_banner() {
    echo -e "${CYAN}"
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║  Cloudflared + Argo 隧道 + 优选 IP + 代理内核 一键安装器      ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

print_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
print_ok()   { echo -e "${GREEN}[OK]${NC} $1"; }
print_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
print_err()  { echo -e "${RED}[ERR]${NC} $1"; exit 1; }

require_cmd() {
    if ! command -v "$1" &>/dev/null; then
        print_err "缺少命令: $1，请先安装"
    fi
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_err "此脚本需要 root 权限运行"
    fi
}

# ---------- 检查系统依赖 ----------
check_dependencies() {
    echo -e "\n${CYAN}========== 检查系统依赖 ==========${NC}"
    local missing_deps=()
    
    local required_cmds=("curl" "wget" "git" "ping" "sed" "awk" "sort")
    for cmd in "${required_cmds[@]}"; do
        if ! command -v "$cmd" &>/dev/null; then
            missing_deps+=("$cmd")
        else
            print_ok "已安装: $cmd"
        fi
    done

    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        print_warn "检测到缺失的依赖: ${missing_deps[*]}"
        print_info "正在尝试自动安装..."
        
        if command -v apt-get &>/dev/null; then
            apt-get update -qq
            apt-get install -y -qq "${missing_deps[@]}" || print_err "apt-get 安装失败"
        elif command -v yum &>/dev/null; then
            yum install -y -q "${missing_deps[@]}" || print_err "yum 安装失败"
        elif command -v apk &>/dev/null; then
            apk add --no-cache -q "${missing_deps[@]}" || print_err "apk 安装失败"
        else
            print_err "无法自动安装依赖，请手动安装: ${missing_deps[*]}"
        fi
    fi
    print_ok "依赖检查完成"
}

# ---------- 下载主脚本 ----------
download_main_script() {
    echo -e "\n${CYAN}========== 下载主脚本 ==========${NC}"
    mkdir -p "$SCRIPT_DIR"
    mkdir -p "$CONFIG_DIR"
    mkdir -p "$LOG_DIR"

    local script_url="${REPO_URL}/raw/main/${SCRIPT_NAME}"
    print_info "正在从 $script_url 下载..."
    
    if ! curl -fsSL -o "${SCRIPT_DIR}/${SCRIPT_NAME}" "$script_url"; then
        print_err "下载主脚本失败"
    fi
    
    chmod +x "${SCRIPT_DIR}/${SCRIPT_NAME}"
    print_ok "主脚本下载完成"
}

# ---------- 安装 cloudflared ----------
install_cloudflared_binary() {
    echo -e "\n${CYAN}========== 安装 cloudflared ==========${NC}"
    if command -v cloudflared &>/dev/null; then
        local ver=$(cloudflared --version 2>/dev/null | head -1)
        print_ok "cloudflared 已安装: $ver"
        return 0
    fi

    local arch=$(uname -m)
    local os=$(uname -s | tr '[:upper:]' '[:lower:]')
    local download_url=""

    case "$arch" in
        x86_64|amd64)  arch="amd64" ;;
        aarch64|arm64) arch="arm64" ;;
        armv7l|armv7)  arch="arm" ;;
        i386|i686)     arch="386" ;;
        *) print_err "不支持的架构: $arch" ;;
    esac

    case "$os" in
        linux)   download_url="https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-${arch}" ;;
        darwin)  download_url="https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-darwin-${arch}" ;;
        *) print_err "不支持的操作系统: $os" ;;
    esac

    print_info "正在下载: $download_url"
    local tmpfile=$(mktemp)
    
    if ! curl -fsSL -o "$tmpfile" "$download_url"; then
        rm -f "$tmpfile"
        print_err "下载 cloudflared 失败"
    fi

    chmod +x "$tmpfile"
    mv "$tmpfile" /usr/local/bin/cloudflared
    print_ok "cloudflared 安装完成"
    cloudflared --version
}

# ---------- 创建快捷命令 ----------
create_alias() {
    echo -e "\n${CYAN}========== 创建快捷命令 ==========${NC}"
    
    # 创建全局可执行脚本
    cat > /usr/local/bin/cf-complete <<EOF
#!/bin/bash
exec bash "${SCRIPT_DIR}/${SCRIPT_NAME}" "\$@"
EOF
    chmod +x /usr/local/bin/cf-complete
    
    # 创建 systemd 服务脚本
    mkdir -p /etc/systemd/system
    cat > /etc/systemd/system/cf-complete.service.d.template <<EOF
[Unit]
Description=Cloudflared Argo Tunnel
After=network.target

[Service]
Type=simple
User=root
ExecStart=${SCRIPT_DIR}/${SCRIPT_NAME} --daemon
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF
    
    print_ok "快捷命令已创建"
    print_info "使用方法:"
    print_info "  cf-complete          # 进入交互式菜单"
    print_info "  cf-complete 1        # 安装 cloudflared"
    print_info "  cf-complete 3        # 运行优选 IP 测速"
}

# ---------- 创建配置目录 ----------
init_config_dirs() {
    echo -e "\n${CYAN}========== 初始化配置目录 ==========${NC}"
    mkdir -p "$CONFIG_DIR" "$LOG_DIR"
    chmod 700 "$CONFIG_DIR"
    print_ok "配置目录已创建: $CONFIG_DIR"
    print_ok "日志目录已创建: $LOG_DIR"
}

# ---------- 验证安装 ----------
verify_installation() {
    echo -e "\n${CYAN}========== 验证安装 ==========${NC}"
    local success=true

    if [[ -f "${SCRIPT_DIR}/${SCRIPT_NAME}" ]]; then
        print_ok "主脚本已安装"
    else
        print_warn "主脚本未找到"
        success=false
    fi

    if command -v cf-complete &>/dev/null; then
        print_ok "快捷命令已可用"
    else
        print_warn "快捷命令未找到"
        success=false
    fi

    if command -v cloudflared &>/dev/null; then
        print_ok "cloudflared 已安装"
    else
        print_warn "cloudflared 未安装 (可稍后通过 cf-complete 1 安装)"
    fi

    if [[ "$success" == "true" ]]; then
        print_ok "安装验证成功!"
        return 0
    else
        print_warn "某些组件未正确安装，但基本框架已就位"
        return 1
    fi
}

# ---------- 显示使用说明 ----------
show_usage() {
    echo -e "\n${CYAN}========== 安装完成 ==========${NC}"
    echo -e "\n${GREEN}主要功能：${NC}"
    echo "  1. 安装/更新 cloudflared"
    echo "  2. 配置 Argo 隧道"
    echo "  3. Cloudflare 优选 IP 测速"
    echo "  4. DNS A 记录自动更新"
    echo "  5. 本地 hosts 绑定"
    echo "  6. Argo 隧道 + CNAME 优选路由"
    echo "  7. 代理内核集成 (Xray/Sing-box)"
    echo "  8. 定时自动优选"
    echo "  9. 系统状态查看"
    
    echo -e "\n${GREEN}快速开始：${NC}"
    echo -e "  ${CYAN}cf-complete${NC}         # 进入交互式菜单"
    echo -e "  ${CYAN}cf-complete 3${NC}       # 直接运行优选 IP 测速"
    echo -e "  ${CYAN}cf-complete 9${NC}       # 查看系统状态"
    
    echo -e "\n${GREEN}配置文件位置：${NC}"
    echo "  $CONFIG_DIR"
    
    echo -e "\n${GREEN}日志位置：${NC}"
    echo "  $LOG_DIR"
    
    echo -e "\n${GREEN}帮助：${NC}"
    echo -e "  访问: ${REPO_URL}"
    echo -e "  文档: ${REPO_URL}/wiki"
    
    echo -e "\n"
}

# ---------- 清理并安装 ----------
uninstall() {
    echo -e "\n${CYAN}========== 卸载 ==========${NC}"
    read -rp "确定要卸载吗? [y/N]: " confirm
    [[ "$confirm" =~ ^[Yy]$ ]] || return 0
    
    rm -f /usr/local/bin/cf-complete
    rm -rf "$SCRIPT_DIR"
    print_ok "卸载完成"
}

# ---------- 主安装流程 ----------
main() {
    print_banner
    
    case "${1:-}" in
        uninstall)
            uninstall
            exit 0
            ;;
    esac
    
    check_root
    check_dependencies
    init_config_dirs
    download_main_script
    install_cloudflared_binary
    create_alias
    verify_installation
    show_usage
}

main "$@"
