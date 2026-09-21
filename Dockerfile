# 阶段 1：从 rtp2httpd 官方镜像中把已经编译好的二进制文件“借”过来
FROM ghcr.io/stackia/rtp2httpd:latest AS rtp_base

# 阶段 2：基于 Alpine 组装全家桶
FROM alpine:latest
LABEL maintainer="ydydid"

# 安装基础工具、Python 环境、定时任务，以及预编译的 py3-lxml 库
RUN apk add --no-cache python3 py3-pip py3-lxml curl tzdata crontabs bash \
    && rm -rf /var/cache/apk/*

ENV TZ=Asia/Shanghai
WORKDIR /data

# 🚀 【修正吸收入 Dockerfile】完美注入 udhcpc 必须的基础回调脚本，确保拨号后 IP 能成功绑定到网卡
RUN mkdir -p /usr/share/udhcpc \
    && echo -e '#!/bin/sh\n[ "$1" = "bound" ] && ip addr add $ip/$mask dev $interface' > /usr/share/udhcpc/default.script \
    && chmod +x /usr/share/udhcpc/default.script

# 复制 rtp2httpd 可执行文件到系统路径
COPY --from=rtp_base /usr/local/bin/rtp2httpd /usr/local/bin/rtp2httpd

# 安装纯 Python 依赖库
RUN pip install --no-cache-dir requests beautifulsoup4 --break-system-packages

# 配置定时任务
RUN echo "5 6 * * * cd /data && python3 gdctiptv.py > /proc/1/fd/1 2>&1" > /etc/mix_cron

# 最终的启动命令（CMD）：
# 1. 载入定时任务
# 2. 强制使用 eth0 发起带 Option 鉴权的 DHCP 请求。（去掉 -R，容器内默认网关锁定 IPTV）
# 3. 循环检测网卡，直到 eth0 真正绑定上私网 IP 后，放行 python3
# 4. 后台启动 crond 守护进程
# 5. 启动 rtp2httpd：将固化的性能优化参数、关闭自带更新参数全部内置，网卡与安全 Token 使用变量动态读取！
CMD crontab /etc/mix_cron \
    && udhcpc -i eth0 -n -x hostname:"$OPT_12" -x 0x3d:"01$OPT_61" -V "$OPT_60" \
    && echo "等待 IPTV 网络拨号就绪..." && while ! ip -4 addr show eth0 | grep -q 'inet '; do sleep 1; done \
    && python3 gdctiptv.py \
    && crond -l 2 \
    && rtp2httpd \
       --external-m3u "$M3U_PATH" \
       --external-m3u-update-interval 0 \
       --upstream-interface "$LAN_NET" \
       --upstream-interface-fcc "$IPTV_NET" \
       --upstream-interface-rtsp "$IPTV_NET" \
       --upstream-interface-multicast "$IPTV_NET" \
       --upstream-interface-http "$LAN_NET" \
       --buffer-pool-max-size 65536 \
       --udp-rcvbuf-size 16777216 \
       --noconfig \
       --verbose "$VERBOSE_LEVEL" \
       --listen "$LISTEN_PORT" \
       --maxclients 10 \
       --workers 2 \
       --xff \
       --r2h-token "$R2H_TOKEN"
