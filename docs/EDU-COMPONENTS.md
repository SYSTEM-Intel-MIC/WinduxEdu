# WinduxEdu 教育教学组件来源声明

本文档声明 WinduxEdu 1.0 中全部教育教学软件的**来源、版本与许可证**。组件分为两类：

1. **开源教育组件**——来自 Debian Bookworm 官方软件源（`deb.debian.org`），版本由 Bookworm 发行版固定；
2. **专有软件收录区**——非开源、仅收录，独立存放在 [`edu-software/`](../edu-software/)，声明见 [`edu-software/README.md`](../edu-software/README.md)。

两类组件的边界不可混淆：开源组件受其自身开源许可证约束并可追溯到上游源码；收录区组件**不属于开源软件，与 SYSTEM-Intel-MIC 无关，仅按原样收录且版本不更换**。

## 一、开源教育组件（Debian Bookworm 官方源）

安装清单：[`config/package-lists/winduxedu-education.list.chroot`](../config/package-lists/winduxedu-education.list.chroot)。构建时由 live-build 从 Bookworm 归档安装，不经过第三方源，不执行上游安装脚本。

### Matchbox-keyboard（触摸虚拟键盘）

| 项目 | 值 |
| --- | --- |
| 功能 | X11 屏幕虚拟键盘，面向触摸屏 |
| Debian 源包 | `matchbox-keyboard` |
| Bookworm 固定版本 | `0.2+git20160713-1`（amd64） |
| 上游项目 | Matchbox Project（`matchbox.handhelds.org`，作者 Matthew Allum / OpenedHand Ltd） |
| 许可证 | GPL-2-or-later（依据 Debian `debian/copyright`：GPL v2 or later） |
| 获取途径 | Debian Bookworm `main`（`http://deb.debian.org/debian`） |
| 附带包 | `matchbox-keyboard-im`（同版本、同许可证的 GTK 输入模块） |
| 本仓库改动 | 无。仅通过包清单安装官方二进制，不打补丁、不重打包 |

### 版本固定说明

Debian Bookworm 为稳定发行版，其 `main` 区中的包版本在发行版生命周期内不升级（仅安全更新以 `+deb12uN` 修订号变化）。上述版本即构建时可取得的唯一版本，满足"版本不更换"要求；构建清单 `WINDUXEDU-1.0-BUILD-MANIFEST.json` 会记录实际安装的包版本以供审计。

## 二、专有软件收录区（edu-software/）

以下组件**均为专有（非开源）软件，与 SYSTEM-Intel-MIC 无关，本仓库仅作收录**，按原维护者分类以独立文件夹存放，版本一律不更换。详细声明与逐文件 SHA-256 见 [`edu-software/README.md`](../edu-software/README.md) 与 [`edu-software/DEB-INVENTORY.tsv`](../edu-software/DEB-INVENTORY.tsv)。

| 分类文件夹 | 组件 | 包名 | 版本 |
| --- | --- | --- | --- |
| `dingding/` | 钉钉 | com.alibabainc.dingtalk | 8.2.8.260818002 |
| `Onlyoffice/` | ONLYOFFICE Desktop Editors | onlyoffice-desktopeditors | 9.4.0-129 |
| `Seewo/` | 希沃白板 | com.seewo.easinote5 | 5.2.2.4.13701 |
| `Seewo/` | 希沃管家 | com.seewo.terminalmanager | 3.0.6.716 |
| `Seewo/` | 班级优化大师 | com.seewo.easicare | 2.1.0.3274 |
| `Seewo/` | 视频展台 | com.seewo.easicamera | 2.0.5.2580 |
| `Tencent IM/` | QQ | linuxqq | 3.2.34-53644 |
| `Tencent IM/` | WeChat | wechat | 4.1.13.23 |

### 分卷存储与重组

为遵守 GitHub 单文件 100 MB 上限，收录区的每个 `.deb` 均以 **50 MiB 固定分卷**存放在其分类文件夹内（`原名.deb.000`、`.001` …）：

- 卷清单与逐卷 SHA-256：[`edu-software/PARTS-INDEX.tsv`](../edu-software/PARTS-INDEX.tsv)
- 整文件（重组后）清单与 SHA-256：[`edu-software/DEB-INVENTORY.tsv`](../edu-software/DEB-INVENTORY.tsv)
- 重组脚本：[`scripts/assemble-edu-debs.py`](../scripts/assemble-edu-debs.py)

```sh
# 仅校验分卷完整性
python3 scripts/assemble-edu-debs.py --check

# 重组并校验，输出到 artifacts/edu-debs/（已被 .gitignore 忽略）
python3 scripts/assemble-edu-debs.py
```

重组过程先校验每一卷的 SHA-256，重组后再校验整文件 SHA-256；任何一步不匹配即失败退出。分卷不改变文件内容——DEB 内部数据本身已是压缩格式，分卷仅为切块存储，重组结果与原文件逐字节相同。

### 装入 Live 镜像

CI 在 staging 阶段执行 `python3 scripts/assemble-edu-debs.py --output config/includes.chroot/opt/winduxedu/edu-packages`，把全部 15 个收录 DEB 重组并双层校验进 chroot 树；`config/hooks/normal/1550-install-winduxedu-edu-software.hook.chroot` 随后以 `apt-get install -y --no-install-recommends` 逐个安装（安装成功后删除暂存目录，分卷原件不进入 squashfs），并把只自带 `/opt/apps/...` 桌面入口的组件补拷到 `/usr/share/applications/` 保证开始菜单可见。

- **15 个收录 DEB 全部安装**，`scripts/validate-winduxedu-live-image.sh` 会在最终 squashfs 的 `var/lib/dpkg/status` 中逐一断言；
- **希沃管家（com.seewo.terminalmanager）靠重打包装入**：它的 control 声明 `Depends: libstdc++6 (>= 8.3), libstdc++6 (<< 9), dkms`，其中 `<< 9` 在 Debian Bookworm（libstdc++6 12.x）上永远无法满足，会让整个 apt 事务中止。安装钩子在调用 apt 之前用 `dpkg-deb -R` 解包、把 `Depends` 改写为 `libstdc++6 (>= 8.3), dkms`、再 `dpkg-deb -b` 重建。上界是厂商的过度保守约束——包内全部 ELF 的最高需求只有 `GLIBCXX_3.4.22` / `CXXABI_1.3.11`（GCC 5 时代），Bookworm 的 libstdc++6 12 完全向后兼容；重写 control 而不是 `--force-depends` 强装，是为了给后续 apt 运行留下一致的 dpkg 数据库；
- **厂商的开机副作用在通用 Live 镜像上被关掉**：`com.seewo.terminalmanager.service`、`com.cvte.maxhub.alfred.service`、`disable-seewo-network-card.service` 通过 `/etc/systemd/system` 下指向 `/dev/null` 的软链屏蔽（单元文件本身仍归 dpkg 所有），同时删除 `/etc/xdg/autostart/com.seewo.terminalmanager.desktop` 与 `/home/*/Desktop` 下的副本。三者仍可从开始菜单按需启动；管家的菜单入口原本是 0 字节占位文件，安装钩子会用 postinst 生成在 `/opt/apps/.../entries/applications/` 的真文件覆盖它，校验脚本额外断言该文件非空；
- **squashfs 用 xz 而非 gzip**：这 15 个包把根文件系统推到 4 GiB 量级，而 ISO9660 level 1/2 单文件上限是 4 GiB − 1，gzip 压缩比不够。恢复 live-build Debian 模式原生的 `xz` 后才有足够余量，构建步骤另外显式断言最终 ISO 小于 4 GiB；
- `libappindicator3-1` 依赖由 Bookworm `main` 的 `libayatana-appindicator3-1`（`Provides: libappindicator3-1`）满足；
- `--no-install-recommends` 避免 ONLYOFFICE 的 `ttf-mscorefonts-installer` 在安装期联网下载字体，也避免 QQ 的 appindicator 推荐项。

### 希沃侧边栏与配套组件（sidebar/）

`sidebar/` 收录 7 个包：`com.seewo.easisidebar`（侧边栏本体）、`udi-hotspot-service`（侧边栏依赖的 UDI 热点服务），以及 5 个希沃小工具（批注、截屏、计时器、随机抽选、人数统计）。它们是**第三方互联网软件、非开源**，与 WinduxEdu / SYSTEM-Intel-MIC 无关，来源与免责声明见 [`THIRD-PARTY-NOTICES.md`](../THIRD-PARTY-NOTICES.md)。

- **默认关闭。** 侧边栏注册的是**用户** systemd 单元 `com.seewo.easisidebar.service`，UDI 服务的 postinst 会执行 `systemctl enable` 装一个系统单元。安装钩子把两者一并屏蔽：`/etc/systemd/user/com.seewo.easisidebar.service → /dev/null`（全局屏蔽，对所有账户包括登录界面上的账户生效）与 `/etc/systemd/system/com.ifpdos.udi.hotspot.service → /dev/null`，并清除所有 `.wants` 激活链接；
- **开关位置。** 设置 → 教育版设置 → 「希沃侧边栏开机自启」（`sidebar-autostart`）。开启时同时解除两者的屏蔽并重建激活链接，因此侧边栏不会脱离其 UDI 依赖单独启动；关闭时反向恢复默认状态；
- **`fonts-noto-cjk` 是硬性依赖。** 侧边栏的 Avalonia 界面写死了 `Noto Sans CJK SC`，而 DEB 没有声明 `Depends`，缺少该字体会在首帧崩溃并以 `StandardOutput=null` 静默重启。镜像通过 `config/package-lists/winduxedu-desktop.list.chroot` 安装该字体，安装钩子与 `scripts/validate-winduxedu-live-image.sh` 各断言一次；
- **菜单保持整洁。** 5 个希沃小工具的 `.desktop` 自带 `NoDisplay=true`，只在侧边栏内部注册使用；侧边栏本体保留开始菜单入口，可手动启动。
- **批注（桌面墨迹）小工具。** `com.seewo.easiminiapps.desktopinkannotation` 的 postinst 把 `miniapp.info` 复制到 `/etc/EasiSideBar/MiniApps/com.cvte.seewo.desktop_annotation`，侧边栏据此列出「批注」入口（`ExecutablePath` 指向厂商自带的 `DesktopInkAnnotation`，参数 `--from-easisidebar`）；安装钩子与校验脚本各断言该注册文件存在，侧边栏开启后即可用。

### 安装钩子内的厂商适配

收录文件本身不做任何修改（[`edu-software/README.md`](../edu-software/README.md) 规则 3），以下调整全部作用于**已安装的系统**，不触碰 `edu-software/` 中的原始分卷：

- **钉钉（DingTalk）无法启动。** `Elevator.sh` 把自带库目录放在 `LD_LIBRARY_PATH` 最前面；厂商 postinst 中按发行版删除过时库的循环写在 `for file in $(ls /home)` 内，在 `/home` 为空的镜像里根本不会执行，于是 `libm.so.6`、`libstdc++.so.6(.0.25)`、`libgbm.so.1.0.0`、`libGLX.so.0.0.0`、`libGLdispatch.so.0.0.0`、`libharfbuzz.so.0.20301.0` 压过系统库，系统 `libgtk-3.so.0` 报 `GLIBC_2.3x not found` 而无法启动。安装钩子在同样的条件下重跑该规则，并补上同一段循环本该完成的 `chmod 4755 chrome-sandbox`；
- **希沃白板的菜单入口。** `com.seewo.easinote5.desktop` 原本指向 `.../files/com.seewo.easinote5.sh`，安装钩子改指同目录下的 `EasiNote5`；仅当厂商脚本确实导出了 `LD_LIBRARY_PATH` 时，才生成 `/usr/local/bin/winduxedu-easinote5` 包装器承接该环境变量。希沃的自启与升级组件（`/etc/xdg/autostart` 中的升级项、升级用 systemd 单元、Electron 的 `app-update.yml`）一并移除或屏蔽，保证固定版本不被原地升级；
- **ONLYOFFICE 默认 PDF 阅读器。** `/etc/xdg/mimeapps.list` 写入 `application/pdf=<ONLYOFFICE 桌面条目>`，并在其 `.desktop` 中补上缺失的 `MimeType=application/pdf;`，使关联在没有用户级配置时也生效；
- **开始菜单收敛。** `xterm.desktop` 加 `NoDisplay=true`（`/etc/skel/Desktop` 下的桌面快捷方式副本保持可见），`guvcview.desktop` 直接删除；两者只从开始菜单消失，程序本身仍可调用。
