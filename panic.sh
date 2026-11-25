#!/system/bin/sh
# 紧急恢复：清空所有网关规则，恢复本机网络
D=/data/adb/gateway
M="mangle"
log(){ printf '[%s] %s\n' "$(date '+%F %T')" "$*" >> $D/gateway.log; }

# 1) 走官方清理
sh $D/tproxy.sh -d $D stop >/dev/null 2>&1

# 2) 兜底清链
for c in PROXY_PREROUTING PROXY_OUTPUT PROXY_INTERFACE BYPASS_INTERFACE BYPASS_IP \
         DNS_HIJACK_PRE DNS_HIJACK_OUT MAC_CHAIN BYPASS_MAC PROXY_MAC; do
  for fam in iptables ip6tables; do
    $fam -t $M -F "$c" 2>/dev/null
    $fam -t $M -D PREROUTING -p tcp -j "$c" 2>/dev/null
    $fam -t $M -D PREROUTING -p udp -j "$c" 2>/dev/null
    $fam -t $M -D OUTPUT -p tcp -j "$c" 2>/dev/null
    $fam -t $M -D OUTPUT -p udp -j "$c" 2>/dev/null
    $fam -t $M -X "$c" 2>/dev/null
  done
done

# 3) 清 TPROXY 直跳残留（不动 Android 自己的 mangle 规则）
for fam in iptables ip6tables; do
  for p in tcp udp; do
    while $fam -t $M -D PREROUTING -p $p -j TPROXY 2>/dev/null; do :; done
    while $fam -t $M -D OUTPUT -p $p -j TPROXY 2>/dev/null; do :; done
  done
done

# 4) 清策略路由
ip rule del fwmark 20 table 2025 2>/dev/null
ip rule del fwmark 20 2>/dev/null
ip -6 rule del fwmark 20 table 2025 2>/dev/null
ip route flush table 2025 2>/dev/null
ip -6 route flush table 2025 2>/dev/null

# 5) 恢复 IPv6（脚本可能把 disable_ipv6 置 1）
for f in /proc/sys/net/ipv6/conf/all/disable_ipv6 /proc/sys/net/ipv6/conf/default/disable_ipv6; do
  [ -w "$f" ] && echo 0 > "$f" 2>/dev/null
done

# 5.5) 清热点 DNS 劫持规则
for ifc in wlan0 wlan1 wlan2 ap0 ap1 swlan0 softap0; do
  while iptables -t nat -D PREROUTING -i "$ifc" -m udp -p udp --dport 53 -j REDIRECT --to-ports 5354 2>/dev/null; do :; done
  while iptables -t nat -D PREROUTING -i "$ifc" -m tcp -p tcp --dport 53 -j REDIRECT --to-ports 5354 2>/dev/null; do :; done
done

rm -f $D/heartbeat_watch

# 6) 停核心
pkill -x mihomo 2>/dev/null
pkill -f "$D/watchdog.sh" 2>/dev/null

log "panic: 已清空规则并恢复网络"
echo "网络已恢复：mangle 表已清空、策略路由已删除、mihomo 已停止"
