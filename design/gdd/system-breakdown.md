# Phase 2 系统设计 · 系统拆解与依赖排序
## 《灰烬之步》ASHEN STEP — System Breakdown & Dependency DAG

| 字段 | 值 |
| --- | --- |
| **阶段** | Phase 2 · 系统设计（概念 v0.2 + 架构基线 v0.2 下游） |
| **文档版本** | v0.2（系统拆解基线） |
| **作者** | 文策渊（设计策略师） |
| **上游依据** | `design/concept/game-concept.md` §1 四支柱 / §3 Mechanics / §4 核心循环 / §5 范围纪律；`docs/architecture/architecture.md` §2 分层 / §4 预算；四条 ADR；`docs/architecture/control-manifest.md`；`design/art/art-bible.md` §3/§8/§9 |
| **下游衔接** | `design/gdd/systems/*.md`（八节 GDD）、`design/gdd/consistency-review.md` |

> **本文件用途**：在概念 §3 的六子系统 + RTwP 时间模型 + 核心 HUD/可访问性基础上，给出**完整 GDD 系统清单**、**依赖 DAG（文字描述）**、**实现优先级**、**与四支柱的映射**，并定义**跨 GDD 共享的事件总线词汇表**（所有子系统 GDD 的「接口」节严格引用此表，杜绝事件名漂移）。

---

## 1. 系统清单（8 个 GDD 系统）

概念 §3 的六子系统（步进提交 / 视野 / 声音 / 掩体阴影 / 巡逻 AI / 互动物件）+ RTwP 时间模型 + 核心 HUD/可访问性，**不新增任何平行系统大类**，严格守「单核心做极致」范围纪律。

| # | 系统 ID | GDD 文件 | 对应概念子系统 | 层（架构 §2） |
| --- | --- | --- | --- | --- |
| ① | `stealth-step-commit` | `systems/stealth-step-commit.md` | 1. 步进提交（Read & Step） | L4 |
| ② | `rtwp-time-model` | `systems/rtwp-time-model.md` | RTwP 凝神时间模型 | L2（时间控制器） |
| ③ | `vision-cone` | `systems/vision-cone.md` | 2. 视野系统 | L4 ↔ L2（空间查询封装） |
| ④ | `sound-propagation` | `systems/sound-propagation.md` | 3. 声音系统 | L4 ↔ L2（网格） |
| ⑤ | `cover-shadow` | `systems/cover-shadow.md` | 4. 掩体/阴影 + 可熄灯 | L4 ↔ L2（LightState） |
| ⑥ | `patrol-ai` | `systems/patrol-ai.md` | 5. 巡逻 AI 与可疑度 FSM | L3 |
| ⑦ | `interactables` | `systems/interactables.md` | 6. 环境互动道具 | L4 |
| ⑧ | `core-hud-a11y` | `systems/core-hud-a11y.md` | 核心 HUD 与可访问性 | L5（表现/UI） |

> 架构 §2 的 L2 基础服务（SpatialHashGrid3D、EventBus、SpatialQueryWrapper/LOS、TimeController、LightState、NavServer、SaveManager、InputManager、A11ySettings）视为**已实现基线**，本文仅引用，不写 GDD；其契约见 `architecture.md` §2。

---

## 2. 跨 GDD 共享事件词汇表（L2 事件总线）

> 所有系统 GDD 的「接口」节统一引用本表。事件名采用 Godot `signal` 风格 snake_case，参数用 `类型 名` 标注。任何系统不得自造未在下表或本系统 GDD 内声明的事件。

### 2.1 上游/基础设施发出的事件（L2 或引擎）
| 事件 | 发出方 | 参数 | 说明 |
| --- | --- | --- | --- |
| `time_scale_changed` | ② RTwP | `old:float, new:float, mode:TimeMode` | 时间缩放变更（FLOWING / FOCUS / PAUSED） |
| `guard_transform_dirty` | ⑥ Patrol AI（经 L2 节流） | `guard_id:int` | 守卫 transform 变化超阈值，触发视野重算 |
| `light_state_changed` | ⑤ Cover/Shadow | `light_id:int, state:LightState{LIT,EXTINGUISHED}` | 光源开关 → 受影响 cell 重算光影成员 |
| `cover_state_changed` | ⑤ Cover/Shadow | `cell:Vector3i` | 掩体/阴影网格 cell 变更 |
| `save_completed` | SaveManager（L2） | `slot_id:int, success:bool` | **【D16 补录】** 异步写盘完成 → ⑧ 吐司/错误提示。**L2 持久化事件，非玩法信号**，不得被 ④/⑤/⑥ 作为 stealth 刺激消费 |
| `load_completed` | SaveManager（L2） | `slot_id:int, success:bool` | **【D16 补录】** 读档完成 → ⑧ 0.4s 淡入 + 应用 `A11ySettings` 全部开关到运行时。同上，非玩法信号 |
| `checkpoint_restored` | SaveManager（L2） | `checkpoint_id:String` | **【D16 补录】** 软失败恢复完成 → ⑥ 世界重置（可疑度清零、守卫回 `RETURN`）+ ⑧ 软重开 UI（0.6s 黑场 + 字幕）。唯一被玩法层（⑥）消费的 L2 存档事件 |

> **D16 裁决（Sprint 2）**：上表三个 SaveManager 事件参数以 `systems/save-system.md` §4 为权威 schema（`slot_id`/`success`/`checkpoint_id`），与 `consistency-review.md` §5.1 登记一致。三者均为 **L2 持久化/生命周期事件**，与 §2.2 玩法信号分属不同层，禁止混用。

### 2.2 玩法层发出的事件（L4/L3）
| 事件 | 发出方 | 参数 | 消费方 |
| --- | --- | --- | --- |
| `player_step_committed` | ① | `StepCommitPayload{from:Vector3, to:Vector3, surface:Surface, gait:Gait, noise_radius:float}` | ④ |
| `decoy_landed` | ⑦ | `DecoyPayload{pos:Vector3, surface:Surface, radius:float}` | ④ → ⑥ |
| `sound_emitted` | ④ | `SoundPayload{origin:Vector3, radius:float, intensity:float, source:SoundSource}` | ⑥ |
| `vision_stimulus` | ③ | `guard_id:int, target:Node, visibility:float[0..1]` | ⑥ |
| `vision_looming` | ③ | `guard_id:int` | ⑧（锥缘 tell） |
| `suspicion_changed` | ⑥ | `guard_id:int, value:float[0..100], tier:SusTier` | ⑧ |
| `guard_fsm_changed` | ⑥ | `guard_id:int, old:GuardState, new:GuardState` | ⑧ |
| `exposure_detected` | ⑥ | `guard_id:int, target:Node` | ⑧ + 失败流（软重开） |
| `interactable_triggered` | ⑦ | `obj_id:int, type:InteractableType, payload` | ④ / ⑤ / ⑥ |
| `guard_spawned` | ⑥ Patrol AI | `guard_id:int, variant:GuardVariant` | ⑧（变体剪影缓存） |

> **D16 裁决（Sprint 2）**：`guard_spawned` 正式入表，**生命周期事件（只读广播），不携带 stealth 语义**——⑧ 仅用它缓存变体剪影（姿态/形状，非颜色），不得据此改可疑度/FSM。
> **激活时点**：其参数类型 `GuardVariant` 由 E08 守卫变体提供，而 E08 已滑 Sprint 3（见 `reviews/sprint2-design-scope.md` §7）。故本事件 **Sprint 2 为「已登记 / 未发出」保留态**，Sprint 3 随 E08 落地才实际广播。Sprint 2 期间 ⑥ 不发、⑧ 不订阅。
> **优先替代方案仍有效**：若 ⑧ 可从既有 `guard_fsm_changed` 快照读 `variant`，则优先走快照，本事件保持休眠以避免词汇膨胀（`consistency-review.md` §5.2）。

### 2.3 共享数据类型（跨 GDD 一致）
| 类型 | 定义 |
| --- | --- |
| `Gait` | `SNEAK \| WALK \| RUN` |
| `Surface` | `STONE \| GRASS \| METAL \| MOSS`（玩法噪声权威集；系数 STONE 1.0 / GRASS 0.7 / METAL 1.2 / MOSS 0.5，见 `stealth-step-commit` §2；`WOOD` 仅资产材质，映射 STONE） |
| `SoundSource` | `FOOTFALL \| DECOY \| TRAP \| AMBIENT` |
| `LightState` | `LIT \| EXTINGUISHED` |
| `GuardState` | `CALM \| SUSPICIOUS \| ALERT \| SEARCH \| RETURN` |
| `SusTier` | `CALM \| SUSPICIOUS \| ALERT \| SEARCH`（CALM = 可疑度 < 25；与 E08-S2 阈值 25/60/10 对齐；SEARCH 由 E08 FSM 在丢失目标后进入，非连续阈值带成员） |
| `TimeMode` | `FLOWING \| FOCUS \| PAUSED` |
| `GuardVariant` | `STANDARD \| HOUND \| NIGHTEYE`（**【D16 补录】** 因 `guard_spawned` 引用而登记。STANDARD=Sprint 1 基线守卫；HOUND=循声猎犬、NIGHTEYE=暗视哨兵，二者为 **⑥ 的参数/权重覆盖维度，非新 FSM 状态、非新系统**。随 E08 于 **Sprint 3** 落地；Sprint 2 期间仅 `STANDARD` 有效） |
| `LightLevel` | `float[0..1]`，由 ⑤ `get_light_level(pos)` 提供 |

---

## 3. 依赖 DAG（文字描述）

依赖单向向下（架构 §2）。同层内按「谁为谁提供数据/事件」排序。

```
[L2 基础设施] SpatialHashGrid3D · EventBus · SpatialQueryWrapper(LOS) · TimeController · LightState · NavServer
       │
       ├─► ② RTwP Time Model
       │       └─ 依赖：L2 TimeController(Engine.time_scale)。无兄弟依赖。 → 优先级 P0（地基）
       │
       ├─► ⑤ Cover/Shadow & Ext. Light
       │       └─ 依赖：L2 LightState + LightmapGI 烘焙 + EventBus。
       │           提供 get_light_level() / get_cover()（被 ③ ⑥ 消费）。 → 优先级 P1
       │
       ├─► ① Stealth-Step-Commit
       │       └─ 依赖：②（focus 释放提交）、L2 EventBus、L2 Grid(落点)、L2 InputManager。
       │           发出 player_step_committed（被 ④ 消费）。 → 优先级 P1
       │
       ├─► ③ Vision Cone
       │       └─ 依赖：L2 SpatialQueryWrapper(LOS) + L2 Grid + ⑤(光影成员)。
       │           发出 vision_stimulus / vision_looming（被 ⑥ ⑧ 消费）。 → 优先级 P2
       │
       ├─► ④ Sound Propagation
       │       └─ 依赖：L2 Grid + L2 EventBus + ①(落足噪声) + ⑦(诱饵落点)。
       │           发出 sound_emitted（被 ⑥ 消费）。 → 优先级 P2
       │
       ├─► ⑦ Interactables
       │       └─ 依赖：L2 EventBus + ⑤(熄灯) + ④(发声) + ⑥(触发机关)。
       │           发出 decoy_landed / interactable_triggered（被 ④ ⑤ ⑥ 消费）。 → 优先级 P2–P3
       │
       ├─► ⑥ Patrol AI & Suspicion
       │       └─ 依赖：③(vision_stimulus) + ④(sound_emitted) + L2 NavServer + L2 Grid + EventBus。 → 优先级 P3
       │
       └─► ⑧ Core HUD & Accessibility
               └─ 依赖：①(预览) ②(凝神态) ③(锥) ④(声环) ⑤(光影) ⑥(可疑度) ⑦(道具) 全部只读聚合。 → 优先级 P4（最后，只读）
```

**关键路径（最长实现链）**：L2 → ② → ① → ④ → ⑥ → ⑧；以及 L2 → ⑤ → ③ → ⑥。
**最小可玩切片（MVP 内部联调顺序）**：②（时间）→ ①（步进）→ ⑤（光影成员）→ ③（视野）→ ④（声音）→ ⑥（AI）→ ⑧（HUD）。⑦ 可与 ④/⑤ 并行接入。

---

## 4. 实现优先级与里程碑建议

| 优先级 | 系统 | 联调前置 | 备注 |
| --- | --- | --- | --- |
| **P0** | ② RTwP Time Model | L2 TimeController | 无兄弟依赖，先落地；其余系统均读 `Engine.time_scale` |
| **P1** | ⑤ Cover/Shadow & Ext. Light | L2 LightState | 须先于 ③，因视野「光影敏感度」依赖 `get_light_level` |
| **P1** | ① Stealth-Step-Commit | ② | 步进提交依赖凝神释放；落足噪声驱动 ④ |
| **P2** | ③ Vision Cone | ⑤ + L2 SpatialQueryWrapper | 事件驱动 + 10Hz 错峰（G-03 / ADR-002） |
| **P2** | ④ Sound Propagation | ① + ⑦ | 声环 ≤8 同屏（G-02） |
| **P2** | ⑦ Interactables | ⑤ + ④ | 可并行；3–4 MVP 道具 |
| **P3** | ⑥ Patrol AI & Suspicion | ③ + ④ | FSM 5–10Hz（G-04），A* 仅状态转换（G-05） |
| **P4** | ⑧ Core HUD & Accessibility | 全部 | 只读聚合；可访问性开关进设置菜单 |

---

## 5. 系统 ↔ 四支柱映射

| 系统 | 支柱一 步步为营 | 支柱二 感官愉悦 | 支柱三 自主掌控 | 支柱四 肃穆压迫 |
| --- | --- | --- | --- | --- |
| ① 步进提交 | ● 核心载体 | ● 落足微光/足音 | ○ | ○ |
| ② RTwP 时间 | ● 暂停读场 | ● 慢放丝滑 | ○ | ● 压暗凝神 |
| ③ 视野锥 | ● 可读威胁 | ○ | ○ | ● 被注视 |
| ④ 声音传播 | ● 权衡噪声 | ○ | ● 诱饵解法 | ○ |
| ⑤ 掩体/阴影 | ● 可消耗资源 | ● 熄灯质地 | ● 主动造影 | ● 暗即安全 |
| ⑥ 巡逻 AI | ● 暴露可恢复 | ○ | ○ | ● 渐升警戒 |
| ⑦ 互动物件 | ● 规划工具 | ○ | ● 多解克制唯一解 | ○ |
| ⑧ 核心 HUD | ○ | ● 克制 juicy | ● 可访问性 | ○ |

> ● = 直接服务；○ = 间接/次要。每个系统至少服务 1 条支柱，无「无主」系统 → 无支柱漂移（详见 `consistency-review.md`）。

---

## 6. 范围纪律自查（对齐概念 §5）

- **未新增平行系统大类**：8 个系统严格是概念 §3 六子系统 + 时间模型 + HUD 的一一展开；⑦ 互动物件只用「已存在动词（熄灯/发声/触发）」组合，不引入新机制族。
- **Tier 划分**：8 系统全部 Tier1 必做（核心循环成立所需）；Tier2 仅以**已有系统的参数/变体/数量扩展**体现（守卫变体、幽灵回放、色盲模式），不新增系统。
- **红线**：若后续出现「新系统大类」需求（如独立战斗、独立解谜），须在评审标「范围漂移 / 支柱漂移」并报主理人裁决——本拆解本身未违反。

*系统拆解基线 v0.2 完成。逐系统八节 GDD 见 `systems/`；跨 GDD 一致性评审见 `consistency-review.md`。*
