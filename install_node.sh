#!/bin/bash

# Telegram MTProto代理节点一键安装脚本
# 此脚本用于自动安装和配置MTProto代理服务器，或者仅配置状态上报

# 彩色输出
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m' # 无颜色

# 卸载上报脚本函数
uninstall_report_script() {
    echo -e "${BLUE}=========================================${NC}"
    echo -e "${GREEN}卸载状态上报脚本${NC}"
    echo -e "${BLUE}=========================================${NC}\n"
    
    # 移除定时任务
    echo -e "${GREEN}正在移除定时任务...${NC}"
    (crontab -l 2>/dev/null | grep -v "report_status.sh") | crontab -
    
    # 停止并移除脚本
    echo -e "${GREEN}正在移除上报脚本...${NC}"
    if [ -f "/usr/local/bin/report_status.sh" ]; then
        rm -f /usr/local/bin/report_status.sh
        echo -e "上报脚本已移除"
    else
        echo -e "${YELLOW}未找到上报脚本${NC}"
    fi
    
    # 询问是否保留日志
    read -p "是否保留状态上报日志? (y/n) [n]: " KEEP_LOG
    if [[ "$KEEP_LOG" != "y" && "$KEEP_LOG" != "Y" ]]; then
        if [ -f "/var/log/mtproto_report.log" ]; then
            rm -f /var/log/mtproto_report.log
            echo -e "状态上报日志已移除"
        else
            echo -e "${YELLOW}未找到状态上报日志${NC}"
        fi
    else
        echo -e "状态上报日志已保留在 /var/log/mtproto_report.log"
    fi
    
    echo -e "\n${GREEN}卸载完成！状态上报脚本和相关定时任务已移除。${NC}"
    echo -e "${YELLOW}注意：此操作不会卸载MTProto代理本身，仅移除状态上报功能。${NC}"
    exit 0
}

# 打印欢迎信息
echo -e "${BLUE}=========================================${NC}"
echo -e "${GREEN}Telegram MTProto代理节点配置脚本${NC}"
echo -e "${BLUE}=========================================${NC}\n"

# 询问是否已经安装MTProto代理
echo -e "请选择操作:"
echo -e "1) 全新安装MTProto代理和状态上报脚本"
echo -e "2) 仅安装状态上报脚本（已有MTProto代理）"
echo -e "3) 卸载状态上报脚本"
read -p "请选择 [1/2/3]: " INSTALL_TYPE
if [ "$INSTALL_TYPE" = "3" ]; then
    uninstall_report_script
fi

if [ "$INSTALL_TYPE" != "1" ] && [ "$INSTALL_TYPE" != "2" ]; then
    echo -e "${RED}无效的选择，默认选择1${NC}"
    INSTALL_TYPE="1"
fi

# 自动检测MTProto代理信息
detect_mtproto() {
    echo -e "${GREEN}正在尝试自动检测MTProto代理信息...${NC}"
    
    # 检测是否使用Docker运行
    if command -v docker &> /dev/null && docker ps | grep -q "mtproto"; then
        echo -e "${GREEN}检测到Docker运行的MTProto代理${NC}"
        USE_DOCKER="y"
        
        # 尝试获取容器名称
        CONTAINER_NAME=$(docker ps | grep mtproto | head -n 1 | awk '{print $NF}')
        if [ -z "$CONTAINER_NAME" ]; then
            CONTAINER_NAME="mtproto-proxy"
        else
            echo -e "检测到容器名称: ${YELLOW}$CONTAINER_NAME${NC}"
        fi
        
        # 尝试获取端口信息
        PORT_INFO=$(docker port "$CONTAINER_NAME" | grep -oP '\d+$' | head -n 1)
        if [ -n "$PORT_INFO" ]; then
            PORT=$PORT_INFO
            echo -e "检测到端口: ${YELLOW}$PORT${NC}"
        fi
        
        # 尝试获取密钥
        DOCKER_ENV=$(docker inspect "$CONTAINER_NAME" | grep -oP '(?<="SECRET=)[^"]+')
        if [ -n "$DOCKER_ENV" ]; then
            SECRET=$DOCKER_ENV
            echo -e "检测到密钥: ${YELLOW}$SECRET${NC}"
        fi
        
        # 设置默认stats端口
        STATS_PORT="2398"
        return 0
    fi
    
    # 检测直接进程运行的MTProto代理
    if ps -ef | grep -q "[m]tproto-proxy"; then
        echo -e "${GREEN}检测到直接进程运行的MTProto代理${NC}"
        USE_DOCKER="n"
        
        # 获取进程命令行
        PROCESS_CMD=$(ps -ef | grep "[m]tproto-proxy" | head -n 1)
        echo -e "检测到进程: ${YELLOW}$(echo $PROCESS_CMD | awk '{print $8" "$9" ..."}')${NC}"
        
        # 尝试提取端口 (-H 参数)
        PORT=$(echo "$PROCESS_CMD" | grep -oP -- "-H\s+\K\d+")
        if [ -n "$PORT" ]; then
            echo -e "检测到端口: ${YELLOW}$PORT${NC}"
        else
            # 尝试提取端口 (-p 参数)
            PORT=$(echo "$PROCESS_CMD" | grep -oP -- "-p\s+\K\d+")
            if [ -n "$PORT" ]; then
                echo -e "检测到端口: ${YELLOW}$PORT${NC}"
            fi
        fi
        
        # 尝试提取密钥 (-S 参数)
        SECRET=$(echo "$PROCESS_CMD" | grep -oP -- "-S\s+\K[a-zA-Z0-9]+")
        if [ -n "$SECRET" ]; then
            echo -e "检测到基本密钥: ${YELLOW}$SECRET${NC}"
            
            # 提取域名参数，可能用于构建完整密钥
            DOMAIN=$(echo "$PROCESS_CMD" | grep -oP -- "--domain\s+\K[a-zA-Z0-9.-]+")
            if [ -n "$DOMAIN" ]; then
                echo -e "检测到伪装域名: ${YELLOW}$DOMAIN${NC}"
                
                # 检查是否需要在密钥前添加'ee'
                if [[ "$SECRET" != ee* ]]; then
                    SECRET_START="ee"
                else
                    SECRET_START=""
                fi
                
                # 将域名转换为十六进制并附加到密钥
                if command -v xxd &> /dev/null; then
                    DOMAIN_HEX=$(echo -n "$DOMAIN" | xxd -p | tr -d '\n')
                    FULL_SECRET="${SECRET_START}${SECRET}${DOMAIN_HEX}"
                    echo -e "构建完整密钥: ${YELLOW}$FULL_SECRET${NC}"
                    SECRET=$FULL_SECRET
                fi
            fi
        else
            # 尝试从文件或环境中提取密钥
            for CONFIG_FILE in /etc/mtproto-proxy.conf /etc/mtproxy.conf $(find /etc -name "*mtpro*" -type f 2>/dev/null); do
                if [ -f "$CONFIG_FILE" ]; then
                    FILE_SECRET=$(grep -oP '(?<=SECRET=|secret=)[a-zA-Z0-9]+' "$CONFIG_FILE")
                    if [ -n "$FILE_SECRET" ]; then
                        SECRET=$FILE_SECRET
                        echo -e "从配置文件提取密钥: ${YELLOW}$SECRET${NC}"
                        break
                    fi
                fi
            done
        fi
        
        # 设置状态获取命令
        STATUS_CMD="netstat -tuln | grep -c :$PORT || ss -tuln | grep -c :$PORT"
        BANDWIDTH_CMD="echo 0"
        
        return 0
    fi
    
    # 检测systemd服务
    if systemctl list-units --type=service | grep -q "mtproto"; then
        echo -e "${GREEN}检测到系统服务运行的MTProto代理${NC}"
        USE_DOCKER="n"
        
        # 获取服务名称
        SERVICE_NAME=$(systemctl list-units --type=service | grep mtproto | head -n 1 | awk '{print $1}')
        echo -e "检测到服务: ${YELLOW}$SERVICE_NAME${NC}"
        
        # 尝试从配置文件获取端口和密钥
        if [ -f "/etc/mtproto-proxy.conf" ]; then
            PORT=$(grep -oP '(?<=PORT=)\d+' /etc/mtproto-proxy.conf)
            SECRET=$(grep -oP '(?<=SECRET=)[a-zA-Z0-9]+' /etc/mtproto-proxy.conf)
            
            if [ -n "$PORT" ]; then
                echo -e "检测到端口: ${YELLOW}$PORT${NC}"
            fi
            
            if [ -n "$SECRET" ]; then
                echo -e "检测到密钥: ${YELLOW}$SECRET${NC}"
            fi
        fi
        
        # 设置状态获取命令
        STATUS_CMD="netstat -tuln | grep -c :$PORT || ss -tuln | grep -c :$PORT"
        BANDWIDTH_CMD="echo 0"
        
        return 0
    fi
    
    # 如果找不到MTProto代理
    echo -e "${YELLOW}未能自动检测到MTProto代理信息，请手动输入${NC}"
    return 1
}

# 自动获取系统信息
HOST=$(curl -s ifconfig.me)
PORT=443
SECRET=$(head -c 16 /dev/urandom | xxd -ps)

# 交互式询问必要信息
echo -e "请输入以下信息（如不确定，请咨询您的机器人管理员）\n"

# 节点名称
read -p "节点名称 [默认节点]: " NAME
NAME=${NAME:-"默认节点"}

# API密钥
read -p "API密钥 (必填): " API_KEY
while [ -z "$API_KEY" ]; do
    echo -e "${RED}API密钥不能为空!${NC}"
    read -p "API密钥 (必填): " API_KEY
done

# Bot API地址
read -p "Bot API地址 (例如 http://your-bot-domain:8080/api/report): " API_URL
while [ -z "$API_URL" ]; do
    echo -e "${RED}Bot API地址不能为空!${NC}"
    read -p "Bot API地址 (例如 http://your-bot-domain:8080/api/report): " API_URL
done

# 节点ID
read -p "节点ID [0]: " NODE_ID
NODE_ID=${NODE_ID:-0}

# 如果是仅安装上报脚本，需要手动输入MTProto配置
if [ "$INSTALL_TYPE" = "2" ]; then
    echo -e "\n请输入您现有MTProto代理的信息:"
    
    # 尝试自动检测MTProto信息
    detect_mtproto
    
    # 如果未提供PORT或SECRET，则请求用户输入
    if [ -z "$PORT" ]; then
        read -p "MTProto端口 [443]: " PORT
        PORT=${PORT:-443}
    else
        echo -e "使用检测到的端口: ${YELLOW}$PORT${NC}"
        read -p "是否使用此端口? (y/n) [y]: " USE_DETECTED_PORT
        if [[ "$USE_DETECTED_PORT" != "y" && "$USE_DETECTED_PORT" != "Y" && "$USE_DETECTED_PORT" != "" ]]; then
            read -p "MTProto端口: " PORT
            PORT=${PORT:-443}
        fi
    fi
    
    if [ -z "$SECRET" ]; then
        read -p "MTProto密钥 (必填): " SECRET
        while [ -z "$SECRET" ]; do
            echo -e "${RED}密钥不能为空!${NC}"
            read -p "MTProto密钥 (必填): " SECRET
        done
    else
        echo -e "使用检测到的密钥: ${YELLOW}$SECRET${NC}"
        read -p "是否使用此密钥? (y/n) [y]: " USE_DETECTED_SECRET
        if [[ "$USE_DETECTED_SECRET" != "y" && "$USE_DETECTED_SECRET" != "Y" && "$USE_DETECTED_SECRET" != "" ]]; then
            read -p "MTProto密钥: " SECRET
            while [ -z "$SECRET" ]; do
                echo -e "${RED}密钥不能为空!${NC}"
                read -p "MTProto密钥: " SECRET
            done
        fi
    fi
    
    # 询问Docker和Stats端口
    if [ -z "$USE_DOCKER" ]; then
        read -p "是否使用Docker运行MTProto代理? (y/n) [y]: " USE_DOCKER
        USE_DOCKER=${USE_DOCKER:-y}
    fi
    
    if [[ "$USE_DOCKER" == "y" || "$USE_DOCKER" == "Y" ]]; then
        if [ -z "$CONTAINER_NAME" ]; then
            read -p "Docker容器名称 [mtproto-proxy]: " CONTAINER_NAME
            CONTAINER_NAME=${CONTAINER_NAME:-mtproto-proxy}
        fi
        
        if [ -z "$STATS_PORT" ]; then
            read -p "Stats端口 [2398]: " STATS_PORT
            STATS_PORT=${STATS_PORT:-2398}
        fi
    else
        if [ -z "$STATUS_CMD" ]; then
            read -p "MTProto代理状态命令 (能够获取连接数的命令): " STATUS_CMD
            if [ -z "$STATUS_CMD" ]; then
                echo -e "${YELLOW}未提供状态命令，将使用简单的端口检测。${NC}"
                STATUS_CMD="ss -tuln | grep -c :$PORT"
            fi
        fi
        
        if [ -z "$BANDWIDTH_CMD" ]; then
            read -p "MTProto代理带宽命令 (能够获取带宽的命令): " BANDWIDTH_CMD
            if [ -z "$BANDWIDTH_CMD" ]; then
                echo -e "${YELLOW}未提供带宽命令，将无法获取准确的带宽使用量。${NC}"
                BANDWIDTH_CMD="echo 0"
            fi
        fi
    fi
fi

# 上报频率(分钟)
read -p "状态上报频率(分钟) [1]: " REPORT_INTERVAL
REPORT_INTERVAL=${REPORT_INTERVAL:-1}

echo -e "\n${BLUE}=========================================${NC}"
if [ "$INSTALL_TYPE" = "1" ]; then
    echo -e "${GREEN}即将安装MTProto代理节点和状态上报，配置如下：${NC}"
else
    echo -e "${GREEN}即将安装状态上报脚本，配置如下：${NC}"
fi
echo -e "${BLUE}=========================================${NC}"
echo -e "节点名称: ${YELLOW}$NAME${NC}"
echo -e "主机地址: ${YELLOW}$HOST${NC}"
echo -e "端口: ${YELLOW}$PORT${NC}"
echo -e "密钥: ${YELLOW}$SECRET${NC}"
echo -e "节点ID: ${YELLOW}$NODE_ID${NC}"
echo -e "状态上报频率: ${YELLOW}每${REPORT_INTERVAL}分钟${NC}"
echo -e "${BLUE}=========================================${NC}\n"

# 确认安装
read -p "确认安装? (y/n): " CONFIRM
if [[ "$CONFIRM" != "y" && "$CONFIRM" != "Y" ]]; then
    echo -e "${RED}安装已取消${NC}"
    exit 1
fi

# 安装依赖
echo -e "\n${GREEN}正在安装依赖...${NC}"
apt-get update
apt-get install -y curl wget

# 如果选择全新安装，则安装Docker和MTProto代理
if [ "$INSTALL_TYPE" = "1" ]; then
    apt-get install -y build-essential git
    
    # 安装Docker（如果尚未安装）
    if ! command -v docker &> /dev/null; then
        echo -e "\n${GREEN}正在安装Docker...${NC}"
        curl -fsSL https://get.docker.com -o get-docker.sh
        sh get-docker.sh
        systemctl enable docker
        systemctl start docker
    fi

    # 拉取MTProto代理镜像
    echo -e "\n${GREEN}正在拉取MTProto代理镜像...${NC}"
    docker pull telegrammessenger/proxy:latest

    # 停止并移除旧容器（如果存在）
    docker stop mtproto-proxy &>/dev/null || true
    docker rm mtproto-proxy &>/dev/null || true

    # 启动MTProto代理容器
    echo -e "\n${GREEN}正在启动MTProto代理...${NC}"
    docker run -d --name mtproto-proxy --restart always -p $PORT:443 \
        -e SECRET=$SECRET \
        -e TAG=dcfd5cbcf7f916c0 \
        telegrammessenger/proxy:latest
        
    # 设置Docker相关变量，用于上报脚本
    USE_DOCKER="y"
    CONTAINER_NAME="mtproto-proxy"
    STATS_PORT="2398"
fi

# 创建上报脚本
echo -e "\n${GREEN}正在创建状态上报脚本...${NC}"

if [[ "$USE_DOCKER" == "y" || "$USE_DOCKER" == "Y" ]]; then
    # Docker版本的上报脚本
    cat > /usr/local/bin/report_status.sh << EOF
#!/bin/bash

# 获取连接数
CONN_COUNT=\$(docker exec $CONTAINER_NAME curl -s http://localhost:$STATS_PORT/stats | grep -oP '(?<="active_users":)[0-9]+')
if [ -z "\$CONN_COUNT" ]; then
    CONN_COUNT=0
fi

# 获取带宽使用量（字节）
BANDWIDTH=\$(docker exec $CONTAINER_NAME curl -s http://localhost:$STATS_PORT/stats | grep -oP '(?<="bytes":)[0-9]+')
if [ -z "\$BANDWIDTH" ]; then
    BANDWIDTH=0
fi

# 当前时间
TIMESTAMP=\$(date +"%Y-%m-%d %H:%M:%S")

# 记录日志
echo "[\$TIMESTAMP] 连接数: \$CONN_COUNT, 带宽: \$BANDWIDTH bytes" >> /var/log/mtproto_report.log

# 发送状态报告
curl -s -X POST $API_URL \\
  -H "Content-Type: application/json" \\
  -d '{
    "node_id": $NODE_ID,
    "conn_count": '\$CONN_COUNT',
    "bandwidth": '\$BANDWIDTH',
    "api_key": "$API_KEY",
    "node_name": "$NAME",
    "host": "$HOST",
    "port": $PORT,
    "secret": "$SECRET",
    "user_data": []
  }' > /dev/null
EOF
else
    # 非Docker版本的上报脚本
    cat > /usr/local/bin/report_status.sh << EOF
#!/bin/bash

# 获取连接数
CONN_COUNT=\$($STATUS_CMD)
if [ -z "\$CONN_COUNT" ]; then
    CONN_COUNT=0
fi

# 获取带宽使用量（字节）
# 尝试使用多种方法获取带宽信息
if [ -f "/var/log/mtproto_bandwidth.log" ]; then
    # 如果存在带宽日志文件，读取上次记录的值
    LAST_BANDWIDTH=\$(cat /var/log/mtproto_bandwidth.log 2>/dev/null || echo "0")
else
    LAST_BANDWIDTH="0"
fi

# 尝试从网络接口获取带宽信息
INTERFACE=\$(ip route | grep default | awk '{print \$5}')
if [ -n "\$INTERFACE" ]; then
    # 获取当前网络接口的接收和发送字节数
    RX_BYTES=\$(cat /sys/class/net/\$INTERFACE/statistics/rx_bytes 2>/dev/null || echo "0")
    TX_BYTES=\$(cat /sys/class/net/\$INTERFACE/statistics/tx_bytes 2>/dev/null || echo "0")
    
    # 计算总带宽
    CURRENT_BANDWIDTH=\$((RX_BYTES + TX_BYTES))
    
    # 如果是首次运行，使用当前值
    if [ "\$LAST_BANDWIDTH" = "0" ]; then
        BANDWIDTH=0
    else
        # 计算增量
        BANDWIDTH=\$((CURRENT_BANDWIDTH - LAST_BANDWIDTH))
        # 如果是负数（可能是由于系统重启），则使用当前值
        if [ \$BANDWIDTH -lt 0 ]; then
            BANDWIDTH=\$CURRENT_BANDWIDTH
        fi
    fi
    
    # 保存当前值供下次使用
    echo \$CURRENT_BANDWIDTH > /var/log/mtproto_bandwidth.log
else
    # 如果无法获取网络接口，使用备用方法
    BANDWIDTH=\$($BANDWIDTH_CMD)
    if [ -z "\$BANDWIDTH" ]; then
        BANDWIDTH=0
    fi
fi

# 当前时间
TIMESTAMP=\$(date +"%Y-%m-%d %H:%M:%S")

# 记录日志
echo "[\$TIMESTAMP] 连接数: \$CONN_COUNT, 带宽: \$BANDWIDTH bytes" >> /var/log/mtproto_report.log

# 发送状态报告
curl -s -X POST $API_URL \\
  -H "Content-Type: application/json" \\
  -d '{
    "node_id": $NODE_ID,
    "conn_count": '\$CONN_COUNT',
    "bandwidth": '\$BANDWIDTH',
    "api_key": "$API_KEY",
    "node_name": "$NAME",
    "host": "$HOST",
    "port": $PORT,
    "secret": "$SECRET",
    "user_data": []
  }' > /dev/null
EOF
fi

chmod +x /usr/local/bin/report_status.sh

# 创建日志文件
touch /var/log/mtproto_report.log
chmod 666 /var/log/mtproto_report.log

# 创建定时任务
echo -e "\n${GREEN}正在设置定时任务...${NC}"
CRON_EXPR="*/$REPORT_INTERVAL * * * *"
(crontab -l 2>/dev/null | grep -v "report_status.sh"; echo "$CRON_EXPR /usr/local/bin/report_status.sh") | crontab -

# 生成Telegram代理链接
PROXY_URL="tg://proxy?server=$HOST&port=$PORT&secret=$SECRET"

echo -e "\n${BLUE}=========================================${NC}"
echo -e "${GREEN}安装完成！${NC}"
echo -e "${BLUE}=========================================${NC}"
if [ "$INSTALL_TYPE" = "1" ]; then
    echo -e "MTProto代理已启动，配置如下："
else
    echo -e "状态上报脚本已安装，配置如下："
fi
echo -e "服务器: ${YELLOW}$HOST${NC}"
echo -e "端口: ${YELLOW}$PORT${NC}"
echo -e "密钥: ${YELLOW}$SECRET${NC}"
echo -e "${GREEN}Telegram链接:${NC} ${YELLOW}$PROXY_URL${NC}"
echo -e "状态将每${YELLOW}${REPORT_INTERVAL}${NC}分钟上报一次"
echo -e "状态日志位置: ${YELLOW}/var/log/mtproto_report.log${NC}"
echo -e "${BLUE}=========================================${NC}"
echo -e "复制下面的链接到Telegram中即可使用代理:"
echo -e "${YELLOW}$PROXY_URL${NC}\n"

# 测试上报脚本
echo -e "${GREEN}正在测试状态上报脚本...${NC}"
/usr/local/bin/report_status.sh
echo -e "${GREEN}上报脚本已运行，请检查/var/log/mtproto_report.log文件查看详情${NC}"

# 测试连接
echo -e "${GREEN}正在测试与Bot API的连接...${NC}"
TEST_RESULT=$(curl -s -X POST "$API_URL" \
  -H "Content-Type: application/json" \
  -d "{
    \"node_id\": $NODE_ID,
    \"conn_count\": 0,
    \"bandwidth\": 0,
    \"api_key\": \"$API_KEY\",
    \"user_data\": []
  }")

if [[ "$TEST_RESULT" == *"success"* ]]; then
    echo -e "${GREEN}连接测试成功! 节点可以正常向Bot上报状态。${NC}"
else
    echo -e "${RED}连接测试失败! 请检查API密钥和Bot API地址是否正确。${NC}"
    echo -e "错误信息: $TEST_RESULT"
fi 
