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
- **危险提示不单色**：警报语义色 **`#D64545`** 必配形状/脉动/图标（**C-07**；`#7A2E2E` 仅作 α≤0.35 底纹，**非语义载体**——1.91:1 数学上永不达 C-03）；色盲模式替换为 **`#F0C070`** 高亮 + **实心三角 `!`** 图标（**C-06**）。
  > **更正说明（Sprint 3，同步 art-bible v0.3 §9.1 / control-manifest v0.2 C-06）**：原文「色盲模式替换为 `#C8862F`」**已作废**——警戒 CAUTION **本就是** `#C8862F`，该映射会使警戒与警报**同色值、亮度比塌缩至 1.00:1**，C-05 三重编码的亮度维度彻底失效。现改 `#F0C070`（vs 警戒 **1.81:1**；vs 面板 `#16181D` **10.55:1**，连 C-02 都过）。
  > 另：**脉冲频率（警戒 0.5Hz 单拍 / 警报 2.0Hz 双拍）与图标面积编码（空心圆环 `?` / 实心三角 `!`）在两种模式下均常驻生效**，不随色盲开关切换——因默认模式下 `#C8862F` vs `#D64545` 亮度比也仅 1.44:1。
- **屏震默认关**（**V-03**），暴露提示不强制屏震。
- **对齐清单**：C-02/C-06/C-07、G-01/G-04/G-05、V-02/V-03；美术 §4.1/§9.1。

## 8. 范围分层归属
- **Tier1（必做）**：五态 FSM + 连续可疑度 + 暴露梯度（软失败宽限 1.2s）+ A* 缓存 + 姿态可读。
- **Tier2（期望）**：守卫变体——循声猎犬（听觉优先，降视觉权重）、暗视哨兵（暗处仍可见，降 L 阈值）；复用 FSM+参数覆盖（architecture §3.4），不新增系统。
- **Tier3（拓展）**：环境处决/机关谜题（组合 ⑦ 道具触发）；仍复用 FSM，不新增系统。
- **范围纪律**：本系统即概念 §3⑤；变体以参数/权重覆盖实现（architecture §3.4），未新增平行机制族。

---

## 9. Sprint 2 守卫变体（E08）
> 本 § 将 ⑥ 的 Tier2 变体落地为**参数/权重覆盖**（architecture §3.4），**零新事件词汇**——变体仅覆写 `GuardBrain` 的常量与 ③④ 采样偏好，复用既有 `suspicion_changed`/`guard_fsm_changed`/`exposure_detected`。这是一致性评审的利好点：变体不污染事件词汇表（见 `consistency-review.md` §5）。

### 9.1 变体覆盖机制
```gdscript
enum GuardVariant { STANDARD, SOUND_HOUND, DARK_SENTINEL }   # ⑥ 内部枚举

class GuardBrain:                 # L3，参数来自 variant overlay
    var variant: GuardVariant = STANDARD
    # 以下常量可被 variant overlay 覆写（默认值=STANDARD）
    var KV: float = 35.0          # 视觉权重
    var KS: float = 15.0          # 声音权重
    var vision_radius: float = 14.0
    var vision_angle_deg: float = 35.0
    var vision_light_floor: float = 0.0   # 暗处可见度地板（哨兵↓）
    var sound_detect_radius_mult: float = 1.0   # 听觉半径倍率（猎犬↑）
    # 阈值/衰减/宽限与 STANDARD 一致：THR_SUSP=25, THR_ALERT=60, THR_RETURN=10, DECAY=8, GRACE_RT=1.2, DECISION_HZ=10
```
- 变体在 `GuardBrain._init(variant)` 时套用 overlay；运行时不可切换（关卡布置决定）。
- HUD（⑧）需知变体以渲染差异化剪影：经既有 `guard_fsm_changed` 携带 `variant` 快照，或新增只读 `guard_spawned(guard_id, variant)`（登记于 `consistency-review.md` §5）。**不**新增 FSM 状态/事件语义。

### 9.2 变体参数表
| 参数 | STANDARD | 循声猎犬 SOUND_HOUND | 暗视哨兵 DARK_SENTINEL | 含义 |
| --- | --- | --- | --- | --- |
| `KV`（视觉权重） | 35 | **15**（↓） | 35 | 视觉刺激对可疑度贡献 |
| `KS`（声音权重） | 15 | **30**（↑×2） | 15 | 声音刺激对可疑度贡献 |
| `vision_radius` | 14m | **11m**（↓） | 14m | 视野锥半径 |
| `vision_angle_deg` | 35° | **30°**（↓） | 35° | 视野锥半角 |
| `vision_light_floor` | 0.0 | 0.0 | **0.05**（↓地板） | 暗处最低可见度（见 9.3） |
| `sound_detect_radius_mult` | 1.0 | **1.6**（↑） | 1.0 | ④ 声音检测半径倍率 |
| 阈值 25/60/10 · DECAY 8 · GRACE 1.2s · ≤10Hz | 同 | 同 | 同 | 升级/宽限逻辑不变 |

### 9.3 行为语义
- **循声猎犬（听觉优先）**：`KV` 降至 15、`KS` 升至 30、听觉半径 ×1.6 → 对脚步/诱饵声极敏感，但锥略缩（11m/30°）对静默阴影绕行容忍度更高。**设计意图**：逼迫玩家用 ④ 声音管理（垫步/熄灯/诱饵调虎）而非纯视觉规避。
- **暗视哨兵（暗处仍可见）**：`vision_light_floor = 0.05` 改写 ③ `vision_vis` 计算——③ 公式 `vis = clamp((L - L_DARK_FLOOR)/(L_BRIGHT - L_DARK_FLOOR), 0, 1)` 中，哨兵取 `L_DARK_FLOOR = vision_light_floor`（0.05 < 标准 0.20 等效地板），使在 `L_DARK=0.20` 阴影里仍读到 `vis≈0.5`（标准守卫≈0）。**设计意图**：阴影不再是哨兵区的「免费安全区」，玩家须靠 ⑦ 道具（熄灯/烟雾）或路径规划破局。

### 9.4 边界（变体）
- **G-01** 同区活动守卫仍 ≤8（MVP）/≤16（Tier2），变体不破上限。
- **G-04** FSM 决策仍 ≤10Hz（节流不变）。
- **V-02** 暴露脉动仍 ≤2Hz。
- **零新事件**：仅参数/权重覆盖，复用全部既有信号（一致性利好，见 `consistency-review.md` §5）。
- **无新系统**：变体是 ⑥ 的数据维度，非平行机制族（范围纪律保持）。
