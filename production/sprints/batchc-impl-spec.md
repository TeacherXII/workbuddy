# Sprint 1 · Batch C 实现规格（Implementation-Ready Spec）

| 字段 | 值 |
| --- | --- |
| **阶段** | Phase 5 · Sprint 1 · Batch C（E08 巡逻 AI + E09 核心 HUD + E06-S5） |
| **文档版本** | v1.0（**实现就绪规格**；上游 `batchc-design-review.md` v1.1 的裁决落地件） |
| **作者** | 文策渊（游戏策划与叙事设计师 / design-strategist） |
| **任务 ID** | BATCHC-IMPL-01 |
| **裁决状态** | **D5 / D6 / D8 / D9 已由主理人游承峰锁定；D7 由林绘澄美术签字（PASS）；D10 全数采纳。§7 六项裁决全部 CLOSED** |
| **批次范围** | 12 条 Story：E08-S1/S2/S3/S4/S5/S6/S8 · E09-S2/S3/S4/S6 · E06-S5 |
| **上游依据** | `production/sprints/batchc-design-review.md`（C1–C10 缺口闭合 / §4 18 钩子 / §5 词汇勾稽）· `design/art/hud-a11y-signature.md` v1.0（D7 签字稿）· `design/gdd/systems/patrol-ai.md` §2/§3 · `design/gdd/systems/core-hud-a11y.md` · `design/gdd/system-breakdown.md` §2 · `production/epics/E08-patrol-ai.md` · `production/epics/E09-core-hud-a11y.md` · `production/sprints/sprint1-stories.md` · `docs/architecture/control-manifest.md` · 现存 `src/**` / `tests/unit/**` |
| **下游衔接** | 程基岩（engineering-lead，按 §9 顺序实现）· 严守真（quality-lead，按 §8 填充 18 钩子）· 林绘澄（art-lead，NEW-1 回签，非阻塞） |

> **本文用途**：把 Batch C 的 12 条 Story 转成**可直接照抄的实现规格**——文件路径、函数签名、常量、伪码、测试钩子、三处地雷落点、执行顺序拓扑。
>
> **纪律**：本文**不写任何 `src/` 代码、不做 git 操作**。所有 GDScript 段落是**规格**不是实现。凡本文与上游 Story 文字冲突处，**以本文为准**（本文已吸收 4 项主理人裁决 + 1 份美术签字）。

---

## 0. 裁决收口速览（本文的全部前提）

| # | 裁决 | 锁定值 | 状态 | 落点 |
| --- | --- | --- | --- | --- |
| **D5** | 声音结算口径 | **脉冲**：`S += KS(15) × falloff`，**不乘 dt**。视觉仍按速率 `KV(35) × vis × dt`。基线式 `dS/dt = vision_vis×KV(35) + sound×KS(15) − (stimulus?0:decay(8))` | **CLOSED**（主理人） | §2.1 · §3.2 · §3.12 |
| **D6** | `guard_fsm_changed` 值域 | **改 int enum 对齐**：`EventBus.GuardState { PATROL/CALM=0, INVESTIGATE/SUSPICIOUS=1, ALERT=2, SEARCH=3, RETURN=4 }`；签名 `(guard_id:int, old:GuardState, new:GuardState)` | **CLOSED**（主理人，**推翻评审 R1 建议**） | §2.2 · §7.1 |
| **D7** | HUD 三档色值 | **林绘澄签字 PASS**：Carrier `#DCE3EC` / Calm `#3E5C76` / Caution `#C8862F` / Alarm `#D64545` / Alarm-Fill `#7A2E2E`（仅填充 α≤0.35）/ **CB `#F0C070`**（~~`= Caution`~~ 已作废，见下） | **CLOSED**（美术签字，**CB 值经 v1.1 追认改判**） | §2.3 · §3.8 · §3.11 |
| **D8** | `interactable_triggered` 签名 | **本批收口**：`(obj_id:int, type:InteractableType, payload:Dictionary)`；`InteractableType { DECOY, LIGHT_TOGGLE, TRAP, SMOKE }` | **CLOSED**（主理人） | §2.2 · §3.10 · §7.1 |
| **D9** | E01-S5 / E01-S8 排期 | **seam 占位 + 延 Sprint 2**：`_checkpoint_sink` / `_path_provider` 两个 `Callable`；E01-S5（SaveManager）/ E01-S8（NavServer）正式排入 **Sprint 2** | **CLOSED**（主理人） | §3.4 · §3.5 · §10 |
| **D10** | 7 个新增常量 | `LOST_TARGET_RT=0.5s` · `RETURN_SETTLE_RT=1.0s` · `STIM_EPS=0.001` · `SUS_EMIT_EPS=0.5` · `MAX_CATCHUP_TICKS=3` · `XFORM_POS_EPS=0.5m` · `XFORM_YAW_EPS_DEG=5.0°` | **CLOSED**（全数采纳，逐字入规格） | §2.1 |

> **被裁决推翻的评审建议（须知悉，勿照旧文实现）**：
> - 评审 §2.5-b 推荐 **R1「保持 String」** → **作废**。D6 采纳 **R2 int enum**。
> - 评审 §2.7 提出的三档明度变体 `#7A5A24 / #A8712A / #E8A94A` → **未进签字稿，作废**。可疑度条改用 **D7 签字色 + Carrier α 阶梯**（§2.3.3）。

---

## 1. 本批交付物文件清单

| # | 文件 | 状态 | 归属 Story | 说明 |
| --- | --- | --- | --- | --- |
| F1 | `src/core/event_bus.gd` | **修改** | 契约前置（D6/D8） | 补 `GuardState` / `InteractableType` 两枚举；改 2 条签名 |
| F2 | `src/ui/hud_colors.gd` | **新建** | 契约前置（D7） | HUD_COLOR_* 权威常量 + WCAG 纯函数（headless 安全） |
| F3 | `src/game/patrol_ai.gd` | **新建** | E08-S1/S2/S3/S4/S5/S6/S8 · E06-S5 | `class_name GuardBrain extends Node`（L3） |
| F4 | `src/ui/hud_slice.gd` | **修改** | E09-S2/S3/S4/S6 | 含**地雷 ①** 双写冲突修复 |
| F5 | `src/game/vision_cone.gd` | **修改（+3 行）** | E09-S3 | 新增 `set_readability_boost(on)` |
| F6 | `src/game/sound_propagation.gd` | **修改（+3 行）** | E09-S3 | 新增 `set_readability_boost(on)`；`update_guard` **不改**（已就绪，由 F3 调用） |
| F7 | `src/game/footfall_vfx.gd` | **修改（+3 行）** | E09-S3 | 新增 `set_readability_boost(on)` |
| T1 | `tests/unit/test_patrol_ai.gd` | **新建** | E08 全部 + E06-S5 | 钩子 1/2/3/4/6/7/8/9/10/11/18 |
| T2 | `tests/unit/test_hud_slice.gd` | **修改** | E09 全部 | 钩子 12/13/14/15/16/17（13 为**改写**，见地雷 ①） |
| T3 | `tests/unit/test_step_commit.gd` | **修改** | E08-S4 | 钩子 5（`ExposureGuardStub` → 真 `GuardBrain`） |
| T4 | `tests/unit/test_event_bus.gd` | **修改** | D6/D8 收口 | L42 名单不变；**L67 emit 桩** + L81 断言随新签名 |

> **不碰**：`tests/ci/budget_assert.gd`（Batch D · E10-S2 负责）· `src/main/sprint0_bootstrap.gd` 的 Sprint 0 遗留声音路径（Batch B 已标记，本批不动）· 任何 `src/core/save_manager.gd` / `nav_server.gd`（D9 延 Sprint 2）。

---

## 2. 全批常量与契约（单一权威源，工程直接抄）

### 2.1 GuardBrain 常量块（`src/game/patrol_ai.gd` 顶部）

```gdscript
# ── GDD 已锁常量（patrol-ai §3，不得改值）─────────────────────────────
const THR_SUSP     := 25.0    # 点        上行阈值 → SUSPICIOUS
const THR_ALERT    := 60.0    # 点        上行阈值 → ALERT
const THR_RETURN   := 10.0    # 点        下行阈值 → RETURN
const KV           := 35.0    # 点/秒     视觉增益（乘 vision_vis∈[0,1] 与 dt）
const KS           := 15.0    # 点/次声事件 声音增益（乘 falloff∈[0,1]，【D5】不乘 dt）
const DECAY        := 8.0     # 点/秒     无刺激衰减（乘 dt）
const GRACE_RT     := 1.2     # 秒（真实时间）暴露宽限
const DECISION_HZ  := 10.0    # Hz（真实时间）G-04 上限
const TICK_DT      := 0.1     # 秒        = 1.0 / DECISION_HZ（派生）

# ── D10 新增常量（主理人已采纳，逐字照抄）──────────────────────────────
const LOST_TARGET_RT     := 0.5     # 秒（真实时间）ALERT→SEARCH 的「丢失目标」判据
const RETURN_SETTLE_RT   := 1.0     # 秒（真实时间）RETURN→CALM 的 Sprint 1 最小化归位判据
const STIM_EPS           := 0.001   # 无量纲    stimulus 浮点判据（杜绝「永远记仇」）
const SUS_EMIT_EPS       := 0.5     # 点        suspicion_changed 节流阈
const MAX_CATCHUP_TICKS  := 3       # 次        固定步长追赶上限（防卡顿螺旋）
const XFORM_POS_EPS      := 0.5     # 米        guard_transform_dirty 位移置脏阈
const XFORM_YAW_EPS_DEG  := 5.0     # 度        guard_transform_dirty 转向置脏阈
```

> **硬编码红线**（`sprint1-stories` §5）：以上全部走常量，玩法逻辑中**不得出现裸数** `25 / 60 / 35 / 15 / 8 / 1.2 / 0.1 / 0.5 / 5.0`。

### 2.2 EventBus 契约变更（F1，D6 + D8，**批内最先做**）

```gdscript
# ── 新增共享枚举（system-breakdown §2.3 词汇表，L2 权威）────────────────
# 【D6】GuardState 提到 L2 作值域唯一权威；L3 GuardBrain 直接引用 EventBus.GuardState.*，
#       不再自建同名枚举（杜绝双份枚举漂移）。序号即 int 值域。
enum GuardState { CALM = 0, SUSPICIOUS = 1, ALERT = 2, SEARCH = 3, RETURN = 4 }
# 【D8】InteractableType（成员取自 interactables §3，四成员已锁）
enum InteractableType { DECOY, LIGHT_TOGGLE, TRAP, SMOKE }

# ── 签名变更（2 条）──────────────────────────────────────────────────
# 旧：signal guard_fsm_changed(guard_id: int, old: String, new: String)
signal guard_fsm_changed(guard_id: int, old: GuardState, new: GuardState)      # 【D6】
# 旧：signal interactable_triggered(id: int, kind: String)
signal interactable_triggered(obj_id: int, type: InteractableType, payload: Dictionary)  # 【D8】
```

**术语对照（主理人口径 ↔ 代码口径，必须一一对应，不得混用）**

| 主理人口述 | 代码成员 | int | GDD/art 姿态（E08-S8） |
| --- | --- | --- | --- |
| PATROL | `GuardState.CALM` | **0** | 垂灯巡逻 |
| INVESTIGATE | `GuardState.SUSPICIOUS` | **1** | 举灯转身 |
| ALERT | `GuardState.ALERT` | **2** | 拔刃灯高举 |
| （SEARCH） | `GuardState.SEARCH` | **3** | 灯左右扫 |
| （RETURN） | `GuardState.RETURN` | **4** | 归位 |

> 采用 GDD/art-bible 既有名（`CALM/SUSPICIOUS`）而非 `PATROL/INVESTIGATE`，理由：`patrol-ai` §2/§3、`system-breakdown` §2.3、`art-bible` §4.1、`sprint1-stories` 四处已锁 `CALM/SUSPICIOUS` 字面，改名会制造**四处文档漂移 + 姿态表失配**，而 D6 的实质要求是「**int enum 对齐**」，与成员命名无关。**int 值域与主理人给的 PATROL=0 / INVESTIGATE=1 / ALERT=2 完全一致。** 若主理人要求连名一并改，属 1 处枚举 + 4 处文档的独立收口，见 §11 OPEN-1。

**全部 emit / connect 站点（D6 + D8 收口清单，一处不漏）**

| # | 站点 | 现状 | 改法 |
| --- | --- | --- | --- |
| S1 | `src/core/event_bus.gd:33` | `guard_fsm_changed(..., old: String, new: String)` | 改 int enum（上方） |
| S2 | `src/core/event_bus.gd:37` | `interactable_triggered(id: int, kind: String)` | 改 3 参（上方） |
| S3 | `src/core/event_bus.gd:8` 注释 | 「interactable_triggered → Batch D, E09-S4」 | 改注为「**Batch C 收口（D8）**」 |
| S4 | `src/game/patrol_ai.gd`（新） | — | **唯一生产发射方**：`_bus.guard_fsm_changed.emit(guard_id, prev, next)`，两参为 `EventBus.GuardState` int |
| S5 | `src/ui/hud_slice.gd`（新连接） | — | `_on_interactable_triggered(obj_id: int, type: int, payload: Dictionary)`（E09-S4，§3.10） |
| S6 | `tests/unit/test_event_bus.gd:67` | `_bus.interactable_triggered.emit(1, "TRAP")` | → `_bus.interactable_triggered.emit(1, EventBus.InteractableType.TRAP, {"charges": 2})` |
| S7 | `tests/unit/test_event_bus.gd:42 / :81` | 名单 + `assert_signal_emitted` | 名单不变；断言不变（按名断言，不校参） |
| S8 | `tests/unit/test_patrol_ai.gd`（新） | — | 钩子 1 断言 `old/new` 为 `EventBus.GuardState` int，**不再断言字符串** |

> **回归面核查**：`grep -rn "guard_fsm_changed\|interactable_triggered" src/ tests/` 现只命中 `event_bus.gd`（声明 + 注释）与 `test_event_bus.gd`（3 处）。**无任何生产发射方 / 消费方**。⇒ D6 + D8 的实际回归面 = **1 个文件 3 行 + 1 个测试文件 1 行**，Batch A CI 59/59 不受影响。

### 2.3 HUD 色板契约（F2 `src/ui/hud_colors.gd`，D7 美术签字稿 v1.0）

#### 2.3.1 常量块（**权威，工程不得另改色值**）

```gdscript
class_name HudColors
extends RefCounted
# 色值来源：design/art/hud-a11y-signature.md v1.0（林绘澄 Art Sign-off，D7 PASS）
# 对比度基准面板 #16181D；在 #1B1B1F / #1C1F26 上同样达标。
# 【禁止】把 #7A2E2E 写成任何文字/边界/图标色 —— 1.91:1，数学上永不达 C-02/C-03。

const HUD_COLOR_PANEL_BASE := Color.from_string("#16181D", Color.BLACK)  # 核算基准
const HUD_COLOR_CARRIER    := Color.from_string("#DCE3EC", Color.WHITE)  # 13.74:1  C-02 ✅
const HUD_COLOR_CALM       := Color.from_string("#3E5C76", Color.WHITE)  #  2.53:1  装饰描边，非信息载体
const HUD_COLOR_CAUTION    := Color.from_string("#C8862F", Color.WHITE)  #  5.84:1  C-01/C-03 ✅
const HUD_COLOR_ALARM      := Color.from_string("#D64545", Color.WHITE)  #  4.06:1  C-03 ✅（边框/图标）
const HUD_COLOR_ALARM_FILL := Color.from_string("#7A2E2E", Color.WHITE)  #  1.91:1  ★仅填充 α≤0.35
# C-06 色盲模式替换。★ 旧写法 `:= HUD_COLOR_CAUTION`（=#C8862F）已作废：警戒本就是 #C8862F，
# 映射后警戒与警报同色值、亮度比塌缩至 1.00:1（art-bible v0.3 §9.1 / control-manifest v0.2 C-06）。
const HUD_COLOR_ALARM_CB   := Color.from_string("#F0C070", Color.WHITE)  # 10.55:1  vs CAUTION 1.81:1
# 预批准备选（仅当审计要求警报边框自身过 C-01 时启用，不得另造）
const HUD_COLOR_ALARM_ALT  := Color.from_string("#E0584F", Color.WHITE)  #  4.80:1  C-01 ✅

const ALARM_FILL_ALPHA_MAX := 0.35   # ★ #7A2E2E 的硬上限（签字稿 §3）
```

#### 2.3.2 载体 / 语义分工（C-02 被测对象口径，签字稿 §3）

| 元素 | 取色 | 对 `#16181D` | 卡的门 |
| --- | --- | --- | --- |
| 可疑度**数值**、暴露**标签**、道具 **charges**、所有 HUD 文字 | `HUD_COLOR_CARRIER` | **13.74:1** | **C-02 ✅** |
| tier **图标字形**（眼 / ? / ! / 放大镜）填充 | `HUD_COLOR_CARRIER` | **13.74:1** | **C-02 ✅** |
| 可疑度条**内边界描边**（1px） | `HUD_COLOR_CARRIER` | **13.74:1** | **C-02 ✅** |
| 面板/结构**装饰描边** | `HUD_COLOR_CALM` | 2.53:1 | 装饰，**不卡门**（签字稿 §0-2） |
| SUSPICIOUS 档**条边框** · `?` 图标描边 · 脉冲 | `HUD_COLOR_CAUTION` | 5.84:1 | **C-03 ✅** |
| ALERT 档**条边框** · 暴露层**边框** · `!` 图标描边 · 脉冲 | `HUD_COLOR_ALARM` | 4.06:1 | **C-03 ✅** |
| 暴露层**底纹填充** | `HUD_COLOR_ALARM_FILL` **α≤0.35** | 1.91:1 | **仅填充**，上覆白载体（见验算） |

**验算（供 QA 直接断言，非估值）**
- 暴露层：`#7A2E2E` @α0.35 over `#16181D` 合成 = `#392320`（L≈0.0201）→ Carrier 文字对其 **11.59:1 ≥7 (C-02 ✅)**；`#D64545` 边框对其 **3.42:1 ≥3 (C-03 ✅)**。⇒ **即便在自家红底上，白字与红框仍双双达标。**
- 色盲模式（C-06）：ALERT 边框 **`#D64545 → #F0C070`**（L=0.574）。此时 SUSPICIOUS（`#C8862F`，L=0.295）与 ALERT **同属琥珀族但亮度比 1.81:1 可分**，再叠 **空心圆环 `?` vs 实心三角 `!` 图标（面积级差异）+ 填充亮度档（0.60 vs 0.92）+ 脉冲频率 0.5Hz 单拍 vs 2.0Hz 双拍** ⇒ C-05/C-07 成立，**不靠单一色相**。`#F0C070` vs 面板 `#16181D` = **10.55:1**，连 C-02 都过。
  > **⚠️ 本行旧理据已被推翻（Sprint 3 更正）**：原文写「ALERT 边框 `#D64545 → #C8862F`…SUSPICIOUS 与 ALERT **同为琥珀**…C-05/C-07 仍成立」。该论证**不成立**——警戒 CAUTION **本就是** `#C8862F`，旧映射后两档是**同一色值、亮度比 1.00:1**，C-05 三重编码的**亮度维度彻底塌缩**，只剩 `?`/`!` 笔画级字符可辨（`hud-a11y-signature.md` v1.1 §5 / art-bible v0.3 §9.1 / control-manifest v0.2 C-06 已明文作废旧口径）。**请勿照此旧文实现。**
  > 另：**脉冲频率与图标面积编码为常驻维度，不随色盲开关切换**——因默认模式下 `#C8862F` vs `#D64545` 亮度比也仅 1.44:1。

#### 2.3.3 可疑度条亮度阶梯（★ 本文新增派生规格，见 §11 NEW-1）

> **为何不能直接拿 tier 语义色当填充**：GDD 要求「**亮度递增**」，但签字色板的相对亮度为 `CALM 0.100 → CAUTION 0.295 → ALARM 0.190` —— **非单调**（琥珀比警报红更亮）。若拿语义色作填充，亮度阶梯会**倒挂**，直接违反 C-04/C-05「亮度编码」。
> **解法（零新色相）**：语义色**只作边框**（正是签字稿 §3 的原话「上升中的可疑度条**边框**」/「警报**边框**」），**填充改用 Carrier 白的 α 阶梯**。α 阶梯在数学上严格单调，且不引入任何色相。

```gdscript
# 可疑度条填充 = HUD_COLOR_CARRIER 在 tier 对应 alpha 下的合成（严格单调递增）
const SUS_FILL_ALPHA := {
    EventBus.SusTier.CALM:       0.30,
    EventBus.SusTier.SUSPICIOUS: 0.60,
    EventBus.SusTier.SEARCH:     0.75,
    EventBus.SusTier.ALERT:      0.92,
}
# tier -> 边框语义色（色盲模式下 ALERT 换 HUD_COLOR_ALARM_CB）
const SUS_BORDER := {
    EventBus.SusTier.CALM:       HudColors.HUD_COLOR_CALM,
    EventBus.SusTier.SUSPICIOUS: HudColors.HUD_COLOR_CAUTION,
    EventBus.SusTier.SEARCH:     HudColors.HUD_COLOR_CAUTION,
    EventBus.SusTier.ALERT:      HudColors.HUD_COLOR_ALARM,
}
# tier -> 图标字形（形状编码，C-05）
const SUS_ICON := {
    EventBus.SusTier.CALM: "◉", EventBus.SusTier.SUSPICIOUS: "?",
    EventBus.SusTier.SEARCH: "⌕", EventBus.SusTier.ALERT: "!",
}
```

| tier | 填充 α | 合成后 L | 对面板对比度 | 相邻档亮度比 |
| --- | --- | --- | --- | --- |
| CALM | 0.30 | 0.090 | 2.37:1 | — |
| SUSPICIOUS | 0.60 | 0.284 | **5.66:1** | **2.39×** ↑ |
| SEARCH | 0.75 | 0.432 | **8.16:1** | 1.44× ↑ |
| ALERT | 0.92 | 0.645 | **11.75:1** | **2.08×**（vs SUSPICIOUS）↑ |

> ✅ 严格单调；相邻主档亮度比 ≥2.0×（色盲三类下靠亮度即可区分，C-04/C-05）；未引入任何新色相（不违反 art-bible §2.4）。

### 2.4 SusTier ↔ GuardState 映射（C5-a，不变）

```gdscript
func compute_tier(s: float, state: int) -> EventBus.SusTier:
    if state == EventBus.GuardState.SEARCH:
        return EventBus.SusTier.SEARCH          # FSM 覆写（system-breakdown §2.3 明文）
    if s >= THR_ALERT:  return EventBus.SusTier.ALERT
    if s >= THR_SUSP:   return EventBus.SusTier.SUSPICIOUS
    return EventBus.SusTier.CALM
```
`RETURN` 无对应 tier：进入 RETURN 的唯一条件是 `S<10`（软失败时 `S` 已复位 0）⇒ 按 value 必落 `CALM`，**无需特判**。

---

## 3. 逐 Story 实现规格（12 条）

> 每条给出：**文件路径 → 新增/修改函数签名 → 关键常量 → 伪码 → 测试钩子（映射 §8 编号）→ 地雷落点**。

---

### 3.1 E08-S1 · 五态 FSM（`patrol-ai` §2）

**文件**：`src/game/patrol_ai.gd`（新建）

```gdscript
class_name GuardBrain
extends Node
# ASHEN STEP — Sprint 1 Batch C. E08 patrol-ai (L3).
# 值域权威：EventBus.GuardState / EventBus.SusTier（L2 词汇表，D6）。
# 本类【不】自建 GuardState 枚举 —— 双份枚举必漂移。
const EventBus = preload("res://src/core/event_bus.gd")
```

**新增签名**
| 签名 | 说明 |
| --- | --- |
| `func set_event_bus(bus: EventBus) -> void` | 与 `vision_cone.gd` / `sound_propagation.gd` 同构 |
| `func _set_fsm(next: int) -> void` | **唯一**状态写入口；负责 `_path_dirty` 与 `guard_fsm_changed` |
| `func _step_fsm(vis: float, dt: float) -> void` | 转换表求值（每 tick 一次） |
| `func get_state() -> int` | 只读访问（测试/HUD/姿态） |

**状态变量**
```gdscript
var guard_id: int = 1
var fsm: int = EventBus.GuardState.CALM
var suspicion: float = 0.0                    # [0,100]
var last_known: Vector3 = Vector3.ZERO
var exposure_timer: float = 0.0               # 真实时间
var _lost_timer: float = 0.0                  # ALERT 下持续无视觉的累计（→ LOST_TARGET_RT）
var _return_timer: float = 0.0                # RETURN 归位累计（→ RETURN_SETTLE_RT）
```

**完整转换表（照抄，无遗漏）**
| 起 | 止 | 条件 | 备注 |
| --- | --- | --- | --- |
| `CALM` | `SUSPICIOUS` | `S ≥ THR_SUSP` | 上行 |
| `SUSPICIOUS` | `ALERT` | `S ≥ THR_ALERT` | 上行；进入触发 A*（§3.5） |
| `SUSPICIOUS` | `RETURN` | `S < THR_RETURN` | **下行统一走 RETURN** |
| `ALERT` | `SEARCH` | `vis ≤ STIM_EPS` 持续 `LOST_TARGET_RT(0.5s)` | 进入触发 A* 去 `last_known` |
| `ALERT` | `RETURN` | 软失败（`exposure_timer ≥ GRACE_RT`） | 强制路径，§3.4 |
| `SEARCH` | `ALERT` | `vis > STIM_EPS` | 重新捕获 |
| `SEARCH` | `RETURN` | `S < THR_RETURN` | 靠 decay 自然超时（60→10 ≈6.25s），**不引入 SEARCH_TIMEOUT** |
| `RETURN` | `CALM` | `_return_timer ≥ RETURN_SETTLE_RT(1.0s)` | Sprint 1 最小化；Sprint 2 换真实归位判据 |
| `RETURN` | `SUSPICIOUS` | `S ≥ THR_SUSP` | 归位途中被重新惊动，**允许打断** |
| 任意 | `RETURN` | 软失败 | 强制路径 |

**抖动防护三纪律（结构性，无需 hysteresis 常量）**
1. **无逐级下行**——不存在 `ALERT→SUSPICIOUS→CALM`；任何下行只在 `S<10` 时一次性进 `RETURN`。25/60 只作**上行**阈值 ⇒ 阈值抖动被结构性消除。
2. `guard_fsm_changed` **仅 `old != new` 时发**。
3. 允许**跨级**：同 tick 从 5 跳到 65 ⇒ `CALM→ALERT` 一步到位，**只发一次**信号，不补中间态（边缘 E9）。

**伪码**
```gdscript
func _step_fsm(vis: float, dt: float) -> void:
    match fsm:
        EventBus.GuardState.CALM:
            if suspicion >= THR_SUSP: _set_fsm(EventBus.GuardState.SUSPICIOUS)
        EventBus.GuardState.SUSPICIOUS:
            if suspicion >= THR_ALERT:        _set_fsm(EventBus.GuardState.ALERT)
            elif suspicion < THR_RETURN:      _set_fsm(EventBus.GuardState.RETURN)
        EventBus.GuardState.ALERT:
            if vis <= STIM_EPS:
                _lost_timer += dt
                if _lost_timer >= LOST_TARGET_RT: _set_fsm(EventBus.GuardState.SEARCH)
            else:
                _lost_timer = 0.0
        EventBus.GuardState.SEARCH:
            if vis > STIM_EPS:                _set_fsm(EventBus.GuardState.ALERT)
            elif suspicion < THR_RETURN:      _set_fsm(EventBus.GuardState.RETURN)
        EventBus.GuardState.RETURN:
            if suspicion >= THR_SUSP:         _set_fsm(EventBus.GuardState.SUSPICIOUS)
            else:
                _return_timer += dt
                if _return_timer >= RETURN_SETTLE_RT: _set_fsm(EventBus.GuardState.CALM)

func _set_fsm(next: int) -> void:
    if next == fsm: return                                  # 纪律 2
    var prev: int = fsm
    fsm = next
    _lost_timer = 0.0
    _return_timer = 0.0
    if next == EventBus.GuardState.ALERT or next == EventBus.GuardState.SEARCH:
        _path_dirty = true                                  # G-05，§3.5
    if _bus != null:
        _bus.guard_fsm_changed.emit(guard_id, prev, next)   # 【D6】int enum
```

**测试钩子**：**H1** `test_fsm_transitions`
**地雷落点**：无（但 `_set_fsm` 是 §3.5 A* 置脏与 §3.6 信号的共同宿主，改动须同步）

---

### 3.2 E08-S2 · 连续可疑度 25/60/10（★ 批内最关键，D5 落点）

**文件**：`src/game/patrol_ai.gd`

**新增签名**
| 签名 | 说明 |
| --- | --- |
| `func tick_real(delta_real: float) -> void` | **真实时间**入口（对齐 `step_commit.gd:131` 既有命名） |
| `func _process(_scaled: float) -> void` | 从 `Time.get_ticks_msec()` 求真实 delta 后转调 `tick_real`（**照抄 `step_commit.gd:138-147` / `vision_cone.gd:154-160` 既有模式**） |
| `func _decide(dt: float) -> void` | 单次固定步长决策 |
| `func _on_vision_stimulus(guard_id: int, target: Node, visibility: float) -> void` | 累积到 `_pending_vision` |
| `func _on_sound_emitted(payload: Dictionary) -> void` | 累积到 `_pending_sound_max`（§3.12） |

**缓冲变量**
```gdscript
var _accum: float = 0.0
var _last_ms: int = 0
var _pending_vision: float = 0.0
var _pending_sound_max: float = 0.0
var _pending_sound_count: int = 0
var _pending_target: Node = null
var decision_count: int = 0          # G-04 断言用（§3.3）
```

**伪码（一次 tick 的完整结算顺序，⚠️ 顺序不可调换）**
```gdscript
func tick_real(delta_real: float) -> void:
    _accum += delta_real
    var n := 0
    while _accum >= TICK_DT and n < MAX_CATCHUP_TICKS:
        _decide(TICK_DT)
        _accum -= TICK_DT
        n += 1
    if n >= MAX_CATCHUP_TICKS:
        _accum = 0.0                          # E5：长卡顿丢弃积压，不做补偿螺旋

func _decide(dt: float) -> void:
    decision_count += 1
    var vis: float = _pending_vision                       # [0,1]
    var snd: float = _pending_sound_max                    # [0,1]，本 tick MAX（E2）
    var had_sound: bool = _pending_sound_count > 0

    # ② stimulus 判据（E3：用 STIM_EPS，绝不用 > 0.0）
    var stimulus: bool = (vis > STIM_EPS) or had_sound

    # ③ 累积 ——【D5】视觉按速率、声音按脉冲
    var d: float = KV * vis * dt
    if had_sound:
        d += KS * snd                                      # ★不乘 dt，单位「点/次」

    # ④ 衰减（E4：与累积互斥，同 tick 不会既加又减）
    if not stimulus:
        d -= DECAY * dt

    # ⑤ 双端钳制（E1：上限 100 截断，不隐形累积超额）
    suspicion = clampf(suspicion + d, 0.0, 100.0)

    # ⑥ last_known 写入优先级（§3.12）
    _update_last_known(vis)
    # ⑦ 暴露计时（§3.4）→ ⑧ FSM（§3.1）→ ⑨ A*（§3.5）→ ⑩ 信号（§3.6）
    _step_exposure(vis, dt)
    _step_fsm(vis, dt)
    _ensure_path()
    _maybe_mark_transform_dirty()
    _emit_if_changed()

    # ⑪ 清空本 tick 脉冲缓冲（不清 _pending_vision —— 视觉是持续量，由 E05 每 tick 覆写）
    _pending_sound_max = 0.0
    _pending_sound_count = 0
```

**边缘情况（须逐条有断言）**
| # | 情况 | 规定行为 |
| --- | --- | --- |
| E1 | `S` 超 `[0,100]` | 双端 `clampf`；上限 **截断不累积超额** |
| E2 | 同 tick 多个 `sound_emitted` | **取 falloff 的 max，不求和**（防「密集小声 > 单次大声」刷分） |
| E3 | `vis = 1e-7` 浮点噪声 | 用 `> STIM_EPS(0.001)` 判，**不用 `> 0.0`**（否则守卫永远记仇） |
| E4 | 同 tick 既有刺激又想衰减 | **互斥**：`stimulus == true` 时 decay 恒为 0 |
| E5 | 一帧 `delta_real = 0.5s` | 固定步长追赶，上限 `MAX_CATCHUP_TICKS(3)`，超出丢弃 |
| E6 | 两 tick 之间到 3 次声事件 | 全并入下一 tick，按 E2 取 max，**只计一次脉冲**（防绕过 G-04） |

**派生时间预算表（QA 断言取值 / playtest 校准）**

| 场景 | `vis` | dS/dt | →25 | →60 | →软失败(+1.2s) |
| --- | --- | --- | --- | --- | --- |
| 全亮开阔 | 1.00 | +35.0 | **0.71s** | **1.71s** | **2.91s** |
| 掩体后（×0.6） | 0.60 | +21.0 | 1.19s | 2.86s | 4.06s |
| 半影 | 0.50 | +17.5 | 1.43s | 3.43s | 4.63s |
| 烟雾（×0.3） | 0.30 | +10.5 | 2.38s | 5.71s | 6.91s |
| 暗处 `L≤0.20` | 0.00 | −8.0 | — | — | — |

衰减侧：`100→60` 5.00s ｜ `60→25` 4.375s ｜ `60→10` **6.25s** ｜ `100→0` 12.50s。攻守比 `KV/DECAY = 4.4:1`。

**【D5】声音轴实测口径（主理人锁定值，QA 直接用）**
| 步态 | `GAIT_INTENSITY` | 半程 falloff | 步频 | 脉冲口径净增速 | 到 25 |
| --- | --- | --- | --- | --- | --- |
| SNEAK | 0.3 | 0.15 | 1.8/s | **−2.5 pts/s** | **永不被听见** ✅ |
| WALK | 0.6 | 0.30 | 2.6/s | **+5.8 pts/s** | **≈4.3s** |
| RUN | 1.0 | 0.50 | 4.2/s | **+26.6 pts/s** | **≈0.94s**（→ALERT ≈2.3s） |

> **红线复查**：脉冲口径下 RUN 有明确成本（0.94s 起疑），SNEAK 有明确奖励（永不被听见）⇒ **「主导策略」红线解除**；三步态在声音轴上梯度清晰 ⇒ 经济平衡成立。若误按速率口径实现，RUN 净 −4.7 pts/s **永不被听见** ⇒ 声音轴失效 + RUN 变零成本最优解 + 诱饵机制失效 ⇒ **三重违规**。

**测试钩子**：**H2** `test_suspicion_thresholds` · **H3** `test_suspicion_stimulus_suppresses_decay`
**地雷落点**：无

---

### 3.3 E08-S3 · 5–10Hz 节流决策（G-04）· **PASS**

**文件**：`src/game/patrol_ai.gd`（`tick_real` / `_process` 已在 §3.2 给出）

**关键纪律**
- **真实时间口径**（ADR-002/003 + T-02）：`_process(delta)` 的 `delta` **受 `Engine.time_scale` 缩放，不可直接用**。必须：
```gdscript
func _process(_scaled: float) -> void:
    var now := Time.get_ticks_msec()
    var rd := 0.0
    if _last_ms > 0:
        rd = float(now - _last_ms) / 1000.0
    _last_ms = now
    if rd > 0.0:
        tick_real(rd)
```
（与 `step_commit.gd:138-147`、`vision_cone.gd:154-160` **完全同构**，勿另发明。）
- 固定步长 `TICK_DT(0.1)` + `MAX_CATCHUP_TICKS(3)` ⇒ 稳态恰 10Hz，卡顿后不突跳。
- **`guard_transform_dirty` 的检测直接挂在本 tick 上**（`DECISION_HZ=10.0`）⇒ **天然满足 G-03**，不额外起计时器。

**测试钩子**：**H4** `test_fsm_tick_le_10hz`（`@ci:G-04`）
**地雷落点**：无

---

### 3.4 E08-S4 · 暴露 1.2s 宽限软失败（D9 seam ①）

**文件**：`src/game/patrol_ai.gd`

**新增签名**
| 签名 | 说明 |
| --- | --- |
| `func set_checkpoint_sink(sink: Callable) -> void` | **D9 seam ①**；默认空 `Callable()` = no-op |
| `func _step_exposure(vis: float, dt: float) -> void` | ALERT + 可见时累加 `exposure_timer` |
| `func _on_soft_fail(target: Node) -> void` | 软失败复位 + 发信号 + 调 sink |

**Sprint 1 In Scope（做）**
1. `fsm == ALERT` 且 `vis > STIM_EPS` → `exposure_timer += dt`（真实时间）；否则**清零**（宽限期内断 LOS 可自救）。
2. `exposure_timer ≥ GRACE_RT(1.2)` → 发 `exposure_detected(guard_id, target)` ——**本 Story 唯一对外契约**。
3. GuardBrain **自身**复位：`suspicion=0` · `exposure_timer=0` · `last_known=Vector3.ZERO` · `fsm→RETURN`（强制路径）。
4. 调 `_checkpoint_sink.call()`（Sprint 1 注入 no-op / 计数桩）。

**Sprint 1 Out of Scope（做了即范围蔓延，须报主理人）**
❌ 任何 `SaveManager` / `ConfigFile` / `user://` 存档 I/O ❌ 玩家重生 / 世界回滚 / charges 还原 ❌ 重开过场 / 淡入淡出 / 关卡重载

**伪码**
```gdscript
var _checkpoint_sink: Callable = Callable()          # D9 seam ①：默认 no-op

func set_checkpoint_sink(sink: Callable) -> void:
    _checkpoint_sink = sink

func _step_exposure(vis: float, dt: float) -> void:
    if fsm == EventBus.GuardState.ALERT and vis > STIM_EPS:
        exposure_timer += dt
        if exposure_timer >= GRACE_RT:
            _on_soft_fail(_pending_target)
    else:
        exposure_timer = 0.0                          # 宽限期内断 LOS → 自救

func _on_soft_fail(target: Node) -> void:
    suspicion = 0.0
    exposure_timer = 0.0
    last_known = Vector3.ZERO
    _set_fsm(EventBus.GuardState.RETURN)              # 强制路径（§3.1）
    if _bus != null:
        _bus.exposure_detected.emit(guard_id, target)
    if _checkpoint_sink.is_valid():
        _checkpoint_sink.call()                       # Sprint 2 在此接 SaveManager.restore_checkpoint()
```

> **架构正当性**：L3 通过 `Callable` 向上解耦，不直接引用未实现的 L2 服务，符合 `architecture.md` §2 单向依赖。**这是正确分层，不是权宜。** Sprint 2 接线 = 改 1 行注入代码，`GuardBrain` 本身不动。

**测试钩子**：**H5** `test_exposure_grace_1_2s`（`test_step_commit.gd:124` **改写**，`ExposureGuardStub` → 真 `GuardBrain`）· **H6** `test_soft_fail_invokes_checkpoint_sink_once`
**地雷落点**：无

---

### 3.5 E08-S5 · A* 仅状态转换触发并缓存（G-05，D9 seam ②）

**文件**：`src/game/patrol_ai.gd`

**新增签名**
| 签名 | 说明 |
| --- | --- |
| `func set_path_provider(provider: Callable) -> void` | **D9 seam ②**；契约 `request_path(from: Vector3, to: Vector3) -> PackedVector3Array` |
| `func _ensure_path() -> void` | 缓存命中即返回，未命中才调 provider |
| `func get_cached_path() -> PackedVector3Array` | 只读访问 |

```gdscript
var _path_provider: Callable = Callable()
var _cached_path: PackedVector3Array = PackedVector3Array()
var _path_dirty: bool = true

func _ensure_path() -> void:
    if not _path_dirty: return                       # ★缓存命中 —— 非逐帧（G-05）
    if _path_provider.is_valid():
        _cached_path = _path_provider.call(global_position_ref, last_known)
    _path_dirty = false
```
`_path_dirty = true` **只在 `_set_fsm` 进入 `ALERT` / `SEARCH` 时置**（§3.1 伪码内），别处不得置脏。

**Sprint 1 边界声明**：本批**不做**真实寻路移动、**不做**导航网格烘焙、**不做**守卫位移动画。E08-S5 在 Sprint 1 的交付物是**「A* 请求的时机与缓存纪律」**，不是「守卫会走路」。
- Sprint 1 注入：`func(a, b): _astar_calls += 1; return PackedVector3Array([a, b])`
- Sprint 2 注入：真实 `NavServer.request_path`（E01-S8）—— GuardBrain **不动**。

**G-05 完整 headless 断言（四步，照抄）**
1. 进入 `ALERT` → `_astar_calls == 1`
2. 随后连续 20 次 `tick_real` 保持 `ALERT` → `_astar_calls` **仍为 1**
3. `ALERT → SEARCH` → `_astar_calls == 2`
4. 回落 `RETURN → CALM` 后再进 `ALERT` → `_astar_calls == 3`

**测试钩子**：**H7** `test_astar_only_on_transition`（`@ci:G-05`）
**地雷落点**：无

---

### 3.6 E08-S6 · 四信号发射 + tier（★ HUD 唯一数据源 · **地雷 ② 落点**）

**文件**：`src/game/patrol_ai.gd`

**新增签名**
| 签名 | 说明 |
| --- | --- |
| `func compute_tier(s: float, state: int) -> EventBus.SusTier` | §2.4 映射（FSM-aware） |
| `func _emit_if_changed() -> void` | `suspicion_changed` 节流发射 |
| `func _maybe_mark_transform_dirty() -> void` | `guard_transform_dirty` + **W1/W3 接线** |
| `func set_sound_system(sound: SoundPropagator) -> void` | **★地雷 ② 修复入口** |
| `func set_vision_cone(cone: VisionCone) -> void` | W2：`guard_id` ↔ 锥实例 1:1 |
| `func set_transform_state(pos: Vector3, yaw_rad: float) -> void` | 外部驱动守卫位姿（Sprint 1 由测试/关卡脚本驱动） |

**四信号发射时机（E08-S6 验收清单）**
| 信号 | 时机 | 节流 | 消费方 |
| --- | --- | --- | --- |
| `suspicion_changed(guard_id, value, tier)` | tick 末 | `abs(ΔS) ≥ SUS_EMIT_EPS(0.5)` **或** tier 变化 | E09-S2 |
| `guard_fsm_changed(guard_id, old, new)` | `_set_fsm` 内 | 仅 `old != new`；**int enum（D6）** | E09（姿态/调试） |
| `exposure_detected(guard_id, target)` | `exposure_timer ≥ 1.2s` | 每次软失败**恰 1 次** | E09-S6 + 失败流 |
| `guard_transform_dirty(guard_id)` | tick 内位姿超阈 | `XFORM_POS_EPS(0.5m)` / `XFORM_YAW_EPS_DEG(5°)` | E05 视野重算 |

> **节流量化**：8 守卫 × 10Hz 全速广播 = 80 信号/s；`SUS_EMIT_EPS` 节流后典型 **<15 信号/s**。

**伪码**
```gdscript
var _last_emitted_sus: float = -999.0
var _last_emitted_tier: int = -1
var _last_dirty_pos: Vector3 = Vector3.ZERO
var _last_dirty_yaw: float = 0.0
var _sound: SoundPropagator = null            # ★地雷 ②

func _emit_if_changed() -> void:
    var tier: int = compute_tier(suspicion, fsm)
    var moved_enough := absf(suspicion - _last_emitted_sus) >= SUS_EMIT_EPS
    if moved_enough or tier != _last_emitted_tier:
        _last_emitted_sus = suspicion
        _last_emitted_tier = tier
        if _bus != null:
            _bus.suspicion_changed.emit(guard_id, suspicion, tier)

# ★★★ 地雷 ②（W1 + W3）：一处搞定「E05 视野重算」+「E06 距离精筛位置回填」★★★
func _maybe_mark_transform_dirty() -> void:
    var moved  := _pos.distance_to(_last_dirty_pos) >= XFORM_POS_EPS
    var turned := absf(rad_to_deg(angle_difference(_yaw, _last_dirty_yaw))) >= XFORM_YAW_EPS_DEG
    if not (moved or turned):
        return
    _last_dirty_pos = _pos
    _last_dirty_yaw = _yaw
    if _bus != null:
        _bus.guard_transform_dirty.emit(guard_id)   # W3 → E05 视野重算
    if _sound != null:
        _sound.update_guard(guard_id, _pos)         # ★W1 → E06 距离精筛（API 已就绪）
    if _cone != null:
        _cone.set_observer(_pos, _forward())        # W2 → 本守卫自己的锥实例
```

**★ 地雷 ② 详解（守卫位置回填缺失 · W1）**

| 项 | 内容 |
| --- | --- |
| **症状** | `src/game/sound_propagation.gd:44-47` 原注释：「The guard/AI system populates and updates this on `guard_transform_dirty` (**Batch C**)… **Without it, `emit()` cannot distance-filter.**」当前**无任何生产代码调用** `SoundPropagator.update_guard()` / `register_guard()`。 |
| **后果** | `_guard_positions` 恒空 → `sound_propagation.gd:124` 的 `if _guard_positions.has(gid)` 恒 false → `enriched["target_guard_ids"]` 恒为空数组 → **E06-S5 距离衰减全链路静默失效**。而 `test_sound_propagation.gd` 因**直接注入**位置仍然全绿 ⇒ **单测绿、集成死**，是最危险的一类缺陷。 |
| **本批必做** | ① `GuardBrain.set_sound_system(sound)` 注入；② `_ready()` 或注入时立即 `_sound.register_guard(guard_id, _pos)`（**首帧就注册，别等第一次移动**）；③ `_maybe_mark_transform_dirty()` 内 `_sound.update_guard(guard_id, _pos)`（上方伪码）。 |
| **验证钩子** | **H10** `test_guard_position_synced_to_sound_system` —— 移动守卫超 `XFORM_POS_EPS` 后，断言 `SoundPropagator` 内该 `guard_id` 的记录位置**已更新**，且 `emit()` 能把该守卫收进 `target_guard_ids`。 |
| **不改** | `sound_propagation.gd` 的 `register_guard` / `update_guard` / `remove_guard` / `emit` **一行不动**（Batch B 已达标）。本批只做**调用方接线**。 |

**测试钩子**：**H8** `test_suspicion_changed_carries_tier` · **H9** `test_guard_signals_emitted` · **H10** `test_guard_position_synced_to_sound_system`
**地雷落点**：**★ 地雷 ②（W1 守卫位置回填）在此闭合**

> ⚠️ **重名警告 N-1**：`test_suspicion_changed_carries_tier`（新，`test_patrol_ai.gd`）**≠** `test_suspicion_changed_carries_tier_parameter`（已存在，`test_event_bus.gd:84`）。前者验「**发射方算出的 tier 值正确**」（语义层，E08-S6），后者验「信号能带 3 个参数」（词汇层，E01-S9）。**两处注释须互相点名**，否则易被当重复而漏做。

---

### 3.7 E08-S8 · 姿态可读（非颜色，C-05/C-07）· **PASS**

**文件**：`src/game/patrol_ai.gd`

```gdscript
# art-bible §4.1 五态姿态，一一对应 EventBus.GuardState。
# ★纯枚举/字符串，【不含任何色值字段】—— C-05 三类色盲下 100% 可读。
const POSTURE := {
    EventBus.GuardState.CALM:       "LANTERN_LOW",     # 垂灯巡逻
    EventBus.GuardState.SUSPICIOUS: "LANTERN_RAISED",  # 举灯转身
    EventBus.GuardState.ALERT:      "BLADE_DRAWN",     # 拔刃灯高举
    EventBus.GuardState.SEARCH:     "LANTERN_SWEEP",   # 灯左右扫
    EventBus.GuardState.RETURN:     "RETURNING",       # 归位
}

func get_posture() -> String:
    return POSTURE.get(fsm, "LANTERN_LOW")
```

**测试钩子**：**H11** `test_guard_posture_non_color`（断言五态各返回唯一非空姿态；姿态集合与 `GuardState` **一一对应**（size == 5，无重复值）；返回值**不含 `#` 字符**——即不含色值）
**地雷落点**：无。**本条零依赖，可与批内任何阶段并行，建议最早起步。**

---

### 3.8 E09-S2 · 可疑度条（C-02 · **地雷 ① + ③ 落点**）

**文件**：`src/ui/hud_slice.gd`（修改）+ `src/ui/hud_colors.gd`（新建，§2.3）

#### ★★★ 地雷 ① · HUD 双写冲突（**不修即 CI 红 + 玩法级闪烁 bug**）★★★

| 项 | 内容 |
| --- | --- |
| **症状** | `src/ui/hud_slice.gd` 现有**两个**处理器同时写 `_suspicion.value`：<br>`:117 _on_vision_stimulus(...)` → `_suspicion.value = clampf(visibility * 100.0, 0, 100)`（Sprint 0 占位）<br>`:122 _on_suspicion_changed(...)` → `_suspicion.value = clampf(value, 0, 100)`（真实数据源） |
| **后果** | Batch C 一旦让 `GuardBrain` 开始发 `suspicion_changed`，两路会**以 10Hz 互相覆写** → 可疑度条在「瞬时可见度×100」与「累积可疑度」间**高频闪烁**，玩家无法读数 ⇒ **E09-S2 的核心价值被彻底摧毁**（支柱一「读出还差多少被发现」失效）。 |
| **E09-S2 必做（三步，同一次提交内完成）** | ① **删除** `hud_slice.gd:117-119` 的 `_on_vision_stimulus` 整个函数；② **删除** `hud_slice.gd:46-47` 的 `vision_stimulus` 连接（经核查 HUD 侧**无其他用途**）；③ 使 `_on_suspicion_changed` 成为 `_suspicion` 的**唯一写入方**。 |
| **强制连带（否则 CI 红）** | `tests/unit/test_hud_slice.gd:74` `test_suspicion_bar_updates_on_vision_stimulus` 断言的**正是即将被删的旧行为**。必须在**同一提交**内改写为 **H13** `test_suspicion_bar_updates_on_suspicion_changed`。⚠️ **重名警告 N-3。** |

#### 多守卫显示策略（C7，认知过载红线）

| 项 | 规定 |
| --- | --- |
| **条数** | **恰好 1 条**，固定于 HUD 一角 |
| **数据源** | 全体守卫中 `suspicion` **最高**者（argmax） |
| **显示** | 该守卫的 `value`（数字，Carrier 白）+ 其 tier 图标（形状）+ 对应**填充亮度档**（§2.3.3） |
| **平局** | 取 `guard_id` **最小**者（确定性，便于测试） |
| **全体 `S < SUS_EMIT_EPS(0.5)`** | 整条 `visible = false` —— HUD 归于沉寂（支柱四） |
| **不做** | ❌ 逐守卫世界内细条（Sprint 2）❌ 守卫列表/小地图 ❌ 多条并列 |

#### 新增/修改签名

| 签名 | 状态 | 说明 |
| --- | --- | --- |
| `func _on_vision_stimulus(...)` | **★删除** | 地雷 ① |
| `func _on_suspicion_changed(guard_id: int, value: float, tier: int) -> void` | 修改 | 由「直写」改为「入字典 + argmax 刷新」；**唯一写入方** |
| `func _refresh_top_guard() -> void` | 新增 | argmax by value，平局取小 `guard_id` |
| `func _apply_tier_visuals(tier: int) -> void` | 新增 | 填充 α / 边框色 / 图标字形（§2.3.3） |
| `static func relative_luminance(c: Color) -> float` | 新增（`HudColors`） | WCAG 纯函数 |
| `static func wcag_contrast(fg: Color, bg: Color) -> float` | 新增（`HudColors`） | WCAG 纯函数 |
| `static func composite(fg: Color, bg: Color, alpha: float) -> Color` | 新增（`HudColors`） | 半透明预合成（**不采样像素**） |

```gdscript
var _suspicion_by_guard: Dictionary = {}      # guard_id -> {"value": float, "tier": int}

func _on_suspicion_changed(guard_id: int, value: float, tier: int) -> void:
    _suspicion_by_guard[guard_id] = {"value": value, "tier": tier}
    _refresh_top_guard()

func _refresh_top_guard() -> void:
    var best_id := -1
    var best_val := -1.0
    for gid in _suspicion_by_guard:
        var v: float = _suspicion_by_guard[gid]["value"]
        if v > best_val or (is_equal_approx(v, best_val) and gid < best_id):
            best_val = v
            best_id = gid
    if best_id < 0 or best_val < SUS_BAR_HIDE_EPS:      # = SUS_EMIT_EPS(0.5)
        _suspicion.visible = false                       # 支柱四：HUD 归于沉寂
        return
    _suspicion.visible = true
    _suspicion.value = clampf(best_val, 0.0, 100.0)      # ★唯一写入点
    _sus_value_label.text = "%d" % roundi(best_val)      # Carrier 白，C-02
    _apply_tier_visuals(_suspicion_by_guard[best_id]["tier"])
```

#### ★ 地雷 ③ · `#7A2E2E` 无法达 C-02 → 由 D7 签字色板闭合

- **禁止**在 `hud_slice.gd` 内出现任何**硬编码色字面量**（含现有 `:66` 的 `Color("#DCE3EC")`、`:11` 的 `PREVIEW_COLOR`、`:12` 的 `STROKE_COLOR`）——一律改引 `HudColors.HUD_COLOR_*`，并在文件头注明 **`# 色值权威：design/art/hud-a11y-signature.md v1.0（art-signed per D7）`**。
- **禁止**把 `HUD_COLOR_ALARM_FILL`（`#7A2E2E`）用作任何文字 / 关键条主体 / C-03 边界或图标。它**只能**以 `alpha ≤ ALARM_FILL_ALPHA_MAX(0.35)` 作填充底纹。
- 可疑度条：填充 = Carrier α 阶梯；边框 = tier 语义色；数字/图标 = Carrier（§2.3.3）。

**C-02 断言写法（headless 安全，纯数值，不采样像素）**
```gdscript
const P := HudColors.HUD_COLOR_PANEL_BASE                      # #16181D
assert_gt(HudColors.wcag_contrast(HudColors.HUD_COLOR_CARRIER, P), 7.0)  # C-02 数值/图标/内描边
# 交叉核算另两种面板（签字稿 §1）
for panel in [Color("#1B1B1F"), Color("#1C1F26")]:
    assert_gt(HudColors.wcag_contrast(HudColors.HUD_COLOR_CARRIER, panel), 7.0)
assert_gt(HudColors.wcag_contrast(HudColors.HUD_COLOR_CAUTION, P), 3.0)  # C-03 SUSPICIOUS 边框
assert_gt(HudColors.wcag_contrast(HudColors.HUD_COLOR_ALARM,   P), 3.0)  # C-03 ALERT 边框
# ★红线守卫：#7A2E2E 永远不达 C-03 ⇒ 反向断言 + alpha 上限，锁死误用
assert_lt(HudColors.wcag_contrast(HudColors.HUD_COLOR_ALARM_FILL, P), 3.0)
assert_lte(HudColors.ALARM_FILL_ALPHA_MAX, 0.35)
```

**测试钩子**：**H12** `test_suspicion_bar_contrast`（`@ci:C-02`）· **H13** `test_suspicion_bar_updates_on_suspicion_changed`（**改写**）· **H14** `test_suspicion_bar_shows_top_guard_only`
**地雷落点**：**★ 地雷 ①（HUD 双写）与 ★ 地雷 ③（`#7A2E2E`）均在此闭合**

---

### 3.9 E09-S3 · 世界内要素可见性编排（C8）

**文件**：`src/ui/hud_slice.gd`（编排清单）+ `vision_cone.gd` / `sound_propagation.gd` / `footfall_vfx.gd`（各 +1 方法）

**统一接口约定（鸭子类型，非新类非继承）**
```gdscript
# 各绘制系统各实现一次：
func set_readability_boost(on: bool) -> void
# 语义：on=true 把该系统的世界内要素提到「凝神可读档」，false 回常态。
# E09 只调这个方法，【绝不触碰对方的 material/shader】—— 满足「只编排不重绘」。
```

| 系统 | 文件 | 建议实现（各 3 行） |
| --- | --- | --- |
| E05 锥 | `src/game/vision_cone.gd` | boost 时把锥 alpha 锁到 `CONE_VFX_ALPHA_MAX(0.30)`；false 回 `[MIN 0.06, MAX 0.30]` 脉动区间 |
| E06 环 | `src/game/sound_propagation.gd` | boost 时 `RING_COLOR` alpha 提一档；false 回常态 |
| E03 残影 | `src/game/footfall_vfx.gd` | boost 时延长 ghost 淡出时长；false 回常态 |

**E09 侧签名**
| 签名 | 说明 |
| --- | --- |
| `func register_world_element(obj: Object) -> void` | 加入编排清单（`Array[Object]`） |
| `func _on_time_scale_changed(old: float, new: float, mode: String) -> void` | **扩展既有函数**（`hud_slice.gd:104`）：`mode == "FOCUS"` → 全体 `set_readability_boost(true)`；否则 `false` |

```gdscript
var _world_elements: Array[Object] = []

func register_world_element(obj: Object) -> void:
    if obj != null and not _world_elements.has(obj):
        _world_elements.append(obj)

func _set_world_boost(on: bool) -> void:
    for e in _world_elements:
        if is_instance_valid(e) and e.has_method("set_readability_boost"):
            e.set_readability_boost(on)
```

**测试钩子**：**H15** `test_world_element_visibility_toggle`（用 `Object` 桩记 `boost_calls`；进 FOCUS 全体收 `true`，出 FOCUS 收 `false`；**不断言任何像素**）
**地雷落点**：无
**依赖**：仅 Batch A/B ⇒ **可与阶段 1 同时起步**（见 §9）

---

### 3.10 E09-S4 · 道具 / charges 显示（D8 落点）

**文件**：`src/ui/hud_slice.gd`

**payload 形状（GDD 未定义，本文最小集，Sprint 2 可追加不破契约）**
```gdscript
payload = { "charges": int }        # >= 0；0 表示耗尽（HUD 置灰但仍显示，不隐藏）
```
唯一来源：`interactables` §3 的 `charges: int`（MVP 每类 2–3 发）。

**新增签名**
| 签名 | 说明 |
| --- | --- |
| `func _on_interactable_triggered(obj_id: int, type: int, payload: Dictionary) -> void` | **D8 新签名**；`type` 为 `EventBus.InteractableType` int |
| `func _refresh_item_slot() -> void` | 图标 + 文字标签 + charges 数字 |

```gdscript
const ITEM_LABEL := {
    EventBus.InteractableType.DECOY:        "DECOY",
    EventBus.InteractableType.LIGHT_TOGGLE: "LIGHT",
    EventBus.InteractableType.TRAP:         "TRAP",
    EventBus.InteractableType.SMOKE:        "SMOKE",
}
const CHARGES_DIM_ALPHA := 0.4        # charges==0 时图标降档（数字保持全亮）
```

**显示规格（C-05 非颜色 / X-01 文本缩放）**
| 元素 | 规定 |
| --- | --- |
| 类型 | **图标 + 文字标签**（`DECOY`/`LIGHT`/`TRAP`/`SMOKE`），**形状编码，不靠色相** |
| charges | 阿拉伯数字，色 `HudColors.HUD_COLOR_CARRIER`（13.74:1，过 C-01 且顺带过 C-02） |
| `charges == 0` | 图标 alpha 降至 `CHARGES_DIM_ALPHA(0.4)` + **数字保持全亮** ⇒ alpha 与数字**双编码**，不用颜色表达「不可用」 |
| 无道具 | 整槽 `visible = false` |
| X-01 | 文本节点用 `Label` + theme font size 变量，**不写死像素**，为 Sprint 2 的 100–150% 缩放预留 |

> **无 E07 实体依赖 ✅**：`src/**` 中无任何 `interactable_triggered` 生产发射方，本 Story 完全靠测试桩驱动。

**测试钩子**：**H16** `test_charges_display`
**地雷落点**：无
**依赖**：仅 D8 契约（F1）⇒ **全程独立，任意时刻可插入**

---

### 3.11 E09-S6 · 暴露 ALERT + 软重开 UI（D7 + D9 落点）

**文件**：`src/ui/hud_slice.gd`

**新增签名**
| 签名 | 说明 |
| --- | --- |
| `func _on_exposure_detected(guard_id: int, target: Node) -> void` | 显示暴露层（ease 淡入，禁硬切） |
| `func _build_exposure_overlay() -> void` | 构建：填充 + 边框 + `!` 图标 + 标签 + 提示条 |
| `func is_exposure_visible() -> bool` | 测试只读 |

```gdscript
const EXPOSURE_PULSE_HZ   := 2.0     # V-02 上限（对齐 vision_cone.gd:30 CONE_VFX_PULSE_HZ）
const EXPOSURE_FADE_SEC   := 0.4     # V-06 ease 淡入，禁硬切
```

**三重编码构成（C-05/C-07 常开，无开关）**
| 层 | 取色 | 说明 |
| --- | --- | --- |
| 底纹**填充** | `HudColors.HUD_COLOR_ALARM_FILL` **@α = ALARM_FILL_ALPHA_MAX(0.35)** | 仅氛围，非载体 |
| **边框** | `HudColors.HUD_COLOR_ALARM`（`#D64545`） | C-03 ✅ 4.06:1；对自家红底仍 3.42:1 ✅ |
| **图标** `!` | 字形 `HudColors.HUD_COLOR_CARRIER` 填充 + `HUD_COLOR_ALARM` 描边 | 形状编码 |
| **标签/提示文本** | `HudColors.HUD_COLOR_CARRIER` | **C-02 11.59:1**（对合成红底）✅ |
| **脉冲** | 边框/图标 alpha 脉动，`EXPOSURE_PULSE_HZ ≤ 2.0` | V-02 |
| **屏震** | 读 `A11ySettings.screen_shake`（`a11y_settings.gd:15`，默认 `false`） | V-03 可断言默认关 |
| **色盲（C-06）** | 边框/图标 → `HudColors.HUD_COLOR_ALARM_CB`（**`= #F0C070`**；~~`#C8862F`~~ 旧口径已作废，见 §2.3.2 注） | **本批仅预留读取点** `A11ySettings.color_blind_mode`（`a11y_settings.gd:13`），**不做开关** |

**Sprint 1 边界（D9）**
- ✅ 收 `exposure_detected` → 显示暴露 ALERT 覆盖层
- ✅ 显示**静态**「软重开提示条」（文本 + 图标，V-06 ease 淡入，**禁硬切**）
- ✅ 读 `A11ySettings.screen_shake` 决定是否屏震 —— **V-03 本批即可断言达标**
- ❌ **不**接 SaveManager、**不**做真实重生、**不**做重开确认交互（D9 → Sprint 2）

> **设计纪律**：本批交付的暴露 UI **必须在不开任何 a11y 开关的情况下就已色盲安全**——这正是 `accessibility-matrix` Basic 档的定义。开关是增强，不是达标前提。

**测试钩子**：**H17** `test_exposure_alert_ui_non_color`（`@ci:V-02/V-03/C-07`）
**地雷落点**：**★ 地雷 ③** 的第二落点（暴露层是 `#7A2E2E` 的唯一合法用武之地——**仅填充、α≤0.35、上覆白载体**）

---

### 3.12 E06-S5 · 声音按距离衰减提可疑度（E08 消费侧，D5 落点）

**文件**：`src/game/patrol_ai.gd`（**消费侧**）· `src/game/sound_propagation.gd`（**一行不改**）

> **E06 侧已在 Batch B 达标 ✅**：`sound_propagation.gd:203 suspicion_from_distance()` 三项越界防护（`dist≥radius`→0 / `radius=0` 防除零 / intensity 单位）全部就位，测试 `test_suspicion_from_sound_distance` + `..._zero_radius_safe` 已覆盖 `d=0 / R/2 / R / 1.5R / R=0`。**Batch C 不重写该函数、不重建同名用例**（⚠️ **重名警告 N-2**）。

**新增签名（E08 侧）**
| 签名 | 说明 |
| --- | --- |
| `func _on_sound_emitted(payload: Dictionary) -> void` | 从 `sound_emitted` 算 falloff 并累积到 `_pending_sound_max` |
| `func _update_last_known(vis: float) -> void` | `last_known` 三级写入优先级 |

**消费侧口径（必须遵守）**
| 项 | 规定 |
| --- | --- |
| `intensity` 单位 | 无量纲 `[0,1]`，由 gait 派生：`SNEAK 0.3 / WALK 0.6 / RUN 1.0`（`sound_propagation.gd:25`，已锁） |
| `dist` / `radius` 单位 | **米**（世界单位） |
| `dist` 度量 | **3D 欧氏距离** `origin.distance_to(guard_pos)` —— **必须与 `sound_propagation.gd:126` 的 in-radius 精筛口径一致**，否则圈内判定与衰减值不自洽 |
| 返回值域 | `[0, intensity] ⊂ [0,1]` |
| **结算口径** | **【D5】脉冲**：`S += KS(15) × falloff`，**不乘 dt** |
| 同 tick 多声源 | 取 **max**（边缘 E2） |
| `last_known` 写入优先级 | ① `vis > STIM_EPS` → 写目标**真实位置**（优先）；② 无视觉但有声事件 → 写 `payload.origin`；③ 皆无 → **不写**（保留旧值） |

```gdscript
func _on_sound_emitted(payload: Dictionary) -> void:
    # 只处理把本守卫收进 target_guard_ids 的声事件（E06-S1 已做网格 + 精筛）
    var targets: Array = payload.get("target_guard_ids", [])
    if not targets.has(guard_id):
        return
    var origin: Vector3 = payload.get("origin", Vector3.ZERO)
    var radius: float   = float(payload.get("radius", 0.0))
    var intensity: float= float(payload.get("intensity", 0.0))
    var dist: float     = origin.distance_to(_pos)            # 与 emit() 口径一致
    var falloff: float  = _sound.suspicion_from_distance(intensity, dist, radius)
    if falloff <= 0.0:
        return                                                # dist>=radius 或 radius<=0 → 贡献 0
    _pending_sound_max = maxf(_pending_sound_max, falloff)    # E2：取 max 不求和
    _pending_sound_count += 1
    _pending_sound_origin = origin                            # last_known 次级来源
```

**边缘情况**
| # | 情况 | 规定行为 |
| --- | --- | --- |
| E11 | `dist == radius` 边界 | 返回 **0**（闭区间外沿取 0）。与 `emit()` 的 `<= radius` 收录判据组合后 = 「边界守卫被通知但贡献 0」—— 无害且行为确定，**不需改 `emit()`** |
| E12 | `radius = 0`（退化声事件） | 返回 0，grid 查询亦返回空 ⇒ 全链路静默，不崩 |
| E13 | 多层关卡垂直高差大 | 3D 距离会因高差衰减。MVP 单层 y 近似恒定，无影响。**Sprint 2 若引入多层，须改「分层判定 + 水平距离」**——本文标记为**已知限制** |
| E7 | 纯声音把 `S` 推过 60 但**从未见过目标** | 进 `ALERT` 后因 `vis ≤ EPS` 持续 0.5s **立即转 `SEARCH`**，`last_known` 取最近一次声事件 `origin`（优先级 ②）。守卫**不会对着空气拔刀** |

**⚠️ 平衡风险 B-1（Batch D 复验，不阻塞本批）**：DECOY 声圈 `radius≈8m`，`intensity=1.0` 时守卫在半程单次脉冲仅 `15×0.5 = 7.5` 点，**远不足 `THR_SUSP(25)`** ⇒ 守卫不去调查，诱饵机制失效（损支柱三）。建议 E06-S4（Batch D）复验时：`source == DECOY` 的声事件**额外无条件写入 `last_known = origin`**（不加权）。若 playtest 仍不足，再考虑 `KS_DECOY` 专属系数（**Tier2 可调参，不在 Batch C 硬编码**）。

**测试钩子**：**H18** `test_suspicion_accumulates_from_sound_event`（单次满强度声事件 → `S += 15×falloff`，**脉冲不乘 dt**；同 tick 3 事件取 max 只计一次；`dist ≥ radius` 贡献 0）
**地雷落点**：**依赖地雷 ② 已修复**——若 `_sound.update_guard` 未接线，本 Story 在集成层静默失效（单测仍绿）。**H10 与 H18 必须成对通过。**

---

## 4. 三处地雷 · 汇总索引（工程 checklist）

| # | 地雷 | 落点 Story | 落点文件:函数 | 验证钩子 | 漏做后果 |
| --- | --- | --- | --- | --- | --- |
| **①** | **HUD 双写冲突** | **E09-S2** | `src/ui/hud_slice.gd`：**删除** `_on_vision_stimulus()`（:117-119）+ **删除** `vision_stimulus` 连接（:46-47）；`_on_suspicion_changed` 为**唯一**写入方 | **H13**（`test_hud_slice.gd:74` **必须同提交改写**） | 可疑度条 10Hz 高频闪烁；**且 CI 立即红**（旧用例断言被删行为） |
| **②** | **守卫位置回填缺失（W1）** | **E08-S6** | `src/game/patrol_ai.gd`：`set_sound_system()` 注入 + `_ready` 首帧 `register_guard()` + `_maybe_mark_transform_dirty()` 内 `_sound.update_guard(guard_id, _pos)` | **H10**（+ **H18** 成对） | `_guard_positions` 恒空 → `target_guard_ids` 恒空 → **E06-S5 全链路静默失效**，而单测全绿（最危险类型） |
| **③** | **`#7A2E2E` 无法达 C-02** | **E09-S2 + E09-S6** | `src/ui/hud_colors.gd`（新建，D7 签字色板）；`hud_slice.gd` 全面改引 `HudColors.HUD_COLOR_*`，禁一切硬编码色字面量 | **H12**（含反向断言 `wcag_contrast(ALARM_FILL, panel) < 3.0` + `ALARM_FILL_ALPHA_MAX ≤ 0.35`） | 关键指示对比度 1.91:1，**C-02 永久不可能达标**；且与 D7 美术签字稿冲突（视觉漂移） |

---

## 5. 常量 ↔ Story ↔ 钩子 交叉表

| 常量 | 值 | 来源 | 用于 Story | 断言钩子 |
| --- | --- | --- | --- | --- |
| `THR_SUSP / THR_ALERT / THR_RETURN` | 25 / 60 / 10 | GDD §3 已锁 | E08-S1/S2/S6 | H1 H2 H8 |
| `KV / KS / DECAY` | 35 / 15 / 8 | GDD §3 已锁；**KS 单位由 D5 定为「点/次」** | E08-S2 · E06-S5 | H2 H3 H18 |
| `GRACE_RT` | 1.2 s | GDD §3 已锁 | E08-S4 | H5 |
| `DECISION_HZ / TICK_DT` | 10.0 Hz / 0.1 s | GDD §3 / G-04 | E08-S3 | H4 |
| `LOST_TARGET_RT` | **0.5 s** | **D10** | E08-S1 | H1 |
| `RETURN_SETTLE_RT` | **1.0 s** | **D10** | E08-S1 | H1 |
| `STIM_EPS` | **0.001** | **D10** | E08-S2/S4 | H3 |
| `SUS_EMIT_EPS` | **0.5** | **D10** | E08-S6 · E09-S2 | H9 H14 |
| `MAX_CATCHUP_TICKS` | **3** | **D10** | E08-S2/S3 | H4 |
| `XFORM_POS_EPS` | **0.5 m** | **D10** | E08-S6 | H9 H10 |
| `XFORM_YAW_EPS_DEG` | **5.0°** | **D10** | E08-S6 | H9 |
| `HUD_COLOR_CARRIER` | `#DCE3EC` | **D7 签字** | E09-S2/S4/S6 | H12 H17 |
| `HUD_COLOR_CALM` | `#3E5C76` | **D7 签字** | E09-S2 | H12 |
| `HUD_COLOR_CAUTION` | `#C8862F` | **D7 签字** | E09-S2 | H12 |
| `HUD_COLOR_ALARM` | `#D64545` | **D7 签字** | E09-S2/S6 | H12 H17 |
| `HUD_COLOR_ALARM_FILL` | `#7A2E2E`（仅填充） | **D7 签字** | E09-S6 | H12（**反向断言**） H17 |
| `HUD_COLOR_ALARM_CB` | **`#F0C070`**（~~`= CAUTION`~~ 作废） | **D7 签字 + v1.1 追认改判** | E09-S6（C-06 预留） | H17 |
| `ALARM_FILL_ALPHA_MAX` | 0.35 | **D7 签字 §3** | E09-S6 | H12 H17 |
| `SUS_FILL_ALPHA` | 0.30/0.60/0.75/0.92 | **本文派生（NEW-1）** | E09-S2 | H12 H13 |
| `EXPOSURE_PULSE_HZ` | 2.0 | V-02 | E09-S6 | H17 |
| `CHARGES_DIM_ALPHA` | 0.4 | 本文（C-05 双编码） | E09-S4 | H16 |

---

## 6. 事件词汇一致性（收口后终态）

| 信号 | `system-breakdown` §2（权威） | 本批终态 | 判定 |
| --- | --- | --- | --- |
| `suspicion_changed` | `(guard_id:int, value:float[0..100], tier:SusTier)` | 不变 | ✅ 一致 |
| `exposure_detected` | `(guard_id:int, target:Node)` | 不变 | ✅ 一致 |
| `guard_transform_dirty` | `(guard_id:int)` | 不变（阈值本文补） | ✅ 一致 |
| `guard_fsm_changed` | `(guard_id:int, old:GuardState, new:GuardState)` | **`(guard_id:int, old:GuardState, new:GuardState)`** | ✅ **D6 收口后完全一致（漂移消除）** |
| `interactable_triggered` | `(obj_id:int, type:InteractableType, payload)` | **`(obj_id:int, type:InteractableType, payload:Dictionary)`** | ✅ **D8 收口后完全一致（漂移消除）** |

| 共享类型 | §2.3 | 收口后 `event_bus.gd` | 判定 |
| --- | --- | --- | --- |
| `LightState` | `LIT \| EXTINGUISHED` | 已声明 | ✅ |
| `SusTier` | 4 成员 | 已声明 | ✅ |
| `GuardState` | 5 成员 | **本批新增（D6）** | ✅ |
| `InteractableType` | 4 成员 | **本批新增（D8）** | ✅ |
| `SoundSource` | 4 成员 | `const` 字符串镜像 | ✅ 可接受（Batch B 既定） |

> **结论**：本批收口后，`system-breakdown` §2 词汇表与 `event_bus.gd` **零漂移**。评审 §5.4 点名的 2 项漂移**全部消除**。

---

## 7. 上游文档同步动作（本文一并执行）

### 7.1 已执行（A1–A8 已于 Batch C 评审闭合时落实）

| # | 文件 | 动作 |
| --- | --- | --- |
| A1 | `production/sprints/batchc-design-review.md` | §7 六项裁决全部标 **CLOSED** + 采纳值；§0/§8 同步；新增 §7.1 裁决落地记录（含 D6 推翻 R1、D7 三档变体作废的说明） |
| A2 | `design/ux/ux-spec.md` | L194 / L227 / L341：ALERT 边框·脉冲·图标 `#7A2E2E` → `#D64545`，`#7A2E2E` 标注**仅填充 α≤0.35** |
| A3 | `design/assets/entity-inventory.md` | #22 暴露 ALERT（L44）：同上 |
| A4 | `design/assets/asset-manifest.md` | #暴露 ALERT（L251）+ 守卫特效钩子（L222）：同上 |
| A5 | `design/gdd/systems/core-hud-a11y.md` | §5 反馈（L50）：同上（签字稿 §6 待同步表所列） |
| A6 | `design/gdd/systems/patrol-ai.md` | §5 Sensation（L57）：同上 |
| A7 | `production/epics/E09-core-hud-a11y.md` | 范围（L17）+ E09-S6 验收（L64/L66）：同上（**工程/QA 直读，不改必复发地雷 ③**） |
| A8 | `production/sprints/sprint1-stories.md` | E09-S6 验收（L332）：同上（同 A7 理由） |

### 7.2 建议后续同步（**不在本批**，非阻塞）

| 文件 | 位置 | 说明 |
| --- | --- | --- |
| `docs/architecture/control-manifest.md` | C-06 / C-07（L63/L64） | 语义正确（讲的是「品牌危险色不得单独使用」），但建议补注「HUD 落地色见 hud-a11y-signature.md」 |
| `design/art/art-bible.md` | §2.4 / §4 / §9（L72/L228/L249） | 同上；`#D64545` 已被签字稿认定为 `#7A2E2E` 明度变体，不违反「禁新色相」 |
| `design/art/accessibility-matrix.md` | 行 3 / 行 4 / §4 | 同上 |
| `design/gdd/systems/vision-cone.md` | §7（L72） | 讲 C-07 通则，非 HUD 边框，可不改 |
| `design/reviews/sprint1-design-scope.md`、`sprint0-design-review.md` | — | **历史评审快照，按纪律不追改** |
| `sprint1-stories.md` E03-S5 | L48「SNEAK+MOSS 2.5」 | 与已锁公式 `5.0×MOSS(0.5)×SNEAK(0.5)=1.25` 不符（代码与 `test_step_commit.gd:181` 均为 1.25）。**Story 举例文字过时**，建议 Batch D 顺手 Edit，本批不动 |

---

## 8. 测试钩子映射表（18 钩子 · 对应评审 §4）

> **约定**：`@ci:*` 类硬约束本批**一律落为 GUT 单测断言**（headless 可跑）。`tests/ci/budget_assert.gd` 扩展属 **E10-S2（Batch D）**，Batch C **不碰 CI 脚本**。

| H# | Story | 测试文件 | 钩子名 | 断言要点 | 状态 |
| --- | --- | --- | --- | --- | --- |
| **H1** | E08-S1 | `test_patrol_ai.gd` | `test_fsm_transitions` | §3.1 转换表逐条；`old/new` 为 **`EventBus.GuardState` int（D6）**；**S 在 24.9↔25.1 抖动 20 次 → `guard_fsm_changed` ≤2 次** | 新建文件 |
| **H2** | E08-S2 | `test_patrol_ai.gd` | `test_suspicion_thresholds` | `vis=1.0` → 0.71s 达 25 / 1.71s 达 60（±1 tick）；衰减 8/s；**上限 100 不超额**（喂 200 后断 LOS，6.25s 内必回 10）；下限 0 | 新建 |
| **H3** | E08-S2 | `test_patrol_ai.gd` | `test_suspicion_stimulus_suppresses_decay` | `vis>STIM_EPS` 的 tick **不扣 decay**；`vis=1e-7` 时**仍扣**（E3） | 新建 |
| **H4** | E08-S3 | `test_patrol_ai.gd` | `test_fsm_tick_le_10hz` `@ci:G-04` | 注入 2.0s 真实时间 → `decision_count ∈ [10,20]`；**`Engine.time_scale=0.25` 下计数不变**（T-02/ADR-003）；单帧 0.5s → 追赶 ≤3 次 | 新建 |
| **H5** | E08-S4 | `test_step_commit.gd` | `test_exposure_grace_1_2s` | **`ExposureGuardStub` → 真 `GuardBrain`**：ALERT+可见 1.0s **不触发**、1.2s **触发**；宽限内断 LOS → `exposure_timer` 归零可自救；软失败后 `suspicion==0` 且 `fsm==RETURN` | **改写**（现 `:124 test_exposure_grace_1_2s_triggers_soft_fail`） |
| **H6** | E08-S4 | `test_patrol_ai.gd` | `test_soft_fail_invokes_checkpoint_sink_once` | 注入计数 `Callable` → 软失败**恰调 1 次**；**未注入时不崩**（D9 seam ①） | 新建 |
| **H7** | E08-S5 | `test_patrol_ai.gd` | `test_astar_only_on_transition` `@ci:G-05` | §3.5 四步：进 ALERT=1 · 保持 20 tick 仍=1 · 转 SEARCH=2 · 回落再进 ALERT=3 | 新建 |
| **H8** | E08-S6 | `test_patrol_ai.gd` | `test_suspicion_changed_carries_tier` | 24.9→CALM · 25.0→SUSPICIOUS · 59.9→SUSPICIOUS · 60.0→ALERT · `fsm==SEARCH` 时**覆写**为 SEARCH · RETURN 态 tier==CALM（E10） | 新建 ⚠️ **N-1** |
| **H9** | E08-S6 | `test_patrol_ai.gd` | `test_guard_signals_emitted` | 四信号全覆盖：`guard_fsm_changed` 仅 `old!=new`；`suspicion_changed` 受 `SUS_EMIT_EPS(0.5)` 节流；`exposure_detected` 每次软失败恰 1 次；`guard_transform_dirty` 按 0.5m/5° 阈值 | 新建 |
| **H10** | E08-S6 | `test_patrol_ai.gd` | `test_guard_position_synced_to_sound_system` | **★地雷 ②**：注入 `SoundPropagator` → 首帧已 `register_guard`；移动 >0.5m 后其内部位置**已更新**；`emit()` 能把该守卫收进 `target_guard_ids` | 新建（**高价值**） |
| **H11** | E08-S8 | `test_patrol_ai.gd` | `test_guard_posture_non_color` | 五态各返回唯一非空姿态；集合与 `GuardState` 一一对应（size==5，无重复）；返回值**不含 `#`**（C-05） | 新建 |
| **H12** | E09-S2 | `test_hud_slice.gd` | `test_suspicion_bar_contrast` `@ci:C-02` | §3.8 断言块：Carrier vs 三种面板 **>7.0**；Caution/Alarm 边框 **>3.0**；**★反向断言** `ALARM_FILL < 3.0` 且 `ALARM_FILL_ALPHA_MAX ≤ 0.35`；`SUS_FILL_ALPHA` 四档**严格单调**。**不采样像素** | 新建 |
| **H13** | E09-S2 | `test_hud_slice.gd` | `test_suspicion_bar_updates_on_suspicion_changed` | **★地雷 ①**：条值**只**由 `suspicion_changed` 驱动；发 `vision_stimulus` 后条值**不变**（反向证明双写已断）；tier 变化时图标切换 | **改写**（原 `:74 ..._on_vision_stimulus`）⚠️ **N-3** |
| **H14** | E09-S2 | `test_hud_slice.gd` | `test_suspicion_bar_shows_top_guard_only` | 3 守卫 10/70/40 → 显示 **70** 且 tier==ALERT；平局取小 `guard_id`；全体 <0.5 → 整条隐藏 | 新建 |
| **H15** | E09-S3 | `test_hud_slice.gd` | `test_world_element_visibility_toggle` | 注册 3 个编排桩 → 进 FOCUS 全体收 `set_readability_boost(true)`；出 FOCUS 收 `false`；**不断言像素** | 新建 |
| **H16** | E09-S4 | `test_hud_slice.gd` | `test_charges_display` | 桩发 `interactable_triggered(1, EventBus.InteractableType.DECOY, {"charges":2})`（**D8 新签名**）→ 槽显示 `DECOY` + 数字 2；`charges==0` → 图标 alpha 降至 0.4 但数字全亮；无道具 → 槽隐藏 | 新建 |
| **H17** | E09-S6 | `test_hud_slice.gd` | `test_exposure_alert_ui_non_color` `@ci:V-02/V-03/C-07` | `exposure_detected` → 暴露层可见；**图标节点非空 + 形状节点非空**（C-07）；`EXPOSURE_PULSE_HZ <= 2.0`（V-02）；`A11ySettings.screen_shake == false`（V-03）；暴露层**边框色 == `HUD_COLOR_ALARM`**（**不是** `ALARM_FILL`）；暴露层文本 vs 合成红底 **>7:1**（C-02） | 新建 |
| **H18** | E06-S5 | `test_patrol_ai.gd` | `test_suspicion_accumulates_from_sound_event` | **E08 消费侧**：单次满强度声事件 → `S += 15×falloff`（**脉冲，不乘 dt**）；同 tick 3 事件取 **max** 只计一次（E2）；`dist ≥ radius` 贡献 0 | 新建 ⚠️ **N-2** |

### 8.1 三处重名 / 已存在警告（必读）

| # | 冲突 | 处置 |
| --- | --- | --- |
| **N-1** | `test_suspicion_changed_carries_tier`（新，`test_patrol_ai.gd`）**vs** `test_suspicion_changed_carries_tier_parameter`（已存在，`test_event_bus.gd:84`） | **职责不同，非重复**：后者验「信号能带 3 参」（词汇层 E01-S9），前者验「**发射方算出的 tier 值正确**」（语义层 E08-S6）。**两处注释须互相点名。** |
| **N-2** | `test_suspicion_from_sound_distance` | **已在 Batch B 落盘**（`test_sound_propagation.gd:139` + `:154`）。Batch C **不要重建同名用例**；E08 消费侧用新名 `test_suspicion_accumulates_from_sound_event`。 |
| **N-3** | `test_suspicion_bar_updates_on_vision_stimulus`（`test_hud_slice.gd:74`，**当前绿**） | 断言的正是地雷 ① 要删除的旧行为。**只加新逻辑而不改这条 ⇒ Batch C 上线即 CI 红。** 必须与地雷 ① 修复**同一次提交内完成**。 |

### 8.2 `@ci:*` 硬约束本批落法

| 约束 | 本批 | Batch D（E10-S2） |
| --- | --- | --- |
| `G-04` ≤10Hz | GUT `test_fsm_tick_le_10hz` 计数断言 | — |
| `G-05` A* 仅转换 | GUT `test_astar_only_on_transition` 计数断言 | — |
| `C-02` ≥7:1 | GUT `HudColors.wcag_contrast()` 纯函数断言 | 可选加入 budget_assert |
| `V-02` ≤2Hz | GUT 常量断言 `EXPOSURE_PULSE_HZ <= 2.0` | `budget_assert._check_pulse_frequency` 已有桩位 ✅ |
| `V-03` 屏震默认关 | GUT `A11ySettings.screen_shake == false` | — |
| `C-07` 危险不单色 | GUT 断言图标/形状节点非空 + 边框色 == `HUD_COLOR_ALARM` | — |

> `tests/ci/budget_assert.gd` 现有 R-02/R-04/R-05/R-06/G-02/V-02 六桩位，**无 G-04/G-05/C-02**。Batch C **不新增桩位**，全部走 GUT。

---

## 9. 工程执行顺序拓扑（依赖排序 · 测试先行）

### 9.1 线性执行清单（照此顺序，每步「先写测试 → 再实现 → 跑绿 → 提交」）

| 步 | 内容 | 文件 | 钩子 | 前置 | 说明 |
| --- | --- | --- | --- | --- | --- |
| **0-a** | **契约前置 · D6 + D8 收口** | `event_bus.gd`（F1）· `test_event_bus.gd`（T4） | — | 无 | **必须最先**：所有后续 emit/connect 依赖新枚举与新签名。改动 = 2 枚举 + 2 签名 + 1 注释 + 1 测试桩 |
| **0-b** | **契约前置 · D7 色板** | `hud_colors.gd`（F2，新建） | — | 无 | 纯常量 + WCAG 纯函数，**零依赖**，与 0-a 可并行 |
| **1** | **E08-S1** 五态 FSM 骨架 | `patrol_ai.gd`（F3，新建） | **H1** | 0-a | 产出 `_set_fsm` + 转换表 + 抖动防护三纪律 |
| **2** | **E08-S2** 可疑度结算核 ★ | `patrol_ai.gd` | **H2 H3** | 1 | **批内最关键**：`tick_real`/`_decide` + D5 脉冲口径 + clamp + stimulus 判据 |
| **3** | **E08-S3** 10Hz 节流 | `patrol_ai.gd` | **H4** | 2 | 真实时间 `_process` 模式 + `MAX_CATCHUP_TICKS` |
| **4** | **E08-S4** 1.2s 软失败 + seam ① | `patrol_ai.gd` · `test_step_commit.gd`（T3） | **H5 H6** | 2 | `_checkpoint_sink`（D9）。**H5 是改写**，注意别新建同名 |
| **5** | **E08-S5** A* seam ② | `patrol_ai.gd` | **H7** | 1 | `_path_provider`（D9）；`_path_dirty` 只在 `_set_fsm` 置 |
| **6** | **E06-S5** 声脉冲消费侧 | `patrol_ai.gd` | **H18** | 2 | `_on_sound_emitted` + `last_known` 优先级。**不改 `sound_propagation.gd`** |
| **7** | **E08-S8** 姿态可读 | `patrol_ai.gd` | **H11** | 1 | 纯枚举。**零风险，可提前到步 1 之后任意点并行** |
| **8** | **E08-S6** 四信号 + tier + **★地雷 ②** | `patrol_ai.gd` | **H8 H9 H10** | 1,2,4 | **串行汇聚点**：tier 与 exposure 都要发信号；W1/W3/W2 三方接线在此 |
| **9** | **E09-S3** 世界要素编排 | `hud_slice.gd`（F4）· F5/F6/F7 各 +3 行 | **H15** | 0-b | ⚡**只依赖 Batch A/B，可与步 1 同时起步** |
| **10** | **E09-S4** 道具/charges | `hud_slice.gd` | **H16** | 0-a | ⚡**与 E08 零耦合，任意时刻可插入** |
| **11** | **E09-S2** 可疑度条 + **★地雷 ① + ③** | `hud_slice.gd` · `test_hud_slice.gd`（T2） | **H12 H13 H14** | 0-b, 8 | 双写修复 + H13 改写**必须同提交**，否则 CI 红 |
| **12** | **E09-S6** 暴露 UI + **★地雷 ③** | `hud_slice.gd` | **H17** | 0-b, 4, 8 | 暴露层：ALARM_FILL 仅 α≤0.35，边框 ALARM，文本 Carrier |

### 9.2 拓扑图

```
【前置 · Batch A/B 已落盘 ✅】
  E01-S9 事件词汇 · E05-S5/S6/S7 视野 · E06-S1/S2/S3 声音 · E04 光影 · E03 步进
  E06-S5(E06 侧) suspicion_from_distance() + 2 测试      ← 本批不重做
                              │
╔═════════════════════════════╪═══════════════════════════════════════════════╗
║ Batch C                     ▼                                               ║
║                                                                             ║
║ ── 步 0 · 契约前置（无依赖，两路并行，必须最先）──────────────────────       ║
║   0-a  event_bus.gd：GuardState + InteractableType 枚举，2 签名 [D6/D8]      ║
║   0-b  hud_colors.gd：HUD_COLOR_* + WCAG 纯函数        [D7 签字]            ║
║        │                              │                                     ║
║ ── 步 1–2 · 串行地基 ──────────────    │                                     ║
║   ① E08-S1 五态 FSM  [H1]             │                                     ║
║        ▼                              │                                     ║
║   ② E08-S2 可疑度结算核 ★ [H2 H3]     │   ⚡ ⑨ E09-S3 世界编排 [H15]        ║
║        │   （D5 脉冲口径）            │      （只依赖 A/B，最早可起）        ║
║        │                              │   ⚡ ⑩ E09-S4 道具/charges [H16]     ║
║ ── 步 3–7 · 五路并行（只依赖 ①②）──   │      （只依赖 0-a，全程独立）        ║
║        ├────┬────┬────┬────┐          │                                     ║
║        ▼    ▼    ▼    ▼    ▼          │                                     ║
║   ③S3  ④S4  ⑤S5  ⑥E06-S5  ⑦S8        │                                     ║
║   [H4] [H5H6][H7]  [H18]  [H11]       │                                     ║
║        └────┴────┴────┴────┘          │                                     ║
║                 ▼                     │                                     ║
║ ── 步 8 · 串行汇聚（依赖 ①②④）────    │                                     ║
║   ⑧ E08-S6 四信号 + tier  [H8 H9 H10] │                                     ║
║      ★★ 地雷 ② W1 位置回填在此闭合 ★★ │                                     ║
║                 │                     │                                     ║
║ ── 步 11–12 · HUD 消费（依赖 ⑧ + 0-b）┘                                     ║
║        ├──────────────┬───────────────┐                                     ║
║        ▼              ▼               ▼                                     ║
║   ⑪ E09-S2       ⑫ E09-S6       （⑨ 已完成）                               ║
║   [H12H13H14]     [H17]                                                     ║
║   ★★地雷①+③★★    ★★地雷③★★                                                 ║
╚═════════════════════════════════════════════════════════════════════════════╝
                              │
                              ▼
        批末冒烟：test_patrol_ai + test_hud_slice 全绿 + 既有 4 文件零回归
```

### 9.3 并行度与关键路径

| 阶段 | Story | 并行度 | 说明 |
| --- | --- | --- | --- |
| 步 0 | 0-a / 0-b | **2 路** | 契约与色板互不依赖 |
| 步 1–2 | E08-S1 → E08-S2 | **串行** | S2 的结算核写在 S1 的 FSM 骨架里，顺序颠倒必返工 |
| 步 3–7 | S3 / S4 / S5 / E06-S5 / S8 | **5 路并行** | 互不依赖 |
| 步 8 | E08-S6 | **串行汇聚** | 必须等 S1/S2/S4 定稿 |
| 步 11–12 | E09-S2 / E09-S6 | **2 路并行** | 互不依赖 |
| 全程 | E09-S3 / E09-S4 | **完全独立** | ⚡ 建议**与步 1 同时起步**，为关键路径腾并行带宽 |

**关键路径**：`0-a → E08-S1 → E08-S2 → E08-S6 → E09-S2/S6`（**5 跳**）。其余 7 条可挂旁路。

### 9.4 批内冒烟检查点

| CP | 时机 | 内容 |
| --- | --- | --- |
| **CP-0** | 步 0 完成 | `test_event_bus.gd` 全绿（D6/D8 签名改后**零回归**）；`hud_colors.gd` 可被 `preload` |
| **CP-1** | 步 2 完成 | `test_patrol_ai.gd` 的 FSM + 阈值用例全绿；**手工验证 S 在 25/60 附近不抖动**（C2 闭合的直接证据） |
| **CP-2** | 步 8 完成 | 四信号可 `emit`/`connect`；**H10 绿**（地雷 ② 已闭合）；`test_event_bus.gd` 不回归 |
| **CP-3** | 步 11–12 完成 | `test_hud_slice.gd` 全绿（**含被改写的 H13**，地雷 ① 已闭合） |
| **CP-4** | 批末 | `test_patrol_ai` + `test_hud_slice` 全绿 + 既有 4 个测试文件**零回归**（对齐 `sprint1-plan` 批间冒烟口径） |

---

## 10. Sprint 2 交接清单（D9 明确延期项）

| 项 | 本批状态 | Sprint 2 动作 | 返工量 |
| --- | --- | --- | --- |
| **E01-S5 SaveManager** | ❌ 未实现、未排期 → **D9 正式排入 Sprint 2** | 实现 `src/core/save_manager.gd`；把 `GuardBrain.set_checkpoint_sink(SaveManager.restore_checkpoint)` | **改 1 行注入代码**，`GuardBrain` 不动 |
| **E01-S8 NavServer** | ❌ 未实现、未排期 → **D9 正式排入 Sprint 2** | 实现 `src/core/nav_server.gd`；`GuardBrain.set_path_provider(NavServer.request_path)` | **改 1 行注入代码**，`GuardBrain` 不动 |
| **E09-S6 真实软重开** | 仅静态提示条 | 接 SaveManager + 重生 + 确认交互 | 中 |
| **E09-S5 a11y 完整包（C-06 开关）** | 仅预留读取点 | 接开关 + 着色器替换（`HUD_COLOR_ALARM → HUD_COLOR_ALARM_CB`） | 小（常量已备好） |
| **E07 实体** | 仅信号级 | 真实诱饵/互动物件发射 `interactable_triggered`（**签名已在本批收口，不再返工**） | **零**（D8 收益） |
| **E08-S7 守卫变体** | 不做 | 参数覆盖（KV/KS、L_DARK 阈值） | 小 |
| **W2 多守卫多锥** | GuardBrain 1:1 持有 `VisionCone` | 关卡侧批量实例化 | 小 |
| **多层关卡声音（E13）** | 3D 欧氏距离 | 改「分层判定 + 水平距离」 | 中 |
| **真实寻路移动** | 不做（仅时机 + 缓存纪律） | 导航网格烘焙 + 位移动画 | 大 |

> **须主理人确认**：是否需为 **E01-S5 / E01-S8** 在 Sprint 2 Story 表中正式建条目（D9 原文的开放问）。

---

## 11. 残留与未闭合项

| # | 项 | 性质 | 阻塞？ | 建议 |
| --- | --- | --- | --- | --- |
| **NEW-1** | **可疑度条 Carrier α 阶梯**（`SUS_FILL_ALPHA = 0.30/0.60/0.75/0.92`，§2.3.3） | **本文新增派生规格**。签字稿把 CAUTION/ALARM 定为「**边框**」用色，未定义条**填充**；而 D7 签字色板的相对亮度 `CALM 0.100 → CAUTION 0.295 → ALARM 0.190` **非单调**，直接拿语义色作填充会使 GDD 要求的「亮度递增」**倒挂**。本文改用 Carrier 白的 α 阶梯（严格单调、零新色相、相邻主档亮度比 ≥2.0×）。 | **否**（合规且可断言） | 建议林绘澄**回签确认**；若美术另有偏好填充方案，仅需改 4 个 α 数值，`hud_slice.gd` 结构不动 |
| **OPEN-1** | **枚举成员命名** `CALM/SUSPICIOUS` vs 主理人口述的 `PATROL/INVESTIGATE` | 本文按 GDD/art-bible 既有名 `CALM/SUSPICIOUS` 实现，**int 值域与主理人给定的 0/1/2 完全一致**（D6 的实质要求已满足）。若主理人要求连名一并改，需同步 `patrol-ai` §2/§3、`system-breakdown` §2.3、`art-bible` §4.1、`sprint1-stories` 四处。 | **否** | 请主理人一句话确认：**保持 `CALM/SUSPICIOUS`**（推荐，零文档漂移）还是**改名 `PATROL/INVESTIGATE`**（需 4 处文档同步） |
| **B-1** | DECOY 声圈单次脉冲 7.5 点 < `THR_SUSP(25)`，诱饵可能失效 | **平衡风险**，属 E06-S4（Batch D） | 否 | Batch D 复验；建议 `source==DECOY` 无条件写 `last_known`，仍不足再议 `KS_DECOY`（Tier2 参数，不在 Batch C 硬编码） |
| **E13** | 多层关卡下 3D 距离会因高差衰减 | **已知限制**，MVP 单层无影响 | 否 | Sprint 2 引入多层时改「分层判定 + 水平距离」 |
| **DOC-1** | `sprint1-stories.md` E03-S5 举例「SNEAK+MOSS 2.5」应为 **1.25** | 陈述性偏差，代码/GDD/测试均为 1.25 | 否 | Batch D 顺手 Edit，本批不动 |
| **DOC-2** | `control-manifest` / `art-bible` / `accessibility-matrix` 中的 `#7A2E2E` 表述 | 语义正确（讲品牌危险色通则），非「HUD 边框误用」 | 否 | 建议补注「HUD 落地色见 `hud-a11y-signature.md`」，见 §7.2 |

> **结论：无 FAIL、无硬阻塞、无未闭合的裁决项。** §7 六项裁决（D5–D10）全部 CLOSED；三处地雷全部有实现级落点 + 验证钩子；18 钩子全部映射到 Story 与断言要点。**NEW-1 与 OPEN-1 是两项「建议确认」，不阻塞开工。**

---

## 12. 设计红线复查（收口后终态）

| 红线 | 状态 | 说明 |
| --- | --- | --- |
| **主导策略** | ✅ **解除** | D5 脉冲口径锁定后：SNEAK 永不被听见（奖励）/ WALK 4.3s / RUN 0.94s（明确成本）。另查「快速闪烁露头」套利：露 0.1s 得 +3.5 点，躲 0.44s 归零，**净收益为零** ⇒ 无套利 |
| **经济失衡** | ✅ | 攻守比 `KV/DECAY = 4.4:1`（露 1s ↔ 躲 4.4s）；三步态声音轴梯度明确；`charges` 经济属 E07（Sprint 2） |
| **认知过载** | ✅ **解除** | 单条聚合（取最高）+ 全体沉寂时隐藏；HUD 屏幕面板 ≤3（`ux-spec` §3.3）；E09-S4 槽位克制（图标+文字，无冗余装饰） |
| **支柱漂移** | ✅ | E08 → 支柱一（1.2s 宽限 + 软失败 + 可读回落）+ 支柱四（渐升警戒 + 姿态庄重）；E09 → 支柱二（克制 juicy）+ 支柱三（a11y 基底）；E06-S5 → 支柱一 + 支柱三。**无「无主」Story** |
| **范围蔓延** | ✅ | 四处高风险点均显式锚定：❌ 完整 SaveManager（§3.4）· ❌ 真实寻路移动/导航烘焙（§3.5）· ❌ a11y 完整包与 C-06 开关（§3.11）· ❌ E07 实体（§3.10）。**任何越界须报主理人裁决** |
| **视觉漂移** | ✅ | 全部 HUD 取色引 `HudColors.HUD_COLOR_*`，源自 D7 美术签字稿；`hud_slice.gd` 内**禁一切硬编码色字面量**；下游 8 处 `#7A2E2E` 误用已同步校正（§7.1） |

---

*Batch C 实现规格 v1.0 完成。**12 条 Story 全部可动手**；建议 **0-a / 0-b / E09-S3 / E09-S4** 四条立即并行起步（不依赖关键路径），随后按 §9.1 线性清单测试先行推进。三处地雷（HUD 双写 / 守卫位置回填 / `#7A2E2E`）均已落到具体文件、函数与验证钩子。—— 文策渊*
