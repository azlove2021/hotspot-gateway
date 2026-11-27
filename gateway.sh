#!/system/bin/sh
# A 手机热点网关：mihomo + TPROXY，只代理热点客户端，不碰本机流量
# 用法:
#   gateway.sh start          # 只代理热点（B 手机连上即可用）
#   gateway.sh start --all    # 热点 + 本机 WiFi/移动数据（测试用，会影响本机）
#   gateway.sh stop           # 停止并恢复网络
#   gateway.sh panic          # 强制恢复（异常保命）
#   gateway.sh status
DIR=/data/adb/gateway
TP=$DIR/tproxy.sh
TPL=$DIR/tproxy.conf.tmpl
LOG=$DIR/gateway.log
log(){ printf '[%s] %s\n' "$(date '+%F %T')" "$*" >> $LOG; }

detect_hotspot(){
  for ifc in ap0 ap1 wlan1 wlan2 swlan0 softap0; do
    if ip -4 addr show dev "$ifc" 2>/dev/null | grep -q 'inet '; then
      ip4=$(ip -4 -o addr show dev "$ifc" | awk '{print $4}' | head -1)
      net=$(echo "$ip4" | cut -d/ -f1 | awk -F. '{print $1"."$2"."$3".0/24"}')
      echo "$ifc@$net"
      return 0
    fi
  done
  return 1
}

gen_conf(){
  MODE="$1"
  HS=$(detect_hotspot)
  if [ -n "$HS" ]; then
    HIF=${HS%%@*}; HNET=${HS#*@}
    sed -e "s|^HOTSPOT_INTERFACE=.*|HOTSPOT_INTERFACE=\"$HIF\"|" \
        -e "s|^HOTSPOT_SUBNET_IPV4=.*|HOTSPOT_SUBNET_IPV4=\"$HNET\"|" \
        -e "s|^PROXY_HOTSPOT=.*|PROXY_HOTSPOT=1|" "$TPL" > $DIR/tproxy.conf
    log "热点接口=$HIF 网段=$HNET"
    echo "热点接口: $HIF ($HNET)"
  else
    sed -e "s|^HOTSPOT_INTERFACE=.*|HOTSPOT_INTERFACE=\"wlan0\"|" \
        -e "s|^PROXY_HOTSPOT=.*|PROXY_HOTSPOT=0|" "$TPL" > $DIR/tproxy.conf
    log "未检测到热点接口（先开热点再 start 才能代理热点）"
  fi
  if [ "$MODE" = "all" ]; then
    sed -i -e "s|^PROXY_WIFI=.*|PROXY_WIFI=1|" -e "s|^PROXY_MOBILE=.*|PROXY_MOBILE=1|" $DIR/tproxy.conf
  else
    sed -i -e "s|^PROXY_WIFI=.*|PROXY_WIFI=0|" -e "s|^PROXY_MOBILE=.*|PROXY_MOBILE=0|" $DIR/tproxy.conf
  fi
}

selfcheck(){   # 0=健康 1=整体不通 2=本机被代理但境外不通
  ok_cn=0; ok_out=0
  for i in 1 2 3; do
    c=$(curl -s -m 4 -o /dev/null -w '%{http_code}' http://www.baidu.com 2>/dev/null)
    case "$c" in 200|301|302) ok_cn=1;; esac
    if [ -z "$c" ] || [ "$c" = "000" ]; then
      c2=$(curl -s -m 5 -o /dev/null -w '%{http_code}' https://www.gstatic.com/generate_204 2>/dev/null)
      [ "$c2" = "204" ] && ok_out=1
    else
      c2=$(curl -s -m 5 -o /dev/null -w '%{http_code}' https://www.gstatic.com/generate_204 2>/dev/null)
      [ "$c2" = "204" ] && ok_out=1
    fi
    # 两路都通直接结束；国内通就够了
    [ $ok_cn -eq 1 ] && break
    [ $i -lt 3 ] && sleep 2
  done
  log "自检: 国内=$ok_cn 境外=$ok_out"

  # 国内不通但境外通 → 链路是好的，只是国内探测点抖动，不当作故障
  if [ $ok_cn -eq 0 ] && [ $ok_out -eq 1 ]; then
    log "国内探测失败但境外可达，判定为抖动，不回滚"
    return 0
  fi
  [ $ok_cn -eq 1 ] || return 1
  [ "$MODE_ALL" = "all" ] && [ $ok_out -eq 0 ] && return 2
  return 0
}

start(){
  MODE="$1"
  log "=== start ($MODE) ==="
  # 冻结旧守护；只有存在残留规则时才做全量清理（省 4 秒）
  touch $DIR/stopping
  pkill -f "$DIR/watchdog.sh" 2>/dev/null
  pkill -x mihomo 2>/dev/null
  if iptables -t mangle -L PROXY_PREROUTING -n >/dev/null 2>&1 || ip rule show 2>/dev/null | grep -q 2025; then
    sh $DIR/panic.sh >/dev/null 2>&1
  fi
  rm -f $DIR/stopping

  # 1) 生成配置
  gen_conf "$MODE"

  # 2) 启动核心并等端口
  cd $DIR
  (setsid ./mihomo -d $DIR >> $DIR/run.log 2>&1 </dev/null &)
  i=0
  while [ $i -lt 60 ]; do
    ss -tln 2>/dev/null | grep -q ':7895' && break
    i=$((i + 1))
    usleep 150000 2>/dev/null || sleep 1
  done
  if ! ss -tln 2>/dev/null | grep -q ':7895'; then
    log "核心未就绪，放弃（未改任何规则）"
    pkill -x mihomo 2>/dev/null
    echo "❌ mihomo 启动失败，网络未做任何改动"
    return 1
  fi
  log "mihomo 就绪 pid=$(pgrep -x mihomo)"

  # 3) 应用 TPROXY 规则
  sh $TP -d $DIR start >> $LOG 2>&1

  # 3.5) 热点客户端 DNS 劫持：mangle 主链放行 53，nat 转给 mihomo DNS
  HSIF=$(detect_hotspot)
  if [ -n "$HSIF" ]; then
    HSIF=${HSIF%%@*}
    for proto in udp tcp; do
      # IPv4
      iptables -t mangle -D PREROUTING -i "$HSIF" -p $proto --dport 53 -j RETURN 2>/dev/null
      iptables -t mangle -I PREROUTING 1 -i "$HSIF" -p $proto --dport 53 -j RETURN
      iptables -t nat -D PREROUTING -i "$HSIF" -p $proto --dport 53 -j REDIRECT --to-ports 5354 2>/dev/null
      iptables -t nat -I PREROUTING 1 -i "$HSIF" -p $proto --dport 53 -j REDIRECT --to-ports 5354
      # IPv6（iPhone 走 v6 时必须一起劫持）
      ip6tables -t mangle -D PREROUTING -i "$HSIF" -p $proto --dport 53 -j RETURN 2>/dev/null
      ip6tables -t mangle -I PREROUTING 1 -i "$HSIF" -p $proto --dport 53 -j RETURN 2>/dev/null
      ip6tables -t nat -D PREROUTING -i "$HSIF" -p $proto --dport 53 -j REDIRECT --to-ports 5354 2>/dev/null
      ip6tables -t nat -I PREROUTING 1 -i "$HSIF" -p $proto --dport 53 -j REDIRECT --to-ports 5354 2>/dev/null
    done
    log "DNS 劫持：$HSIF 的 53 → 5354"

    # 关键：禁用热点接口 IPv6。内核没有 ip6tables nat 表，v6 DNS 无法劫持，
    # 而 iPhone/iPad 会优先走 IPv6 从而完全绕过代理（现象：国内能上、国外不通）
    echo 1 > /proc/sys/net/ipv6/conf/$HSIF/disable_ipv6 2>/dev/null
    log "已禁用 $HSIF 的 IPv6（强制客户端走 IPv4，否则 v6 绕过代理）"
  fi

  # 4) 自检 + 失败自动回滚
  MODE_ALL="$MODE"
  selfcheck
  rc=$?
  if [ $rc -eq 1 ]; then
    log "国内网络不通 → 回滚"
    sh $DIR/panic.sh >/dev/null 2>&1
    echo "❌ 自检失败（国内不通），已自动回滚，网络已恢复"
    return 2
  fi
  if [ $rc -eq 2 ]; then
    log "境外不通 → 回滚"
    sh $DIR/panic.sh >/dev/null 2>&1
    echo "❌ 自检失败（节点不通），已自动回滚，网络已恢复"
    return 2
  fi

  touch $DIR/heartbeat_watch

  # 5) 守护
  (setsid sh $DIR/watchdog.sh >> $LOG 2>&1 </dev/null &)
  HS=$(detect_hotspot)
  if [ "$MODE" = "all" ]; then
    echo "✅ 网关已启动（本机 + 热点都走代理）"
  else
    echo "✅ 网关已启动，只代理热点客户端，本机不受影响"
  fi
  [ -n "$HS" ] && echo "   热点接口: ${HS%%@*}  网段: ${HS#*@}" || echo "   ⚠️ 当前没检测到热点，B 手机连上后需再执行一次 restart"
  return 0
}

case "$1" in
  start) start "$2";;
  stop)  touch $DIR/stopping; sh $DIR/panic.sh; echo "已停止";;
  panic) sh $DIR/panic.sh;;
  restart) touch $DIR/stopping; sh $DIR/panic.sh >/dev/null 2>&1; sleep 1; start "$2";;
  status)
    echo "mihomo: $(pgrep -x mihomo || echo 未运行)"
    echo "watchdog: $(pgrep -f watchdog.sh | head -1 || echo 未运行)"
    ss -tln 2>/dev/null | grep -E '7891|7895|9095'
    echo "--- 热点 ---"; detect_hotspot || echo "未检测到热点"
    echo "--- 规则 ---"; iptables -t mangle -S 2>/dev/null | grep -cE 'TPROXY|PROXY_'
    ip rule show | grep 2025 || echo "无策略路由"
    ;;
  *) echo "用法: $0 start [--all] | stop | restart | panic | status";;
esac
