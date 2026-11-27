#!/system/bin/sh
# 热点 IPv6 守卫
# 系统每次重开热点都会把 disable_ipv6 重置为 0，而 iPhone/iPad 优先走 IPv6
# 会直接绕过 TPROXY（国内能上、国外不通）。默认持续禁用，可在 App 里关掉。
# 用法：hotspot_v6guard.sh [on|off|status]
D=/data/adb/gateway
SW=$D/v6guard.conf

find_hotspot() {
  for i in wlan2 ap0 ap1 swlan0 softap0 wlan1; do
    if ip -4 addr show dev "$i" 2>/dev/null | grep -q "inet "; then
      echo "$i"; return 0
    fi
  done
  return 1
}

switch_state() {
  cat "$SW" 2>/dev/null | tr -d '\r\n' | grep -qx "OFF" && echo "OFF" || echo "ON"
}

case "$1" in
  on)
    echo "ON" > "$SW"; chmod 600 "$SW"
    HIF=$(find_hotspot) && echo 1 > "/proc/sys/net/ipv6/conf/$HIF/disable_ipv6" 2>/dev/null
    echo "[$(date '+%F %T')] IPv6 守卫：已开启" >> "$D/gateway.log"
    echo "OK|on"
    ;;
  off)
    echo "OFF" > "$SW"; chmod 600 "$SW"
    for i in wlan2 ap0 ap1 swlan0 softap0 wlan1; do
      [ -w "/proc/sys/net/ipv6/conf/$i/disable_ipv6" ] && echo 0 > "/proc/sys/net/ipv6/conf/$i/disable_ipv6" 2>/dev/null
    done
    echo "[$(date '+%F %T')] IPv6 守卫：已关闭（热点恢复 IPv6，注意 iPhone 可能绕过代理）" >> "$D/gateway.log"
    echo "OK|off"
    ;;
  status)
    echo "$(switch_state)"
    ;;
  *)
    # 无参数 = 定时守卫调用
    [ "$(switch_state)" = "OFF" ] && exit 0
    HIF=$(find_hotspot) || exit 0
    NEIGH=$(ip neigh show dev "$HIF" 2>/dev/null | grep -cE '^[0-9]+\.')
    F=/proc/sys/net/ipv6/conf/$HIF/disable_ipv6
    if [ -w "$F" ] && [ "$(cat "$F" 2>/dev/null)" != "1" ]; then
      echo 1 > "$F" 2>/dev/null && \
        echo "[$(date '+%F %T')] $HIF 的 IPv6 被系统恢复，已重新禁用（客户端 $NEIGH 台）" >> "$D/gateway.log"
    fi
    ;;
esac
