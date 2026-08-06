# 损坏徽标矢量规格 · `ui_badge_corrupt`（S3-B · ART-OOS-2 交付 D）

| 字段 | 值 |
| --- | --- |
| **项目** | ASHEN STEP《灰烬之步》 |
| **文档版本** | v1.0（S3-B 残留收口 · ART-OOS-2 交付 D） |
| **作者** | 林绘澄（Art Director / 美术与视觉表现指导） |
| **引擎 / 平台** | Godot 4.4 · PC·Steam（键鼠 + 手柄） |
| **上游依据** | `design/assets/sprint3-b-asset-spec.md` §3.5（L130–147）/ §4.1 EC-11（L173–186）；`docs/architecture/control-manifest.md` C-05 / C-07 / V-01 / V-02；`design/art/accessibility-matrix.md` 行 3 / 行 4 / 行 13；`design/art/art-bible.md` v0.4 §9.1 / §9.4.1 |
| **下游衔接** | `src/ui/save_ui_model.gd`（L108 `BADGE_CORRUPT` 常量 · L72 `CORRUPT_PULSE_HZ`） · `src/ui/save_slots_screen.gd`（L522 徽标 Label · L650 赋值 · L675–679 着色 · L795–811 脉动）；**落地由程基岩执行（见 §5）** |
| **性质** | **矢量资产规格 + 源文件**。`res://arts/` 根当前不存在（E-1 由程基岩创建）；本矢量先落 `design/art/staging/`，由程基岩移入 `res://arts/ui/`。 |

---

## 1. 用途与语义

存档槽列表里，**损坏（CORRUPT）** 状态的行徽标。现行实现把 ⚠ emoji 直接塞进字符串常量：

```gdscript
# src/ui/save_ui_model.gd · L108
const BADGE_CORRUPT := "〔⚠ 损坏〕"
```

⚠ emoji 是 **EC-11 的隐患**：它依赖 emoji 字体与平台渲染，既不是一个**可靠的实心三角形状通道**，也无法保证在色盲模式下与焦点环（`#F0C070`）的视觉区分。本规格用一个**矢量实心三角图标**替换它，使「形状 + 图标 + 亮度」三重编码（C-05 / C-07）在损坏徽标上真正成立，并把与焦点环的撞色缓解落在**形状维 + 频率维**两个正交维度上（见 §3）。

> **语义不变量**：本资产只替换「⚠ 形状/图标」这一承载，不改动徽标的文字（"损坏"由 `save_slots_screen.gd` 的 `badge` Label 继续渲染）、不动 `CORRUPT_PULSE_HZ := 2.0`（L72）、不动 `animation_channels()` 里 `corrupt_badge` @2.0Hz 的 V-01 审计登记（L858–862）。

---

## 2. 视觉规格

### 2.1 形状与尺寸

| 项 | 取值 | 说明 |
| --- | --- | --- |
| 形状 | **实心（填充）向上三角** + 内部「!」镂空 | 形状通道 = 实心三角；图标通道 = 「!」。**C-05/C-07 要求三维全部为视觉**，本资产同时承担形状与图标两维 |
| 视口 | `viewBox="0 0 24 24"` | 矢量，可无损缩放；UI 实际渲染约 **18–20 px**（与 `ROW_SUB_FONT_SIZE` 行副文字高对齐） |
| 填充 | `#FFFFFF`（白） | **白色填充**是为运行时 `TextureRect.modulate`  tint 服务：白 × modulate = modulate 本色，单一资产即服务两种色态（§2.2） |
| 镂空「!」 | `#1B1B1F`（近黑） | 经 modulate tint 后仍为近黑，在红/琥珀三角上均清晰可读 |
| 描边 | 无 | 实心填充三角，不靠描边；与焦点环「空心矩形描边」形成形状维反差（§3） |

> 源文件：`design/art/staging/ui_badge_corrupt.svg`（三角形顶点 `12,3 / 21,21 / 3,21`，「!」竖条 `x=11 y=8.5 w=2 h=6.5 rx=1`、圆点 `cx=12 cy=18 r=1.3`）。

### 2.2 颜色态（双模，经 C-06 解析器）

| 模式 | 三角 tint（modulate） | 对面板 `#1B1B1F` 对比 | 约束 |
| --- | --- | --- | --- |
| **默认（ALARM）** | **`#D64545`** | **3.92:1** | 过 **C-03**（≥3:1，世界/要素级）——与 `sprint3-b-asset-spec.md` §3.5 一致 |
| **色盲（C-06 替换）** | **`#F0C070`** | **10.20:1** | 过 **C-02**（≥7:1，关键指示级）——与 `accessibility-matrix` 行 4 现行口径一致 |

> **现行口径锁定**：C-06 危险色映射 = `#D64545 → #F0C070`（**非**已作废的 `#7A2E2E→#C8862F`）。常量 `HUD_COLOR_ALARM_CB` 已退休，由 `HUD_COLOR_DANGER_CB` 取代（见 §5 与 `accessibility-matrix` 行 19–22 编号治理注）。

### 2.3 脉动（频率维，已存在于代码）

- **2.0Hz 双拍**，alpha 0.55 → 1.0（由 `save_slots_screen.gd` L795–811 `_apply_corrupt_pulse()` 驱动，仅作用于损坏行徽标）。
- 受 **V-01**（禁 >3Hz）/ **V-02**（≤2Hz 温和）约束，2.0Hz 在限内。
- 与焦点环 **0Hz 不脉冲** 形成频率维正交（§3）。

---

## 3. EC-11 撞色硬约束 —— 与焦点环的正交分离

色盲模式下，损坏徽标与焦点环**同为 `#F0C070`**。缓解**只能靠形状维 + 频率维**（颜色维已塌缩），二者必须同时成立：

| 维度 | 焦点环（§9.4.1） | 损坏徽标（本资产） | 是否正交 |
| --- | --- | --- | --- |
| **色值** | `#F0C070` | `#F0C070` | ❌ 同值（塌缩，不靠它区分） |
| **形状** | 空心矩形描边（2px 实线） | **实心三角（填充）** | ✅ 正交 |
| **频率** | **0Hz 不脉冲**（恒亮） | **2.0Hz 双拍** | ✅ 正交 |
| **锚定** | 面板 chrome（行边框） | 世界锚 / 行内徽标 | ✅ 位置分离 |
| **触发** | 仅聚焦行 | 仅 CORRUPT 状态行 | ✅ 状态分离 |

> **硬禁令（规范级）**：焦点环一旦脉冲，频率维即失效，C-05 三重编码随之塌缩（见 `save_ui_model.gd` L63–69 / L70 `FOCUS_RING_HZ := 0.0` 的注释）。本资产**必须保持实心三角形状 + 2.0Hz 脉动**，不得改为空心或停脉冲——否则与焦点环的区分只剩锚定维，撞色风险复现。

---

## 4. 交付物与路径

| 交付物 | 路径 | 状态 |
| --- | --- | --- |
| **矢量源** | `design/art/staging/ui_badge_corrupt.svg` | ✅ 本次产出 |
| **规格文档** | `design/art/ui-badge-corrupt-spec.md` | ✅ 本次产出 |
| **运行时位置** | `res://arts/ui/ui_badge_corrupt.svg`（或 `.png` 由 SVG 栅格化） | ⏳ 待程基岩：E-1 建 `res://arts/` 后移入 `res://arts/ui/` |

> **F-2（已确认）**：`res://arts/` 仍是既定资产根（当前不存在，由程基岩 E-1 创建）。本矢量先落 staging，不移交前的路径不参与构建。

---

## 5. Handoff —— 给程基岩（程基岩落地，`art-director` 不碰 `.gd`）

> 以下为**建议改法**。本人**未修改任何 `.gd`、未执行 git**。所有行号基于 main `89dbffd`。

### 5.1 `src/ui/save_ui_model.gd`

- **L108**：把 emoji 移出字符串常量，文字与图标分离——
  ```gdscript
  # 旧：const BADGE_CORRUPT := "〔⚠ 损坏〕"
  const BADGE_CORRUPT := "损坏"                       # 文字部分交 Label 渲染
  const BADGE_CORRUPT_ICON := "res://arts/ui/ui_badge_corrupt.svg"  # 三角图标（E-1 后可用）
  ```
  （括号「〔〕」可保留或去掉，纯排版选择；关键是**去掉 ⚠ emoji**。）
- **L72** `CORRUPT_PULSE_HZ := 2.0`：**保持不变**（频率维硬约束，见 §3）。
- **L858–862** `animation_channels()`：已登记 `corrupt_badge @ 2.0Hz` 与 `focus_ring @ 0.0Hz`，**保持不变**（V-01 审计依赖此表）。

### 5.2 `src/ui/save_slots_screen.gd`

- **L522–523**（徽标创建）：在 `badge` Label 旁增一个 `TextureRect`（`badge_icon`），承载三角图标；保留 `badge` Label 渲染 "损坏" 文字。
- **L650**（赋值）：`w["badge"].text = SaveUiModelScript.row_badge(row)`（现无 emoji）；CORRUPT 行额外 `w["badge_icon"].texture = load(SaveUiModelScript.BADGE_CORRUPT_ICON)`。
- **L675–679**（着色，**当前为占位 bug**）：两分支都写 `HUD_COLOR_CARRIER`，注释自称「走 C-06 解析器」但实未接。请改为经 **C-06 危险色解析器** 取色——
  - 默认：`#D64545`；色盲（`HUD_COLOR_DANGER_CB`，**非已退休的 `HUD_COLOR_ALARM_CB`**）：`#F0C070`。
  - 该色应用于 `badge_icon.modulate`（三角 tint），"损坏" 文字可同色或保持 `HUD_COLOR_CARRIER` 中性，由你定。
- **L795–811**（脉动）：`_apply_corrupt_pulse()` 现只对 `w["badge"]` Label 做 2.0Hz 双拍 alpha。请把同一 `wave` 也作用于 `w["badge_icon"]`（或把 icon+text 包进一个容器统一脉冲），**保持 2.0Hz、0.55→1.0**，且**绝不触碰焦点环**。

### 5.3 验收要点（落地后自检）

1. 色盲模式下，聚焦一个 CORRUPT 行：焦点环（空心矩形、`#F0C070`、0Hz）与损坏徽标（实心三角、`#F0C070`、2.0Hz）**必须可分辨**——靠形状 + 频率。
2. 默认模式损坏徽标对比度 ≥3.92:1（C-03）；色盲模式 ≥10.20:1（C-02）。
3. `animation_channels()` 两通道 hz 不变（2.0 / 0.0），V-01 断言仍过。
4. 全程无 `HUD_COLOR_ALARM_CB` 引用（已退休）→ 用 `HUD_COLOR_DANGER_CB`。

---

## 6. 与既有规格的关系

- **权威上游**：`design/assets/sprint3-b-asset-spec.md` §3.5（L130–147）定义 `ui_badge_corrupt` 的语义/色态/脉动，§4.1 EC-11（L173–186）定义与焦点环的正交表。本规格是其**矢量落地**，数值（2.0Hz、`#D64545`/`#F0C070`、对比度）与之逐字一致。
- **PNG → 矢量**：§3.5 原写 `ui_badge_corrupt.png` 96×24px（栅格 mock）。本交付为**矢量 SVG**（派工 F-2 明示「矢量先落 staging」）。SVG 为权威源；若某管线需栅格，由 SVG 导出 `.png`，**不要反向**以旧 PNG 覆盖本矢量。
- **不重编号 / 不新增约束**：本资产复用既有 C-05 / C-07 / V-01 / V-02 与 EC-11，不引入新编号。

---

*损坏徽标矢量规格 v1.0 完成。交付 `staging/ui_badge_corrupt.svg` + 本规格；`.gd` 落地交程基岩（§5）。未修改任何源码、未执行 git。*
