#!/usr/bin/env python3
"""Patch the vendored ElevenDE copy used by WinduxEdu only.

ElevenDE's desktop intentionally opens ordinary files through xdg-open. A
.desktop file is therefore treated as text unless the shell explicitly parses
its Exec field. Keep upstream untouched and add that behavior to the WinduxEdu
build copy so desktop application launchers behave like Windows shortcuts.

ElevenDE 3.6 grew native launcher handling (gio launch for .desktop files and a
localized Name= label), so those two hunks are skipped when the pinned upstream
revision already provides the behavior.  The WinduxEdu-specific launcher icon
mapping is still required and is re-anchored onto the 3.6 icon chain, and the
desktop record's Icon= field is widened so a vendor /opt/apps/... path is not
silently truncated into an icon that never renders.
"""
from pathlib import Path
import sys

if len(sys.argv) != 2:
    raise SystemExit("usage: patch-elevende-desktop-launcher.py PATH_TO_MAIN_C")

path = Path(sys.argv[1])
text = path.read_text()
applied = []

# --- hunk 1: execute .desktop launchers through Exec= ------------------------
old = '''    } else {
        /* files go to the DEFAULT application via xdg-open (MIME based).
         * The old "explorer.exe || xdg-open" never reached xdg-open because
         * explorer.exe happily "opens" any path -- which is why archives
         * and documents popped up in the file manager. */
        snprintf(cmd, sizeof cmd, "xdg-open '%s' || explorer.exe '%s'",
                 path, path);
    }
'''
new = '''    } else if (strstr(path, ".desktop") && access(path, R_OK) == 0) {
        /* ElevenDE desktop application shortcuts must execute Exec= directly.
         * Ordinary files continue to use the user's MIME association below. */
        FILE *df = fopen(path, "r");
        char line[1024];
        cmd[0] = 0;
        if (df) {
            while (fgets(line, sizeof line, df)) {
                if (!strncmp(line, "Exec=", 5)) {
                    snprintf(cmd, sizeof cmd, "%s", line + 5);
                    cmd[strcspn(cmd, "\\r\\n")] = 0;
                    break;
                }
            }
            fclose(df);
        }
        if (!cmd[0]) {
            snprintf(cmd, sizeof cmd, "xdg-open '%s' || explorer.exe '%s'",
                     path, path);
        }
    } else {
        /* files go to the DEFAULT application via xdg-open (MIME based). */
        snprintf(cmd, sizeof cmd, "xdg-open '%s' || explorer.exe '%s'",
                 path, path);
    }
'''
if new in text:
    pass
elif old in text:
    text = text.replace(old, new, 1)
    applied.append("open_path Exec parsing")
elif '"gio launch \'%s\' 2>/dev/null || xdg-open \'%s\'"' in text:
    # ElevenDE 3.6 executes .desktop launchers itself (glib resolves Exec=,
    # field codes and the desktop id), which is a superset of this hunk.
    pass
else:
    raise SystemExit("ElevenDE open_path block was not found; source layout changed")

# --- hunk 2: drop the .desktop suffix from the desktop label ----------------
old_label = '''            snprintf(ic[nic].label, sizeof ic[nic].label, "%s", de->d_name);
            snprintf(ic[nic].path, sizeof ic[nic].path, "%s/%s", dir, de->d_name);
'''
new_label = '''            size_t label_len = strlen(de->d_name);
            if (label_len > 8 && !strcmp(de->d_name + label_len - 8, ".desktop"))
                label_len -= 8;
            snprintf(ic[nic].label, sizeof ic[nic].label, "%.*s",
                     (int)label_len, de->d_name);
            snprintf(ic[nic].path, sizeof ic[nic].path, "%s/%s", dir, de->d_name);
'''
if new_label in text:
    pass
elif old_label in text:
    text = text.replace(old_label, new_label, 1)
    applied.append("desktop label suffix strip")
elif "read_desktop_entry(ic[nic].path" in text:
    # ElevenDE 3.6 reads the entry's localized Name= and only falls back to
    # stripping the .desktop suffix, so no WinduxEdu hunk is needed here.
    pass
else:
    raise SystemExit("ElevenDE desktop label block was not found; source layout changed")

# --- hunk 3: WinduxEdu launcher icon mapping --------------------------------
winduxedu_map = '''        /* ElevenDE enumerates ~/Desktop as ordinary files.  WinduxEdu therefore
         * maps its known launchers here, at the same layer as Install WinduxEdu,
         * instead of relying on the .desktop Icon= field. */
        if (strstr(ic[i].path, "/Install WinduxEdu.desktop"))
            nm = "winduxedu-installer";
        else if (strstr(ic[i].path, "/注册表编辑器.desktop"))
            nm = "linux-regedit";
        else if (strstr(ic[i].path, "/Microsoft Edge.desktop"))
            nm = "microsoft-edge";
        else if (strstr(ic[i].path, "/终端.desktop"))
            nm = "winduxedu-windowshit";
'''

old_icon = '        const char *nm = ic[i].is_dir ? "folder" : file_icon_name(ic[i].label);\n        int kind = ic[i].is_dir ? VI_FOLDER : VI_FILE;\n'
new_icon = '''        const char *nm = ic[i].is_dir ? "folder" : file_icon_name(ic[i].label);
        int kind = ic[i].is_dir ? VI_FOLDER : VI_FILE;
''' + winduxedu_map

# ElevenDE 3.6 icon chain: the mapping must run after it so WinduxEdu launchers
# keep their icon even when the entry ships an Icon= field of its own.
icon_chain_tail = '''        } else if (ic[i].icon[0]) {
            /* *.desktop launcher: use the entry's own Icon= (name or path),
               not a generic executable glyph */
            nm = ic[i].icon;
        }
'''

if winduxedu_map in text:
    pass
elif icon_chain_tail in text:
    text = text.replace(icon_chain_tail, icon_chain_tail + winduxedu_map, 1)
    applied.append("desktop icon mapping (3.6 chain)")
elif old_icon in text:
    text = text.replace(old_icon, new_icon, 1)
    applied.append("desktop icon mapping")
else:
    raise SystemExit("ElevenDE desktop icon block was not found; source layout changed")

# --- hunk 4: hold a whole vendor Icon= path in the desktop record ----------
# The desktop surface keeps the Icon= of a ~/Desktop record in a fixed field
# and passes it to theme_find() verbatim.  Every collected vendor DEB (Seewo,
# DingTalk, ...) declares Icon=/opt/apps/<id>/entries/icons/hicolor/<size>/
# apps/<id>.png, i.e. ~80 characters, so the value is snprintf-truncated into
# an unopenable path, theme_find() returns NULL and the launcher renders as a
# blank generic glyph.  The Start menu record has room for 128 bytes and never
# suffered from this, which is why only the desktop icons looked broken.
old_icon_field = 'typedef struct { int x, y; char label[64]; char path[512]; int is_dir; char icon[64]; } Icon;'
new_icon_field = 'typedef struct { int x, y; char label[64]; char path[512]; int is_dir; char icon[256]; } Icon;'
if new_icon_field in text:
    pass
elif old_icon_field in text:
    text = text.replace(old_icon_field, new_icon_field, 1)
    applied.append("desktop icon field widened")
else:
    raise SystemExit("ElevenDE desktop Icon record was not found; source layout changed")

path.write_text(text)
print(f"patched {path}" + (f" ({', '.join(applied)})" if applied else " (upstream already provides launchers/labels)"))
