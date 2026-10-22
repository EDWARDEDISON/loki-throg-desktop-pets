# macOS 原生实现

基于 Swift / AppKit；共用仓库根目录的 454 张 PNG、14 段 WAV、36 组动作配置和声音触发点。Windows 引擎源码和已发布的运行包不受此目录影响。

## 编译与自检

在安装 Xcode Command Line Tools 的 Mac 上，从仓库根目录执行：

```bash
bash macos/build.sh
dist/macos/LokiThrogPets.app/Contents/MacOS/LokiThrogPets --self-test artifacts/macos-test
dist/macos/LokiThrogPets.app/Contents/MacOS/LokiThrogPets --smoke-test artifacts/macos-smoke
```

构建脚本分别编译 arm64 和 x86_64，再通过 lipo 合为 Universal 程序。目标系统为 macOS 11 及以上；无需安装第三方依赖。构建完成后以本地 ad-hoc 签名检查包完整性；这不等同于 Apple Developer ID 签名或公证。

`--self-test` 不播放声音，也不启动桌宠窗口：检查全部动画帧、行为切换、长距离巡游、相遇与单人计时、暂停和菜单保护、负坐标显示器、拖拽、颜色管理、透明命中测试，并将实际 AppKit 绘图与原版固定样例逐像素比较。

`--smoke-test` 在测试环境中短暂创建四个不抢焦点的透明窗口，显示两只独立角色，导出本程序视图的 PNG，写入启动记录后自动退出。该测试静音，不采集其他应用或完整桌面。不要与已经运行的桌宠同时执行。

## 设计

- `Model.swift`：独立于 AppKit 的行为引擎，桌面坐标统一为向下递增，屏幕允许负坐标；巡游和表演继承 v0.10 调度规则。
- `Rendering.swift`：原始 PNG 解码、24 fps 图集裁帧、最近邻绘制、透明像素命中检测、原生非激活 NSPanel。NSWindow 与世界坐标仅在此处转换。
- `App.swift`：窗口调度、逐像素鼠标穿透、拖拽、Control 点击及触控板菜单、菜单栏入口、NSSound 和音量偏好。
- `Tests.swift`：行为和像素回归测试。颜色比较通过同一个 sRGB CGContext 解码，不将未标记 PNG 的 Generic RGB 默认值与 sRGB 数值混为一谈。

GitHub Actions 会用真实的 macOS runner 编译，在 Apple 芯片和 Intel runner 上运行同一个 Universal 包并保存验证记录。它能验证编译、引擎和原生窗口启动；不同用户机器上的系统安全提示、Spaces 与全屏应用表现，仍需要实机试用反馈。
