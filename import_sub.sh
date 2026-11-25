#!/system/bin/sh
# 导入 Clash / mihomo 订阅：替换 config.yaml 里的 proxies 段
D=/data/adb/gateway
CFG=$D/config.yaml
TMP=$D/sub_raw.yaml
NEW=$D/sub_proxies.txt
URL="$1"

[ -z "$URL" ] && { echo "ERR 缺少订阅地址"; exit 1; }

echo "下载: $URL"
HDR=$D/.sub_headers
curl -s -L -m 40 -A "clash-verge/v2.4.2" -D "$HDR" "$URL" -o "$TMP" || { echo "ERR 下载失败"; exit 1; }

# 解析 subscription-userinfo（机场流量：upload/download/total/expire）
UI=$(grep -i "^subscription-userinfo:" "$HDR" 2>/dev/null | head -1 | sed 's/^[^:]*: *//' | tr -d '\r')
if [ -n "$UI" ]; then
  echo "$UI" > "$D/.sub_userinfo"
  echo "流量信息: $UI"
fi
# 机场官网（部分机场提供）
WU=$(grep -i "^profile-web-page-url:" "$HDR" 2>/dev/null | head -1 | sed 's/^[^:]*: *//' | tr -d '\r')
[ -n "$WU" ] && echo "$WU" > "$D/.sub_webpage"
rm -f "$HDR"
SIZE=$(wc -c < "$TMP" 2>/dev/null)
echo "大小: $SIZE 字节"
[ "$SIZE" -lt 40 ] && { echo "ERR 内容过短，可能下载失败"; head -c 200 "$TMP"; exit 1; }

# base64 订阅先解码
if ! grep -q "^proxies:" "$TMP" 2>/dev/null; then
  if head -c 400 "$TMP" | grep -qE "^[A-Za-z0-9+/=]{20,}$"; then
    base64 -d "$TMP" > "$TMP.dec" 2>/dev/null && mv "$TMP.dec" "$TMP"
    echo "已解码 base64"
  fi
fi

# 仍不是 clash yaml → 尝试从 base64 里找
if ! grep -q "^proxies:" "$TMP" 2>/dev/null; then
  echo "ERR 不是 Clash/mihomo 格式订阅（需要 yaml，含 proxies:）"
  head -c 160 "$TMP"
  exit 2
fi

# 提取 proxies 段
awk '/^proxies:/{f=1} f && /^[a-zA-Z_-]+:/ && !/^proxies:/{f=0} f' "$TMP" > "$NEW"
LINES=$(wc -l < "$NEW")
echo "节点行数: $LINES"
[ "$LINES" -lt 2 ] && { echo "ERR 没解析出节点"; exit 3; }

cp "$CFG" "$CFG.bak.$(date +%s)"

# 替换 config.yaml 的 proxies 段
awk -v newfile="$NEW" '
  BEGIN { while ((getline l < newfile) > 0) np = np l "\n" }
  /^proxies:/ { printf "%s", np; skip = 1; next }
  skip && /^[a-zA-Z_-]+:/ { skip = 0 }
  { if (!skip) print }
' "$CFG" > "$CFG.new" && mv "$CFG.new" "$CFG"

chmod 600 "$CFG"
CNT=$(grep -c "^  - {name:" "$CFG" 2>/dev/null || grep -c "^  - name:" "$CFG" 2>/dev/null)
echo "已替换 proxies 段，节点条目: $CNT"

# 关键：重建策略组，否则旧组引用不到新节点名会导致整个配置解析失败
if [ -x "$D/rebuild_groups.sh" ]; then
  sh "$D/rebuild_groups.sh"
  echo "OK 导入完成，策略组已重建"
else
  echo "警告：rebuild_groups.sh 不存在，策略组可能引用失效"
fi
echo "重启网关生效：gateway.sh restart"
