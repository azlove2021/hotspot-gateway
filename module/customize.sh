#!/system/bin/sh
SKIPUNZIP=0

ui_print "- 热点网关：部署运行环境"

mkdir -p /data/adb/gateway
cp -f "$MODPATH/files/mihomo" /data/adb/gateway/mihomo 2>/dev/null
cp -f "$MODPATH/files/"*.sh /data/adb/gateway/ 2>/dev/null
cp -f "$MODPATH/files/GEOIP.dat" "$MODPATH/files/GEOSITE.dat" "$MODPATH/files/ASN.mmdb" /data/adb/gateway/ 2>/dev/null

# 只在没有配置时放模板，避免覆盖已有节点
if [ ! -f /data/adb/gateway/config.yaml ]; then
  cp -f "$MODPATH/files/config.template.yaml" /data/adb/gateway/config.yaml
  ui_print "- 已写入默认配置（需在 App 里导入订阅）"
fi

chmod 755 /data/adb/gateway/mihomo 2>/dev/null
chmod 755 /data/adb/gateway/*.sh 2>/dev/null
chmod 600 /data/adb/gateway/config.yaml 2>/dev/null

# 开机守护
mkdir -p /data/adb/service.d
cp -f "$MODPATH/files/service_daemon.sh" /data/adb/service.d/gw_daemon.sh 2>/dev/null
chmod 755 /data/adb/service.d/gw_daemon.sh 2>/dev/null

# 立刻拉起守护
if ! pgrep -f "/data/adb/gateway/daemon.sh" >/dev/null 2>&1; then
  setsid sh /data/adb/gateway/daemon.sh >/dev/null 2>&1 &
fi

ui_print "- 部署完成：/data/adb/gateway"
ui_print "- 下一步：安装 热点网关.apk，打开后导入订阅并点启动"
