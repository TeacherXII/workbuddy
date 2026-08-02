# Sprint 1 · Batch B 设计评审（Design Gate Review）—《灰烬之步》ASHEN STEP

| 字段 | 值 |
| --- | --- |
| **评审人** | 文策渊（design-strategist / 策划负责人） |
| **批次** | Phase 5 · Sprint 1 · **Batch B**（视野锥完整 + 声音传播） |
| **评审维度** | **仅设计 / 策划维度**（四支柱、范围纪律、控制清单、事件词汇、数值锚、设计理论红线）。不涉源码改动、不 git commit、不越权 QA/测试评审（测试执行与全绿判定归 quality-lead）。 |
| **评审依据** | `design/gdd/system-breakdown.md` §2（13 信号词汇表）/ §5（四支柱映射）；`docs/architecture/control-manifest.md` §7（R/T/V/C/X/G 硬约束）；`design/reviews/sprint1-design-scope.md`（Do/Dont + 数值锚 + 缺口 G1–G8）；`production/sprints/sprint1-plan.md` §2（Do/Dont）、§6（裁决 D1–D4）；`production/sprints/sprint1-stories.md`（E05/E06 验收 G/W/T）；`docs/sprint1-batchB-engineering-report.md`（程基岩 §2/§5/§6）。 |
| **实现产物** | `src/game/vision_cone.gd`、`src/game/sound_propagation.gd`、`src/core/event_bus.gd`（未改）、`src/game/step_commit.gd`、`src/main/sprint0_bootstrap.gd`、`src/game/light_model.gd`、`src/core/spatial_hash_grid.gd`（交叉验证用）。 |

---

## 0. 设计门判定（Design Gate Verdict）

> **判定：PASS / CONCERNS（无硬阻塞项）**

Batch B 在**设计意图层面整体达标**：四支柱无漂移、范围未越界（E07 实体确未实现）、事件词汇零漂移、控制清单硬约束全部在常量层满足、主数值锚（HALF_ANGLE 35° / RANGE 14m / TICK_HZ 10 / EDGE 8° / RING_CAP 8）与 GDD 一致、无裸数硬编码漂移。

存在 **3 项非阻塞 CONCERN / 需主理人裁决项**，均不阻塞本批冒烟点，但须在 Sprint 1 退出前闭环（多落 Batch C）：
1. **E05-S6「掩体接入」接线缺失**（机制+常量+R-03 达成，但 `VIS_MULT_COVER` 未被任何消费方传入 `compute_visibility`，掩体降可见尚未真正生效）→ 建议 Batch C 返工接线。
2. **G1 双发冲突**（Batch A 遗留 `StepCommit.sound_emitted` 直发 + `sprint0_bootstrap` 转发，与 E06-S2 规范路径并存）→ 需主理人授权 Batch C 清理。
3. **G3 `vision_looming` LOS 门控**（当前几何判据，墙后也发）→ 可调项，需主理人定夺「墙后发不发」。

> 测试「实跑全绿」属 quality-lead 职责（程基岩报告 §4/§6 K1 已诚实标注沙箱无 Godot/GUT 未实跑）。本评审不评估测试通过与否，仅评估设计契约/控制清单是否被实现产物所尊重。

---

## 1. 逐 Story 设计评审

> 判定图例：✅ PASS（设计意图达成）／🟡 CONCERN（设计意图部分达成或待确认）／❌ FAIL（违背设计意图）。

### 1.1 E05-S5 · 锥缘 tell `vision_looming(guard_id)`

- **设计意图**（`sprint1-stories.md` E05-S5 / `design-scope.md` §1.4）：玩家进入锥缘 8° 预警带 → 发 `vision_looming(guard_id)`（经 E01-S9 声明）；锥缘脉动 ≤2Hz（V-02）；不靠色相（C-05）。
- **实现核对**（`vision_cone.gd`）：
  - `EDGE_MARGIN_DEG := 8.0`（L26）✅；`is_in_edge_band()`（L109–116）按 `range + 角度带[HALF_ANGLE-8, HALF_ANGLE]` 判定，锥外/锥内深处均返回 false ✅。
  - 去抖：进入带发一次、`_edge_warned` 置位，离开后 re-arm（L126–134）✅，与验收「进入去抖触发一次、停留不重发、离开再进可重发」一致。
  - `_tick_once()`（L121–134）在 10Hz tick 内发本地 `vision_looming` 并**双向转发** `_bus.vision_looming.emit(guard_id)`（L129–131）✅，信号签名与 `event_bus.gd:31` 一致。
  - 脉动 V-02 由 `CONE_VFX_PULSE_HZ=2.0` + Tween 封顶（见 E05-S7）✅。
- **控制清单**：V-02 ✅、C-05 ✅（亮度+形状编码，图标由 E09 Batch C 接，与计划一致）、V-01 ✅（2Hz 远低于 3Hz 频闪禁限）。
- **判定**：✅ **PASS**（机制层）。
- **CONCERN（G3，需主理人裁决）**：tell 为**纯几何判据，未要求 LOS 清晰**（L109–116 不查 LOS）。即玩家处于墙后、但实际在锥缘角度带内时也会收到 looming。设计上可解读为「即将被扫到的空间预警」，但会削弱支柱四「被注视」的信息诚实性（误报）。程基岩报告 §6 G3 已列为可调项。**建议主理人裁决**：是否加 `_query.has_line_of_sight` 门控（墙后不发）。不阻塞本批（报告已说明为几何预警意图）。

### 1.2 E05-S6 · 外部 `visibility_multiplier` 注入（烟雾×0.3 / 掩体×0.6）

- **设计意图**（`design-scope.md` §1.4 / §3 缺口 G3 / `sprint1-plan.md` §2 Do）：`compute_visibility` 接受 `external_multiplier`（默认 1.0），**掩体/烟雾经此衰减**；**Sprint 1 仅加槽 + 默认 1.0 + 掩体接入**；不新增系统；仅降可见、非无敌（R-03）。
- **实现核对**（`vision_cone.gd`）：
  - 槽：`compute_visibility(target, visibility_multiplier := 1.0)`（L82）；乘数仅缩放 light-sensitivity 项，锥/LOS/range 门控在其之上不动（L82–103）✅。
  - 不无敌（R-03）：`m := clampf(visibility_multiplier, 0.0, 1.0)`；锥外/LOS 断/超距仍为 0；仅 0.0 乘数才归零，而掩体/烟雾用 0.6/0.3（L102–103）✅，与验收「掩体/烟雾不再变无敌」一致。
  - 常量：`VIS_MULT_SMOKE := 0.3`、`VIS_MULT_COVER := 0.6`（L36–37）值与设计一致 ✅。
  - 不新增系统、仅消费已存在信号/接口 ✅。
- **⚠️ CONCERN（设计意图部分未达 — 掩体接入接线缺失）**：`VIS_MULT_COVER` / `VIS_MULT_SMOKE` **仅声明，未被任何代码路径传入 `compute_visibility`**。`_tick_once()`（L122）调用 `compute_visibility(player_pos)` 用默认 `1.0`；全仓 grep 确认 `VIS_MULT_COVER/SMOKE` 仅在声明与测试入参出现（`vision_cone.gd:10/36/37`，`light_model.gd` 中 `get_cover` 亦未被 E05 调用）。即：**Batch B 交付了「槽 + 常量 + R-03 不无敌测试」，但「掩体实际降低可见」的接线并未完成**——处于掩体中的目标当前仍按 LOS 中断（`SpatialQueryWrapper.has_line_of_sight`，但切片未置 `_query`，Sprint 0 局限）而非乘数×0.6 降可见。E04-S3 `get_cover` 已在 Batch A 落地（返回 bool），接线仅需 ~3 行（tick 内读 `_light.get_cover(target)` → 传 `VIS_MULT_COVER`）。
- **控制清单**：R-03 ✅（机制）、C-04 ✅（亮度编码，非色相）。
- **判定**：🟡 **CONCERN（机制 PASS / 集成 PARTIAL）**。函数正确性达标且 R-03 满足，但设计文档明确要求 Sprint 1「掩体接入」，本批未接。程基岩报告 §2 E05-S6 将其标为「达成」属**对集成完成度的过度陈述**。
- **处置**：列为**建议工程返工项（Batch C 落地）**——在 E05 tick 接入 `LightModel.get_cover → VIS_MULT_COVER`；SMOKE 生产源仍属 E07 Sprint 2，其 ×0.3 注入点已留槽、无需本批做。详见 §9.3。

### 1.3 E05-S7 · 锥可视化完整（冷白 #9FB8C9 / 脉动 / 亮度差 / 非实时光）

- **设计意图**（`design-scope.md` §1.4）：半透明 MeshInstance3D 地面光斑冷白 `#9FB8C9`；脉动 ≤2Hz（V-02）；亮度差 ≥3:1（C-03）；非实时光（R-02）；不靠色相（C-04）。
- **实现核对**（`vision_cone.gd`）：
  - `attach_cone_vfx()`（L155–176）：emissive quad（`StandardMaterial3D.emissive`，**非 OmniLight3D**）✅ R-02；颜色 `CONE_VFX_COLOR = Color("#9FB8C9")` ✅ C-04（冷白、`b≥r` 非危险色相）；扁平 `scale(Vector3(1,0.02,1))` 地面 patch ✅。
  - 脉动：`CONE_VFX_PULSE_HZ = 2.0`（L30）✅ V-02；`_start_pulse()`（L179–187）用 Tween 在 `[ALPHA_MIN, ALPHA_MAX]` 间呼吸。
  - 亮度差：`ALPHA_MAX/ALPHA_MIN = 0.30/0.06 = 5:1 ≥ 3:1`（L32–33）✅ C-03（以 alpha 摆幅近似世界要素亮度对比）。
  - T-04：`tween.set_speed_scale(Engine.time_scale if >0 else 1.0)`（L183）——凝神（0.25）下脉动变慢、绝不提速，V-02 恒满足 ✅。
  - headless 安全：`_can_render()` 门控（L190–191），无树不构建 VFX ✅。
- **控制清单**：V-02 ✅、C-03 ✅（常量层）、C-04 ✅、R-02 ✅、T-04 ✅。
- **判定**：✅ **PASS（常量 + 渲染骨架）**。
- **待确认（非偏差）**：C-03 的**实测**对比度（emissive quad 亮度 vs 暗场景）须在有引擎环境由 Batch D `budget_assert` / 手动确认；当前 test 断言 alpha 摆幅 5:1，属合理近似。与程基岩报告 §5 C-03 🟡 一致。

### 1.4 E06-S1 · `emit` 经 Grid 通知半径内守卫

- **设计意图**（`sprint1-stories.md` E06-S1）：`emit(payload)` 经 E01 Grid 查 radius 内守卫 → `sound_emitted(SoundPayload)` → E08；成本 O(半径内守卫)。
- **实现核对**（`sound_propagation.gd`）：
  - `emit()`（L106–134）：`grid.query_radius(origin, radius)` 取候选（L122）→ 对 `_guard_positions` 注册表做 `origin.distance_to(gp) <= radius` **精确距离过滤**（L123–127）→ `target_guard_ids` ✅，与 ADR-002「网格返回包围盒候选、精确过滤由调用方做」一致（见 §6 G2 核对）。
  - 广播 `_bus.sound_emitted.emit(enriched)`（L133），payload 含 `origin/radius/intensity/source/target_guard_ids`，shape 与 `system-breakdown.md` §2.2 `SoundPayload` 兼容（新增 `target_guard_ids` 为 E08 所需扩展，非漂移）✅。
  - 成本：一次网格查询 + 一次总线广播 + 精确过滤，O(半径内守卫) ✅。
- **控制清单**：G-03 ✅（事件驱动非逐帧）、G-01 🟡（守卫总数由 Batch C 的 E08 管理保证，emit 仅按半径过滤，符合设计分工）。
- **判定**：✅ **PASS**。

### 1.5 E06-S2 · 用 E03 noise_radius 发落足声

- **设计意图**（`sprint1-stories.md` E06-S2）：监听 `player_step_committed`（携带 `noise_radius/surface/gait`）→ 生成 `SoundPayload{origin=to, radius=noise_radius, intensity=gait派生, source=FOOTFALL}`；**半径不改写**（由 E03 公式给定）。
- **实现核对**（`sound_propagation.gd`）：
  - `_on_player_step_committed()`（L90–100）：`radius = payload.get("noise_radius")`（L92）**原样取用、不改写** ✅；`origin = payload.get("to")` ✅；`gait → GAIT_INTENSITY` 派生 intensity（L93–94）✅；`source = SOURCE_FOOTFALL` ✅。
  - `bind` 在 `_ready` + 直连双保险（L81–85），headless 安全 ✅。
- **控制清单**：G-02 ✅（声环由 E06-S3 卡）、C-02 🟡（后续 HUD，Batch C）。
- **判定**：✅ **PASS**。
- **注**：`GAIT_INTENSITY{SNEAK0.3/WALK0.6/RUN1.0}`（L25–29）为合理单调设计常量，与 `system-breakdown` §2.3 `Gait` 枚举一致；设计锚未钉死具体强度值，仅要求「由 gait 派生」，无漂移。与 E08 `KS15` 缩放的最终联调见 §9.2（U1）。

### 1.6 E06-S3 · 声环 VFX ≤8 FIFO（G-02）

- **设计意图**（`sprint1-stories.md` E06-S3 / `design-scope.md` §1.5）：同屏声环 ≤8，FIFO 淘汰最旧（Tween 自毁）；形状编码（同心圆）对应 C-05；粒子随 `time_scale`（T-04）。
- **实现核对**（`sound_propagation.gd`）：
  - `request_ring()`（L139–153）：纯记账 FIFO，`while _rings.size() > RING_CAP: pop_front` + `_destroy_ring_visual`（L149–151），`RING_CAP := 8`（L22）✅ G-02；`is_over_ring_budget()`（L158–159）供 Batch D `@ci:G-02` ✅。
  - `_spawn_ring_visual()`（L162–192）：emissive quad（非实时光 R-02）✅；`RING_COLOR = #9FB8C9` 冷白（L38）✅ C-04/C-05；**同心圆扩张 = 形状编码** ✅ C-05；Tween `set_speed_scale(Engine.time_scale)`（L183）✅ T-04；自毁 `queue_free`（L192）✅。
  - headless 门控 `_can_render()`（L211–212），无树仅记账不渲染 ✅。
- **控制清单**：G-02 ✅、C-05 ✅（形状编码，图标由 E09 Batch C 接）、T-04 ✅、R-02 ✅。
- **判定**：✅ **PASS**。
- **微小打磨建议（非偏差）**：环 VFX 的 `emissive_intensity=0.25`、`col.a=0.25`、`scale 0.02` 扁平、`0.6s` 扩张时长属渲染侧裸数，非玩法预算/阈值（不触 `sprint1-stories.md` §5 红线常量清单）。建议 Batch D 前将其提为命名常量以便调参与一致性；不阻塞。

### 1.7 E06-S5 · 按距离衰减提可疑度（→ E08）

- **设计意图**（`sprint1-stories.md` E06-S5）：公式 `sound_in_range = intensity×(1−dist/radius)` 来自 `sound_emitted`，供 E08 累加可疑度（含 KS15）。
- **实现核对**（`sound_propagation.gd`）：
  - `suspicion_from_distance(intensity, dist, radius)`（L203–208）：`factor = 1 - d/radius`；`max(0, intensity*factor)`；零半径除零保护 `if radius<=0: return 0` ✅；与 §2 公式逐字一致 ✅。
- **范围纪律**：完整 E08 联调**明确留 Batch C**（程基岩报告 §6 U1；`sprint1-stories.md` §3 批注「可后置到 Batch C 初」）✅，未越界、未伪闭环。
- **控制清单**：G-04 🟡（FSM 节流由 Batch C E08-S3 落实）、C-02 🟡（HUD Batch C）。
- **判定**：✅ **PASS（范围内）** —— 声音侧公式 + 桩测试达成，E08 消费合同已由 `sound_emitted` payload（`target_guard_ids` + `origin/radius/intensity`）备齐。

---

## 2. 四支柱贴合核对（Batch B 范围）

| Epic / 系统 | 服务支柱 | Batch B 落点 | 漂移？ |
| --- | --- | --- | --- |
| E05 视野锥（S5/S6/S7） | 支柱四● / 支柱一● | 锥缘 tell「被注视」压迫（S5）+ 威胁一眼可读支撑规划（S7）+ 掩体降可见资源（S6，*接线待 Batch C*） | 无（S6 接线缺口见 §1.2/§9.3，非支柱漂移） |
| E06 声音传播（S1/S2/S3/S5） | 支柱一● / 支柱三● | 噪声是可权衡承诺（S2）+ 诱饵=主动解法克制唯一解（S1/S3 形状编码，DECOY 实体 Sprint 2） | 无 |

**结论**：Batch B 两个 Epic 各自服务 ≥1 支柱，无「无主」系统、无支柱漂移。E05-S6 掩体降可见的*机制*已就位，仅消费接线待 Batch C，不视为支柱漂移（软资源仍在，只是当前切片未生效）。

---

## 3. 范围边界：E07 互动物件未越界确认

- `sound_propagation.gd` 仅声明 `SOURCE_DECOY/TRAP/AMBIENT` 常量并注释「E06-S4 (DECOY) 是 Batch D」（L31–35）；**未实现**任何 decoy/诱饵实体、未监听 `decoy_landed`、未触碰 E07。
- Batch B 范围 = E05-S5/S6/S7 + E06-S1/S2/S3/S5（程基岩报告 §1、§7 结论）；E06-S4（DECOY 声圈）、E09-S4（道具/charges）明确归 Batch D，依赖 E07 实体（Sprint 2）。
- `decoy_landed` / `interactable_triggered` 信号已在 Batch A（E01-S9）声明，Batch B 仅*消费契约*就绪、**未擅自实现实体** ✅。
- **判定**：✅ 范围未越界，严守「E07 整系统推迟 Sprint 2，Sprint 1 仅接事件副作用」铁律（`design-scope.md` §1 / 范围纪律）。

---

## 4. 事件词汇零漂移评审

- **`event_bus.gd` 未经 Batch B 改动**（程基岩报告 §1「未改动（按纪律）」已核实；本评审交叉读 `src/core/event_bus.gd` 确认无 Batch B 编辑痕迹）。
- **`vision_looming(guard_id: int)`**：`event_bus.gd:31` 声明 = `vision_cone.gd:51` 本地信号 = 转发调用 `_bus.vision_looming.emit(guard_id)`（L131）三方一致 ✅。
- **`sound_emitted(payload: Dictionary)`**：`event_bus.gd:29` 声明 = `sound_propagation.gd:133` 广播（`enriched` dict）一致；dict 字段 `origin/radius/intensity/source` 对齐 `system-breakdown.md` §2.2 `SoundPayload`，并追加 `target_guard_ids`（E08 所需、向后兼容扩展）✅。
- 其余 13 信号词汇表（`system-breakdown.md` §2）Batch B 未新增/未改名/未改参 ✅。
- **判定**：✅ **事件词汇零漂移**。

---

## 5. 一致性 / 数值锚核对（无裸数硬编码漂移）

| 常量 | 实现值 | 文件:行 | 权威锚（GDD/架构/控制清单） | 一致？ |
| --- | --- | --- | --- | --- |
| `HALF_ANGLE_DEG` | 35.0 | vision_cone.gd:21 | design-scope §1.1：35° | ✅ |
| `RANGE` | 14.0 | vision_cone.gd:22 | design-scope §1.1：14m | ✅ |
| `TICK_HZ` | 10.0 | vision_cone.gd:23 | design-scope §1.1：10Hz（G-03 错峰） | ✅ |
| `EDGE_MARGIN_DEG` | 8.0 | vision_cone.gd:26 | E05-S5：锥缘 8° 预警带 | ✅ |
| `CONE_VFX_PULSE_HZ` | 2.0 | vision_cone.gd:30 | V-02 ≤2Hz | ✅ |
| `CONE_VFX_ALPHA_MIN/MAX` | 0.06 / 0.30 | vision_cone.gd:32–33 | C-03 ≥3:1 → 实测 5:1 | ✅ |
| `CONE_VFX_COLOR` | #9FB8C9 | vision_cone.gd:31 | E05-S7 冷白（C-04/C-05） | ✅ |
| `VIS_MULT_SMOKE` | 0.3 | vision_cone.gd:36 | E05-S6 烟雾×0.3 | ✅ 值对，**未被消费**（见 §1.2/§9.3） |
| `VIS_MULT_COVER` | 0.6 | vision_cone.gd:37 | E05-S6 掩体×0.6 | ✅ 值对，**未被消费**（见 §1.2/§9.3） |
| `RING_CAP` | 8 | sound_propagation.gd:22 | G-02 ≤8 | ✅ |
| `GAIT_INTENSITY` | SNEAK0.3/WALK0.6/RUN1.0 | sound_propagation.gd:25–29 | 非硬性锚（仅「由 gait 派生」，单调一致） | ✅（新常量，待 E08 KS15 联调） |
| `RING_COLOR` | #9FB8C9 | sound_propagation.gd:38 | C-05 冷白非危险色相 | ✅ |
| `CELL`（网格） | 14.0 | spatial_hash_grid.gd:14 | ADR-002：cell ≥ 最大锥程 | ✅ |

- **常量引用纪律**（`sprint1-stories.md` §5 红线）：全部玩法阈值/预算（HALF_ANGLE/RANGE/TICK_HZ/EDGE_MARGIN/RING_CAP/VIS_MULT_*/GAIT_INTENSITY）均以命名常量引用，**无裸数散落于玩法逻辑** ✅。
- **唯一裸数**为渲染侧 VFX 细节（`emissive_intensity=0.25`、`scale.y=0.02`、环扩张 `0.6s`，见 §1.3/§1.6），不属玩法预算红线，仅作 Batch D 前打磨建议。

---

## 6. 控制清单逐条勾稽（Batch B 触发项）

| 约束 | 来源 | 状态 | 证据（文件:行） |
| --- | --- | --- | --- |
| **V-02** 脉动 ≤2Hz | E05-S5/S7 | ✅ 常量满足 | CONE_VFX_PULSE_HZ=2.0（vision_cone.gd:30）；Tween 封顶 |
| **V-01** 禁 >3Hz 频闪 | E05-S5 | ✅ | 2Hz 呼吸（非亮灭闪），远低于 3Hz |
| **G-02** 声环 ≤8 | E06-S3 | ✅ | RING_CAP=8（sound:22）；FIFO + is_over_ring_budget |
| **C-03** 亮度差 ≥3:1 | E05-S7 | ✅ 常量 / 🟡 实测待确认 | ALPHA 5:1（vision:32–33）；引擎实测交 Batch D |
| **C-04** 不靠色相 | E05-S7/E06 | ✅ | 冷白 #9FB8C9（vision:31 / sound:38）+ 亮度脉动 |
| **C-05** 亮度+形状+图标 | E05-S5/E06-S3 | ✅ 亮度+形状 / 🟡 图标 Batch C | 锥缘脉动+同心圆声环（形状）；图标由 E09 接（计划一致） |
| **R-02** 锥/声非实时光 | E05-S7/E06-S3 | ✅ | emissive quad（非 OmniLight3D） |
| **R-03** 掩体降可见非无敌 | E05-S6 | ✅ 机制 / 🟡 掩体接线待 Batch C | clampf[0,1] + 0.6/0.3 乘数（vision:102–103） |
| **T-04** 粒子随 time_scale | E05-S7/E06-S3 | ✅ 代码 / 🟡 观感待引擎确认 | set_speed_scale(Engine.time_scale)（vision:183 / sound:183） |
| **G-03** ≤10Hz/守卫、非逐帧 | E05/E06 | ✅ | TICK_HZ=10 错峰（vision:23）；emit 事件驱动 |
| **G-01** 守卫 ≤8/16 | E06-S1 | 🟡 由 E08 保证 | emit 仅按半径过滤（设计分工，Batch C） |

> 🟡 = 机制已落地 / 常量已满足，但**最终观感或联调**需在真实引擎（Batch D CI 或手动）确认，或依赖 Batch C 调用方补齐。均非本批设计偏差。

---

## 7. 设计理论红线复查（MDA / 自我决定论 / 心流 / Bartle / 四支柱）

| 红线 | Batch B 评估 | 结论 |
| --- | --- | --- |
| **主导策略（Dominant Strategy）** | 无新主导策略。E06 噪声为可权衡承诺（高 gait→高噪声引怪），与 RUN（Batch A，D1 裁决「高成本 deliberate」）一致；无「唯一最优解」被引入。 | 无 |
| **经济失衡（Economy Imbalance）** | 本批无经济系统；声音/可见性为信息博弈，无资源通胀/贬值。 | 无 |
| **认知过载（Cognitive Overload）** | 锥 VFX（冷白脉动）与声环 VFX（同心圆冷白）**共用同一非色相编码语言**（#9FB8C9 + 亮度/形状），表现一致、不堆砌；图标层（E09）尚未接入，信息密度受控。 | 无 |
| **支柱漂移（Pillar Drift）** | 见 §2：E05/E06 各服务 ≥1 支柱，无无主系统、无反向违背。 | 无 |

**结论**：Batch B 未触碰四条设计理论红线。

---

## 8. 已知风险与跨批待办（设计视角，handoff）

- **K1（quality-lead 接管）**：沙箱无 Godot/GUT，17 个 Batch B 测试未实跑（程基岩报告 §4/§6）。本评审不评估测试绿否；建议主理人指派 quality-lead 在可运行引擎跑 `godot --headless -s res://addons/gut/gut_cmdln.gd -gdir=res://tests/unit -gexit` 做最终确认。
- **C-03 / T-04 实测**：锥 VFX 亮度对比、声环/锥脉动随 time_scale 的**可视观感**须引擎确认（与程基岩报告 §5 🟡 一致），建议 Batch D `budget_assert` + 手动巡检。
- **VFX 网格几何**：`CylinderMesh` 扁平朝向细节由 E09 在 Batch C 打磨（计划已载），非本批阻塞。

---

## 9. 需主理人裁决 / 建议工程返工项（设计相关）

### 9.1 G3 · `vision_looming` 是否加 LOS 门控（可调项，不阻塞）
- **现状**：tell 为纯几何（range+角度带），墙后也发（§1.1）。
- **设计影响**：不加 → 可能误报、削弱支柱四「被注视」的信息诚实；加 → 更诚实但实现需 `_query` 在切片中置位（当前 Sprint 0 切片未置 `_query`，LOS 默认通过）。
- **请主理人裁决**：保持几何预警（当前设计意图），还是改为「墙后不发」（加 `_query.has_line_of_sight` 门控）？无论哪种，本批不阻塞。

### 9.2 G1 · Batch A 遗留 `sound_emitted` 双发冲突（需授权 Batch C 清理）
- **现状**（已交叉验证）：
  - `src/game/step_commit.gd:78` 直接 `sound_emitted.emit({"pos": to, "radius": noise_radius})`（本地信号，payload 缺 `intensity/source/target_guard_ids`）；
  - `src/main/sprint0_bootstrap.gd:100` `_step.sound_emitted.connect(_bus.sound_emitted.emit)` 将其转发总线；
  - 与 E06-S2 规范路径（`SoundPropagator` 监听 `player_step_committed` → 发完整 `sound_emitted`）并存 → 集成后**双发**，且遗留 payload 用 `pos` 而非 `origin`、无 `intensity`，Batch C 的 E08 距离衰减将取不到字段。
  - 另：`sprint0_bootstrap.gd` 当前**未实例化 `SoundPropagator`**，故 Batch C 接入 E08 时尚须补实例化 + 移除遗留直发。
- **请主理人裁决**：是否授权 Batch C 在接入 E08 前，删除 `step_commit.gd:78` 直发与 `sprint0_bootstrap.gd:100` 转发，使 `SoundPropagator` 成为 `sound_emitted` 唯一拥有者（程基岩报告 §6 G1 建议）。此清理不属 Batch B 职责（纪律要求不擅动 Batch A），须主理人发令。

### 9.3 E05-S6「掩体接入」接线缺失（建议工程返工，Batch C 落地）
- **现状**：`VIS_MULT_COVER=0.6` 已声明但未被任何消费方传入 `compute_visibility`；`LightModel.get_cover`（Batch A）亦未被 E05 调用。当前掩体降可见**尚未实际生效**（仅 LOS 中断在起作用，且切片未置 `_query`）。
- **设计缺口**：`design-scope.md` §1.4 与 `sprint1-plan.md` §2 均要求 Sprint 1「掩体接入」；程基岩报告 §2 E05-S6 标「达成」属对集成完成度的过度陈述。
- **建议返工（Batch C，~3 行）**：在 `VisionCone._tick_once()`（或 `compute_visibility` 调用处）加入——`if _light != null and _light.get_cover(player_pos): m = VIS_MULT_COVER`，将 `m` 传入 `compute_visibility(player_pos, m)`。SMOKE 生产源仍属 E07 Sprint 2，其 ×0.3 注入点已留槽，无需本批做。
- **不阻塞本批冒烟点**；但若 Sprint 1 退出标准要「掩体真正降可见」，此接线须在 Sprint 1 内（Batch C）闭环。

---

## 10. 设计门结论与建议

> **设计门判定：PASS / CONCERNS（无硬阻塞）**

- **守住项**：四支柱无漂移；E07 未越界；事件词汇零漂移；控制清单硬约束（V-02/G-02/C-03/C-04/C-05/R-02/R-03/T-04/V-01/G-03）在常量层全满足；主数值锚（35°/14m/10Hz/8°/8 环）与 GDD 一致；无裸数硬编码漂移；设计理论四红线无触发。
- **须闭环项（均非本批阻塞，落 Batch C / 主理人裁决）**：
  1. **E05-S6 掩体接入接线**（§9.3，建议 Batch C 返工）——当前掩体降可见未真正生效。
  2. **G1 双发清理授权**（§9.2）——主理人发令 Batch C 移除遗留 `sound_emitted` 直发。
  3. **G3 looming LOS 门控**（§9.1）——主理人定夺墙后发不发。
- **handoff**：测试实跑（K1）与 C-03/T-04 引擎实测交 quality-lead / Batch D。

**建议主理人**：可放行 Batch B 进入 Batch C；但**在 Sprint 1 退出前**须明确 (a) 掩体接线由 Batch C 补完、(b) G1 清理授权已下达、(c) G3 偏好已定。三项任一若留到 Sprint 1 末未决，将影响「完整核心循环可玩」退出标准（尤其掩体降可见与声音双发对 E08 联调正确性的影响）。

---

*— 文策渊 / design-strategist · Phase 5 Sprint 1 Batch B 设计评审*
