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
- **色盲模式（C-05/C-06/C-07）**：开启后暴露 `#7A2E2E`→`#C8862F` 高亮+图标；机制信息亮度+形状+图标三重编码；光池vs阴影靠亮度边界（C-04）。
- **时间缩放（T-01/T-02）**：用户 0.1–1.0 可调，默认 0.25；联动 ②。
- **眩晕/光敏（V-01~V-06）**：禁 >3Hz 频闪（V-01，由着色器约束）、暴露脉动 ≤2Hz（V-02）、屏震默认关（V-03）、雾选项（V-04）、动态模糊默认关（V-05）、转场 ease（V-06）。
- **文本/字幕（X-01/X-02）**：文本 100–150% 不破版（X-01）；关键音景字幕带说话者标识+图标（X-02）。
- **输入可达**：焦点环 `#C8862F` 细描边，键盘/手柄可达（美术 §9.4）。
- **对齐清单**：C-01~C-07、X-01/X-02、V-01~V-06、T-01/T-02；美术 §9 全节。

## 8. 范围分层归属
- **Tier1（必做）**：世界内锥/光池/声环/残影 + 屏幕四摘要（可疑度/道具/凝神/预演）+ 面板基调。
- **Tier2（期望）**：完整可访问性包——色盲模式、时间缩放、屏震关、雾选项、动态模糊关、文本缩放、字幕（概念 §5 Tier2）。
- **Tier3（拓展）**：照片模式取景 UI；「最干净通关」排行榜 UI；复用 HUD 框架，不新增系统。
- **范围纪律**：本系统即概念 §5「核心 HUD」；可访问性为 Tier2 显式要求，未新增平行机制族。
