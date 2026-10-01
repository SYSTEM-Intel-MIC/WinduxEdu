#!/usr/bin/env python3
"""Add the WinduxEdu 教育版设置 page to the ElevenDE settings application.

ElevenDE ships settings pages built from main.cpp (navigation, page stack and
home grid) plus extra.cpp (the exported page builders declared in pages.h).
This patch adds one page and wires it in at three fixed anchors:

  * a fourth column entry "教育版设置" in the left navigation,
  * ``m_stack->addWidget(buildEduPage())`` right after the users page so the
    page index stays aligned with the navigation index (the home grid's action
    rows carry the target index, appended as 12),
  * ``buildEduPage()`` itself at the end of extra.cpp, next to the other
    exported builders.

The page drives /usr/local/bin/winduxedu-edu-settings (get/set/list-seewo/
uninstall-seewo), so the actual state always comes from the system rather than
from a copy held by the UI:

  * 屏幕键盘                screen-keyboard        per user, default off
  * 希沃管家开机自启         seewo-autostart        system,    default off
                            (hint: 建议希沃一体机开启，其它设备关闭)
  * 希沃侧边栏开机自启       sidebar-autostart      system,    default off,
                            switches the sidebar user unit *and* its UDI
                            hotspot dependency together
  * 希沃类软件一键卸载        list-seewo / uninstall-seewo, one row per package

Every key is re-read on a two second timer while the page is visible, so a
switch flipped from a terminal, a vendor package being removed, or the polkit
prompt still being on screen all show up without reopening the page.

Run with the settings source directory and the shared icon tree::

    scripts/patch-elevende-settings-education.py \
        path/to/ElevenDE/apps/settings path/to/ElevenDE/assets/icons

The script is idempotent: a tree that already carries the page is reported as
already applied and left untouched.
"""

import os
import shutil
import sys

MARKER = "buildEduPage"

NAV_TAIL = (
    '            { "settings-nav-power", "电源" }, '
    '{ "settings-nav-users", "用户" }\n'
    "        };"
)
NAV_TAIL_NEW = (
    '            { "settings-nav-power", "电源" }, '
    '{ "settings-nav-users", "用户" },\n'
    '            { "settings-nav-edu", "教育版设置" }\n'
    "        };"
)

STACK_ANCHOR = "        m_stack->addWidget(ElevenSettings::buildUsersPage());\n"
STACK_ANCHOR_NEW = (
    "        m_stack->addWidget(ElevenSettings::buildUsersPage());\n"
    "        m_stack->addWidget(ElevenSettings::buildEduPage());\n"
)

HOME_ANCHOR = (
    '        homeActionRow(QStringLiteral("settings-nav-network"), '
    'QStringLiteral("网络和 Internet"), '
    'QStringLiteral("网络接口和连接状态"), 4)\n'
    '    }), QStringLiteral("ElevenDE 已提供的系统功能")));'
)
HOME_ANCHOR_NEW = (
    '        homeActionRow(QStringLiteral("settings-nav-network"), '
    'QStringLiteral("网络和 Internet"), '
    'QStringLiteral("网络接口和连接状态"), 4),\n'
    '        homeActionRow(QStringLiteral("settings-nav-edu"), '
    'QStringLiteral("教育版设置"), '
    'QStringLiteral("屏幕键盘、希沃自启与一键卸载"), 12)\n'
    '    }), QStringLiteral("ElevenDE 已提供的系统功能")));'
)

PAGES_ANCHOR = "QWidget *buildUsersPage();\n"
PAGES_ANCHOR_NEW = "QWidget *buildUsersPage();\nQWidget *buildEduPage();\n"

EXTRA_ANCHOR = "} // namespace ElevenSettings"

EDU_PAGE = r'''
/* ---------- 教育版设置 (WinduxEdu) ---------- */

namespace {

QString eduToolPath()
{
    return QStringLiteral("/usr/local/bin/winduxedu-edu-settings");
}

// Returns the system truth for a key; an empty answer (tool missing, not yet
// installed) falls back to the documented default instead of guessing.
bool eduRead(const QString &key, bool fallback)
{
    const QString out =
        runOut(eduToolPath(), { QStringLiteral("get"), key }).trimmed();
    if (out.isEmpty())
        return fallback;
    return out == QStringLiteral("1") || out == QStringLiteral("true");
}

// The system-level switches escalate through winduxedu-privileged-action and
// the WinduxEdu polkit rule, which already returns YES for the live and
// installed users.  Detached so the settings window never waits on it.
void eduWrite(const QString &key, bool on)
{
    QProcess::startDetached(eduToolPath(),
                            { QStringLiteral("set"), key,
                              on ? QStringLiteral("1") : QStringLiteral("0") });
}

struct EduToggle {
    QString key;
    QCheckBox *box;
    bool fallback;
};

struct EduState {
    QList<EduToggle> toggles;
    QString listing;
};

QWidget *eduToggleRow(const QString &title, const QString &detail,
                      const QString &key, bool fallback, EduState *state)
{
    auto *row = new QWidget();
    auto *h = new QHBoxLayout(row);
    h->setContentsMargins(0, 0, 0, 0);
    h->setSpacing(12);

    auto *text = new QWidget(row);
    auto *tv = new QVBoxLayout(text);
    tv->setContentsMargins(0, 0, 0, 0);
    tv->setSpacing(2);

    auto *t = new QLabel(title, text);
    QFont tf = t->font();
    tf.setPointSizeF(10.5);
    tf.setBold(true);
    t->setFont(tf);
    tv->addWidget(t);

    auto *d = new QLabel(detail, text);
    d->setWordWrap(true);
    d->setProperty("subtle", true);
    tv->addWidget(d);

    auto *box = new QCheckBox(row);
    box->setChecked(eduRead(key, fallback));
    state->toggles.append({ key, box, fallback });

    h->addWidget(text, 1);
    h->addWidget(box, 0, Qt::AlignVCenter);

    QObject::connect(box, &QCheckBox::toggled, [key](bool on) {
        eduWrite(key, on);
    });
    return row;
}

// One row per installed Seewo package: name, package id and a confirm-then-
// detached uninstall button.  Returns the listing so the refresh timer can
// detect that the set of packages changed.
QString eduFillUninstall(QWidget *container, QVBoxLayout *lay)
{
    QLayoutItem *old = nullptr;
    while ((old = lay->takeAt(0)) != nullptr) {
        if (old->widget())
            old->widget()->deleteLater();
        delete old;
    }

    const QString listing =
        runOut(eduToolPath(), { QStringLiteral("list-seewo") });
    const QStringList rows =
        listing.split(QLatin1Char('\n'), Qt::SkipEmptyParts);

    if (rows.isEmpty()) {
        auto *none =
            new QLabel(QStringLiteral("没有检测到已安装的希沃类软件。"), container);
        none->setWordWrap(true);
        none->setProperty("subtle", true);
        lay->addWidget(none);
        return listing;
    }

    for (const QString &raw : rows) {
        const QString line = raw.trimmed();
        if (line.isEmpty())
            continue;
        const QStringList cols =
            line.split(QLatin1Char('\t'), Qt::SkipEmptyParts);
        const QString pkg = cols.value(0);
        if (pkg.isEmpty())
            continue;
        const QString label = cols.value(1, pkg);

        auto *row = new QWidget(container);
        auto *rh = new QHBoxLayout(row);
        rh->setContentsMargins(0, 0, 0, 0);
        rh->setSpacing(12);

        auto *names = new QWidget(row);
        auto *nv = new QVBoxLayout(names);
        nv->setContentsMargins(0, 0, 0, 0);
        nv->setSpacing(1);

        auto *l1 = new QLabel(label, names);
        QFont lf = l1->font();
        lf.setPointSizeF(10.5);
        lf.setBold(true);
        l1->setFont(lf);
        nv->addWidget(l1);

        auto *l2 = new QLabel(pkg, names);
        l2->setProperty("subtle", true);
        nv->addWidget(l2);

        auto *btn = new QPushButton(QStringLiteral("卸载"), row);
        rh->addWidget(names, 1);
        rh->addWidget(btn, 0, Qt::AlignVCenter);

        QObject::connect(btn, &QPushButton::clicked, row, [pkg, label]() {
            const auto answer = QMessageBox::question(
                nullptr,
                QStringLiteral("卸载 %1").arg(label),
                QStringLiteral("确定卸载 %1 吗？软件本体将被移除，已生成的文件不会被清除。")
                    .arg(label),
                QMessageBox::Yes | QMessageBox::No, QMessageBox::No);
            if (answer != QMessageBox::Yes)
                return;
            QProcess::startDetached(eduToolPath(),
                                    { QStringLiteral("uninstall-seewo"), pkg });
        });
        lay->addWidget(row);
    }
    return listing;
}

} // namespace

QWidget *buildEduPage()
{
    auto *state = new EduState();

    auto *page = new QWidget();
    auto *outer = new QWidget();
    auto *v = new QVBoxLayout(outer);
    v->setContentsMargins(32, 24, 32, 24);
    v->setSpacing(12);
    v->addWidget(xHeading(QStringLiteral("教育版设置")));

    auto *intro = new QLabel(QStringLiteral(
        "WinduxEdu 面向教学场景的开关。默认全部关闭：只有在希沃一体机上才需要"
        "打开希沃管家，侧边栏与其 UDI 依赖则是第三方互联网软件。"
        "标注为系统级的开关会请求管理员授权；页面每两秒重新读取一次真实状态。"),
        outer);
    intro->setWordWrap(true);
    intro->setProperty("subtle", true);
    v->addWidget(intro);

    v->addWidget(xCard(QStringLiteral("屏幕键盘"),
                       eduToggleRow(QStringLiteral("输入时弹出屏幕键盘"),
                                    QStringLiteral("输入文字时自动弹出，登录界面同样生效；"
                                                   "实现为 matchbox-keyboard（GPL-2-or-later，"
                                                   "许可见 /usr/share/doc/"
                                                   "matchbox-keyboard/copyright）。"),
                                    QStringLiteral("screen-keyboard"),
                                    false,
                                    state)));

    v->addWidget(xCard(QStringLiteral("希沃"),
                       eduToggleRow(QStringLiteral("希沃管家开机自启"),
                                    QStringLiteral("建议希沃一体机开启，其它设备关闭；"
                                                   "同时接管希沃的开机自启组件。"),
                                    QStringLiteral("seewo-autostart"),
                                    false,
                                    state)));

    v->addWidget(xCard(QStringLiteral("第三方侧边栏"),
                       eduToggleRow(QStringLiteral("希沃侧边栏开机自启"),
                                    QStringLiteral("侧边栏与其依赖的 UDI 热点服务均为"
                                                   "第三方互联网软件、非开源，与 WinduxEdu / "
                                                   "SYSTEM-Intel-MIC 无关；默认关闭，"
                                                   "打开时一并启用依赖服务。"),
                                    QStringLiteral("sidebar-autostart"),
                                    false,
                                    state)));

    auto *unHost = new QWidget();
    auto *unLay = new QVBoxLayout(unHost);
    unLay->setContentsMargins(0, 0, 0, 0);
    unLay->setSpacing(6);
    state->listing = eduFillUninstall(unHost, unLay);
    v->addWidget(xCard(QStringLiteral("希沃类软件一键卸载"),
                       unHost,
                       QStringLiteral("按软件分别卸载，卸载完成后本列表会自动刷新")));

    auto *foot = new QLabel(QStringLiteral(
        "命令行为 winduxedu-edu-settings get|set|status|list-seewo|uninstall-seewo；"
        "用户级开关写入 ~/.config/winduxedu/edu-settings.conf，"
        "系统级开关写入 /etc/winduxedu/edu-settings.conf。"), outer);
    foot->setWordWrap(true);
    foot->setProperty("subtle", true);
    v->addWidget(foot);

    v->addStretch(1);

    auto *lay = new QVBoxLayout(page);
    lay->setContentsMargins(0, 0, 0, 0);
    lay->addWidget(xScroll(outer));

    // Re-read both the switches and the package list while the page is open,
    // so an external change (a terminal, a polkit prompt, an uninstall that has
    // just finished) is reflected without reopening the page.
    auto *timer = new QTimer(page);
    QObject::connect(timer, &QTimer::timeout, page,
                     [page, state, unHost, unLay]() {
        if (!page->isVisible())
            return;
        for (const EduToggle &t : state->toggles) {
            const bool now = eduRead(t.key, t.fallback);
            if (t.box->isChecked() != now) {
                t.box->blockSignals(true);
                t.box->setChecked(now);
                t.box->blockSignals(false);
            }
        }
        const QString listing =
            runOut(eduToolPath(), { QStringLiteral("list-seewo") });
        if (listing != state->listing) {
            state->listing = listing;
            eduFillUninstall(unHost, unLay);
        }
    });
    timer->start(2000);

    QObject::connect(page, &QObject::destroyed, [state]() { delete state; });
    return page;
}
'''


def fail(message):
    print("patch-elevende-settings-education: error: " + message, file=sys.stderr)
    raise SystemExit(1)


def read_text(path):
    with open(path, encoding="utf-8") as handle:
        return handle.read()


def write_text(path, text):
    with open(path, "w", encoding="utf-8") as handle:
        handle.write(text)


def replace_once(path, old, new, what):
    text = read_text(path)
    if text.count(old) != 1:
        fail(
            "%s: expected exactly one anchor for %s, found %d"
            % (path, what, text.count(old))
        )
    write_text(path, text.replace(old, new, 1))
    print("  + %s" % what)


def ensure_icons(icons):
    """The navigation and home grid resolve icons through the shared
    settings-nav-<id>.png convention; reuse the 系统 glyph for the new entry."""
    if not os.path.isdir(icons):
        fail("icon tree not found: %s" % icons)
    copied = 0
    for group in sorted(os.listdir(icons)):
        apps = os.path.join(icons, group, "apps")
        source = os.path.join(apps, "settings-nav-system.png")
        target = os.path.join(apps, "settings-nav-edu.png")
        if not os.path.isfile(source):
            continue
        if not os.path.isfile(target):
            shutil.copyfile(source, target)
            copied += 1
    if copied == 0:
        # Already present from a previous run, but make sure at least one copy
        # exists so the menu never shows an empty glyph.
        if not any(
            os.path.isfile(os.path.join(icons, g, "apps", "settings-nav-edu.png"))
            for g in os.listdir(icons)
        ):
            fail("no settings-nav-system.png found to derive settings-nav-edu.png")
    print("  + settings-nav-edu.png icon (%d new)" % copied)


def main(argv):
    if len(argv) != 3:
        fail(
            "usage: patch-elevende-settings-education.py "
            "<eleven-settings-dir> <eleven-icons-dir>"
        )

    settings = os.path.abspath(argv[1])
    icons = os.path.abspath(argv[2])
    main_cpp = os.path.join(settings, "main.cpp")
    pages_h = os.path.join(settings, "pages.h")
    extra_cpp = os.path.join(settings, "extra.cpp")
    for path in (main_cpp, pages_h, extra_cpp):
        if not os.path.isfile(path):
            fail("missing %s (is %s the ElevenDE settings dir?)" % (path, settings))
    if not os.path.isdir(icons):
        fail("icon tree not found: %s" % icons)

    present = all(
        MARKER in read_text(path) for path in (main_cpp, pages_h, extra_cpp)
    )
    if present:
        ensure_icons(icons)
        print("教育版设置 page already applied; nothing to do")
        return 0

    print("applying 教育版设置 page")
    replace_once(main_cpp, NAV_TAIL, NAV_TAIL_NEW, "navigation entry")
    replace_once(main_cpp, STACK_ANCHOR, STACK_ANCHOR_NEW, "page stack entry")
    replace_once(main_cpp, HOME_ANCHOR, HOME_ANCHOR_NEW, "home grid row")
    replace_once(pages_h, PAGES_ANCHOR, PAGES_ANCHOR_NEW, "pages.h declaration")

    extra = read_text(extra_cpp)
    if extra.count(EXTRA_ANCHOR) != 1:
        fail(
            "expected exactly one %r in %s, found %d"
            % (EXTRA_ANCHOR, extra_cpp, extra.count(EXTRA_ANCHOR))
        )
    if not extra.endswith("\n"):
        extra += "\n"
    index = extra.rindex(EXTRA_ANCHOR)
    extra = extra[:index] + EDU_PAGE.lstrip("\n") + "\n" + extra[index:]
    write_text(extra_cpp, extra)
    print("  + buildEduPage() in extra.cpp")

    ensure_icons(icons)
    print("教育版设置 page applied")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
