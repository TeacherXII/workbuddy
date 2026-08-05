# Epic / Story 拆分总览 ·《灰烬之步》ASHEN STEP — Phase 4 预制作

| 字段 | 值 |
| --- | --- |
| **阶段** | Phase 4 · 预制作（工程侧交付：Epic/Story 拆分 + 测试框架脚手架） |
| **文档版本** | v0.1（epic 基线，待主理人裁决进入逐 Story 排期） |
| **作者** | 程基岩（工程负责人 / jiyan-p4） |
| **引擎** | Godot 4.4（Forward+ / Vulkan，GDScript 为主，热点 C#/GDExtension）· PC·Steam |
| **上游依据** | `docs/architecture/architecture.md` §2 分层 / §4 性能预算 · `docs/architecture/adr/adr-001~004-*.md` · `docs/architecture/control-manifest.md` · `design/gdd/system-breakdown.md`（依赖 DAG P0→P4 + 事件词汇表）· `design/gdd/systems/*.md`（8 份八节 GDD）· `design/concept/game-concept.md`（四支柱 / 核心循环 / 范围分层）· `design/gdd/consistency-review.md`（4 项 CONCERNS C1–C4）· `design/assets/asset-manifest.md` + `entity-inventory.md` |
| **下游衔接** | `production/epics/E<NN>-*.md`（逐 Epic 展开）· `tests/`（测试脚手架，框架归工程，用例归 Phase 5 quality-lead）· 逐 Story 实现（Phase 5+） |

> **用途**：把已锁定的 8 个 GDD 系统 + L2 基础设施 + 发布/CI 拆成可排期的 Epic 与可测试 Story。所有数值严格对齐架构 §4 预算、ADR-001~004、control-manifest（R/T/V/C/X/G）、GDD 编号与 system-breakdown 依赖 DAG / 事件词汇表。Story 验收标准以 Given/When/Then 写就，均可被 `tests/` 脚手架覆盖（验证驱动）。
>
> **知识诚实**：本拆分为 Phase 4 预制作产物，底层 Godot 节点尚未实现；Story 以「接口/信号契约」（system-breakdown §2 词汇表 + 各 GDD §3 数据模型）为锚，确保先测后写可落地。

---

## 1. Epic 总表（11 个 Epic）

> 粒度 = 每个核心系统 1 个 Epic（E02–E09）+ 1 个工程基座/管线 Epic（E01）+ 1 个发布/CI Epic（E10）+ 1 个 L2 持久化 Epic（**E11**，Sprint 2 从 E01 剥离）。
> 优先级采用 **MoSCoW**；规模采用 **T 恤码**（XS/S/M/L，仅量级，不写实人天）。依赖对齐 `system-breakdown.md` §3 依赖 DAG。

| Epic ID | 名称 | 对应 GDD / 模块 | 层（架构 §2） | 依赖 | DAG 优先级 | MoSCoW | T 恤 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| **E01** | 工程基座与管线（L2 基础设施 + 资产管线 + CI 基座） | L2 基础设施（EventBus / SpatialHashGrid3D / SpatialQueryWrapper / LightState / NavServer / InputManager / A11ySettings **接口**；SaveManager **实现已剥离至 E11**）+ 资产导入管线（asset-manifest §1.3） | L2 / L1 | —（地基） | P0 地基 | **Must** | L |
| **E02** | RTwP 凝神时间模型 | `rtwp-time-model`（GDD ②） | L2 时间控制器 | E01 | P0 | **Must** | M |
| **E03** | 步进提交 / 读—步循环 | `stealth-step-commit`（GDD ①） | L4 | E02, E01 | P1 | **Must** | M |
| **E04** | 掩体 / 阴影与可熄灯 | `cover-shadow`（GDD ⑤） | L4 ↔ L2 | E01 | P1 | **Must** | M |
| **E05** | 视野锥 | `vision-cone`（GDD ③） | L4 ↔ L2 | E04, E01 | P2 | **Must** | M |
| **E06** | 声音传播 | `sound-propagation`（GDD ④） | L4 ↔ L2 | E01, E03, E07 | P2 | **Must** | S |
| **E07** | 互动物件 | `interactables`（GDD ⑦） | L4 | E01, E04, E06, E08 | P2–P3 | **Must**（Tier1 四类）/ Could（变体） | M |
| **E08** | 巡逻 AI 与可疑度 FSM | `patrol-ai`（GDD ⑥） | L3 | E05, E06, E02, E01 | P3 | **Must** | L |
| **E09** | 核心 HUD 与可访问性 | `core-hud-a11y`（GDD ⑧） | L5（表现/UI） | 全部（只读聚合） | P4 | **Should**（Tier1 HUD Must / a11y 包 Tier2） | M |
| **E10** | 发布 / CI / 质量门 | control-manifest §7 + 资产校验（asset-manifest §1.3/§6） | L1 / 管线 | 全部（质量门） | —（贯穿） | **Must** | M |
| **E11** | 存档与设置持久化（SaveManager） | `save-system`（存档 GDD）+ `architecture` §3.2（L2 存档服务）+ C4 检查点 + 偏好委托持久化 | L2 / 管线 | E01（接口） | P1 | **Must** | M |

> **E11 状态：正式新立**（主理人 Sprint 2 裁决 2，已从 E01 剥离）。原 `E01-S5`「SaveManager 完整层」职责整体迁入 E11 的 SAV-S1~S6；E01 保留 SaveManager **接口**声明与其余 L2 服务，`E01-S8` NavServer 不受影响（仍归 E01、仍为 seam 占位）。**排期**：Sprint 2 交数据层（SAV-S1/S2/S3/S4/S6），Sprint 3 交手动存档/读档 UI（SAV-S5，裁决 1 滑期）。详见 `production/epics/E11-save-manager.md` + `production/sprints/sprint2-stories.md` §1 Batch A / §5 FLAG-A。
>
> **剥离理由**：E01 已是 L 量级（多 L2 服务 + 管线）；SaveManager 在 Sprint 2 升级为完整持久化层（versioned schema / 双类槽 / 检查点注入 / 偏好委托 / 版本拒绝），并已有独立权威 GDD `design/gdd/systems/save-system.md`，体量与追溯性都足够独立成 epic。

**T 恤量级说明**（预估故事点量级，非人天）：
- **L**：E01（多 L2 服务 + 管线）、E08（FSM + 寻路 + 变体）— 系统面广、状态多。
- **M**：E02 / E03 / E04 / E05 / E07 / E09 / E10 / **E11** — 单系统核心逻辑明确。
- **S**：E06（声环 VFX + 网格通知，逻辑最薄）— 预算以 FIFO 自毁为主。

---

## 2. 依赖 DAG（对齐 system-breakdown §3，文字图）

```
[E01 工程基座/L2] ── EventBus · Grid · SpatialQueryWrapper(LOS) · TimeController · LightState · NavServer · InputManager · A11ySettings
   │
   ├─► E11 SaveManager (L2 持久化)  (依赖 E01 接口；发 save_completed/load_completed/checkpoint_restored；
   │                                 restore_checkpoint 注入 ⑥ D9 seam → E08；偏好委托 → E09 → P1)
   │
   ├─► E02 RTwP Time Model        (依赖 E01 TimeController；无兄弟依赖 → P0 地基)
   │
   ├─► E04 Cover/Shadow & Light   (依赖 E01 LightState + EventBus；提供 get_light_level/get_cover → 被 E05/E08 消费 → P1)
   │
   ├─► E03 Stealth-Step-Commit    (依赖 E02 focus-release + E01 EventBus/Grid/Input；发 player_step_committed → E06 → P1)
   │
   ├─► E05 Vision Cone            (依赖 E04 get_light_level + E01 SpatialQueryWrapper/Grid；发 vision_stimulus/looming → E08/E09 → P2)
   │
   ├─► E06 Sound Propagation      (依赖 E01 Grid/EventBus + E03 落足 + E07 诱饵；发 sound_emitted → E08 → P2)
   │
   ├─► E07 Interactables          (依赖 E01 EventBus + E04 熄灯 + E06 发声 + E08 触发；发 decoy_landed/interactable_triggered → E04/05/06 → P2–P3)
   │
   ├─► E08 Patrol AI & Suspicion  (依赖 E05 vision_stimulus + E06 sound_emitted + E02 tick 真实时间 + E01 NavServer/Grid → P3)
   │
   └─► E09 Core HUD & A11y        (依赖 ①②③④⑤⑥⑦ 全部只读聚合 → P4 终端层)
E10 发布/CI ── 贯穿所有 Epic，作为质量门（control-manifest §7）在每 Sprint 收口。
```

**关键路径（最长实现链）**：E01 → E02 → E03 → E06 → E08 → E09；以及 E01 → E04 → E05 → E08。
**最小可玩切片内部联调顺序**（同 system-breakdown §3）：E01 → E02 → E03 → E04 → E05 → E06 → E08 → E09；E07 可与 E04/E06 并行接入。

---

## 3. 冲刺编排建议（Sprint 0 垂直切片 → Sprint 1+ → 收尾）

> 评审强度 lean：仅核心节点（架构 §4 预算 / control-manifest 硬约束）卡质量门。每个 Sprint 退出以「可玩/可测 + CI 绿灯」为据。

### Sprint 0 — 垂直切片（验证「读—步」是否好玩）⭐
- **目标**：用最小可玩核心循环验证 deliberate 手感是否成立（支柱一 步步为营 / 支柱二 感官愉悦），不追求完整度。
- **包含 Epic 子集**：
  - **E01（切片）**：EventBus（词汇表 §2 全信号声明）、SpatialHashGrid3D（cell=14m，ADR-002）、SpatialQueryWrapper（LOS 统一遮挡 mask）、TimeController 接口（FOCUS/exit）、InputManager 最小（凝神键 + 步态键）、A11ySettings 持久化接口。
  - **E02（完整）**：FOCUS↔FLOWING + `time_scale` 0.25（ramp 0.15s，T-02）+ `time_scale_changed` 信号；冷却用真实时间（ADR-003 风险4）。
  - **E03（切片）**：提交一步（SNEAK/WALK）+ aim_point 预演 + `player_step_committed`（含 noise_radius 公式 BASE5.0×surface×gait）+ 落足微光/足音/残影(≤6)。
  - **E04（切片）**：最小 `get_light_level`（烘焙/mock 返回 [0,1]）+ 阈值 `L_DARK=0.20`/`L_BRIGHT=0.60` 暴露；一处阴影池 mock。
  - **E05（切片）**：单守卫单锥（half_angle 35°/range 14m，10Hz 错峰 G-03）+ `compute_visibility`（InCone×LOS×光影）+ `vision_stimulus`。
  - **E09（切片）**：下一步落点预演（ghost footprint + `#C8862F` 微光，C-05/C-03）+ 凝神态读出 + 单守卫可疑度占位条。
- **退出标准（Exit Criteria）**：
  1. 玩家可在 FOCUS 中选 aim_point，松开凝神提交一步，角色走到落点并留下微光/足音/残影。
  2. 进入凝神 `time_scale` 切到 **0.25**（断言见 `tests/unit/test_step_commit.gd`）；玩家输入在慢放下仍实时（不受缩放）。
  3. 单守卫锥 10Hz 检测：玩家在光池（L≥0.60）被 `vision_stimulus` 报 visibility≈1.0；在暗处（L≤0.20）报 ≈0（断言见 `tests/unit/test_vision_cone.gd`）。
  4. 基础 HUD 显示下一步预演 + 凝神态 + 可疑度占位。
  5. `tests/` GUT 冒烟在 `godot --headless` 下跑通（E10 切片）。
- **明确 Do / Dont**（见 §4）。

### Sprint 1 — 核心循环闭环
- **包含**：E03 完整（三步态 / ghost_trail / 噪声半径全 surface）/ E04 完整（`get_cover` + `light_state_changed` + 可熄灯过场 R-05 ramp≤0.12/≤0.4s + vignette ease V-06）/ E05 完整（锥缘 tell `vision_looming` ≤2Hz V-02 + 外部 `visibility_multiplier` 注入 C3 + 锥可视化）/ E06 完整（footfall 声环 ≤8 FIFO G-02 + 诱饵 DECOY + `sound_emitted`）/ E08 核心（Calm→…→Alert FSM + 连续可疑度 25/60/10 + 暴露梯度 1.2s 软失败 + A* 仅状态转换缓存 G-05 + `guard_transform_dirty`）/ E09 核心（可疑度条 C-02 ≥7:1 + 暴露 UI `exposure_detected` + 道具/charges 显示）/ E10（headless GUT + control-manifest §7 部分断言）。
- **退出标准**：完整「扫描→规划→提交→读反馈→调适」循环可玩；暴露软失败（宽限 1.2s→检查点重生，C4）跑通；CI 冒烟 + 预算断言部分绿灯。

### Sprint 2 — 互动物件实体级 / 存档数据层 / a11y 完整包（详见 `production/sprints/sprint2-stories.md` v1.0）

> **主理人 Sprint 2 最终裁决**（收口依据）：
> - **裁决 1（按建议滑期）**：守卫变体（E08-S7/S9/S10）+ 手动存档/读档 UI（SAV-S5）+ Tech Debt（TD-S1~S4）**全部滑到 Sprint 3**。
> - **裁决 2（新立 E11 epic）**：SaveManager 从 E01 剥离为独立 Epic **E11**（L2 持久化）。
>
> 故 Sprint 2 必交 = **E07 互动物件实体级** + **E11 SaveManager 数据层** + **E09 a11y 完整包（Tier2）** 三件，拆三批 A/B/C。

- **Batch A — 存档基座（E11 数据层）**：SAV-S1（`schema_version` 前置/版本字段）/ SAV-S2（检查点滚动槽写入 C4 seam）/ SAV-S3（`GuardBrain._checkpoint_sink` 扩参契约）/ SAV-S4（偏好委托持久化 API，字段无关 `save_prefs(section,data)`）/ SAV-S6（数据层 CI 断言）。**不含读档 UI（SAV-S5 滑 S3）**。
- **Batch B — 互动物件实体级（E07）**：E07-S1~S8（DECOY/LIGHT_TOGGLE/TRAP/SMOKE 四类实体 + `charges` 双模型 + TRAP FSM + `smoke_factor=0.3` + 实例注册防 orphan + 预算计入 G-02/R-02）。
- **Batch C — a11y 完整包（E09 Tier2）**：E09-S5a~S5d（色盲枚举 / 时间滑杆 [0.1,1.0] 默认 0.25 / 屏震关 V-03 / 雾三态 V-04 / 动模糊关 V-05 / 文本缩放 [1.0,1.5] X-01 / 字幕 X-02）+ E09-S7（a11y 设置 schema + 偏好委托持久化接 E11 SAV-S4）。
- **分批（依赖 DAG）**：Batch A（存档基座）→ B（互动物件）→ C（a11y）。a11y 经 SAV-S4 偏好委托持久化（FLAG-J 破环：SAV-S4 API 字段无关，避免 a11y↔prefs 循环依赖）。
- **退出标准（重新聚焦，无 S3 依赖）**：
  1. E07 四类互动物件实体级闭环 + `charges` 限量 + 实例注册无 orphan + 预算计入（G-02/R-02）。
  2. E11 存档数据层真实持久化：检查点滚动槽写入 + 偏好委托持久化 + 单档 ≤32KB + 版本不匹配拒绝（无迁移，FLAG-H 对齐 GDD `save-system.md`）+ `save_completed`/`load_completed`/`checkpoint_restored` 信号齐备。
  3. E09 a11y 完整包全部驱动系统（非空转），Tier2 16 同行不破动态光 32（R-02）。
  4. GUT 全绿 + `budget_assert` WARN-ONLY 无破门 + N-7 门不因裸 `[Risky]` 误红（E10）。
- **架构风险 FLAG**（详见 `production/sprints/sprint2-stories.md` §5）：A·SaveManager schema 迁移 + C4 seam 扩参（高，保留 Sprint 2 Batch A，缓解见下）/ C·a11y-HUD 耦合（已降级 **CLOSED**——代码实测 `FOCUS_TINT` 不存在，Batch C 不受 TD 阻塞）/ H·GDD `save-system.md` 与 v0.1 草案冲突（已闭合：采 GDD 为权威源）/ I·E01-S9 事件收口（OPEN）/ J·a11y↔prefs 环（已解：SAV-S4 字段无关）/ K·GDD Tier1 vs 排期（OPEN）。

  > **FLAG-A 缓解（Sprint 2 Batch A 高风险项）**：① SAV-S1 版本字段 `SAVE_VERSION`(=2) 前置写入，所有 load 路径先校验 `schema_version`，不匹配即 `mark_corrupt()` 拒绝（**不迁移**，对齐 GDD）；② SAV-S3 契约测试 `@test_checkpoint_sink_arity_contract` 断言 `GuardBrain._checkpoint_sink(payload)` 扩参后零/单参双兼容，且 `tests/unit/test_patrol_ai.gd:413` `test_soft_fail_invokes_checkpoint_sink_once` **必须同步改**（batchd R7）；③ 扩参列为「必须同步编辑」项，纳入 control-manifest 改动门（R-SAV-1）。

### Sprint 3 — 守卫变体 / 手动存档 UI / Tech Debt 收口（裁决 1 滑期项，详见 `production/sprints/sprint2-stories.md` §2）

- **S3-A 守卫变体（E08）**：E08-S7（循声猎犬 KV15/KS30/感知半径×1.6/锥 11m·30°）/ E08-S9（变体实例化）/ E08-S10（FSM 合并验证，不新增系统，复用 `GuardBrain` 参数覆盖）。**Batch C 延期**。
- **S3-B 手动存档/读档 UI（E11 · SAV-S5）**：手动槽（`MAX_MANUAL_SLOTS=3`）存/取 UI + 槽列表/覆盖确认。**Batch A 延期（读档 UI 仅 S3，数据层 S2 已交）**。
- **S3-C Tech Debt 收口**：TD-S1（hud_slice 相机 bug）/ TD-S2（`FOCUS_TINT` 迁移——**注：代码实测 `FOCUS_TINT` 不存在，本项降级为「hud_slice 字面色字面统一走 `HudColors`」**，见 FLAG-C 降级）/ TD-S3（orphans 治理）/ TD-S4（全 QA 门收口）。
- **退出标准（Sprint 3）**：
  1. 守卫变体不破核心（Tier2 16 同行不破动态光 32，R-02，光 LOD ADR-004）；变体 FSM 合并无状态污染（FLAG-B 中-高）。
  2. 手动存档/读档 UI 闭环：槽列表/存/读/覆盖确认 + 与检查点滚动槽共存。
  3. Tech Debt 收口 + GUT 全绿 + `budget_assert` WARN-ONLY 无破门 + N-7 门不因裸 `[Risky]` 误红（E10）。

### 收尾冲刺（Hardening）
- 性能剖析与优化，逐条对齐架构 §4 预算（守卫 MVP 8 / Tier2 16、锥 10Hz、射线峰值 MVP≈160/s / Tier2≈480/s、fog base≤0.05）。
- 光 LOD 纪律实测（ADR-004 / R-02 ≤32）；眩晕/光敏合规（V-01 禁 >3Hz 频闪 / V-02 脉动 ≤2Hz / V-03 屏震默认关 / V-06 转场 ease）。
- 存档/读档 + 软重开（SaveManager + C4 检查点粒度）。
- Steam 提交准备（E10）。

---

## 4. Sprint 0 垂直切片范围（明确 Do / Dont）

### Do（必须做出）
- **提交一步（step-commit）**：选 aim_point → 松开凝神 → 角色在 `step_duration` 内走到落点 → 落足瞬间微光（`#C8862F`，≤10% 画面纪律，art-bible §2.1）+ 足音 foley + `ghost_trail` 残影（≤6 步淡出）。
- **RTwP 凝神 / 恢复**：按住凝神 → `time_scale` 0.25（缓动 ramp≈0.15s，T-02，非硬切 V-06）；松开 → 1.0。**玩家输入实时**（不受 `time_scale`，ADR-003）。
- **一个视野锥**：1 守卫，`half_angle=35°` / `range=14m`（= grid cell，ADR-002），**10Hz 错峰** tick（G-03），LOS（遮挡层 interfersect_ray，经 E01 SpatialQueryWrapper），光影敏感度（`L≥0.60`→visibility 1.0；`L≤0.20`→≈0）。
- **一处遮蔽 / 阴影**：1 块阴影池（或 1 盏可熄灯 mock）使 `get_light_level` 在暗处≈0、光池≈1（阈值 `L_DARK=0.20`/`L_BRIGHT=0.60`）。
- **基础 HUD 反馈**：下一步落点预演（ghost footprint + `#C8862F` 微光，世界内非屏框，C-05/C-03 亮度+形状编码）、凝神态读出、单守卫可疑度占位条。

### Dont（本切片不做，留给后续 Sprint）
- ❌ 完整 FSM / 暴露宽限 1.2s 软失败完整流（仅占位，Sprint 1 做 E08）。
- ❌ 声音声环 VFX / 诱饵 / 烟雾 / 多守卫 A*（Sprint 1 做 E06/E07/E08）。
- ❌ 完整可访问性设置面板（仅预留 `A11ySettings` 持久化接口，Sprint 2 做 E09）。
- ❌ LightmapGI 实烘焙（用 mock / 程序化 `LightLevel`，真烘焙在 E04 完整 + E10 资产管线）。
- ❌ Steam 导出 / 完整 §7 断言（仅 GUT 冒烟能 `godot --headless` 跑通，E10 切片）。

---

## 5. Sprint 0 进入 Story 速查（Epic → Story）

| Epic | 进入 Sprint 0 的 Story |
| --- | --- |
| E01 | E01-S1（EventBus 词汇表）、E01-S2（SpatialHashGrid3D）、E01-S3（SpatialQueryWrapper LOS）、E01-S4（LightState 接口 + get_light_level 契约）、E01-S6（InputManager + A11ySettings 接口） |
| E02 | E02-S1（TimeController FOCUS/exit + 0.25）、E02-S2（`time_scale_changed`）、E02-S3（真实时间冷却纪律） |
| E03 | E03-S1（Step 状态机 + 冷却 0.12s）、E03-S2（SNEAK/WALK 步态）、E03-S3（预演）、E03-S4（`player_step_committed` + noise_radius） |
| E04 | E04-S1（get_light_level API）、E04-S2（L_DARK/L_BRIGHT 阈值） |
| E05 | E05-S1（单锥 10Hz）、E05-S2（compute_visibility 公式）、E05-S3（LOS）、E05-S4（`vision_stimulus`） |
| E06 | —（Sprint 1 起） |
| E07 | —（Sprint 1 起） |
| E08 | —（占位，Sprint 1 起） |
| E09 | E09-S1（预演可见性 + 凝神态读出） |
| E10 | E10-S1（headless GUT 冒烟） |

> 逐 Story 完整定义、Given/When/Then 验收与架构/控制清单勾稽见各 `E<NN>-*.md`。

---

## 6. 与四支柱 / 范围纪律对齐（勾稽基线）

- **四支柱服务**：8 系统均服务 ≥1 支柱（system-breakdown §5），无支柱漂移；Epic 拆分未新增平行系统大类，严守概念 §5 范围纪律。
- **性能预算锁**：所有 Story 验收中的数值（time_scale 0.25、锥 10Hz、射线峰值、守卫 8/16、动态光 12/32、雾 ≤0.05、声环 ≤8、FSM ≤10Hz、A* 仅状态转换、脉动 ≤2Hz）均直接引用架构 §4 / control-manifest，CI（E10）以 §7 断言卡门。
- **事件词汇零漂移**：所有 Story 仅引用 system-breakdown §2 声明信号；E01-S1 以 CI lint 断言「无未声明信号」（对应 consistency-review §1.3 闭合性）。
- **CONCERNS 归属**：C1（声环≤8 FIFO）→ E06；C2（光 LOD 32 上限）→ E04/E10；C3（烟雾 visibility 注入）→ E05/E07；C4（暴露软失败检查点）→ E08/E01(SaveManager)。均非阻塞，lean 内缓解。

*Epic 基线 v0.1 完成。逐 Epic 展开见 `E01`–`E10`；测试脚手架见 `tests/`；用例填充交 Phase 5 quality-lead。*
