# Sprint 2 设计规划草案（Design Scope）
**《灰烬之步》ASHEN STEP · Phase 2 · 设计策略师 文策渊**

| 字段 | 值 |
| --- | --- |
| **阶段** | Sprint 2 设计规划（**v0.2 已收口**——主理人裁决 FLAG-1/2/3 全滑 S3、新立 E11、D16 补录已落） |
| **作者** | 文策渊（设计策略师） |
| **对齐基线** | 概念 v0.2、架构 v0.2、ADR-001~004、`control-manifest.md` v0.1、美术圣经 v0.2、Sprint 1 收口（`be15521`，GUT 95/95，五退出标准全 PASS）、`system-breakdown.md`、`consistency-review.md` v0.2 |
| **范围纪律红线** | 单核心做极致；不新增平行机制大类；四支柱无漂移 |
| **交付纪律** | 仅 design/ 文档；不写 production/sprints/；不 git commit/push |

---

## 0. 摘要
**主理人已裁决收口（v0.2）**：Sprint 2 必交收敛为**三件套**——**E07 互动物件实体级 + E11 SaveManager 数据层 + E09 a11y 完整包**；**守卫变体（E08）/ 手动存档·读档 UI / Tech Debt 基线三项全滑 Sprint 3**（原 FLAG-1/2/3 全部 RESOLVED，见 §7）。同时 **SaveManager 从 E01 剥离，新立独立 epic E11**；**D16 裁决**将 4 个新事件正式补录进权威词汇表 `system-breakdown.md` §2。

三件套**全部是既有系统的参数、数量或 L2 服务补全，未引入任何平行机制大类，四支柱无漂移**。本文给出每工作流 Do/Dont、统一数值锚、进/出边界、依赖有序的 **3 批提案（A 存档基座 / B 互动物件 / C a11y）**、范围纪律自查与 Sprint 3 候选清单。完整 QA 门沿用 Sprint 1 五退出标准。

---

## 1. 范围总览（Sprint 2 三件套必交）
| # | 工作流 | Epic/Story | 性质 | 支柱服务 | 归属 |
| --- | --- | --- | --- | --- | --- |
| 1 | 互动物件实体级 | E07（S1–S6） | ⑦ 实体化扩展 | 三自主掌控 / 一步步为营 | **S2 必交** |
| 2 | **SaveManager 数据层** | **E11**（原 E01-S5 剥离） | L2 服务补全（minimal→完整数据层） | 一步步为营 / 三自主掌控 | **S2 必交** |
| 3 | a11y 完整包 | E09（S5 等） | ⑧ 设置/表现层补全 | 二感官愉悦 / 三自主掌控 | **S2 必交** |
| — | 守卫变体 | E08（S7） | ⑥ 参数覆盖 | 一 / 四肃穆压迫 | ➡️ **S3**（§7.1） |
| — | 手动存档/读档 UI | E09-S4 / E11 UI 面 | ⑧ UI 表现层 | 三自主掌控 | ➡️ **S3**（§7.2） |
| — | Tech Debt 基线 | TD-1~3 | 非阻塞清理 | （无新增支柱负载） | ➡️ **S3**（§7.3） |

> **E11 说明（主理人裁决）**：SaveManager 原挂 E01-S5，因其已膨胀为完整 L2 持久化层（数据模型 / 版本化 / 检查点滚动槽 / 偏好委托 / 异步落盘），**独立成 epic E11**，与 E01（引擎基座）解耦，便于单独排期与验收。**这是组织层面的 epic 拆分，不改变系统边界、不新增系统大类**；其 GDD 仍为 `design/gdd/systems/save-system.md`。Story 编号相应由 `S-E01-5x` 迁为 `S-E11-x`（见 `gdd/sprint2-story-candidates.md` §B）。
> **epic 文件落地**（`production/epics/E11/`）属交付面，不在设计策略师职责内——由主理人转程基岩/排期流程创建。
> NavServer（E01-S8）依 **D9 裁决**仍走 seam 占位（本文不展开，仅标注其 1 行注入点）。

---

## 2. 每工作流的 Do / Dont 速览

### 2.1 E07 互动物件实体级
**Do**
- 区分两类实体：**世界互动物件**（LIGHT_TOGGLE/TRAP，关卡布置、就近触发）与**玩家携带物件**（DECOY/SMOKE，`entity-inventory` 背包、投掷/使用）。
- `charges` **双模型**：世界物件自身 charges + 玩家背包按类型计 charges。
- TRAP 内部 FSM：`IDLE→ARMED→TRIGGERED→RECOVER/SPENT`。
- 烟雾经 **`smoke_factor` 注入 ③**（`vis = base×cover×smoke`，因子 0.3、限时 ≈4s）——**解决一致性评审 C3**。
- 复用 Sprint 1 已冻结的信号契约（D11）。

**Dont**
- 不新增 `InteractableType`（仍 4 类）；不改 `decoy_landed`/`interactable_triggered`/`light_state_changed` 签名；不引入新系统/新事件。
- 不做机关谜题 / 环境处决（Tier3，滑后，不在此 Sprint）。

### 2.2 E11 SaveManager **数据层**（原 E01-S5，已剥离独立 epic）
> **裁决收口**：Sprint 2 只交**数据层**；**手动存档/读档 UI（槽管理 / 覆盖确认 / 缩略图）滑 Sprint 3**（§7.2）。
> **边界要点**：`write_slot()/read_slot()` 对手动槽 `0..2` 的 **API 与磁盘格式属数据层，Sprint 2 内落地并单测**（否则 S3 UI 无处可接）；滑出的只是**其上的 ⑧ UI 表现层**。

**Do**
- `SAVE_VERSION = 2` 字段化；**检查点滚动槽**（`CHECKPOINT_SLOT_ID = -1`）+ **手动 3 槽的数据结构与读写 API**（`MAX_MANUAL_SLOTS = 3`）。
- `restore_checkpoint()` 注入 ⑥ `patrol_ai._checkpoint_sink` seam（D9，**仅改 1 行**）——**软失败核心循环硬依赖，不可滑**。
- 偏好委托：`A11ySettings` 经 `save_prefs("a11y")/load_prefs` 落盘（替代直接 ConfigFile）——a11y 完整包依赖项。
- 异步落盘（不阻塞主线程）；版本不匹配/损坏 → 拒绝 + 错误态置位（**UI 呈现可在 S3 补，数据层先给出 `success:false`**）。
- 发 `save_completed`/`load_completed`/`checkpoint_restored`（**D16 已补录权威词汇表**）。

**Dont**
- **不做手动存档/读档 UI**（滑 S3）；不做云同步/自动备份（Tier2，滑后）；不做存档缩略图。
- 不破坏 minimal 已满足的 C4；不阻塞主线程 IO。
- 不新增玩法事件语义（`save_completed`/`load_completed`/`checkpoint_restored` 是 L2 扩展，非玩法信号）。

### 2.3 E09 a11y 完整包
> **裁决收口**：a11y **完整包全量留 Sprint 2**；唯一例外是 **S-E09-4「存档 UI 调 SaveManager」随手动存档 UI 滑 S3**。
> ⚠️ **保留项**：`load_completed → 淡入 + 应用全部 a11y 开关` 的**表现接线仍属 Sprint 2**（检查点恢复路径要用），并入 S-E09-3，勿随 UI 一起滑出。

**Do**
- `A11ySettings` 补全：`subtitles` 字段（原缺失）、`color_blind_mode` 升四态枚举（OFF/PROTAN/DEUTAN/TRITAN）、接入 SaveManager。
- 设置菜单 7 项控件：色盲下拉 / 时间滑杆(0.25) / 屏震关 / 雾 FULL·REDUCED·OFF / 动态模糊关 / 文本 100–150% / 字幕开。
- 表现接线：色盲 `#7A2E2E→#C8862F`+图标、脉动 ≤2Hz、文本不破版、字幕渲染；**含 `load_completed`/`checkpoint_restored` 后重应用全部开关**。
- ~~存档 UI 调 `SaveManager.write_slot/read_slot`~~ ➡️ **滑 S3**（§7.2）。

**Dont**
- 不新增事件词汇（开关经 L2 `A11ySettings` 直读，无需广播）；不破 C-01~C-07 / X-01/X-02 / V-01~V-06 / T-01/T-02；不破版（文本 ≤150%）；不引入新系统。

### 2.4 E08 守卫变体 ➡️ **已滑 Sprint 3**（FLAG-1 RESOLVED）
> **裁决：两款变体全滑 Sprint 3**（未采用「只留暗视哨兵」兜底方案）。以下 Do/Dont **原样保留为 Sprint 3 设计输入**，Sprint 2 不投人力、不开 Story。
> 词汇侧已预留：`guard_spawned` + `GuardVariant` 经 D16 补录进 `system-breakdown.md` §2（**S2 登记 / 未发出**，S3 激活），S3 无需再动权威表。

**Do**
- 变体以**参数/权重覆盖**实现（architecture §3.4）：`GuardBrain._init(variant)` 套 overlay。
- **循声猎犬**：`KV15/KS30`、听觉半径 ×1.6、锥 11m·30°。
- **暗视哨兵**：`vision_light_floor = 0.05` → `L_DARK=0.20` 阴影里仍 `vis≈0.5`（标准≈0）。
- 阈值 25/60/10、DECAY 8、GRACE 1.2s、≤10Hz **全部不变**；**零新事件**。

**Dont**
- 不新增 FSM 状态；不新增事件词汇；不做第三种变体（Tier3）；不破 G-01≤16 / G-04≤10Hz / V-02。

### 2.5 Tech Debt 基线（非阻塞）➡️ **已滑 Sprint 3**（FLAG-3 RESOLVED）
> **裁决：三项 Tech Debt 全滑 Sprint 3**。以下保留为 Sprint 3 输入；Sprint 2 不投人力。orphans 23 **不参与 N-7 门**，故不引入发布风险。

**Do**
- `hud_slice.gd` 相机引用治理（第 432 行 `get_viewport().get_camera_3d()` 的缓存/空判）。
- orphans 清理（~23，GUT 报告项，**不参与 N-7 门**）。
- `FOCUS_TINT` 治理（实为 `_dim`+`_set_world_boost` 染色逻辑、无独立常量 → 补注释/可选常量化）。

**Dont**
- 不重写 hud_slice；不扩大范围到新功能；**不因此阻塞发布**（用户已标非阻塞）。

---

## 3. 统一数值锚（全工作流引用此表，禁止另立数字）
| 维度 | 数值 | 来源/约束 |
| --- | --- | --- |
| 凝神 time_scale | **0.25**（钳 [0.1, 1.0]） | T-01/T-02 |
| 视野锥 | **35° / 14m / ≤10Hz** | G-03 |
| 光级 | **L_DARK 0.20 / L_BRIGHT 0.60** | ⑤ |
| 噪声 | **BASE 5.0 × surface × gait**（STONE1.0/GRASS0.7/METAL1.2/MOSS0.5） | ④ |
| 可疑度阈值 | **25 / 60 / 10**（SUSP/ALERT/RETURN） | ⑥ |
| 暴露宽限 | **GRACE_RT 1.2s**（真实时间） | ⑥/软失败 |
| 声环 | **≤8** | G-02 |
| 脉动 | **≤2Hz** | V-02 |
| 熄灯 ramp | **≤0.12 / ≤0.4s** | R-05 |
| FSM 决策 | **≤10Hz** | G-04 |
| 动态点光 | **≤12 / ≤32** | R-02 |
| 残影 | **≤6** | ① |
| 交互冷却 | **≥0.12s** | ① |
| 对比度 | **C-01 ≥4.5:1 / C-02 ≥7:1 / C-03 ≥3:1** | ⑧ |
| SaveManager | **SAVE_VERSION=2 / MAX_MANUAL_SLOTS=3 / CHECKPOINT_SLOT_ID=-1 / 单槽≤32KB / 检查点写冷却≥0.5s** | 本草案 |
| a11y 枚举 | **色盲 OFF/PROTAN/DEUTAN/TRITAN；雾 FULL/REDUCED/OFF；文本 100–150%** | ⑨ |
| 守卫变体 | **猎犬 KV15/KS30/半径×1.6/锥11m·30°；哨兵 vision_light_floor 0.05** | ⑧(E08) |

---

## 4. 进 / 出边界（裁决后 v0.2：Sprint 2 仅三件套）

### 4.1 Sprint 2 **进**（必交，In→Out）
| 工作流 | In（起点） | Out（Sprint 2 完成即验收） | 明确不做（滑 S3 / 不在范围） |
| --- | --- | --- | --- |
| **E07 互动物件实体级** | Sprint1 MVP 四类型 + D11 冻结信号 | 实体级：两类实体 / charges 双模型 / TRAP FSM / **smoke_factor 注入③（C3 解决）** / 存档快照对接（charges·light_states） | Tier3 机关谜题、环境处决 |
| **E11 SaveManager 数据层** | minimal SaveManager（仅 C4 内存态重生） | 完整**数据层**：`SAVE_VERSION=2` 版本化 / 检查点滚动槽 / 手动 3 槽**读写 API 与磁盘格式** / 偏好委托 / 异步落盘 / **`restore_checkpoint` 注入 ⑥ D9 seam（改 1 行）** / 3 事件广播 | **手动存档·读档 UI（槽管理/覆盖确认/缩略图）➡️S3**；云同步·自动备份（Tier2） |
| **E09 a11y 完整包** | E01-S6 接口骨架 + 默认值 | 完整包：`A11ySettings` 数据补全（subtitles / 四态色盲）+ 设置菜单 7 项 + 表现接线（对比度 C-01/02/03、脉动≤2Hz、文本≤150% 不破版、字幕）+ **`load_completed`/`checkpoint_restored` 后重应用开关** | **存档 UI 入口（S-E09-4）➡️S3**；新系统 / 新事件 |

### 4.2 Sprint 2 **出**（明确滑 Sprint 3，Sprint 2 零投入）
| 滑出项 | 原 FLAG | 滑出理由（一句话） | S3 接续起点 |
| --- | --- | --- | --- |
| E08 守卫变体（猎犬 / 哨兵） | FLAG-1 | Tier2「期望」非必做，纯参数覆盖加法，全滑不破核心循环与四支柱 | ⑥ 五态 FSM 已完成；`guard_spawned`/`GuardVariant` 词汇已预留 |
| 手动存档 / 读档 UI | FLAG-2 | 检查点自动持久化已满足软失败硬依赖，手动 UI 是便利功能 | E11 数据层 `write_slot/read_slot` API 已就位 |
| Tech Debt 基线（×3） | FLAG-3 | 用户已标非阻塞；orphans 23 不参与 N-7 门 | 三项 debt 位置已定位（§2.5） |

> **判定口径**：Sprint 2 验收只看 §4.1 三行的 Out 列；§4.2 三项**不计入 Sprint 2 退出标准**，其缺席不构成 Sprint 2 FAIL。

---

## 5. 依赖有序批次提案（裁决后 **3 批：A / B / C**，附 DAG 标注）
> 基础 DAG（架构）：`L2 → ② → ① → ⑤ → ③ → ④ → ⑦ → ⑥ → ⑧`。Sprint 2 在其上叠加 L2 服务补全与既有系统扩展。
> **变更说明**：原 4 批中的 Batch 3「E08 变体」与 Batch 4「Tech Debt」随裁决滑出；原 Batch 4 的 **QA 门不滑**，并入 Batch C 收尾。

**Batch A — 存档基座（Foundation · E11 + a11y 数据侧）**
- **E11 SaveManager 数据层**：数据模型 / `SAVE_VERSION=2` 版本化 / 检查点滚动槽 / 手动 3 槽读写 API / 异步落盘 / **restore 注入 ⑥ D9 seam（改 1 行）** / 3 事件广播。
- E09 数据侧：`A11ySettings` 补全（subtitles / 四态色盲枚举）+ 接入 SaveManager 偏好委托。
- 依赖：无上游（L2 基座）；**解锁** Batch B 的快照对接与 Batch C 的偏好持久化。
- 退出：save round-trip 单测 PASS + `restore_checkpoint` 经 `_checkpoint_sink` 打通 + 版本拒绝单测 PASS。

**Batch B — 互动物件实体级（E07）**
- ⑦ 实体化：两类实体 / charges 双模型 / TRAP FSM / **smoke_factor 注入③（C3 解决）** / 存档快照对接（`interactable_charges`·`light_states`）。
- 依赖：L2 EventBus（Sprint1 已有）+ ④/⑤/⑥ 消费者（Sprint1 已完成）；快照对接依赖 **Batch A 数据模型**。
- 退出：四类型实体可触发、charges 消耗与 SPENT 表现、烟雾降可见性（`vis=base×cover×smoke`）、**零新事件**、charges/灯态可存可还原。

**Batch C — a11y 表现层 + 整合 / QA 门**
- E09 表现层：设置菜单 7 项 + 表现接线（色盲 / 时间 / 雾 / 模糊 / 文本 / 字幕）+ **`load_completed`·`checkpoint_restored` 后重应用全部开关**。
- 全 Sprint 整合 + **完整 QA 门**（设计评审 + QA 计划 + 烟雾/回归 + 控制清单卡门，见 §8）。
- 依赖：Batch A（偏好委托落盘）、⑧ 读全系统（Sprint1 完成）；与 Batch B 无强耦合。
- 退出：a11y 开关全生效，C-01≥4.5 / C-02≥7 / C-03≥3、脉动≤2Hz、文本≤150% 不破版；**五退出标准全 PASS**（类比 Sprint1）。

> **并行提示**：Batch B（E07）与 Batch C 前半（a11y 表现）分属 ⑦ / ⑧，在 Batch A 数据层落地后**可并行启动**；Batch C 的 QA 门必须最后收。排期由主理人按人力拍板。
> **不再有 Batch 4**：Tech Debt 已滑 S3；原属其中的 QA 门责任已并入 Batch C，**QA 强度不因批次合并而下降**。

---

## 6. 范围纪律自查（四支柱 / 无新增系统 / 无漂移）
| 检查项 | 结果 |
| --- | --- |
| 四支柱映射（S2 三件套各服务≥1支柱） | ✅ E07→三/一；E11→一/三；E09→二/三 |
| **滑期后支柱覆盖仍完整** | ✅ 滑出的 E08 服务「一/四」，但支柱一由 E11 检查点/软失败承接、支柱四由 Sprint1 既有五态 FSM + ⑤ 光影承接，**四支柱在 S2 内均有活跃载体，无支柱悬空** |
| 无新增平行机制大类 | ✅ SaveManager=L2 补全（**E11 仅为 epic 拆分，非新系统**）；E07/E09=既有系统参数/数量扩展 |
| 支柱漂移 | ❌ 未触发（无反向违背任一支柱的设计） |
| 跨 GDD 事件词汇无漂移 | ✅ D16 已补录 4 事件入权威表：S2 生效 3 个（save/load/checkpoint_restored）+ `guard_spawned` **登记未发出**（S3 激活）；E08 变体**零新事件**（参数覆盖） |
| 性能预算引用自洽 | ✅ 数值锚（§3）与 control-manifest/架构完全一致 |
| 范围纪律红线（单核心做极致） | ✅ S2 三件套均属「同一核心（潜行循环）的纵深」，非平行铺开；**滑期进一步收紧至单核心** |

---

## 7. Sprint 3 候选（原 FLAG-1/2/3 — **全部已裁决滑出，RESOLVED**）★关键交付
> **主理人裁决（本次收口）**：三项 FLAG **全部滑 Sprint 3**，不再是「建议/触发条件」而是**已生效的范围决定**。触发条件段已失效并归档。
> Sprint 2 必交基线 = **E07 实体级 + E11 SaveManager 数据层 + E09 a11y 完整包**。

| FLAG | 项目 | 裁决 | 状态 |
| --- | --- | --- | --- |
| FLAG-1 | E08 守卫变体（猎犬 / 哨兵） | **两款全滑 S3**（未采用只留哨兵的兜底） | ✅ **RESOLVED** |
| FLAG-2 | 手动存档 / 读档 UI | **滑 S3**；数据层留 S2 | ✅ **RESOLVED** |
| FLAG-3 | Tech Debt 基线（×3） | **全滑 S3** | ✅ **RESOLVED** |

### 7.1 FLAG-1 ✅ RESOLVED — E08 守卫变体（循声猎犬 / 暗视哨兵）➡️ Sprint 3
- **裁决**：**两款变体全部滑 Sprint 3**；Sprint 2 不开 Story、不投人力。原「只留暗视哨兵」兜底方案**未被采用**，特此归档。
- **理由（留档）**：属 Tier2「期望」非「必做」；纯参数/权重覆盖加法（architecture §3.4），依赖 ⑥ 已完成；全滑不破核心潜行循环与四支柱。
- **S3 接续起点**：⑥ 五态 FSM + 连续可疑度已就绪；`guard_spawned` + `GuardVariant` 已随 D16 预登记于 `system-breakdown.md` §2（S2 未发出），**S3 无需再改权威词汇表**。
- **S3 需重验**：暗视哨兵 `vision_light_floor=0.05` 与 Sprint 2 新落地的 **E07 烟雾 `smoke_factor=0.3`** 的叠乘效果（`vis=base×cover×smoke`，哨兵在烟中是否仍过强）——S2 完成后此组合才首次可测。

### 7.2 FLAG-2 ✅ RESOLVED — 手动存档/读档 UI（槽管理/覆盖确认/缩略）➡️ Sprint 3
- **裁决**：**UI 层滑 Sprint 3**；**E11 SaveManager 数据层留在 Sprint 2**（它是软失败基座，不可滑）。
- **S2/S3 切割线（重要）**：
  - **留 S2**：`write_slot()/read_slot()` API + 手动槽 `0..2` 磁盘格式 + 版本/损坏拒绝（返回 `success:false`）+ `save_completed`/`load_completed` 广播 + 检查点全链路。
  - **滑 S3**：暂停菜单槽列表 UI、覆盖确认弹窗、缩略图占位、错误提示的 ⑧ 视觉呈现（对应 `S-E09-4`）。
- **理由（留档）**：检查点自动持久化 + `restore_checkpoint` 注入 ⑥（D9）+ a11y 偏好持久化已满足软失败核心循环硬依赖；手动 UI 是便利功能。

### 7.3 FLAG-3 ✅ RESOLVED — Tech Debt 基线（hud_slice 相机 / ~23 orphans / FOCUS_TINT）➡️ Sprint 3
- **裁决**：三项**全滑 Sprint 3**，Sprint 2 零投入。
- **理由（留档）**：用户已标「**非阻塞**」；orphans 23 明确不参与 N-7 门（`batchd-qa-plan.md`），滑出**不引入发布风险**。
- **S3 接续起点**：三处位置已定位（`hud_slice.gd` 第 432 行相机引用 / GUT orphans 报告项 / `_dim`+`_set_world_boost` 染色逻辑），详见 §2.5。
- **遗留待裁**：`FOCUS_TINT` 治理粒度（仅注释 vs 常量化入 `hud_colors.gd`）随本项一并移至 Sprint 3 决策（原 §9.3）。

### 7.4 Sprint 3 候选汇总（交接清单）
| # | 候选项 | 来源 | 规模（设计估） | S3 前置 |
| --- | --- | --- | --- | --- |
| 1 | E08 守卫变体 ×2（S-E08-1~4） | FLAG-1 | S×4 | ⑥ 已就绪；词汇已预留 |
| 2 | 手动存档/读档 UI（槽管理/覆盖确认/缩略） | FLAG-2 | S~M | E11 数据层（S2 交付） |
| 3 | 存档 UI 入口接线（S-E09-4） | FLAG-2 | S | 同上 |
| 4 | Tech Debt ×3（S-TD-1~3） | FLAG-3 | S/M/S | 无 |
| 5 | `guard_spawned` 实际广播 + ⑧ 变体剪影 | D16 预留 | S | 随 #1 |

> **不在范围（S2/S3 均不评估）**：SaveManager Tier2 云同步/自动备份、E07 Tier3 机关谜题/环境处决、第三守卫变体、照片模式 UI——均属 Tier2/Tier3 滑后项。

---

## 8. 评审门对齐（沿用 Sprint 1 五退出标准）
| 退出标准 | Sprint 2 落点 |
| --- | --- |
| ① 设计评审 PASS | 本 scope v0.2 + `consistency-review.md`（**D16 已补录、C4 已解决**，见其 §5） |
| ② QA 计划 | `batchd-qa-plan.md` 增补 Sprint2 条目（save round-trip、版本拒绝、a11y 对比度断言）；**变体参数断言随 E08 移 S3** |
| ③ 烟雾/回归 | GUT 维持 95/95；新增 SaveManager round-trip / 版本拒绝 / prefs 委托、smoke_factor 注入单测；**变体参数单测移 S3** |
| ④ 控制清单卡门 | `control-manifest.md` §7 CI 断言（N-7 等）；orphans 23 不参与 N-7（**Tech Debt 滑 S3 不影响此门**） |
| ⑤ 文档齐 | 本交付物集（scope v0.2 + GDD 编辑 + story 候选 S2/S3 标注 + `system-breakdown.md` §2 D16 补录 + consistency 更新） |

---

## 9. 裁决记录与剩余开放项

### 9.1 已裁决（本次收口，CLOSED）
| # | 原开放项 | 裁决结果 | 落点 |
| --- | --- | --- | --- |
| 1 | FLAG-2：手动存档 UI 去留 | **UI 滑 S3，数据层留 S2** | §7.2 / §4 |
| 2 | FLAG-1：守卫变体两款/只留哨兵/全滑 | **两款全滑 S3** | §7.1 / §4.2 |
| — | FLAG-3：Tech Debt | **全滑 S3** | §7.3 |
| — | SaveManager epic 归属 | **新立独立 epic E11**（从 E01 剥离） | §1 |
| — | **D16**：4 新事件是否入权威词汇表 | **正式补录** `system-breakdown.md` §2（+ §2.3 类型 `GuardVariant`） | `system-breakdown.md` §2 / `consistency-review.md` §5 |

### 9.2 剩余开放项（不影响 Sprint 2 启动，可后置）
1. **检查点密度 × GRACE_RT 终值**：需 playtest 调参（概念取舍 #2），现用 **1.2s**。**建议在 Sprint 2 Batch A 完成后即刻可测**（检查点链路一通就能量化挫败度）。
2. **a11y 文本缩放上限**：现取 **150%**（X-01 [1.0,1.5]），若需更高须重评破版风险。
3. ~~FOCUS_TINT 治理粒度~~ ➡️ 随 FLAG-3 移交 Sprint 3 决策（§7.3）。

---
*Sprint 2 设计规划 **v0.2（已收口）** — 文策渊。结论：裁决后 Sprint 2 = **三件套必交**（E07 实体级 / E11 SaveManager 数据层 / E09 a11y 完整包），**3 批依赖有序（A 存档基座 → B 互动物件 → C a11y + QA 门）**，FLAG-1/2/3 全部 RESOLVED 并移入 §7.4 Sprint 3 候选，D16 已补录权威词汇表。范围纪律 PASS，四支柱无悬空。可进入逐 Story 排期。*
