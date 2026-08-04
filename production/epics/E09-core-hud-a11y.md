# Epic E09 · 核心 HUD 与可访问性（core-hud-a11y）

- **对应 GDD**：`design/gdd/systems/core-hud-a11y.md`（GDD ⑧）
- **层**：L5 表现/UI 层（架构 §2）
- **依赖**：①–⑦ 全部（只读聚合）；E01（A11ySettings 持久化）；E02（time_scale_changed）；E08（exposure_detected → 软重开 UI）
- **DAG 优先级**：P4（最后，只读聚合）
- **MoSCoW**：**Should**（Tier1 HUD **Must** / a11y 完整包 Tier2）｜ **T 恤**：M
- **上游**：概念 §5（核心 HUD）/§6；control-manifest C-01~C-07、X-01/X-02、V-01~V-06、T-01/T-02；art-bible §8/§9；accessibility-matrix

## 目标
极简、克制、肃穆的 HUD——世界内（diegetic）呈现锥/光池/声环/残影，屏幕仅摘要状态；并落地全部可访问性开关（支柱二 感官愉悦 / 支柱三 自主掌控）。HUD 不破坏肃穆压迫。

## 范围（In Scope）
- 世界内要素编排（锥/光池/声环/残影，由各系统绘制，本系统只管可见性）：见 E05/E04/E06/E03。
- 屏幕 HUD 摘要：可疑度条、当前道具/charges、凝神状态、下一步落点预演。
- 可访问性设置分区：色盲模式、时间缩放滑杆、屏震、雾、动态模糊、文本缩放、字幕。
- 暴露 ALERT UI：`#D64545`（D7 签字；`#7A2E2E` 仅作低不透明填充 α≤0.35）+图标+可关屏震（C-07/V-03）+ 软重开 UI。

## 关键 Story 列表

### E09-S1 · 作为（玩家）我要（看下一步落点预演 + 凝神态）以便（读场有依据）
**Sprint 0**：是
**验收**
- Given core-hud-a11y §2「屏幕摘要含凝神状态 + 下一步落点预演（① 世界内但本系统管辖可见性开关）」；stealth-step-commit §5/§7（ghost footprint + #C8862F 微光）。
- When 玩家进入 FOCUS 并瞄准。
- Then 下一步预演（ghost footprint + 微光）可见，亮度+形状编码（C-05/C-03）；凝神态读出（压暗四周、提亮可读要素，art §8.4）。
**关联**：core-hud-a11y §2；stealth-step-commit §5/§7；control-manifest C-03/C-05；art-bible §8.4。

### E09-S2 · 作为（玩家）我要（看可疑度条）以便（读出还差多少被发现）
**Sprint 0**：否（Sprint 1）
**验收**
- Given core-hud-a11y §5「可疑度条亮度递增+图标（眼/?/!）+数字（C-02）」；patrol-ai §5。
- When E08 发 `suspicion_changed(guard_id,value,tier)`。
- Then HUD 显示图标+数字+亮度递增（颜色仅辅助）；关键指示对比度 ≥7:1（C-02）。
**关联**：core-hud-a11y §5；patrol-ai §5；control-manifest C-02（≥7:1）。

### E09-S3 · 作为（系统）我要（编排世界内要素可见性）以便（锥/光池/声环/残影在世界平面俯读）
**Sprint 0**：是（最小：预演 + 锥 patch 可见）；完整 Sprint 1
**验收**
- Given core-hud-a11y §2「世界内要素由对应系统绘制，本系统只编排/不重绘」；概念 §2（固定高角 45–60° 俯视）。
- When 各系统绘制要素。
- Then E09 管辖其可见性开关（如凝神压暗时提亮可读要素）；要素在世界平面俯视可读，不抢操作焦点。
**关联**：core-hud-a11y §2；concept §2；art-bible §8.1（世界内非屏框）。

### E09-S4 · 作为（玩家）我要（看当前道具/charges）以便（规划有依据）
**Sprint 0**：否（Sprint 1，配合 E07-S6）
**验收**
- Given core-hud-a11y §2「屏幕摘要：当前道具/charges（⑦）」；interactables §4。
- When E07 道具切换/charges 变化。
- Then HUD 显示 `InteractableType` + `charges`（图标+文字，非颜色 C-05）。
**关联**：core-hud-a11y §2；interactables §4/§7；control-manifest C-05。

### E09-S5 · 作为（可访问性玩家）我要（设置色盲/时间缩放/屏震/雾/动模糊/文本/字幕）以便（Own 自己的体验）
**Sprint 0**：否（Sprint 2，a11y 包）
**验收**
- Given core-hud-a11y §7 + control-manifest：C-05/C-06/C-07（色盲 #7A2E2E→#C8862F+图标）、T-01/T-02（时间 0.1–1.0 默认 0.25）、V-03（屏震默认关）、V-04（雾选项）、V-05（动模糊默认关）、X-01（文本 100–150%）、X-02（字幕说话者+图标）、V-01（禁>3Hz 频闪）、V-02（脉动≤2Hz）、V-06（转场 ease）。
- When 玩家在设置菜单调整。
- Then 写入 `A11ySettings`（经 E01 持久化）；生效于对应系统（色盲模式→E05/E08 图标；时间滑杆→E02；屏震/雾/动模糊→VFX；文本/字幕→UI）。
**关联**：core-hud-a11y §7；control-manifest C-/V-/X-/T- 全约束；E01-S6（A11ySettings）；E02-S7（时间滑杆）。

### E09-S6 · 作为（玩家）我要（看到暴露 ALERT 并软重开）以便（失败有反馈且可恢复）
**Sprint 0**：否（Sprint 1）
**验收**
- Given core-hud-a11y §5「暴露 `#D64545`（D7 签字；`#7A2E2E` 仅作低不透明填充 α≤0.35）+脉动(≤2Hz V-02)+图标+可关屏震(V-03)；绝不单色(C-07)」；patrol-ai §2（exposure_detected → 软失败）。
- When E08 发 `exposure_detected`。
- Then HUD 显示暴露 ALERT：`#D64545`（D7 签字；`#7A2E2E` 仅作低不透明填充 α≤0.35）+图标+脉动≤2Hz；色盲模式→`#C8862F` 高亮+图标（C-06）；屏震默认关（V-03）；触发软重开 UI（经 E01 SaveManager 检查点，C4）。
**关联**：core-hud-a11y §5；patrol-ai §2；consistency-review C4；control-manifest C-06/C-07/V-02/V-03。

## 依赖
①–⑦ 全部（只读聚合，不反向驱动玩法）；E01（A11ySettings 持久化）；E02（time_scale_changed）；E08（exposure_detected）。被依赖：无（终端呈现层）。

## 整 Epic 验收标准
1. 世界内锥/光池/声环/残影 + 屏幕四摘要（可疑度/道具/凝神/预演）落地。
2. 面板基调：半透明暗面板 `#1B1B1F`@70–85% + `#3E5C76` 细描边，无外发光/霓虹。
3. 可访问性完整包生效：色盲/时间/屏震/雾/动模糊/文本/字幕（Tier2）。
4. 暴露 ALERT 三重编码（亮度+形状+图标）非单色；屏震默认关；软重开 UI 接 SaveManager。
5. 对比度达标：C-01 ≥4.5:1、C-02 ≥7:1、C-03 ≥3:1。

## 风险
- **R-HUD-1**：HUD 喧宾夺主破坏肃穆。缓解：极简克制、世界内为主、凝神时 UI 退后（art §8.1/§8.4）。
- **R-HUD-2**：可访问性开关若未真正驱动系统 → 合规空转。缓解：E09-S5 与 E01/E02/E05/E08 显式接线 + E10 自检。
- **R-HUD-3**：暴露脉动 >2Hz 触发光敏。缓解：V-02 着色器上限 + E10 CI 断言。

## 与架构 + 控制清单勾稽
- 架构 §2（L5 表现层，经 L2/事件，不直触引擎底层）、§3（HUD 成本可忽略，世界要素归各系统预算）。
- ADR-003（凝神压暗由 time_scale_changed 驱动）、ADR-002（只读聚合不反向驱动）。
- control-manifest：C-01（≥4.5:1）、C-02（≥7:1）、C-03（≥3:1）、C-04（亮度边界非色相）、C-05/C-06/C-07（三重编码/色盲/危险不单色）、X-01/X-02（文本/字幕）、V-01~V-06（眩晕/光敏）、T-01/T-02（时间缩放）。
- core-hud-a11y §8（Tier1 世界内+四摘要+面板；Tier2 a11y 包；Tier3 照片/排行复用）。
