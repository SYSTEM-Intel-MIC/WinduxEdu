# WinduxEdu 教育教学组件来源声明

本文档声明 WinduxEdu 1.0 中全部教育教学软件的**来源、版本与许可证**。组件分为两类：

1. **开源教育组件**——来自 Debian Bookworm 官方软件源（`deb.debian.org`），版本由 Bookworm 发行版固定；
2. **专有软件收录区**——非开源、仅收录，独立存放在 [`edu-software/`](../edu-software/)，声明见 [`edu-software/README.md`](../edu-software/README.md)。

两类组件的边界不可混淆：开源组件受其自身开源许可证约束并可追溯到上游源码；收录区组件**不属于开源软件，与 SYSTEM-Intel-MIC 无关，仅按原样收录且版本不更换**。

## 一、开源教育组件（Debian Bookworm 官方源）

安装清单：[`config/package-lists/winduxedu-education.list.chroot`](../config/package-lists/winduxedu-education.list.chroot)。构建时由 live-build 从 Bookworm 归档安装，不经过第三方源，不执行上游安装脚本。

### OpenBoard（开源白板）

| 项目 | 值 |
| --- | --- |
| 功能 | 面向课堂教学的交互式电子白板 |
| Debian 源包 | `openboard` |
| Bookworm 固定版本 | `1.6.4+dfsg-1+b1`（amd64） |
| 上游项目 | [OpenBoard-org/OpenBoard](https://github.com/OpenBoard-org/OpenBoard) |
| 上游站点 | <https://openboard.ch> |
| 许可证 | GPL-3.0（Debian 打包声明：`GPL-3 with OpenSSL exception`） |
| 获取途径 | Debian Bookworm `main`（`http://deb.debian.org/debian`） |
| 本仓库改动 | 无。仅通过包清单安装官方二进制，不打补丁、不重打包 |

> Debian 的 OpenBoard 为 dfsg 重打包版：移除了部分含内嵌第三方 JS/资源的 Web Widget（见 Debian `debian/copyright` 中的 Comment），其余为上游原代码。

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
