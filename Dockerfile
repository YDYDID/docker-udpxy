# 阶段 1：从 rtp2httpd 官方镜像中把已经编译好的二进制文件“借”过来
FROM ghcr.io/stackia/rtp2httpd:latest AS rtp_base

# 阶段 2：基于 Alpine 组装全家桶
FROM alpine:latest
LABEL maintainer="ydydid"

# 安装基础工具、Python 环境、定时任务，以及 Alpine 官方预编译的 py3-lxml 库（防止 pip 编译失败）
RUN apk add --no-cache python3 py3-pip py3-lxml curl tzdata crontabs bash \
    && rm -rf /var/cache/apk/*

ENV TZ=Asia/Shanghai
WORKDIR /data

# 复制 rtp2httpd 可执行文件到系统路径
COPY --from=rtp_base /usr/local/bin/rtp2httpd /usr/local/bin/rtp2httpd

# 此时 pip 只需要安全地安装纯 Python 依赖库（无需额外编译环境）
RUN pip install --no-cache-dir requests beautifulsoup4 --break-system-packages

# 配置定时任务：每天凌晨 06:05 自动执行 python 脚本，并将日志输出到标准输出供 docker logs 查看
RUN echo "5 6 * * * cd /data && python3 gdctiptv.py > /proc/1/fd/1 2>&1" > /etc/mix_cron

# 启动命令（CMD）：
# 1. 载入定时任务
# 2. 强制使用容器内的第一块网卡 eth0 发起带 Option 鉴权的 DHCP 请求。（-R 不抢默认路由）
# 3. 【核心修正】循环检查网卡，直到 eth0 真正拿到 IP 后再向下执行，彻底消除网络时序报错
# 4. 后台启动 crond 守护进程，前台常驻运行 rtp2httpd 
CMD crontab /etc/mix_cron \
    && udhcpc -i eth0 -n -R -x hostname:"你的Option12" -x 0x3d:"你的Option61" -V "你的Option60" \
    && echo "等待 IPTV 网络拨号就绪..." && while ! ip -4 addr show eth0 | grep -q 'inet '; do sleep 1; done \
    && python3 gdctiptv.py \
    && crond -l 2 \
    && rtp2httpd -c /data/rtp2httpd.conf









# 阶段 1：从 rtp2httpd 官方镜像中把已经编译好的二进制文件“借”过来
FROM ghcr.io/stackia/rtp2httpd:latest AS rtp_base

# 阶段 2：基于 Alpine 组装全家桶
FROM alpine:latest
LABEL maintainer="ydydid"

# 安装基础工具、Python 环境和 Alpine 定时任务工具 crontabs
RUN apk add --no-cache python3 py3-pip curl tzdata crontabs \
    && rm -rf /var/cache/apk/*

ENV TZ=Asia/Shanghai
WORKDIR /data

# 复制 rtp2httpd 可执行文件到系统路径
COPY --from=rtp_base /usr/local/bin/rtp2httpd /usr/local/bin/rtp2httpd

RUN pip install --no-cache-dir requests beautifulsoup4 lxml --break-system-packages

# 配置定时任务：每天凌晨 06:05 自动执行 python 脚本，并将日志输出到标准输出供 docker logs 查看
RUN echo "5 6 * * * cd /data && python3 gdctiptv.py > /proc/1/fd/1 2>&1" > /etc/mix_cron

# 启动命令（CMD）：
# 1. 载入定时任务
# 2. 强制使用容器内的第一块网卡 eth0（它对应宿主机的 IPTV 网卡）发起带 Option 鉴权的 DHCP 请求。
#    注意：-R 参数（不修改默认路由）极其重要！防止 IPTV 的网关冲掉局域网路由
# 3. 强制立刻执行一次 Python 抓取脚本
# 4. 后台启动 crond 守护进程，前台常驻运行 rtp2httpd 
CMD crontab /etc/mix_cron \
    && udhcpc -i eth0 -n -R -x hostname:"你的Option12" -x 0x3d:"你的Option61" -V "你的Option60" \
    && python3 gdctiptv.py \
    && crond -l 2 \
    && rtp2httpd -c /data/rtp2httpd.conf




FROM alpine:latest
LABEL maintainer="ydydid"

# 1. 安装基础工具、Python 环境和 Alpine 定时任务工具 crontabs
RUN apk add --no-cache python3 py3-pip curl tzdata crontabs \
    && rm -rf /var/cache/apk/*

ENV TZ=Asia/Shanghai

WORKDIR /data

RUN pip install --no-cache-dir requests beautifulsoup4 lxml --break-system-packages

# 2. 配置定时任务：每天凌晨 06:05 自动到 /data 目录下执行 python 脚本
# 并且把日志输出到终端，方便你用 docker logs 查看
RUN echo "5 6 * * * cd /data && python3 gdctiptv.py > /proc/1/fd/1 2>&1"  > /etc/mix_cron

# 3. 启动命令：
# 第一步加载定时任务 
# 第二步容器启动时【立刻强制执行一次】python3 gdctiptv.py
# 第三步启动 crond 守护进程撑住容器
CMD crontab /etc/mix_cron && python3 gdctiptv.py && crond -f -l 2
