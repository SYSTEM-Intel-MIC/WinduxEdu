# WinduxEdu 教育教学软件收录区（Proprietary Software Collection）

## 声明

1. **本目录下的所有软件均不属于开源软件。** 它们是各商业公司发布的专有（proprietary）二进制发行包，不适用 GPL/MIT 等任何开源许可证，其源码不受本仓库约束，也不因本仓库的 GPL-3.0 许可证而改变许可状态。
2. **这些软件与 SYSTEM-Intel-MIC 无关。** SYSTEM-Intel-MIC 不是其开发者、不是其分发渠道维护者、不拥有其商标，也不对其功能、安全性、更新或服务可用性提供任何保证、责任承担。Windows、Microsoft、Tencent、Alibaba/DingTalk、ONLYOFFICE、Seewo（希沃）等名称与商标归各自权利人所有。
3. **本仓库仅作收录（collection only）。** 文件按原样（as-is）收录，不做任何修改、重打包、去广告、注入或二次封装。
4. **版本不更换。** 每个文件的上游版本以 [`DEB-INVENTORY.tsv`](DEB-INVENTORY.tsv) 中记录的 `Package` / `Version` 字段为准，收录与构建流程均不得替换、降级、升级或改动这些文件的内容；任何文件被改动后其 SHA-256 必须与清单不符，即视为违规。
5. **分类结构保留原始归属。** 本目录的分类文件夹（`dingding/`、`Onlyoffice/`、`Seewo/`、`Tencent IM/`）为原维护者手动整理的分类，收录、引用与后续集成必须沿用该结构，不得合并、改名或重新归类。后续新增的**希沃侧边栏组件**单独存放于 `sidebar/`，不并入上述原维护者分类，也不改动任何既有条目。

## 分类与清单

| 分类文件夹 | 文件 | 包名 | 版本 | 大小 (MiB) |
| --- | --- | --- | --- | --- |
| `dingding/` | `com.alibabainc.dingtalk.deb` | com.alibabainc.dingtalk | 8.2.8.260818002 | 357.0 |
| `Onlyoffice/` | `onlyoffice.deb` | onlyoffice-desktopeditors | 9.4.0-129 | 347.8 |
| `Seewo/` | `希沃白板.deb` | com.seewo.easinote5 | 5.2.2.4.13701 | 161.1 |
| `Seewo/` | `希沃管家.deb` | com.seewo.terminalmanager | 3.0.6.716 | 245.0 |
| `Seewo/` | `班级优化大师.deb` | com.seewo.easicare | 2.1.0.3274 | 111.2 |
| `Seewo/` | `视频展台.deb` | com.seewo.easicamera | 2.0.5.2580 | 133.2 |
| `Tencent IM/` | `QQ.deb` | linuxqq | 3.2.34-53644 | 178.5 |
| `Tencent IM/` | `WeChat.deb` | wechat | 4.1.13.23 | 220.6 |
| `sidebar/` | `com.seewo.easisidebar_6.0.0.877_amd64.deb` | com.seewo.easisidebar | 6.0.0.877 | 32.1 |
| `sidebar/` | `UdiHotspotService-R.2.5.1.23-amd64.deb` | udi-hotspot-service | 2.5.1.23.R | 2.5 |
| `sidebar/` | `com.seewo.easiminiapps.desktopscreenshot_6.0.0.1152_amd64.deb` | com.seewo.easiminiapps.desktopscreenshot | 6.0.0.1152 | 9.9 |
| `sidebar/` | `com.seewo.easiminiapps.desktoptimer_6.0.0.1078_amd64.deb` | com.seewo.easiminiapps.desktoptimer | 6.0.0.1078 | 11.0 |
| `sidebar/` | `com.seewo.easiminiapps.luckyrandom_6.0.0.1071_amd64.deb` | com.seewo.easiminiapps.luckyrandom | 6.0.0.1071 | 48.8 |
| `sidebar/` | `com.seewo.easiminiapps.rollcall_6.0.0.1071_amd64.deb` | com.seewo.easiminiapps.rollcall | 6.0.0.1071 | 46.5 |
| `sidebar/` | `com.seewo.easiminiapps.desktopinkannotation_6.0.0.1069_amd64.deb` | com.seewo.easiminiapps.desktopinkannotation | 6.0.0.1069 | 10.0 |

合计 15 个文件（原维护者收录的 8 个 + 后续新增的希沃侧边栏组件 7 个），约 1.87 GiB。完整的 `Package` / `Version` / `Architecture` / `Size` / `SHA-256` 机器可读清单见 [`DEB-INVENTORY.tsv`](DEB-INVENTORY.tsv)（制表符分隔，UTF-8）。

## 分卷存储

为遵守 GitHub 单文件 100 MB 上限，本目录**不存放完整 `.deb`**，而是以 **50 MiB 固定分卷**存放：每个文件按原名切分为 `原名.deb.000`、`原名.deb.001` …，保持在上表的分类文件夹内。例如 `Seewo/希沃白板.deb` 存为 `Seewo/希沃白板.deb.000` … `希沃白板.deb.003`。

- 逐卷清单（文件、卷号、大小、SHA-256）：[`PARTS-INDEX.tsv`](PARTS-INDEX.tsv)
- 整文件清单（重组后 SHA-256）：[`DEB-INVENTORY.tsv`](DEB-INVENTORY.tsv)
- 重组脚本：[`../scripts/assemble-edu-debs.py`](../scripts/assemble-edu-debs.py)

DEB 内部数据本身已是压缩格式，分卷仅为切块存储（无二次压缩）；重组结果与原文件**逐字节相同**，因此不构成对文件的修改。

## 完整性校验与重组

任何构建或发布流程在使用这些文件前必须先校验：

```sh
# 1) 校验全部分卷（不生成完整文件）
python3 scripts/assemble-edu-debs.py --check

# 2) 重组到 artifacts/edu-debs/（已被 .gitignore 忽略）
#    逐卷校验 SHA-256 → 拼接 → 整文件 SHA-256 校验
python3 scripts/assemble-edu-debs.py
```

重组脚本先按 `PARTS-INDEX.tsv` 校验每一卷，再按 `DEB-INVENTORY.tsv` 校验整文件；任何一步不匹配即以非零状态退出并中止。校验失败必须中止构建，禁止用其他来源的同名文件替换，禁止更换版本。

## 与构建系统的关系

- 这些文件**不进入** `packages/sources.lock.tsv`（该锁只记录可审计的开源 Git 来源），也**不进入** `packages/binaries.lock.tsv`（该锁只记录有官方公开 URL 的发行 DEB）。
- 它们以本目录为唯一来源，由后续的集成步骤按 `DEB-INVENTORY.tsv` 校验后装入 Live 镜像；在此之前本目录只作收录与存档。
- 本目录内容不适用仓库根目录的 GPL-3.0 许可证，见 [`../THIRD-PARTY-NOTICES.md`](../THIRD-PARTY-NOTICES.md) 的对应说明。
