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
**关联**：patrol-ai §2/§3；consistency-review C4；E01-S5（SaveManager）；control-manifest（无编号，属 GDD ⑥）。

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
**Sprint 0**：否（Sprint 2）
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
- **R-AI-3**：检查点粒度不当 → 重生挫败。缓解：E01-S5 SaveManager + C4 待与程基岩按 L2 落地。

## 与架构 + 控制清单勾稽
- 架构 §2（L3 AI）、§3.4（FSM 决策 5–10Hz、A* 缓存、变体参数覆盖）、§4（守卫 8/16、FSM ≤10Hz、射线随 E05）。
- ADR-002（FSM 节流 5–10Hz、A* 仅状态转换缓存、事件驱动重算）。
- control-manifest：G-01（守卫≤8/16）、G-04（≤10Hz）、G-05（A* 仅状态转换）、V-02（暴露脉动≤2Hz）、V-03（屏震默认关）、C-02（可疑度≥7:1）、C-06（色盲 #7A2E2E→#C8862F+图标）、C-07（危险不单色）。
- patrol-ai §8（Tier1 五态+连续+软失败+A*+姿态；Tier2 变体；Tier3 机关谜题复用）。
