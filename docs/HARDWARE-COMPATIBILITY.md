# WinduxEdu 硬件兼容性策略

本文档基于维护者提供的《通用 Debian 衍生发行版 驱动与固件完整清单（最大兼容）》，说明 WinduxEdu 1.0 的驱动与固件策略：**哪些预装进镜像、哪些按需可选、哪些留作后续集成**。所有列出的包名均已对照 Debian Bookworm 归档逐一验证存在。

安装清单：

- [`config/package-lists/winduxedu-desktop.list.chroot`](../config/package-lists/winduxedu-desktop.list.chroot)——基础固件（Intel/AMD/Realtek/Atheros/Broadcom 无线、AMD 显卡、Intel 音频）与内核头文件
- [`config/package-lists/winduxedu-compat.list.chroot`](../config/package-lists/winduxedu-compat.list.chroot)——本兼容性层新增：全量固件、微码、Mesa 工具、蓝牙、PipeWire、libinput 输入栈、摄像头、打印扫描、指纹框架
- [`config/package-lists/winduxedu-education.list.chroot`](../config/package-lists/winduxedu-education.list.chroot)——教育组件（Matchbox-keyboard）

软件源：`main contrib non-free non-free-firmware`（live-build 与 `config/archives` 均已启用）。

## 1. 预装策略（镜像内）

| 类别 | 方案 | 说明 |
| --- | --- | --- |
| 内核 | `linux-image-amd64`（Bookworm 6.1 LTS） | 稳定性优先，DKMS 兼容性最佳 |
| CPU 微码 | `intel-microcode` + `amd64-microcode` | 随镜像预装 |
| Intel/AMD 显卡 | 内核 modesetting + `firmware-misc-nonfree` / `firmware-amd-graphics` + Mesa 工具 | 开源栈，开箱即用；**不安装** `xf86-video-intel` |
| NVIDIA | **默认 nouveau**（`firmware-misc-nonfree`） | 不预装闭源驱动，见 §3 |
| 有线网卡 | 内核内置（e1000e / igb / r8169 / tg3） | 服务器级固件 `firmware-bnx2*` `firmware-cavium` 等一并预装 |
| 无线网卡 | `firmware-iwlwifi` `firmware-realtek` `firmware-atheros` `firmware-brcm80211` | 覆盖 Intel AX/AC、Realtek RTL88xx、Atheros、Broadcom brcmfmac |
| 蓝牙 | `bluez` `bluez-tools` `libspa-0.2-bluetooth` | PipeWire 蓝牙音频模块已包含 |
| 音频 | `firmware-sof-signed`（Intel SOF，防无声）+ `firmware-intel-sound` + `firmware-cirrus`（见 §2）+ PipeWire 栈 | `pipewire` `pipewire-pulse` `wireplumber` `alsa-utils` |
| 输入 | `xserver-xorg-input-libinput` + `xinput-calibrator` | 触摸屏/触摸板统一 libinput |
| 屏幕键盘 | **`matchbox-keyboard` + `matchbox-keyboard-im`** | 见 §4 |
| 摄像头 | UVC 内核驱动 + `v4l-utils` `guvcview` `ffmpeg` | 绝大多数 USB 摄像头开箱即用 |
| 打印扫描 | CUPS + `printer-driver-all` + OpenPrinting PPD + HPLIP + SANE | 覆盖 HP/Canon/Epson/Brother 等 |
| 指纹 | `fprintd` `libpam-fprintd` | 预装框架，不保证所有传感器可用（§6） |
| DKMS | `dkms` `build-essential` `linux-headers-amd64` | 内核升级后自动重建第三方模块 |

## 2. 仅存在于 bookworm-backports 的固件（可选）

以下固件包 Bookworm 主归档没有，仅在 `bookworm-backports`（`20250410-2~bpo12+1`）与更高发行版提供。为保持镜像来源单一、构建确定，它们**不进入镜像**；新硬件需要时在已安装系统上执行：

```sh
echo 'deb http://deb.debian.org/debian bookworm-backports main contrib non-free non-free-firmware' \
  | sudo tee /etc/apt/sources.list.d/backports.list
sudo apt update
sudo apt install -t bookworm-backports \
  firmware-intel-graphics \   # Intel 新显卡/IPU 固件
  firmware-intel-misc \       # Intel 杂项固件
  firmware-mediatek \         # MediaTek/MT79xx 无线
  firmware-cirrus \           # Cirrus Logic 新音频编解码
  firmware-marvell-prestera   # Marvell 交换机（服务器，普通 PC 可忽略）
```

## 3. NVIDIA 策略

镜像**默认使用 nouveau 开源驱动**（办公/教学场景足够，含 `firmware-misc-nonfree`）：

| 方案 | 命令 | 适用 |
| --- | --- | --- |
| A：nouveau（默认） | 无需操作 | 办公、教学 |
| B：闭源 DKMS | `sudo apt install nvidia-driver nvidia-kernel-dkms` | 需要 CUDA / 3D 性能 |
| C：开源内核模块 | `sudo apt install nvidia-open-kernel-dkms nvidia-driver` | Turing 及更新架构 |

镜像已预装 `dkms` 与内核头文件，切换方案无需额外准备。Maxwell/Pascal/Volta 仅支持方案 B。

## 4. 屏幕键盘：matchbox-keyboard

参考清单中建议 `onboard`；WinduxEdu 实际采用 **`matchbox-keyboard`**（Debian `main`，`0.2+git20160713-1`，GPL-2-or-later，见 [`EDU-COMPONENTS.md`](EDU-COMPONENTS.md)），因为它更轻量、无 GTK 依赖负担，适配触摸教学屏。若需要 `onboard`：

```sh
sudo apt install onboard
```

## 5. HWE 内核（新硬件支持，可选）

镜像默认 Bookworm 6.1 稳定内核。新 CPU/GPU/网卡（如 Realtek 2.5G r8125、MT7925）识别不佳时，可切换 backports HWE 内核：

```sh
echo 'deb http://deb.debian.org/debian bookworm-backports main contrib non-free non-free-firmware' \
  | sudo tee /etc/apt/sources.list.d/backports.list
sudo apt update
sudo apt install -t bookworm-backports linux-image-amd64 linux-headers-amd64
```

## 6. 已知边界

- **AIC8800 无线网卡（希沃等国产设备常用）**：无主线驱动，需 out-of-tree DKMS（[radxa-pkg/aic8800](https://github.com/radxa-pkg/aic8800)，PCIe/SDIO/USB 三接口）。属外部来源，**尚未集成**；后续按 `sources.lock.tsv` 审计后决定是否进入构建。
- **指纹识别**：`fprintd` 已预装，但 Goodix 27c6:550a、Broadcom ControlVault 3、CS9711 等需社区驱动或 OEM 二进制，不保证可用；用 `lsusb` 对照 [libfprint 支持列表](https://libfprint.freedesktop.org/support/)。
- **Brother / Epson 扫描仪**：需厂商官网 brscan / epsonscan2 包，不随镜像分发。
- **多屏触摸校准**：`xinput map-to-output <device> <output>` 映射触摸到指定显示器；偏移时用 `xinput-calibrator`。
- **NVIDIA 首启向导**：检测 NVIDIA 显卡并提示切换闭源驱动的向导为规划项，当前未实现。

## 参考

维护者清单原件：`驱动（最大兼容）.txt`（仓库外），覆盖内核/微码、显卡三方案、有线无线、音频、输入、存储、摄像头、打印扫描、指纹与固件总表。
