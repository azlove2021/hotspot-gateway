# 热点网关 · Hotspot Gateway

把一台 root 过的 Android 手机变成**热点翻墙网关**：A 手机开热点，B 手机连上就能直接访问境外网络，**B 端零配置**。

```
B 手机 ──WiFi──> A 手机热点(wlan2) ──TPROXY──> mihomo ──> 机场节点 ──> Internet
                        │
                   root daemon + 控制 App
```

## 特性

- **真透明代理**：iptables TPROXY 接管热点接口的 TCP + UDP，DNS 劫持到内核内置 DNS（fake-ip），不依赖客户端设代理
- **只代理热点**：本机 WiFi / 移动数据完全不碰，出问题也不会把自己搞断网
- **四层保护**：启动自检回滚 / 心跳看护 / 进程看护 / 重启即恢复
- **控制 App**：FlClash 风格的仪表盘、节点管理（订阅导入、切换、测延迟）、设置、诊断（B 手机连通性、测速）

## 组成

| 文件 | 作用 |
|---|---|
| `gateway.sh` | 启停封装：热点接口探测 → 生成配置 → 起内核 → 装规则 → 自检回滚 |
| `daemon.sh` | root 守护：App 命令通道（私有目录四文件协议）+ 心跳看护 |
| `watchdog.sh` | 运行时看护：内核/端口/连通性异常自动恢复 |
| `panic.sh` | 一键恢复：清 mangle、删策略路由、停内核、恢复 IPv6 |
| `status.sh` | 一次性输出 JSON 状态 |
| `import_sub.sh` | 订阅导入，替换 `config.yaml` 的 proxies 段 |
| `tproxy.sh` | [AndroidTProxyShell](https://github.com/CHIZI-0618/AndroidTProxyShell)，TPROXY 规则层 |
| `app/` | 控制 App（Java + WebView，无第三方依赖） |

## 快速开始

1. 把 `mihomo`（android-arm64）放到 `/data/adb/gateway/`，配置 `config.yaml`
2. 部署脚本到 `/data/adb/gateway/`，`chmod 755 *.sh`
3. 启动守护：`sh /data/adb/gateway/gwctl.sh start`
4. 安装 `app/gateway.apk`，打开后点「启动网关」

详细原理、踩坑记录见 [`技术文档-热点网关.md`](./技术文档-热点网关.md)。

## 环境要求

- KernelSU / Magisk / APatch root
- Android 内核支持 `xt_TPROXY`、`REDIRECT`、`owner`、`mac`（多数 5.10+ 内核具备）
- 热点接口名因厂商而异（本机为 `wlan2`），`gateway.sh` 会自动探测

## 紧急恢复

```sh
su -c "sh /data/adb/gateway/panic.sh"
```

## 许可

`tproxy.sh` 来自 AndroidTProxyShell（GPL-3.0），其余为本项目代码。
