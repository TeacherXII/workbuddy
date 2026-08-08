# Phase 6 Playtest Report · ASHEN STEP《灰烬之步》

**Author:** 严守真 (Yan Soujin) — Quality-Lead / QA
**Build under test:** `main` @ `24fc2ef` (clean working tree)
**Engine:** Godot 4.4.1-stable (win64 console, headless)
**Test runner:** GUT v9.3.0
**Verification authority:** Local Godot is authoritative (CI runner down). All numbers below are **real** output from a local headless GUT run, not estimated. No `.gd` source was modified; no commit made.

---

## 1. Playtest Charter

**Scope.** Three focused evaluation passes over the RTwP stealth vertical slice. This is a **structured walkthrough + real headless GUT** playtest — the environment is headless (no display), so visual/audio/"feel" dimensions are validated by assertions and static trace, **not** by human perception. Limitation stated up front: frame-time, rendered look, and audio were not perceptually playtested.

**Round 1 — Core-loop stability.** Walk the RTwP stealth loop closure (infiltrate → trigger → sound/light exposure → respond → save/restore); cross-check GUT coverage of `test_patrol_ai` / `test_sound_propagation` / `test_interactables` / `test_save`; judge whether tests prove "fun/stable", not just "no crash"; run full local GUT to get authoritative numbers; confirm parse-error gate = 0.

**Round 2 — Boundary & resilience.** Stress save/restore (orphan staging, corrupt slot → silent data loss?); a11y (C-06 color/contrast, A-0N reachability); `EventBus` arbitrary-order wiring (TD#3-② fix).

**Round 3 — Experience polish & regression.** Regression read of prior blocker/major items; overall release-readiness reading + priority suggestions for perf / art / audio teams.

**Authoritative GUT result (real).**

```
Scripts 18 | Tests 227 | Passing 227 | Asserts 1515 | Time 7.984s
Failed 0 | Risky 0 | Parse-error gate 0 | Exit code 0 | "All tests passed!"
Orphans: 32.0 total (GUT note: excludes GUT-freed & pre-run orphans)
```

---

## 2. Round 1 — Core-loop stability

**Method.** Static walkthrough of the loop chain `StepCommit → EventBus → VisionCone → SoundPropagator (E06) → GuardBrain FSM (E08) → soft-fail (D9 seam) → restore_checkpoint`, cross-read against the four named test files; then a full local GUT run for real numbers.

**Findings.**
- **Patrol FSM is stable and well-covered.** `GuardBrain` (`patrol_ai.gd`) is a 5-state machine (CALM/SUSPICIOUS/ALERT/SEARCH/RETURN) with thresholds `THR_SUSP=25 / THR_ALERT=60 / THR_RETURN=10`, decay `8/s`, and `DECOY_REDIRECT_COOLDOWN_RT=3.0` (N-9 floor so a single decoy reaches `THR_SUSP`). `test_patrol_ai.gd` (H1–H11, H18, H26/H24/H25 decoy, H27 10 Hz decoy path) exercises tick boundaries and decoy redirection. No over-trigger or stuck-state observed in assertions.
- **Sound / decoy propagation green.** `SoundPropagator.emit()` (`sound_propagation.gd:157`) does grid query + distance filter + ring-VFX FIFO cap (`RING_CAP=8`) + bus broadcast; `suspicion_from_distance()` (`sound_propagation.gd:260`) uses `intensity*(1-dist/radius)`. `test_sound_propagation.gd` covers emit/radius/footfall/decoy/ring-cap. No runaway suspicion.
- **Interactables leak-free.** `InteractableRegistry` (`interactable_registry.gd`, `INSTANCE_CAP=16`, RefCounted) — `test_interactables.gd` asserts `leaked_count()==0` + weakref-null, proving no production orphans.
- **⚠ MAJOR GAP — the "save/restore" half of the loop is open in live play.** The D9 soft-fail seam is *wired*: `patrol_ai.gd:149` calls `set_checkpoint_sink(SaveManager.restore_checkpoint)` and `_on_soft_fail()` (`patrol_ai.gd:430-442`) invokes `_checkpoint_sink.call()`. But `restore_checkpoint()` is a **safe no-op when no checkpoint slot exists** (`save_manager.gd:650-654`, `push_warning("no checkpoint available — no-op")`). A grep across all of `src/` finds **no gameplay caller of `write_slot(CHECKPOINT_SLOT_ID, …)`** — the only references are in `save_ui_model.gd` (the SaveSlots UI, which *explicitly skips* the rolling-checkpoint row: `_apply_write` comment L704 "the rolling checkpoint slot writes on its own schedule"), and that screen is **not mounted in the vertical slice** (`sprint0_bootstrap.gd:102-118`). The writer scaffolding already exists (`_checkpoint_write_throttled()` at `save_manager.gd:251`, `make_slot(CHECKPOINT_SLOT_ID, …)` at `save_manager.gd:258`), but nothing calls it during play.
  - **Effect:** on the first soft-fail the player expects a rollback and gets a silent no-op. The loop is one-sided; the closure is unverified in live play.
  - **Test-design note:** `test_soft_fail_invokes_checkpoint_sink_once` (`test_patrol_ai.gd:449`) verifies the *seam fires* (reverse-arity paired with `test_save_manager.gd`), **not** that a real checkpoint slot is produced. Tests prove wiring + no-crash, not player-perceived loop closure.
- **GUT real numbers:** 18/227/227/1515, 0 failed, 0 risky, parse-gate 0, exit 0. Loop logic is regression-green.

---

## 3. Round 2 — Boundary & resilience

**Method.** Read save atomicity + orphan-recovery paths; read a11y settings/colors and their live consumers; confirm TD#3-② by source + `git show 24fc2ef`.

**Findings.**
- **Save atomicity & orphan recovery — strong, no silent data loss.**
  - Atomic staging write: `_write_atomic()` (`save_manager.gd:424`) writes `slot.json.tmp` then `DirAccess.rename_absolute`.
  - Orphaned-staging recovery: `recover_orphaned_staging()` (`save_manager.gd:548`), lazy `ensure_staging_recovered()` (`save_manager.gd:587`), `_is_promotable_staging()` (`save_manager.gd:599`).
  - `test_save_ui.gd` proves the contract: orphan promoted on next session (`L325`); orphan **never overwrites** an existing slot (`L359`); **truncated orphan not promoted** into a corrupt slot (`L388`); destination never opened for truncating write (`L305`).
  - Corruption rejection SAV-S6 (`test_save_manager.gd`): a corrupt slot is rejected, never swallowed. **Verdict: deliberately corrupting a slot does NOT silently drop data** — recovery is explicit and tested.
- **a11y C-06 — fully covered.** `HUD_COLOR_DANGER_CB := Color("#F0C070")` (`hud_colors.gd`) replaces the retired `#C8862F` collapse; `danger_color()` applies per colorblind mode; WCAG contrast helpers gate C-02 (7:1) / C-03 (3:1). `test_a11y_settings.gd` asserts the substitute value + contrast + 4-state colorblind enum (OFF/PROTAN/DEUTAN/TRITAN) + fog (V-04) / text-scale (X-01) / subtitles. Live **PULL** consumption confirmed: `hud_slice.gd apply_a11y() → HudColors.danger_color(colorblind_mode())`; `time_controller.gd:173 apply_a11y() → set_user_scale(time_scale_user)`.
- **a11y A-0N — defined, live consumption NOT observed (see defect D2).** Audio-a11y tiering (Basic/Standard/Comprehensive) is modeled in `a11y_settings.gd` and `AudioDirector` is an autoload (`project.godot:40`), but the slice (`sprint0_bootstrap.gd`) shows no runtime application of the A-0N tier to audio; no test asserts live audio-tier reachability.
- **TD#3-② — CLOSED.** `SoundPropagator.set_event_bus` (`sound_propagation.gd:74-76`) now calls `_bind_bus()` (added at `:76`), so late/arbitrary-order bus wiring can't leave the propagator unwired. Confirmed in `git show 24fc2ef`. `test_event_bus.gd` covers vocabulary completeness + `decoy_landed` arity-3 contract (N-8).

---

## 4. Round 3 — Experience polish & regression

**Method.** Regression read against prior blocker/major items via the real GUT run + static re-trace of previously-fixed seams.

**Findings.**
- **All prior blocker/major items are green** in the real run: SAV-S1/S2/S3/S4/S6, E07-S1..S8, C-06, FLAG-A (zero-arg `restore_checkpoint` arity), FLAG-J (field-agnostic prefs), TD#3-②, N-8/N-9 floors — all asserted and passing.
- **Polish observations (non-blocking):**
  - Headless cannot validate rendered look/feel or audio; cone-VFX gating off headless (`test_cone_vfx_not_built_headless`) means no render artifacts in CI, but a real-render visual pass is still required (see art priority).
  - A-0N audio-tier reachability is the one open polish item (D2).
  - Leak-at-exit artifacts to verify (D3).

---

## 5. Prioritised Defect Table

| Sev | Defect | Affected system | Evidence | Suggested handling | Needs code change? |
|---|---|---|---|---|---|
| **Major** | Rolling checkpoint never written during gameplay → `restore_checkpoint()` is a no-op on first soft-fail; core-loop "save/restore" half not closed in live play (escalates to **Blocker** for the full game) | SaveManager + PatrolAI (D9 seam) | No `write_slot(CHECKPOINT_SLOT_ID, …)` gameplay caller in `src/`; `save_ui_model.gd` skips checkpoint row (L704) and SaveSlotsScreen not mounted (`sprint0_bootstrap.gd:102-118`); safe no-op at `save_manager.gd:650-654`; writer scaffolding exists (`save_manager.gd:251,258`) | Add a gameplay-side checkpoint producer (checkpoint volume/trigger or throttled autosave) invoking `write_slot(CHECKPOINT_SLOT_ID, …)`. Until then treat soft-fail rollback as **unverified-in-live-play** | **YES** (gameplay writer) |
| **Minor** | A-0N audio-a11y tiering (Basic/Standard/Comprehensive) modeled but no live gameplay consumption observed in the slice | A11ySettings + AudioDirector | `a11y_settings.gd` carries tiers; `AudioDirector` autoload (`project.godot:40`); `sprint0_bootstrap.gd` shows no A-0N tier applied to runtime audio; no test asserts live audio-tier reachability | Audio team: confirm `AudioDirector` applies the A-0N tier at runtime; add a GUT assertion for audio-tier wiring | Likely (audio consumption) |
| **Minor** | 32 GUT orphans + "ObjectDB instances leaked at exit" + "4 resources still in use at exit" | Test harness / teardown | `local_gut.txt:5557-5569`; GUT note excludes pre-run/GUT-freed orphans; `test_interactables.gd` proves production RefCounted leak-free (`leaked_count()==0`) | **VERIFIED-CLOSED (Phase 6 R-02/D3/F-3 follow-up):** harness-only 已通过 `Godot --headless … -gexit --verbose` 确认（见 §7）；无需生产修复，不新增断言（lean） | **VERIFIED-CLOSED** (harness-only) |
| **Minor** | Test-design: soft-fail test verifies the seam fires (spy sink), not that a real checkpoint slot is produced | Test coverage | `tests/unit/test_patrol_ai.gd:449` (reverse-arity paired w/ `test_save_manager.gd`) | Add integration test: real soft-fail → assert checkpoint slot file produced → assert restore restores state | YES (test only) |

**Counts:** Blocker 0 · Major 1 · Minor 3.

---

## 6. Release Readiness + Priority Suggestions

**Readiness reading.** The codebase is in **strong, regression-green, stable** shape: 227/227 GUT pass, 0 parse errors, 0 failed/risky. System-level stability (patrol FSM, sound/decoy, save atomicity & orphan recovery, a11y color/contrast) is well-covered and green. **One Major functional gap** (live checkpoint writer) keeps the core loop's save/restore half open in live play — safe (no crash/corruption) but unverified for the player. **Safe to proceed** to content/integration work; the checkpoint producer is the single must-fix before the loop can be called "closed".

**Performance team.** Headless GUT does **not** measure frame-time/CPU/GPU. No logic perf regression found, but real render-thread cost (cone VFX, light model, ghost-trail cap 6) was never exercised with frames. → Establish a perf baseline + gate; run a headless `--verbose`/render-trace or minimal windowed smoke to capture FPS before perf sign-off. **Priority: medium (unmeasured, not broken).**

**Art team.** Cone-VFX color/contrast gates are asserted green (C-03 5.00:1, C-04/C-05 cool-tone, ground spot `#9FB8C9`); headless VFX mesh is gated off so no render artifacts in CI. But look/feel of VFX, the `#F0C070` danger substitution, fog/text-scale were validated by assertion, not by eye. → Real-render visual pass: confirm C-06 `#F0C070` reads as danger in-context and cone VFX is legible. **Priority: medium (verify look).**

**Audio team.** A-0N audio-a11y tiering consumption not observed in the slice (defect D2); `AudioDirector` is autoloaded. → Confirm at runtime the audio tier actually changes output and that `sound_emitted`/decoy paths respect it; add a wiring assertion. **Priority: medium (close A-0N reachability).**

**Top routing item:** D1 (checkpoint writer) → gameplay/engine team, **highest priority** — it is the only item that blocks the core-loop closure.

---

## 7. D3 — 退出泄漏验证关闭（Phase 6 R-02/D3/F-3 follow-up）

**Verdict: VERIFIED-CLOSED（harness-only，无生产泄漏）。不新增断言（lean）。**

**Author:** 程基岩（engineering-lead）· **Date:** Phase 6 follow-up · **Engine:** Godot 4.4.1-stable (win64 console, headless)

### 7.1 验证方法
按 `engineering-followups-spec.md` D3 口径，用真实 console 跑（**只看实时控制台真数，不看 `gut_output.txt`**）：

```
Godot_v4.4.1-stable_win64_console.exe --headless \
  -s addons/gut/gut_cmdln.gd -gdir=res://tests/unit -gexit --verbose
→ exit code 0；GUT 全绿（22/241/241/1588，Failing 0）
→ "WARNING: ObjectDB instances leaked at exit" + "ERROR: 4 resources still in use at exit"
```

### 7.2 `--verbose` 追踪分类（关键行）

| 退出泄漏条目 | 分类 | 判定 |
|---|---|---|
| `Node`（多条 `Cannot get path … not in a scene tree`） | 测试内创建的节点（GuardBrain / VisionCone / Marker3D / SoundPropagator 等），headless 下游离、随退出惰性释放 | **harness-only** |
| `RefCounted`（无脚本路径，多条） | 测试内创建的 RefCounted（registry / ledger 等），GUT teardown 未 free | **harness-only**（生产 `leaked_count()==0` 由 `test_interactables.gd` 证明） |
| `GDScriptNativeClass` ×2 | 引擎内部原生类引用 | **engine/harness** |
| `Resource still in use`：4 个 `.gd`（`light_model.gd` / `patrol_ai.gd` / `vision_cone.gd` / `guard_variant_params.gd`） | 静态 `preload` 引用（被 `budget_checks.gd` / `guard_spawner.gd` 等持有），进程退出前持久 | **harness/autoload 级**，非玩法对象 |
| `Orphan StringName`（LightModel / _enter_tree / _lost_timer …） | Godot 退出时 StringName 缓存清理 | **engine 标准行为** |

**关键反证（已有，未重测即成立）：** `test_interactables.gd` 断言生产 `RefCounted` 的 `leaked_count()==0` 且 weakref 为 null → **零生产泄漏**。本次 `--verbose` 未出现任何属于 `src/` 玩法对象且脱离测试生命周期的泄漏。

### 7.3 结论
- 32 GUT orphans + 退出 "ObjectDB leaked" + "4 resources still in use" **全部源于测试 harness / 引擎退出清理**，非生产代码真实泄漏。
- 与 `playtest-report.md:81` 原 "NO (verify)" 判定一致，现升级为 **VERIFIED-CLOSED**。
- 按 spec「不强制加断言」：**仅登记，不改 `tests/` 断言、不碰 `src/`**。若未来 test-teardown 真实性受损（出现非 harness 节点泄漏），再回过头补 `queue_free`/生命周期修复。
