FROM alpine:latest
LABEL maintainer="ydydid"

# 1. 安装基础工具、Python 环境和 Alpine 定时任务工具 crontabs
RUN apk add --no-cache python3 py3-pip curl tzdata crontabs \
    && rm -rf /var/cache/apk/*

ENV TZ=Asia/Shanghai

WORKDIR /data

RUN pip install --no-cache-dir requests beautifulsoup4 lxml --break-system-packages

# 2. 配置定时任务：每天凌晨 04:00 自动到 /data 目录下执行 python 脚本
# 并且把日志输出到终端，方便你用 docker logs 查看
RUN echo "5 6 * * * cd /data && python3 main.py >> /var/log/iptv.log 2>&1" > /etc/mix_cron

# 3. 启动命令：
# 第一步加载定时任务 
# 第二步容器启动时【立刻强制执行一次】python3 main.py，确保你每次部署或重启后，Jellyfin 马上就能看电视，不用傻等到凌晨4点
# 第三步启动 crond 守护进程撑住容器
CMD crontab /etc/mix_cron && python3 main.py && crond -f -l 2
