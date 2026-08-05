# 系统 GDD · 核心 HUD 与可访问性（core-hud-a11y）
**Phase 2 · 八节 GDD · 优先级 P4（只读聚合全部系统）**

> 上游：`design/concept/game-concept.md` §5（核心 HUD）、§6；`docs/architecture/control-manifest.md` C-01~C-07、X-01/X-02、V-03/V-04/V-05、T-01/T-02；`design/art/art-bible.md` §8/§9。

---

## 1. 系统目标与支柱对齐
- **目标**：极简、克制、肃穆的 HUD——世界内（diegetic）呈现锥/光池/声环/残影，屏幕仅摘要状态；并落地全部可访问性开关。
- **支柱对齐**：
  - 支柱二 **感官愉悦**：juicy 但克制的反馈，UI 是「世界的低声注解」（美术 §8）。
  - 支柱三 **自主掌控**：可访问性=让更多玩家 Own 自己的体验。
  - 全部四支柱：HUD 不破坏肃穆压迫（美术 §1 红线）。
- **为何存在**：把 ①–⑦ 的状态收敛为可读界面，且不喧宾夺主；可访问性是 Tier2 硬基线（概念 §5）。

## 2. 核心机制与规则
- **世界内（near-diegetic）要素**（由对应系统绘制，本系统只编排/不重绘）：视野锥（③）、光池/阴影（⑤）、声波环（④）、足迹残影/下一步预演（①）。均在世界平面，俯视可读（概念 §2）。
- **屏幕 HUD 摘要**（极简，美术 §8.1）：① 可疑度（贴近相关守卫或 HUD 一角细条）② 当前道具/charges（⑦）③ 凝神状态（②）④ 下一步落点预演（①，世界内但本系统管辖其可见性开关）。
- **面板基调**：半透明暗面板 `#1B1B1F`@70–85% + `#3E5C76` 细描边；无外发光/霓虹/圆角糖果（美术 §8.1）。
- **可访问性设置分区**（设置菜单）：色盲模式、时间缩放滑杆、屏震开关、雾选项、动态模糊、文本缩放、字幕（见 §7）。

## 3. 数据模型与状态
```gdscript
class HUDModel:                    # L5，只读聚合
    var suspicion: Dictionary[int, float]      # guard_id -> S（来自 ⑥）
    var guard_states: Dictionary[int, GuardState]
    var current_item: InteractableType
    var item_charges: int
    var focus_mode: TimeMode                    # 来自 ②
    var next_step_preview: Vector3              # 来自 ①

class A11ySettings:                # L2，持久化
    var colorblind_mode: bool
    var time_scale_user: float              # [0.1, 1.0]（T-01），默认 0.25
    var screen_shake: bool = false          # V-03 默认关
    var fog_option: FogOpt { FULL, REDUCED, OFF }   # V-04
    var motion_blur: bool = false           # V-05 默认关
    var text_scale: float = 1.0             # [1.0, 1.5]（X-01）
    var subtitles: bool = true              # X-02
```

## 4. 与其他系统的接口
- **依赖（只读）**：① `aim_point`/ghost_trail、② `time_scale_changed`/focus、③ 锥+`vision_looming`、④ 声环、⑤ 光池/阴影、⑥ `suspicion_changed`/`guard_fsm_changed`/`exposure_detected`、⑦ 道具/charges。
- **发出**：仅 UI 交互事件（设置变更）→ L2 A11ySettings 持久化；不直接驱动玩法（玩法读 `Engine.time_scale`/A11ySettings）。
- **被依赖**：无（终端呈现层）。失败流消费 ⑥ `exposure_detected` → 触发软重开 UI。
- **联动词汇表**：所有事件名见 `system-breakdown.md` §2。

## 5. 玩家交互与反馈
- **输入**：设置菜单键（暂停态）；HUD 本身不抢操作焦点（美术 §8.4：凝神时 UI 退后、世界上前）。
- **反馈**：可疑度条亮度递增+图标（眼/?/!）+数字（C-02）；暴露 `#D64545`（D7 签字；`#7A2E2E` 仅作低不透明填充 α≤0.35）+脉动+图标+（可关）屏震（C-07/V-03）；世界要素在凝神压暗中反而提亮（美术 §8.4）。

## 6. 边界与性能约束
- **C-01** UI 正文/数值对比度 ≥4.5:1（WCAG AA）。
- **C-02** 关键指示（可疑度/暴露）≥7:1。
- **C-03** 世界可读要素（锥缘/落点预演）亮度差 ≥3:1。
- **V-03** 屏震默认关、可开、幅度可调；**V-04** 雾选项；**V-05** 动态模糊默认关。
- **T-01/T-02** 时间缩放滑杆写入 `A11ySettings.time_scale_user`（钳 [0.1,1.0]，默认 0.25）。
- **性能**：HUD 为 2D 叠加，成本可忽略；世界内要素成本归各自系统预算（③锥/④环/⑤光池）。
- **架构联动**：`architecture.md` §3（L5 表现层）、§2（L5 经 L2/事件，不直触引擎底层）。

## 7. 可访问性考量（本系统核心职责）
- **色盲模式（C-05/C-06/C-07）**：开启后警报语义色 **`#D64545` → `#F0C070`** 高亮 + **实心三角 `!`** 图标（`#7A2E2E` 仅作 α≤0.35 底纹，非语义载体）；机制信息亮度+形状+图标三重编码；光池vs阴影靠亮度边界（C-04）。
  > **更正说明（Sprint 3，同步 art-bible v0.3 §9.1 / control-manifest v0.2 C-06）**：原文「暴露 `#7A2E2E`→`#C8862F`」两处均已作废——① 语义载体由不达标的 `#7A2E2E`（1.91:1）改为 `#D64545`；② 色盲映射目标由 `#C8862F` 改为 `#F0C070`，因警戒 CAUTION 本就是 `#C8862F`，旧映射会令警戒与警报亮度比塌缩至 1.00:1。
- **时间缩放（T-01/T-02）**：用户 0.1–1.0 可调，默认 0.25；联动 ②。
- **眩晕/光敏（V-01~V-06）**：禁 >3Hz 频闪（V-01，由着色器约束）、暴露脉动 ≤2Hz（V-02）、屏震默认关（V-03）、雾选项（V-04）、动态模糊默认关（V-05）、转场 ease（V-06）。
- **文本/字幕（X-01/X-02）**：文本 100–150% 不破版（X-01）；关键音景字幕带说话者标识+图标（X-02）。
- **输入可达**：焦点环 **`#F0C070`** 2px 实线描边 + **恒 0Hz 不脉冲**（对 `#1B1B1F` = 10.20:1，过 **C-02**），键盘/手柄可达（美术 **§9.4.1**，**独立语义槽，非 C-06**）。
- **对齐清单**：C-01~C-07、X-01/X-02、V-01~V-06、T-01/T-02；美术 §9 全节。

## 8. 范围分层归属
- **Tier1（必做）**：世界内锥/光池/声环/残影 + 屏幕四摘要（可疑度/道具/凝神/预演）+ 面板基调。
- **Tier2（期望）**：完整可访问性包——色盲模式、时间缩放、屏震关、雾选项、动态模糊关、文本缩放、字幕（概念 §5 Tier2）。
- **Tier3（拓展）**：照片模式取景 UI；「最干净通关」排行榜 UI；复用 HUD 框架，不新增系统。
- **范围纪律**：本系统即概念 §5「核心 HUD」；可访问性为 Tier2 显式要求，未新增平行机制族。

---

## 9. Sprint 2 Tier2 完整 a11y 包（E09）
> 本 § 将 ⑧ 的设置/表现层从「骨架（E01-S6 接口+默认值）」升级为**完整可访问性包**：补全 `A11ySettings` 数据、落地设置菜单 UI 规格、接线全部表现效果、并接入 `save-system.md` 偏好持久化。所有开关对齐 `control-manifest` C-01~C-07 / X-01/X-02 / V-01~V-06 / T-01/T-02。

### 9.1 A11ySettings 数据补全（L2）
```gdscript
enum ColorBlindMode { OFF, PROTAN, DEUTAN, TRITAN }   # 完整枚举（原仅 bool）
enum FogOpt { FULL, REDUCED, OFF }

class A11ySettings:                # L2，持久化经 SaveManager
    var color_blind_mode: ColorBlindMode = OFF        # C-05/C-06
    var time_scale_user: float = 0.25                 # [0.1, 1.0]（T-01），默认 0.25
    var screen_shake: bool = false                    # V-03 默认关
    var fog_option: FogOpt = FULL                     # V-04
    var motion_blur: bool = false                     # V-05 默认关
    var text_scale: float = 1.0                       # [1.0, 1.5]（X-01）
    var subtitles: bool = true                        # X-02（原缺失字段，新增）
    # 持久化：save()/load() 改调 SaveManager.save_prefs("a11y", dict)/load_prefs("a11y")
```
- `subtitles` 字段原缺失（a11y_settings.gd 仅接口骨架），本 Sprint 补全并接入。
- `color_blind_mode` 从 `bool` 升级为四态枚举（PROTAN/DEUTAN/TRITAN 对应三色盲类型，§9.3 配色）。

### 9.2 设置菜单 UI 规格（暂停态，⑧ 管辖）
| 分组 | 控件 | 范围/默认 | 对齐 |
| --- | --- | --- | --- |
| 视觉·色觉 | 色盲模式下拉 | OFF/PROTAN/DEUTAN/TRITAN | C-05/C-06 |
| 节奏·时间 | 凝神时间滑杆 | 0.1–1.0，默认 0.25 | T-01/T-02 |
| 舒适·眩晕 | 屏震开关 | 默认关 | V-03 |
| 舒适·雾 | 雾选项 | FULL/REDUCED/OFF | V-04 |
| 舒适·动态模糊 | 动态模糊开关 | 默认关 | V-05 |
| 文本 | 文本缩放滑杆 | 100–150%，默认 100% | X-01 |
| 字幕 | 字幕开关 | 默认开 | X-02 |
- 控件不抢操作焦点（§5）；键盘/手柄可达，焦点环 **`#F0C070`** 2px 实线 · 恒 0Hz 不脉冲（美术 **§9.4.1**）。
  > **更正说明（Sprint 3 · O-1 Option A）**：原文「焦点环 `#C8862F`（C-06）」**两处均误**——① **取值**：`#C8862F` 对 `#1B1B1F` 仅 **5.65:1**，过 C-01 但**不过 C-02**；焦点环是「关键操作指示」，须按 C-02（≥7:1）要求，故改 `#F0C070`（**10.20:1**）。② **约束归属**：焦点环归 **美术 §9.4.1「输入可访问性」独立语义槽**，**不归 C-06**——C-06 管的是色盲模式下警报语义色的替换。二者只是恰好共用同一 HEX，「(C-06)」这个括注本身就是标注错误。

### 9.3 HUD 表现接线
- **色盲模式（C-05/C-06/C-07）**：开启后警报语义色 **`#D64545` → `#F0C070`** 高亮 + **实心三角 `!`** 图标（`#7A2E2E` 仅作 α≤0.35 底纹，非语义载体）；机制信息亮度+形状+图标三重编码；按类型映射（PROTAN/DEUTAN/TRITAN 各有安全区分配色，不依赖色相 alone）。光池 vs 阴影靠亮度边界（C-04）。**脉冲频率（0.5Hz / 2.0Hz）与图标面积编码（空心圆环 / 实心三角）常驻生效，不随本开关切换**（art-bible v0.3 §9.1）。
  > **更正说明（Sprint 3）**：同 §7，原文「暴露 `#7A2E2E`→`#C8862F`」的语义载体与色盲映射目标均已作废，理由见 §7 注。
- **时间缩放（T-01/T-02）**：滑杆写入 `A11ySettings.time_scale_user`，钳 [0.1,1.0]，联动 ②（默认 0.25）。
- **眩晕/光敏（V-01~V-06）**：禁 >3Hz 频闪（V-01，着色器约束）；暴露脉动 ≤2Hz（V-02）；屏震默认关、可开、幅度可调（V-03）；雾选项（V-04）；动态模糊默认关（V-05）；转场 ease（V-06）。
- **文本/字幕（X-01/X-02）**：文本 100–150% 不破版（hud_slice 第 322 行注释「Sprint 2 100-150% text scale drops in without relayout」）；关键音景字幕带说话者标识 + 图标（X-02）。`subtitles` 关则抑制环境音景字幕。
- **对比度（C-01/C-02/C-03）**：正文 ≥4.5:1、关键指示 ≥7:1、世界可读要素 ≥3:1，沿用 §6 硬约束。

### 9.4 存档 UI（调用 SaveManager）
- 设置菜单「存档/读档」入口 → `SaveManager.write_slot` / `read_slot`（见 `save-system.md` §4/§5）。偏好变更即时 `save_prefs("a11y", ...)` 落盘，跨会话保留。
- 读档完成：`load_completed` → ⑧ 淡入 + 应用 `A11ySettings` 全部开关到运行时（着色器/时间/雾/模糊/缩放）。

### 9.5 边界（Tier2 包）
- 全部对齐 C-01~C-07、X-01/X-02、V-01~V-06、T-01/T-02；美术 §9 全节。
- 不新增事件词汇：a11y 开关变更经 L2 `A11ySettings` 直接被玩法/着色器读取，无需事件总线广播（与 §4「仅 UI 交互→L2 持久化」一致）。
- 表现成本归各自系统预算（③锥/④环/⑤光池/着色器），HUD 2D 叠加成本可忽略。
