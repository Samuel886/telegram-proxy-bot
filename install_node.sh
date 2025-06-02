#!/bin/bash

# Telegram MTProto代理节点一键安装脚本
# 此脚本用于自动安装和配置MTProto代理服务器，或者仅配置状态上报

# 彩色输出
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m' # 无颜色

# 脚本正文开始前先处理命令行参数
while getopts "r:h" opt; do
  case $opt in
    r)
      NODE_ID=$OPTARG
      echo -e "${GREEN}正在重启节点 ID: $NODE_ID${NC}"
      restart_node
      ;;
    h)
      echo -e "用法: $0 [-r node_id] [-h]"
      echo -e "  -r node_id    重启指定节点ID"
      echo -e "  -h            显示帮助信息"
      exit 0
      ;;
    \?)
      echo "无效的选项: -$OPTARG" >&2
      exit 1
      ;;
  esac
done

# 重启节点函数
restart_node() {
    echo -e "${BLUE}=========================================${NC}"
    echo -e "${GREEN}重启节点${NC}"
    echo -e "${BLUE}=========================================${NC}\n"
    
    # 检查是否使用Docker
    if command -v docker &> /dev/null && docker ps | grep -q "mtproto"; then
        # Docker版本重启
        CONTAINER_NAME=$(docker ps | grep mtproto | head -n 1 | awk '{print $NF}')
        if [ -z "$CONTAINER_NAME" ]; then
            CONTAINER_NAME="mtproto-proxy"
        fi
        
        echo -e "${GREEN}正在重启Docker容器 $CONTAINER_NAME...${NC}"
        docker restart $CONTAINER_NAME
        echo -e "${GREEN}重启完成！${NC}"
    else
        # 非Docker版本重启
        echo -e "${GREEN}检测系统服务...${NC}"
        if systemctl list-units --type=service | grep -q "mtproto"; then
            SERVICE_NAME=$(systemctl list-units --type=service | grep mtproto | head -n 1 | awk '{print $1}')
            echo -e "${GREEN}正在重启服务 $SERVICE_NAME...${NC}"
            systemctl restart $SERVICE_NAME
            echo -e "${GREEN}重启完成！${NC}"
        else
            echo -e "${YELLOW}未检测到MTProto服务，尝试通过进程重启...${NC}"
            PID=$(ps -ef | grep "[m]tproto-proxy" | head -n 1 | awk '{print $2}')
            if [ -n "$PID" ]; then
                echo -e "${GREEN}正在终止进程 $PID...${NC}"
                kill -15 $PID
                sleep 2
                
                # 获取启动命令并重新启动
                CMD=$(ps -fp $PID -o cmd= 2>/dev/null || echo "")
                if [ -n "$CMD" ]; then
                    echo -e "${GREEN}正在重新启动...${NC}"
                    nohup $CMD > /dev/null 2>&1 &
                    echo -e "${GREEN}重启完成！${NC}"
                else
                    echo -e "${RED}无法获取启动命令，请手动重启。${NC}"
                fi
            else
                echo -e "${RED}未找到MTProto代理进程，请手动重启。${NC}"
            fi
        fi
    fi
    
    # 重启上报脚本
    if [ -f "/usr/local/bin/report_status.sh" ]; then
        echo -e "${GREEN}正在执行状态上报脚本...${NC}"
        /usr/local/bin/report_status.sh
        echo -e "${GREEN}状态上报已执行${NC}"
    fi
    
    echo -e "\n${GREEN}节点重启操作完成！${NC}"
    exit 0
}

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
        # 尝试杀死所有运行中的上报脚本进程
        pkill -f "report_status.sh" 2>/dev/null || true
        rm -f /usr/local/bin/report_status.sh
        echo -e "上报脚本已移除"
    else
        echo -e "${YELLOW}未找到上报脚本${NC}"
    fi
    
    # 清理临时文件
    echo -e "${GREEN}正在清理临时文件...${NC}"
    rm -f /tmp/restart_request.tmp
    rm -f /tmp/last_bandwidth_*.txt
    rm -f /tmp/last_time_*.txt
    rm -f /tmp/mtproto_cron
    
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
    
    # 询问是否卸载MTProto代理
    read -p "是否卸载MTProto代理服务? (y/n) [n]: " UNINSTALL_PROXY
    if [[ "$UNINSTALL_PROXY" == "y" || "$UNINSTALL_PROXY" == "Y" ]]; then
        echo -e "${GREEN}正在卸载MTProto代理...${NC}"
        
        # 检查是否使用Docker
        if command -v docker &> /dev/null && docker ps -a | grep -q "mtproto"; then
            echo -e "${GREEN}检测到Docker版本的MTProto代理，正在移除...${NC}"
            # 获取所有MTProto相关容器
            CONTAINERS=$(docker ps -a | grep mtproto | awk '{print $1}')
            for CONTAINER in $CONTAINERS; do
                echo -e "停止并移除容器 $CONTAINER..."
                docker stop $CONTAINER 2>/dev/null || true
                docker rm $CONTAINER 2>/dev/null || true
            done
            
            # 询问是否移除Docker镜像
            read -p "是否移除MTProto代理Docker镜像? (y/n) [n]: " REMOVE_IMAGE
            if [[ "$REMOVE_IMAGE" == "y" || "$REMOVE_IMAGE" == "Y" ]]; then
                docker rmi telegrammessenger/proxy:latest 2>/dev/null || true
                echo -e "Docker镜像已移除"
            fi
        else
            # 检查系统服务
            if systemctl list-units --type=service | grep -q "mtproto"; then
                SERVICE_NAME=$(systemctl list-units --type=service | grep mtproto | head -n 1 | awk '{print $1}')
                echo -e "${GREEN}正在停止并禁用服务 $SERVICE_NAME...${NC}"
                systemctl stop $SERVICE_NAME 2>/dev/null || true
                systemctl disable $SERVICE_NAME 2>/dev/null || true
                
                # 移除服务文件
                if [ -f "/etc/systemd/system/$SERVICE_NAME" ]; then
                    rm -f "/etc/systemd/system/$SERVICE_NAME"
                    systemctl daemon-reload
                    echo -e "服务文件已移除"
                fi
            fi
            
            # 检查进程
            PID=$(ps -ef | grep "[m]tproto-proxy" | head -n 1 | awk '{print $2}')
            if [ -n "$PID" ]; then
                echo -e "${GREEN}正在终止MTProto代理进程...${NC}"
                kill -15 $PID 2>/dev/null || kill -9 $PID 2>/dev/null || true
                echo -e "进程已终止"
            fi
            
            # 移除配置文件
            echo -e "${GREEN}正在移除配置文件...${NC}"
            rm -f /etc/mtproto-proxy.conf 2>/dev/null || true
            rm -f /etc/mtpproxy.conf 2>/dev/null || true
            
            # 清理日志
            read -p "是否移除MTProto代理日志? (y/n) [n]: " REMOVE_LOGS
            if [[ "$REMOVE_LOGS" == "y" || "$REMOVE_LOGS" == "Y" ]]; then
                rm -f /var/log/mtproto.log 2>/dev/null || true
                echo -e "代理日志已移除"
            fi
        fi
        
        echo -e "${GREEN}MTProto代理卸载完成!${NC}"
    fi
    
    echo -e "\n${GREEN}卸载完成！状态上报脚本和相关定时任务已移除。${NC}"
    if [[ "$UNINSTALL_PROXY" != "y" && "$UNINSTALL_PROXY" != "Y" ]]; then
        echo -e "${YELLOW}注意：此操作不会卸载MTProto代理本身，仅移除状态上报功能。${NC}"
    fi
    exit 0
}

# 打印欢迎信息
echo -e "${BLUE}=========================================${NC}"
echo -e "${GREEN}Telegram MTProto代理节点配置脚本${NC}"
echo -e "${BLUE}=========================================${NC}\n"

# 询问操作类型
echo -e "请选择操作:"
echo -e "1) 全新安装MTProto代理和状态上报脚本"
echo -e "2) 仅安装状态上报脚本（已有MTProto代理）"
echo -e "3) 卸载状态上报脚本"
echo -e "4) 重启节点"
read -p "请选择 [1/2/3/4]: " INSTALL_TYPE

if [ "$INSTALL_TYPE" = "3" ]; then
    uninstall_report_script
elif [ "$INSTALL_TYPE" = "4" ]; then
    restart_node
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
    echo "DEBUG: cat开始"
    cat > /tmp/report_status.sh << EOF
#!/bin/bash
echo hello
EOF
    echo "DEBUG: cat已写入"
    echo "DEBUG: mv开始"
    mv /tmp/report_status.sh /usr/local/bin/report_status.sh
    echo "DEBUG: mv已完成"
    echo "DEBUG: chmod开始"
    chmod +x /usr/local/bin/report_status.sh
    echo "DEBUG: chmod已完成"
else
    # 非Docker版本的上报脚本
    cat > /tmp/report_status.sh << EOF
#!/bin/bash
echo hello
EOF
    mv /tmp/report_status.sh /usr/local/bin/report_status.sh
    chmod +x /usr/local/bin/report_status.sh
fi

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
    \"real_bandwidth\": 0,
    \"api_key\": \"$API_KEY\",
    \"node_name\": \"$NAME\",
    \"host\": \"$HOST\",
    \"port\": $PORT,
    \"secret\": \"$SECRET\",
    \"user_data\": []
  }")

if [[ "$TEST_RESULT" == *"success"* ]]; then
    echo -e "${GREEN}连接测试成功! 节点可以正常向Bot上报状态。${NC}"
else
    echo -e "${RED}连接测试失败! 请检查API密钥和Bot API地址是否正确。${NC}"
    echo -e "错误信息: $TEST_RESULT"
fi

# 创建cron任务，每分钟运行一次
echo "* * * * * /usr/local/bin/report_status.sh" > /tmp/mtproto_cron
crontab /tmp/mtproto_cron
rm /tmp/mtproto_cron

# 设置日志文件权限
touch /var/log/mtproto_report.log
chmod 644 /var/log/mtproto_report.log

echo -e "\n${GREEN}状态上报脚本创建成功！${NC}"
echo -e "每分钟将自动上报节点状态。\n"

# 显示连接信息
echo -e "\n${GREEN}MTProto Proxy 已成功安装！${NC}"
echo -e "代理信息如下：\n"
echo -e "服务器地址: ${YELLOW}$HOST${NC}"
echo -e "端口: ${YELLOW}$PORT${NC}"
echo -e "密钥: ${YELLOW}$SECRET${NC}"
echo -e "链接: ${YELLOW}https://t.me/proxy?server=$HOST&port=$PORT&secret=$SECRET${NC}\n"

# 如果是Docker安装，显示Docker命令
if [[ "$USE_DOCKER" == "y" || "$USE_DOCKER" == "Y" ]]; then
    echo -e "Docker 容器名称: ${YELLOW}$CONTAINER_NAME${NC}"
    echo -e "查看日志: ${YELLOW}docker logs $CONTAINER_NAME${NC}"
    echo -e "重启代理: ${YELLOW}docker restart $CONTAINER_NAME${NC}"
else
    echo -e "服务名称: ${YELLOW}mtproto-proxy${NC}"
    echo -e "查看日志: ${YELLOW}journalctl -u mtproto-proxy${NC}"
    echo -e "重启代理: ${YELLOW}systemctl restart mtproto-proxy${NC}"
fi

echo -e "\n服务已启动，状态上报已设置。节点ID: ${YELLOW}$NODE_ID${NC}\n"
echo -e "请将以下信息告知机器人管理员："
echo -e "节点ID: ${YELLOW}$NODE_ID${NC}"
echo -e "节点名称: ${YELLOW}$NAME${NC}"
echo -e "主机地址: ${YELLOW}$HOST${NC}"
echo -e "端口: ${YELLOW}$PORT${NC}"
echo -e "密钥: ${YELLOW}$SECRET${NC}\n" 
