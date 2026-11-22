# InstaBox Manager (macOS Apple Silicon `arm64` 原生版)

使用原生 **Swift + SwiftUI（Liquid Glass 液态玻璃设计系统）** 编写的 [InstaBox (`instabox.sh`)](https://instabox.sh) 云端沙盒桌面管理面板，专为 **macOS 27 及以上版本的 Apple Silicon (`arm64`)** 打造，输入 `ibk_...` API Key 即可一站式管理全部沙盒资源。

## 核心功能

0. **全场景原生液态玻璃（Liquid Glass）视觉架构**
   - 基于 macOS 原生 `GlassEffectContainer`、`glassEffect(.regular / .clear)`、`.buttonStyle(.glass / .glassProminent)` 与 3×3 `MeshGradient` 动态光学折射背景打造。
   - 顶栏、状态筛选器与沙盒详情 6 大标签栏采用 `glassEffectID` 流体形态过渡（Fluid Morphing），全局通知横幅支持 `materialize` 液态凝结动效，列表与滚动区域启用 `scrollEdgeEffectStyle(.soft)` 边缘消融，并完整适配系统「降低透明度」、「增强对比度」与「减弱动态效果」辅助功能。

1. **输入 API Key 即刻管理（支持多工作区）**
   - 输入 `ibk_...`（或自动识别环境变量 `INSTABOX_API_KEY`）即可验证连接。
   - 使用 macOS 系统级 **钥匙串（Keychain）** 安全加密存储多个工作区的 API Key，支持一键切换。
2. **沙盒全生命周期控制**
   - 秒级创建沙盒（支持 `agent-browser`、`android`、`omarchy`、`ci`、`universal` 等全部官方模板或已有快照）。
   - 启动（Start）、暂停保活内存（Suspend/Pause）、秒级恢复（Resume）、关机（Stop）、重启、快速克隆（Fork）、原地快照回滚（Restore）、在线扩容 `/data` 持久化磁盘与调整自动暂停策略。
   - 自动跟踪异步 `Operation` 长轮询进度，删除资源自动携带 `Idempotency-Key` 与 `X-Confirm-Delete` 安全防误删校验。
3. **内置实时流式终端（SSE Exec）与历史记录**
   - 基于 `text/event-stream` 实时流式输出 `stdout` / `stderr`，内置常用运维快捷指令与历史命令回溯。
4. **远程文件管理器**
   - 目录浏览、双击在线文本编辑保存、本地文件多选上传、二进制文件原样下载、新建目录与删除。
5. **一键免密打开 macOS 终端连接 SSH + 公网/私密端口暴露**
   - 一键签发临时 SSH Token 并直接拉起 `Terminal.app` 或 `iTerm2` 进入交互式 Shell（无繁琐密钥配置）。
   - 一键将沙盒内端口暴露为公开或私密（Token 保护）HTTPS 域名。
6. **内嵌远程桌面（X11 / Wayland / Android 14）**
   - 支持检测、安装、启动云端图形桌面，并在面板内部通过原生 `WKWebView` 直接操控或生成临时分享链接。
7. **监控图表、进程管理、快照、Org Secrets & Webhooks + macOS 顶部菜单栏快捷面板**
   - 原生 Swift `Charts` 展示 CPU / 内存趋势、磁盘占用、进程列表与内核启动日志。
   - 常驻 macOS 顶部状态栏（`MenuBarExtra`），随时查看运行数量并一键启停或打开 SSH。

## 编译与打包（仅限 Apple Silicon `arm64`）

```bash
cd /Users/darling/Desktop/Genius/InstaBox-Manager

# 一键编译、签名、自检并打包 .app / .dmg / .zip（输出至 dist/）
chmod +x scripts/build-arm64.sh
./scripts/build-arm64.sh

# 单独运行内置 arm64 二进制自检测试
"./dist/InstaBox Manager.app/Contents/MacOS/InstaBoxManager" --self-test

# 直接启动应用或打开 DMG 安装包
open "dist/InstaBox Manager.app"
open "dist/InstaBox-Manager-1.0.0-arm64.dmg"
```

### 打包产物说明（`dist/` 目录）

- `InstaBox Manager.app`：独立签名的 macOS 原生应用包（`arm64`）
- `InstaBox-Manager-1.0.0-arm64.dmg`：带 `Applications` 拖拽安装快捷方式的标准 macOS 磁盘映像安装包
- `InstaBox-Manager-1.0.0-arm64.zip`：保留签名与扩展属性的分发压缩包
- `SHA256SUMS.txt`：安装包 SHA-256 校验值
