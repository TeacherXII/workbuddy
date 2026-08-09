# Localization Coverage · ASHEN STEP《灰烬之步》Phase 7 — 内部封闭 alpha

**文档类型：** 本地化覆盖盘点
**负责人：** 路远行（release-ops-lead）
**发布范围：** 仅 zh-CN（简体中文）
**盘点方法：** 只读扫描（`project.godot`、`*.translation`、`translation*.csv`、`ProjectSettings` internationalization 段、`src/` 中 `TranslationServer`/`get_locale`/`tr(` 调用）

---

## 1. i18n 框架扫描结论

| 检查项 | 结果 |
|---|---|
| `project.godot` 的 `[application]` 是否有 `version` | ❌ 缺失（见 release-checklist §2） |
| `project.godot` 是否含 `[internationalization]` / locale 配置 | ❌ **无**（全文件无 locale / translation 段） |
| `*.translation` 资源文件 | ❌ **仓库内零个** |
| `translation*.csv` 字符串表 | ❌ **仓库内零个** |
| `src/` 调用 `TranslationServer` / `load_translation` / `get_locale` / `tr(` | ❌ **零调用**（排除 `addons/gut` 后为空） |
| `src/` 中 `str(...)` / 枚举名映射 | ✅ 存在，但均为字符串转换 / 显示名映射，**非翻译 API** |

**结论：项目当前没有任何国际化（i18n）框架。** 既无 `TranslationServer` 接入，也无字符串表（`.translation` / `.csv`），`project.godot` 未配置任何 locale。Godot 默认 locale 为系统 locale，但项目未提供任何替代语言资源——游戏显示的内容就是**源码中写死的字符串**。

---

## 2. 现有字符串资产盘点

由于没有 i18n 框架，所有玩家可见文案均为**源码硬编码**。扫描结果：

- **玩家面向 UI 文案 = 简体中文（zh-CN）：**
  - 确认对话框：`"取消"` / `"确定"`（`src/ui/save_slots_screen.gd:906-907`）
  - HUD 标题：`"灰烬之步 · Sprint1"`（`src/ui/hud_slice.gd:257`）
  - 字幕 / toast / 确认弹窗正文（`save_slots_screen.gd`、`save_ui_model.gd`）
- **枚举 / 调试标签 = 英文（非玩家关键，属内部标识）：**
  - `TIER_NAMES`：`"MVP"` / `"Tier2"`（`guard_spawner.gd:71`）
  - `VARIANT_NAMES`：`"STANDARD"` 等（`guard_variant_params.gd:219`）
  - `LEGACY_CB_NAMES` / `CB_MODE_NAMES`：`"OFF"` / `"PROTAN"` …（`a11y_settings.gd`）
  - `FOG_OPTION_NAMES`：`"FULL"` 等
  - 这些为引擎/调试层标识，内测者通常不可见或仅在调试上下文出现。

**资产语言结构：** 玩家面向 UI 以 zh-CN 为主；少量英文为枚举/调试标识。对**内部封闭 alpha** 而言，此混合可接受（无对外暴露的本地化质量要求）。

---

## 3. 缺口（Gap）

| 缺口 | 严重度 | 说明 |
|---|---|---|
| 无正式 i18n 框架（TranslationServer + 字符串抽取） | Info（本次不阻塞） | 当前所有字符串硬编码。未来要做多语言，须先接入 `TranslationServer`、抽取字符串表、建 `.translation`/`.csv` 流水线。 |
| 无字符串表 / 无翻译记忆 | Info | 无集中可译资源，无法做增量翻译或译员协作。 |
| 玩家 UI 混用 zh-CN 与英文枚举标签 | Info | 属内部标识，内测可接受；正式多语言时需统一口径。 |
| 无 RTL / 平台 locale 适配 | Info | 仅 zh-CN 不涉及 RTL；未来多语言（如阿拉伯语）才需。 |

> 上述缺口**均不阻塞本次发布**——本次范围明确为 zh-CN only。

---

## 4. 结论

**本次发布：zh-CN only（简体中文，唯一语言）。**

- 项目无多语言框架，"zh-CN only" 是通过**源码写死中文 UI 文案**实现的隐式单语状态，而非通过 locale 切换锁定。
- 内测者将看到简体中文界面；无语言切换选项（当前也不应有）。
- 未来若要扩展语言：须先建设 i18n 基础框架（接入 `TranslationServer`、抽取字符串表、建翻译流水线），再进入本地化生产。该项不计入本次发布阻塞。

---

*本盘点为只读扫描，未改动任何文件。结论：本次发布 zh-CN only。*
