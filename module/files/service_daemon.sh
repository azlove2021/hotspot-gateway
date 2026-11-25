#!/system/bin/sh
# 开机拉起网关守护进程（只启动命令通道，不启用任何代理规则）
sleep 25
RUNNING=$(ps -A -o ARGS 2>/dev/null | awk '$1=="sh" && $2=="/data/adb/gateway/daemon.sh"' | wc -l)
if [ "$RUNNING" -eq 0 ]; then
  setsid sh /data/adb/gateway/daemon.sh >/dev/null 2>&1 &
fi
