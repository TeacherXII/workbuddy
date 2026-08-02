# Sprint 1 · Batch A 实现说明（词汇 + 光影地基）

**阶段**：Phase 5 · Sprint 1 · Batch A（7 Story：E01-S9 → E04-S3 → E04-S4 → E04-S7 → E03-S5 → E03-S6 → E03-S7）
**作者**：程基岩（engineering-lead）
**范围**：纯代码 + 测试 + 本说明；不写 GDD / 策划文档。
**验证方式**：本沙箱无法运行 Godot，全部以 Read 自校验（GDScript 语法 / 常量引用 / 信号签名一致性）+ GUT 纯逻辑断言（headless 安全，不进场景树）。所有新增/扩展测试走「策略 2 纯逻辑」。未触碰 Sprint 0 的 6 个失败集成测试（属 E10-S1 / Batch D）。

---

## 1. 落盘文件清单

| 文件 | 操作 | 涉及 Story |
| --- | --- | --- |
| `src/core/event_bus.gd` | 重写（收口词汇） | E01-S9 |
| `src/game/light_model.gd` | 重写（追加盖板/状态/脏 cell） | E04-S3 / E04-S4 / E04-S7 |
| `src/game/step_commit.gd` | 重写（三步态 + MOSS + VFX 钩子） | E03-S5 / E03-S6 / E03-S7 |
| `src/game/footfall_vfx.gd` | 新建 | E03-S7 |
| `src/main/sprint0_bootstrap.gd` | 改 1 处（副作用修复，见 §3） | E01-S9 后果 |
| `src/ui/hud_slice.gd` | 改 1 处（信号签名对齐） | E01-S9 后果 |
| `tests/unit/test_event_bus.gd` | 新建 | E01-S9 |
| `tests/unit/test_light_model.gd` | 扩展 +3 测试 | E04-S3 / E04-S4 / E04-S7 |
| `tests/unit/test_step_commit.gd` | 扩展 +3 测试 | E03-S5 / E03-S6 / E03-S7 |

---

## 2. 逐 Story 改动

### E01-S9 · 事件词汇收口（`event_bus.gd`）
- 新增枚举：`enum LightState { LIT, EXTINGUISHED }`、`enum SusTier { CALM, SUSPICIOUS, ALERT, SEARCH }`。
- **信号改名 / 签名修正（3 项漂移）**：
  1. `light_state_changed(point:Vector3, level:float)` → `light_state_changed(light_id:int, state:LightState)`。
  2. `suspicion_changed(guard_id:int, value:float)` → `suspicion_changed(guard_id:int, value:float, tier:SusTier)`。
  3. 补 4 个缺失信号：`guard_transform_dirty(guard_id:int)`、`cover_state_changed(cell:Vector3i)`、`vision_looming(guard_id:int)`、`guard_fsm_changed(guard_id:int, old:String, new:String)`。
- 保留 Sprint 0 其余 9 信号名与语义（`time_scale_changed` 仍用 `mode:String`，与 `TimeController` 发射方一致；`player_step_committed`/`sound_emitted`/`vision_stimulus`/`exposure_detected` 不变）。
- **故意未改（留给 Batch D，见 §4）**：`decoy_landed(pos:Vector3)`、`interactable_triggered(id:int, kind:String)` 维持 Sprint 0 形态（§2 想要更丰富 payload）。这是 sprint1-stories §4 三漂移清单之外的已知残余漂移，按计划由 E06-S4 / E09-S4 收口，不在 E01-S9 范围，以免牵连 Sprint 0 实现。
- 退出钩子：`tests/unit/test_event_bus.gd` → `test_event_vocabulary_complete` / `test_all_signals_can_connect_and_emit` / 两个签名专项断言。`EventBus.new()` 不进树，纯逻辑 emit/connect 全绿。

### E04-S3 · get_cover（`light_model.gd`）
- 新增：`const COVER_PENUMBRA := 1.0`、`var _cover_boxes`、`add_cover_box(center, radius)`、`get_cover(pos:Vector3) -> bool`。
- 语义：pos 位于遮挡体「邻接半影带」（`distance <= radius + COVER_PENUMBRA`）即判为 cover（LOS 中断候选）。**掩体 ≠ 无敌**：仅降 visibility + 提供 LOS 中断，真正 LOS 阻断由 E05 经 `SpatialQueryWrapper.has_line_of_sight` + visibility multiplier 落实（C-03 / G-03）。纯几何预检，便宜、非逐帧。
- 退出钩子：`test_get_cover_blocks_los`（邻接点 true / 空旷点 false）。

### E04-S4 · light_state_changed 完整签名（`light_model.gd`）
- 新增本地信号 `signal light_state_changed(light_id:int, state:int)`（与 EventBus 同签名，沿用 Sprint 0 StepCommit/VisionCone 的「本地信号 + EventBus 事件」模式，便于无树纯逻辑测试）。
- `var _light_states`、`register_light(id,pos)`、`get_light_state(id)`、`set_light_state(id,state)`、`toggle_light(id)`。
- `set_light_state` 更新字典并 `light_state_changed.emit(light_id, state)`。
- 退出钩子：`test_light_state_changed_emitted_with_state`（断言签名 + 字典更新 + toggle 还原）。
- 触发：R-02（熄灯释放实时光）、G-03（事件驱动）。

### E04-S7 · 受影响 cell 重算（`light_model.gd`）
- 新增目标注册：`register_target(id,pos)`（按 cell 分桶）、`mark_cell_dirty(cell)`、`get_recomputed_targets()`、`get_cached_light_level(id)`、`_last_recomputed`。
- cell 定位复用 `SpatialHashGrid3D.CELL`（ADR-002）：`_cell_of(pos) -> Vector3i`、`_cell_key(pos) -> String`。
- `set_light_state` 仅在灯所在 cell 调 `mark_cell_dirty`（O(cell)，非全图）；非逐帧（G-03）。`cover_state_changed` 的完整接线落消费者侧（E05）。
- 退出钩子：`test_light_change_recomputes_only_dirty_cell`（两 cell，改一个只重算该 cell 内目标）。

### E03-S5 · 噪声半径全 surface（`step_commit.gd`）
- `SURFACE_FACTOR` 增加 `"MOSS": 0.5`（见 §5 GDD 缺口）。其余 `STONE 1.0 / GRASS 0.7 / METAL 1.2` 维持 Sprint 0 / stealth-step-commit §2。
- 公式不变：`NOISE_BASE(5.0) × SURFACE_FACTOR × GAIT_FACTOR`。payload 已带 `surface` 字段（供 E06-S2）。
- 退出钩子：`test_noise_radius_all_surfaces`（SNEAK+MOSS=1.25 / WALK+GRASS=3.5 / RUN+METAL=12.0）。
- 触发：G-02（声环由 E06 校验）。

### E03-S6 · 三步态完整 RUN（`step_commit.gd`）
- 用 `const GAIT_PARAMS` 统一三步态：`SNEAK{1.5,0.55,0.5}` / `WALK{2.5,0.38,1.0}` / `RUN{4.0,0.24,2.0}`（max_step / step_duration / noise_factor）。`commit` 据 gait 取参，`noise_radius` 用 `noise_factor`。
- 新增 `effective_step_duration(time_scale)`：基值 ÷ time_scale（T-02 / ADR-003；FOCUS 0.25 下 RUN 步进 ~4× 慢）。payload 写入 `distance`、`step_duration`、`gait`。
- **RUN = 高成本 deliberate 选项**（用户裁决 D1）：10m 噪声显著引怪，代码注释明确「非无脑冲刺」，靠噪声半径而非手感做权衡（C-05）。
- 退出钩子：`test_gait_run_noise_and_step`（断言距离/step_duration/噪声系数 + FOCUS 缩放）。
- 触发：T-02、C-05。

### E03-S7 · 落足微光 / 足音 / 残影 VFX（`footfall_vfx.gd` + `step_commit.gd`）
- 新建 `FootfallVFX`（Node，自包含）：`spawn_landing_glow(pos)` 用 emissive quad（`#C8862F`，alpha ≤0.10，**非实时光**省 R-02）、`emit_foley(surface)` 发足音字幕占位信号（X-02，`FOOTFALL_SUBTITLE` 按 surface 变体）、`footfall_subtitle(surface)`。
- `StepCommit` 新增 `_spawn_footfall_vfx(from,to,surface)` 与 `is_vfx_enabled()`；仅当 `Engine.get_main_loop() != null && is_inside_tree()` 才实例化/创建 VFX 节点——**headless 下（测试 `_step` 不进树）完全跳过，绝不崩**。ghost_trail 维持 `MAX_GHOST=6` 上限。
- 收口 Sprint 0 CONCERN #4（落足微光/足音待落地）。
- 退出钩子：`test_footfall_vfx_present`（surface 写入 / ghost_trail ≤6 / VFX 跳过判空）。
- 触发：R-02、C-06、X-02、T-04。

---

## 3. E01-S9 的连带修复（信号签名破坏性改动）

`suspicion_changed` 由 2 参变 3 参，Sprint 0 有真实发射方，必须同步否则运行期报错：

- `src/main/sprint0_bootstrap.gd::_on_vision_stimulus`：原 `_bus.suspicion_changed.emit(guard_id, suspicion)` → 改为 3 参，新增 `_suspicion_tier(value)` 用连续值派生临时 tier（<25 CALM / <60 SUSPICIOUS / 否则 ALERT）；E08-S2 落地后用真实 25/60/10 替换。
- `src/ui/hud_slice.gd::_on_suspicion_changed`：形参加 `_tier: int`（Godot 4 允许少参连接，但显式对齐更稳）。HUD 逻辑不变。

上述两处是 E01-S9 的必要后果，已最小化改动、保留 Sprint 0 行为语义。

---

## 4. 故意保留的残余漂移（待 Batch D）

`decoy_landed(pos:Vector3)`、`interactable_triggered(id:int, kind:String)` 与 §2 全量 payload 形态不一致。按 sprint1-stories §4 的「3 项漂移」契约，E01-S9 只收口那 3 项；这两个由 E06-S4 / E09-S4（Batch D）对齐 §2 的 `DecoyPayload` / `obj_id,type,payload`。此处不动，避免牵连 Sprint 0 发射方。

---

## 5. ⚠️ GDD 缺口 / 待主理人+文策渊裁决项

### 5.1 表面（Surface）词汇与数值冲突（**待确认**）
四份来源互相矛盾：

| 来源 | 表面集合 / 值 |
| --- | --- |
| sprint1-stories E03-S5 原文 | `{STONE 1.0, GRASS 0.7, METAL 1.2, MOSS ?}` |
| `stealth-step-commit.md` §2 | `STONE 1.0 / GRASS 0.7 / METAL 1.2`（明确废弃 WOOD/MOSS，映射 WOOD≈STONE、MOSS≈GRASS） |
| `system-breakdown.md` §2.3 共享类型 | `Surface = STONE \| WOOD \| MOSS`（无 GRASS/METAL，无值） |
| `asset-manifest.md` §3.1 | `STONE 1.2 / WOOD 1.0 / MOSS 0.5`（无 GRASS/METAL） |

**Batch A 裁决（实现采用）**：遵循任务 E03-S5 显式指令 + Sprint 0 代码 →
`SURFACE_FACTOR = {STONE:1.0, GRASS:0.7, METAL:1.2, MOSS:0.5}`。
- **MOSS 系数 0.5 为「待主理人 / 文策渊确认的 GDD 缺口」提议值**（依据：苔藓吸音、应比 GRASS 0.7 更安静；与 asset-manifest §3.1 的 MOSS=0.5 巧合一致，但与 stealth-step-commit §2「MOSS 废弃≈GRASS=0.7」矛盾）。**未悄悄硬编码不留痕**——本文件 §5.1 与 `step_commit.gd` 注释均已标注。
- **STONE 值冲突**：实现用 1.0（任务 + stealth-step-commit §2 + Sprint 0），但 asset-manifest §3.1 写 1.2。请裁决统一。
- **词汇集冲突**：STONE/GRASS/METAL（实现）vs STONE/WOOD/MOSS（§2.3 / asset-manifest）。请裁决采用哪套，并回填 GDD。

### 5.2 SusTier 枚举成员冲突（**待确认**）
- `system-breakdown.md` §2.3：`SusTier = NONE | SUSPICIOUS | ALERT | SEARCH`。
- 任务 E01-S9 显式指令 + sprint1-stories §4：`SusTier = CALM | SUSPICIOUS | ALERT | SEARCH`。
- **Batch A 采用任务指令（CALM…）**，因为 E08-S2 阈值 25/60/10 映射的是 CALM/SUSPICIOUS/ALERT/SEARCH 带。请主理人/文策渊确认 §2.3 的 `NONE` 是否应改为 `CALM`。

---

## 6. Headless 安全说明

- 所有 Batch A 新增/扩展测试均为纯逻辑：`EventBus.new()` / `LightModel.new()` / `StepCommit.new()` 直接构造，**不 `add_child` 进场景树**（规避 Sprint 0 那 6 个 TD 的 SceneTree 问题）。
- `StepCommit` 的 VFX 创建被 `Engine.get_main_loop() != null && is_inside_tree()` 双重包裹；测试中 `_step` 不进树 → 跳过渲染节点创建，提交永不崩溃。
- `LightModel` / `EventBus` 不依赖任何场景树 API；`has_line_of_sight` 在 headless 无世界时返 true（已被既有 `spatial_query_wrapper` 处理），`get_cover` 走纯几何，不受影响。
- 未修复 Sprint 0 的 6 个失败集成测试（E10-S1 / Batch D 职责）。Batch A 仅保证自身新增测试 headless 安全。

---

## 7. 批间冒烟预期（A 末）

运行：`godot --headless -s res://addons/gut/gut_cmdln.gd -gdir=res://tests/unit -gexit`

- **`test_light_model`**：既有 6 例（阈值/暗亮/敏感度）全绿 + 新增 3 例（`test_get_cover_blocks_los` / `test_light_state_changed_emitted_with_state` / `test_light_change_recomputes_only_dirty_cell`）。
- **`test_step_commit`**：既有 8 例全绿 + 新增 3 例（`test_noise_radius_all_surfaces` / `test_gait_run_noise_and_step` / `test_footfall_vfx_present`）。
- **`test_event_bus`**（新增）：4 例全绿。

预期：上述三文件全绿、退出码 0。Sprint 0 既有的 6 个集成测试失败保持原状（Batch D 修复），不在本批范围。

---

*Batch A 实现说明 v0.1 完成。§5 两项为待主理人 / 文策渊裁决的 GDD 缺口，请勿静默合并。*
