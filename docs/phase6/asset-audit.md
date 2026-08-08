# ASHEN STEP《灰烬之步》· Phase 6 美术资产审计报告

**审计人：** 林绘澄（art-director / 美术与视觉指导）
**审计对象：** `Game-RPG` 工作副本（main = `24fc2ef`，working tree clean）
**引擎：** Godot 4.4.1 / GDScript 2.0 / GUT v9.3.0
**审计性质：** 只读（read-only）—— 所有问题仅登记于本报告，**未修改任何项目文件**（arts/、src/、addons/ 均未被改动）
**审计日期：** 2026-08-08

---

## 1. 审计范围与方法

### 1.1 范围
- `arts/` 目录全部资产（视觉 + 音频），含 `.svg` / `.tres` / `.wav` 及各自的 `.import` 元数据、`.uid` 跟踪、`.godot/imported` 生成缓存。
- `src/` 与 `addons/` 下所有 `.tscn` 场景及其引用的纹理 / 材质 / 字体 / 着色器；`.gd` 中的资产路径引用（`res://...`）与颜色字面量。
- 美术圣经合规：`design/art/art-bible.md`（v0.4）九节视觉身份。
- 颜色铁律 C-06 现行口径逐处核对（见 §4）。
- 可访问性矩阵 `design/art/accessibility-matrix.md`（v0.5）视觉侧落地 + A-0N 说明（见 §5）。
- 命名 / 目录 / `.import` / `.uid` 规范（见 §6）。

### 1.2 方法
1. **资产清单**：`find arts/` 枚举全部资产文件；`grep "res://arts/"` 在 `.gd`/`.tscn`/`.import` 中收集所有资产引用路径，逐一核对存在性。
2. **孤立 / 缺失引用**：遍历全部 `.import`（排除 `addons/gut` 与 `.godot`），校验 `source_file` 指向的源文件存在；校验 `.godot/imported/*.ctex|*.sample` 生成缓存存在。
3. **C-06 逐处核对**：`grep` 全仓 `#D64545` / `#F0C070` / `#C8862F` / `#7A2E2E` 与 `HUD_COLOR_DANGER_CB` / `HUD_COLOR_ALARM_CB`，逐条判定是否守住现行口径。
4. **硬编码色字面量**：`grep "Color("` 全仓，区分「签名色板权威 `hud_colors.gd`」与「散落字面量」。
5. **美术圣经 / 矩阵对齐**：对照 `art-bible.md` v0.4 §2/§3/§8/§9、`accessibility-matrix.md` v0.5 行 3/4/13/16，核对实装代码（`hud_colors.gd` / `save_ui_model.gd` / `save_slots_screen.gd` / `src/game/*`）。

---

## 2. 资产清单与完整性

### 2.1 `arts/` 实际资产清单（共 7 个资产文件）

| # | 资产文件 | 类型 | 引用方（代码） | 导入缓存 | 状态 |
|---|----------|------|----------------|----------|------|
| 1 | `arts/ui/ui_badge_corrupt.svg` (+`.import`) | 矢量图标（实心三角 !） | `src/ui/save_ui_model.gd:121` → `save_slots_screen.gd:864` `load()` | `.godot/imported/...ctex` 存在（212B）+ `.md5` | ✅ 已消费、已正确导入 |
| 2 | `arts/audio/audio_bus_layout.tres` | 音频总线布局 | `project.godot` autoload `AudioDirector`；测试 `test_audio_bus_layout.gd:52` | 内联资源 | ✅（音频域，阮和鸣） |
| 3 | `arts/audio/ui/sfx_ui_save_success.wav` (+`.import`) | 音效 | `src/core/audio_director.gd:78` | `.godot/imported/...sample` | ✅（音频域） |
| 4 | `arts/audio/ui/sfx_ui_save_failure.wav` (+`.import`) | 音效 | `src/core/audio_director.gd:83/88` | `.godot/imported/...sample` | ✅（音频域） |
| 5 | `arts/ui/ui_badge_corrupt.svg.import` | 导入元数据 | — | — | ✅ uid=`uid://dc7s6soaxp287`，source/dest 一致 |
| 6 | `arts/audio/ui/sfx_ui_save_success.wav.import` | 导入元数据 | — | — | ✅ uid=`uid://4ru5jwwvw8h2` |
| 7 | `arts/audio/ui/sfx_ui_save_failure.wav.import` | 导入元数据 | — | — | ✅ uid 内嵌 |

> 注：主线索场景 `src/main/sprint0.tscn` 与 `src/ui/audio_settings_panel.tscn` 仅 `preload` 脚本，无任何内嵌纹理 / 材质 / 字体 / 着色器引用 → 无场景内缺失引用。

### 2.2 完整性结论
- **孤立 / 缺失引用：0 条。** 全部 `.import` 的 `source_file` 均指向存在的源文件；全部 `.godot/imported` 生成缓存均存在。
- **占位 / 退化资产：0 个。** 唯一项目视觉资产 `ui_badge_corrupt.svg` 为合规成品（白底 + 深色 ! 镂空，运行时经 `TextureRect.modulate` 染 `#D64545`/`#F0C070`，单一资产双模通用，符合 `ui-badge-corrupt-spec.md` §5）。
- **第三方资产（排除出合规范围）**：`addons/gut/*`（GUT 测试框架的 `arrow.png`/`play.png`/`red.png`/`green.png`/`yellow.png`/`Folder.svg`/`Script.svg`/字体/`GutSceneTheme.tres`）为测试框架自带，非项目视觉资产，不计入合规。
- **注册表 vs 实装漂移**：见发现 **M1 / M2**（主要问题，均为文档/清单漂移，无运行时断链）。

---

## 3. 美术圣经合规（art-bible.md v0.4 九节）

| 圣经条目 | 实装核对 | 结论 |
|----------|----------|------|
| §2 调性 / 冷暖纪律（90/10、暖 `#C8862F`≤6% / 血锈 `#7A2E2E`≤4%） | 代码侧 `HUD_COLOR_CAUTION=#C8862F`、`HUD_COLOR_ALARM_FILL=#7A2E2E` 仅填充；`footfall_vfx.gd:16` 落足微光用 `#C8862F`（暖，非危险） | ✅ |
| §2.2 规则4 封顶琥珀族（`#C8862F`/`#F0C070` 两槽，禁止第三语义） | `HUD_COLOR_DANGER_CB` 与 `HUD_COLOR_FOCUS` 共用 `#F0C070` 但为两个独立常量（FLAG-L，见 I2） | ✅ |
| §3.4 视野锥冷白 `#9FB8C9` | `vision_cone.gd:35` / `sound_propagation.gd:50` 用 `#9FB8C9`（冷，非危险色） | ✅（圣经 §2/§3.4 授权） |
| §8.2 落足微光 / 下一步预演 | `footfall_vfx.gd` `#C8862F` emissive quad（非实时光） | ✅ |
| §9.1 损坏徽标（实心三角 + 2.0Hz 双拍 + C-06 色盲 `#F0C070`） | `ui_badge_corrupt.svg` + `save_slots_screen.gd` modulate + `CORRUPT_PULSE_HZ=2.0` | ✅ |
| §9.4.1 焦点环独立槽（`#F0C070` 2px、恒 0Hz、非 C-06） | `HUD_COLOR_FOCUS=#F0C070`、`FOCUS_RING_HZ=0.0`、`FOCUS_RING_WIDTH_PX=2` | ✅ |

**结论**：唯一已产出的视觉资产与全部世界 VFX 颜色均对齐美术圣经；暗黑奇幻 / 灰烬 / 潜行基调由签名色板常量（`hud_colors.gd`）+ 着色器承载，无偏离。

---

## 4. 颜色规范 C-06 现行口径核对（铁律）

**现行口径**：危险/报警默认 `#D64545` → 色盲 `#F0C070` 过渡 + **实心三角图标**；`HUD_COLOR_DANGER_CB` 已取代旧 `HUD_COLOR_ALARM_CB`；旧 `#C8862F` 仅用于合法 CAUTION / 暖光 / 光池 / 落足，不得作危险色。

| 核对项 | 全仓证据 | 结论 |
|--------|----------|------|
| 默认报警色 = `#D64545` | `hud_colors.gd:40` `HUD_COLOR_ALARM := Color("#D64545")` | ✅ |
| 色盲替代 = `#F0C070` | `hud_colors.gd:93` `HUD_COLOR_DANGER_CB := Color("#F0C070")`；`danger_color()` L172-175 返回 `#F0C070`（色盲）/ `#D64545`（默认） | ✅ |
| 旧常量名 `HUD_COLOR_ALARM_CB` | 仅出现在 `hud_colors.gd` L42/51/54/66/80 **墓碑注释** + 文档旧引用；**无任何 `.gd` 生产调用**（测试亦只引 `HUD_COLOR_DANGER_CB`，见 `test_a11y_settings.gd:105`、`test_hud_slice.gd:439`） | ✅ 已退役 |
| 残留旧映射 `#7A2E2E`→`#C8862F` | 代码侧无此映射；唯一 `#7A2E2E` 为 `HUD_COLOR_ALARM_FILL`（L41），仅填充 `a<=0.35` | ✅ |
| `#C8862F` 误用为危险色 | 无。`footfall_vfx.gd:16` 将其用于落足微光（暖光/CAUTION，合法）；`HUD_COLOR_CAUTION`（L39）为警戒合法语义 | ✅ |
| 实心三角图标常驻 | `ui_badge_corrupt.svg` 矢量实心三角；`DANGER_ICON="!"`（L143）所有模式返回，非色盲回退 | ✅ |
| 频率/面积编码不随开关切换 | `CORRUPT_PULSE_HZ=2.0` 常驻；默认档 `#C8862F` vs `#D64545` 仅 1.44:1，靠常驻编码兜底 | ✅ |

**结论**：C-06 现行口径在代码侧**完全守住**，无残留旧色、无旧常量名生产调用、无 `#C8862F` 危险误用。

---

## 5. 可访问性矩阵落地（视觉侧）+ A-0N

### 5.1 视觉侧 a11y 实装核对（accessibility-matrix.md v0.5 行 3/4/13/16）
- **C-06 色盲替代**：`danger_color()` 实装，`HUD_COLOR_DANGER_CB=#F0C070`；`a11y_settings.gd` `ColorBlindMode.OFF` 枚举驱动。✅
- **C-02 焦点环**：`HUD_COLOR_FOCUS=#F0C070` / 10.20:1 / 恒 0Hz / 2px（`save_ui_model.gd`）。✅
- **C-03/C-05/C-07 三重编码**：形状（实心三角/空心矩形）+ 图标（`!`/`?`）+ 亮度；`danger_read_is_multi_channel()`（L189）运行时自检。✅
- **对比度门断言**：`focus_ring_contrast()` / `carrier_contrast()` / `disabled_carrier_contrast()` / `boundary_contrast()` 被 `tests/unit/test_save_ui.gd` 头无显示断言。✅
- **V-01 动画上限**：`animation_channels()` 注册焦点环(0Hz)+损坏徽标(2.0Hz)，`max_animation_hz()` 受测。✅

**结论**：视觉侧可访问性矩阵项**已落地且被测试断言覆盖**，非仅文档声明。

### 5.2 A-0N 说明（视觉侧只管，音频侧归阮和鸣）
- `accessibility-matrix.md` v0.5 已将原 `AUD-*`（行 19–22）renumber 为 **`A-0N`**（A-01~A-05，音频硬约束，权威源 `control-manifest.md` §8），编号并轨完成（治理注块收口）。
- **视觉侧与 A-0N 无耦合**：A-0N 为音频分层（Basic/Standard/Comprehensive）消费，其取值范围在音频规格 §1.7；playtest 报告 D2（A-0N 音频档实机消费未观察到）属**音频域（阮和鸣）**，不影响视觉侧任何矩阵项。
- 交叉影响：**无**。视觉 a11y 健康，独立于 D2。

---

## 6. 命名 / 目录 / .import / .uid 规范

- **目录结构**：`arts/ui/`（视觉）、`arts/audio/`（音频）分层合理；与 `project.godot` 的 `buses/default_bus_layout` 路径一致。✅
- **命名**：`ui_badge_corrupt`（类别_语义）、`sfx_ui_save_success/failure`（sfx_域_事件）均 snake_case 规范。✅
- **.import 元数据**：`source_file` / `dest_files` / `uid` 三段齐全；svg 用 `compress/mode=0`（无损）、`mipmaps/generate=false`（UI 图标正确）；wav 参数正常。✅
- **.uid 跟踪**：导入型资产（svg/wav）的 uid 正确内嵌于 `.import`（`uid="uid://..."`）；Godot 4.4 对 imported 资产以 `.import` 内 uid 为权威，**`arts/` 下无独立 `.uid` 文件属正常**。项目级 `.uid` 仅见于脚本/场景（如 `addons/gut/*.gd.uid`），与本项目资产无关。✅
- **生成缓存**：`.godot/imported/*.ctex`、`*.sample`、`*.md5` 均存在 → 导入态健康，无退化。✅

---

## 7. 发现表

| 资产 / 文件:行 | 问题 | 严重度 | 建议修复 |
|----------------|------|--------|----------|
| `design/assets/asset-manifest.md:53`；`design/assets/entity-inventory.md`（无 ui_badge_corrupt / ui_focus_ring 条目）；`design/assets/sprint3-b-asset-spec.md` §3（计划集 ui_saveslot_row / ui_thumb_placeholder / ui_badge_readonly / ui_actionbar_key_glyph） | **注册表 vs 实装漂移**：清单登记了 `ui_panel_dark_70.tres`、`ui_focus_ring.tres` 等视觉资产，但 `arts/ui/` 仅有 `ui_badge_corrupt.svg`。其余 S3-B 视觉资产均改为**代码绘制**（`save_slots_screen.gd` 焦点环/槽位/缩略图 + `save_ui_model.gd` 文本/字形常量）。无代码 `load()` 这些缺失文件 → **无运行时断链**，纯清单不准确。 | **Minor** | 二选一：① 更新 `asset-manifest.md` / `entity-inventory.md`，将已代码化的项标注「code-rendered, no bitmap」并移除不存在的 `.tres` 名；② 若仍要位图，则补产。建议走①，与 SAV-S5 代码驱动渲染的架构一致。 |
| `design/assets/sprint3-b-asset-spec.md:26,132`；`design/art/ui-badge-corrupt-spec.md:126` | **文件名漂移**：规格写 `ui_badge_corrupt.png`（96×24），实际交付为 `ui_badge_corrupt.svg`（24×24 矢量）。属**有意矢量优先（F-2）**，但规格/清单未同步到 `.svg`，易致混淆。 | **Minor** | 将 `sprint3-b-asset-spec.md` §3.5 与 `asset-manifest.md` 相关行由 `.png` 改为 `.svg`，并注明「矢量源，单一资产双模经 modulate」。 |
| `src/game/vision_cone.gd:35`、`src/game/sound_propagation.gd:50`、`src/game/footfall_vfx.gd:16` | **世界 VFX 颜色字面量未集中**：`#9FB8C9`（冷，视野锥/声环）、`#C8862F`（暖，落足微光）为散落硬编码，未走统一色权模块。色相**正确**（冷≠危险；`#9FB8C9` 经 art-bible §2/§3.4 授权；`#C8862F`=CAUTION/落足，非危险 → C-06 合规），但调色板重调时易漂移。 | **Minor** | 建议新增 `src/game/world_colors.gd`（或并入现有权威）集中世界 VFX 色，降低漂移风险。低优先级、非阻断。 |
| 任务简报「约 3 个文件」vs 实际 `arts/` = 7 个 | **信息项**：简报低估资产数（1 .tres / 1 .svg / 1 .import），实际为 `audio_bus_layout.tres` + `ui_badge_corrupt.svg`+`.import` + 2×`sfx_ui_*.wav`+`.import` = 7 个。"3" 应为仅数视觉相关子集。 | **Info** | 无需修复；供后续审计引用实际口径。 |
| `src/ui/hud_colors.gd:127` + `src/ui/save_ui_model.gd:70-72`；`tests/unit/test_save_ui.gd`（reverse lock） | **FLAG-L 已知残留**：色盲模式下焦点环与损坏徽标同为 `#F0C070`（1.00:1）。已通过「频率维(0Hz vs 2.0Hz) + 形状维(空心矩形 vs 实心三角) + 锚定维」三维正交化解，并有反向锁测试。属**已记录、已接受**残险。 | **Info** | 无需美术动作；保持反向锁测试不被误删。 |
| `arts/audio/*`（3 项） | **音频资产完整且正确导入**，但属音频域（阮和鸣）。命名 `sfx_ui_*` 规范；`.import`/uid/缓存齐全；无孤立导入。 | **Info** | 仅登记，不归本审计处置。 |
| `addons/gut/*` | 第三方测试框架资产（纹理/字体/主题）。 | **Info** | 排除出项目视觉合规范围。 |
| 整体视觉资产足迹 | 当前垂直切片阶段视觉资产**仅 1 个 SVG**，暗黑奇幻/灰烬/潜行基调由签名色板常量 + 着色器承载。资产清单完整性实质为「文档 vs 代码对齐」问题（见 M1/M2）。 | **Info** | 进度健康；后续若引入位图/材质，须同步 `asset-manifest.md`。 |

---

## 8. 汇总计数

| 严重度 | 数量 | 条目 |
|--------|------|------|
| **Blocker** | **0** | — |
| **Major** | **0** | —（D1 检查点逻辑=玩法/引擎；D2 A-0N=音频，均非美术域） |
| **Minor** | **3** | M1 注册表漂移 / M2 文件名漂移 / M3 世界VFX色未集中 |
| **Info** | **5** | I1 资产数低估 / I2 FLAG-L 已接受 / I3 音频资产 / I4 第三方 / I5 足迹 |
| **合计** | **8** | — |

> 关键结论：**美术/视觉域无 Blocker、无 Major**。全部 C-06 铁律守住，唯一视觉资产合规且已正确导入消费，视觉 a11y 矩阵项已实装并被测试断言。问题集中于「文档/注册表与代码实装的对齐」（M1/M2），不阻断运行。

---

## 9. 与 Phase 6 其他 track 的交叉影响

| Track | Phase 6 状态（据简报） | 与本审计的交叉影响 |
|-------|------------------------|---------------------|
| **yan（Playtest）** | GUT 真数 18/227/227/1515、0 Failed/0 Risky/0 N-7b；缺陷 Blocker0 / Major1(D1 检查点触发逻辑缺失) / Minor3 | D1 为玩法/引擎逻辑（文策渊域），**非美术**。视觉 a11y（C-06/C-02/C-03/C-05/C-07）已有实装代码+测试断言支撑，playtest 视觉侧检查无美术阻塞。 |
| **cheng（Perf）** | 剖析运行中；R-02 实时光为逻辑层主风险 | 唯一视觉资产（svg）仅 212B ctex，对纹理/VFX 预算无影响；perf 报告明确 headless 不可测真实帧时间，R-02 风险为引擎/关卡层，**与美术资产无关**。无交叉阻塞。 |
| **D1 检查点触发逻辑** | 代码实现待派（文策渊） | 不涉及美术资产；本审计无依赖。 |
| **阮和鸣（音频 A-0N）** | 音频打磨待派；兼吸收 D2（A-0N 音频项实机消费） | D2 为音频域。视觉侧 a11y 矩阵（行 3/4/13/16）已独立实装，与 A-0N 无耦合。**交叉影响：无**。 |
| **文策渊（GDD/UX）** | — | M1/M2 的注册表/规格漂移涉及 `asset-manifest.md`、`entity-inventory.md`、`sprint3-b-asset-spec.md` —— 这些文档的视觉资产章节需与代码实装（SAV-S5 代码驱动渲染）重新对齐，建议由美术（本报告）提 PR 或请文策渊协同修订。 |

**给团队的下一步建议**
1. **M1（优先）**：修订 `asset-manifest.md` / `entity-inventory.md`，将 S3-B 已代码化的视觉项标注为 code-rendered 并移除不存在的 `.tres` 名（避免后续审计/外包误判为缺失资产）。
2. **M2**：将 `sprint3-b-asset-spec.md` §3.5 与 `asset-manifest.md` 的 `ui_badge_corrupt` 由 `.png` 改为 `.svg`。
3. **M3（低优先）**：世界 VFX 色字面量集中到统一模块，降低调色板漂移风险。
4. 以上均**不阻断** Phase 6 收口；可视为主理人排期的文档/规范 hygiene 收尾。
