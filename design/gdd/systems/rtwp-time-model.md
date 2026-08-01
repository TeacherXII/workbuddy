# 系统 GDD · RTwP 凝神时间模型（rtwp-time-model）
**Phase 2 · 八节 GDD · 优先级 P0（地基）**

> 上游：`design/concept/game-concept.md` §2 Mechanics（步进提交/凝神）、§4 核心循环；`docs/architecture/adr/adr-003-realtime-with-pause-time-model.md`；`docs/architecture/control-manifest.md` §2（T-01~T-04）；`design/art/art-bible.md` §8.4/§9.3。

---

## 1. 系统目标与支柱对齐
- **目标**：提供单一全局时间控制器，支撑「读—步」循环——常态世界流动，按住「凝神 / 聚焦」进慢放预览，松开即提交下一步。
- **支柱对齐**：
  - 支柱一 **步步为营**：凝神暂停/慢放即「读场」间隙，让规划成立而非反应。
  - 支柱二 **感官愉悦**：慢放是丝滑、有重量的操控质感（ADR-003：动画/残影天然减速）。
  - 支柱四 **肃穆压迫**：凝神时仅整体压暗四周、提亮可读要素，强化「被注视的寂静」。
- **为何存在**：RTwP 是「实时 + 可暂停」而非回合制——保流动感（风险1 缓解）；慢放用时间缩放而非双模拟（风险5 / ADR-003）。

## 2. 核心机制与规则
- **时间模式** `TimeMode`：`FLOWING`（常态 1.0）| `FOCUS`（凝神慢放）| `PAUSED`（仅菜单）。
- **缩放参数**（硬编码下限由控制清单约束）：
  - 常态 `time_scale = 1.0`。
  - 凝神目标 `0.25`（可调区间 `0.1–0.3`，**T-02**）；用户总可调范围 `0.1×–1.0×`（**T-01**），下限 `0.1` 防物理不稳。
  - 进入/退出用缓动 ramp，时长 `≈0.15s`（ease，非硬切，**V-06**）。
- **输入实时性**：`InputEvent` 不受 `time_scale` 影响——慢放中玩家仍可规划、步进提交（**ADR-003**）。
- **冷却纪律**：所有玩法冷却计时须用**真实时间（wallclock）**，不得落入受缩放的 `_process` delta（**ADR-003 风险4**）；否则慢放下冷却变慢导致手感异常。
- **完全暂停**：`get_tree().paused=true` 或 `time_scale=0` 仅用于菜单/设置，**不作常规玩法**（**T-03**）。
- **可访问性替代**：提供「步进暂停模式（Step-Pause）」——凝神键改为完全冻结（time_scale=0）而非慢放，供眩晕/低敏玩家；属同一 `TimeMode.FOCUS` 下的子开关。

## 3. 数据模型与状态
```gdscript
enum TimeMode { FLOWING, FOCUS, PAUSED }
enum FocusStyle { SLOWMO, STEP_PAUSE }   # STEP_PAUSE = 可访问性替代

class TimeController:        # L2 单例，经 Engine.time_scale 实施
    var mode: TimeMode = FLOWING
    var focus_style: FocusStyle = SLOWMO
    var current_scale: float = 1.0
    var target_scale: float = 1.0
    var ramp_t: float = 0.0            # 真实时间累积，不受缩放
    const RAMP_DUR: float = 0.15
    const FOCUS_DEFAULT: float = 0.25
    const USER_MIN: float = 0.1
    const USER_MAX: float = 1.0
    var user_focus_scale: float = 0.25  # 设置菜单可调，钳制 [0.1, 0.3]
```
- 状态机：`FLOWING ⇄ FOCUS`（按住/松开凝神键）；`FLOWING/ FOCUS → PAUSED`（菜单打开）。
- `ramp_t` 用 `real_delta`（`_process` 内 `Engine.get_process_time()` 或 `Time.get_ticks_msec()` 差）推进。

## 4. 与其他系统的接口
- **发出**（L2 EventBus）：`time_scale_changed(old, new, mode)`——订阅方：②自身下游、粒子同步、音频。
- **被依赖**：
  - ① 步进提交：消费凝神键 released → 提交下一步；慢放下步进动画减速。
  - ③ 视野锥 / ④ 声音 / ⑥ 巡逻 AI：其节流 tick（10Hz / 5–10Hz）基于**真实时间**，不随 `time_scale` 改变（慢放下帧率仍 60，tick 不变 → 收益更大，ADR-002/003）。
- **联动架构 §2**：时间统一由 L2 时间控制器经 `Engine.time_scale` 管理；玩法不得自管时间。

## 5. 玩家交互与反馈
- **输入**：凝神键（默认 右键鼠标 / `Shift` / 手柄 `LT`），hold=进入，release=退出。
- **视觉**：机位不动（概念 §2）；凝神时整体压暗四周 + 轻微冷调（`#10141C` 染色），世界可读要素（锥/光池/声环/残影）反而提亮——「读场」时刻（美术 §8.4）。
- **音频**（ADR-003）：凝神期**不变调**（避免光敏/眩晕），仅施加全局 `lowpass` + `ducking` 增强「凝神」质感；关键 `AudioStreamPlayer` 不全局 `pitch_scale`。
- **粒子同步**：凝神时显式同步 `GPUParticles3D/CPUParticles3D.time_scale = current_scale`（**T-04**），否则尘埃/声环不与世界同速。

## 6. 边界与性能约束
- **T-01** 时间缩放可调 `0.1×–1.0×`；**T-02** 凝神默认 `0.25`（区间 `0.1–0.3`），下限 `0.1`（防固定步物理有效步频下降，ADR-003 风险3）。
- **T-03** 完全冻结仅菜单/设置。
- **T-04** 凝神时同步粒子 `.time_scale`。
- **性能**：慢放近乎零额外成本（物理步更少=更省 CPU，ADR-003 正向）；时间控制器本身 O(1) 每帧。
- **架构联动**：`architecture.md` §4「凝神时间缩放 0.1–0.3（默认 0.25）」；ADR-003。

## 7. 可访问性考量
- **时间缩放可调**：用户 `0.1–1.0` 自由设凝神倍率（**T-01**；美术 §9.3）。
- **步进暂停替代**：`STEP_PAUSE` 模式把凝神改为完全冻结，服务眩晕/低敏玩家（仍属 FOCUS 语义，不破坏循环）。
- **眩晕防护**：屏震默认关（**V-03**，由 ⑧ 实施但本系统不强制）；动态模糊默认关（**V-05**）；转场缓动（**V-06**）。
- **对齐清单**：T-01/T-02/T-03/T-04、V-03/V-05/V-06；美术 §9.3。

## 8. 范围分层归属
- **Tier1（必做）**：`FLOWING`/`FOCUS` 慢放（默认 0.25）+ ramp + 输入实时 + 冷却用真实时间 + 音频 lowpass/ducking + 粒子同步。
- **Tier2（期望）**：色盲无关；但「步进暂停模式」「时间缩放 UI 滑杆」在 Tier2 可访问性包内（概念 §5 Tier2）。
- **Tier3（拓展）**：无新增系统；最多扩展 `user_focus_scale` 预设档。
- **范围纪律**：本系统即概念 §3 时间模型本身，未新增平行机制族。
