# TD#2 — Orphan `.tmp` Staging Policy (verdict: ACCEPTED-AS-DESIGN)

**Owner:** Engineering (程基岩) · **Status:** CLOSED — accepted as design, non-blocking
**Scope:** 46 orphaned `*.json.tmp` staging files reported as a tech debt.

## 1. Where the 46 orphans actually live
- **Not in version control.** Verified by 主理人: `git ls-files` shows zero `.tmp`
  (the only `.tmp_gut/` tree is the local GUT verification channel, protected by 铁律9, untouched).
- They reside in the **runtime `user://` saves directory** (per-player, per-machine),
  produced by `_write_atomic()`'s staging-then-rename pattern when a session is
  interrupted (power loss, SIGKILL, OOM, crash). They are therefore out of git's reach
  by design and cannot be "removed from the repo."

## 2. Recovery code — current state (verified)
File: `src/core/save_manager.gd`
- `recover_orphaned_staging()` — L548: scans every legal slot id, and for each
  `slot_N.json.tmp`:
  - if `slot_N.json` already exists → slot is authoritative, **not** promoted (L559–563);
  - else if `_is_promotable_staging()` fails the gate → kept for diagnosis, **not** promoted (L566–569);
  - else rename tmp → final slot, appended to `recovered` (L571–580).
- `_is_promotable_staging()` — L599: same bar as `read_slot()` (parseable JSON →
  Dictionary → `version == SAVE_VERSION` → `slot_id` agrees with filename). Guarantees
  recovery can never admit a document a normal load would reject.
- `ensure_staging_recovered()` — L587: idempotent, lazy trigger (`_staging_recovery_done`
  guard) so the scan runs at most once per configured path set.

**Wired to all 4 read paths (verified):**
- `save_manager.gd:281`, `:343`, `:375`
- `save_slots_screen.gd:302` (so a recoverable slot is never shown as free space)

## 3. Why the scan never deletes (L531–538, verbatim intent)
> Promote, or report and leave. Nothing else. Boot is the worst possible moment to
> destroy data: it happens before the player can intervene, and every `.tmp` that
> survives to boot is by definition the best evidence available about an abnormal
> shutdown. … If a cleanup ever becomes genuinely necessary it belongs behind an
> explicit "repair saves" action, not in a silent boot path.

Orphans are also self-limiting: the next write to that slot reopens the staging path
with `WRITE` and truncates the file.

## 4. Trade-off: retain vs. autofree
| Option | Pro | Con |
|---|---|---|
| **Retain + diagnose (current)** | Zero risk of destroying player evidence; POSIX/Windows semantics already fall back safely; self-limiting | Litter accumulates until next save to that slot |
| **Auto-delete invalid orphans at boot** | Cleaner dir | Destroys the only evidence of an abnormal shutdown at the worst possible moment; irrecoverable data loss risk |
| **Dev/build-only autofree (`--repair-saves` / debug cmd)** | Lets developers clean scratch in dev builds | Not needed for shipped safety; adds a surface to maintain |

## 5. Verdict
**ACCEPTED-AS-DESIGN — runtime safety retention, non-blocking.**

No unhandled bug or leak path was found: valid orphans are promoted on the first
read; invalid orphans are intentionally preserved for diagnosis; the next save
self-cleans the slot's staging path. The item moves from "待办" to
"ACCEPTED-AS-DESIGN."

### Follow-up (OPTIONAL, not required)
A dev/build-only autofree entry point remains a reasonable *future* enhancement for
developer hygiene (e.g. a `--repair-saves` CLI flag or a debug console command that
calls a new `purge_unpromotable_staging()` behind `OS.is_debug_build()`). It is **not**
required to close this debt and was **not** implemented. If 主理人 wants it, propose
the concrete change for separate review — it must stay out of the silent boot path.

## 6. Verification evidence
- Recovery call sites confirmed via grep: `save_manager.gd:281/343/375`, `save_slots_screen.gd:302`.
- "Never delete" rationale confirmed at `save_manager.gd:531–538`.
- `git ls-files` (version control): zero `.tmp` tracked — consistent with runtime-only location.
