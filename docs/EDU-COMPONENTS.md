# WinduxEdu 教育教学组件来源声明

本文档声明 WinduxEdu 1.0 中全部**教学软件**的来源、版本与许可证。教学软件只有一类：

1. **专有软件收录区**——非开源、仅收录，独立存放在 [`edu-software/`](../edu-software/)，声明见 [`edu-software/README.md`](../edu-software/README.md)。

收录区组件**不属于开源软件，与 SYSTEM-Intel-MIC 无关，仅按原样收录且版本不更换**。

> 屏幕键盘等 Debian 源内的开源组件**不是教学软件**：`onboard` 属于触屏输入/无障碍组件，随硬件兼容层安装，声明见 [`HARDWARE-COMPATIBILITY.md`](HARDWARE-COMPATIBILITY.md) §4。

## 一、专有软件收录区（edu-software/）

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
- **希沃管家的后端常开，只有登录弹窗归开关管**：`com.seewo.terminalmanager.service`（`hugo_launcher --runmode=daemon`，希沃管家窗口要对话的后端）在镜像里保持 **enabled**（`/etc/systemd/system/multi-user.target.wants` 软链）——屏蔽它时窗口照样能从开始菜单打开，却拿不到任何响应，正是实测到的 `Cannot read property 'data' of undefined`。`com.cvte.maxhub.alfred.service` 与 `disable-seewo-network-card.service` 仍通过 `/etc/systemd/system` 下指向 `/dev/null` 的软链屏蔽（单元文件本身仍归 dpkg 所有）。登录时是否自动弹出管家窗口由 `教育版设置 → 希沃管家开机自启` 决定：默认删除 `/etc/xdg/autostart/com.seewo.terminalmanager.desktop` 与 `/home/*/Desktop` 下的副本，开启时恢复；窗口本身始终可从开始菜单启动。管家的菜单入口原本是 0 字节占位文件，安装钩子会用 postinst 生成在 `/opt/apps/.../entries/applications/` 的真文件覆盖它，校验脚本额外断言该文件非空；
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
- **希沃白板的菜单入口。** `com.seewo.easinote5.desktop` 原本指向 `.../files/com.seewo.easinote5.sh`，安装钩子改指同目录下的 `EasiNote5`；仅当厂商脚本确实导出了 `LD_LIBRARY_PATH` 时，才生成 `/usr/local/bin/winduxedu-easinote5` 包装器承接该环境变量。希沃的自启与升级组件（`/etc/xdg/autostart` 中的升级项、升级用 systemd 单元、Electron 的 `app-update.yml`）一并移除或屏蔽，保证固定版本不被原地升级；上述三层只管“不自动装”，管不住白板自己“去问”——它还带着一次与 electron-updater 无关的 HTTP 检查，打向监测报告抓到的 `https://ota-gateway.seewo.com/api/v1/update`，只要端点在线就可能回 `{"hasUpdate":true}`，故把 `ota-gateway.seewo.com` 指向 `127.0.0.1` 让连接立刻被拒；只封这一个域，`enweb3.seewo.com` 是登录与课件主 API，必须保持可达。这一步**只能在开机做**：`/etc/hosts` 归 live-build 所有——`lb_chroot_hosts` 把构建机的该文件挂进 chroot，`lb_binary` 再用它覆盖成品目录，于是钩子写入或 `includes.chroot` 投放的行在 ISO 校验之前就已消失（run 38923665983 实证：钩子日志显示写入成功，校验器在 ISO 里却一无所获）。故新增 `winduxedu-seewo-ota-block.service`（oneshot，`ExecStart=/usr/local/bin/winduxedu-seewo-ota-block`）在启动时幂等地补这一行，Live 会话与安装版一并生效；钩子以显式 `.wants` 软链启用它，理由与显示服务相同：chroot 内 preset 状态不可靠。校验器据此断言单元存在**且已启用**、助手只点名 OTA 域且完全不提 enweb3，而不是去查 `/etc/hosts` 的内容；
- **ONLYOFFICE 默认 PDF 阅读器。** `/etc/xdg/mimeapps.list` 写入 `application/pdf=<ONLYOFFICE 桌面条目>`，并在其 `.desktop` 中补上缺失的 `MimeType=application/pdf;`，使关联在没有用户级配置时也生效；
- **开始菜单收敛。** `xterm.desktop` 加 `NoDisplay=true`（`/etc/skel/Desktop` 下的桌面快捷方式副本保持可见），`guvcview.desktop` 直接删除；两者只从开始菜单消失，程序本身仍可调用。
- **桌面快捷方式的图标。** 厂商条目普遍写死 `Icon=/opt/apps/<id>/entries/icons/hicolor/<size>/apps/<id>.png`（希沃白板 79 字符），而 ElevenDE 桌面记录曾用 `char icon[64]` 原样保存再 `snprintf`，路径被截断成不存在的串，`theme_find()` 返回 NULL，图标渲染成空白通用字形；即使不截断，`theme_find()` 也从不搜索 `/opt/apps/**`，其 hicolor 尺寸表还没有 256/512。安装钩子因此一次性解析每个快捷方式的图标：在 `/opt/apps`、`/usr/share/icons`、`/usr/share/pixmaps` 中按绝对路径、裸名字、桌面条目名三级查找，优先取厂商自带的同尺寸渲染，发布到 `usr/local/share/elevende-shell/icons/{32,48,64,128,256}x*/apps/<短名>.{png,svg}`（ElevenDE 桌面、开始菜单、任务栏都会先查这个命名空间），并把桌面副本与 `/usr/share/applications` 中的厂商条目一并改写为该短名；`patch-elevende-desktop-launcher.py` 同时把记录字段扩到 `icon[256]`，让用户自行拖入桌面、仍带厂商长路径的条目也能正常显示。以上只覆盖**构建期写好的快捷方式**；希沃应用启动后还会自己往 `~/Desktop`、`~/.local/share/applications` 回写记录，那种记录带 `Name`/`Exec` 却缺 `Icon=` 或指向不存在的文件，原 `winduxedu-desktop-tidy` 补完 `Name`/`Exec` 就放行，桌面上遂成“有条目但图标空白/通用图”。该助手现在也校验 `Icon=`：按 `theme_find()` 的实际查找规则判断该值能否真的打开——绝对路径要求能放进记录字段（256 字节）且 `access()` 可读，裸名字要在 `elevende-shell/icons` 命名空间、`pixmaps` 或常见主题里能解析——不能则依次回退到打包条目的 `Icon=`、再到本条目 id 名下已发布的图标；改写只动 `[Desktop Entry]` 组内那一处，各 `[Desktop Action]` 自己的图标原样保留。同时它把 `~/Desktop`、`~/桌面` 与 `xdg-user-dir DESKTOP` 指向的目录**一起**清扫：ElevenDE 只读 `$HOME/Desktop`，而 zh_CN 会话里 `xdg-user-dir DESKTOP` 回 `~/桌面`，只修后者等于没修到真正被绘制的记录。
- **希沃工具条被主窗口遮挡。** 监测报告的三个窗口里，工具条 `0x04000007`（280×64+68+1036）与主窗口 `0x04000006`（2307×1237+0+35）**都**声明 `_NET_WM_STATE_ABOVE`，所以按状态判断永远得出“已经在最上层”：原助手正是停在 `already_above "$id" && continue` 处空转——用报告里的真实窗口 id 复现时，它一次系统调用都不发。真正的故障是**相对顺序**，批注模式下主窗口爬到工具条之上，点击全部落在白板上。助手改为每 1 秒读 `_NET_CLIENT_LIST_STACKING`（`xprop` 给 `0x4000007`、`wmctrl` 给 `0x04000007`，先归一化成十进制再比），按“浮动窗口类型，或不足整屏 60%”把希沃窗口分成工具条与主窗口两组，仅当主窗口的堆叠序号高于工具条时用 `xdotool windowraise` 提升（不抢焦点，wmctrl `remove,above`/`add,above` 兜底），并把丢失的 `ABOVE` 补回；几何按 `WxH+X+Y` 的**形状**从 `wmctrl -lG -x` 输出中识别而非按列号取——列数随版本与旗标变化，取错会让窗口被整体跳过。覆盖状态只在开始时记一条日志，避免批注全程每秒刷屏。这两条改动连同 `StartupWMClass=` 一并由 `validate-winduxedu-live-image.sh` 断言。
- **希沃应用的任务栏图标。** ElevenDE 先按 `StartupWMClass=`（忽略大小写）或条目 id 词干匹配窗口，再退回瞬态 `_NET_WM_ICON`。原实现从**改写前**的 `Exec=…/com.seewo.easinote5.sh` 派生出 `StartupWMClass=com.seewo.easinote5.sh`，而运行时 `WM_CLASS` 是 `EasiNote5`/`easinote5`，两者对不上、id 词干也不相等，`desktop_icon_for_class()` 返回 NULL，任务栏按钮没有图标源。派生改为在**所有 `Exec=` 改写之后**执行，并先解开启动器：厂商 `.sh`（`班级优化大师`、`视频展台` 至今仍在用）以及 `winduxedu-*` 包装器都只是 `exec` 真正的程序，窗口管理器只认那个程序名；解开结果若是解释器则退回启动器名——那至少还属于本应用。派生值插进 `[Desktop Entry]` 组内（原先追加到文件末尾会掉进 `[Desktop Action]` 组），校验器据此断言四个希沃条目均有 `StartupWMClass=`、且既不以 `.sh` 结尾也不指向 `winduxedu-` 包装器。
