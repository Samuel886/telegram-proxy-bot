#!/bin/bash

# Telegram MTProto代理节点一键安装脚本
# 此脚本用于自动安装和配置MTProto代理服务器，或者仅配置状态上报

# 彩色输出
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m' # 无颜色

# 打印欢迎信息
echo -e "${BLUE}=========================================${NC}"
echo -e "${GREEN}Telegram MTProto代理节点配置脚本${NC}"
echo -e "${BLUE}=========================================${NC}\n"

# 询问是否已经安装MTProto代理
echo -e "请选择操作:"
echo -e "1) 全新安装MTProto代理和状态上报脚本"
echo -e "2) 仅安装状态上报脚本（已有MTProto代理）"
read -p "请选择 [1/2]: " INSTALL_TYPE
if [ "$INSTALL_TYPE" != "1" ] && [ "$INSTALL_TYPE" != "2" ]; then
    echo -e "${RED}无效的选择，默认选择1${NC}"
    INSTALL_TYPE="1"
fi

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
    read -p "MTProto端口 [443]: " PORT
    PORT=${PORT:-443}
    
    read -p "MTProto密钥 (必填): " SECRET
    while [ -z "$SECRET" ]; do
        echo -e "${RED}密钥不能为空!${NC}"
        read -p "MTProto密钥 (必填): " SECRET
    done
    
    # 询问Docker和Stats端口
    read -p "是否使用Docker运行MTProto代理? (y/n) [y]: " USE_DOCKER
    USE_DOCKER=${USE_DOCKER:-y}
    
    if [[ "$USE_DOCKER" == "y" || "$USE_DOCKER" == "Y" ]]; then
        read -p "Docker容器名称 [mtproto-proxy]: " CONTAINER_NAME
        CONTAINER_NAME=${CONTAINER_NAME:-mtproto-proxy}
        
        read -p "Stats端口 [2398]: " STATS_PORT
        STATS_PORT=${STATS_PORT:-2398}
    else
        read -p "MTProto代理状态命令 (能够获取连接数的命令): " STATUS_CMD
        if [ -z "$STATUS_CMD" ]; then
            echo -e "${YELLOW}未提供状态命令，将无法获取准确的连接数。${NC}"
            STATUS_CMD="echo 0"
        fi
        
        read -p "MTProto代理带宽命令 (能够获取带宽的命令): " BANDWIDTH_CMD
        if [ -z "$BANDWIDTH_CMD" ]; then
            echo -e "${YELLOW}未提供带宽命令，将无法获取准确的带宽使用量。${NC}"
            BANDWIDTH_CMD="echo 0"
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
BANDWIDTH=\$($BANDWIDTH_CMD)
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
