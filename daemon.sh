#!/system/bin/sh
# 热点网关 root 守护：给 App 提供命令执行通道 + 心跳保活
# 协议：App 写 files/seq（序号）与 files/cmd（命令）；守护执行后写 files/out 并更新 files/done
D=/data/adb/gateway
APPD=/data/data/com.dsh.gateway/files
LOG=$D/daemon.log
HB=$APPD/heartbeat

log(){ printf '[%s] %s\n' "$(date '+%F %T')" "$*" >> $LOG; }

mkdir -p "$APPD" 2>/dev/null
chmod 777 "$APPD" 2>/dev/null
# 单实例保护
PIDFILE=$D/daemon.pid
if [ -f "$PIDFILE" ]; then
  OLD=$(cat "$PIDFILE" 2>/dev/null)
  if [ -n "$OLD" ] && [ "$OLD" != "$$" ] && kill -0 "$OLD" 2>/dev/null; then
    log "已有实例 pid=$OLD，本实例退出"
    exit 0
  fi
fi
echo $$ > "$PIDFILE"
log "daemon 启动 pid=$$"

TICK=0
LAST_SEQ=$(cat "$APPD/seq" 2>/dev/null)
case "$LAST_SEQ" in ''|*[!0-9]*) LAST_SEQ=0 ;; esac

while true; do
  sleep 1

  # ---------- 命令通道 ----------
  if [ -f "$APPD/cmd" ] && [ -f "$APPD/seq" ]; then
    SEQ=$(cat "$APPD/seq" 2>/dev/null)
    case "$SEQ" in
      ''|*[!0-9]*) SEQ=0 ;;
    esac
    if [ "$SEQ" -gt "$LAST_SEQ" ] 2>/dev/null; then
      LAST_SEQ=$SEQ
      CMD=$(cat "$APPD/cmd" 2>/dev/null)
      if [ -n "$CMD" ]; then
        OUT=$(sh -c "$CMD" 2>&1)
        printf '%s' "$OUT" > "$APPD/out"
        chmod 666 "$APPD/out" 2>/dev/null
        printf '%s' "$SEQ" > "$APPD/done"
        chmod 666 "$APPD/done" 2>/dev/null
        log "seq=$SEQ cmd=$(printf '%s' "$CMD" | head -c 60)"
      fi
    fi
  fi

  # ---------- 热点 IPv6 守卫（每 10 秒；系统重开热点会恢复 IPv6）----------
  if [ $((TICK % 10)) -eq 0 ] && [ -x "$D/hotspot_v6guard.sh" ]; then
    sh $D/hotspot_v6guard.sh 2>/dev/null
  fi

  # ---------- 订阅定时更新（每 60 秒检查一次是否到期）----------
  TICK=$((TICK + 1))
  if [ $((TICK % 60)) -eq 0 ] && [ -x "$D/sub_manager.sh" ]; then
    sh $D/sub_manager.sh check >> $LOG 2>&1
  fi

  # ---------- 心跳看护：App 关了就把网络恢复 ----------
  if pgrep -x mihomo >/dev/null 2>&1 && [ -f "$D/heartbeat_watch" ]; then
    if [ -f "$HB" ]; then
      MT=$(stat -c %Y "$HB" 2>/dev/null)
      case "$MT" in ''|*[!0-9]*) MT=0 ;; esac
      AGE=$(( $(date +%s) - MT ))
      if [ "$AGE" -gt 90 ]; then
        log "心跳超时 ${AGE}s → 恢复默认网络"
        sh $D/panic.sh >> $LOG 2>&1
      fi
    fi
  fi
done
