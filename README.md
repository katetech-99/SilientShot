# SilentShot

一个没有窗口、Dock 图标、菜单栏图标、选区边框和通知的 macOS 区域截图工具。

## 下载

从 [GitHub Releases](https://github.com/katetech-99/SilientShot/releases/latest) 下载最新版本，或直接下载 [SilentShot-1.0.0.dmg](https://github.com/katetech-99/SilientShot/releases/download/v1.0.0/SilentShot-1.0.0.dmg)。

## 使用

1. 从 DMG 把 `SilentShot.app` 拖到“应用程序”。
2. 首次启动，允许 macOS 请求的“辅助功能”和“屏幕与系统音频录制”权限。授权后如无反应，退出并重新打开一次应用。
3. 按住**右 Option**，用鼠标左键拖出区域，松开鼠标。
4. 图片已在系统剪贴板，可直接按 `Command-V` 粘贴。

应用刻意不显示成功提示。要退出它，请在“活动监视器”中结束 `SilentShot`，或运行：

```sh
killall SilentShot
```

再次双击已运行的应用可查看权限、鼠标监听、已拦截拖动和成功截图次数。截图期间不会显示状态窗口。

如果拖动仍会选中文字，先检查状态窗口中的权限与监听。临时签名的应用更新后，旧授权可能失效；即使系统设置的旧条目已经勾选，也请删除该条目并重新添加 `/Applications/SilentShot.app`，授权后退出并重启。只保留 Applications 中的一个应用实例。

本地诊断状态保存在 `~/Library/Caches/com.jerry.SilentShot/status.json`，仅包含权限、监听、修饰键标志和截图计数，不保存截图内容或输入文字。

## 修改触发键

例如改为右 Command：

```sh
defaults write com.jerry.SilentShot TriggerKey -string rightCommand
killall SilentShot 2>/dev/null || true
open -a SilentShot
```

可用值：`rightOption`、`leftOption`、`rightCommand`、`leftCommand`、`rightControl`、`leftControl`、`rightShift`、`leftShift`。

恢复默认右 Option：

```sh
defaults delete com.jerry.SilentShot TriggerKey
```

## 构建 DMG

```sh
chmod +x build_dmg.sh
./build_dmg.sh
```

产物位于 `build/SilentShot-1.0.0.dmg`。

## 隐私边界

SilentShot 不会、也不能绕过 macOS 的隐私保护。首次授权对话框，以及新版 macOS 可能显示的系统录屏隐私指示，均由系统控制，应用无法合法隐藏。分发给其他人前，建议使用 Apple Developer ID 签名并公证；本地脚本只做 ad-hoc 签名。
