#!/system/bin/sh
# 守护：mihomo 挂了/端口消失/国内网络连续失败 → 自动 panic 恢复
D=/data/adb/gateway
LOG=$D/watchdog.log
wlog(){ printf '[%s] %s\n' "$(date '+%F %T')" "$*" >> $LOG; }

wlog "watchdog 启动"
FAIL=0
N=0
while true; do
  sleep 5

  # 网关已被人为停止 → 退出
  [ -f "$D/stopping" ] && { wlog "收到停止标记，退出"; exit 0; }

  # 核心进程
  if ! pgrep -x mihomo >/dev/null 2>&1; then
    wlog "mihomo 进程消失 → 自动恢复"
    sh $D/panic.sh keep >> $LOG 2>&1
    exit 0
  fi

  # TPROXY 端口
  if ! ss -tln 2>/dev/null | grep -q ':7895'; then
    wlog "tproxy 端口 7895 消失 → 自动恢复"
    sh $D/panic.sh >> $LOG 2>&1
    exit 0
  fi

  # 每 15 秒测一次国内直连（防止规则把本机打瘸）
  N=$((N + 1))
  if [ $((N % 3)) -eq 0 ]; then
    code=$(curl -s -m 6 -o /dev/null -w '%{http_code}' http://www.baidu.com 2>/dev/null)
    if [ "$code" = "200" ] || [ "$code" = "301" ] || [ "$code" = "302" ]; then
      FAIL=0
    else
      FAIL=$((FAIL + 1))
      wlog "国内连通性异常（第 $FAIL 次，code=$code）"
      if [ "$FAIL" -ge 2 ]; then
        wlog "连续异常 → 自动恢复"
        sh $D/panic.sh >> $LOG 2>&1
        exit 0
      fi
    fi
  fi
done
