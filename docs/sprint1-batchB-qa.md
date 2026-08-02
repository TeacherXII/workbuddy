# Sprint 1 · Batch B QA 计划与质量门评审 —《灰烬之步》ASHEN STEP

| 字段 | 值 |
| --- | --- |
| 评审人 | 严守真（quality-lead / QA 负责人） |
| 批次 | Phase 5 · Sprint 1 · Batch B（视野完整 E05-S5/S6/S7 + 声音 E06-S1/S2/S3/S5） |
| 评审类型 | 真实质量门评审（非调研）。静态评审 + 文档核对；沙箱无 Godot/GUT，测试未经实跑 |
| 仓库 | `C:/Users/admin/WorkBuddy/Game-RPG` |
| 上游依据 | `docs/sprint1-batchB-engineering-report.md`（程基岩）· `production/sprints/sprint1-stories.md` · `production/sprints/sprint1-plan.md` |
| 实现产物 | `src/game/vision_cone.gd` · `src/game/sound_propagation.gd` · `tests/unit/test_vision_cone.gd` · `tests/unit/test_sound_propagation.gd` |

---

## 1. 执行摘要（质量门判定）

> **Batch B QA 质量门 = CONCERNS**（非 FAIL，非 PASS）

**判定逻辑**（依据主理人纪律）：FAIL = 实现/测试本身有缺陷；CONCERNS = 测试未实跑、需本地确认。
- 实现产物（`vision_cone.gd` / `sound_propagation.gd`）**未发现逻辑缺陷**。
- 16 个 Batch B 测试**未发现测试逻辑缺陷**（含对 GUT 断言签名的逐条核对，已与绿色套件交叉验证）。
- 但**沙箱无 Godot/GUT 二进制，16 个测试均未经执行**——无法出具「全绿」认证。
- 另有 VFX 渲染观感、Batch A 双发集成风险等需真实引擎/后续批次确认的项。

**核心阻塞项（local 实跑前无法解除）**：
1. **K1-未实跑**：16 测试需在本地 `godot --headless -s res://addons/gut/gut_cmdln.gd -gdir=res://tests/unit -gexit` 跑通确认（详见 §10）。
2. **K1-VFX 观感**：锥/环 Tween 脉动（≤2Hz）、emissive 渲染、T-04 `time_scale` 同步、C-03 对比度观感 **无法 headless 验证**，仅常量被断言；需 CI `budget_assert`（E10-S2）或手动确认。
3. **G1-双发**：Batch A 遗留 `StepCommit.sound_emitted` 直发 + 本批 `SoundPropagator` 规范路径，集成后双发 `sound_emitted`；需主理人授权 Batch C 清理（不在本批单测覆盖内）。

**转 PASS 条件**：本地实跑 `test_vision_cone` + `test_sound_propagation` 全绿，且 VFX 观感经 CI/手动确认 → 门可转 PASS（仍建议保留 G1 为 Sprint 1 退出项）。

---

## 2. 测试清单与计数校正

**报告/主理人所述「17 个」与实测不符** —— QA 务必澄清，避免下游误判覆盖度：

- 工程报告 §1 称 `test_vision_cone.gd`「补全 **9** 个 Batch B 测试」；但 §3 表格实际列出 **8** 个；§7 称「合计 **17** 个」。
- 实际文件核对：`test_vision_cone.gd` 的 Batch B 段（行 83 注释 `# Batch B` 之后）含 **8** 个；`test_sound_propagation.gd`（整文件新建）含 **8** 个。
- **真实 Batch B 测试数 = 16**（非 17）。报告内 §1「9」、§7「17」为笔误（应为 8 / 16）。
- **覆盖度无缺口**：E05-S5/S6/S7、E06-S1/S2/S3/S5 的 Given/When/Then 均被覆盖（见 §5 矩阵）。建议工程报告将「9」「17」修正为「8」「16」。

> 注：下方 §3 逐条评审覆盖全部 16 个 Batch B 测试 + 一并核对 `test_vision_cone.gd` 中 6 个 Sprint 0 回归测试（因 Batch B 冒烟点会一起跑）。

---

## 3. 逐测试静态评审（Batch B 16 条 + 回归守卫）

评级说明：**PASS**（静态合理、headless 安全、API 正确）/ **DEFECT**（发现测试逻辑缺陷，需工程修复）。本批 **无 DEFECT**。

### 3.1 `tests/unit/test_vision_cone.gd`（Batch B 段，行 89–186）

| # | 测试 | Story | 覆盖 G/W/T | headless 可验 | 评审 |
| --- | --- | --- | --- | --- | --- |
| V1 | `test_vision_looming_emitted_at_edge` | E05-S5 | 进入 8°带 → `vision_looming` 触发**一次**（去抖）；停留不重发 | ✅ 纯 `_tick_once()` | **PASS** — 用测试内 `_count_loom` 回调计数（规避 GUT 信号计数 API 版本差异），`_loom_count` 断言 1→1 正确 |
| V2 | `test_vision_looming_not_emitted_deep_inside_cone` | E05-S5 | 锥内深处（0°）不发 tell | ✅ | **PASS** |
| V3 | `test_vision_looming_not_emitted_outside_cone` | E05-S5 | 锥外（47°）不发 tell | ✅ | **PASS** |
| V4 | `test_vision_looming_rearms_after_leaving_band` | E05-S5 | 离开带→重新进入再次触发（re-arm） | ✅ | **PASS** — 1→离开仍1→再入2，逻辑正确 |
| V5 | `test_visibility_multiplier_smoke` | E05-S6 | 烟×0.3 / 掩体×0.6 缩放；锥外仍为 0 | ✅ `assert_almost_eq` 容差 1e-4 | **PASS** — 基1.0、×0.3、×0.6、锥外0 全中 |
| V6 | `test_visibility_multiplier_only_lowers_not_invincible` | E05-S6 | 掩体仅降可见非无敌；仅显式 0.0 归零（R-03） | ✅ | **PASS** — `seen∈(0,1)`、`0.0` 仅显式乘数 |
| V7 | `test_cone_vfx_pulse_rate` | E05-S7 | V-02≤2Hz、C-03 亮度差≥3:1、C-04/C-05 冷白非危险色相、色值 `#9FB8C9` | ✅ 常量断言 | **PASS** — `PULSE_HZ=2.0≤2`、`ALPHA_MAX/MIN=5:1≥3`、`b≥r`、色值相等 |
| V8 | `test_cone_vfx_not_built_headless` | E05-S7 | 无树时 `attach_cone_vfx()` 返回 null（渲染门控） | ✅ | **PASS** — `_can_render()` 依赖 `is_inside_tree()`，`_vc` 未 `add_child` → false → null |

### 3.2 `tests/unit/test_sound_propagation.gd`（整文件新建，8 条）

| # | 测试 | Story | 覆盖 G/W/T | headless 可验 | 评审 |
| --- | --- | --- | --- | --- | --- |
| S1 | `test_sound_emitted_notifies_guards_in_radius` | E06-S1 | Grid 查半径内守卫→`sound_emitted`；**精确距离过滤排除 20m**（G2） | ✅ 纯逻辑 | **PASS** — 3/12m 入、20m 出；`_captured` payload（radius/origin/source）透传 E08 正确。**这是 G2 风险的现网覆盖证据** |
| S2 | `test_sound_emit_cost_is_radius_local` | E06-S1/G-03 | 空网格仍发射；成本随半径内守卫（非总数/帧率） | ✅ | **PASS** — `target_guard_ids` 空、`intensity` 透传 |
| S3 | `test_footfall_emits_sound_with_radius` | E06-S2 | 落足→FOOTFALL；`radius`=E03 `noise_radius` 不改写 | ✅ | **PASS** — `to`/`5.0`/`FOOTFALL`/`WALK=0.6` 全中（显式 `_bind_bus()` 补 `_ready` 未触发） |
| S4 | `test_footfall_intensity_derived_from_gait` | E06-S2 | 强度随 gait（SNEAK 0.3 / RUN 1.0） | ✅ | **PASS** |
| S5 | `test_ring_vfx_capped_at_eight` | E06-S3/G-02 | 10 环→存活 8，FIFO 淘汰最旧（seq 3..10） | ✅ 纯记账 | **PASS** — `_rings.size()==8`、`[0].seq==3`、`[7].seq==10`、`is_over_ring_budget()==false` |
| S6 | `test_ring_vfx_not_built_headless` | E06-S3 | 无树时仅记账不渲染 | ✅ | **PASS** — `_rings.size()==1`，`_can_render()` false 跳过 `_spawn_ring_visual` |
| S7 | `test_suspicion_from_sound_distance` | E06-S5 | 公式 `intensity×(1−dist/radius)`：dist=0→满、=R→0、=½→½、>R→0；含 gait 派生 | ✅ | **PASS** — 6 组断言全中（桩验证，E08 联调见 U1） |
| S8 | `test_suspicion_from_sound_distance_zero_radius_safe` | E06-S5 | 零半径除零保护 | ✅ | **PASS** — `radius=0→0.0` |

### 3.3 Sprint 0 回归测试（`test_vision_cone.gd` 行 43–80，Batch B 冒烟点会一起跑）

| 测试 | 评审 |
| --- | --- |
| `test_target_in_light_pool_is_detected` | PASS — 光池 `compute_visibility=1.0`（LightModel 无阴影盒） |
| `test_target_in_shadow_is_invisible` | PASS — 阴影盒内 `get_light_level=0.1→light_sensitivity=0.0→0.0` |
| `test_target_outside_cone_is_invisible` | PASS — (0,20,5) 超 35°→0.0 |
| `test_cone_constants_align_to_gdd` | PASS — `HALF_ANGLE=35 / RANGE=14 / TICK_HZ=10` |
| `test_phase_offset_initialized_within_tick_window` | PASS（依赖 SceneTree）— `add_child(_vc)` 触发 `_ready` 设 `_accum∈[0,0.1)`。**该 `add_child` 模式与绿色 Batch A `test_step_commit.gd:50` 一致，headless 可用** |
| `test_no_light_model_assumes_full_light` | PASS — `_light=null` 时假设满光 → 1.0 |

---

## 4. GUT v9.3.0 断言 API 逐条核对

核对所用 API：`assert_eq` / `assert_true` / `assert_false` / `assert_null` / `assert_almost_eq` / `assert_signal_emitted` / `assert_signal_not_emitted` / `watch_signals`。

| 断言 | 用法 | 正确性 |
| --- | --- | --- |
| `assert_eq(a, b, "msg")` | 全 16 测试 | ✅ `(thing, expected, text="")` 3 参为 text，正确 |
| `assert_almost_eq(a, b, 1e-4, "msg")` | V5/S7/S8 | ✅ `(thing, expected, tolerance, text="")` 容差占 3 参、text 占 4 参，正确 |
| `assert_true` / `assert_false` / `assert_null` | 多处 | ✅ 标准用法 |
| `assert_signal_not_emitted(obj, "sig", "msg")` | V2/V3 | ✅ `(object, signal_name="", text="")`，3 参为 text，正确 |
| `assert_signal_emitted(obj, "sig")` | S2 | ✅ 2 参，正确 |
| `assert_signal_emitted(obj, "sig", "msg")` | V1/S1/S3 | ✅ **有效**（详见下框澄清） |
| `watch_signals(obj)` + 手动 `connect` 计数 | V1/V4 | ✅ 规避 GUT 信号计数 API 版本差异，稳健 |

> ### ⚠️ 关于 `assert_signal_emitted(obj, "sig", "msg")` 三参形式的专项澄清
> 评审初期曾质疑：GUT v9 文档签名 `assert_signal_emitted(object, signal_name="", parameters=null, text="")` 的**第 3 个位置参数是 `parameters` 而非 `text`**，若把字符串 message 传入会变成「期望参数」，导致信号已发射却断言失败。
> **但交叉核对绿色 Batch A 套件后确认该形式为有效**：`test_step_commit.gd:85-86 / 164-165 / 166-167` 使用**完全相同**的 `assert_signal_emitted(_step, "player_step_committed", "msg")` 三参形式，而 `test_step_commit` 是 Batch A 冒烟点且报告称已全绿。
> **结论**：本项目实际使用的 GUT 版本接受「第 3 参为 text」的三参形式（与 `assert_signal_emitted_with_parameters` 分置），Batch B 沿用无缺陷。**此为「已澄清、无问题」项，非缺陷**，记录于此以示评审 rigor，避免后续误报。

---

## 5. 外部依赖静态核对（测试未实跑，缺方法/信号即隐性缺陷）

| 依赖 | 文件 | 核对结果 |
| --- | --- | --- |
| `EventBus` 信号声明 | `src/core/event_bus.gd` | ✅ `player_step_committed(payload)` / `sound_emitted(payload)` / `vision_stimulus(...)` / `vision_looming(guard_id)` **均声明**（行 25/29/30/31）。Batch B 引用与声明**零漂移** |
| `SpatialHashGrid3D.insert` / `query_radius` | `src/core/spatial_hash_grid.gd` | ✅ `insert(id, pos)`（行 27）、`query_radius(center, radius)→Array[int]`（行 49）存在；返回包围盒候选（与 G2 设计一致） |
| `LightModel.add_shadow_box` / `get_light_level` / `light_sensitivity` | `src/game/light_model.gd` | ✅ 均存在（行 45/49/58）；Sprint 0 回归测试有效 |
| `SoundPropagator` 依赖注入 | `sound_propagation.gd` | ✅ `set_event_bus` / `set_grid` / `_bind_bus`（带 `is_connected` 防双连）设计正确；`before_each` 不触发 `_ready`，测试显式 `_bind_bus()` 合理 |

---

## 6. 测试矩阵（Story → Given/When/Then → 测试 → 验证层级）

| Epic/Story | Given / When / Then（摘要） | 覆盖测试 | headless 可验 ✅ / 需真实引擎 🔶 |
| --- | --- | --- | --- |
| **E05-S5** 锥缘 tell | G: 玩家入 8°带 → W: 进入 → T: 发 `vision_looming` 一次、去抖、离开 re-arm、≤2Hz | V1, V2, V3, V4 | ✅ 全部 headless（信号语义）；🔶 V-02「≤2Hz 频率」仅常量断言，真实脉冲观感见 §9-VFX |
| **E05-S6** 可见度乘数 | G: `compute_visibility` 接 `visibility_multiplier` → W: 烟/掩体 → T: ×乘数、非无敌、锥外仍为 0 | V5, V6 | ✅ 全部 headless |
| **E05-S7** 锥可视化 | G: 冷白地面光斑、脉动≤2Hz、亮度差≥3:1、非实时光 → W: 守卫在场 → T: 常量满足、渲染门控 | V7, V8 | ✅ 常量 headless；🔶 真实 emissive/Tween 脉动观感见 §9-VFX |
| **E06-S1** 半径通知 | G: `emit` 经 Grid 查半径内守卫 → W: `emit` → T: 精确距离过滤、广播 `sound_emitted` 携 payload | S1, S2 | ✅ 全部 headless（含 G2 精确过滤） |
| **E06-S2** 落足声 | G: `player_step_committed` 携 `noise_radius/gait` → W: E03 发 → T: FOOTFALL payload，`radius` 不改写 | S3, S4 | ✅ 全部 headless |
| **E06-S3** 声环≤8 FIFO | G: `RING_CAP=8` FIFO → W: >8 环 → T: 存活≤8 | S5, S6 | ✅ 记账 headless；🔶 真实环 Tween 展开/淡出观感见 §9-VFX |
| **E06-S5** 距离衰减 | G: `sound_in_range=intensity×(1−dist/radius)` → W: 到达 E08 → T: 公式正确（桩） | S7, S8 | ✅ 公式 headless；🔶 与 E08 完整联调属 U1（Batch C） |

---

## 7. 烟雾测试清单（Batch B 冒烟点）

**批间冒烟点（来自 `sprint1-plan.md` §3）：B 末跑 `test_vision_cone` + `test_sound_propagation` 全绿。**

| 冒烟项 | 文件 | 期望 | 当前状态 |
| --- | --- | --- | --- |
| 视野完整 | `tests/unit/test_vision_cone.gd`（14 测试：8 Batch B + 6 Sprint 0） | 全绿（含 1 个 `add_child` 的 Sprint 0 测试，headless 可用） | ⏳ 沙箱未实跑 |
| 声音传播 | `tests/unit/test_sound_propagation.gd`（8 测试） | 全绿 | ⏳ 沙箱未实跑 |

**冒烟门控脚本**（用户在本地有 Godot 环境执行）：
```bash
godot --headless -s res://addons/gut/gut_cmdln.gd -gdir=res://tests/unit -gexit
```
判定：退出码 0 且上述两文件无 FAIL → 冒烟点达成。

---

## 8. 回归守卫（不破坏 Batch A）

Batch B 仅改动 `vision_cone.gd`（扩展）、新增 `sound_propagation.gd`；**未触碰** Batch A 的 `light_model.gd` / `step_commit.gd` / `event_bus.gd`。因此 Batch A 的以下冒烟点应不受影响：

| Batch A 守卫测试 | 文件 | 与 Batch B 关系 | 风险 |
| --- | --- | --- | --- |
| `test_light_model` | `tests/unit/test_light_model.gd` | Batch B 未改 LightModel | ✅ 无回归风险 |
| `test_step_commit` | `tests/unit/test_step_commit.gd` | Batch B 未改 StepCommit | ✅ 无回归风险（注：G1 双发为**集成**风险，非 `test_step_commit` 单测失败） |
| `test_event_bus` | `tests/unit/test_event_bus.gd` | Batch B 零信号漂移（§5 已核对） | ✅ 无回归风险 |

**注意**：Batch B 冒烟点 `test_vision_cone` 含 1 个 `add_child` 测试（Sprint 0 `test_phase_offset`），与 Batch A `test_step_commit.gd:50` 同模式——headless 可用，不引入新 harness 依赖。**不属本批的 6 个失败测试**（`test_integration_step_vision.gd`，Batch D 的 E10-S1 harness 修复）Batch B 未触碰，不影响本批判定。

---

## 9. 验证缺口清单（沙箱未实跑 + VFX 渲染路径）

### 9.1 沙箱未实跑（K1，核心 CONCERNS 来源）
- 16 个 Batch B 测试 + 6 个 Sprint 0 回归测试在 `test_vision_cone` 中，**均未在沙箱执行**（无 Godot/GUT 二进制）。
- 「全绿」目前基于：(a) 沿用绿色 Batch A 套件的 headless 模式与 GUT API；(b) 逐行静态复核 GDScript 语法与 GUT 签名（含 §4 澄清）；(c) 外部依赖存在性核对（§5）。
- **必须本地实跑确认**（见 §10）。

### 9.2 VFX 渲染路径（🔶 无法 headless 验证，需 CI/手动）
以下由 `attach_cone_vfx()` / `_spawn_ring_visual()` 实现，均门控于 `_can_render()`（`Engine.get_main_loop() != null and is_inside_tree()`），headless 不执行，**常量被断言但行为未被验证**：

| 项 | 验证内容 | 验证方式 |
| --- | --- | --- |
| 锥 VFX 脉动 | `CONE_VFX_PULSE_HZ=2.0` 真实 Tween ≤2Hz（V-02）；`emissive_intensity` 在 0.06↔0.30 间脉动 | CI `budget_assert`（E10-S2 `@ci:V-02`）+ 手动观感 |
| 锥 VFX 对比度 | `ALPHA_MAX/ALPHA_MIN=5:1`（C-03 ≥3:1）真实观感 | 手动/截图对比 |
| 锥 VFX 非实时光 | emissive quad（非 OmniLight3D，R-02） | 手动确认场景无新增实时光 |
| 环 VFX | 同心圆展开+淡出（`Tween` 自毁）、≤8 同屏（G-02）；T-04 `time_scale` 同步（凝神下变慢、绝不提速） | CI `budget_assert`（`@ci:G-02`）+ 手动 |
| 锥/环 冷白 | `#9FB8C9` 冷白、亮度/形状编码非色相（C-04/C-05） | 手动色板核对 |
| 网格几何 | `CylinderMesh` 扁平地面 patch 朝向（E09 Batch C 打磨） | 手动/后续 Batch C |

> 上述 VFX 项**不影响 Batch B 冒烟点**（冒烟点只跑逻辑测试），但属于 Sprint 1 退出标准（控制清单 V-02/C-03/G-02/R-02/T-04）的「观感确认」层，需在 CI 或手动阶段闭环。

---

## 10. 风险分级（基于工程报告 §6：G1/G2/G3/K1/U1 + 本批结论）

| 风险 | 来源 | 本批状态 | QA 结论 |
| --- | --- | --- | --- |
| **G2** 网格候选需精确距离过滤 | 报告 §6 | ✅ **已解决** — Batch B 新增 `register_guard` 注册表 + `origin.distance_to(gp)<=radius` 精确过滤；测试 S1 覆盖「20m 被排除」 | 闭合，有测试证据 |
| **G3** `vision_looming` 几何判据（无 LOS 门控） | 报告 §6 | 🟡 设计可调项 — 测试 V1–V4 覆盖几何语义；「墙后不发」为可选增强 | 非阻塞；转 design-strategist 裁决是否加 LOS 门控 |
| **G1** Batch A 双发 `sound_emitted` | 报告 §6 | 🔴 **未解决（需主理人裁决）** — `StepCommit.sound_emitted` 直发 + `SoundPropagator` 规范路径，集成后双发；单测各自隔离故未发现 | 集成风险；建议授权 Batch C 清理（移除 `step_commit.gd:78` 直发 + `sprint0_bootstrap.gd:100` 转发） |
| **K1** 知识/验证缺口 | 报告 §6 | 🔴 **未实跑** — 见 §9.1；VFX 渲染见 §9.2 | 构成 CONCERNS 主因 |
| **U1** E06-S5 ↔ E08 联调 | 报告 §6 | 🟡 明确延后 Batch C — S7/S8 为公式桩；`sound_emitted` payload 已备齐 E08 输入 | 非本批阻塞 |

**本批 QA 新增观察（非缺陷，供相关 owner）**：
- **O1（设计观察，转 design-strategist）**：`vision_looming` 仅去抖-入带触发、re-arm-离带，但**未对「玩家在带边缘高频振荡」做 ≤2Hz 频率上限**。若玩家以 >2Hz 穿越带缘，tell 信令可能 >2Hz（V-02 原意覆盖锥 VFX 脉动，tell 信号本身无频限）。建议确认是否需在 `vision_looming` 发射侧加频率闸。
- **O2（集成观察，转 engineering-lead）**：`SoundPropagator` 为 `sound_emitted` 唯一规范拥有者，但 `sprint0_bootstrap.gd` 转发仍活跃（G1），联调前须清理，否则 E08 会收到重复/缺字段事件。

---

## 11. 质量门判定（CONCERNS）

| 维度 | 结果 |
| --- | --- |
| 实现缺陷（vision_cone.gd / sound_propagation.gd） | 无发现 |
| 测试逻辑缺陷（16 个 Batch B 测试） | 无发现（含 GUT API 核对 §4） |
| headless 安全性 | ✅ 全部纯逻辑 / 渲染门控；仅 1 个 Sprint 0 `add_child` 测试，headless 可用 |
| 信号零漂移 | ✅ EventBus 声明齐全（§5） |
| 外部依赖存在性 | ✅ Grid / LightModel / EventBus 方法均存在 |
| 测试实跑 | ❌ 沙箱未跑（K1） |
| VFX 观感验证 | ❌ 无法 headless（需 CI/手动） |
| 集成风险 | 🔴 G1 双发待 Batch C 清理 |

> **判定：CONCERNS**
> - 非 FAIL：实现与测试均无已识别缺陷，不满足「代码本身有缺陷」的 FAIL 条件。
> - 非 PASS：测试未经实跑、VFX 观感未确认、G1 集成风险未闭环，无法出具「全绿/可放行」认证。
> - 解除 CONCERNS 路径：本地实跑 §10 清单全绿 + VFX 观感确认 + G1 进入 Batch C 清理计划 → 转 PASS（G1 保留为 Sprint 1 退出项跟踪）。

---

## 12. 建议工程修复项（无测试逻辑缺陷，故仅列观察与文档修正）

> 依纪律：未发现测试本身逻辑缺陷，**无需工程改动测试**。以下为文档/流程建议，非缺陷修复：

1. **文档修正（低）**：工程报告 `sprint1-batchB-engineering-report.md` §1「补全 9 个」、§7「合计 17 个」应修正为「8 个 / 16 个」（见 §2）。
2. **跟踪项（非本批）**：G1 双发清理 → 建议主理人授权 Batch C 实施（移除 `step_commit.gd:78` 直发 + `sprint0_bootstrap.gd:100` 转发）。
3. **设计裁决（转 design-strategist）**：G3（looming 是否加 LOS 门控）、O1（looming ≤2Hz 频率闸）。
4. **VFX 确认（转 E10-S2 / 手动）**：§9.2 清单在 CI `budget_assert` 与手动 playtest 闭环。

---

## 13. 本地实跑确认清单（主理人/工程最需执行的动作）

在**有 Godot 4.4 + GUT 的安装环境**执行以下命令，并确认退出码 0、无 FAIL：

```bash
# 1) Batch B 冒烟点（必须全绿）
godot --headless -s res://addons/gut/gut_cmdln.gd -gdir=res://tests/unit -gexit

# 2) 如需单文件聚焦核对
godot --headless -s res://addons/gut/gut_cmdln.gd -gdir=res://tests/unit -gtest=test_vision_cone -gexit
godot --headless -s res://addons/gut/gut_cmdln.gd -gdir=res://tests/unit -gtest=test_sound_propagation -gexit
```

**最需用户在本地实跑确认的 16 个 Batch B 测试（按优先级）**：
1. 🔴 `test_vision_looming_emitted_at_edge`（V1）— 去抖语义核心，确认 `_loom_count` 计数与 `assert_signal_emitted` 行为符合预期。
2. 🔴 `test_sound_emitted_notifies_guards_in_radius`（S1）— G2 精确距离过滤现网证据，确认 20m 守卫被排除、payload 透传 E08。
3. 🔴 `test_ring_vfx_capped_at_eight`（S5）— G-02 FIFO 上限，确认 seq 3..10 与 `is_over_ring_budget()==false`。
4. 🔴 `test_footfall_emits_sound_with_radius`（S3）— E06-S2 规范路径，确认 `radius` 不改写（与 G1 双发问题区分）。
5. ✅ 其余 12 个（V2–V8, S2, S4, S6–S8）— 纯逻辑/常量断言，静态把握高，实跑为最终确认。

**实跑后请额外人工/CI 确认（§9.2）**：锥/环 VFX 脉动 ≤2Hz、亮度差 ≥3:1、冷白非色相、`time_scale` 同步观感；G1 双发是否在集成场景出现。

---

*— 严守真 / quality-lead · Phase 5 Sprint 1 Batch B QA 评审*
