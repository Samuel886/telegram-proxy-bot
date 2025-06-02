
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m' 


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


restart_node() {
    echo -e "${BLUE}=========================================${NC}"
    echo -e "${GREEN}重启节点${NC}"
    echo -e "${BLUE}=========================================${NC}\n"
    

    if command -v docker &> /dev/null && docker ps | grep -q "mtproto"; then

        CONTAINER_NAME=$(docker ps | grep mtproto | head -n 1 | awk '{print $NF}')
        if [ -z "$CONTAINER_NAME" ]; then
            CONTAINER_NAME="mtproto-proxy"
        fi
        
        echo -e "${GREEN}正在重启Docker容器 $CONTAINER_NAME...${NC}"
        docker restart $CONTAINER_NAME
        echo -e "${GREEN}重启完成！${NC}"
    else

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
    

    if [ -f "/usr/local/bin/report_status.sh" ]; then
        echo -e "${GREEN}正在执行状态上报脚本...${NC}"
        /usr/local/bin/report_status.sh
        echo -e "${GREEN}状态上报已执行${NC}"
    fi
    
    echo -e "\n${GREEN}节点重启操作完成！${NC}"
    exit 0
}


uninstall_report_script() {
    echo -e "${BLUE}=========================================${NC}"
    echo -e "${GREEN}卸载状态上报脚本${NC}"
    echo -e "${BLUE}=========================================${NC}\n"
    

    echo -e "${GREEN}正在移除定时任务...${NC}"
    (crontab -l 2>/dev/null | grep -v "report_status.sh") | crontab -
    

    echo -e "${GREEN}正在移除上报脚本...${NC}"
    if [ -f "/usr/local/bin/report_status.sh" ]; then

        pkill -f "report_status.sh" 2>/dev/null || true
        rm -f /usr/local/bin/report_status.sh
        echo -e "上报脚本已移除"
    else
        echo -e "${YELLOW}未找到上报脚本${NC}"
    fi
    

    echo -e "${GREEN}正在清理临时文件...${NC}"
    rm -f /tmp/restart_request.tmp
    rm -f /tmp/last_bandwidth_*.txt
    rm -f /tmp/last_time_*.txt
    rm -f /tmp/mtproto_cron
    

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
    

    read -p "是否卸载MTProto代理服务? (y/n) [n]: " UNINSTALL_PROXY
    if [[ "$UNINSTALL_PROXY" == "y" || "$UNINSTALL_PROXY" == "Y" ]]; then
        echo -e "${GREEN}正在卸载MTProto代理...${NC}"
        

        if command -v docker &> /dev/null && docker ps -a | grep -q "mtproto"; then
            echo -e "${GREEN}检测到Docker版本的MTProto代理，正在移除...${NC}"
            # 获取所有MTProto相关容器
            CONTAINERS=$(docker ps -a | grep mtproto | awk '{print $1}')
            for CONTAINER in $CONTAINERS; do
                echo -e "停止并移除容器 $CONTAINER..."
                docker stop $CONTAINER 2>/dev/null || true
                docker rm $CONTAINER 2>/dev/null || true
            done
            

            read -p "是否移除MTProto代理Docker镜像? (y/n) [n]: " REMOVE_IMAGE
            if [[ "$REMOVE_IMAGE" == "y" || "$REMOVE_IMAGE" == "Y" ]]; then
                docker rmi telegrammessenger/proxy:latest 2>/dev/null || true
                echo -e "Docker镜像已移除"
            fi
        else

            if systemctl list-units --type=service | grep -q "mtproto"; then
                SERVICE_NAME=$(systemctl list-units --type=service | grep mtproto | head -n 1 | awk '{print $1}')
                echo -e "${GREEN}正在停止并禁用服务 $SERVICE_NAME...${NC}"
                systemctl stop $SERVICE_NAME 2>/dev/null || true
                systemctl disable $SERVICE_NAME 2>/dev/null || true
                

                if [ -f "/etc/systemd/system/$SERVICE_NAME" ]; then
                    rm -f "/etc/systemd/system/$SERVICE_NAME"
                    systemctl daemon-reload
                    echo -e "服务文件已移除"
                fi
            fi
            

            PID=$(ps -ef | grep "[m]tproto-proxy" | head -n 1 | awk '{print $2}')
            if [ -n "$PID" ]; then
                echo -e "${GREEN}正在终止MTProto代理进程...${NC}"
                kill -15 $PID 2>/dev/null || kill -9 $PID 2>/dev/null || true
                echo -e "进程已终止"
            fi
            

            echo -e "${GREEN}正在移除配置文件...${NC}"
            rm -f /etc/mtproto-proxy.conf 2>/dev/null || true
            rm -f /etc/mtpproxy.conf 2>/dev/null || true
            

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


echo -e "${BLUE}=========================================${NC}"
echo -e "${GREEN}Telegram MTProto代理节点配置脚本${NC}"
echo -e "${BLUE}=========================================${NC}\n"


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


detect_mtproto() {
    echo -e "${GREEN}正在尝试自动检测MTProto代理信息...${NC}"
    

    if command -v docker &> /dev/null && docker ps | grep -q "mtproto"; then
        echo -e "${GREEN}检测到Docker运行的MTProto代理${NC}"
        USE_DOCKER="y"
        

        CONTAINER_NAME=$(docker ps | grep mtproto | head -n 1 | awk '{print $NF}')
        if [ -z "$CONTAINER_NAME" ]; then
            CONTAINER_NAME="mtproto-proxy"
        else
            echo -e "检测到容器名称: ${YELLOW}$CONTAINER_NAME${NC}"
        fi
        

        PORT_INFO=$(docker port "$CONTAINER_NAME" | grep -oP '\d+$' | head -n 1)
        if [ -n "$PORT_INFO" ]; then
            PORT=$PORT_INFO
            echo -e "检测到端口: ${YELLOW}$PORT${NC}"
        fi
        

        DOCKER_ENV=$(docker inspect "$CONTAINER_NAME" | grep -oP '(?<="SECRET=)[^"]+')
        if [ -n "$DOCKER_ENV" ]; then
            SECRET=$DOCKER_ENV
            echo -e "检测到密钥: ${YELLOW}$SECRET${NC}"
        fi
        

        STATS_PORT="2398"
        return 0
    fi
    

    if ps -ef | grep -q "[m]tproto-proxy"; then
        echo -e "${GREEN}检测到直接进程运行的MTProto代理${NC}"
        USE_DOCKER="n"
        

        PROCESS_CMD=$(ps -ef | grep "[m]tproto-proxy" | head -n 1)
        echo -e "检测到进程: ${YELLOW}$(echo $PROCESS_CMD | awk '{print $8" "$9" ..."}')${NC}"
        

        PORT=$(echo "$PROCESS_CMD" | grep -oP -- "-H\s+\K\d+")
        if [ -n "$PORT" ]; then
            echo -e "检测到端口: ${YELLOW}$PORT${NC}"
        else

            PORT=$(echo "$PROCESS_CMD" | grep -oP -- "-p\s+\K\d+")
            if [ -n "$PORT" ]; then
                echo -e "检测到端口: ${YELLOW}$PORT${NC}"
            fi
        fi
        

        SECRET=$(echo "$PROCESS_CMD" | grep -oP -- "-S\s+\K[a-zA-Z0-9]+")
        if [ -n "$SECRET" ]; then
            echo -e "检测到基本密钥: ${YELLOW}$SECRET${NC}"
            

            DOMAIN=$(echo "$PROCESS_CMD" | grep -oP -- "--domain\s+\K[a-zA-Z0-9.-]+")
            if [ -n "$DOMAIN" ]; then
                echo -e "检测到伪装域名: ${YELLOW}$DOMAIN${NC}"
                

                if [[ "$SECRET" != ee* ]]; then
                    SECRET_START="ee"
                else
                    SECRET_START=""
                fi
                

                if command -v xxd &> /dev/null; then
                    DOMAIN_HEX=$(echo -n "$DOMAIN" | xxd -p | tr -d '\n')
                    FULL_SECRET="${SECRET_START}${SECRET}${DOMAIN_HEX}"
                    echo -e "构建完整密钥: ${YELLOW}$FULL_SECRET${NC}"
                    SECRET=$FULL_SECRET
                fi
            fi
        else

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
        

        STATUS_CMD="netstat -tuln | grep -c :$PORT || ss -tuln | grep -c :$PORT"
        BANDWIDTH_CMD="echo 0"
        
        return 0
    fi
    

    if systemctl list-units --type=service | grep -q "mtproto"; then
        echo -e "${GREEN}检测到系统服务运行的MTProto代理${NC}"
        USE_DOCKER="n"
        

        SERVICE_NAME=$(systemctl list-units --type=service | grep mtproto | head -n 1 | awk '{print $1}')
        echo -e "检测到服务: ${YELLOW}$SERVICE_NAME${NC}"
        

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
        

        STATUS_CMD="netstat -tuln | grep -c :$PORT || ss -tuln | grep -c :$PORT"
        BANDWIDTH_CMD="echo 0"
        
        return 0
    fi
    

    echo -e "${YELLOW}未能自动检测到MTProto代理信息，请手动输入${NC}"
    return 1
}


HOST=$(curl -s ifconfig.me)
PORT=443
SECRET=$(head -c 16 /dev/urandom | xxd -ps)


echo -e "请输入以下信息（如不确定，请咨询您的机器人管理员）\n"


read -p "节点名称 [默认节点]: " NAME
NAME=${NAME:-"默认节点"}


read -p "API密钥 (必填): " API_KEY
while [ -z "$API_KEY" ]; do
    echo -e "${RED}API密钥不能为空!${NC}"
    read -p "API密钥 (必填): " API_KEY
done


read -p "Bot API地址 (例如 http://your-bot-domain:8080/api/report): " API_URL
while [ -z "$API_URL" ]; do
    echo -e "${RED}Bot API地址不能为空!${NC}"
    read -p "Bot API地址 (例如 http://your-bot-domain:8080/api/report): " API_URL
done


read -p "节点ID [0]: " NODE_ID
NODE_ID=${NODE_ID:-0}


if [ "$INSTALL_TYPE" = "2" ]; then
    echo -e "\n请输入您现有MTProto代理的信息:"
    

    detect_mtproto
    

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


read -p "确认安装? (y/n): " CONFIRM
if [[ "$CONFIRM" != "y" && "$CONFIRM" != "Y" ]]; then
    echo -e "${RED}安装已取消${NC}"
    exit 1
fi


echo -e "\n${GREEN}正在安装依赖...${NC}"
apt-get update
apt-get install -y curl wget


if [ "$INSTALL_TYPE" = "1" ]; then
    apt-get install -y build-essential git
    

    if ! command -v docker &> /dev/null; then
        echo -e "\n${GREEN}正在安装Docker...${NC}"
        curl -fsSL https://get.docker.com -o get-docker.sh
        sh get-docker.sh
        systemctl enable docker
        systemctl start docker
    fi


    echo -e "\n${GREEN}正在拉取MTProto代理镜像...${NC}"
    docker pull telegrammessenger/proxy:latest


    docker stop mtproto-proxy &>/dev/null || true
    docker rm mtproto-proxy &>/dev/null || true


    echo -e "\n${GREEN}正在启动MTProto代理...${NC}"
    docker run -d --name mtproto-proxy --restart always -p $PORT:443 \
        -e SECRET=$SECRET \
        -e TAG=dcfd5cbcf7f916c0 \
        telegrammessenger/proxy:latest
        

    USE_DOCKER="y"
    CONTAINER_NAME="mtproto-proxy"
    STATS_PORT="2398"
fi


echo -e "\n${GREEN}正在创建状态上报脚本...${NC}"

if [[ "$USE_DOCKER" == "y" || "$USE_DOCKER" == "Y" ]]; then

    cat > /usr/local/bin/report_status.sh << EOF
#!/bin/bash


API_KEY="$API_KEY"
NODE_ID=$NODE_ID


start_restart_server() {

    if netstat -tuln | grep -q ':8080'; then
        return
    fi
    

    while true; do
        echo -e "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\n\r\n{\"status\":\"success\"}" | nc -l -p 8080 > /tmp/restart_request.tmp
        

        if grep -q "restart" /tmp/restart_request.tmp; then

            if grep -q "\\"api_key\\":\\"$API_KEY\\"" /tmp/restart_request.tmp; then
                echo "收到重启命令，正在重启..."
                

                docker restart $CONTAINER_NAME
                

                report_status
            fi
        fi
    done
}


report_status() {

    echo "[\$(date +"%Y-%m-%d %H:%M:%S")] 开始获取节点状态..." >> /var/log/mtproto_report.log
    

    echo "[\$(date +"%Y-%m-%d %H:%M:%S")] 尝试从stats端口获取连接数..." >> /var/log/mtproto_report.log
    CONN_COUNT=\$(docker exec $CONTAINER_NAME curl -s http://localhost:$STATS_PORT/stats 2>/dev/null | grep -oP '(?<="active_users":)[0-9]+' || echo 0)
    if [ -z "\$CONN_COUNT" ] || [ "\$CONN_COUNT" -eq 0 ]; then
        echo "[\$(date +"%Y-%m-%d %H:%M:%S")] 从stats端口获取连接数失败，尝试使用netstat..." >> /var/log/mtproto_report.log

        CONN_COUNT=\$(docker exec $CONTAINER_NAME bash -c "netstat -ant | grep ESTABLISHED | grep -c :443" 2>/dev/null || echo 0)
        if [ -z "\$CONN_COUNT" ] || [ "\$CONN_COUNT" -eq 0 ]; then
            echo "[\$(date +"%Y-%m-%d %H:%M:%S")] 使用netstat获取连接数失败，尝试使用ss..." >> /var/log/mtproto_report.log

            CONN_COUNT=\$(docker exec $CONTAINER_NAME bash -c "ss -ant | grep ESTABLISHED | grep -c :443" 2>/dev/null || echo 0)
        fi
        if [ -z "\$CONN_COUNT" ]; then
            CONN_COUNT=0
        fi
    fi
    echo "[\$(date +"%Y-%m-%d %H:%M:%S")] 最终获取到的连接数: \$CONN_COUNT" >> /var/log/mtproto_report.log
    

    echo "[\$(date +"%Y-%m-%d %H:%M:%S")] 尝试从日志获取带宽..." >> /var/log/mtproto_report.log
    BANDWIDTH=\$(docker exec $CONTAINER_NAME cat /var/log/mtproto.log 2>/dev/null | grep "Written" | awk '{sum+=\$2} END {print sum}')
    if [ -z "\$BANDWIDTH" ] || [ "\$BANDWIDTH" -eq 0 ]; then
        echo "[\$(date +"%Y-%m-%d %H:%M:%S")] 从日志获取带宽失败，尝试使用网络接口..." >> /var/log/mtproto_report.log
        # 尝试使用其他方法获取带宽
        BANDWIDTH=\$(docker exec $CONTAINER_NAME bash -c "cat /proc/net/dev | grep eth0" 2>/dev/null | awk '{print \$10}')
        if [ -z "\$BANDWIDTH" ]; then
            BANDWIDTH=0
        fi
    fi
    echo "[\$(date +"%Y-%m-%d %H:%M:%S")] 最终获取到的带宽: \$BANDWIDTH" >> /var/log/mtproto_report.log
    

    CURRENT_TIME=\$(date +%s)
    LAST_BANDWIDTH_FILE="/tmp/last_bandwidth_$NODE_ID.txt"
    LAST_TIME_FILE="/tmp/last_time_$NODE_ID.txt"
    
    if [ -f "\$LAST_BANDWIDTH_FILE" ] && [ -f "\$LAST_TIME_FILE" ]; then
        LAST_BANDWIDTH=\$(cat \$LAST_BANDWIDTH_FILE)
        LAST_TIME=\$(cat \$LAST_TIME_FILE)
        

        BANDWIDTH_DIFF=\$((\$BANDWIDTH - \$LAST_BANDWIDTH))
        TIME_DIFF=\$((\$CURRENT_TIME - \$LAST_TIME))
        
        if [ \$TIME_DIFF -gt 0 ]; then
            # 计算实时带宽 (bytes/s)
            REAL_BANDWIDTH=\$((\$BANDWIDTH_DIFF / \$TIME_DIFF))
        else
            REAL_BANDWIDTH=0
        fi
    else
        REAL_BANDWIDTH=0
    fi
    

    echo "\$BANDWIDTH" > "\$LAST_BANDWIDTH_FILE"
    echo "\$CURRENT_TIME" > "\$LAST_TIME_FILE"
    

    TIMESTAMP=\$(date +"%Y-%m-%d %H:%M:%S")
    

    echo "[\$TIMESTAMP] 连接数: \$CONN_COUNT, 总带宽: \$BANDWIDTH bytes, 实时带宽: \$REAL_BANDWIDTH bytes/s" >> /var/log/mtproto_report.log
    

    curl -s -X POST $API_URL \\
      -H "Content-Type: application/json" \\
      -d '{
        "node_id": '$NODE_ID',
        "conn_count": '\$CONN_COUNT',
        "bandwidth": '\$BANDWIDTH',
        "real_bandwidth": '\$REAL_BANDWIDTH',
        "api_key": "'$API_KEY'",
        "node_name": "$NAME",
        "host": "$HOST",
        "port": $PORT,
        "secret": "$SECRET",
        "user_data": []
      }' > /dev/null
}


start_restart_server &


report_status
EOF
else

    cat > /usr/local/bin/report_status.sh << EOF
#!/bin/bash


API_KEY="$API_KEY"
NODE_ID=$NODE_ID


start_restart_server() {

    if netstat -tuln | grep -q ':8080'; then
        return
    fi
    

    while true; do
        echo -e "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\n\r\n{\"status\":\"success\"}" | nc -l -p 8080 > /tmp/restart_request.tmp
        

        if grep -q "restart" /tmp/restart_request.tmp; then

            if grep -q "\\"api_key\\":\\"$API_KEY\\"" /tmp/restart_request.tmp; then
                echo "收到重启命令，正在重启..."
                

                systemctl restart mtproto-proxy
                

                report_status
            fi
        fi
    done
}


report_status() {

    echo "[\$(date +"%Y-%m-%d %H:%M:%S")] 开始获取节点状态..." >> /var/log/mtproto_report.log
    

    echo "[\$(date +"%Y-%m-%d %H:%M:%S")] 尝试从stats端口获取连接数..." >> /var/log/mtproto_report.log
    CONN_COUNT=\$(curl -s http://localhost:$STATS_PORT/stats 2>/dev/null | grep -oP '(?<="active_users":)[0-9]+' || echo 0)
    if [ -z "\$CONN_COUNT" ] || [ "\$CONN_COUNT" -eq 0 ]; then
        echo "[\$(date +"%Y-%m-%d %H:%M:%S")] 从stats端口获取连接数失败，尝试使用netstat..." >> /var/log/mtproto_report.log
        # 尝试使用netstat或ss命令获取连接数
        CONN_COUNT=\$(netstat -ant | grep ESTABLISHED | grep -c :$PORT 2>/dev/null || echo 0)
        if [ -z "\$CONN_COUNT" ] || [ "\$CONN_COUNT" -eq 0 ]; then
            echo "[\$(date +"%Y-%m-%d %H:%M:%S")] 使用netstat获取连接数失败，尝试使用ss..." >> /var/log/mtproto_report.log
            # 再次尝试使用ss命令
            CONN_COUNT=\$(ss -ant | grep ESTABLISHED | grep -c :$PORT 2>/dev/null || echo 0)
        fi
        if [ -z "\$CONN_COUNT" ]; then
            CONN_COUNT=0
        fi
    fi
    echo "[\$(date +"%Y-%m-%d %H:%M:%S")] 最终获取到的连接数: \$CONN_COUNT" >> /var/log/mtproto_report.log
    

    echo "[\$(date +"%Y-%m-%d %H:%M:%S")] 尝试从日志获取带宽..." >> /var/log/mtproto_report.log
    BANDWIDTH=\$(cat /var/log/mtproto.log 2>/dev/null | grep "Written" | awk '{sum+=\$2} END {print sum}')
    if [ -z "\$BANDWIDTH" ] || [ "\$BANDWIDTH" -eq 0 ]; then
        echo "[\$(date +"%Y-%m-%d %H:%M:%S")] 从日志获取带宽失败，尝试使用网络接口..." >> /var/log/mtproto_report.log
        # 尝试使用其他方法获取带宽
        INTERFACE=\$(ip route | grep default | awk '{print \$5}' | head -n 1)
        if [ -n "\$INTERFACE" ]; then
            BANDWIDTH=\$(cat /proc/net/dev | grep "\$INTERFACE" | awk '{print \$10}')
        fi
        if [ -z "\$BANDWIDTH" ]; then
            BANDWIDTH=0
        fi
    fi
    echo "[\$(date +"%Y-%m-%d %H:%M:%S")] 最终获取到的带宽: \$BANDWIDTH" >> /var/log/mtproto_report.log
    

    CURRENT_TIME=\$(date +%s)
    LAST_BANDWIDTH_FILE="/tmp/last_bandwidth_$NODE_ID.txt"
    LAST_TIME_FILE="/tmp/last_time_$NODE_ID.txt"
    
    if [ -f "\$LAST_BANDWIDTH_FILE" ] && [ -f "\$LAST_TIME_FILE" ]; then
        LAST_BANDWIDTH=\$(cat \$LAST_BANDWIDTH_FILE)
        LAST_TIME=\$(cat \$LAST_TIME_FILE)
        

        BANDWIDTH_DIFF=\$((\$BANDWIDTH - \$LAST_BANDWIDTH))
        TIME_DIFF=\$((\$CURRENT_TIME - \$LAST_TIME))
        
        if [ \$TIME_DIFF -gt 0 ]; then
            # 计算实时带宽 (bytes/s)
            REAL_BANDWIDTH=\$((\$BANDWIDTH_DIFF / \$TIME_DIFF))
        else
            REAL_BANDWIDTH=0
        fi
    else
        REAL_BANDWIDTH=0
    fi
    

    echo "\$BANDWIDTH" > "\$LAST_BANDWIDTH_FILE"
    echo "\$CURRENT_TIME" > "\$LAST_TIME_FILE"
    

    TIMESTAMP=\$(date +"%Y-%m-%d %H:%M:%S")
    

    echo "[\$TIMESTAMP] 连接数: \$CONN_COUNT, 总带宽: \$BANDWIDTH bytes, 实时带宽: \$REAL_BANDWIDTH bytes/s" >> /var/log/mtproto_report.log
    

    curl -s -X POST $API_URL \\
      -H "Content-Type: application/json" \\
      -d '{
        "node_id": '$NODE_ID',
        "conn_count": '\$CONN_COUNT',
        "bandwidth": '\$BANDWIDTH',
        "real_bandwidth": '\$REAL_BANDWIDTH',
        "api_key": "'$API_KEY'",
        "node_name": "$NAME",
        "host": "$HOST",
        "port": $PORT,
        "secret": "$SECRET",
        "user_data": []
      }' > /dev/null
}


start_restart_server &


report_status
EOF
fi


chmod +x /usr/local/bin/report_status.sh


touch /var/log/mtproto_report.log
chmod 666 /var/log/mtproto_report.log


echo -e "\n${GREEN}正在设置定时任务...${NC}"
CRON_EXPR="*/$REPORT_INTERVAL * * * *"
(crontab -l 2>/dev/null | grep -v "report_status.sh"; echo "$CRON_EXPR /usr/local/bin/report_status.sh") | crontab -


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


echo -e "${GREEN}正在测试状态上报脚本...${NC}"
/usr/local/bin/report_status.sh
echo -e "${GREEN}上报脚本已运行，请检查/var/log/mtproto_report.log文件查看详情${NC}"


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


echo "* * * * * /usr/local/bin/report_status.sh" > /tmp/mtproto_cron
crontab /tmp/mtproto_cron
rm /tmp/mtproto_cron


touch /var/log/mtproto_report.log
chmod 644 /var/log/mtproto_report.log

echo -e "\n${GREEN}状态上报脚本创建成功！${NC}"
echo -e "每分钟将自动上报节点状态。\n"


echo -e "\n${GREEN}MTProto Proxy 已成功安装！${NC}"
echo -e "代理信息如下：\n"
echo -e "服务器地址: ${YELLOW}$HOST${NC}"
echo -e "端口: ${YELLOW}$PORT${NC}"
echo -e "密钥: ${YELLOW}$SECRET${NC}"
echo -e "链接: ${YELLOW}https://t.me/proxy?server=$HOST&port=$PORT&secret=$SECRET${NC}\n"


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
