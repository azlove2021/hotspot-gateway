#!/system/bin/sh
# 从 FlClash 的配置里同步节点与策略组到网关
D=/data/adb/gateway
CFG=$D/config.yaml
SRC=/data/data/com.follow.clash/files/config.yaml

[ -f "$SRC" ] || { echo "ERR 找不到 FlClash 配置（$SRC）"; exit 1; }
grep -q "^proxies:" "$SRC" 2>/dev/null || { echo "ERR FlClash 配置里没有 proxies 段"; exit 1; }

cp "$CFG" "$CFG.bak.sync.$(date +%s)" 2>/dev/null

# 1) 提取 FlClash 的 proxies 段
awk '/^proxies:/{f=1} f && /^[a-zA-Z_-]+:/ && !/^proxies:/{f=0} f' "$SRC" > "$D/.fl_proxies"
N=$(grep -c "name:" "$D/.fl_proxies" 2>/dev/null)
[ -z "$N" ] && N=0
[ "$N" -lt 1 ] && { echo "ERR 没从 FlClash 提取到节点"; exit 2; }

# 2) 替换到网关配置
awk -v nf="$D/.fl_proxies" '
  BEGIN { while ((getline l < nf) > 0) np = np l "\n" }
  /^proxies:/ { printf "%s", np; skip = 1; next }
  skip && /^[a-zA-Z_-]+:/ { skip = 0 }
  { if (!skip) print }
' "$CFG" > "$CFG.new" && mv "$CFG.new" "$CFG"

rm -f "$D/.fl_proxies"
chmod 600 "$CFG"

# 3) 重建策略组（必须，否则旧组引用会失效）
sh "$D/rebuild_groups.sh"

echo "OK 已从 FlClash 同步 $N 个节点"
