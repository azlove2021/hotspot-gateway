#!/system/bin/sh
# 导入 Clash / mihomo 订阅：替换 config.yaml 里的 proxies 段
D=/data/adb/gateway
CFG=$D/config.yaml
TMP=$D/sub_raw.yaml
NEW=$D/sub_proxies.txt
URL="$1"

[ -z "$URL" ] && { echo "ERR 缺少订阅地址"; exit 1; }

echo "下载: $URL"
curl -s -L -m 40 -A "clash-verge/v2.4.2" "$URL" -o "$TMP" || { echo "ERR 下载失败"; exit 1; }
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
echo "OK 已导入，配置中节点关键词条数: $CNT"
echo "重启网关生效：gateway.sh restart"
