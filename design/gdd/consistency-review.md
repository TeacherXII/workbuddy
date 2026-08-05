# Phase 2 跨 GDD 一致性评审（Consistency Review）
## 《灰烬之步》ASHEN STEP

| 字段 | 值 |
| --- | --- |
| **阶段** | Phase 2 · 系统设计交付评审 |
| **文档版本** | v0.3（Sprint 2 设计增补） |
| **作者** | 文策渊（设计策略师） |
| **评审对象** | `design/gdd/system-breakdown.md` + `design/gdd/systems/*.md`（8 份八节 GDD） |
| **对齐基线** | 概念 v0.2、架构 v0.2、ADR-001~004、`control-manifest.md` v0.1、美术圣经 v0.2 |

---

## 0. 评审结论

### **判定：PASS / CONCERNS（通过，含 4 项非阻塞 CONCERNS）**

- **无 FAIL / 无硬阻塞项**：八系统均对齐四支柱、范围纪律未被违反、跨 GDD 事件词汇一致、性能预算引用与 ADR/control-manifest 自洽。
- 与架构基线风险5 结论一致：架构判定 **PASS（含 4 项非阻塞 Concerns）**；本设计评审的 CONCERNS 与架构 Concern #2/#3 同源，均已落位到对应 GDD，可在 lean 评审内缓解，不阻断发布。
- 见 §4 阻塞项清单：**空**。

---

## 1. 已对齐项（PASS 依据）

### 1.1 四支柱对齐（无支柱漂移）
| 系统 | 服务支柱 | 判定 |
| --- | --- | --- |
| ① 步进提交 | 支柱一● 支柱二● | ✅ |
| ② RTwP 时间 | 支柱一● 支柱二● 支柱四● | ✅ |
| ③ 视野锥 | 支柱四● 支柱一● | ✅ |
| ④ 声音传播 | 支柱一● 支柱三● | ✅ |
| ⑤ 掩体/阴影 | 支柱一● 支柱三● 支柱二● 支柱四● | ✅ |
| ⑥ 巡逻 AI | 支柱一● 支柱四● | ✅ |
| ⑦ 互动物件 | 支柱三● 支柱一● | ✅ |
| ⑧ 核心 HUD | 支柱二● 支柱三●（四支柱均不破坏） | ✅ |

> 每个系统至少服务 1 条支柱（见 `system-breakdown.md` §5），无「无主」系统，无反向违背任一支柱的设计。

### 1.2 范围纪律（无范围漂移）
- 8 个系统严格是**概念 §3 六子系统 + RTwP 时间模型 + 核心 HUD** 的一一展开，未新增任何平行机制大类。
- ⑦ 互动物件仅**派发既有事件**（熄灯/发声/触发），不另立机制族；Tier2/3 全部以**参数/变体/数据复用**实现（守卫变体、幽灵回放、机关谜题），未新增系统。✅

### 1.3 跨 GDD 接口一致性（事件词汇无漂移）
- 全部事件名、参数、共享类型（`Gait`/`Surface`/`SoundSource`/`LightState`/`GuardState`/`SusTier`/`TimeMode`/`LightLevel`）统一见于 `system-breakdown.md` §2，且被各 GDD「接口」节严格引用。
- 交叉核对（发出方 ⇄ 消费方）全部闭合：
  - ② `time_scale_changed` ← L2 TimeController ✅
  - ⑤ `light_state_changed`/`cover_state_changed` → ③ 重算 ✅
  - ① `player_step_committed` → ④ ✅
  - ⑦ `decoy_landed` → ④；`interactable_triggered` → ④/⑤/⑥ ✅
  - ④ `sound_emitted` → ⑥ ✅
  - ③ `vision_stimulus`/`vision_looming` → ⑥/⑧ ✅
  - ⑥ `suspicion_changed`/`guard_fsm_changed`/`exposure_detected`/`guard_transform_dirty` → ⑧/③ ✅
  - ⑧ 仅只读聚合，不反向驱动玩法 ✅

### 1.4 性能预算引用一致性（ADR / control-manifest 自洽）
| GDD | 引用硬约束 | 与基线一致？ |
| --- | --- | --- |
| ② | T-01/T-02/T-03/T-04 | ✅（architecture §4 凝神缩放） |
| ① | T-04 粒子同步、ADR-003 | ✅ |
| ⑤ | R-02/R-03/R-04/R-05/R-06、ADR-004 | ✅ |
| ③ | G-01/G-03、C-03/C-05/C-07、V-02、ADR-002 | ✅ |
| ④ | G-02、C-03/C-05、X-02、ADR-002 | ✅ |
| ⑦ | G-02、R-02、C-03/C-05、X-02 | ✅ |
| ⑥ | G-01/G-04/G-05、C-02/C-06/C-07、V-02/V-03、ADR-002 | ✅ |
| ⑧ | C-01~C-07、X-01/X-02、V-01~V-06、T-01/T-02 | ✅ |

> 锥 10Hz（G-03）、声环 ≤8（G-02）、守卫 ≤8/16（G-01）、FSM ≤10Hz（G-04）、A* 仅状态转换（G-05）、雾 ≤0.05（R-04）、熄灯 ramp ≤0.12/≤0.4s（R-05）、屏震默认关（V-03）、脉动 ≤2Hz（V-02）等关键数字在各 GDD 与架构/清单间**完全一致**，无相互矛盾。

### 1.5 相机一致性
- 固定高角 45–60°（概念 §2，已锁定）被 ①（残影俯读）、③（锥地面投影）、⑧（世界内可读）一致引用，与美术 §0、架构 §6 无冲突。✅

---

## 2. 发现的冲突 / 风险（CONCERNS，非阻塞）

| # | 风险 | 涉及系统 | 缓解（已落位 GDD） | 阻塞？ |
| --- | --- | --- | --- | --- |
| C1 | 同屏声环 ≤8（G-02）在 8 守卫+玩家密集落足时可能瞬时逼近上限 | ④/① | ④ 已规定 FIFO 淘汰最旧环（`RING_CAP=8`，自毁）；CI 断言同屏>8 告警 | 否 |
| C2 | Tier2 16 守卫 + 动态光 32 上限逼近（架构 Concern #2） | ⑤/③ | ⑤ 已写「光 LOD：远处提灯降为自发光近似/关实时光」；受 R-02 + CI 断言保障 | 否 |
| C3 | 烟雾（⑦）如何改写 ③ 可见性需明确接口 | ⑦/③ | ③ `compute_visibility` 应接受外部 `visibility_multiplier`（烟雾/掩体注入）；⑤ `get_cover` 已降系数。建议 ③ 公式追加 `× smoke_factor`，由 ⑦ 落点区提供 | 否 |
| C4 | 暴露软失败（宽限 1.2s→检查点重生）依赖 L2 SaveManager 检查点语义 | ⑥/⑧ | **Sprint 2 已解决**：`save-system.md` 定义完整 L2 持久化层（检查点滚动槽 `CHECKPOINT_SLOT_ID=-1` + `restore_checkpoint`）；D9 seam `patrol_ai._checkpoint_sink` 注入 SaveManager（改 1 行）。C4 由 CONCERN 转为**已落位**。 | 否 |

> 上述 4 项与架构风险5 的 4 Concerns 同源（C2↔架构#2 光LOD；C4↔架构#3 时间/粒子；C1/C3 为本设计细化）。均**非阻塞**，lean 评审内可缓解。

---

## 3. 重大取舍标注（主理人知悉）

1. **RUN 步态 vs 「步步为营」红线**：概念 §3 明文「不做爽快连击式位移」，但 §3 声音段又列「奔跑/疾走」。本设计保留 `RUN` 为**高成本 deliberate 选项**（噪声半径 12m 显著引怪、step_duration 仍受提交间隙约束，非无脑冲刺），服务 Autonomy（快而险的路线）+ 张力。属有意取舍，非支柱漂移；若主理人认为与红线冲突，可降级 RUN 为 Tier2。
2. **暴露=软失败边界**：定义为 `ALERT + 持续可见 1.2s（真实时间）`→重生检查点。刻意避开瞬死，但「被捕即重开」的挫败度需在 playtest 调 `GRACE_RT` 与检查点密度。
3. **光 LOD 视觉代价**：Tier2 远处提灯失实时光 →「威胁光弧」可能轻微 pop；以自发光近似+emissive 缓解，属性能/表现的 known tradeoff（架构 Concern #2）。

---

## 4. 阻塞项清单（FAIL 条件核查）

| 阻塞条件 | 是否触发 |
| --- | --- |
| 任一系统违反四支柱（支柱漂移） | ❌ 未触发 |
| 范围纪律被违反（新增平行系统大类） | ❌ 未触发 |
| 跨 GDD 事件名/参数矛盾 | ❌ 未触发 |
| 性能预算引用与架构/清单不一致 | ❌ 未触发 |
| 存在硬阻塞实现风险（FAIL） | ❌ 未触发 |

> **阻塞项：无。** 评审结论 **PASS / CONCERNS**，可在主理人裁决下进入逐系统实现排期（优先级见 `system-breakdown.md` §4）。

---

---

## 5. Sprint 2 新增事件词汇登记与范围纪律重申

> **状态：D16 已裁决并已补录（RESOLVED）。** 主理人裁定将下表 4 个事件正式补录进权威词汇表 `system-breakdown.md` §2——`save_completed`/`load_completed`/`checkpoint_restored` 入 **§2.1（上游/基础设施）**，`guard_spawned` 入 **§2.2（玩法层，发出方 ⑥）**，并因 `guard_spawned` 引用而在 **§2.3 补登共享类型 `GuardVariant`**。补录条目均带「D16 补录」标注。本节自此为**登记副本/理由留档**，权威定义以 §2 为准。

### 5.1 新增词汇（来源：`save-system.md` §4，L2 服务层）
| 新增事件 | 参数 | 发出方 | 消费方 | 备注 |
| --- | --- | --- | --- | --- |
| `save_completed` | `slot_id: int, success: bool` | SaveManager(L2) | ⑧ HUD | 吐司/错误提示，非玩法信号 |
| `load_completed` | `slot_id: int, success: bool` | SaveManager(L2) | ⑧ HUD | 读档完成回调 |
| `checkpoint_restored` | `checkpoint_id: String` | SaveManager(L2) | ⑥/⑧ | 触发世界重置/软重开 UI |
| `guard_spawned` | `guard_id: int, variant: GuardVariant` | ⑥ patrol_ai | ⑧ HUD | 仅用于 HUD 缓存变体剪影；**Sprint 2 为「已登记 / 未发出」保留态**（依赖 E08，已滑 S3）；若 ⑧ 改从 `guard_fsm_changed` 快照读 variant 则可长期休眠（见 §5.2） |

- 上述 4 个事件为 **L2 持久化/生命周期事件**，**非玩法战斗事件**，不与 ④/⑤/⑥ 的 stealth 信号混淆；已依 **D16 裁决**统一补录进 `system-breakdown.md` §2 词汇表（**✅ 已补录**，§2.1×3 + §2.2×1 + §2.3 类型 `GuardVariant`×1）。
- **Sprint 2 实际生效者为 3 个**（`save_completed`/`load_completed`/`checkpoint_restored`）；`guard_spawned` 随 E08 于 Sprint 3 激活，词汇表已预留以免 S3 再改权威表。
- 与既有词汇无命名冲突、无参数矛盾；`decoy_landed`/`interactable_triggered`/`light_state_changed` 签名仍为 D11 冻结态，**未改动**。

### 5.2 E08 守卫变体：零新事件（一致性利好）
- 循声猎犬 / 暗视哨兵**仅以参数/权重覆盖** `GuardBrain`（architecture §3.4），复用全部既有 `suspicion_changed`/`guard_fsm_changed`/`exposure_detected`。
- **不新增 FSM 状态、不新增 stealth 事件词汇**——变体是 ⑥ 的数据维度，非平行机制族。这是范围纪律的正面印证（见 §1.2）。
- 若 HUD 需渲染变体剪影，优先走既有 `guard_fsm_changed` 携带 `variant` 快照；仅在快照不可行时才启用可选 `guard_spawned`（§5.1），避免词汇膨胀。

### 5.3 范围纪律重申（Sprint 2 三件套 + Sprint 3 候选）
> 依主理人裁决，原「五件套」收敛为 **Sprint 2 三件套必交**，其余滑 Sprint 3。

| 系统/工作流 | 性质 | 支柱服务 | 新增系统？ | 归属 |
| --- | --- | --- | --- | --- |
| **E11 SaveManager 数据层**（原 E01-S5 剥离） | L2 服务补全（minimal→完整数据层） | 一/三 | ❌（L2 补全） | **S2 必交** |
| **E07 实体级互动物件** | ⑦ 参数/数量/实体化扩展 | 三/一 | ❌ | **S2 必交** |
| **E09 a11y 完整包** | ⑧ 设置/表现层补全 | 二/三 | ❌ | **S2 必交** |
| E08 守卫变体 | ⑥ 参数覆盖 | 一/四 | ❌ | S3（FLAG-1 RESOLVED） |
| 手动存档/读档 UI | ⑧ UI 表现层 | 三 | ❌ | S3（FLAG-2 RESOLVED） |
| Tech Debt 基线 | 非阻塞清理 | — | ❌ | S3（FLAG-3 RESOLVED） |

> **结论**：Sprint 2/3 全部条目均为既有系统纵深扩展，四支柱无漂移、跨 GDD 事件词汇仅 L2 层受控新增（4 个，D16 已补录），E08 变体零新事件。**E11 为组织层面的 epic 拆分（SaveManager 从 E01 剥离独立），不改变系统边界与 L2 归属，非新增系统大类。**
> **C4（SaveManager 检查点语义）：✅ 已解决（RESOLVED）** —— 已在 `systems/save-system.md` §2/§3 落位（检查点滚动槽 `CHECKPOINT_SLOT_ID=-1`、`restore_checkpoint()`）并接入 ⑥ D9 seam（`_checkpoint_sink`，仅改 1 行），且其完成信号 `checkpoint_restored` 已随 D16 入权威词汇表。由 CONCERN 正式转为**已解决**，Sprint 2 内交付（不受 FLAG-2 手动 UI 滑期影响）。

---

*跨 GDD 一致性评审 v0.3 完成。Phase 2 系统结论：**PASS / CONCERNS（C1–C3 非阻塞，C4 已解决）**；Sprint 2 增补结论：**PASS（范围纪律保持，词汇受控新增）**。下游：Sprint 2 逐 Story 排期（见 `design/gdd/sprint2-story-candidates.md` + `design/reviews/sprint2-design-scope.md`）。*
