#!/usr/bin/env bash
# whoami.sh - Show your username on the top-left of the GNOME top bar (Fedora / GNOME 45+)
# Usage:
#   bash whoami.sh            -> install & enable (shows login name, e.g. "john")
#   bash whoami.sh --fullname -> install & enable (shows full name, e.g. "John Doe")
#   bash whoami.sh --remove   -> disable & uninstall

set -euo pipefail

UUID="username@local"
EXT_DIR="$HOME/.local/share/gnome-shell/extensions/$UUID"

# ---------- uninstall ----------
if [[ "${1:-}" == "--remove" ]]; then
    gnome-extensions disable "$UUID" 2>/dev/null || true
    current=$(gsettings get org.gnome.shell enabled-extensions)
    new=$(echo "$current" | sed "s/, *'$UUID'//; s/'$UUID', *//; s/'$UUID'//")
    gsettings set org.gnome.shell enabled-extensions "$new"
    rm -rf "$EXT_DIR"
    echo "✔ Removed. Log out and back in to clear it from the top bar."
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

NAME_FUNC="get_user_name"
if [[ "${1:-}" == "--fullname" ]]; then
    NAME_FUNC="get_real_name"
fi

# ---------- create extension files ----------
mkdir -p "$EXT_DIR"

cat > "$EXT_DIR/metadata.json" <<EOF
{
  "uuid": "$UUID",
  "name": "Show Username",
  "description": "Shows the username on the left of the top bar",
  "shell-version": ["45", "46", "47", "48", "49", "50", "$SHELL_MAJOR"]
}
EOF

cat > "$EXT_DIR/extension.js" <<EOF
import St from 'gi://St';
import GLib from 'gi://GLib';
import Clutter from 'gi://Clutter';
import {Extension} from 'resource:///org/gnome/shell/extensions/extension.js';
import * as Main from 'resource:///org/gnome/shell/ui/main.js';
import * as PanelMenu from 'resource:///org/gnome/shell/ui/panelMenu.js';

export default class UsernameExtension extends Extension {
    enable() {
        this._button = new PanelMenu.Button(0.0, 'Username', true);
        const label = new St.Label({
            text: GLib.$NAME_FUNC(),
            y_align: Clutter.ActorAlign.CENTER,
        });
        this._button.add_child(label);
        Main.panel.addToStatusArea('username-indicator', this._button, 1, 'left');
    }

    disable() {
        this._button?.destroy();
        this._button = null;
    }
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
echo "Done! Now Log-Out and Log-Back IN — your username will appear top-left."
echo "  (To undo later: bash whoami.sh --remove)"
