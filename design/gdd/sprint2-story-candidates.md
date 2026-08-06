# Sprint 2 Story 候选（按工作流）
**《灰烬之步》ASHEN STEP · 设计策略师 文策渊 · 粗略候选，供主理人排期**

> 说明：以下为**粗略 Story 候选**，T 恤尺寸（S/M/L）、依赖、Given-When-Then 验收草样均出自设计视角，供 Sprint 规划会细化。Story 编号沿用 Epic 前缀（E07/**E11**/E09/E08）+ Sprint2 后缀；Tech Debt 用 TD 前缀。**不写入 `production/sprints/`**，仅作规划输入。
> 对齐：`design/reviews/sprint2-design-scope.md` §5 批次（**裁决后 3 批 A/B/C**）、`design/gdd/systems/*.md`（含 `save-system.md`）。

---

## 📌 裁决后 S2 / S3 划分总表（主理人已拍板）
> **Sprint 2 必交** = E07 实体级 + **E11 SaveManager 数据层** + E09 a11y 完整包。
> **滑 Sprint 3** = E08 守卫变体（全部）+ 手动存档/读档 UI + Tech Debt（全部）。
> **每条 Story 已在下方各表首列标注 `S2` / `S3`。**

| 归属 | Story | 合计 |
| --- | --- | --- |
| **S2（必交，13 条）** | S-E07-1~6（6）、S-E11-1/2/4/5（4）、S-E09-1/2/3（3） | **13** |
| **S3（滑期，10 条）** | S-E11-3（手动槽 UI）、S-E09-4（存档 UI）、S-E08-1~4（4）、S-TD-1~3（3） | **10** |

> ⚠️ **两处「拆条」提醒（非整条滑动，规划会须留意）**：
> 1. **S-E11-3** 原含「手动 3 槽写入/读取 + 覆盖确认」——**数据层 API（`write_slot/read_slot` 对槽 0..2 + 磁盘格式）已上提至 S2 的 S-E11-1**，滑 S3 的仅剩**槽管理 UI + 覆盖确认弹窗**。
> 2. **S-E09-4** 原含「读档完成 `load_completed` → 淡入并应用 a11y 开关」——**该表现接线留 S2（并入 S-E09-3）**，因检查点恢复路径需要；滑 S3 的仅剩**存档 UI 入口本身**。

---

## Epic 编号变更（主理人裁决）
**SaveManager 从 E01 剥离，新立独立 epic `E11`。** 原 `S-E01-5a~5e` 相应改号为 `S-E11-1~5`（下表括号内保留原号以便追溯）。此为组织层面拆分，**不改变系统边界、不新增系统大类**，GDD 仍为 `design/gdd/systems/save-system.md`。

> ✅ **交付面已落地**：`production/epics/E11-save-manager.md` 已由交付流程创建（v1.0，story 编号 `SAV-S1~S6`），并已在 `production/sprints/sprint2-stories.md` 排期。**排期/验收以交付侧编号为权威**，本文编号仅作设计追溯——对照表见下方 §B。
> `E01-S8` NavServer 不受本次剥离影响（仍归 E01，仍为 seam 占位）。

---

## A. E07 互动物件实体级（对应 scope §2.1 / §5 **Batch B**）— **整组 S2 必交**
| 归属 | Story | 标题 | 尺寸 | 依赖 | Given-When-Then（草样） |
| --- | --- | --- | --- | --- | --- |
| **S2** | **S-E07-1** | 实体分类 + charges 双模型 | M | L2 EventBus | **Given** 四类互动物件存在；**When** 世界物件/携带物件分别计 charges；**Then** `charges==0` 进入 SPENT 且不可触发（视觉降饱和）。 |
| **S2** | **S-E07-2** | 玩家携带背包 entity-inventory | M | — | **Given** 玩家持有 DECOY/SMOKE 槽；**When** 选中并使用；**Then** `charges-1`、HUD 显示剩余、归零后槽置灰。 |
| **S2** | **S-E07-3** | TRAP 内部 FSM | S | S-E07-1 | **Given** TRAP 布设；**When** 触发；**Then** 发 `interactable_triggered(id,TRAP,payload)` 且 `charges>0?ARMED:SPENT`。 |
| **S2** | **S-E07-4** | 烟雾 smoke_factor 注入③（解决 C3） | M | ③ vision_cone | **Given** 烟雾弹落点；**When** 生效期内；**Then** ③ `compute_visibility` 乘 `smoke_factor=0.3`、半径内线性衰减、≈4s 后失效。 |
| **S2** | **S-E07-5** | 世界物件交互完善（LIGHT_TOGGLE state/charges） | S | S-E07-1 | **Given** 可熄灯；**When** 互动键；**Then** `state.lit` 翻转 + 发 `light_state_changed` + R-02 仍计。 |
| **S2** | **S-E07-6** | 存档快照对接（charges/light_states） | S | **S-E11-1**（数据模型，S2） | **Given** 运行时 charges/灯态变化；**When** 检查点写入（**手动存亦经同一 API**）；**Then** `interactable_charges`/`light_states` 写入、读档还原。 |

> **S-E07-6 依赖说明**：仅依赖 **S-E11-1 数据模型 + 读写 API（S2 内交付）**，**不**依赖已滑 S3 的手动存档 UI。验收走检查点路径 + `write_slot/read_slot` 单测即可，不被滑期阻塞。

---

## B. **E11 SaveManager 数据层**（原 E01-S5，对应 scope §2.2 / §5 **Batch A**）— 4 条 S2 + 1 条 S3
| 归属 | Story（原号） | 标题 | 尺寸 | 依赖 | Given-When-Then（草样） |
| --- | --- | --- | --- | --- | --- |
| **S2** | **S-E11-1**（原 5a） | 完整数据模型 + SAVE_VERSION 字段化 + **槽读写 API** | M | — | **Given** `SaveSlot` 结构与 `write_slot/read_slot`（覆盖检查点槽 `-1` 与手动槽 `0..2`）；**When** 写入；**Then** `version=2`、单槽 ≤32KB、JSON 落 `user://saves/`、round-trip 单测 PASS。 |
| **S2** | **S-E11-2**（原 5b） | 检查点滚动槽 + restore 注入 D9 seam | M | ⑥ patrol_ai | **Given** 玩家入检查点区；**When** 软失败；**Then** `_checkpoint_sink`→`SaveManager.restore_checkpoint`（改 1 行），可疑度清零、守卫回 RETURN、发 `checkpoint_restored(checkpoint_id)`。 |
| **S3** | **S-E11-3**（原 5c）➡️**滑 S3** | **手动槽管理 UI + 覆盖确认**（数据层 API 已上提至 S-E11-1） | S~M | S-E11-1（S2 已交） | **Given** 暂停菜单存档界面；**When** 选槽写入/读档；**Then** 非空槽二次确认弹窗、槽列表显示时间戳/检查点 id/缩略占位。 |
| **S2** | **S-E11-4**（原 5d） | 偏好委托 A11ySettings | S | S-E09-1 | **Given** 设置变更；**When** 退出/即时；**Then** `save_prefs("a11y",dict)` 落盘、启动 `load_prefs` 恢复；迁移旧 a11y.cfg。 |
| **S2** | **S-E11-5**（原 5e） | 异步落盘 + 版本/损坏保护 | S | S-E11-1 | **Given** 写盘；**When** `version!=2` 或 JSON 损坏；**Then** 异步完成发 `save_completed(slot_id,success)`、**拒绝并置 `success:false`**（UI 呈现随 S-E11-3 滑 S3）。 |

> **S2/S3 切割线**：数据层（结构 / 版本化 / 读写 API / 异步 / 检查点全链路 / 3 事件广播）**全部 S2**；仅 **⑧ UI 呈现面**滑 S3。这样 S3 接手时无需回改数据层。
> **事件对齐**：`save_completed` / `load_completed` / `checkpoint_restored` 参数以 `systems/save-system.md` §4 为权威，已随 **D16** 补录 `system-breakdown.md` §2.1。

#### ⚠️ 编号对照：本文 `S-E11-x`（设计侧）↔ `SAV-Sx`（交付侧权威）
> **交付面已先行落编号**：`production/epics/E11-save-manager.md` 与 `production/sprints/sprint2-stories.md` 已采用 **`SAV-S1~S6`**，粒度比本设计草案更细（把「数据模型」与「读写 API/异步」拆开）。
> **权威归属**：**排期与验收以交付侧 `SAV-Sx` 为准**；本表的 `S-E11-x` 仅为设计侧规划输入，保留以追溯原 `S-E01-5x`。**两套编号的 S2/S3 划分完全一致，无实质冲突。**

| 本文（设计侧） | 交付侧权威 | 归属 | 备注 |
| --- | --- | --- | --- |
| S-E11-1（原 5a） | **SAV-S1** + **SAV-S2** | S2 | 交付侧把「数据模型/版本前置」与「`write_slot`/`read_slot` API + 异步落盘」拆为两条 |
| S-E11-2（原 5b） | **SAV-S3** | S2 | D9 seam 注入，交付侧标 ★FLAG-A 高风险 |
| S-E11-3（原 5c） | **SAV-S5** | **S3** | 手动存档/读档 UI，两侧一致滑期 |
| S-E11-4（原 5d） | **SAV-S4** | S2 | 偏好委托 + `a11y.cfg` 一次性迁移 |
| S-E11-5（原 5e） | **SAV-S2**（异步）+ **SAV-S6**（版本拒绝/损坏） | S2 | 交付侧按「异步」与「拒绝路径」分列 |

> ✅ **交叉校验通过**：交付侧「Sprint 2 = SAV-S1/S2/S3/S4/S6，Sprint 3 = SAV-S5」与本文 S2/S3 划分**逐条吻合**；批次命名 **Batch A/B/C** 亦与 scope §5 一致。

---

## C. E09 a11y 完整包（对应 scope §2.3 / §5 **Batch A 数据侧 + Batch C 表现侧**）— 3 条 S2 + 1 条 S3
| 归属 | Story | 标题 | 尺寸 | 依赖 | Given-When-Then（草样） |
| --- | --- | --- | --- | --- | --- |
| **S2** | **S-E09-1** | A11ySettings 数据补全 | S | — | **Given** 当前仅接口骨架；**When** 补全；**Then** `subtitles:bool`、`color_blind_mode:枚举(OFF/PROTAN/DEUTAN/TRITAN)` 存在。 |
| **S2** | **S-E09-2** | 设置菜单 7 项控件 | M | S-E09-1 | **Given** 暂停菜单；**When** 打开设置；**Then** 色盲下拉/时间滑杆(0.25)/屏震关/雾三态/动态模糊关/文本100–150%/字幕开 均可操作。 |
| **S2** | **S-E09-3** | 表现接线（色盲/时间/雾/模糊/文本/字幕）**+ 恢复后重应用开关** | L | S-E09-2, ③⑤着色器, S-E11-2 | **Given** 开关变更**或 `load_completed`/`checkpoint_restored` 到达**；**When** 应用；**Then** 色盲 `#D64545→#F0C070`+**实心三角**图标、脉动≤2Hz、文本≤150%不破版、字幕渲染、雾/模糊生效；对比度 C-01≥4.5/C-02≥7/C-03≥3。 |
| **S3** | **S-E09-4** ➡️**滑 S3** | 存档 UI 入口调 SaveManager | S | S-E11-3（S3） | **Given** 设置菜单存档入口；**When** 点击；**Then** 调 `write_slot/read_slot` 并呈现结果/错误提示。 |

> **更正说明（S3-B 残留收口 · C-06 现行口径 · 林绘澄签字）**：S-E09-3 原文「色盲 `#7A2E2E→#C8862F`」**已作废**。根因：警戒 CAUTION **本就是** `#C8862F`，该映射令警戒与警报**亮度比塌缩至 1.00:1**，C-05 三重编码中的「亮度」维度彻底失效 —— 等于**在无障碍规格内部犯 C-05**。**现行口径 = `#D64545` → `#F0C070`**（vs 警戒 `#C8862F` = **1.81:1**；vs 面板 `#1B1B1F` = **10.20:1**，连 C-02 都过）。依据 `design/art/art-bible.md` **v0.4** §9.1 / `design/art/accessibility-matrix.md` §3.1「警报 ALARM 语义色（色盲 C-06）」行。
> **另**：源码常量 **`HUD_COLOR_ALARM_CB` 已退休**，由 **`HUD_COLOR_DANGER_CB`**（`#F0C070`）取代（S3-B 落地）；**脉冲 2.0Hz 双拍 + 实心三角图标常驻生效，不随色盲开关切换**。

> ⚠️ **拆条提醒**：原 S-E09-4 的「读档完成 `load_completed` → 淡入并应用全部 a11y 开关」**已上提到 S-E09-3（S2）**——检查点恢复路径（S-E11-2，S2 交付）会触发它，不能随 UI 一起滑走。滑 S3 的仅为**存档 UI 入口本身**。

---

## D. E08 守卫变体（对应 scope §2.4 / §7.1）— ➡️ **整组滑 Sprint 3（FLAG-1 RESOLVED）**
> **裁决：两款变体全滑 S3**，Sprint 2 不开 Story、不投人力。「只留暗视哨兵」兜底方案未被采用。
> 词汇已预留：`guard_spawned` + `GuardVariant` 经 **D16** 补录 `system-breakdown.md` §2（S2 登记未发出），**S3 无需再改权威表**。

| 归属 | Story | 标题 | 尺寸 | 依赖 | Given-When-Then（草样） |
| --- | --- | --- | --- | --- | --- |
| **S3** | **S-E08-1** | 变体覆盖机制 + 枚举 | S | ⑥ | **Given** `GuardVariant` 枚举（`STANDARD/HOUND/NIGHTEYE`，已登记 §2.3）；**When** `GuardBrain._init(variant)`；**Then** 套 overlay，阈值/衰减/宽限不变，**零新事件**。 |
| **S3** | **S-E08-2** | 循声猎犬参数 | S | S-E08-1, ④ | **Given** 猎犬实例；**When** 脚步/诱饵声入范围；**Then** `KV15/KS30`、听觉半径×1.6、锥11m·30° 生效。 |
| **S3** | **S-E08-3** | 暗视哨兵参数 | M | S-E08-1, ③ | **Given** 哨兵在 `L_DARK=0.20` 阴影；**When** 玩家进入；**Then** `vision_light_floor=0.05`→`vis≈0.5`（标准≈0）。 |
| **S3** | **S-E08-4** | HUD 变体剪影 + `guard_spawned` 实际广播 | S | S-E08-1, ⑧ | **Given** 变体守卫生成；**When** 渲染；**Then** ⑧ 依 `variant` 绘差异化剪影（姿态/形状，非颜色）；优先走 `guard_fsm_changed` 快照，必要时启用 `guard_spawned`。 |

> **S3 新增验证项**：暗视哨兵 `vision_light_floor=0.05` × Sprint 2 新落地的 **E07 烟雾 `smoke_factor=0.3`** 的叠乘平衡（`vis=base×cover×smoke`）——S2 完成后才首次可测，S3 需专门回归（见 scope §7.1）。

---

## E. Tech Debt 基线（对应 scope §2.5 / §7.3）— ➡️ **整组滑 Sprint 3（FLAG-3 RESOLVED，非阻塞）**
> **裁决：三项全滑 S3**，Sprint 2 零投入。orphans 23 **不参与 N-7 门**，滑出不引入发布风险。

| 归属 | Story | 标题 | 尺寸 | 依赖 | Given-When-Then（草样） |
| --- | --- | --- | --- | --- | --- |
| **S3** | **S-TD-1** | hud_slice 相机引用治理 | S | — | **Given** 第432行 `get_camera_3d()`；**When** 相机切换/空；**Then** 缓存引用 + 空判，无空引用崩溃。 |
| **S3** | **S-TD-2** | orphans 清理（~23） | M | — | **Given** GUT 报 ~23 orphans；**When** 清理；**Then** 报告项下降、**不参与 N-7 门**（不阻断）。 |
| **S3** | **S-TD-3** | FOCUS_TINT 治理 | S | — | **Given** 染色逻辑在 `_dim`/`_set_world_boost`（无独立常量）；**When** 治理；**Then** 补注释/可选常量化入 `hud_colors.gd`，行为不变。**治理粒度（仅注释 vs 常量化）待 S3 裁决**。 |

---

## 尺寸汇总与排期提示（裁决后）

### Sprint 2 必交（13 条）
| 工作流 | S | M | L | 总计 | 批次 |
| --- | --- | --- | --- | --- | --- |
| **E07** 互动物件实体级 | 3 | 3 | 0 | **6** | **Batch B** |
| **E11** SaveManager 数据层 | 2 | 2 | 0 | **4** | **Batch A** |
| **E09** a11y 完整包 | 1 | 1 | 1 | **3** | Batch A（数据侧 S-E09-1）+ **Batch C**（表现侧） |
| **S2 合计** | **6** | **6** | **1** | **13** | A → B → C |

### Sprint 3 候选（10 条，不计入 Sprint 2 基线）
| 工作流 | S | M | L | 总计 | 来源 |
| --- | --- | --- | --- | --- | --- |
| E08 守卫变体 | 3 | 1 | 0 | **4** | FLAG-1 |
| 手动存档 UI（S-E11-3 + S-E09-4） | 1 | 1 | 0 | **2** | FLAG-2 |
| Tech Debt | 2 | 1 | 0 | **3** | FLAG-3 |
| `guard_spawned` 广播（含于 S-E08-4） | — | — | — | （并入 E08） | D16 预留 |
| **S3 合计** | **6** | **3** | **0** | **9~10** | — |

> **T 恤尺寸仅设计估算**，工程估点以 Sprint 规划会为准。
> **Sprint 2 退出标准只核验上表 13 条 S2 Story**；S3 组缺席**不构成 Sprint 2 FAIL**（scope §4.2）。
> **排期建议**：Batch A（S-E11-1/2/4/5 + S-E09-1）为唯一强前置，务必先收；Batch B 与 Batch C 可并行。
