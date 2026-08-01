# Sprint 0 QA 计划 ·《灰烬之步》ASHEN STEP（Phase 5 · Sprint 0 垂直切片）

> **作者**：严守真（quality-lead / 游戏质量负责人）
> **阶段**：Phase 5 制作 · Sprint 0 垂直切片 · 棒次②（QA 计划 + 测试用例扩充）
> **范围**：E01（切片）/ E02（完整）/ E03（切片）/ E04（切片）/ E05（切片）/ E09（切片）的 QA 计划、测试用例、冒烟定义、回归基线、Bug 分级。
> **环境说明**：本环境 Bash 全线故障，无法实跑 `godot` / GUT（记为 **N2**）。全部交付物经 **Read 比对 GDD / 架构常量 + GDScript 4.4 语法审查** 确认；运行时校验（N2）为 Sprint 0 退出硬标准之一，须在可运行环境补（见 §6）。

---

## 0. 质量门判定（Preview）

| 项 | 状态 |
| --- | --- |
| 计划与测试矩阵 | ✅ 已建立（覆盖 Sprint 0 全部 Story） |
| 真实断言测试用例 | ✅ 新增 `test_light_model.gd` / `test_hud_slice.gd` / `test_integration_step_vision.gd`，并扩充 `test_step_commit.gd` / `test_vision_cone.gd` |
| 暴露阻塞项 | ⚠️ **2 项**：(a) HUD 测试需场景树 + Camera3D，本环境无法实跑；(b) GDD↔实现「表面系数」漂移（见 §6.2） |
| 运行时校验 | ⏳ N2 待可运行环境补（Sprint 0 退出硬标准⑤） |
| 建议性门控 | 本 QA 计划为 **advisory**；最终放行由主理人裁决（符合「用户始终掌舵」）。 |

---

## 1. 测试策略

**框架**：GUT（bitwes/gut，`extends GutTest`）+ `godot --headless` 跑 `tests/unit`（详见 `tests/README.md` §3）。

**分层与类型**：
| 类型 | 目录 / 文件 | 说明 |
| --- | --- | --- |
| 单元 | `tests/unit/test_step_commit.gd`、`test_vision_cone.gd`、`test_light_model.gd` | 纯逻辑断言，preload 真实类 |
| 集成 | `tests/unit/test_integration_step_vision.gd` | StepCommit→EventBus→VisionCone 词汇表贯通 |
| 表现层 | `tests/unit/test_hud_slice.gd` | HUD 需场景树 + EventBus group + Camera3D（见 §6.1） |
| 静态预算 | `tests/ci/budget_assert.gd` | control-manifest §7 断言骨架（warn-only） |

**CI 卡门**（对齐 `control-manifest.md` §7 + `tests/ci-note.md`）：
- **GUT 冒烟（阻断）**：`godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests/unit -gexit`；失败阻断合并。
- **预算静态断言（仅告警）**：`godot --headless -s res://tests/ci/budget_assert.gd -gexit`；warn-only，告警入评审记录交主理人裁决（不阻断构建）。

**验证驱动纪律**：断言数值直接引用真实代码常量（`TimeController.FOCUS_SCALE` 等）与 GDD/架构 §4 预算，不凭记忆硬编码。

---

## 2. Sprint 0 测试矩阵（逐 Story）

> 覆盖对齐 `epic-overview.md` §5「Sprint 0 进入 Story 速查」与 `production/epics/E<NN>-*.md` 的 Given/When/Then。
> 标记：✅ 已覆盖断言 ｜ ⚠️ 部分/契约级 ｜ ⏳ 待可运行环境（N2）

### 2.1 E02 · RTwP 凝神时间模型
| Story | 测试文件 · 用例 | 预期结果 | 关联 GDD / 控制 |
| --- | --- | --- | --- |
| E02-S1 凝神 0.25 | `test_step_commit::test_focus_enters_slowmo_at_0_25` | `mode==FOCUS`，`FOCUS_SCALE==0.25`，`time_scale_changed` 发射 | rtwp-time-model §2 / **T-02** / ADR-003 |
| E02-S2 信号 | 同用例（watch_signals + assert_signal_emitted）& `test_focus_exit_restores_flowing` | FLOWING↔FOCUS 切换均发 `time_scale_changed(old,new,mode)` | system-breakdown §2 / rtwp-time-model §4 |
| E02-S3 真实时间冷却 | `test_step_commit::test_commit_cooldown_uses_real_time_not_scaled` | commit 后 tick 真实 0.13s → `can_commit()==true` | ADR-003 风险4 / stealth-step-commit §2 |

### 2.2 E03 · 步进提交 / 读—步循环
| Story | 测试文件 · 用例 | 预期结果 | 关联 GDD / 控制 |
| --- | --- | --- | --- |
| E03-S1 读间隙 / 非连击 | `test_step_commit::test_non_idle_rejects_commit` + `test_commit_cooldown_uses_real_time_not_scaled` | 非 `IDLE` 状态 commit 被拒；冷却 0.12s 真实时间 | 概念 §3 红线 / stealth-step-commit §2 |
| E03-S2 步态 SNEAK/WALK | `test_step_commit::test_gait_switch_changes_noise_radius` | SNEAK+STONE=2.5 / WALK+STONE=5.0（按实现系数） | stealth-step-commit §2（见 §6.2 漂移） |
| E03-S3 落点预演 | `test_hud_slice::test_set_aim_preview_shows_and_matches_projection` | `set_aim_preview` 后预演 Control 显示且位置≈投影点 | core-hud-a11y §2 / **C-03/C-05** |
| E03-S4 落足发射 | `test_step_commit::test_commit_moves_player_to_landing_point` + `test_integration_step_vision::test_commit_emits_sound_with_landing_payload` + `::test_event_bus_wiring_carries_step_commit` | `player_step_committed`(含 from/to/surface/gait/noise_radius) 与 `sound_emitted` 均发射，并经 EventBus 贯通 | system-breakdown §2 / ADR-002 |
| E03-S5 噪声半径公式 | `test_step_commit::test_commit_noise_radius_matches_budget` + `::test_gait_switch_changes_noise_radius` | `noise_radius = 5.0 × surface × gait` | E03-S5 / **§6.2 漂移** |
| E03-S6 微光/足音/残影 | `test_integration_step_vision::test_ghost_trail_capped_at_six`（≤6）+ 落足信号（`player_step_committed`+`sound_emitted` 发射） | 残影数组长度 ≤ 6；落足事件驱动声音/视野重算 | stealth-step-commit §5 / **R-02**（微光省预算）/ MAX_GHOST=6 |

### 2.3 E04 · 掩体 / 阴影与可熄灯
| Story | 测试文件 · 用例 | 预期结果 | 关联 GDD / 控制 |
| --- | --- | --- | --- |
| E04-S1 get_light_level | `test_light_model::test_light_level_in_shadow_box_is_dark`（≈0.1）/ `::test_light_level_outside_shadow_is_bright`（≈1.0）+ `test_integration_step_vision::test_visibility_in_light_pool_is_full`（1.0）/ `::test_visibility_in_shadow_is_zero`（0.0） | 暗处≈0、光池≈1 | cover-shadow §2 / vision-cone §2 |
| E04-S2 阈值暴露 | `test_light_model::test_thresholds_exposed_as_constants` | `L_DARK==0.20`、`L_BRIGHT==0.60` | cover-shadow §2 / **E04-S2** |
| E04-S4 光状态事件契约 | ⚠️ 契约级：`EventBus.light_state_changed` 已声明（system-breakdown §2）；Sprint 0 无独立 LightState 节点，断言见静态 lint（CI） | 信号词汇存在，熄灯过场逻辑 Sprint 1 | system-breakdown §2 / cover-shadow §4 |
| E04-S7 事件驱动重算 | ⚠️ 部分：集成用例证明 `commit→sound_emitted→recompute` 词汇贯通；全 cell 重算钩子 Sprint 1 | 置脏触发局部重算（ADR-002） | ADR-002 / G-03 |

### 2.4 E05 · 视野锥
| Story | 测试文件 · 用例 | 预期结果 | 关联 GDD / 控制 |
| --- | --- | --- | --- |
| E05-S1 10Hz 错峰 | `test_vision_cone::test_cone_constants_align_to_gdd`（`TICK_HZ==10.0`）+ `::test_phase_offset_initialized_within_tick_window`（`_accum∈[0,0.1)`） | 每守卫 ≤10Hz 且错峰初始化 | ADR-002 / **G-03** / architecture §4 |
| E05-S2 可见性公式 | `test_vision_cone::test_target_in_light_pool_is_detected`（1.0）/ `::test_target_in_shadow_is_invisible`（0.0）/ `::test_target_outside_cone_is_invisible`（0.0）/ `::test_no_light_model_assumes_full_light`（1.0） | 光池必检、阴影不可见、锥外/LOS 阻断归零 | vision-cone §2 / **E04-S2** |
| E05-S3 LOS 经封装 | ⏳ N2：headless 无 world → `SpatialQueryWrapper` 容错返回可见；真实遮挡 LOS 待可运行环境（需 physics world） | LOS 仅对遮挡层（封装统一 mask） | 架构 §2 / ADR-002 / E01-S3 |
| E05-S4 vision_stimulus | ⚠️ 契约级：`VisionCone.vision_stimulus(guard_id,target,visibility)` 已声明并在 bootstrap 接线；集成用例 `watch_signals(_vc)` 验证可连接 | 每 tick 发信号（Sprint 1 E08 消费） | system-breakdown §2 / vision-cone §4 |
| E05-S7 锥 patch 可见 | ⏳ N2：可视化（半透明锥 patch）属渲染，需可运行环境人工/截图核对 | 俯视可读，亮度差 ≥3:1 | **C-03** / art-bible §8.2 |

### 2.5 E09 · 核心 HUD 与可访问性（切片）
| Story | 测试文件 · 用例 | 预期结果 | 关联 GDD / 控制 |
| --- | --- | --- | --- |
| E09-S1 凝神态 + 预演 | `test_hud_slice::test_focus_readout_updates`（凝神读出 "凝神 0.25×"）/ `::test_set_aim_preview_shows_and_matches_projection` | FOCUS 后状态读出更新、预演显示 | core-hud-a11y §2 / **C-03/C-05** |
| E09-S3 世界要素编排 | `test_hud_slice::test_suspicion_bar_updates`（vision_stimulus→可疑度条 value） | 收到 `vision_stimulus` 后可疑度条 value 更新 | core-hud-a11y §2 / patrol-ai（Sprint 1） |

### 2.6 E08 · 暴露软失败（占位，Sprint 0 stub）
| Story | 测试文件 · 用例 | 预期结果 | 关联 |
| --- | --- | --- | --- |
| E08（暴露宽限 1.2s） | `test_step_commit::test_exposure_grace_1_2s_triggers_soft_fail`（`ExposureGuardStub`，唯一保留 stub） | ALERT + 可见持续 1.2s 真实时间 → 发 `exposure_detected`（软失败） | patrol-ai §3 / consistency-review C4 |

---

## 3. 冒烟测试定义（绿灯标准）

对齐 `epic-overview.md` §3 退出标准⑤——「`tests/` GUT 冒烟在 `godot --headless` 下跑通」。

**冒烟必须包含用例集合（任意失败即红灯，阻断合并）**：

1. `test_step_commit.gd`
   - `test_commit_moves_player_to_landing_point`
   - `test_commit_noise_radius_matches_budget`
   - `test_focus_enters_slowmo_at_0_25`
   - `test_commit_cooldown_uses_real_time_not_scaled`
2. `test_vision_cone.gd`
   - `test_target_in_light_pool_is_detected`
   - `test_target_in_shadow_is_invisible`
   - `test_target_outside_cone_is_invisible`
3. `test_light_model.gd`
   - `test_thresholds_exposed_as_constants`
   - `test_light_level_in_shadow_box_is_dark`
   - `test_sensitivity_below_dark_is_zero` / `..._above_bright_is_one` / `..._linear_between_thresholds`
4. `test_hud_slice.gd`
   - `test_focus_readout_updates`
   - `test_suspicion_bar_updates`
   - （`test_set_aim_preview_*` 入冒烟，但需场景树 + Camera3D；见 §6.1）
5. `test_integration_step_vision.gd`
   - `test_commit_emits_sound_with_landing_payload`
   - `test_visibility_in_light_pool_is_full`
   - `test_ghost_trail_capped_at_six`

**绿灯标准**：上述全部 `assert_*` 通过，进程退出码 0。任一失败 → 红灯，禁止合并。

---

## 4. 回归基线（Sprint 0 锁定）

Sprint 0 锁定的断言作为后续 Sprint 回归基线（**不可在后续 Sprint 无理由削弱**）：

| 常量 / 契约 | 锁定值 | 出处 |
| --- | --- | --- |
| `TimeController.FOCUS_SCALE` | 0.25 | ADR-003 / T-02 |
| `TimeController.RAMP` | 0.15 | V-06（非硬切） |
| `TimeController.USER_MIN/MAX` | 0.1 / 1.0 | T-01/T-02 |
| `StepCommit.COMMIT_COOLDOWN_RT` | 0.12（真实时间） | E03-S1 / ADR-003 |
| `StepCommit.NOISE_BASE` | 5.0 | E03-S5 |
| `StepCommit.GAIT_FACTOR` | SNEAK 0.5 / WALK 1.0 | stealth-step-commit §2（⚠️ 见 §6.2 漂移） |
| `StepCommit.MAX_GHOST` | 6 | E03-S6 |
| `LightModel.L_DARK / L_BRIGHT` | 0.20 / 0.60 | E04-S2 |
| `LightModel` 暗/亮返回 | 0.1 / 1.0 | cover-shadow §2 |
| `VisionCone.HALF_ANGLE_DEG / RANGE / TICK_HZ` | 35.0 / 14.0 / 10.0 | vision-cone §2 / G-03 / ADR-002 |
| `SpatialHashGrid3D.CELL` | 14.0 | ADR-002 |
| EventBus 信号词汇 | §2 全信号 | system-breakdown §2 |

> 后续 Sprint 若需变更任一锁定值，须走主理人裁决 + 同步更新 GDD/架构 + 本回归基线表（防止静默漂移）。

---

## 5. Bug 分级 Rubric

对齐 `control-manifest.md` 硬约束与 `architecture.md` §4 预算。质量门为 **advisory**，但分级决定处理优先级与主理人裁决必要性。

### P0 — 阻断合并（硬约束违反，CI 必须告警并交主理人裁决）
| 触发 | 约束号 | 说明 |
| --- | --- | --- |
| 同屏动态点光（OmniLight3D/SpotLight3D）> 32 | **R-02** | 光 LOD 纪律破上限 |
| 体积雾 `volumetric_fog_density` base > 0.05 | **R-04** | 雾预算破上限 |
| 熄灯雾 ramp > 0.12 或持续 > 0.4s | **R-05** | 过场超限 |
| 锥体重算 > 10Hz/守卫 | **G-03** | 节流违反（成本随帧率爆炸） |
| 同屏声环实例 > 8 | **G-02** | 声环 FIFO 破上限 |
| 暴露/锥缘脉动 shader 频率 > 2Hz | **V-02** | 光敏风险 |
| 频闪 > 3Hz 亮灭 | **V-01** | 光敏硬禁 |

### P1 — 阻断（可访问性硬约束；CI 告警 → 主理人裁决）
| 触发 | 约束号 | 说明 |
| --- | --- | --- |
| UI 对比度 < 4.5:1 / 关键指示 < 7:1 / 世界要素 < 3:1 | **C-01/C-02/C-03** | WCAG 不达标 |
| 危险提示 `#7A2E2E` 单独使用 | **C-07** | 必配形状/脉动/图标 |
| 机制信息仅靠单一色相 | **C-04/C-05** | 色盲安全 |
| 色盲模式缺失 | **C-06** | 暴露色映射 |
| 屏震默认开 / 动态模糊默认开 | **V-03/V-05** | 眩晕防护默认关 |
| 转场硬切闪光 | **V-06** | ease 非硬切 |

### P2 — Sprint 内缺陷（数值/契约漂移，须修）
| 触发 | 说明 |
| --- | --- |
| GDD↔实现数值不符（如 §6.2 表面系数漂移） | 规格不一致 |
| 信号未声明（违反 system-breakdown §2 词汇表） | consistency-review §1.3 闭合性 |
| 残影 > 6 / 噪声半径公式偏差 | 预算/手感破坏 |

### P3 — 建议/优化（不阻塞）
测试稳定化（去 flaky）、命名规范、断言注释、覆盖率提升。

---

## 6. 已知限制 / 暴露阻塞项

### 6.1 HUD 测试需场景树 + Camera3D（N2 表现层）
- `test_hud_slice.gd` 依赖：(a) `EventBus` 经 `add_child` 入树并注册 group `"event_bus"`；(b) `HudSlice` 经 `add_child` 触发 `_ready` 连接信号；(c) `set_aim_preview` 需 `Viewport.get_camera_3d()` 返回有效 `Camera3D` 才能 unproject。
- 本环境无法实跑（N2），正确性经 **Read 比对 `hud_slice.gd` 源码逻辑 + GDScript 语法审查** 确认。
- 在可运行环境首次运行时，需核对：(1) headless 下 `get_camera_3d()` 是否返回有效相机（必要时在测试内 `add_child(Camera3D, current=true)`）；(2) `unproject_position` 在 0 尺寸 viewport 下的有限性（测试已加 NaN 守卫，有限时再比对投影位置）。
- **不阻塞** Sprint 0 退出（退出标准④仅要求「基础 HUD 显示」，运行时人工核对即可）；但建议 Sprint 1 前固化 HUD 测试 harness。

### 6.2 GDD↔实现「表面系数」漂移（P2，待工程裁决）
- **GDD E03-S5**（权威规格）：`surface_factor：STONE 1.2 / WOOD 1.0 / MOSS 0.5`；示例 `SNEAK+STONE=3.0`、`WALK+WOOD=5.0`、`RUN+STONE=12.0`。
- **实现** `step_commit.gd::SURFACE_FACTOR`：`{STONE: 1.0, GRASS: 0.7, METAL: 1.2}` —— **表面分类不同（STONE/GRASS/METAL vs STONE/WOOD/MOSS）且 STONE 值不同（1.0 vs 1.2）**。
- **QA 处理**：测试锁定**已实现代码**（保证 Sprint 0 冒烟绿灯、作为回归基线），即 `SNEAK+STONE=5.0×1.0×0.5=2.5`、`WALK+STONE=5.0`。同时在 §4 回归基线标注此漂移，并**提请工程（jiyan）裁决**：统一 GDD 与实现（建议实现改回 GDD 的 STONE/WOOD/MOSS 分类与 1.2/1.0/0.5 值，或反之在 GDD 落版实现分类），并在裁决后回填对应测试常量。
- 该漂移 **不阻断** 本次冒烟；列为 P2 Sprint 内修。

### 6.3 LOS / 可视化待可运行环境（N2）
- `VisionCone` 真实遮挡 LOS（E05-S3）需 physics world；`SpatialQueryWrapper` 在 headless 无 world 时容错返回可见，故单元测试仅覆盖「无遮挡=可见」与安全容错，**真实遮挡 LOS 与锥 patch 可视化（E05-S7/C-03）须 N2 后补**。

---

## 7. 交付物清单

| # | 文件（绝对路径） | 类型 | 说明 |
| --- | --- | --- | --- |
| 1 | `tests/qa/sprint0-qa-plan.md` | 文档 | 本 QA 计划（策略/矩阵/冒烟/回归/Bug rubric/限制） |
| 2 | `tests/unit/test_light_model.gd` | 新增 | LightModel 阈值 + 光影敏感度断言 |
| 3 | `tests/unit/test_hud_slice.gd` | 新增 | HUD 凝神读出 / 可疑度条 / 落点预演（需树） |
| 4 | `tests/unit/test_integration_step_vision.gd` | 新增 | StepCommit→EventBus→VisionCone 集成贯通 |
| 5 | `tests/unit/test_step_commit.gd` | 扩充 | 增 `test_non_idle_rejects_commit` / `test_gait_switch_changes_noise_radius` / `test_commit_emits_both_signals_with_payload`（保留既有断言） |
| 6 | `tests/unit/test_vision_cone.gd` | 扩充 | 增常量对齐 / 错峰初始化 / 无光模型兜底（保留既有断言） |
| 7 | `tests/README.md` | 更新 | §5 测试缺口表：Sprint 0 范围内闭合，开放缺口标注归属 Epic |
| 8 | `tests/ci/budget_assert.gd` | 更新 | Sprint 0 退出标准⑤冒烟检查骨架（warn-only，可被 CI 调用） |

---

*QA 计划 v1.0（Sprint 0）。advisory 门控；运行时校验 N2 待可运行环境补。*
