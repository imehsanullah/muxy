# Agent Vault

Muxy indexes local coding-agent sessions and shows them in the right-side Vault panel beside the workspace. The top-right Vault button and `Cmd+Opt+B` toggle the panel. The first supported session sources are Claude Code JSONL transcripts under Claude config directories and Codex JSONL rollouts under `~/.codex/sessions`.

The Vault groups sessions by folder or agent and shows the agent, title, working directory, branch, model, and last modified time. Search filters across those fields. The refresh button rescans the local session stores.

Right-click a session to resume it, copy its resume command, reveal its transcript, open its working directory, or delete that session. In folder grouping, right-click a folder header to delete every Vault session for that working directory.

Selecting a session resumes it in a new Muxy terminal tab with the agent-native resume command:

- Claude Code: `claude --resume <session-id>`
- Codex: `codex resume <session-id>`

If the session working directory matches an added Muxy project or worktree, Muxy switches there before opening the resume tab. Otherwise it resumes in the active project. Sessions can also be dragged from the Vault onto a terminal area. Dropping in the center resumes in that pane; dropping on an edge creates a split with the resumed session.
