# Tak runtime flow

Tak keeps stable worktree facts separate from runtime status and operation outcomes.

```text
mix tak.create/list/remove
        |
        v
   Tak.Worktrees
        |
        +--> Tak.Worktree        (stable identity/config)
        +--> Tak.WorktreeStatus  (runtime status + PID)
        +--> Tak.RemoveResult    (remove outcome + DB cleanup)
        |
        +--> .tak metadata       (primary source of truth)
        +--> config/dev.local.exs (legacy fallback still supported)
        +--> git / mix / dropdb via Tak.System
```

Failure path for create:

```text
create worktree
  -> write local config
  -> run mix deps.get / mix ecto.setup
  -> write .tak only after bootstrap succeeds
  -> on bootstrap failure, best-effort cleanup of worktree + newly created branch
```
