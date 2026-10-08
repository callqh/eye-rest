# 构建与验证指南

## 环境要求

- 原生 macOS 开发工具链；构建机需要包含 macOS 26 或更新 SDK 的 Command Line Tools / Xcode。
- 最低目标系统为 macOS 14；当前验证设备为 Apple Silicon、macOS 26、双显示器。
- 无第三方 Swift 包依赖。
- 发布版构建使用本地临时签名，尚未进行 Developer ID 签名或 Apple 公证。

## 构建

在仓库根目录执行：

```sh
./scripts/build-app.sh
```

该脚本会：

1. 用 Swift Package Manager 构建 Release 可执行程序。
2. 创建 `build/休息一下.app`，打包图图素材和应用元数据。
3. 生成多尺寸图标。
4. 使用临时签名，并执行严格签名校验。

```sh
./scripts/install-local.sh
open "$HOME/Applications/休息一下.app"
```

安装脚本默认写入个人应用程序目录；若已有同名且不同 bundle identifier 的应用，会拒绝覆盖。更新正在运行的应用前，建议先从菜单栏退出旧版本。

## 核心状态机检查

```sh
swift run -c release RestEngineChecks
```

这是独立的可执行检查程序，不依赖 XCTest，也不要求完整 Xcode。成功时最后输出：

```text
16 lifecycle checks passed
```

覆盖：主动休息开始与打断、会议和续时、延后与跳过、暂停、睡眠恢复、设置变更、等待回来、活动自动开始及暂停 / 挂起优先等规则。

## 原生烟雾检查

```sh
mkdir -p build/verification
"build/休息一下.app/Contents/MacOS/EyeRest" \
  --smoke-test --output "$PWD/build/verification" \
  > build/verification/smoke.log 2>&1
```

**注意：检查会真实展示设置窗口、菜单栏弹框和全部显示器的休息遮罩，运行期间可能短暂打断桌面操作。** 完成后诊断进程自动退出。

诊断模式：

- 不加载、修改用户保存的偏好，不注册登录启动。
- 使用短时长驱动真实计时器，向应用自己的窗口发送局部事件验证休息重置。
- 全局活动判断以注入的事件计数进行确定性检查，避免用户正常操作干扰测试，不向桌面发送全局模拟输入。
- 检查所有菜单栏状态符号是否存在。
- 截图只渲染应用自己的原生视图，不采集屏幕、其他应用或桌面内容。
- 成功时日志最后包含 `SMOKE TEST COMPLETE`；发现失败应检查 `FAIL` 行和退出码。

### 截图与 README 图片

| 诊断图片 | 内容 |
| --- | --- |
| `menu-light.png` | 浅色弹框、倒计时和图图头像 |
| `settings-light.png` / `settings-dark.png` | 深浅色设置 |
| `overlay-light.png` / `overlay-dark.png` | 待休息提示 |
| `resting-default-dark.png` | 按默认时长渲染的坐姿图图休息界面 |
| `active-rest.png` | 短时长测试中的休息打断状态，不适合直接作为默认产品节奏展示 |
| `meeting-grace.png` | 会议续时窗口 |
| `return-ready-light.png` / `return-ready-dark.png` | 休息完成后的等待界面 |

README 图片保存在 [图片目录](<images/>)，来自当前诊断渲染，只做缩放与全屏中央区域裁切，没有添加虚构界面元素。图图休息图使用默认 5 分钟延后设置，而不是短时长测试值。

原生 NSView 位图不能完整包含窗口服务器的桌面模糊和 Liquid Glass 合成。这些图片用于说明布局和状态，不证明真实桌面合成效果；材质仍需在运行中的应用目视检查。

## 尚需系统实测

- 真实锁屏、系统睡眠、显示器睡眠和会话恢复通知。
- 其他应用的全屏 Space，以及不同显示器和缩放设置。
- 登录启动审批、注销再登录和真实提示音播放。
- macOS 14 / 15 的兼容材质及 Intel 设备。

不要为了自动检查而锁定他人的电脑、切换系统外观或开启登录启动。提交问题时应说明已验证的范围，不把状态机模拟等同于系统实测。
