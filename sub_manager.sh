#!/system/bin/sh
# 订阅管理：记录/查询/定时更新
# 用法：
#   sub_manager.sh save <url> [名称] [间隔秒]
#   sub_manager.sh info
#   sub_manager.sh check      # 到期则更新（给 daemon 定时调用）
#   sub_manager.sh update     # 立即更新
D=/data/adb/gateway
CONF=$D/subscription.conf

mask_url() {
  # 隐藏 token：只保留协议+域名
  echo "$1" | sed -E 's#(https?://[^/]+).*#\1/***#'
}

load() {
  [ -f "$CONF" ] || return 1
  . "$CONF"
  return 0
}

save() {
  URL="$1"
  NAME="$2"
  INT="$3"
  [ -z "$INT" ] && INT=3600
  [ -z "$NAME" ] && NAME=$(echo "$URL" | sed -E 's#https?://([^/]+).*#\1#')
  {
    echo "SUB_URL='$URL'"
    echo "SUB_NAME='$NAME'"
    echo "SUB_INTERVAL=$INT"
    echo "SUB_LAST=$(date +%s)"
    echo "SUB_COUNT=${4:-0}"
  } > "$CONF"
  chmod 600 "$CONF"
}

do_update() {
  load || { echo "ERR|没有已保存的订阅"; return 2; }
  echo "更新订阅: $SUB_NAME"
  OUT=$(sh $D/import_sub.sh "$SUB_URL" 2>&1)
  echo "$OUT" | tail -5
  CNT=$(echo "$OUT" | grep -oE '节点 [0-9]+ 个' | grep -oE '[0-9]+' | head -1)
  [ -z "$CNT" ] && CNT=0
  save "$SUB_URL" "$SUB_NAME" "$SUB_INTERVAL" "$CNT"
  sh $D/gateway.sh restart >/dev/null 2>&1
  echo "OK|已更新，节点 $CNT 个"
}

cmd="$1"
case "$cmd" in
  save)
    save "$2" "$3" "$4" "$5"
    echo "OK|已保存订阅：$3"
    ;;
  info)
    if load; then
      NOW=$(date +%s)
      NEXT=$((SUB_LAST + SUB_INTERVAL))
      UP=0; DOWN=0; TOTAL=0; EXPIRE=0
      if [ -f "$D/.sub_userinfo" ]; then
        UI=$(cat "$D/.sub_userinfo" 2>/dev/null)
        UP=$(echo "$UI" | grep -oE 'upload=[0-9]+' | cut -d= -f2)
        DOWN=$(echo "$UI" | grep -oE 'download=[0-9]+' | cut -d= -f2)
        TOTAL=$(echo "$UI" | grep -oE 'total=[0-9]+' | cut -d= -f2)
        EXPIRE=$(echo "$UI" | grep -oE 'expire=[0-9]+' | cut -d= -f2)
      fi
      [ -z "$UP" ] && UP=0
      [ -z "$DOWN" ] && DOWN=0
      [ -z "$TOTAL" ] && TOTAL=0
      [ -z "$EXPIRE" ] && EXPIRE=0
      WEB=""
      [ -f "$D/.sub_webpage" ] && WEB=$(cat "$D/.sub_webpage" 2>/dev/null)
      printf '{"name":"%s","host":"%s","web":"%s","count":%s,"last":%s,"interval":%s,"next":%s,"now":%s,"up":%s,"down":%s,"total":%s,"expire":%s}\n' \
        "$SUB_NAME" "$(mask_url "$SUB_URL")" "$WEB" "${SUB_COUNT:-0}" "${SUB_LAST:-0}" "${SUB_INTERVAL:-0}" "$NEXT" "$NOW" "$UP" "$DOWN" "$TOTAL" "$EXPIRE"
    else
      echo '{"name":"","host":"","web":"","count":0,"last":0,"interval":0,"next":0,"now":0,"up":0,"down":0,"total":0,"expire":0}'
    fi
    ;;
  check)
    load || exit 0
    NOW=$(date +%s)
    [ "${SUB_INTERVAL:-0}" -le 0 ] && exit 0
    DUE=$(( ${SUB_LAST:-0} + SUB_INTERVAL ))
    if [ "$NOW" -ge "$DUE" ]; then
      do_update
    fi
    ;;
  setint)
    load || { echo "ERR|没有已保存的订阅"; exit 2; }
    save "$SUB_URL" "$SUB_NAME" "$2" "$SUB_COUNT"
    echo "OK|间隔已设为 $2 秒"
    ;;
  update)
    do_update
    ;;
  *)
    echo "用法: $0 save|info|check|update"
    ;;
esac
