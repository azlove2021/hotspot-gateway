#!/system/bin/sh
# 热点 IPv6 守卫：系统每次重开热点都会把 disable_ipv6 重置为 0，
# 而 iPhone/iPad 会优先走 IPv6 直接绕过 TPROXY（现象：国内能上、国外不通）。
# 由 daemon 每 10 秒调用一次，发现热点接口 v6 被打开就重新关掉。
D=/data/adb/gateway
CHANGED=0

find_hotspot() {
  for i in wlan2 ap0 ap1 swlan0 softap0 wlan1; do
    if ip -4 addr show dev "$i" 2>/dev/null | grep -q "inet "; then
      echo "$i"
      return 0
    fi
  done
  return 1
}

HIF=$(find_hotspot) || exit 0

# 只处理有客户端的热点接口，避免误伤普通 WiFi
NEIGH=$(ip neigh show dev "$HIF" 2>/dev/null | grep -cE '^[0-9]+\.')
V6FILE=/proc/sys/net/ipv6/conf/$HIF/disable_ipv6

if [ -w "$V6FILE" ] && [ "$(cat "$V6FILE" 2>/dev/null)" != "1" ]; then
  echo 1 > "$V6FILE" 2>/dev/null && CHANGED=1
fi

[ "$CHANGED" = "1" ] && echo "[$(date '+%F %T')] $HIF 的 IPv6 被系统恢复，已重新禁用（客户端 $NEIGH 台）" >> "$D/gateway.log"
exit 0
