# Sprint 1 · Batch A — QA 批间冒烟就绪评审

**评审人**：严守真（Yan Soujin / quality-lead）
**阶段**：Phase 5 · Sprint 1 · Batch A
**评审方式**：静态 Read 审查（沙箱不可运行 Godot，禁用 Bash；测试文件 + 实现对象 + CI 配置交叉比对，无 GUT 实际执行）
**评审范围**：7 Story（E01-S9 / E04-S3 / E04-S4 / E04-S7 / E03-S5 / E03-S6 / E03-S7）新增/扩展测试；不含 E10-S1 的 6 个失败集成测试（Batch D）。

---

## 0. 冒烟就绪判定：**CONCERNS**

**结论**：Batch A 自身三个测试文件（`test_event_bus` / `test_light_model` / `test_step_commit`）**断言对象 API 与实现完全一致，无阻断性不一致**；新增/扩展测试均为纯逻辑、`headless` 安全（不进场景树、VFX 路径被跳过）。故**非 FAIL**。

但存在 **1 项建议性修复（中风险，零代价）** 与 **1 项 CI 预期需纠偏**，故判 **CONCERNS** 而非纯 PASS：

1. **[中风险] `test_light_model.gd` 的 `test_light_state_changed_emitted_with_state` 未调用 `watch_signals(_lm)`**，与另两个 Batch A 文件（均在其 `before_each` 调 `watch_signals`）不一致。取决于 GUT 9.3.0 的 `assert_signal_emitted` 是否对"先 emit 后断言"做自动回看——若 GUT 要求事先 `watch_signals`，该单测会**虚假失败**（仅 1 条，不影响其余）。建议 push 前补一行。
2. **[CI 预期纠偏] 6 个已知失败集成测试 `test_integration_step_vision.gd` 与 Batch A 三文件同处 `tests/unit`**，CI 的 `-gdir=res://tests/unit` 会一并扫描执行。Batch A push 后整体退出码**不会是 0**（那 6 个仍红，属 E10-S1 / Batch D 继承状态）。`impl.md §7` 的"退出码 0"仅对"三文件各自全绿"成立，对整跑不成立。

> 无 API 不一致（即"测试断言对象 API ≠ 实现 = CI 必红"）条目。这是本评审最重要的正面结论。

---

## 1. 测试清单表（24 例，逐条评审）

### 1.1 `tests/unit/test_event_bus.gd`（E01-S9，新建，4 例）— headless-safe ✓

| # | 测试名 | 评审结论 | 风险 |
|---|--------|---------|------|
| 1 | `test_event_vocabulary_complete` | PASS — 13 个 §2 信号全部 `has_signal` 为真，`declared==13` | Low |
| 2 | `test_all_signals_can_connect_and_emit` | PASS — 13 信号签名/emit/断言与 `event_bus.gd:20-38` 逐一吻合 | Low |
| 3 | `test_suspicion_changed_carries_tier_parameter` | PASS — 3 参 `(3,70.0,SusTier.ALERT)` 与 signal `:33` 一致 | Low |
| 4 | `test_light_state_changed_uses_lightstate_enum` | PASS — `(5,LightState.LIT)` 与 signal `:22` 一致 | Low |

> 注：`vision_stimulus(guard_id,target:Node,visibility)` / `exposure_detected(guard_id,target:Node)` 以 `null` 作 `Node` 实参 emit，Godot 4 允许 null 对象引用，合法。`before_each` 已 `watch_signals(_bus)`。

### 1.2 `tests/unit/test_light_model.gd`（E04-S3/S4/S7 扩 +3，含 Sprint0 既有 6 例）— headless-safe ✓（1 例 CONCERN）

| # | 测试名 | 评审结论 | 风险 |
|---|--------|---------|------|
| 5 | `test_thresholds_exposed_as_constants` | PASS — `L_DARK=0.20`/`L_BRIGHT=0.60` 与 `:9-10` 一致 | Low |
| 6 | `test_light_level_in_shadow_box_is_dark` | PASS — 盒内 `get_light_level≈0.1`（`light_model.gd:49-55`） | Low |
| 7 | `test_light_level_outside_shadow_is_bright` | PASS — 盒外 `≈1.0` | Low |
| 8 | `test_sensitivity_below_dark_is_zero` | PASS — `<=L_DARK → 0.0` | Low |
| 9 | `test_sensitivity_above_bright_is_one` | PASS — `>=L_BRIGHT → 1.0` | Low |
| 10 | `test_sensitivity_linear_between_thresholds` | PASS — 线性 `(L-0.2)/0.4`，0.4→0.5、0.3→0.25 | Low |
| 11 | `test_get_cover_blocks_los` | PASS — 邻接点 `(3,0,1)` dist 2.0≤3.0→true；半影带 `(3,0,4.5)` dist 1.5≤3.0→true；空旷 `(0,0,0)` →false（`get_cover :74-88`） | Low |
| 12 | `test_light_state_changed_emitted_with_state` | **CONCERN** — 逻辑/API 全对（`get_light_state` 默认 `LIT`→`set_light_state`→emit→`toggle` 还原与 `:97-115` 一致），但 `before_each(:16-18)` **未 `watch_signals(_lm)`**，其余两文件均调。见 §2 条目 A。 | **Medium** |
| 13 | `test_light_change_recomputes_only_dirty_cell` | PASS — `SpatialHashGrid3D.CELL=14.0`，target1 `(0,0,0)→cell(0,0,0)`、target2 `(20,0,0)→cell(1,0,0)` 确属**不同 cell**，脏 cell 重算断言成立（`:152-162`） | Low |

### 1.3 `tests/unit/test_step_commit.gd`（E03-S5/S6/S7 扩 +3，含 Sprint0 既有 8 例）— headless-safe ✓

| # | 测试名 | 评审结论 | 风险 |
|---|--------|---------|------|
| 14 | `test_commit_moves_player_to_landing_point` | PASS — `to`/`from` payload + `player_step_committed` 信号（`step_commit.gd:59-78`） | Low |
| 15 | `test_commit_noise_radius_matches_budget` | PASS — `SNEAK+STONE=5*1*0.5=2.5` | Low |
| 16 | `test_focus_enters_slowmo_at_0_25` | PASS — `TimeController.FOCUS_SCALE=0.25`、`mode` 同步 emit（`time_controller.gd:15,27-34`） | Low |
| 17 | `test_focus_exit_restores_flowing` | PASS — `exit_focus` 还原 FLOWING | Low |
| 18 | `test_commit_cooldown_uses_real_time_not_scaled` | PASS — `tick_real(0.13)` 跨过 `COMMIT_COOLDOWN_RT=0.12`，`can_commit` 翻转（`:55,124-128`） | Low |
| 19 | `test_exposure_grace_1_2s_triggers_soft_fail` | PASS — 内部 `ExposureGuardStub` 自包含，`grace_rt=1.2`，1.0s 不触发、1.3s 触发 | Low |
| 20 | `test_non_idle_rejects_commit` | PASS — 首次 commit→RECOVERING，二次被拒（`can_commit` false 直接 return） | Low |
| 21 | `test_gait_switch_changes_noise_radius` | PASS — `SNEAK+STONE=2.5`、`WALK+STONE=5.0`，中间 `tick_real` 解冷却 | Low |
| 22 | `test_noise_radius_all_surfaces` | PASS — `SNEAK+MOSS=5*0.5*0.5=1.25`、`WALK+GRASS=5*0.7*1.0=3.5`、`RUN+METAL=5*1.2*2.0=12.0`（`SURFACE_FACTOR :19-24`/`GAIT_PARAMS :34-38`） | Low |
| 23 | `test_gait_run_noise_and_step` | PASS — `distance=4.0`、`step_duration=0.24`、`noise=10.0`、`effective_step_duration(0.25)=0.24/0.25=0.96`（`:87-94`） | Low |
| 24 | `test_footfall_vfx_present` | PASS — `surface=MOSS` 写入；10 次 commit 后 `ghost_trail` 封顶 `MAX_GHOST=6`；`_step` 未进树→`is_vfx_enabled()`=false（`:119-121`）→VFX 跳过，headless 不崩 | Low |

> `before_each(:47-55)` 调 `watch_signals(_step/_time/_exp)` 且 `add_child(_time)` 使 `TimeController` tween 合法；`after_each` 复位 `Engine.time_scale=1.0` 并 `remove_child+free(_time)`，清理防御到位。

---

## 2. API 不一致 / Headless 风险具体清单

> 格式：文件:行 — 期望 vs 实际 — 等级 — 处置

### A. [CONCERN · Medium] `test_light_model.gd:94-104` 缺 `watch_signals`
- **位置**：`test_light_state_changed_emitted_with_state` 使用 `assert_signal_emitted_with_parameters(_lm, "light_state_changed", [1, EventBus.LightState.EXTINGUISHED])`，但 `before_each`（`:16-18`）仅有 `_lm = LightModel.new()`，**未** `watch_signals(_lm)`。
- **期望**：与 `test_event_bus.gd:18-20`、`test_step_commit.gd:51` 一致，先在 `before_each` `watch_signals` 以确保信号在 emit 前被监听。
- **实际**：`LightModel` 是 `RefCounted`（`:2`），信号 emit 发生在断言之前；若 GUT 9.3.0 的 `assert_signal_emitted*` 不对"先 emit 后断言"做自动回看，则**该单测虚假失败**（仅 1 条，blast radius 小）。
- **处置（建议，零代价）**：在 `before_each` 末尾补 `watch_signals(_lm)`。即便 GUT 自动回看成立，此补强与另两文件一致、无副作用。

### B. [CI 预期纠偏 · 非阻断] 整体退出码不为 0
- **位置**：`.github/workflows/ci.yml:50-54` `-gdir=res://tests/unit`；`tests/unit/` 下含 `test_integration_step_vision.gd`（6 个已知失败，E10-S1 / Batch D，`before_each` 用 `add_child(_bus/_step/_vc)` — 属"headless 缺 SceneTree"失败模式）。
- **期望（impl §7）**："三文件全绿、退出码 0"。
- **实际**：GUT 扫描整目录会一并执行该集成文件 → 那 6 例仍红 → 整跑退出码非 0。故"退出码 0"**仅对三文件各自成立**，对 CI 整跑不成立。
- **处置**：用户请以**三文件各自结果**为 Batch A 放行依据；整跑红是继承状态，非 Batch A 引入。若要 Batch A 真正"退出码 0"，需把那 6 例移出 `tests/unit`（如 `tests/integration/`）或加 `-gignore`，属 Batch D 范畴（见 §4）。

### C. [GDD 缺口 · 非阻断] `MOSS=0.5` 与 `SusTier=CALM vs NONE`
- `test_step_commit.gd:175-177` 断言 `SNEAK+MOSS=1.25`（MOSS 系数 0.5）与 `step_commit.gd:23` 一致；`event_bus.gd:17` `SusTier{CALM,SUSPICIOUS,ALERT,SEARCH}` 与测试断言一致。
- 二者均为 `impl.md §5.1/§5.2` 已标注的 GDD 冲突（asset-manifest §3.1 写 MOSS 0.5、STONE 1.2 vs 其它源；system-breakdown §2.3 写 `NONE` vs `CALM`）。**测试与实现一致 ⇒ 不导致 CI 失败**，但属待 主理人/文策渊 裁决项，请勿静默合并。

### D. [前瞻 · 非阻断] `footfall_vfx.gd` 在集成测试（进树）路径的 headless 安全
- Batch A 三文件均**不**将 `StepCommit` 进树 → `is_vfx_enabled()=false` → VFX 跳过（`:119-121`），headless 不崩。
- 但 `test_integration_step_vision.gd:37` `add_child(_step)` 会把 `StepCommit` 进树，若 Batch D 修复该集成测试使其变绿，则 `commit` 会真实执行 `_spawn_footfall_vfx` 创建 `FootfallVFX` 节点（`:103-116`）。届时 `footfall_vfx.gd` 必须 headless 安全（不得依赖 RenderingServer-only 调用）。**本批评审不覆盖该路径**（Batch A 单测不触发），列为 Batch D 修复时的前置校验项。

---

## 3. Headless 安全小结（逐文件）

| 文件 | 构造方式 | 是否进场景树 | VFX/渲染依赖 | 结论 |
|------|---------|------------|-------------|------|
| `test_event_bus.gd` | `EventBus.new()`（Node） | 否 | 无；信号在任意 Object 上可 emit | 安全 ✓ |
| `test_light_model.gd` | `LightModel.new()`（RefCounted） | 否 | 无；`get_cover`/光照纯几何逻辑 | 安全 ✓（§2-A 监听遗漏除外） |
| `test_step_commit.gd` | `StepCommit.new()`（Node）不进树；`TimeController` 进树供 tween | `_step` 否 / `_time` 是 | VFX 因 `_step` 不在树被跳过；`Engine.time_scale` 复位 | 安全 ✓ |

> Batch A 未向任何新增测试引入场景树依赖，未重蹈 Sprint0 那 6 个集成测试的 SceneTree 失败模式。

---

## 4. 给用户的明确建议

1. **push 后盯 CI 的三文件**：`test_event_bus` / `test_light_model` / `test_step_commit`，预期**三者各自全绿**（共 4+3+3 新增/扩展例 + 继承例全过）。
2. **不要以"整体退出码 0"判 Batch A**：`tests/unit/` 同目录的 `test_integration_step_vision.gd`（6 例，E10-S1 / Batch D）仍会红，整跑退出码非 0 属**继承状态、非 Batch A 引入**。若团队要求 Batch A 冒烟"退出码 0"，请另开 Batch D 任务把那 6 例移出 `tests/unit` 或加 `-gignore`。
3. **建议 push 前补 1 行**：`test_light_model.gd` 的 `before_each` 加 `watch_signals(_lm)`（§2-A），与另两文件一致、消除 GUT 运行时语义不确定性。
4. **GDD 缺口待裁决**：§5.1（MOSS/STONE 系数与词汇集冲突）、§5.2（`SusTier` 的 `CALM` vs `NONE`）为 `impl.md` 已标注项，测试与实现一致不阻 CI，但请 主理人/文策渊 尽快收口，勿静默合并。
5. **Sprint0 的 6 个 TD 失败保持原状到 Batch D**：确认 Batch A 未触碰其结构（仅 `event_bus.gd` 的 `suspicion_changed` 2→3 改动已完整传播至 `hud_slice.gd`/`sprint0_bootstrap.gd`，且 `tests/unit` 下除 `test_event_bus.gd` 外无其它测试引用该信号 ⇒ 无新 cascading 失败）。

---

*评审文档 v0.1 · 严守真 · 静态 Read 评审（无 Godot 执行）· 判定 CONCERNS（无阻断性 API 不一致；1 中风险建议修复 + 1 CI 预期纠偏）。*
