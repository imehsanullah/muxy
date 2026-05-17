# Agent Vault

Agent Vault is a local index over coding-agent session stores. `AgentVaultStore` is the main-actor observable singleton used by the toolbar button and right sidebar UI. It coalesces refresh state and delegates filesystem scanning to `AgentVaultScanner` on a utility task.

`AgentVaultScanner` currently reads:

- Claude Code transcripts from Claude config `projects` directories, including `CLAUDE_CONFIG_DIR`, `~/.codex-accounts/claude/*`, and `~/.claude`
- Codex rollouts from `~/.codex/sessions`

Each scan returns `AgentVaultSession` values with provider, title, cwd, branch, model, modified date, transcript path, and a full shell resume command. Resume commands preserve the session working directory with `cd -- <cwd> && ...`.

`AgentVaultToolbarItem` posts the right-sidebar toggle notification, and `MainWindow` hosts `AgentVaultSidePanel` in the shared right-side panel slot. `AgentVaultResumeCoordinator` resolves the best Muxy project/worktree target and creates the command tab. When a session cwd matches a known local Muxy project or worktree, it switches to that project/worktree before creating a command tab. If no cwd match exists, it falls back to the active project. Drag resumes can target an existing area or request a split through `createCommandTabSplit`.

`AgentVaultDragPayload` encodes sessions for same-process drag and drop and mirrors the active drag onto `NSPasteboard(name: .drag)` for AppKit routing. `AgentVaultDropTargetOverlay` provides a pane-level drop target that reports edge hover zones and resumes sessions in the target terminal area. `GhosttyTerminalNSView` also recognizes the Vault payload so terminal-hosted drops continue to work if they route directly to the embedded terminal.

`AgentVaultDeletionService` removes transcript files for session and folder context-menu deletes. `AgentVaultStore` updates the in-memory list from the deletion result so stale sessions disappear without waiting for another scan.
