# Terminal

Muxy's terminals are powered by [libghostty](https://github.com/ghostty-org/ghostty), running on a Metal layer for fast, GPU-accelerated rendering.

## Configuration

Muxy's active Ghostty config is `~/Library/Application Support/Muxy/ghostty.conf`. On first launch Muxy seeds it from `~/.config/ghostty/config` when that file exists; after that, Muxy reads and writes its own copy. Open it with **Muxy -> Open Configuration...**, reload after editing with `⌘⇧R`.

Most Ghostty options work — fonts, colors, padding, keybinds, shell integration. Muxy applies the active light/dark variant automatically when the system appearance changes.

## Find in terminal

`⌘F` opens an inline search overlay scoped to the focused pane. Enter / Shift-Enter cycle through matches; Escape dismisses.

## Copy and paste

| Action | Shortcut |
| --- | --- |
| Copy (with selection) | `⌘C` |
| Send `^C` to program | `⌘C` with no selection |
| Paste | `⌘V` or right-click → Paste |
| X11 selection paste | Middle-click |

Enable **Settings -> Terminal -> Auto-copy terminal selection** to copy selected terminal text on mouse release.

## Working directory

Muxy tracks the cwd via Ghostty's shell integration (OSC 7). The directory is persisted in workspace snapshots so newly recreated tabs land in the same folder when applicable.

Remote terminals use the selected SSH device's environment before starting the remote login shell. New SSH devices default to `TERM=xterm-256color`; edit the device in Settings -> Remote Devices to change or remove it.

## Persistent remote terminals

Remote terminal tabs use a named `tmux` session on the SSH host. Install `tmux` on the remote host to keep running processes and scrollback alive when the network drops, the Mac sleeps, the tab is put to sleep, or Muxy quits. Muxy saves a stable session identity with the workspace and reattaches to the same session after restoration. The tmux client uses `TERM=xterm-256color`; the other environment values configured for the SSH device are preserved.

Saving an SSH device and workspace is separate from preserving a live shell: device settings are stored in `remote-devices.json`, layout metadata is stored in `workspaces.json`, and the running shell remains on the remote host inside tmux. If tmux is unavailable, Muxy falls back to a direct SSH login shell; tabs and layout still restore, but remote processes cannot survive a disconnected SSH client.

Transport failures are retried with increasing delays of approximately 5, 15, 30, 60, 120, and 300 seconds, including jitter and per-host staggering so many panes do not reconnect at once. Muxy stops after six retries, and stops earlier after two immediate failures that usually indicate an authentication, host-key, or configuration problem. The disconnected pane remains open and offers **Reconnect**. Network recovery and macOS wake retry only panes already marked disconnected.

Closing a remote tab or pane, replacing its layout, or removing its worktree/project also deletes the corresponding tmux session. Quitting Muxy, switching workspaces, hiding a tab, sleeping, and losing the network do not delete it.

## Muxy CLI

Use the `muxy` command to open projects and control panes from a shell or automation script. See [Muxy CLI](muxy-cli.md).

## Custom command shortcuts

Define reusable shell command shortcuts in **Settings → Commands**:

- Display name, command, optional icon, optional keybinding.
- Triggering one creates a new tab and runs the command.
- Useful for `npm run dev`, `make watch`, `just test`, …

## Rich Input

`Cmd+I` opens a multiline composer for prompts, files, images, and broadcast sends. See [Rich Input](rich-input.md).

## Right-click menu

Inside a terminal pane: **Paste**, **Split Right**, **Split Down**, **Close Pane**.

## Notifications from the terminal

OSC 9 and OSC 777 notification escape sequences are routed into Muxy's notification panel and (optionally) macOS notifications. See [Notifications](notifications.md).

## Quick-select labels

Ghostty's quick-select feature lets you focus a pane or surface by typing a label key. Labels and bindings are configured in the Ghostty config.
