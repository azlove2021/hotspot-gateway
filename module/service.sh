#!/system/bin/sh
# 开机拉起守护进程（只开命令通道，不启用任何代理规则）
sleep 25
if ! pgrep -f "/data/adb/gateway/daemon.sh" >/dev/null 2>&1; then
  setsid sh /data/adb/gateway/daemon.sh >/dev/null 2>&1 &
fi
