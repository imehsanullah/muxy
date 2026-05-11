# File Tree

A side panel showing the active worktree's directory structure. Toggle with `⌘E`.

```mermaid
flowchart TB
  Tree[FileTreeView]
  Tree -->|"local filesystem or SSH"| Listing[Directory listing]
  Listing -->|"git check-ignore"| Filter[gitignore-aware listing]
  Tree -->|"local git or remote git over SSH"| Colors[Per-file status colors]
  FSEvents[FSEvents watcher<br/>local projects] --> Tree
```

Only one of the file tree or attached VCS panel is visible at a time — opening one closes the other.

## What it shows

- Lazy-loaded directories — children load when you expand a folder.
- `.gitignore` is respected via `git check-ignore`. Toggle ignored files in the panel header.
- **Show only changes** filters to files with git changes.
- The active editor file is highlighted; its parent folders auto-expand.

## Git status colors

Files are colored by git status: modified, added, untracked, deleted. Folders inherit a status hint from their descendants.

## File operations

| Action | How |
| --- | --- |
| New File / New Folder | Inline text field on the parent folder |
| Rename | Double-click, or right-click → Rename |
| Delete | Moves to Trash via `NSWorkspace.recycle` (so OS handles Undo) |
| Cut / Copy / Paste | System pasteboard with a Muxy cut marker |
| Reveal in Finder | Right-click |
| Open in Terminal | New terminal tab rooted at that directory |

Multi-select with `⌘`-click and `⇧`-click. Drag and drop moves; hold `⌥` while dragging to copy.

Remote projects support SSH-backed browsing, gitignore marking, git status colors, path copying, and opening a terminal in the selected remote directory. Local filesystem operations such as rename, delete, paste, drag/drop, and Reveal in Finder are only shown for local projects.

## External changes

A FSEvents watcher picks up local changes made outside Muxy — no manual refresh needed. Remote projects refresh from VCS notifications and the panel refresh button.

## Resizing

Panel width is draggable and persists in `UserDefaults` (`muxy.fileTreeWidth`).
