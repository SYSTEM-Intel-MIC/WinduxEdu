# WinduxEdu 1.0 Component Integration

> **范围。** 本文记录 WinduxEdu 1.0 的第三方来源锁、包 recipe、受控构建修改、ElevenDE 桌面适配与安全边界。WinduxEdu 1.0 以 ElevenDE 为桌面核心；它不重新开发上游应用，也不让上游工具越过 Debian 的认证和权限模型。

## 分层模型与构建边界

WinduxEdu 采用 package layer + patch layer + desktop integration layer。`packages/sources.lock.tsv` 固定 Git 来源和提交；`packages/binaries.lock.tsv` 固定发行 DEB 和 SHA-256；`artifacts/source-cache/` 仅为本地/CI 缓存。构建工作树和缓存不提交到 Git，最终 Live 组装只读取已验证的 `artifacts/packages/*.deb`、清单和哈希。

| 层 | 位置 | 作用 |
| --- | --- | --- |
| 来源锁 | `packages/*.lock.tsv` | 明确上游 URL、不可变修订、许可证状态与集成角色。 |
| 核心/附加 recipe | `scripts/build-winduxedu-components.sh`、`scripts/build-winduxedu-extra-components.sh` | 在隔离 Bookworm 容器中取得来源、构建独立 DEB；从不执行上游 `install.sh`。 |
| ElevenDE 补丁 | `packages/elevende/patches/README.md` 与 `scripts/patch-elevende-*.py` | 对构建副本注入启动、分辨率重排、图标解析、图标 staging 和会话策略。 |
| 桌面适配 | `winduxedu-component-launch`、ElevenDE GTK 覆盖和 Live hook | 统一会话环境、X11 标题栏行为、入口、图标和基础 GTK 控件，而不改第三方业务代码。 |
| ISO 质量门 | `validate-winduxedu-component-packages.sh`、`validate-winduxedu-live-image.sh` | 检查包哈希、架构、许可证、入口、Calamares、原生会话服务、图标和最终 squashfs。 |

## ElevenDE 桌面适配

### Windows 11 图标映射

`packages/elevende/icon-map.tsv` 为 13 个集成组件定义图标别名。`import-winduxedu-win11-icons.py` 使用用户指定的 [HaydenReeve/WindowsIcons][windowsicons] ICO 路径生成 16–128px PNG 覆盖层；只保留实际使用的转换输出，而不复制完整上游资产库。`patch-elevende-winduxedu-component-icons.py` 将窗口类别和启动命令映射到这些别名，确保桌面、开始菜单、任务栏与 ElevenDE 自绘标题栏的一致性。

`patch-elevende-icon-overlay-staging.py` 在 ElevenDE 上游 SVG/ICO 生成完成后重新放入覆盖层，避免打包过程覆写 WinduxEdu 图标。最终 ISO 校验会验证全部别名的 64px PNG。来源与资产权利状态见 [`packages/elevende/ASSET-SOURCES.md`](../packages/elevende/ASSET-SOURCES.md) 和 ElevenDE 自带的 `WINDOWSICONS-NOTICE.md`。

### UI 与启动统一

每个第三方应用的最终 XDG 入口由 Live 安装钩子重写至 `/usr/local/share/applications/`，并使用 `/usr/local/libexec/winduxedu-component-launch`。适配器设置 `XDG_CURRENT_DESKTOP=ElevenDE`、X11/GTK/Qt 环境和统一图标目录，关闭 GTK 客户端标题栏，从而让 Openbox/ElevenDE 统一绘制窗口框架。`/usr/share/themes/ElevenDE/gtk-3.0/gtk.css` 为 GTK 按钮、输入、列表、焦点和进度条提供浅色、圆角、Windows 蓝色强调；Qt、GTK 和 Tk 工具的功能逻辑保持上游实现。

### 会话策略

WinduxEdu 不安装 LightDM。`winduxedu-elevende-display.service` 通过 Xorg/xinit 启动 ElevenDE：LiveCD 由 `winduxedu-live-session-init` 创建并直接启动临时 `user`，不设置或公布密码；安装后 Calamares 写入实际用户到 `/etc/winduxedu/session-user`，ElevenDE 再显示自身的 Win11 风格登录界面并验证该用户密码。Live 初始化不添加 `nopasswdlogin`、不写 PAM/LightDM 配置；目标后安装清理 Live 服务和临时策略。

## 组件矩阵

| 组件 | 来源锁 / 许可证 | WinduxEdu DEB 与受控修改 | ElevenDE 入口和安全边界 |
| --- | --- | --- | --- |
| ElevenDE 3.5.1 | `b4b97ca` / GPL-3.0-or-later | 仅补丁构建副本：桌面启动、显示重排、图标、会话。 | 核心 Shell 与原生登录；不修改上游仓库。 |
| Linux PC Manager | `4a744338` / 上游未提供许可证文件 | `linux-pcmanager` Python package。 | 控制面板图标；许可证状态显式保留，不被 WinduxEdu GPL 覆盖。 |
| Registry Editor | `0e3de3dc` / 上游未提供许可证文件 | `linux-regedit` Meson/C package；提供 `regedit` 命令别名。 | Windows 键图标。 |
| Device Manager | `e7e8238c` / 上游声明 | `winduxedu-device-manager` Go package；使用 WinduxEdu 固定 `go.sum` 和 `-mod=readonly`。 | 设备图标。 |
| WinduxEdu Store | `264b3821` / GPL-3.0-only | `winduxedu-store` Python/GTK package。 | Store 图标；实际安装仍通过配置的 APT/polkit 路径。 |
| Copilot for Linux | 固定 v1.0.0 DEB / 上游声明 | 只下载二进制锁中 SHA-256 验证的 DEB；Live 提供受控 Electron 启动器。 | package 图标；无 API 密钥。 |
| PeaZip | 固定 11.2.0 DEB / LGPL-3.0-or-later | 只下载二进制锁中 SHA-256 验证的 Qt6 DEB。 | ZIP 文件夹图标。 |
| Troubleshooting | `124a743d` / MIT | `winduxedu-troubleshooting`；构建期 PySide6 → PyQt5 兼容导入。 | 信息图标。 |
| Sticky Keys | `511364af` / MIT | `winduxedu-sticky-keys` Python package，覆盖错误的上游 desktop Exec。 | Sticky Notes 图标；用户会话入口。 |
| Windows Widgets | `5b923111` / MIT | `winduxedu-widgets` Python/PyQt5 package。 | Widgets 图标；不默认驻留启动。 |
| Windows Commands | `5eac6c1d` / MIT | `winduxedu-windowshit` Rust package。 | Terminal 图标；所有命令使用 `winduxedu-*` 前缀，避免覆盖 Linux 命令。 |
| WinSAT | `dc292e6c` / WTFPL | `winduxedu-winsat` Python package。 | 芯片图标；只按需运行。 |
| About WinduxEdu | `cdd2c192` / GPL-3.0 | `winduxedu-winver` GTK4/C package。 | 系统版本图标。 |
| Feedback Hub | `67befa32` / GPL-3.0 | `feedbackhub` Python/GTK package。 | Feedback 图标。 |
| `windowsuninstaller/mmclinux` | 无可验证公开来源 | 不进入来源锁、构建或 ISO。 | **未集成**；需要准确 URL 与许可证资料。 |

完整 URL、提交与角色以 [`packages/sources.lock.tsv`](../packages/sources.lock.tsv) 为准，二进制 URL/SHA-256 以 [`packages/binaries.lock.tsv`](../packages/binaries.lock.tsv) 为准。

## 验证与安全约束

构建必须通过 package SHA-256、DEB 架构、许可证文档、XDG 入口和 JSON manifest 检查。ISO 还必须通过 squashfs 校验，覆盖 Calamares 的 `shellprocess@winduxedu-postinstall`、最小 Live sudoers、安装器依赖、无 LightDM、ElevenDE 原生服务、WinduxEdu Store、组件适配器、GTK 主题和 13 个图标别名。QEMU BIOS/UEFI 冒烟是产物上传前的进一步门槛。

仅具观赏价值的演示/预览组件（蓝屏演示、UAC 预览、更新预览、激活水印、Defender 状态预览）已从 WinduxEdu 1.0 移除；电源动作仅保留 suspend/poweroff/reboot 三个固定分支。驱动探测只触发现有 udev/firmware 状态并可查询 `fwupdmgr`，不会静默下载、安装或替换驱动。

## 参考

[windowsicons]: https://github.com/HaydenReeve/WindowsIcons "WindowsIcons source"
