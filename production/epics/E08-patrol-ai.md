# Epic E08 · 巡逻 AI 与可疑度 FSM（patrol-ai）

- **对应 GDD**：`design/gdd/systems/patrol-ai.md`（GDD ⑥）
- **层**：L3 AI 层（架构 §2）
- **依赖**：E05（vision_stimulus）、E06（sound_emitted）、E02（tick 用真实时间）、E01（NavServer / Grid / EventBus / SaveManager）
- **DAG 优先级**：P3（依赖 E05 视野 + E06 声音）
- **MoSCoW**：**Must** ｜ **T 恤**：L
- **上游**：概念 §3⑤（巡逻 AI）/§4；ADR-002（FSM 5–10Hz、A* 仅状态转换）；control-manifest G-01/G-04/G-05、C-02/C-06/C-07、V-02/V-03；art-bible §4.1

## 目标
守卫 FSM `CALM→SUSPICIOUS→ALERT→SEARCH→RETURN`；可疑度连续条非二进制；暴露是可见的升级（梯度），给玩家时间补救/重规划，非瞬死（支柱一 步步为营 暴露可恢复 / 支柱四 肃穆压迫 渐升警戒）。

## 范围（In Scope）
- `GuardBrain` FSM + 连续可疑度 S∈[0,100]，阈值 SUSPICIOUS≥25/ALERT≥60/RETURN<10。
- 累积/衰减（决策 5–10Hz，G-04）：`dS/dt = vision_vis×KV(35) + sound×KS(15) − (stimulus?0:decay(8))`。
- 暴露梯度：ALERT + 持续可见累计 **宽限 1.2s（真实时间）** → `exposure_detected` → 软失败（检查点重生，C4）。
- A* 仅状态转换触发并缓存（G-05）；`guard_transform_dirty` 触发 E05 重算。
- 守卫变体（猎犬/哨兵，参数覆盖）、姿态可读（art §4.1）。

## 关键 Story 列表

> **Sprint 2 滑期标注（主理人裁决 1）**：守卫变体相关 Story **E08-S7 / E08-S9 / E08-S10 滑到 Sprint 3**（详见 `production/sprints/sprint2-stories.md` §2 S3-A）。其余 E08-S1~S6、E08-S8 留 Sprint 1/Sprint 2 不变。变体参数覆盖（猎犬 KV15/KS30/感知半径×1.6/锥 11m·30°、哨兵 vision_light_floor=0.05）仍复用 `GuardBrain`，不新增系统。

### E08-S1 · 作为（系统）我要（守卫按五态 FSM 运行）以便（暴露是梯度非瞬死）
**Sprint 0**：否（Sprint 1；Sprint 0 仅占位，由 E05 单锥静态检测驱动）
**验收**
- Given patrol-ai §2「FSM：CALM→SUSPICIOUS→ALERT→SEARCH→RETURN」；概念 §3⑤「暴露极少瞬间即死，是可见升级」。
- When 可疑度跨阈值。
- Then FSM 在 CALM/SUSPICIOUS/ALERT/SEARCH/RETURN 间按阈值转换；状态靠姿态+道具非颜色（art §4.1）。
**关联**：patrol-ai §2/§5；concept §3⑤；art-bible §4.1；control-manifest C-05（非颜色）。

### E08-S2 · 作为（系统）我要（维护连续可疑度并跨阈值）以便（玩家读出还差多少被发现）
**Sprint 0**：否（Sprint 1）
**验收**
- Given patrol-ai §2「S∈[0,100]；THR_SUSP=25、THR_ALERT=60、THR_RETURN=10」。
- When 累加/衰减可疑度。
- Then S 连续变化；≥25→SUSPICIOUS、≥60→ALERT、<10→RETURN；HUD 显示数值+图标（C-02）。
**关联**：patrol-ai §2/§3；core-hud-a11y §5（可疑度条）；control-manifest C-02。

### E08-S3 · 作为（系统）我要（5–10Hz 节流决策）以便（成本随 tick 非帧率）
**Sprint 0**：否（Sprint 1）
**验收**
- Given ADR-002「FSM 决策 5–10Hz」；control-manifest G-04「≤10Hz」。
- When 守卫决策 tick。
- Then 决策频率 ≤10Hz（真实时间，不随 time_scale，ADR-002/003）；慢放下仍 5–10Hz。
**关联**：ADR-002；control-manifest G-04；architecture §4（FSM 决策 5–10Hz）。

### E08-S4 · 作为（玩家）我要（暴露有 1.2s 宽限可自救）以便（失误变重规划机会）
**Sprint 0**：否（Sprint 1；断言桩见 `tests/unit/test_step_commit.gd`）
**验收**
- Given patrol-ai §2「ALERT 且目标持续 visibility>0 累计宽限 1.2s（真实时间）→ exposure_detected → 软失败：最近检查点重生、可疑度清零、守卫回 RETURN/巡逻（C4）」；consistency-review C4。
- When 守卫 ALERT 且玩家持续可见。
- Then 累计真实时间达 1.2s → 发 `exposure_detected(guard_id, target)` → 软失败（经 E01 SaveManager 检查点重生）；宽限期内玩家断 LOS/熄灯/诱饵降 S 可自救。
- Then 断言：ALERT+可见 1.0s 不触发，1.2s 触发（见 `tests/unit/test_step_commit.gd::test_exposure_grace_1_2s_triggers_soft_fail`）。
**关联**：patrol-ai §2/§3；consistency-review C4；E11（SaveManager）；control-manifest（无编号，属 GDD ⑥）。

### E08-S5 · 作为（系统）我要（A* 仅状态转换触发并缓存）以便（寻路非逐帧）
**Sprint 0**：否（Sprint 1）
**验收**
- Given ADR-002「A* 寻路仅状态转换（CALM→ALERT/SEARCH）触发并缓存，非逐帧」；control-manifest G-05。
- When FSM 进入 ALERT/SEARCH。
- Then 经 E01 NavServer 发起 `NavigationAgent3D` 寻路并缓存路径；非逐帧调用。
**关联**：ADR-002；control-manifest G-05；E01-S8。

### E08-S6 · 作为（E09）我要（发出可疑度/FSM/暴露/transform 信号）以便（HUD 与视野联动）
**Sprint 0**：否（Sprint 1）
**验收**
- Given system-breakdown §2「suspicion_changed(guard_id,value,tier)、guard_fsm_changed(guard_id,old,new)、exposure_detected(guard_id,target)、guard_transform_dirty(guard_id)」。
- When 上述状态变更。
- Then 对应信号发射；`guard_transform_dirty` → E05 视野重算（ADR-002 事件驱动）。
**关联**：system-breakdown §2；patrol-ai §4；vision-cone（guard_transform_dirty）。

### E08-S7 · 作为（设计）我要（守卫变体猎犬/哨兵）以便（Tier2 增加解法维度）
**Sprint 2**：否 → **Sprint 3**：滑期（主理人裁决 1，守卫变体延期）
**验收**
- Given patrol-ai §8「循声猎犬（听觉优先，降视觉权重）、暗视哨兵（暗处仍可见，降 L 阈值）；复用 FSM+参数覆盖（architecture §3.4）不新增系统」。
- When 变体实例化。
- Then 仅权重/阈值覆盖（KV/KS、L_DARK 阈值）；复用 E08 FSM；不新增系统/机制族。
**关联**：patrol-ai §8；vision-cone §8；architecture §3.4（变体参数）；concept §5（Tier2 变体）。

### E08-S8 · 作为（玩家）我要（靠姿态读守卫状态）以便（三类色盲 100% 可读）
**Sprint 0**：否（Sprint 1）
**验收**
- Given patrol-ai §2「姿态：CALM 垂灯/SUSPICIOUS 举灯转身/ALERT 拔刃灯高举/SEARCH 灯左右扫/RETURN 归位」；art-bible §4.1（靠姿态+道具非颜色）。
- When 守卫处于某状态。
- Then 姿态/提灯状态传达 FSM；不依赖色相（C-05）；可疑度条图标+数字+亮度（C-02）。
**关联**：patrol-ai §2/§5/§7；art-bible §4.1；control-manifest C-02/C-05/C-07。

### E08-S9 · 作为（设计）我要（变体实例化与 entity-inventory 类型绑定）以便（Tier2 由资产驱动）
**Sprint 2**：否 → **Sprint 3**：滑期（主理人裁决 1）
**验收**
- Given 4 类角色（玩家 + 标准守卫 + 2 Tier2 变体）；变体由 entity-inventory 类型字段驱动参数覆盖。
- When 关卡加载变体守卫。
- Then 实例化时按类型套用参数覆盖（不新增系统/机制族）；计入 G-01 守卫预算。
**关联**：patrol-ai §8；entity-inventory（守卫变体实体表）；control-manifest G-01。

### E08-S10 · 作为（系统）我要（变体 FSM 合并验证）以便（基类阈值契约不被污染）
**Sprint 2**：否 → **Sprint 3**：滑期（主理人裁决 1）
**验收**
- Given 参数覆盖若实现为运行时 mut 实例常量，可能破坏 Sprint 1 已锁阈值测试（THR_SUSP=25/THR_ALERT=60/THR_RETURN=10/DECISION_HZ=10）。
- When 变体运行五态 FSM + 连续可疑度 + 决策 ≤10Hz。
- Then 基类阈值契约不被覆盖污染（用参数对象而非改类常量）；标准守卫与变体阈值一致（合并测试）。
**关联**：patrol-ai §2；control-manifest G-04/C-02；架构风险 FLAG-B（sprint2-stories.md §5）。

## 依赖
E05（vision_stimulus）、E06（sound_emitted）、E02（tick 真实时间）、E01（NavServer/Grid/EventBus/SaveManager）。发出 `suspicion_changed`/`guard_fsm_changed`/`exposure_detected`/`guard_transform_dirty` → E09/E05。被依赖：E09（HUD/软重开）、E05（transform 重算）。

## 整 Epic 验收标准
1. FSM 五态 + 连续可疑度（25/60/10）；决策 ≤10Hz（真实时间，G-04）。
2. 暴露梯度：ALERT+可见 1.2s 真实时间 → `exposure_detected` → 软失败（检查点重生，C4）。
3. A* 仅状态转换触发并缓存（G-05）。
4. 信号 `suspicion_changed`/`guard_fsm_changed`/`exposure_detected`/`guard_transform_dirty` 契约存在。
5. 姿态可读（非颜色）；变体参数覆盖不新增系统。

## 风险
- **R-AI-1**：暴露瞬死破坏 deliberate 手感。缓解：E08-S4 1.2s 宽限 + 软失败（概念 §3⑤）。
- **R-AI-2**：tick 若随 time_scale → 慢放下 AI 变慢失平衡。缓解：E08-S3 真实时间 tick（ADR-002/003）。
- **R-AI-3**：检查点粒度不当 → 重生挫败。缓解：E11 SaveManager + C4 待与程基岩按 L2 落地。

## 与架构 + 控制清单勾稽
- 架构 §2（L3 AI）、§3.4（FSM 决策 5–10Hz、A* 缓存、变体参数覆盖）、§4（守卫 8/16、FSM ≤10Hz、射线随 E05）。
- ADR-002（FSM 节流 5–10Hz、A* 仅状态转换缓存、事件驱动重算）。
- control-manifest：G-01（守卫≤8/16）、G-04（≤10Hz）、G-05（A* 仅状态转换）、V-02（暴露脉动≤2Hz）、V-03（屏震默认关）、C-02（可疑度≥7:1）、C-06（色盲 `#D64545`→`#F0C070`+**实心三角**图标）、C-07（危险不单色）。
- patrol-ai §8（Tier1 五态+连续+软失败+A*+姿态；Tier2 变体；Tier3 机关谜题复用）。

> **更正说明（S3-B 残留收口 · C-06 现行口径 · 林绘澄签字）**：本行原文「C-06（色盲 `#7A2E2E→#C8862F`+图标）」**已作废**。根因：警戒 CAUTION **本就是** `#C8862F` —— 守卫 SUSPICIOUS（警戒）与 ALERT（警报）在色盲档下会被映射成**同一色值、亮度比 1.00:1**，而守卫状态可读性正是 E08-S8 的验收核心。**现行口径 = `#D64545` → `#F0C070`**（vs 警戒 `#C8862F` = **1.81:1**）。依据 `design/art/art-bible.md` **v0.4** §9.1 / `design/art/accessibility-matrix.md` 行 4。源码常量 **`HUD_COLOR_ALARM_CB` 已退休** → **`HUD_COLOR_DANGER_CB`**。守卫警戒/警报的**频率维（0.5Hz 单拍 / 2.0Hz 双拍）与形状维（空心圆环 `?` / 实心三角 `!`）常驻生效**，不随色盲开关切换 —— 这是 E08-S8「靠姿态读守卫状态」在默认档（`#C8862F` vs `#D64545` 仅 1.44:1）也成立的兜底。
