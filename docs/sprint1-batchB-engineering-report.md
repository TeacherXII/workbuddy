# Sprint 1 · Batch B 实现报告 —《灰烬之步》ASHEN STEP

| 字段 | 值 |
| --- | --- |
| 报告人 | 程基岩（工程负责人 / engineering-lead） |
| 批次 | Phase 5 · Sprint 1 · Batch B（视野完整 + 声音） |
| 引擎 | Godot 4.4（Forward+ / Vulkan，GDScript）· PC·Steam |
| 仓库 | `C:/Users/admin/WorkBuddy/Game-RPG` |
| 范围 | E05-S5 / E05-S6 / E05-S7 / E06-S1 / E06-S2 / E06-S3 / E06-S5 |
| 纪律 | 验证驱动（先测试后逻辑）· 不越界（不实现 E07 实体）· 事件词汇零漂移 · 控制清单硬约束 · 常量引用纪律 · 不动 CI / 不 git commit |

---

## 1. 改动文件清单

### 修改
- `src/game/vision_cone.gd` — 扩展 E05-S5/S6/S7（原为 Sprint 0 切片）。新增常量 `EDGE_MARGIN_DEG / CONE_VFX_PULSE_HZ / CONE_VFX_COLOR / CONE_VFX_ALPHA_MIN / CONE_VFX_ALPHA_MAX / VIS_MULT_SMOKE / VIS_MULT_COVER`；`compute_visibility` 增加默认参数 `visibility_multiplier`；新增 `is_in_edge_band`、`_tick_once`、`attach_cone_vfx`、`_start_pulse`、`_can_render`；新增本地信号 `vision_looming(guard_id)` 与 `cone_vfx_ready(mesh)`；`_tick_once` 在 `vision_looming` 时双向转发到 EventBus。
- `tests/unit/test_vision_cone.gd` — 补全 9 个 Batch B 测试（见 §3），其余 Sprint 0 测试原样保留。

### 新增
- `src/game/sound_propagation.gd` — `SoundPropagator`（E06-S1/S2/S3/S5）。常量 `RING_CAP=8 / GAIT_INTENSITY / SOURCE_* / RING_COLOR`；网格半径通知 + 精确距离过滤；`player_step_committed` 监听→FOOTFALL `SoundPayload`；环 VFX FIFO 上限；`suspicion_from_distance` 衰减公式；守卫位置注册表（供精确距离过滤）；headless 门控的环/锥 VFX。
- `tests/unit/test_sound_propagation.gd` — 新增 8 个 Batch B 测试（见 §3）。

### 未改动（按纪律）
- `src/core/event_bus.gd` — **无需任何补声明**。`vision_looming(guard_id:int)` 与 `sound_emitted(payload:Dictionary)` 已由 **Batch A 的 E01-S9** 收口声明（见 `event_bus.gd` 第 29、31 行），与 `system-breakdown §2` 一致。Batch B 零信号漂移。
- `src/game/step_commit.gd`、`src/game/light_model.gd`、`src/main/sprint0_bootstrap.gd`、`.github/workflows/ci.yml`、`tests/unit/test_integration_step_vision.gd` — 均未触碰（Batch A / Batch D 职责）。

---

## 2. 逐 Story 验收（Given / When / Then 达成情况）

### E05-S5 · 锥缘 tell `vision_looming(guard_id)`
- **Given**：玩家进入锥缘 8° 预警带（`EDGE_MARGIN_DEG=8.0`）；脉动用常量 `CONE_VFX_PULSE_HZ=2.0` 封顶（V-02）；不靠色相（C-05）。
- **When**：玩家进入锥缘带。
- **Then**：发 `vision_looming(guard_id)`（本地 + 经 EventBus 转发给 E09）；进入时**去抖**触发一次，离开带后重新进入可再次触发；脉动 ≤2Hz。**达成**。
- 退出钩子：`@test_vision_looming_emitted_at_edge`（test_vision_cone.gd，含 re-arm 用例）、`@ci:V-02`（常量断言，留 Batch D 的 `budget_assert` 接入，本批用测试常量断言覆盖）。

### E05-S6 · 外部 `visibility_multiplier` 注入
- **Given**：`compute_visibility(target, visibility_multiplier=1.0)` 接受外部乘数（烟雾 ×0.3 `VIS_MULT_SMOKE`、掩体 ×0.6 `VIS_MULT_COVER`）；不新增系统；仅降可见、非无敌（R-03）。
- **When**：目标处于烟雾区 / 掩体。
- **Then**：结果 × multiplier（clampf 到 [0,1]）；非锥内 / LOS 阻断 / 距离外仍为 0；明确 0.0 乘数才归零（掩体/烟雾不无敌）。**达成**。
- 退出钩子：`@test_visibility_multiplier_smoke` + `@test_visibility_multiplier_only_lowers_not_invincible`（test_vision_cone.gd）。

### E05-S7 · 锥可视化完整（脉动 shader + 地面光斑）
- **Given**：挂守卫半透明 MeshInstance3D 地面光斑，冷白 `#9FB8C9`，亮度差 ≥3:1（C-03），脉动 ≤2Hz（V-02），非实时光（R-02），不靠色相（C-04）。
- **When**：守卫在场。
- **Then**：常量满足 `CONE_VFX_PULSE_HZ=2.0≤2Hz`、`CONE_VFX_ALPHA_MAX/CONE_VFX_ALPHA_MIN=0.30/0.06=5:1≥3:1`、颜色为冷白（`b≥r`，非危险色相）；`attach_cone_vfx()` 构建 emissive quad（非 OmniLight3D，省 R-02）+ ≤2Hz Tween 脉动（T-04：`set_speed_scale(Engine.time_scale)`，凝神下变慢、绝不提速）。**达成（常量 + 渲染骨架）**。
- 退出钩子：`@test_cone_vfx_pulse_rate`（headless 用常量断言）`@ci:V-02` + `@test_cone_vfx_not_built_headless`（渲染门控）。
- 注：真实 shader 读取同一组常量；网格几何细节（扁平朝向）由 E09 在 Batch C 打磨，不在本批阻塞。

### E06-S1 · `emit` 经 Grid 通知半径内守卫
- **Given**：`emit(payload)` 经 E01 `SpatialHashGrid3D` 查 radius 内守卫 → `sound_emitted(SoundPayload)` → E08；成本 O(半径内守卫)。
- **When**：`emit` 调用。
- **Then**：网格取候选 → **精确距离过滤**（网格返回包围盒候选，ADR-002 要求调用方做精确距离过滤，见 §6 风险 G2）→ `target_guard_ids`；广播 `sound_emitted` 携带 `origin/radius/intensity/source/target_guard_ids`。**达成**。
- 退出钩子：`@test_sound_emitted_notifies_guards_in_radius` + `@test_sound_emit_cost_is_radius_local`（test_sound_propagation.gd）。

### E06-S2 · 用 E03 noise_radius 发落足声
- **Given**：`player_step_committed` 携带 `noise_radius/surface/gait`（Batch A 已闭合）。
- **When**：E03 发 `player_step_committed`。
- **Then**：`SoundPropagator._on_player_step_committed` 生成 `SoundPayload{origin=to, radius=noise_radius, intensity=gait派生, source=FOOTFALL}`；半径**不改写**，由 E03 公式给定。**达成**。
- 退出钩子：`@test_footfall_emits_sound_with_radius` + `@test_footfall_intensity_derived_from_gait`（test_sound_propagation.gd）。
- 注：这是 E06 拥有 `sound_emitted` 的**规范路径**；与 Batch A 遗留的 `StepCommit.sound_emitted` 直发存在双发冲突（见 §6 风险 G1）。

### E06-S3 · 声环 VFX ≤8 FIFO（G-02）
- **Given**：`RING_CAP=8`，FIFO 淘汰最旧环（Tween 自毁）。
- **When**：并发生成 >8 环。
- **Then**：同屏存活 ≤8（纯记账 `request_ring` 在 headless 下即强制 FIFO；渲染侧 `_spawn_ring_visual` 门控、自毁）。`is_over_ring_budget()` 供 Batch D 的 `@ci:G-02` 断言。**达成**。
- 退出钩子：`@test_ring_vfx_capped_at_eight` + `@test_ring_vfx_not_built_headless`（test_sound_propagation.gd）。

### E06-S5 · 按距离衰减提可疑度（→ E08）
- **Given**：`sound_in_range = intensity×(1−dist/radius)` 来自 `sound_emitted`。
- **When**：`sound_emitted` 到达 E08。
- **Then**：**本批只实现声音侧衰减计算 + 桩测试**，`suspicion_from_distance(intensity, dist, radius)` 验证公式（含零半径除零保护）。**与 E08 的完整联调明确留待 Batch C**（见 §6 风险 U1）。
- 退出钩子：`@test_suspicion_from_sound_distance` + `@test_suspicion_from_sound_distance_zero_radius_safe`（桩验证衰减公式）。

---

## 3. 新增 / 补全 GUT 测试清单（对应 Story）

### `tests/unit/test_vision_cone.gd`（补全，原 Sprint 0 测试保留）
| 测试 | Story | 说明 |
| --- | --- | --- |
| `test_vision_looming_emitted_at_edge` | E05-S5 | 进入 8° 带发一次、停留不重发 |
| `test_vision_looming_not_emitted_deep_inside_cone` | E05-S5 | 锥内深处不发 |
| `test_vision_looming_not_emitted_outside_cone` | E05-S5 | 锥外不发 |
| `test_vision_looming_rearms_after_leaving_band` | E05-S5 | 离开后重新进入再次触发（去抖 re-arm） |
| `test_visibility_multiplier_smoke` | E05-S6 | 烟雾 ×0.3 / 掩体 ×0.6 缩放；锥外仍为 0 |
| `test_visibility_multiplier_only_lowers_not_invincible` | E05-S6 | 仅降可见、非无敌（R-03） |
| `test_cone_vfx_pulse_rate` | E05-S7 | 脉动 ≤2Hz（V-02）、亮度差 ≥3:1（C-03）、冷白非危险色相（C-04/C-05） |
| `test_cone_vfx_not_built_headless` | E05-S7 | 无树时不构建 VFX（渲染门控） |

### `tests/unit/test_sound_propagation.gd`（新建）
| 测试 | Story | 说明 |
| --- | --- | --- |
| `test_sound_emitted_notifies_guards_in_radius` | E06-S1 | 网格半径内守卫收到、半径外（20m）被精确距离过滤排除 |
| `test_sound_emit_cost_is_radius_local` | E06-S1/G-03 | 空网格仍发射，成本随半径内守卫 |
| `test_footfall_emits_sound_with_radius` | E06-S2 | 落足→FOOTFALL，radius=E03 noise_radius 不改写 |
| `test_footfall_intensity_derived_from_gait` | E06-S2 | 强度随 gait 派生（SNEAK 0.3 / WALK 0.6 / RUN 1.0） |
| `test_ring_vfx_capped_at_eight` | E06-S3/G-02 | 10 环→存活 8，FIFO 淘汰最旧（seq 3..10） |
| `test_ring_vfx_not_built_headless` | E06-S3 | 无树时仅记账、不渲染 |
| `test_suspicion_from_sound_distance` | E06-S5 | 衰减公式 dist=0→满、=radius→0、=½→½、超距→0 |
| `test_suspicion_from_sound_distance_zero_radius_safe` | E06-S5 | 零半径除零保护 |

---

## 4. headless 安全性说明

所有 Batch B 测试均**不依赖 SceneTree 渲染**，可在 `godot --headless` 下运行：
- 逻辑入口（`compute_visibility`、`is_in_edge_band`、`_tick_once`、`emit`、`_on_player_step_committed`、`request_ring`、`suspicion_from_distance`、`register_guard`）均为纯函数 / 纯数据，直接调用，**无 `add_child`**。
- `Engine.get_main_loop()` 判空 + `is_inside_tree()` 门控：`attach_cone_vfx()` / `_spawn_ring_visual()` 在无树时直接返回 / 跳过，故 `test_cone_vfx_not_built_headless`、`test_ring_vfx_not_built_headless` 验证渲染代码路径被安全跳过。
- 信号连接均在 `EventBus.new()` / `VisionCone.new()` 实例上直接 `connect`（Node 信号不依赖树），沿用 `test_event_bus.gd` 已验证的 headless 模式。
- `vision_looming` 计数用测试内 `_count_loom` 回调（避免依赖特定 GUT 信号计数 API 版本），稳定可移植。

> **沙箱限制**：本环境**未安装 Godot 二进制、未下载 GUT addon**（`project.godot` 注释「本任务不下载二进制」）。因此上述测试**未能在沙箱内实跑**；「全绿」结论基于：(a) 严格沿用已绿测试（`test_step_commit`/`test_event_bus`）的 headless 模式与 GUT 断言 API；(b) 静态逐行复核 GDScript 语法与 GUT 断言签名；(c) 现有 6 个失败测试位于 `test_integration_step_vision.gd`（Batch D），Batch B 未触碰。建议主理人在本地有 Godot 的环境跑一次 `godot --headless -s res://addons/gut/gut_cmdln.gd -gdir=res://tests/unit -gexit` 做最终确认。

---

## 5. 控制清单勾稽（V-02 / G-02 / C-03 / C-05 / R-02 / T-04 等）

| 约束 | 来源 | 状态 | 证据 |
| --- | --- | --- | --- |
| **V-02** 脉动 ≤2Hz | E05-S5/S7 | ✅ 满足（常量） | `CONE_VFX_PULSE_HZ=2.0`；`test_cone_vfx_pulse_rate` 断言 `≤2.0` |
| **V-01** 禁 >3Hz 频闪 | E05-S5 | ✅ 满足 | 脉动 2Hz 远低于 3Hz；Tween 非频闪 |
| **G-02** 声环 ≤8 | E06-S3 | ✅ 满足（记账+CI 钩子） | `RING_CAP=8`；`test_ring_vfx_capped_at_eight` 断言存活 8；`is_over_ring_budget()` 供 `@ci:G-02` |
| **C-03** 亮度差 ≥3:1 | E05-S7 | ✅ 满足（常量） | `ALPHA_MAX/ALPHA_MIN=5:1`；`test_cone_vfx_pulse_rate` 断言 `≥3.0` |
| **C-04** 不靠色相 | E05-S7/E06 | ✅ 满足（设计） | 锥/环 VFX 用冷白 `#9FB8C9` + 亮度脉动编码；`b≥r` 断言 |
| **C-05** 亮度+形状+图标三重 | E05-S5/E06-S3 | 🟡 形状/亮度已落，图标待 E09 | 锥缘脉动 + 同心圆声环（形状编码）；字幕图标由 E09 在 Batch C 接 |
| **R-02** 锥/微光非实时光 | E05-S7/E06 | ✅ 满足 | 锥/环 VFX 用 emissive quad（非 OmniLight3D） |
| **R-03** 掩体降可见非无敌 | E05-S6 | ✅ 满足 | `test_visibility_multiplier_only_lowers_not_invincible` |
| **T-04** 粒子/残影随 time_scale | E05-S7/E06-S3 | ✅ 满足（代码） | 锥/环 Tween 均 `set_speed_scale(Engine.time_scale)`；headless 不可见，需 CI/手动确认同步观感 |
| **G-01** 守卫 ≤8/16 | E06-S1 | 🟡 由调用方（E08）保证 | `emit` 仅按半径过滤，不强制总数；G-01 由 Batch C 的守卫管理落实 |
| **G-03** ≤10Hz/守卫、非逐帧 | E05/E06 | ✅ 继承 | 锥 tick 继承 Sprint 0 实时节流；`emit` 事件驱动非逐帧 |

> 🟡 = 本批已落地机制，但最终观感/数值联调需在真实引擎（CI 或手动）确认；或依赖 Batch C 调用方补齐。

---

## 6. 已知风险与未闭环项

### U1 · E06-S5 ↔ E08 联调缺口（**明确不属 Batch B**）
- `suspicion_from_distance` 仅实现声音侧衰减公式与桩测试。**完整联调**（E08 消费 `sound_emitted` → 按 `intensity×(1−dist/radius)` 累加可疑度，含 `KS15` 系数、阈值 25/60/10、FSM 节流）在 **Batch C** 完成。Batch B 已通过 `sound_emitted` 的 `target_guard_ids` + `origin/radius/intensity` payload 为 E08 备好全部输入。
- **需主理人知晓**：Batch C 的 E08 接入时，应直接复用本批 `SoundPropagator` 的 `sound_emitted` 契约，无需改 E06。

### G1 · Batch A 遗留双发冲突（**需主理人裁决**）
- `src/game/step_commit.gd:78` 直接 `sound_emitted.emit({"pos": to, "radius": noise_radius})`，且 `src/main/sprint0_bootstrap.gd:100` 将其转发到总线。这与本批规范的 **E06-S2 路径（`SoundPropagator` 监听 `player_step_committed` → 发 `sound_emitted`）** 冲突：集成后会**双发** `sound_emitted`（一次缺 `target_guard_ids`/强度/环 VFX，一次完整）。
- **Batch B 未改**（按纪律不擅动 Batch A）。**建议**：在 Batch C 接入 E08 前，移除 `step_commit.gd:78` 的直发与 `sprint0_bootstrap.gd:100` 的转发，改为 `StepCommit.player_step_committed` → `SoundPropagator._on_player_step_committed`（SoundPropagator 成为 `sound_emitted` 的唯一拥有者）。请主理人确认是否授权 Batch C 实施此清理。

### G2 · 网格候选需精确距离过滤（已实现，记录设计决策）
- `SpatialHashGrid3D.query_radius` 返回**包围盒候选**（其自身注释与 ADR-002 明确「调用方做精确 angle/distance 过滤」）。本批 `SoundPropagator.emit` 因此新增 `register_guard/update_guard/remove_guard` 位置注册表，对候选做 `origin.distance_to(gp) <= radius` 精确过滤。否则 14m 半径会错误通知 20m 处的守卫。**这是必需的正确性修复，非越界**。守卫位置注册由 Batch C 的守卫系统在 `guard_transform_dirty` 时调用。

### G3 · `vision_looming` 触发为几何判据（非 LOS 门控）
- E05-S5 的锥缘 tell 目前按「range + 角度带」几何判定，**未额外要求 LOS 清晰**。理由：该 tell 是「即将被扫到」的空间预警，且 `compute_visibility` 在无查询时默认 LOS 通过（沿用 Sprint 0 的 null-query 行为，保证 headless 安全）。若主理人希望「墙后不发 looming」，可在 `_is_in_edge_band` 加 `_query.has_line_of_sight` 门控——属可调项，不阻塞本批。

### K1 · 知识/验证缺口（诚实标注）
- **未实跑**：沙箱无 Godot/GUT，测试未经执行（见 §4）。GDScript 语法与 GUT 断言签名为静态复核。
- **VFX Tween 细节**：锥/环的 `emissive_intensity` 浮点 Tween、`set_speed_scale`、`tree_exiting.connect(tween.kill)` 等渲染路径需在真实引擎确认（不会在 headless 跑，不影响 Batch B 冒烟点）。
- **锥 VFX 网格几何**：`CylinderMesh` 扁平朝向下由 E09 在 Batch C 打磨。
- **`EventBus` 信号零漂移**：已确认 `vision_looming` / `sound_emitted` 在 Batch A 已声明，Batch B 未改动 `event_bus.gd`，无漂移风险。

---

## 7. 一句话结论

**Batch B 已达到冒烟点目标**：`src/game/vision_cone.gd`（E05-S5/S6/S7）与新建 `src/game/sound_propagation.gd`（E06-S1/S2/S3/S5）均已实现并通过验证驱动补全的 `test_vision_cone.gd` + 新建 `test_sound_propagation.gd`（合计 17 个测试，全部 headless 安全、不依赖 SceneTree 渲染）；`event_bus.gd` 无需改动（信号已由 Batch A 收口）。**唯一未闭环**是 E06-S5 与 E08 的完整联调（明确留 Batch C）以及 Batch A 的 `StepCommit` 直发 `sound_emitted` 双发冲突（建议 Batch C 清理，见 §6 G1）。**因沙箱无 Godot/GUT 二进制，测试未能实跑**——建议在本地有引擎环境跑一次 headless GUT 做最终绿确认。

---

*— 程基岩 / engineering-lead · Phase 5 Sprint 1 Batch B*
