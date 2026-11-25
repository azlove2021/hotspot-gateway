#!/system/bin/sh
# 守护进程管理：start / stop / status
D=/data/adb/gateway
PIDFILE=$D/daemon.pid

list_pids(){
  ps -A -o PID,ARGS 2>/dev/null | grep -F "sh $D/daemon.sh" | grep -v grep | awk '{print $1}'
}

case "$1" in
  start)
    N=$(list_pids | wc -l)
    if [ "$N" -gt 0 ]; then
      echo "已在运行: $(list_pids | tr '\n' ' ')"
      exit 0
    fi
    rm -f "$PIDFILE"
    setsid sh "$D/daemon.sh" >/dev/null 2>&1 &
    sleep 2
    echo "已启动: $(cat $PIDFILE 2>/dev/null)"
    ;;
  stop)
    for p in $(list_pids); do kill "$p" 2>/dev/null; done
    sleep 1
    rm -f "$PIDFILE"
    echo "已停止"
    ;;
  status)
    echo "守护进程: $(list_pids | tr '\n' ' ')"
    echo "pidfile: $(cat $PIDFILE 2>/dev/null)"
    echo "mihomo: $(pgrep -x mihomo || echo 未运行)"
    ;;
  *)
    echo "用法: $0 start|stop|status"
    ;;
esac
