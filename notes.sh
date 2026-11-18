#!/usr/bin/env bash
# notes.sh - Quick Notes for the GNOME top bar (Fedora / GNOME 45+)
# A note icon on the top-left. Click it -> floating box with your notes
# and an "Add note" box at the bottom. Notes are saved and survive reboots.
#
# Usage:
#   bash notes.sh           -> install & enable
#   bash notes.sh --remove  -> disable & uninstall (your saved notes are kept)

set -euo pipefail

UUID="quick-notes@local"
EXT_DIR="$HOME/.local/share/gnome-shell/extensions/$UUID"

# ---------- uninstall ----------
if [[ "${1:-}" == "--remove" ]]; then
    gnome-extensions disable "$UUID" 2>/dev/null || true
    current=$(gsettings get org.gnome.shell enabled-extensions)
    new=$(echo "$current" | sed "s/, *'$UUID'//; s/'$UUID', *//; s/'$UUID'//")
    gsettings set org.gnome.shell enabled-extensions "$new"
    rm -rf "$EXT_DIR"
    echo "✔ Removed. Log out and back in to clear it from the top bar."
    echo "  Your notes are still saved in ~/.local/share/quick-notes/notes.json"
    exit 0
fi

# ---------- checks ----------
if ! command -v gnome-shell >/dev/null; then
    echo "✘ gnome-shell not found. This script is for GNOME desktops only." >&2
    exit 1
fi

SHELL_MAJOR=$(gnome-shell --version | grep -oE '[0-9]+' | head -n1)
if (( SHELL_MAJOR < 45 )); then
    echo "✘ GNOME $SHELL_MAJOR detected. This script needs GNOME 45 or newer." >&2
    exit 1
fi
echo "• Detected GNOME Shell $SHELL_MAJOR"

mkdir -p "$EXT_DIR"

# ---------- metadata.json ----------
cat > "$EXT_DIR/metadata.json" <<EOF
{
  "uuid": "$UUID",
  "name": "Quick Notes",
  "description": "Take quick notes from the top bar",
  "shell-version": ["45", "46", "47", "48", "49", "50", "$SHELL_MAJOR"]
}
EOF

# ---------- extension.js ----------
cat > "$EXT_DIR/extension.js" <<'EOF'
import St from 'gi://St';
import GLib from 'gi://GLib';
import Clutter from 'gi://Clutter';
import Pango from 'gi://Pango';
import {Extension} from 'resource:///org/gnome/shell/extensions/extension.js';
import * as Main from 'resource:///org/gnome/shell/ui/main.js';
import * as PanelMenu from 'resource:///org/gnome/shell/ui/panelMenu.js';
import * as PopupMenu from 'resource:///org/gnome/shell/ui/popupMenu.js';

const NOTES_DIR = GLib.build_filenamev([GLib.get_user_data_dir(), 'quick-notes']);
const NOTES_FILE = GLib.build_filenamev([NOTES_DIR, 'notes.json']);

// Vertical box that works on both old (vertical) and new (orientation) GNOME
function vbox(params) {
    const box = new St.BoxLayout(params);
    if ('orientation' in box)
        box.orientation = Clutter.Orientation.VERTICAL;
    else
        box.vertical = true;
    return box;
}

export default class QuickNotesExtension extends Extension {
    enable() {
        this._notes = this._load();

        // Top-bar button with a note icon
        this._button = new PanelMenu.Button(0.0, 'Quick Notes', false);
        this._button.add_child(new St.Icon({
            icon_name: 'document-edit-symbolic',
            style_class: 'system-status-icon',
        }));

        // ---- Notes list (scrollable) ----
        this._listBox = vbox({style_class: 'quick-notes-list', x_expand: true});
        this._scroll = new St.ScrollView({
            style_class: 'quick-notes-scroll',
            overlay_scrollbars: true,
            x_expand: true,
        });
        this._scroll.set_policy(St.PolicyType.NEVER, St.PolicyType.AUTOMATIC);
        if (this._scroll.set_child)
            this._scroll.set_child(this._listBox);
        else
            this._scroll.add_actor(this._listBox);

        const listSection = new PopupMenu.PopupMenuSection();
        listSection.actor.add_child(this._scroll);
        this._button.menu.addMenuItem(listSection);

        this._separator = new PopupMenu.PopupSeparatorMenuItem();
        this._button.menu.addMenuItem(this._separator);

        // ---- "Add note" row (always at the bottom) ----
        const addItem = new PopupMenu.PopupBaseMenuItem({reactive: false, can_focus: false});
        addItem.add_style_class_name('quick-notes-add-row');

        this._entry = new St.Entry({
            hint_text: 'Write a note…',
            style_class: 'quick-notes-entry',
            can_focus: true,
            x_expand: true,
        });
        this._entry.clutter_text.connect('activate', () => this._addNote());

        const addButton = new St.Button({
            label: 'Add note',
            style_class: 'button quick-notes-add',
            can_focus: true,
        });
        addButton.connect('clicked', () => this._addNote());

        addItem.add_child(this._entry);
        addItem.add_child(addButton);
        this._button.menu.addMenuItem(addItem);

        // Put the cursor in the text box whenever the popup opens
        this._button.menu.connect('open-state-changed', (_menu, open) => {
            if (!open)
                return;
            this._clearFocusSource();
            this._focusSource = GLib.idle_add(GLib.PRIORITY_DEFAULT, () => {
                global.stage.set_key_focus(this._entry);
                this._focusSource = 0;
                return GLib.SOURCE_REMOVE;
            });
        });

        this._rebuildList();

        // Left side of the top bar, after Activities (and username, if present)
        Main.panel.addToStatusArea('quick-notes', this._button, 2, 'left');
    }

    disable() {
        this._clearFocusSource();
        this._button?.destroy();
        this._button = null;
        this._listBox = null;
        this._scroll = null;
        this._separator = null;
        this._entry = null;
        this._notes = null;
    }

    _clearFocusSource() {
        if (this._focusSource) {
            GLib.source_remove(this._focusSource);
            this._focusSource = 0;
        }
    }

    _addNote() {
        const text = this._entry.get_text().trim();
        if (!text)
            return;
        this._notes.push({text, created: Date.now()});
        this._save();
        this._entry.set_text('');
        this._rebuildList();
        global.stage.set_key_focus(this._entry);
    }

    _deleteNote(index) {
        this._notes.splice(index, 1);
        this._save();
        this._rebuildList();
    }

    _rebuildList() {
        this._listBox.destroy_all_children();

        this._notes.forEach((note, index) => {
            const row = new St.BoxLayout({style_class: 'quick-notes-row', x_expand: true});

            const label = new St.Label({
                text: note.text,
                style_class: 'quick-notes-text',
                x_expand: true,
                y_align: Clutter.ActorAlign.CENTER,
            });
            label.clutter_text.line_wrap = true;
            label.clutter_text.line_wrap_mode = Pango.WrapMode.WORD_CHAR;
            label.clutter_text.ellipsize = Pango.EllipsizeMode.NONE;

            const del = new St.Button({
                style_class: 'quick-notes-del',
                child: new St.Icon({icon_name: 'edit-delete-symbolic', icon_size: 14}),
                y_align: Clutter.ActorAlign.START,
            });
            del.connect('clicked', () => this._deleteNote(index));

            row.add_child(label);
            row.add_child(del);
            this._listBox.add_child(row);
        });

        const hasNotes = this._notes.length > 0;
        this._scroll.visible = hasNotes;
        this._separator.visible = hasNotes;
    }

    _load() {
        try {
            const [ok, bytes] = GLib.file_get_contents(NOTES_FILE);
            if (ok) {
                const data = JSON.parse(new TextDecoder().decode(bytes));
                if (Array.isArray(data))
                    return data;
            }
        } catch (_e) {
            // no notes file yet
        }
        return [];
    }

    _save() {
        try {
            GLib.mkdir_with_parents(NOTES_DIR, 0o755);
            GLib.file_set_contents(NOTES_FILE, JSON.stringify(this._notes, null, 2));
        } catch (e) {
            console.error(`Quick Notes: could not save notes: ${e}`);
        }
    }
}
EOF

# ---------- stylesheet.css ----------
cat > "$EXT_DIR/stylesheet.css" <<'EOF'
.quick-notes-scroll {
    max-height: 380px;
}

.quick-notes-list {
    spacing: 6px;
    padding: 6px 12px;
}

.quick-notes-row {
    spacing: 8px;
    padding: 8px 10px;
    border-radius: 10px;
    background-color: rgba(255, 255, 255, 0.07);
}

.quick-notes-text {
    width: 270px;
}

.quick-notes-del {
    padding: 4px;
    border-radius: 6px;
}

.quick-notes-del:hover {
    background-color: rgba(255, 80, 80, 0.35);
}

.quick-notes-add-row {
    spacing: 8px;
}

.quick-notes-entry {
    width: 210px;
}

.quick-notes-add {
    padding: 4px 12px;
}
EOF
echo "• Extension files written to $EXT_DIR"

# ---------- enable (takes effect at next login) ----------
gsettings set org.gnome.shell disable-user-extensions false

current=$(gsettings get org.gnome.shell enabled-extensions)
if [[ "$current" != *"'$UUID'"* ]]; then
    if [[ "$current" == "@as []" || "$current" == "[]" ]]; then
        new="['$UUID']"
    else
        new="${current%]}, '$UUID']"
    fi
    gsettings set org.gnome.shell enabled-extensions "$new"
fi
echo "• Extension enabled"

echo
echo "✔ Done! Now LOG OUT and LOG BACK IN — a note icon will appear top-left."
echo "  Notes are saved in ~/.local/share/quick-notes/notes.json"
echo "  (To undo later: bash notes.sh --remove)"
