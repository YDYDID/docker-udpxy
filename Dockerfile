# 阶段 1：从 rtp2httpd 官方镜像中把已经编译好的二进制文件“借”过来
FROM ghcr.io/stackia/rtp2httpd:latest AS rtp_base

# 阶段 2：基于 Alpine 组装全家桶
FROM alpine:latest
LABEL maintainer="ydydid"

#【极度精简】去掉了没有用处的 bash，修正了定时任务包名为官方标准的 dcron
RUN apk add --no-cache python3 py3-pip py3-lxml curl tzdata dcron \
    && rm -rf /var/cache/apk/*

ENV TZ=Asia/Shanghai
WORKDIR /data

# 注入完美的默认脚本：重连时清空旧网络、绑定新IP、下发精细路由，并利用 -O 42 自动同步电信内网时间
RUN mkdir -p /usr/share/udhcpc && \
    echo -e '#!/bin/sh\n\
case "$1" in\n\
    bound|renew)\n\
        ip addr flush dev $interface\n\
        ip route flush dev $interface proto static 2>/dev/null\n\
        ip addr add $ip/$mask dev $interface\n\
        if [ -n "$classless_static_routes" ]; then\n\
            set -- $classless_static_routes\n\
            while [ $# -ge 5 ]; do\n\
                ip route add $1/$2 via $3.$4.$5.$6 dev $interface proto static 2>/dev/null\n\
                shift 6\n\
            done\n\
        fi\n\
        if [ -n "$router" ]; then\n\
            for network in 14.29.0.0/16 183.59.0.0/16 125.88.0.0/16 10.0.0.0/8; do\n\
                ip route add $network via $router dev $interface proto static 2>/dev/null\n\
            done\n\
        fi\n\
        if [ -n "$ntpsrv" ]; then\n\
            echo "IPTV NTP Server found: $ntpsrv. Syncing time..."\n\
            ntpd -n -q -p $ntpsrv 2>/dev/null\n\
        fi\n\
        ;;\n\
esac' > /usr/share/udhcpc/default.script && \
    chmod +x /usr/share/udhcpc/default.script

# 复制 rtp2httpd 可执行文件到 system 路径
COPY --from=rtp_base /usr/local/bin/rtp2httpd /usr/local/bin/rtp2httpd

# 安装 pure Python 依赖库
RUN pip install --no-cache-dir requests beautifulsoup4 --break-system-packages

# 配置定时任务
RUN echo "5 6 * * * cd /data && python3 gdctiptv.py > /proc/1/fd/1 2>&1" > /etc/mix_cron

# 最终的启动命令（CMD）：
CMD crontab /etc/mix_cron \
    && echo "正在处理 MAC 地址格式..." \
    && IPTV_MAC=$(echo "${OPT_61//:/}" | tr '[:upper:]' '[:lower:]') \
    && echo "正在为网卡 $IPTV_NET 注入机顶盒伪装 MAC (带冒号): $OPT_61 ..." \
    && ip link set $IPTV_NET down \
    && ip link set $IPTV_NET address $OPT_61 \
    && ip link set $IPTV_NET up \
    && echo "正在发起带 Option 鉴权的 DHCP 请求..." \
    && udhcpc -i $IPTV_NET -p /var/run/udhcpc.pid \
       -t 3 -A 60 \
       -O 28 -O 33 -O 42 -O 43 -O 121 \
       -x 0x0c:$OPT_12 \
       -x 0x3d:01$IPTV_MAC \
       -V $OPT_60 & \
    echo "等待 IPTV 网络拨号就绪并自动写入路由..." \
    && while ! ip -4 addr show $IPTV_NET | grep -q 'inet '; do sleep 1; done \
    && echo "检测到本地 IP 已成功绑定！等待 5 秒让局端路由表稳定下发..." \
    && sleep 5 \
    && (python3 gdctiptv.py || echo "Python 抓取报错，等待后续定时任务重试") \
    && crond -l 2 \
    && rtp2httpd \
       --external-m3u $M3U_PATH \
       --external-m3u-update-interval 0 \
       --upstream-interface $LAN_NET \
       --upstream-interface-fcc $IPTV_NET \
       --upstream-interface-rtsp $IPTV_NET \
       --upstream-interface-multicast $IPTV_NET \
       --upstream-interface-http $LAN_NET \
       --buffer-pool-max-size 131072 \
       --udp-rcvbuf-size 33554432 \
       --noconfig \
       --verbose $VERBOSE_LEVEL \
       --listen $LISTEN_PORT \
       --maxclients 10 \
       --workers 2 \
       --xff \
       --r2h-token $R2H_TOKEN
