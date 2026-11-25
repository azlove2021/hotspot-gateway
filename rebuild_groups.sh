#!/system/bin/sh
# 按当前 proxies 段重建 proxy-groups，保证组内只引用真实存在的节点
D=/data/adb/gateway
CFG=$D/config.yaml
TMP=$D/.new_groups

[ -f "$CFG" ] || { echo "ERR 找不到 config.yaml"; exit 1; }

# 1) 提取节点名（跳过流量/到期这类信息节点）
NAMES=$(sed -n '/^proxies:/,/^[a-zA-Z_-]*:/p' "$CFG" \
  | grep -oE "name: [^,}]+" \
  | sed "s/^name: //" \
  | sed "s/^'//; s/'$//" \
  | sed 's/^"//; s/"$//' \
  | grep -vE "剩余流量|套餐到期|官网|过期|到期|流量" \
  | awk 'NF' )

CNT=$(printf '%s\n' "$NAMES" | awk 'NF' | wc -l)
[ "$CNT" -lt 1 ] && { echo "ERR 没有解析到有效节点"; exit 2; }

LIST=$(printf '%s\n' "$NAMES" | awk 'NF' | paste -sd, - 2>/dev/null)
[ -z "$LIST" ] && LIST=$(printf '%s\n' "$NAMES" | awk 'NF{printf "%s%s", (n++?",":""), $0}')

echo "有效节点 $CNT 个"

# 2) 生成策略组
{
  echo "proxy-groups:"
  echo "  - {name: 节点选择, type: select, proxies: [自动选择, $LIST]}"
  echo "  - {name: 自动选择, type: url-test, proxies: [$LIST], url: 'https://www.gstatic.com/generate_204', interval: 300, tolerance: 50, lazy: false}"
  for g in ChatGPT Gemini Netflix Telegram Twitter TikTok WhatsApp Copilot 谷歌服务; do
    echo "  - {name: $g, type: select, proxies: [节点选择]}"
  done
  for g in 哔哩哔哩 抖音 苹果服务 微软服务 Steam; do
    echo "  - {name: $g, type: select, proxies: [DIRECT, 节点选择]}"
  done
  echo "  - {name: 磁力下载, type: select, proxies: [DIRECT]}"
} > "$TMP"

# 3) 替换 proxy-groups 段
awk -v nf="$TMP" '
  BEGIN { while ((getline l < nf) > 0) ng = ng l "\n" }
  /^proxy-groups:/ { printf "%s", ng; skip = 1; next }
  skip && /^[a-zA-Z_-]+:/ { skip = 0 }
  { if (!skip) print }
' "$CFG" > "$CFG.new" && mv "$CFG.new" "$CFG"

rm -f "$TMP"
chmod 600 "$CFG"
echo "OK 策略组已重建（主组：节点选择 / 自动选择）"
