# 系统 GDD · 巡逻 AI 与可疑度 FSM（patrol-ai）
**Phase 2 · 八节 GDD · 优先级 P3（依赖 ③ 视野 + ④ 声音）**

> 上游：`design/concept/game-concept.md` §3 Mechanics⑤、§4；`docs/architecture/adr/adr-002-stealth-compute-model.md`（FSM 5–10Hz、A* 仅状态转换）；`docs/architecture/control-manifest.md` G-01/G-04/G-05、C-02/C-07、V-02；`design/art/art-bible.md` §4.1。

---

## 1. 系统目标与支柱对齐
- **目标**：守卫 FSM `CALM→SUSPICIOUS→ALERT→SEARCH→RETURN`；可疑度**连续条**非二进制；暴露是**可见的升级**（梯度），给玩家时间补救/重规划，非瞬死。
- **支柱对齐**：
  - 支柱一 **步步为营**：暴露可恢复 → 失误变「重新规划机会」而非读档（概念 §3 Dynamics）。
  - 支柱四 **肃穆压迫**：渐升警戒的庄重紧张。
- **为何存在**：把「被发现」从硬失败改成可管理的梯度，是 deliberate 手感的关键保障（风险1/概念 §3⑤）。

## 2. 核心机制与规则
- **FSM 状态** `GuardState{CALM, SUSPICIOUS, ALERT, SEARCH, RETURN}`。
- **可疑度连续值** `S ∈ [0,100]`；阈值：`SUSPICIOUS ≥25`、`ALERT ≥60`、`SEARCH`=ALERT 且丢失目标、`RETURN`=S<10 且回归巡逻。
- **累积/衰减**（决策 **5–10Hz**，G-04）：
  ```
  dS/dt = vision_vis × kV(35) + sound_in_range × kS(15) − (stimulus?0:decay(8))
  vision_vis ∈ [0,1] 来自 ③ vision_stimulus
  sound_in_range = intensity × (1 − dist/radius) 来自 ④ sound_emitted
  ```
- **暴露梯度（非瞬死）**：当 `ALERT` 且目标持续 `visibility>0` 累计 **宽限 1.2s（真实时间）** → 发 `exposure_detected` → **软失败**：在最近安全检查点重生，可疑度清零，守卫回 `RETURN`/巡逻（世界部分重置）。宽限期内玩家可断 LOS/熄灯/诱饵降 S 自救。
- **A\* 寻路**（G-05）：仅状态转换（CALM→ALERT/SEARCH）触发 `NavigationAgent3D` 并缓存路径，非逐帧。
- **行为姿态**（美术 §4.1，靠姿态+道具非颜色）：CALM 垂灯巡逻 / SUSPICIOUS 举灯转身 / ALERT 拔刃灯高举 / SEARCH 灯左右扫 / RETURN 归位。

## 3. 数据模型与状态
```gdscript
enum GuardState { CALM, SUSPICIOUS, ALERT, SEARCH, RETURN }
enum SusTier { CALM, SUSPICIOUS, ALERT, SEARCH }   # CALM = 可疑度 < 25（对齐 system-breakdown §2.3 / E08-S2 阈值 25/60/10；旧 NONE 作废）

class GuardBrain:                 # L3
    var fsm: GuardState = CALM
    var suspicion: float = 0.0    # [0,100]
    var last_known: Vector3
    var exposure_timer: float = 0.0   # 真实时间
    const THR_SUSP: float = 25.0
    const THR_ALERT: float = 60.0
    const THR_RETURN: float = 10.0
    const KV: float = 35.0
    const KS: float = 15.0
    const DECAY: float = 8.0
    const GRACE_RT: float = 1.2    # 暴露宽限（真实时间）
    const DECISION_HZ: float = 10.0  # ≤ G-04
```
- 决策 tick 用真实时间（不随 `time_scale`），慢放下仍 5–10Hz（ADR-002/003）。

## 4. 与其他系统的接口
- **依赖**：③ `vision_stimulus(guard_id, target, visibility)`、④ `sound_emitted(SoundPayload)`、L2 NavServer、L2 Grid、②（tick 真实时间）。
- **发出**：`suspicion_changed(guard_id, value, tier)`（→⑧）、`guard_fsm_changed(guard_id, old, new)`（→⑧）、`exposure_detected(guard_id, target)`（→⑧+失败流）、`guard_transform_dirty(guard_id)`（→③ 视野重算）。
- **被依赖**：⑧ HUD 绘制可疑度条/姿态；失败流由 ⑧/存档处理软重开。
- **联动 ADR-002**：FSM 节流 5–10Hz、A* 仅状态转换缓存。

## 5. 玩家交互与反馈
- **可读性**：守卫姿态+提灯状态（非颜色）传达 FSM（美术 §4.1）；可疑度条（⑧）带图标+数字（C-02）。
- **Sensation**：暴露脉动 `#D64545`（D7 签字；`#7A2E2E` 仅作低不透明填充 α≤0.35）+图标+（可关）屏震（V-03），是「质地」紧张非庆祝。
- **补救窗口**：宽限期内玩家可见可疑度条回落/守卫转身——明确的「还差多少被发现」（概念 §3⑤）。

## 6. 边界与性能约束
- **G-01** 同区活动守卫 MVP ≤8 / Tier2 ≤16。
- **G-04** FSM 决策 ≤10Hz（节流）。
- **G-05** A* 仅状态转换触发并缓存，非逐帧。
- **V-02** 暴露脉动 ≤2Hz，幅度温和。
- **LOS 射线**：随 ③（MVP≈160/s，Tier2≈480/s）。
- **架构联动**：`architecture.md` §3.4（FSM 决策 5–10Hz、A* 缓存）；§4 预算。

## 7. 可访问性考量
- **状态靠姿态/形状非颜色**（美术 §4.1）：三类色盲下守卫状态 100% 可读。
- **可疑度条**：图标+数字+亮度递增，颜色仅辅助（**C-02** ≥7:1，关键指示）。
- **危险提示不单色**：`#7A2E2E` 必配形状/脉动/图标（**C-07**）；色盲模式替换为 `#C8862F` 高亮+图标（**C-06**）。
- **屏震默认关**（**V-03**），暴露提示不强制屏震。
- **对齐清单**：C-02/C-06/C-07、G-01/G-04/G-05、V-02/V-03；美术 §4.1/§9.1。

## 8. 范围分层归属
- **Tier1（必做）**：五态 FSM + 连续可疑度 + 暴露梯度（软失败宽限 1.2s）+ A* 缓存 + 姿态可读。
- **Tier2（期望）**：守卫变体——循声猎犬（听觉优先，降视觉权重）、暗视哨兵（暗处仍可见，降 L 阈值）；复用 FSM+参数覆盖（architecture §3.4），不新增系统。
- **Tier3（拓展）**：环境处决/机关谜题（组合 ⑦ 道具触发）；仍复用 FSM，不新增系统。
- **范围纪律**：本系统即概念 §3⑤；变体以参数/权重覆盖实现（architecture §3.4），未新增平行机制族。
