# WinduxEdu 1.0

**WinduxEdu 1.0** 是由 **SYSTEM-Intel-MIC** 维护的 Debian Bookworm AMD64 Live 教育发行版集成层。它以 **ElevenDE 3.6** 为核心 X11 桌面，提供 Windows 风格的开始菜单、任务栏、统一标题栏、资源管理器、设置、任务管理器、运行对话框、中文输入、Calamares 安装器和一组受控集成的 Windows 风格工具，并面向课堂教学按声明收录**专有教学软件**，另带**触屏输入与硬件兼容层**（屏幕键盘、固件与输入栈等）。

> `main` 为唯一主干。推送到 `main`（或手动触发）即运行 GitHub Actions：组件包构建 → ISO 组装 → squashfs/QEMU 校验，全部通过后自动创建 **Preview Release**（预发布）并附带 ISO（超过 2 GiB 时自动切分为分卷资产）与 SHA-256 校验文件。

## 发行版集成架构

WinduxEdu 不把所有上游项目做成长期完整 fork，也不让 `live-build` 直接面对 GitHub。仓库只维护"如何把固定上游软件变成 WinduxEdu 一部分"的 package layer、patch layer 与 desktop integration layer；每个正式构建先产出可验证 DEB，再由 `live-build` 只消费已验证包集。

| 层 | 仓库位置 | 职责 | 不做什么 |
| --- | --- | --- | --- |
| **来源锁** | `packages/sources.lock.tsv`、`packages/binaries.lock.tsv` | 固定每个 Git 项目的 URL/提交，或固定预构建 DEB 的 URL/SHA-256。 | 不记录浮动分支或"最新版"标签。 |
| **源码缓存** | `artifacts/source-cache/` 与 CI 缓存 | 将锁定提交缓存到一次性构建工作树，允许同一来源在核心/附加 recipe 间复用。 | 不提交完整第三方 Git 历史或工作副本。 |
| **包 recipe** | `scripts/build-winduxedu-components.sh`、`scripts/build-winduxedu-extra-components.sh` | 在独立 Bookworm 容器中获取锁定来源、应用受控适配、构建 DEB 并写入哈希。 | 不执行上游 `install.sh`，不让 Live ISO 直接拉取源码。 |
| **补丁层** | `packages/elevende/patches/` 与受审计补丁脚本 | 对构建副本应用显示重排、桌面入口、会话策略和图标解析改造。 | 不修改或推送 ElevenDE 上游仓库。 |
| **桌面集成层** | `config/includes.chroot/`、`config/hooks/normal/` | 统一 ElevenDE 会话变量、标题栏、启动入口、Windows 11 图标和 GTK 控件主题。 | 不替代第三方工具的业务逻辑。 |
| **Live 输入层** | `scripts/stage-winduxedu-live-inputs.sh` | 只向 Live chroot 放入已校验 DEB、SHA256、清单和执行钩子。 | 不重新下载组件。 |
| **教学软件层** | `edu-software/` | 专有教学软件按声明分卷收录，CI 双层校验重组后安装进 Live 镜像；Debian 源内的屏幕键盘等输入/无障碍组件归入硬件兼容层的 `winduxedu-compat.list.chroot`，不属于教学软件。 | 不修改收录文件，不更换其版本。 |

这种结构将上游更新、WinduxEdu 适配、包构建和 ISO 组装明确分离。`WINDUXEDU-1.0-BUILD-MANIFEST.json` 同时记录 WinduxEdu 提交、包哈希、来源锁、二进制锁、ElevenDE 图标映射及每个覆盖图标的 SHA-256，便于复核最终 ISO 的输入。

## 教学软件

教学软件只有一类，边界不可混淆（完整声明见 [`docs/EDU-COMPONENTS.md`](docs/EDU-COMPONENTS.md)）：

> 屏幕键盘（`onboard`）**不属于教学软件**：它是触屏输入/无障碍组件，随硬件兼容层
> [`config/package-lists/winduxedu-compat.list.chroot`](config/package-lists/winduxedu-compat.list.chroot) 安装，
> 来源与版本声明见 [`docs/HARDWARE-COMPATIBILITY.md`](docs/HARDWARE-COMPATIBILITY.md) §4。

### 专有软件收录区（`edu-software/`，非开源、仅收录）

钉钉、ONLYOFFICE、希沃（白板/管家/班级优化大师/视频展台）、QQ、WeChat 按维护者的分类文件夹收录：

- **不属于开源软件**，不适用本仓库 GPL-3.0；
- **与 SYSTEM-Intel-MIC 无关**：本组织非开发者、非分发维护者、不拥有其商标、不提供任何保证；
- **仅作收录、版本不更换**：`Package`/`Version`/SHA-256 固定于 `edu-software/DEB-INVENTORY.tsv`；
- 为遵守 GitHub 单文件 100 MB 上限，每个 DEB 以 **50 MiB 分卷**存放（`PARTS-INDEX.tsv` 逐卷哈希，`scripts/assemble-edu-debs.py` 重组并双层校验）。
- **进入 Live 镜像**：CI 在 staging 阶段用 `scripts/assemble-edu-debs.py --output config/includes.chroot/opt/winduxedu/edu-packages` 重组并校验，`config/hooks/normal/1550-install-winduxedu-edu-software.hook.chroot` 以 `apt-get install -y --no-install-recommends` 逐个安装进 chroot（安装后删除暂存目录，不进 squashfs）。**希沃管家（com.seewo.terminalmanager）同样安装**：安装钩子先用 `dpkg-deb` 把它 control 里在 Bookworm 上永远无法满足的 `libstdc++6 (<< 9)` 改写掉，再交给 apt，避免整个事务中止；8 个专有教学软件与 7 个希沃侧边栏组件（共 15 个包）由 `scripts/validate-winduxedu-live-image.sh` 在最终 squashfs 的 dpkg status 中逐一断言。该包的后端单元 `com.seewo.terminalmanager.service` 在镜像里保持启用——屏蔽它会让窗口打开后拿不到任何响应，即实测到的 `Cannot read property 'data' of undefined`；只有 `/etc/xdg/autostart` 登录弹窗项由「教育版设置 → 希沃管家开机自启」决定，菜单入口始终可手动启动（详见 [`docs/EDU-COMPONENTS.md`](docs/EDU-COMPONENTS.md)）。`libappindicator3-1` 依赖由 Bookworm `main` 的 `libayatana-appindicator3-1`（`Provides: libappindicator3-1`）满足；`--no-install-recommends` 避免 ONLYOFFICE 的 `ttf-mscorefonts-installer` 在安装期联网抓取字体。希沃/钉钉/微信/QQ 等入口若只自带 `/opt/apps/...` 桌面文件，安装钩子会补拷到 `/usr/share/applications/` 保证菜单可见。

声明全文见 [`edu-software/README.md`](edu-software/README.md)。

## 桌面、会话与安装体验

| 范围 | WinduxEdu 1.0 实现 |
| --- | --- |
| **核心桌面** | ElevenDE 3.6、Openbox、picom、Xorg、NetworkManager 与 Fcitx5 中文输入。ElevenDE 负责开始菜单、任务栏、窗口标题栏、窗口操作和其自身的 Win11 风格登录/锁屏界面。 |
| **LiveCD** | `winduxedu-elevende-display.service` 使用 Xorg/xinit 直接启动一次性的 `user` 桌面会话。Live 用户不需要、也不公开密码；该临时用户只由系统服务通过 `runuser` 启动。 |
| **已安装系统** | Calamares 后安装步骤写入实际创建的用户至 `/etc/winduxedu/session-user`。同一个 ElevenDE 原生显示服务以该用户启动会话，ElevenDE 自己的 `elevende-lock --login` 显示并验证密码。**不使用 LightDM 或其 Greeter。** |
| **安全边界** | Live 初始化不会设置 `user:live`、不会创建 `nopasswdlogin` 组，也不会更改安装时设置的密码。已安装系统保留用户密码并仅将用户加入 Debian `sudo` 组。 |
| **安装器** | Calamares 使用 WinduxEdu 标识、中文欢迎页和专属幻灯片；Live 桌面与开始菜单提供"安装 WinduxEdu"。目标系统清理 Live 安装器入口、Live 初始化服务和临时用户策略。 |
| **启动链路** | ISO 使用统一的 `boot=live config components splash` BIOS/UEFI 参数。ISOLINUX 运行模块来自同一 syslinux 包；EFI System Partition 由双启动重打包脚本注入。安装后 GRUB 主题仅在主题和壁纸均存在时启用，避免悬空主题路径报错。 |

## 硬件兼容性

面向教学终端的最大兼容性预装（策略全文见 [`docs/HARDWARE-COMPATIBILITY.md`](docs/HARDWARE-COMPATIBILITY.md)）：

- **固件全覆盖**：Intel/AMD/Realtek/Atheros/Broadcom 无线、Intel SOF/HDA 音频、AMD/Intel 显卡、服务器网卡固件与双平台 CPU 微码，全部预装（Bookworm `non-free-firmware`）；
- **音频**：PipeWire（`pipewire` / `pipewire-pulse` / `wireplumber`）；
- **输入**：libinput 统一触摸屏/触摸板/键盘，含 `xinput-calibrator`；触摸屏另配三层救助（udev 按设备名补 `ID_INPUT_TOUCHSCREEN` 标签、99- 序号 InputClass 保证 `Ignore "false"` 是最终判定、热插拔开关防厂商 `xorg.conf` 关闭），并由 `winduxedu-touch-fix` 在零设备首帧写入取证日志；
- **打印扫描**：CUPS + `printer-driver-all` + OpenPrinting PPD + HPLIP + SANE；
- **摄像头与指纹**：UVC 工具链、`fprintd` 框架；
- **显卡**：Intel/AMD 开源栈开箱即用；NVIDIA 默认 nouveau，闭源/CUDA 按文档切换；
- **可选扩展**：bookworm-backports 的 HWE 内核与新固件、AIC8800（希沃设备）DKMS 驱动按文档说明安装，不进入镜像。

## ElevenDE Windows 11 图标与 UI 适配

WinduxEdu 对每个集成组件提供明确的 ElevenDE 图标别名，而不是依赖 Linux 主题的随机回退。`packages/elevende/icon-map.tsv` 将大多数入口映射到用户指定的 [WindowsIcons](https://github.com/HaydenReeve/WindowsIcons) ICO 路径，并为注册表编辑器使用单独记录来源、由 `regedit_100.ico` 重绘的公开 Windows 11 图标资源；`scripts/import-winduxedu-win11-icons.py` 将**实际使用的 13 组**资产转换为 16–128px PNG 覆盖层。仓库保存被使用的确定性输出和来源说明，不镜像完整第三方图标库。完整资产边界见 [`packages/elevende/ASSET-SOURCES.md`](packages/elevende/ASSET-SOURCES.md)。

构建时，`patch-elevende-winduxedu-component-icons.py` 向 ElevenDE 的窗口/应用解析表注入命令与窗口类别名，`patch-elevende-icon-overlay-staging.py` 确保上游图标生成步骤后重新放入覆盖资源。因此桌面、开始菜单、任务栏和 ElevenDE 绘制的窗口标题栏都解析同一 Windows 11 图标。最终 ISO 验证会检查全部 13 个 64px 组件图标存在，并拒绝残留的关机、重启、注销、睡眠或锁屏桌面入口。

第三方入口统一经由 `/usr/local/libexec/winduxedu-component-launch` 运行。该适配器设置 ElevenDE/X11 会话变量、关闭 GTK 客户端标题栏并使用统一图标搜索路径；`/usr/share/themes/ElevenDE/gtk-3.0/gtk.css` 为 GTK 的按钮、输入框、列表、进度条和焦点状态提供浅色、圆角和蓝色强调。Qt/GTK/Tk 应用仍保留各自上游业务界面，但窗口外框、标题栏、启动入口、图标和基本控件行为遵循 ElevenDE 环境。

## 集成组件、上游与 WinduxEdu 修改

下表为 WinduxEdu 1.0 的完整第三方组件声明。实际 URL 与不可变提交位于 `packages/sources.lock.tsv`；Copilot 和 PeaZip 的发布 DEB 与 SHA-256 位于 `packages/binaries.lock.tsv`。其中"入口/图标"均表示经过 ElevenDE 启动适配与 Windows 11 图标映射。专有收录区见上文「教学软件」与 [`docs/EDU-COMPONENTS.md`](docs/EDU-COMPONENTS.md)；触屏输入组件 Matchbox-keyboard 见 [`docs/HARDWARE-COMPATIBILITY.md`](docs/HARDWARE-COMPATIBILITY.md) §4。

| 组件 | 上游 | WinduxEdu 包与技术实现 | 入口/图标与安全边界 |
| --- | --- | --- | --- |
| **ElevenDE 3.6** | [SYSTEM-Intel-MIC/ElevenDE](https://github.com/SYSTEM-Intel-MIC/ElevenDE) | 固定 `c3221d9e`；构建副本应用桌面启动、显示重排、图标解析、图标覆盖、会话策略与设置「教育版设置」页补丁。 | 核心 Shell；Live 绕过登录，安装系统使用其原生登录界面。 |
| Linux PC Manager | [SYSTEM-Intel-MIC/LinuxPCManager](https://github.com/SYSTEM-Intel-MIC/LinuxPCManager) | Python 源码打包为 `linux-pcmanager`。 | `linux-pcmanager` / 控制面板图标。 |
| Registry Editor | [heyManNice/regedit](https://github.com/heyManNice/regedit) | Meson/C 构建为 `linux-regedit`，并提供 `regedit` 命令别名。 | `linux-regedit` / Windows 键图标。 |
| Device Manager | [daimile2/Device-Manager-But-Linux](https://github.com/daimile2/Device-Manager-But-Linux) | Go 构建；上游缺少 `go.sum`，WinduxEdu 使用 `vendor/winduxedu-device-manager.go.sum` 并强制 `-mod=readonly`。 | `devmgr` / 设备图标。 |
| **WinduxEdu Store** | [SYSTEM-Intel-MIC/linux-store](https://github.com/SYSTEM-Intel-MIC/linux-store) | 锁定源码打包为 `winduxedu-store`；沿用 APT 与 polkit 的软件安装模型。 | `winduxedu-store` / Microsoft Store 风格图标。 |
| Copilot for Linux | [com-in/Copilot-For-Linux](https://github.com/com-in/Copilot-For-Linux) | 仅获取 SHA-256 校验的 v1.0.0 AMD64 发布 DEB；Live 环境使用受控 Electron 沙箱兼容包装器。 | `winduxedu-copilot` / package 图标；不包含 API 密钥。 |
| PeaZip | [PeaZip](https://github.com/peazip/PeaZip) | 仅获取 SHA-256 校验的 11.2.0 Qt6 AMD64 发布 DEB。 | `peazip` / ZIP 文件夹图标。 |
| **Microsoft Edge** | [Microsoft Edge for Linux](https://packages.microsoft.com/repos/edge/) | 使用 `packages/binaries.lock.tsv` 中固定版本、URL 和 SHA-256 的官方 amd64 DEB；不在 Live 构建中查询漂移的 latest。 | 官方包图标；桌面提供 Microsoft Edge 快捷方式。该专有二进制不重新许可为 GPL。 |
| Troubleshooting | [BobbyChengCN0518/Lindows-Troubleshooting](https://github.com/BobbyChengCN0518/Lindows-Troubleshooting) | PySide6 导入适配为 Debian 可用的 PyQt5 绑定。 | `winduxedu-troubleshooting` / 信息图标。 |
| Sticky Keys | [xusk1234/Linux-Sticky-keys](https://github.com/xusk1234/Linux-Sticky-keys) | Python 入口打包，并由 WinduxEdu 覆盖错误的上游桌面 Exec。 | `winduxedu-sticky-keys` / Sticky Notes 图标。 |
| Windows Widgets | [phillin-liu/WindowsWidget-for-Linux](https://github.com/phillin-liu/WindowsWidget-for-Linux) | Python/PyQt5 包装。 | `winduxedu-widgets` / Widgets 图标。 |
| Windows Commands | [HelloAIXIAOJI/windowshit](https://github.com/HelloAIXIAOJI/windowshit) | Rust 1.95 构建；所有命令以 `winduxedu-*` 命名空间暴露，避免覆盖 Linux 命令。 | `winduxedu-windowshit` / Terminal 图标；电源命令仍受权限控制。 |
| WinSAT | [WhatDamon/WinSAT](https://github.com/WhatDamon/WinSAT) | Python 模块打包。 | `winsat` / 芯片图标。 |
| About WinduxEdu | [DeepslateQAQ/linux-winver](https://github.com/DeepslateQAQ/linux-winver) | GTK4/C 构建。 | `winver` / 系统版本图标。 |
| Onboard | [onboard-osk/onboard](https://github.com/onboard-osk/onboard) | Debian `main` 归档包 `onboard` `1.4.1-5`（含 `onboard-data`），随硬件兼容层安装、不进入来源锁；仅安装官方二进制，不打补丁、不重打包。 | 触屏屏幕键盘（完整 PC 布局含数字行，位置跨会话保留），由「教育版设置 → 屏幕键盘」开关控制（登录界面同样生效）；声明见 [`docs/HARDWARE-COMPATIBILITY.md`](docs/HARDWARE-COMPATIBILITY.md) §4。 |
| mmclinux | `windowsuninstaller/mmclinux` | 用户提供的公开地址在审计时无法确认，未进入来源锁、构建、ISO 或菜单。 | **未集成。** 提供可审计来源与许可后才可能评估。 |

## 构建、验证与发布

本地完整回归要求 Debian/Ubuntu 主机具备 Docker、`live-build`、`xorriso`、`qemu-system-x86_64`、OVMF 与 `sudo`。核心 recipe 在 `golang:1.24-bookworm` 容器中构建；含 Rust 依赖的附加组件在 `rust:1.95-bookworm` 容器中构建。

```sh
git clone https://github.com/SYSTEM-Intel-MIC/WinduxEdu.git winduxedu
cd winduxedu
bash scripts/local-test.sh
```

构建顺序为：来源锁与缓存 → 核心/附加 DEB → SHA-256 与包元数据校验 → 构建清单 → Live staging → Bookworm ISO → BIOS/UEFI 重打包 → squashfs 内容校验 → QEMU BIOS/UEFI 冒烟。根文件系统用 `xz` 压缩（15 个专有组件会让 ISO 接近 ISO9660 的 4 GiB 单文件上限，gzip 的压缩比不够），构建步骤显式断言最终 ISO 小于 4 GiB；超过 GitHub 2 GiB 单附件上限时按原始字节切分成 `.001/.002` 卷发布。`scripts/validate-winduxedu-live-image.sh` 必须确认 Calamares 后安装模块、最小 Live sudoers、无 LightDM、原生 ElevenDE 服务、13 个图标别名、受限 polkit 调度器、无系统命令桌面入口、WinduxEdu Store、关键组件入口、厂商开机单元已屏蔽，以及 15 个专有组件（8 个教学软件与希沃侧边栏的 7 个包）均已安装在最终 squashfs 中。

GitHub Actions（[`.github/workflows/build.yml`](.github/workflows/build.yml)）在 `main` 与 `winduxedu-1.0-integration` 推送时运行：

1. 在两个固定 Bookworm 容器中构建组件 DEB 并校验；
2. 组装 Live 输入（含重组校验 `edu-software/` 专有 DEB 至 chroot 树）并执行 `lb build`、双启动重打包；
3. 解出 squashfs 验证关键结构，运行 `validate-winduxedu-live-image.sh`；
4. QEMU BIOS/UEFI 有界启动冒烟并截取画面；
5. 上传 ISO、ISO SHA-256、启动报告、构建日志、组件包集和 manifest 为 Artifacts；
6. 全部检查通过后创建 **Preview Release**（预发布），因此每次成功的构建都会产出可供下载的预发布版本；ISO 超过 GitHub 单资产 2 GiB 上限时自动切分为 `.001`/`.002` 分卷。

### 下载、拼接与安装（Release 资产说明）

**为什么可能是分卷而不是单个 ISO。** GitHub Release 对**单个上传资产**强制 2 GiB（2 147 483 648 字节）硬上限，而 Release 的总容量与下载带宽没有限制。集成专有教学软件后镜像体积超过该上限，因此 CI 在 ISO 超过 2 GiB 时自动按 **1900 MiB 裸字节切卷**为 `WinduxEdu-1.0-amd64-livecd.iso.001`、`.002` … 上传——切卷不压缩、不打包，只是顺序分割原始字节；未超过上限时仍上传单个 ISO。

**校验**（在下载目录执行）：

```sh
# 切卷时提供：逐卷校验
sha256sum -c WinduxEdu-1.0-amd64-livecd.iso.parts.sha256

# 拼接出完整 ISO 后：整卷校验（始终提供）
sha256sum -c WinduxEdu-1.0-amd64-livecd.iso.sha256
```

**拼接成完整 ISO**（三选一）：

| 方式 | 操作 |
| --- | --- |
| Windows 命令行 | `copy /b WinduxEdu-1.0-amd64-livecd.iso.001+WinduxEdu-1.0-amd64-livecd.iso.002 WinduxEdu-1.0-amd64-livecd.iso` |
| Linux / macOS | `cat WinduxEdu-1.0-amd64-livecd.iso.001 WinduxEdu-1.0-amd64-livecd.iso.002 > WinduxEdu-1.0-amd64-livecd.iso` |
| 7-Zip / WinRAR | 直接打开 `.001` 分卷并解出完整 `WinduxEdu-1.0-amd64-livecd.iso`（解压即拼接） |

**写盘与安装**：拼接并通过校验后的完整 ISO 用 **Rufus**（Windows）或 **Etcher** 写入 U 盘——Rufus/Etcher 只接受拼好的完整 ISO，不能直接写 `.001` 分卷。U 盘启动后可先在 Live 桌面体验，再运行「安装 WinduxEdu」用 Calamares 安装到硬盘；BIOS 与 UEFI 均可启动。

## 许可证与安全边界

WinduxEdu 自有集成代码、构建 recipe、补丁、配置、品牌资源和文档按 **GPL-3.0-or-later** 发布，全文见 [`LICENSE`](LICENSE)。根目录 GPL 不会重新授权 MIT、LGPL、WTFPL、Debian 软件包、二进制发布包或未明确许可的上游代码。逐组件来源、固定提交、许可证文本和分发状态见 [`THIRD-PARTY-NOTICES.md`](THIRD-PARTY-NOTICES.md)；教学软件来源见 [`docs/EDU-COMPONENTS.md`](docs/EDU-COMPONENTS.md)；专有收录区声明见 [`edu-software/README.md`](edu-software/README.md)。

ElevenDE 自有代码按 GPL-3.0-or-later 发布；其 SAS-for-Linux、Explorer-for-Linux 和 runbox-linux 来源仍保留各自边界。Explorer 在 ElevenDE 内经过大幅修改和重构，因此原始上游部分与 ElevenDE 的 GPL 增量必须被区分。[1]

WinduxEdu 不自动执行系统清理、驱动卸载、驱动下载、系统任务创建、系统升级或重启。Copilot 凭据必须由用户自行配置。

Start 与 SAS 的电源操作通过 `/usr/local/libexec/winduxedu-privileged-action` 这个固定功能调度器请求单一的 polkit 动作。调度器只接受 `suspend`、`poweroff`、`reboot` 三个无参数动作。Live 的 `user` 仅对这一个动作免密，安装系统则保留 active-user 的标准 `auth_self` 桌面认证提示；不存在通用 `pkexec`、任意命令或宽泛 sudo 绕过。

## 维护者

**SYSTEM-Intel-MIC**

项目主页：<https://github.com/SYSTEM-Intel-MIC/WinduxEdu>

问题反馈：<https://github.com/SYSTEM-Intel-MIC/WinduxEdu/issues>

## 参考

[1]: https://github.com/SYSTEM-Intel-MIC/ElevenDE/tree/c3221d9eaeeca10d989ae1ae596d9cf82d9508e9 "ElevenDE source and license boundary"
# Trigger rebuild
