# Agent git workflow (read before ANY git command)

Several agents work on Bunker Game at once: local Claude sessions, cloud
Claude sessions and Codex. On 2026-09-27 an agent stashed another agent's
work, switched the shared folder to a different branch, and a second worktree
was checked out on the same branch. Nothing was lost, but only because of
manual recovery. These rules exist so that never happens again.

## The one branch

- **`testing` is the single integration branch.** Every piece of finished
  work lands on `origin/testing`, and nothing is "done" until it's there.
- `main` is Brannon's release branch. Never commit or push to it unless
  Brannon asks.
- Never force-push, never delete a branch, and never rewrite pushed history.

## Local agents (shared folder `/mnt/storage/Default Project/bunker-game`)

This folder is **shared**. Other agents and Brannon's open Godot editor have
uncommitted work in it right now.

**Never** run, in the shared folder:
- `git checkout <branch>` / `git switch` / `git checkout -- <path>` / `git restore`
- `git stash` (in any form), `git reset`, `git clean`, `git rebase`, `git pull --rebase`
- `git add -A`, `git add .`, `git commit -a`
- `git worktree add` (a second checkout of `testing` breaks both)

**Always:**
1. **Stage your own files by explicit path only.**
   `git add -- path/one.gd path/two.tscn`, then `git diff --cached --name-only`
   to confirm nothing else is staged, then `git commit -- <same paths>`.
2. **Before editing a file, check for someone else's uncommitted work in it:**
   `git diff --stat -- <file>`. If it shows changes that aren't yours,
   coordinate first (see "Talking to each other").
3. **Commit and push at every stopping point**, and at least every hour
   while working. Small commits are fine. Uncommitted work in a shared
   folder is at risk.
4. **Syncing:**
   ```bash
   git fetch origin
   git merge --ff-only origin/testing    # fails safely if it can't fast-forward
   git push origin testing
   ```
   If the push is rejected because `origin/testing` moved, run
   `git fetch origin && git merge origin/testing` (a normal merge commit),
   re-run your checks, then push. A merge that would touch a file with
   someone's uncommitted changes aborts on its own. In that case stop and
   coordinate; never stash to force it through.
5. **In a merge conflict,** keep both sides' intent. If one area has an
   owner (below), their version is canonical. Re-apply your change on top
   of theirs; don't overwrite it.

## Cloud agents (claude.ai/code, Codex cloud)

You work in your own clone on a `claude/*` (or `codex/*`) branch. That's
fine, but it must not drift:

1. **Start** by merging the latest `origin/testing` into your branch.
2. **At every stopping point** (and at least every few hours):
   `git fetch origin`, `git merge origin/testing` into your branch, run the
   checks, then **push your branch AND fast-forward `testing` to it**:
   `git push origin HEAD:testing`. If the push is rejected, merge
   `origin/testing` again and retry. Never force.
3. Never leave finished work only on your own branch. Brannon's machine
   pulls `testing`.

## Areas and owners (update when ownership changes)

| Area | Owner / canonical source |
|---|---|
| `scripts/npc/**`, `scenes/npc/**`, `docs/systems/npc/**` | NPC system polish review session (local since 2026-09-28; took over from the cloud `claude/gifted-planck-32j7ii` session, which is retired) |
| `scripts/player/Adventurer*`, `scenes/player/AdventurerModel.tscn`, `assets/models/player/anims/**`, `tools/anim_pipeline/**`, player/NPC sit/lie entry points | Animation polish session (local) |
| `scripts/ui/**`, `scenes/ui/**`, `docs/ui/**`, `PreviewStudio`, `SharedUI` | UI session (local) |
| `scripts/weapons/**` (except `PistolAnimationLayer.gd`), `scenes/weapons/**`, `assets/models/weapons/**`, `docs/systems/weapons/**` | Weapons session (local); contract in `docs/systems/weapons/HANDOFF.md` |
| `scripts/weapons/PistolAnimationLayer.gd`, weapon animation clips | Animation polish session (local) |
| Performance passes (water, power, build, shelving) | Codex FPS work; parked NPC items in `plans/codex-fps-npc-dropped/` |

Shared hot files such as `scripts/world/core/MainWorld.gd`, `project.godot`
and `scripts/npc/NPC.gd`: edit only the functions you need, commit them
promptly, and mention it to the other sessions.

## Talking to each other

- **Local Claude sessions:** use `ListAgents` / `SendMessage`. Tell the
  others before you touch a shared hot file or another owner's area, and
  when you've pushed.
- **Cloud sessions can't be messaged directly.** Leave a short note in your
  commit message (what changed, what others should know), and ask Brannon
  to relay anything urgent.

## Other rules

- Headless or live Godot runs must isolate user data:
  `export XDG_DATA_HOME=$(mktemp -d) XDG_CONFIG_HOME=$(mktemp -d)`.
  Never touch `~/.local/share/godot/app_userdata/BunkerGame` (real saves).
- Don't kill Brannon's Godot editor or a game he's running.
- `.godot/` is local cache. If headless runs report "Identifier X not
  declared" right after a branch change or a new `class_name`, the class
  index is stale. The editor rebuilds it on rescan; it isn't a code bug.
- Before anything destructive you've been explicitly asked to do, make a
  backup ref first, e.g. `git update-ref refs/backups/<name>-<date> <commit>`.
  Backup refs from 2026-09-27 live under `refs/backups/`.
