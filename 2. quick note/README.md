### Quick Notes (`notes.sh`)

Adds a note icon to the top-left of the top bar. 
Click it to open a floating box where you can add, view and delete notes.

Run these from inside the repo folder (or use the full path to the script):

```bash
bash notes.sh           # install
bash notes.sh --remove  # uninstall (your notes are kept)
```

Or uninstall from anywhere, without the script:

```bash
gnome-extensions uninstall quick-notes@local
```

After installing or uninstalling, **log out and log back in**.

**How to use**

- Click the note icon, type a note and press **Enter** or click **Add note**
- Click to delete a note

**Where notes are saved**

```
~/.local/share/quick-notes/notes.json
```

- Notes stay after a restart and after uninstalling, so reinstalling brings them back
- The `.local` folder is hidden. Press **Ctrl + H** in the Files app to see it
- To move your notes to another machine, copy this file over
