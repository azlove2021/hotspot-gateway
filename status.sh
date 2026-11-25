#!/system/bin/sh
# 一次性输出网关状态（JSON），供 App 单次调用
D=/data/adb/gateway
API=http://127.0.0.1:9095

RUN=0
pgrep -x mihomo >/dev/null 2>&1 && RUN=1

# 热点接口（优先 Android 热点命名）
IF=""
for i in ap0 ap1 wlan2 wlan1 swlan0 softap0; do
  if ip -4 addr show dev "$i" 2>/dev/null | grep -q "inet "; then IF=$i; break; fi
done
[ -z "$IF" ] && IF=$(ip -o -4 addr show 2>/dev/null | awk '$2 ~ /^wlan/ {print $2; exit}')

NET="-"
if [ -n "$IF" ]; then
  IP4=$(ip -4 -o addr show dev "$IF" 2>/dev/null | awk '{print $4}' | head -1)
  if [ -n "$IP4" ]; then
    NET=$(echo "$IP4" | cut -d/ -f1 | awk -F. '{print $1"."$2"."$3".0/24"}')
  fi
fi

# 所有网卡（IPv4）
IFJ=$(ip -o -4 addr show 2>/dev/null | grep -v ' lo ' | awk '{
  n=$2; ip=$4;
  printf "%s{\"n\":\"%s\",\"ip\":\"%s\"}", (c>0?",":""), n, ip; c++
}')

# 热点客户端（IPv4 + MAC）
CLJ=""
CLIENTS=0
if [ -n "$IF" ]; then
  CLIENTS=$(ip neigh show dev "$IF" 2>/dev/null | grep -E '^[0-9]+\.' | grep -c lladdr)
  CLJ=$(ip neigh show dev "$IF" 2>/dev/null | grep -E '^[0-9]+\.' | grep lladdr | awk '{
    printf "%s{\"ip\":\"%s\",\"mac\":\"%s\"}", (c>0?",":""), $1, $3; c++
  }')
fi

SCOPE="仅热点"
grep -qE '^PROXY_WIFI=1' $D/tproxy.conf 2>/dev/null && SCOPE="本机 + 热点"

UP=0; DOWN=0; CONNS=0
if [ "$RUN" = "1" ]; then
  J=$(curl -s -m 3 $API/connections 2>/dev/null)
  if [ -n "$J" ]; then
    UP=$(printf '%s' "$J" | grep -oE '"uploadTotal":[0-9]+' | head -1 | cut -d: -f2)
    DOWN=$(printf '%s' "$J" | grep -oE '"downloadTotal":[0-9]+' | head -1 | cut -d: -f2)
    CONNS=$(printf '%s' "$J" | grep -oc '"id":')
  fi
fi
[ -z "$UP" ] && UP=0
[ -z "$DOWN" ] && DOWN=0
[ -z "$CONNS" ] && CONNS=0

printf '{"running":%s,"iface":"%s","net":"%s","clients":%s,"scope":"%s","up":%s,"down":%s,"conns":%s,"ifaces":[%s],"assoc":[%s]}\n' \
  "$RUN" "$IF" "$NET" "$CLIENTS" "$SCOPE" "$UP" "$DOWN" "$CONNS" "$IFJ" "$CLJ"
