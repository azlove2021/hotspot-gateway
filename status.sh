#!/system/bin/sh
# 一次性输出网关状态（JSON），供 App 单次调用
D=/data/adb/gateway
API=http://127.0.0.1:9095

RUN=0
pgrep -x mihomo >/dev/null 2>&1 && RUN=1

# 热点接口
IF=""
for i in ap0 ap1 wlan2 wlan1 swlan0 softap0; do
  if ip -4 addr show dev "$i" 2>/dev/null | grep -q "inet "; then IF=$i; break; fi
done
[ -z "$IF" ] && IF=$(ip -o -4 addr show 2>/dev/null | awk '$2 ~ /^wlan/ {print $2; exit}')

NET="-"
if [ -n "$IF" ]; then
  IP4=$(ip -4 -o addr show dev "$IF" 2>/dev/null | awk '{print $4}' | head -1)
  [ -n "$IP4" ] && NET=$(echo "$IP4" | cut -d/ -f1 | awk -F. '{print $1"."$2"."$3".0/24"}')
fi

# 热点 IPv6 状态：1=已禁用 0=启用
V6S="unknown"
V6A=""
if [ -n "$IF" ]; then
  V6S=$(cat /proc/sys/net/ipv6/conf/$IF/disable_ipv6 2>/dev/null)
  [ "$V6S" = "1" ] && V6S="disabled" || V6S="enabled"
  V6A=$(ip -6 -o addr show dev "$IF" 2>/dev/null | awk '$4 ~ /^2|^3/ {print $4}' | head -1)
fi

# 所有网卡（IPv4 + IPv6 全局地址）
IFJ=$(ip -o -4 addr show 2>/dev/null | grep -v ' lo ' | awk '{
  n=$2; ip=$4;
  printf "%s{\"n\":\"%s\",\"ip\":\"%s\"}", (c>0?",":""), n, ip; c++
}')

# 客户端（IPv4 + MAC）
CLJ=""
CLIENTS=0
if [ -n "$IF" ]; then
  CLIENTS=$(ip neigh show dev "$IF" 2>/dev/null | grep -E '^[0-9]+\.' | grep -c lladdr)
  CLJ=$(ip neigh show dev "$IF" 2>/dev/null | grep -E '^[0-9]+\.' | grep lladdr | awk '{
    printf "%s{\"ip\":\"%s\",\"mac\":\"%s\"}", (c>0?",":""), $1, $3; c++
  }')
fi

# 启动阶段（gateway.sh 写入）
STAGE=""; SMSG=""; SEXIP=""
if [ -f "$D/startup.state" ]; then
  STAGE=$(grep -oE '^STAGE=.*' "$D/startup.state" 2>/dev/null | cut -d= -f2-)
  SMSG=$(grep -oE '^MSG=.*' "$D/startup.state" 2>/dev/null | cut -d= -f2-)
  SEXIP=$(grep -oE '^EXIT_IP=.*' "$D/startup.state" 2>/dev/null | cut -d= -f2-)
fi

V6G="ON"
grep -qx "OFF" "$D/v6guard.conf" 2>/dev/null && V6G="OFF"

SCOPE="仅热点"
grep -qE '^PROXY_WIFI=1' $D/tproxy.conf 2>/dev/null && SCOPE="本机 + 热点"

UP=0; DOWN=0; CONNS=0
HOSTS=""
if [ "$RUN" = "1" ]; then
  J=$(curl -s -m 3 $API/connections 2>/dev/null)
  if [ -n "$J" ]; then
    UP=$(printf '%s' "$J" | grep -oE '"uploadTotal":[0-9]+' | head -1 | cut -d: -f2)
    DOWN=$(printf '%s' "$J" | grep -oE '"downloadTotal":[0-9]+' | head -1 | cut -d: -f2)
    CONNS=$(printf '%s' "$J" | grep -oc '"id":')
    # 提取 客户端IP + 访问域名，去重
    HOSTS=$(printf '%s' "$J" | tr '{' '\n' | awk -F'"' '
      /"sourceIP"/{
        ip=""; host="";
        for(i=1;i<=NF;i++){
          if($i=="sourceIP") ip=$(i+2);
          if($i=="host") host=$(i+2);
        }
        if(ip!="" && host!="") print ip"|"host
      }' | sort -u | awk -F'|' '{
        printf "%s{\"ip\":\"%s\",\"h\":\"%s\"}", (c>0?",":""), $1, $2; c++
      }')
  fi
fi
[ -z "$UP" ] && UP=0
[ -z "$DOWN" ] && DOWN=0
[ -z "$CONNS" ] && CONNS=0

printf '{"running":%s,"iface":"%s","net":"%s","ipv6":"%s","ipv6addr":"%s","clients":%s,"scope":"%s","up":%s,"down":%s,"conns":%s,"stage":"%s","msg":"%s","exitip":"%s","v6guard":"%s","ifaces":[%s],"assoc":[%s],"hosts":[%s]}\n' \
  "$RUN" "$IF" "$NET" "$V6S" "$V6A" "$CLIENTS" "$SCOPE" "$UP" "$DOWN" "$CONNS" "$STAGE" "$SMSG" "$SEXIP" "$V6G" "$IFJ" "$CLJ" "$HOSTS"
