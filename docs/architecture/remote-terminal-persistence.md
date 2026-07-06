# Remote Terminal Persistence Implementation

This branch adds persistent remote terminal sessions on top of Muxy's official remote workspace architecture.

## Branch Context

- Worktree: `/Users/ehsanullah/codebase/bullshit/terminals/muxy-dev-2026-07-06`
- Branch: `dev_2026-07-06`
- Base commit: `14faa4c` (`Add webview modals for extensions (#866)`)
- Remote: `origin` points to `git@github.com:imehsanullah/muxy.git`

## Purpose

Remote workspaces already route terminals, git, files, worktrees, and extension commands through reusable SSH devices. Before this branch, a remote terminal process still depended on the live SSH client connection. If the Mac slept, the network dropped, Muxy restarted, or a terminal surface was recreated, the remote shell process could be lost.

The goal of this branch is to keep remote terminal processes and scrollback alive by placing each remote terminal inside a stable `tmux` session on the SSH host, while still using the official `RemoteDevice`, `ProjectGroup`, and `WorkspaceContext` model instead of storing raw host strings on terminal panes.

## What Changed

### Stable Remote Session Identity

- `TerminalPaneState` now owns a stable `remoteSessionID`.
- `TerminalTabSnapshot` persists that ID so restored layouts reattach to the same remote session.
- `RemoteTerminalSessionName` builds sanitized tmux names from project ID, worktree ID, and terminal session ID.
- Session identity intentionally excludes mutable host display names and SSH credentials.

### Persistent Remote Launch

- `TerminalLaunchCommand.remoteShellCommand` now delegates persistent remote terminals to `RemoteTerminalSessionCommand`.
- The local launch command runs a `/bin/sh -c` reconnect wrapper.
- The wrapper starts OpenSSH with interactive-terminal options, keepalives, and `ControlMaster=no`.
- On the SSH host, Muxy checks for `tmux`.
- If `tmux` exists, Muxy creates the named session only when it is absent, applies terminal options, and attaches to it.
- If `tmux` is missing, Muxy falls back to a direct SSH login shell. In that fallback mode, layout restoration still works, but the remote process cannot survive a broken SSH connection.

### Shell Command Fix

During testing, remote project terminals showed:

```text
bash: line 0: exec: exec: not found
```

The cause was the persistent remote launch path handing a command that began with the shell builtin `exec` into a context where it could be treated as an executable name. The fix was:

- do not make the top-level Ghostty command start with `exec`;
- start it as `/bin/sh -c ...`;
- wrap the tmux session creation command as `/bin/sh -lc ...` so the remote shell builtin is interpreted by a real shell.

### Reconnect Behavior

- `RemoteTerminalReconnectPolicy` retries only OpenSSH transport failures (`255`).
- Retry delays are approximately `5`, `15`, `30`, `60`, `120`, and `300` seconds.
- Jitter and a per-destination lock/state file stagger reconnect attempts across multiple panes.
- Two immediate failures stop early because they usually mean authentication, host-key, access, or configuration problems.
- `RemoteSessionReconnectMonitor` listens for network recovery and macOS wake, then asks only disconnected remote panes to reconnect.
- `TerminalPane` shows a disconnected/reconnecting overlay and a manual **Reconnect** action.

### Cleanup Rules

Remote tmux sessions are killed only when the user takes a destructive action that removes the terminal from the workspace model:

- closing a remote tab;
- removing a split area containing remote panes;
- replacing a layout;
- removing a remote worktree;
- removing a remote project.

Remote tmux sessions are not killed when:

- Muxy quits;
- the Mac sleeps;
- the network drops;
- a terminal surface is temporarily destroyed or put offline;
- the user switches workspaces or projects.

Cleanup is emitted as reducer side effects through `RemoteTerminalSessionReference`, then executed by `RemoteTerminalSessionTerminator` with a tolerant `tmux kill-session` command.

### App Integration

- `GhosttyTerminalNSView` accepts the active `WorkspaceContext` and remote session name.
- `TerminalViewRegistry` can restart a remote session surface for reconnect.
- `TerminalSurfaceMaterializer` preserves remote session identity for visible and headless materialization.
- `MuxyApp` wires `AppState.workspaceContextProvider`, loads remote project worktrees before workspace restoration, and starts the reconnect monitor.
- `SSHDestination` now has persistent terminal SSH options separate from regular batch/terminal options.

### Documentation and Tests

Docs were updated in:

- `docs/features/terminal.md`
- `docs/features/project-workspaces.md`
- `docs/README.md`
- this architecture note

Focused tests were added or updated for:

- remote terminal session command generation;
- retry policy and reconnect staggering;
- terminal pane remote connection state;
- workspace snapshot persistence;
- remote session cleanup side effects;
- reconnect monitor trigger behavior;
- terminal launch command escaping, including the `exec exec` failure mode.

## Verification

The focused terminal tests passed with the Xcode toolchain:

```text
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter 'TerminalLaunchCommandTests|RemoteTerminalSessionCommandTests'
```

Result:

```text
17 tests passed
```

The dev app was rebuilt and launched from this worktree:

```text
/Applications/Muxy-Dev.app
```

Build metadata:

- Version: `1.3.0`
- Build: `814`
- Source commit: `14faa4c`

Code signature verification passed for the installed app bundle.

## Runtime Behavior

When a remote terminal uses tmux, the bottom tmux status line is configured with:

- `status-left`: `muxy-<last4>`
- `history-limit`: `1000000`
- `mouse`: `on`
- `allow-passthrough`: `on` when supported

`<last4>` is derived from the sanitized session name suffix. Other default tmux status content may still appear unless the user's tmux configuration changes it.
