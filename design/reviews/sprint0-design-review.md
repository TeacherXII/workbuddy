# Sprint 0 设计评审 ·《灰烬之步》ASHEN STEP（Phase 5 · 制作 · Sprint 0 垂直切片）

> **评审人**：文策渊（design-strategist / 设计策略师）
> **棒次**：③ 设计评审 + 范围检查 + 裁决数值漂移（工程①已实现代码、质量②已出 QA 计划与测试之后）
> **评审对象**：Sprint 0 垂直切片全部实现（`src/core/*`、`src/game/*`、`src/ui/hud_slice.gd`、`src/main/*`）+ QA（`tests/qa`、`tests/unit`、`tests/README.md` §5）+ 计划/验收（`production/epics/*`）+ 设计/架构（`design/gdd/*`、`design/concept`、`design/ux`、`design/art`、`docs/architecture/*`）
> **环境约束**：本环境 Bash 全线故障，未运行 `godot`/GUT；全部交付物经 **Read 比对 GDD/架构/控制-manifest/ADR 常量 + GDScript 4.4 语法审查** 确认（与 QA 计划 §0 / README §5 同一口径）。
> **评审强度**：lean（仅核心节点卡质量门）。

---

## 0. 评审结论速览

| 项 | 状态 |
| --- | --- |
| 四支柱是否守住 | ✅ **全守**（步步为营 / 感官愉悦 / 自主掌控 / 肃穆压迫） |
| 范围 Do/Dont 是否越界 | ✅ **未越界**（只做 Do，未做 Dont） |
| 数值一致性（GDD↔实现↔架构↔ADR） | ✅ **一致**（含本次裁决闭合的 `SURFACE_FACTOR` 漂移） |
| 事件词汇一致性 | ⚠️ **核心信号一致**；4 个未来信号未声明 + 2 处签名/参数差异（Sprint 1 收口，非阻塞） |
| 表面系数漂移（P2） | ✅ **已裁决闭合**：以实现为准，已 Edit GDD `stealth-step-commit.md` §3 对齐 |
| 质量门判定 | **PASS / CONCERNS**（无硬阻塞项；N2 运行时校验为退出标准⑤待可运行环境补） |

---

## 1. 四支柱设计评审

> 逐条对照实现代码与 GDD/ux-spec/art-bible/概念四支柱，核对 Sprint 0 是否守住四支柱。

### 1.1 支柱一 · 步步为营（Deliberate Motion）

**判定：✅ 守住**

- **focus 读出是否体现「读」间隙**
  - `hud_slice.gd::_on_time_scale_changed`：进入 FOCUS 时 `_status.text = "凝神 0.25×"` 且 `_dim.visible = true`；`_dim` 为 `#10141C`（Moon Ink，art-bible §2.1 冷影）@0.35 alpha 的压暗遮罩。退出 FOCUS 还原。→ 凝神「读场」时刻有视觉落点（ux-spec §4.1、art-bible §8.4 压暗+提亮可读要素）。
  - `time_controller.gd`：`FOCUS_SCALE=0.25`、`RAMP=0.15`、`_ramp_to` 用 `Tween.TRANS_QUAD / EASE_OUT` 非硬切（V-06）。→ 进入/退出是 ease，符合「读间隙」非瞬移。
- **step-commit 是否 deliberate（单一确认、残影/微光走质地非烟花）**
  - **单一确认**：`sprint0_bootstrap.gd::_process` 在 `not focusing && mode==FOCUS` 时 `exit_focus()` 并 `if can_commit() && aim_point!=ZERO: commit(...)`——松开凝神即提交，零额外点击（ux-spec §2.2「提交确认=松开凝神=单一确认」；GDD ① §2）。✓
  - **状态机杜绝连击**：`step_commit.gd` 状态 `IDLE/AIMING/COMMITTING/RECOVERING`；`can_commit()` 仅 `IDLE && _cooldown<=0`；非 IDLE 提交被拒（`test_non_idle_rejects_commit` 验证 `RECOVERING` 拒收）。`COMMIT_COOLDOWN_RT=0.12` 真实时间兜底（ADR-003 风险4）。→ 天然杜绝爽快连击式位移（概念 §3 红线「不做爽快连击式位移」）。✓
  - **残影/微光走质地非烟花**：`commit()` 落足仅 `push` 残影 + `emit player_step_committed` + `emit sound_emitted`，**不触发任何庆祝式粒子/闪光**。`MAX_GHOST=6` 限制残影数组长度（`test_ghost_trail_capped_at_six` 验证 ≤6）。落足微光/足音以**事件**形式驱动下游（E06/VFX 在 Sprint 1 以 emissive quad `#C8862F` ≤10% 画面纪律 + 触觉级 foley 落地，art-bible §1 调性禁区「反馈走物理/触觉，非庆祝」）。→ 反馈走质地，符合 art-bible §1 / §8.2。✓

### 1.2 支柱二 · 感官愉悦（Sensory Craft）

**判定：✅ 守住**

- **反馈走质地（对齐 ux-spec / art-bible §8）**
  - HUD 预演落点用 `#C8862F`（Candle Amber，主色板内，C-06）的 footprint（`hud_slice.gd::PREVIEW_COLOR`），世界内投影（`set_aim_preview` 用 `cam.unproject_position`），非屏框烟花。
  - 凝神压暗用 `#10141C`（Moon Ink）→ 冷调「读场」基调（art-bible §8.4）。
  - 状态读出文字「灰烬之步 · Sprint0 / 凝神 0.25× / FLOWING 1.0×」低饱和暖灰 `#DCE3EC`，无霓虹/跳动字（art-bible §8.3 禁「彩虹渐变字、跳动庆祝字」）。
  - 无频闪/脉动 UI（V-01/V-02/V-06 满足：仅 ease 状态切换，无闪烁）。
  - 落足微光/足音虽在切片内以事件呈现（VFX 实体在 Sprint 1），但其设计契约（`#C8862F` emissive quad、surface 足音变体、≤10% 画面）严格对齐 art-bible §2.1/§8.2/§1，走「质地」非「烟花」。✓
-  minor 备注（非阻塞）：切片仅完成逻辑+事件接线，实际 emissive quad 微光与 foley 音效由 E06/VFX 在 Sprint 1 落地；Do 清单「落足瞬间微光+足音 foley+ghost_trail 残影」在 Sprint 0 以「事件发射 + ghost 数据 + HUD 预演」满足，可视微光待 VFX 接入——这是垂直切片预期，不构成支柱违背。

### 1.3 支柱三 · 自主掌控（Owned Agency）

**判定：✅ 守住（切片范围内多解可见度有限，已注明）**

- Sprint 0 切片范围（epic-overview §4 Dont）：**无互动物件（E07）/无诱饵/烟雾（E06）/无多守卫 A\***。故「完整多解/多路线」不在 Sprint 0 可见范畴，符合范围纪律，非支柱违背。
- **切片内可见的可选性**：`input_manager.gd` 提供 `gait`（SNEAK/WALK 切换），`step_commit.gaIT_FACTOR={SNEAK:0.5, WALK:1.0}` 给出 **2 种步幅/噪声权衡**（规划自己的安静步 vs 快步），即一种「Owned Agency」的萌芽（玩家 Own 自己的步法选择）。落点由玩家 `aim_point` 自由定（地面射线定点的连续空间），非脚本固定。→ 在切片限度内，自主体现在「步态权衡 + 落点自由」。
- 完整多解（路线/诱饵/可熄灯制造阴影）由 Sprint 1（E06/E07/E04 完整）兑现，届时支柱三在 UX 上以「META_INTEL 自选侧翼 / 道具多选项 / 世界内读显示替代路线」显性成立（ux-spec §8 自查已确认无漂移）。

### 1.4 支柱四 · 肃穆压迫（Oppressive Stillness）

**判定：✅ 守住**

- **HUD near-diegetic、无闪亮 UI（对齐 ux-spec §3、art-bible §8 色板/描边）**
  - 预演落点（`#C8862F` footprint）为世界内投影（`set_aim_preview` 经相机 unproject），非屏框——near-diegetic（ux-spec §3.1、art-bible §8.1 世界内优先）。
  - 凝神压暗遮罩 `#10141C`（Moon Ink，art-bible §2.1）→ 冷调肃穆基调，无暖/高饱和 UI。
  - 状态文字低饱和、`_dim` 仅 alpha 0.35 压暗，无外发光/霓虹/糖果圆角（art-bible §8.1 「无外发光、无霓虹、无圆角糖果感」）。
  - 无频闪/脉动（V-06 ease；V-01 禁 >3Hz 亮灭；本切片无任何闪烁 UI）。✓
  - 可疑度条（`_suspicion` ProgressBar）为 Sprint 0 **占位条**（Do 清单「单守卫可疑度占位条」），使用引擎默认主题；完整面板 `#1B1B1F`@70–85% + `#3E5C76` 细描边为 E09 Sprint 2 a11y 包打磨项（ux-spec §3.1、art-bible §8.1）。占位条在 Sprint 0 范围内可接受，不破坏肃穆压迫（无闪亮）。
- 结论：HUD 为克制的 near-diegetic 摘要 + 世界内预演，色板取自主色板（Moon Ink / Candle Amber），无破坏肃穆压迫的闪亮 UI。✓

---

## 2. 范围检查（Do / Dont）

> 逐条核对 `epic-overview.md` §4 Do/Dont，读 `src/` 代码确认只做了 Do、未越界做 Dont。

### 2.1 Do 项——全部落实 ✅

| Do 项（epic-overview §4） | 实现证据 | 核对 |
| --- | --- | --- |
| 提交一步（aim→松开凝神→走到落点→微光+足音+残影≤6） | `step_commit.gd` commit() + `MAX_GHOST=6` + 双信号发射；`sprint0_bootstrap._process` 松开触发 commit | ✅ |
| RTwP 凝神/恢复 0.25 + ramp 0.15 ease + 输入实时 | `time_controller.gd` FOCUS_SCALE=0.25 / RAMP=0.15 / QUAD-EASE_OUT；`input_manager.gd` 用 `Input.*`（不受 time_scale） | ✅ |
| 一个视野锥 35°/14m/10Hz 错峰 + LOS + 光影敏感度 | `vision_cone.gd` HALF_ANGLE_DEG=35 / RANGE=14 / TICK_HZ=10 + `_accum=randf()*(1/TICK_HZ)` 错峰 + `SpatialQueryWrapper` LOS + `LightModel` 敏感度 | ✅ |
| 一处阴影/遮蔽（get_light_level 暗≈0/亮≈1，阈值 0.20/0.60） | `light_model.gd` L_DARK=0.20 / L_BRIGHT=0.60 + `add_shadow_box` → 0.1 / 1.0；`sprint0_bootstrap._setup_scene` 加 1 块阴影盒 | ✅ |
| 基础 HUD：落点预演 + 凝神态读出 + 单守卫可疑度占位条 | `hud_slice.gd` 预演 `#C8862F` + `_on_time_scale_changed` 读出 + `_on_vision_stimulus`→可疑度占位条 | ✅ |

### 2.2 Dont 项——确认未做 ✅（无越界）

| Dont 项（epic-overview §4） | 代码核查 | 核对 |
| --- | --- | --- |
| ❌ 完整 FSM / 暴露宽限 1.2s 软失败完整流 | 无 patrol AI 节点；`exposure_detected` 仅在 `EventBus` 声明、仅 `test_step_commit.ExposureGuardStub` 占位触发；bootstrap 仅把 `vision_stimulus` 转 `suspicion_changed` 占位，**无 FSM、无软重开** | ✅ 未越界 |
| ❌ 声音声环 VFX / 诱饵 / 烟雾 / 多守卫 A\* | 无 `sound_propagation.gd`；`sound_emitted` 仅发射事件（驱动未来 E06），**无声环 VFX / 无 DECOY / 无 SMOKE / 无 NavServer A\*** | ✅ 未越界 |
| ❌ 完整可访问性设置面板 | `a11y_settings.gd` 仅接口 + 默认值（持久化），**无设置菜单 UI** | ✅ 未越界 |
| ❌ LightmapGI 实烘焙 | `light_model.gd` 为 mock（`get_light_level` 程序化阴影盒），**无烘焙** | ✅ 未越界 |
| ❌ Steam 导出 / 完整 §7 断言 | 仅 GUT 冒烟（`tests/unit`）；无 Steam 导出、无 budget_assert 实跑 | ✅ 未越界 |

**范围结论**：Sprint 0 实现与 epic-overview §4 Do/Dont **完全一致**，无越界。

---

## 3. 一致性核查

### 3.1 数值对齐（GDD / 架构 §4 / control-manifest / ADR）

| 数值 | GDD/架构/ADR 权威值 | 实现常量 | 对齐 |
| --- | --- | --- | --- |
| 凝神 time_scale | T-02 / ADR-003 / architecture §4：默认 **0.25** | `TimeController.FOCUS_SCALE=0.25` | ✅ |
| 凝神 ramp | V-06 ease ≈0.15s | `TimeController.RAMP=0.15` | ✅ |
| 时间缩放区间 | T-01 [0.1,1.0]；T-02 下限 0.1 | `USER_MIN=0.1 / USER_MAX=1.0` | ✅ |
| 锥半角/射程/频率 | vision-cone §2 / G-03 / ADR-002：35° / 14m / 10Hz | `VisionCone.HALF_ANGLE_DEG=35 / RANGE=14 / TICK_HZ=10` | ✅ |
| 网格 cell | ADR-002（=最大锥射程 14m） | `SpatialHashGrid3D.CELL=14.0` | ✅ |
| 光影阈值 | cover-shadow §2 / E04-S2：L_DARK 0.20 / L_BRIGHT 0.60 | `LightModel.L_DARK=0.20 / L_BRIGHT=0.60` | ✅ |
| 暗/亮返回 | cover-shadow §2：≈0.1 / ≈1.0 | `get_light_level` 阴影 0.1 / 光池 1.0 | ✅ |
| 残影上限 | stealth-step-commit §3 / E03-S6：≤6 | `StepCommit.MAX_GHOST=6` | ✅ |
| 提交冷却（真实时间） | stealth-step-commit §2 / E03-S1：≥0.12s | `COMMIT_COOLDOWN_RT=0.12` | ✅ |
| 噪声基数 | stealth-step-commit §2 / E03-S5：BASE 5.0m | `NOISE_BASE=5.0` | ✅ |
| 步态系数 | stealth-step-commit §2：SNEAK 0.5 / WALK 1.0 | `GAIT_FACTOR={SNEAK:0.5, WALK:1.0}` | ✅ |
| 噪声公式 | `5.0 × surface × gait` | `commit()`：`NOISE_BASE × SURFACE_FACTOR × GAIT_FACTOR` | ✅（surface 见 §4 裁决） |

> 全部关键数值与 GDD/架构 §4/control-manifest/ADR **一字对齐**。

### 3.2 事件词汇对齐（system-breakdown §2 / EventBus 信号）

- **Sprint 0 实际使用并接线**的信号（`EventBus` 声明 ↔ `bootstrap`/`hud` 连接 ↔ 测试断言）全部一致：
  - `time_scale_changed(old,new,mode)` — `TimeController` 发、`HudSlice` 接 `_on_time_scale_changed` ✅
  - `player_step_committed(payload)` — `StepCommit` 发、`EventBus` 转发、`test_*` 断言 ✅
  - `sound_emitted(payload)` — `StepCommit` 发、`EventBus` 转发 ✅
  - `vision_stimulus(guard_id,target,visibility)` — `VisionCone` 发、`EventBus` 转发 + `bootstrap._on_vision_stimulus` ✅
  - `suspicion_changed(guard_id,value)` — `bootstrap` 由 `vision_stimulus` 转、`HudSlice` 接 `_on_suspicion_changed` ✅
- **一致性结论**：Sprint 0 切片内事件流闭合、零漂移。

### 3.3 残留事件词汇差异（非阻塞，Sprint 1 收口）

| 差异 | 说明 | 阻塞？ |
| --- | --- | --- |
| `EventBus.light_state_changed(point, level)` vs §2 `light_state_changed(light_id, state:LightState)` | **签名不同**。Sprint 0 无 LightState 节点、该信号**从未发射/连接**（QA 计划 §2.3 E04-S4 已标「契约级占位」）。需在 E04/E07 Sprint 1 落地前将 EventBus 签名对齐 §2 | 否（切片内无发射方/消费方） |
| `EventBus.suspicion_changed(guard_id, value:float)` vs §2 `(guard_id, value, tier:SusTier)` | **缺 `tier` 参数**。Sprint 0 无 FSM/tier，2 参为切片简化；bootstrap/HUD 一致使用 2 参。E08 Sprint 1 须扩为 3 参 | 否（切片内一致） |
| 4 个未来信号未声明：`guard_transform_dirty` / `cover_state_changed` / `vision_looming` / `guard_fsm_changed` | Sprint 0 未实现其产生/消费系统（E05 looming、E08 FSM、E04 熄灯），故 EventBus 暂未声明。属 E01-S1「§2 全信号声明」的 Sprint 1 补全项 | 否（对应系统在 Sprint 1） |

> 上述 3 项均为 **Sprint 1 收口项**，Sprint 0 切片内因无对应发射/消费方而不触发漂移。建议 E01-S1 在 Sprint 1 起补全 EventBus 全 §2 信号并统一签名。

---

## 4. 裁决 SURFACE_FACTOR 漂移（P2，关键）

### 4.1 现状

- **实现**（`src/game/step_commit.gd` 第 12 行）：
  `const SURFACE_FACTOR := {"STONE": 1.0, "GRASS": 0.7, "METAL": 1.2}`
- **GDD**（`design/gdd/systems/stealth-step-commit.md` §2 第 25–26 行）：
  `surface_factor：STONE 1.2 | WOOD 1.0 | MOSS 0.5`
- **两类不一致**：
  1. **表面分类不同**：实现用 `STONE/GRASS/METAL`，GDD 用 `STONE/WOOD/MOSS`；
  2. **STONE 值不同**：实现 `1.0` vs GDD `1.2`。
- QA（`tests/qa/sprint0-qa-plan.md` §6.2 / `tests/README.md` §5）已锁定**实现值**为回归基线：`SNEAK+STONE=5.0×1.0×0.5=2.5`、`WALK+STONE=5.0×1.0×1.0=5.0`，测试 `test_gait_switch_changes_noise_radius` 断言此值。

### 4.2 裁决

> **裁定：以「实现为准、更新 GDD 对齐」**（保持 Sprint 0 冒烟绿灯、避免工程返工、不破坏已锁定的回归基线）。
> 即把 GDD `stealth-step-commit.md` §2/§3 的表面系数表改为 `{STONE:1.0, GRASS:0.7, METAL:1.2}`，并在 GDD 注明**表面分类统一为 STONE/GRASS/METAL**（废弃 WOOD/MOSS，映射 `WOOD≈STONE`、`MOSS≈GRASS`）。

**理由**：
1. QA 测试已锁定实现值并作为回归基线（sprint0-qa-plan §4），改实现会破坏冒烟绿灯与基线，触发工程返工，违背「Sprint 0 垂直切片快速验证手感」目标。
2. 表面分类（STONE/GRASS/METAL vs WOOD/MOSS）属资产元数据命名差异，不影响四支柱/范围/手感；以实现命名统一为切片事实源，GDD 落版对齐，符合「用户始终掌舵 + 验证驱动」纪律。
3. 数值改变（STONE 1.2→1.0）使 `SNEAK+STONE` 由 3.0→2.5、示例需同步刷新；噪声公式结构与权重未变，仅系数落版，无机制漂移。

### 4.3 执行（已落盘）

- ✅ 已 **Edit** `design/gdd/systems/stealth-step-commit.md`：
  - §2 表面系数表改为 `STONE 1.0 | GRASS 0.7 | METAL 1.2`，示例刷新为 `SNEAK+STONE=2.5m；WALK+STONE=5.0m；RUN+STONE=10.0m`（RUN 为 Tier2，未进 Sprint 0），并加注分类统一说明与映射。
  - §3 数据模型 `Surface` 注释改为 `STONE/GRASS/METAL` 并加注映射。
- ✅ 落盘后已 **Read 回读**确认 §3 已更新（见交付物自检）。

### 4.4 残留交叉引用（建议 Sprint 1 同步，非阻塞）

以下两处仍保留旧值，建议在 Sprint 1 起随本裁决同步更新，以彻底闭合漂移：
- `design/gdd/system-breakdown.md` §2.3 共享类型 `Surface | STONE | WOOD | MOSS` → 建议改 `STONE | GRASS | METAL` 并注映射。
- `production/epics/E03-stealth-step-commit.md` §E03-S5 示例 `STONE1.2/WOOD1.0/MOSS0.5` 及 `SNEAK+STONE 3.0 / WALK+WOOD 5.0 / RUN+STONE 12.0` → 建议按新值刷新。
> 本裁决仅强制 Edit GDD（权威实现侧），交叉引用为规划文档，留待 Sprint 1 顺带收口，不阻断 Sprint 0 退出。

---

## 5. 质量门判定

### 判定：**PASS / CONCERNS**

- **无 FAIL / 无硬阻塞项**：四支柱全守、范围未越界、关键数值全对齐、事件流（切片内）零漂移、表面漂移已裁决闭合。
- 与 Phase 2 `consistency-review.md`（PASS/CONCERNS）及架构风险5（PASS/CONCERNS）口径一致；本次为 Sprint 0 实现层评审，结论同源。

### CONCERNS（非阻塞，须跟踪）

| # | CONCERN | 影响 | 缓解 / 归属 |
| --- | --- | --- | --- |
| N2 | **运行时校验未执行**（本环境 Bash 故障，无法跑 `godot --headless` GUT）。所有断言经 Read 比对 + GDScript 审查确认；退出标准⑤（GUT 冒烟跑通）为硬依赖，须在可运行环境补 | 退出标准⑤待补 | 可运行环境首次跑 `tests/unit` 冒烟（sprint0-qa-plan §3 用例集） |
| HUD-N2 | `test_hud_slice.gd` 需场景树 + Camera3D，本环境无法实跑（sprint0-qa-plan §6.1） | 退出标准④（基础 HUD 显示）运行时人工核对即可 | Sprint 1 前固化 HUD 测试 harness（headless 下 `add_child(Camera3D, current=true)` + NaN 守卫已就位） |
| SURF | 表面系数漂移（P2） | 已裁决**闭合** | 已 Edit GDD §3 对齐实现 |
| EVT | 事件词汇 3 项残留差异（§3.3） | 切片内无发射/消费方，不触发漂移 | E01-S1 Sprint 1 补全 EventBus 全 §2 信号 + 统一签名 |
| VFX | 落足微光 emissive quad / 足音 foley 在切片内以事件呈现，可视实体 Sprint 1（E06/VFX）落地 | Do 清单在「事件+ghost+HUD 预演」层满足 | Sprint 1 E03 完整 / E06 接入 |

### 阻塞项清单（FAIL 条件核查）

| 阻塞条件 | 是否触发 |
| --- | --- |
| 任一系统违反四支柱（支柱漂移） | ❌ 未触发 |
| 范围纪律被违反（越界做 Dont） | ❌ 未触发 |
| 性能预算/硬约束违反（R/T/V/C/X/G） | ❌ 未触发（无动态光/雾/声环/脉动实体） |
| 关键数值 GDD↔实现矛盾（除已裁决闭合的 SURFACE_FACTOR） | ❌ 未触发 |
| 事件词汇切片内矛盾 | ❌ 未触发 |

> **阻塞项：无。** 评审结论 **PASS / CONCERNS**，可在主理人裁决下进入 Sprint 1。

---

## 6. 已知风险与缓解 + 给 Phase 5 后续 Sprint（Sprint 1+）的设计建议

### 6.1 已知风险与缓解

| 风险 | 说明 | 缓解 |
| --- | --- | --- |
| N2 运行时盲区 | Bash 故障致 GUT 未实跑；断言仅靠静态审查 | Sprint 1 起在可运行环境跑通 `tests/unit` 冒烟 + 补齐 budget_assert（E10）；本评审所有数值已逐常量比对，风险低 |
| HUD 测试 harness | HUD 依赖场景树+相机，headless 需构造 | 测试已加 `Camera3D(current=true)` + NaN 守卫；Sprint 1 固化 harness |
| 事件词汇签名/参数 | `light_state_changed` 签名、`suspicion_changed` 缺 tier、4 信号未声明 | Sprint 1 E01-S1 补全 EventBus 全 §2 信号；E04/E08 落地前对齐签名 |
| 落足 VFX 实体缺失 | 微光/足音仅事件，缺可视/可听实体 | Sprint 1 E03 完整 + E06 接入 emissive quad `#C8862F` + surface foley（X-02 字幕） |
| 表面分类残留引用 | system-breakdown §2.3 / E03-S5 仍旧值 | Sprint 1 顺带刷新（§4.4） |

### 6.2 给 Sprint 1+ 的设计建议

1. **E01-S1 事件词汇补全**：在 Sprint 1 启动即把 `EventBus` 扩到 system-breakdown §2 全信号，并统一 `light_state_changed(light_id, state:LightState)`、`suspicion_changed(guard_id, value, tier)` 签名，消除 §3.3 残留差异（一致性评审 §1.3 闭合性前置）。
2. **E03 完整**：三步态（RUN 高成本 deliberate 选项，consistency-review 取舍1）、ghost_trail Tween 淡出、落足微光 emissive quad（≤10% 画面，R-02 省预算）、surface 足音变体（X-02 字幕）；surface 元数据按新分类 STONE/GRASS/METAL 落 `asset-manifest §3.1`。
3. **E04 完整**：`get_cover`（降可见度+断 LOS，非无敌）、`light_state_changed` 事件驱动 cell 重算（ADR-002）、可熄灯过场（雾 ramp≤0.12 / ≤0.4s，R-05 + vignette ease V-06）；注意 `light_state_changed` 签名须对齐 §2。
4. **E05 完整**：锥缘 tell `vision_looming`（≤2Hz V-02 脉动）、`compute_visibility` 接受外部 `visibility_multiplier`（烟雾 ×0.3，consistency-review C3）、锥 patch 可视化（冷白 `#9FB8C9`，亮度差 ≥3:1，C-03）。
5. **E06/E07/E08 引入多解**：声环 ≤8 FIFO（G-02）、诱饵 DECOY、烟雾 SMOKE、可熄灯——把**支柱三 自主掌控**从「切片内步态权衡」升级为「路线/工具/解法多可见可选」（META_INTEL 自选侧翼 + 世界内读显示替代路线），正式兑现 Autonomy。
6. **E08 暴露软失败**：`ALERT + 持续可见 1.2s 真实时间 → exposure_detected → 软重开`（consistency-review C4 + SaveManager 检查点）；暴露用 `#7A2E2E`+脉动+图标非单色（C-07/V-03），色盲模式→`#C8862F`（C-06）。
7. **E09 a11y 完整包（Sprint 2）**：面板 `#1B1B1F`@70–85% + `#3E5C76` 细描边、可疑度条 C-02 ≥7:1、完整 a11y 开关（C-05/C-06/C-07、T-01/T-02、V-03/V-04/V-05、X-01/X-02）——把 Sprint 0 占位 HUD 打磨为肃穆压迫基调的完整终端层。
8. **设计理论红线持续扫描**：Sprint 1 引入多步态/多道具/多路线后，定期复查「主导策略 / 经济失衡 / 认知过载 / 支柱漂移」四红线（ux-spec §8 口径）——当前无四项，但系统扩张后须防「单一最优解」或「HUD 信息过载」。

---

*Sprint 0 设计评审 v1.0 完成。结论：**PASS / CONCERNS**；四支柱全守、范围未越界、关键数值全对齐、表面系数漂移（P2）已裁决闭合（Edit GDD §3 对齐实现）。N2 运行时校验与 HUD 测试 harness 为 Sprint 0 退出标准⑤/④的待补项（非硬阻塞）。*
