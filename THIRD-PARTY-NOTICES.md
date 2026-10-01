# WinduxEdu 1.0 第三方组件与许可证声明

Copyright © 2026 **SYSTEM-Intel-MIC**。除文件另有说明外，WinduxEdu 自有的构建脚本、配置、打包元数据、品牌资源、文档和集成代码均按 **GNU GPL-3.0-or-later** 发布，完整文本见 [`LICENSE`](LICENSE)。WinduxEdu 是聚合发行项目；根目录 GPL **不会**改变第三方组件的原始许可证、版权或分发条件。

> 对于上游明确提供许可证文件的每个本地 DEB，构建会安装许可证副本至 `/usr/share/doc/<package>/copyright`。仓库同时在 [`LICENSES/`](LICENSES/) 保留审计时取得的许可证原文；LinuxPCManager 与 linux-regedit 的上游快照未提供许可证文件，WinduxEdu 仅记录其状态而不伪造授权。

## 固定组件与分发边界

| 组件 | 固定来源 | 许可证 | WinduxEdu 1.0 分发与启用边界 |
|---|---|---|---|
| ElevenDE 3.6 | `c3221d9eaeeca10d989ae1ae596d9cf82d9508e9` [1] | GPL-3.0-or-later（ElevenDE 自有部分） | 从公开固定提交构建。SAS、Explorer 与 runbox 的原始上游部分保留独立许可证；ElevenDE 对 Explorer 的重大修改和集成按其 GPL 声明处理。 |
| LinuxPCManager、linux-regedit | 见 [`packages/sources.lock.tsv`](packages/sources.lock.tsv) | 上游当前未提供可执行的明确许可证 | 不重新标注为 GPL；保留来源和固定提交。单独再分发前应取得明确授权。 |
| Device Manager | 见 [`packages/sources.lock.tsv`](packages/sources.lock.tsv) | 上游当前未提供可执行的明确许可证 | 独立 `winduxedu-device-manager` DEB；保留来源和固定提交，不重新标注为 GPL。 |
| WinduxEdu Store | `264b3821b1f180201226e02003fa48d81ffee214` [2] | GPL-3.0-only | 独立 `winduxedu-store` DEB；仅使用系统 APT/polkit 路径，未内置第三方源或凭据。 |
| Copilot for Linux、PeaZip | 固定 Release DEB | GPL-3.0；LGPL-3.0 | 二进制 URL 和 SHA-256 位于 `packages/binaries.lock.tsv`。Copilot 不预置 API 密钥。 |
| Lindows-Troubleshooting | 固定提交 [3] | MIT | 以独立 DEB 提供疑难解答入口。 |
| Linux-Sticky-keys | 固定提交 [4] | MIT | 用户显式启动的桌面工具；不在安装时写入 root、PAM 或自动启动配置。 |
| WindowsWidget-for-Linux | `5b92311174dfe3236b995ced6aeae73487ef313c` [5] | MIT | 用户会话组件，不在 Live 会话默认自动启动。 |
| windowshit | `5eac6c1d8e3d126bbbc03c76d11edd9e2badc718` [6] | MIT | 命令以 `winduxedu-` 前缀安装，避免覆盖 Debian 原生命令；涉及电源的命令仍受系统权限与确认限制。 |
| WinSAT | `dc292e6c34d089f9b5718d44744d54a40dbb818e` [7] | WTFPL | 按需运行的基准测试，不自动启动。 |
| linux-winver | 固定提交 [8] | GPL-3.0 | 作为“About WinduxEdu”独立 DEB 构建，并保留 GPL 源码与许可证。 |
| Matchbox-keyboard（触摸键盘） | Debian Bookworm `matchbox-keyboard` `0.2+git20160713-1` [11] | GPL-2-or-later | 仅从 Debian `main` 官方源安装官方二进制（含 `matchbox-keyboard-im`），不打补丁、不重打包；来源与版本声明见 [`docs/EDU-COMPONENTS.md`](docs/EDU-COMPONENTS.md)。 |
| windowsuninstaller/mmclinux | 用户指定地址在审查时不可获取 | 未知 | GitHub API 返回 404，且未找到可验证替代公开来源，因此**未被集成**。提供可审计 URL 与许可证后才可加入。 |

## 非开源软件收录区（edu-software/）

[`edu-software/`](edu-software/) 目录收录钉钉、OnlyOffice、希沃（Seewo）系列、QQ、WeChat 等**专有（非开源）二进制发行包**，按原维护者的手动分类以独立文件夹存放，后续新增的希沃侧边栏组件单列 `sidebar/`。该目录：

- **不属于开源软件**，不适用本仓库的 GPL-3.0 许可证，也不被任何第三方开源许可证覆盖；
- **与 SYSTEM-Intel-MIC 无关**：本组织非其开发者、非其分发渠道维护者、不拥有其商标，不对其功能与安全性作任何保证或背书；
- **仅作收录**：文件按原样收录，不修改、不重打包、不更换版本；`Package` / `Version` / SHA-256 固定记录于 [`edu-software/DEB-INVENTORY.tsv`](edu-software/DEB-INVENTORY.tsv)，构建使用前必须校验。文件以 50 MiB 分卷存储（逐卷 SHA-256 见 [`edu-software/PARTS-INDEX.tsv`](edu-software/PARTS-INDEX.tsv)，重组脚本 [`scripts/assemble-edu-debs.py`](scripts/assemble-edu-debs.py)）；
- **希沃侧边栏（EasiSideBar）与 UDI 热点服务**（`edu-software/sidebar/`）同样是第三方互联网软件、非开源，与 WinduxEdu / SYSTEM-Intel-MIC 无关：镜像默认**关闭**二者的开机自启，只在「设置 → 教育版设置」中手动开启；其界面硬依赖的 `fonts-noto-cjk` 由 Debian `main` 官方源提供；
- 具体声明与清单见 [`edu-software/README.md`](edu-software/README.md)。

## ElevenDE 上游边界

ElevenDE 自有代码的 GPL-3.0-or-later 文本保存在 [`LICENSES/GPL-3.0-ElevenDE.txt`](LICENSES/GPL-3.0-ElevenDE.txt)。其内嵌 Explorer-for-Linux 并非未修改镜像：上游原始代码继续受 MIT 条款约束，而 ElevenDE 对其重构、构建整合与增量实现遵循 ElevenDE 的 GPL 声明。WinduxEdu 不声称能够以根目录 GPL 重新授权任何独立上游项目。[1]

## Debian 与运行时依赖

Microsoft Edge、VLC、Calamares、Fcitx5、Xorg、Openbox、NetworkManager、GTK、Qt、Python、Rust、Go 及其他依赖均由 Debian Bookworm 或固定构建容器提供，且各自保留其版权与许可证。已安装系统以 `/usr/share/doc/<package>/copyright` 为准。WinduxEdu 不为 Debian 软件包重新授权。

## 对应源码与构建可追溯性

WinduxEdu 自有源码、配置和构建脚本在本仓库公开。`packages/sources.lock.tsv`、`packages/binaries.lock.tsv`、构建期 Git 缓存和 package recipe 共同定义可复现输入；构建时使用的提交、DEB SHA-256、来源锁、二进制锁、ElevenDE 图标映射与图标覆盖层哈希会写入 `WINDUXEDU-1.0-BUILD-MANIFEST.json`，并随 GitHub Actions 工件上传。上游许可证文本位于 [`LICENSES/`](LICENSES/)，构建逻辑位于 [`scripts/build-winduxedu-components.sh`](scripts/build-winduxedu-components.sh) 与 [`scripts/build-winduxedu-extra-components.sh`](scripts/build-winduxedu-extra-components.sh)。

## 商标

“Windows”、“Windows 11”、“Microsoft”、“Copilot”和 WindowsIcons 等名称、标志及相关品牌可能属于各自权利人。WinduxEdu 对 `packages/elevende/icons/` 中由 [WindowsIcons][12] 转换的精选 PNG 不主张所有权；图标转换不会改变上游资产的权利状态。WinduxEdu 是独立 Linux 发行版项目，不代表也未获 Microsoft 授权。

## 参考

[1]: https://github.com/SYSTEM-Intel-MIC/ElevenDE/tree/c3221d9eaeeca10d989ae1ae596d9cf82d9508e9 "ElevenDE 3.6 fixed source"
[2]: https://github.com/SYSTEM-Intel-MIC/linux-store "linux-store"
[3]: https://github.com/BobbyChengCN0518/Lindows-Troubleshooting "WinduxEdu Troubleshooting"
[4]: https://github.com/xusk1234/Linux-Sticky-keys "Linux Sticky Keys"
[5]: https://github.com/phillin-liu/WindowsWidget-for-Linux "WindowsWidget for Linux"
[6]: https://github.com/HelloAIXIAOJI/windowshit "windowshit"
[7]: https://github.com/WhatDamon/WinSAT "WinSAT"
[8]: https://github.com/DeepslateQAQ/linux-winver "linux-winver"
[11]: https://wiki.debian.org/Teams/DebianMatchboxProject "Debian Matchbox project"
[12]: https://github.com/HaydenReeve/WindowsIcons "WindowsIcons"
