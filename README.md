# Lightnav

Lightning-fast navigation between the apps you have running in [Omarchy](https://omarchy.org): every open window on any workspace and any monitor, plus apps in the system tray. Type a few letters, press Enter, and you are there.

![Lightnav](preview.png)

## What it shows

Every row is one open window:

- **App name** as the app calls itself (from its desktop entry), followed by the window title
- **Workspace number** in a small square, numbered the same way as the bar (each monitor has its own 1–0); `S` for the scratchpad and minimized windows
- **Laptop or monitor icon**: whether the window is on the built-in display or an external monitor
- **Layout miniature**: the windows of that workspace drawn to scale, with this one highlighted

Tray apps without an open window are listed too, with a tray badge. Apps that are not running are never shown.

The window you are in is dimmed. Without a search, apps are sorted alphabetically; windows of the same app go largest first, then in reading order (top to bottom, left to right). While you type, the list is filtered by app name and window title, ignoring case and diacritics, and ranked by how well it matches.

## Keys

| Key | Action |
|---|---|
| Type | Filter |
| Up / Down, PageUp / PageDown | Move the selection |
| Enter or click | Go to the window, or open the tray app |
| Delete | Close the selected window and stay in the list |
| Esc | Clear the filter, then close |

Enter on a window switches to its workspace and monitor and focuses it; a minimized window comes back to the workspace in front of you. A tray app is asked to open its window; if it doesn't respond, its tray menu is shown inside Lightnav.

## Install

```bash
omarchy plugin add https://github.com/smetak13/omarchy-lightnav.git --enable
```

Then add a shortcut to `~/.config/hypr/bindings.lua`:

```lua
o.bind("SUPER + N", "Lightnav", { panel = "smetak13.lightnav" })
```

`SUPER + N` is free in a default Omarchy setup. Lightnav stays loaded in the shell, so it opens instantly.

Remove it with `omarchy plugin remove smetak13.lightnav` and delete the binding.

## Development

The filtering, sorting, workspace numbering and layout miniature live in `Model.js`, tested with Node's built-in runner:

```bash
node --test tests/
```

After editing the QML, run `omarchy restart shell`: a plugin that stays loaded keeps its old code until the shell restarts.

## License

[MIT](LICENSE)
