# Epic E07 · 互动物件（interactables）

- **对应 GDD**：`design/gdd/systems/interactables.md`（GDD ⑦）
- **层**：L4 玩法/模拟层（架构 §2）
- **依赖**：E01（EventBus）、E04（LIGHT_TOGGLE → light_state_changed）、E06（DECOY/TRAP 发声）、E08（TRAP/SMOKE 触发机关）
- **DAG 优先级**：P2–P3（组合既有动词，可并行接入）
- **MoSCoW**：**Must**（Tier1 四类）/ **Could**（变体/数量扩展）｜ **T 恤**：M
- **上游**：概念 §3⑥（互动物件）/§5（MVP 3–4 种）；control-manifest G-02/R-02；art-bible §4.2/§5；entity-inventory（互动物件实体）

## 目标
提供小工具集，用「已存在的动词（熄灯/发声/触发）」组合出多种解法——同一扇门可用钥匙、阴影绕行、或声响调虎。道具不引入新机制族，只派发事件给 E04/E05/E06，是 Autonomy 的物化（支柱三 自主掌控 / 支柱一 步步为营）。

## 范围（In Scope）
- MVP 4 类：`DECOY`(诱饵) / `LIGHT_TOGGLE`(可熄光源) / `TRAP`(机关) / `SMOKE`(烟雾)，均映射既有动词。
- `charges` 限量（MVP 每类 2–3 发，关卡补给，entity-inventory 配置）。
- 烟雾临时 `visibility×0.3`（注入 E05，C3）；机关触发声/光/阻（→ E04/E05/E06）。
- 不新增平行系统；Tier2 仅以参数/数量扩展。

## 关键 Story 列表

> **Sprint 2 滑期标注（主理人裁决 1）**：E07 全部 Story（E07-S1~S8）**留 Sprint 2，无滑期**。其中 E07-S7 的「静态扫描 orphan=0」依赖 Tech Debt 治理项 TD-S3（滑 S3），但实例注册/反注册机制本 Sprint 交付；orphan=0 为 WARN-ONLY，不进 N-7 门。

### E07-S1 · 作为（玩家）我要（投声响诱饵生成可控噪声圈）以便（引开守卫）
**Sprint 2**：是（实体级；Sprint 1 仅消费信号级占位）
**验收**
- Given interactables §2「DECOY decoy_landed(pos,surface,radius≈8m) → ④」；system-breakdown §2。
- When 玩家对准+投掷诱饵（复用 E03 aim 逻辑选落点）。
- Then 发 `decoy_landed(pos,surface,radius≈8m)` → E06 生成 DECOY 声事件；charges−1。
**关联**：interactables §2；sound-propagation §2；system-breakdown §2。

### E07-S2 · 作为（玩家）我要（熄灯/点亮可互光源）以便（主动制造阴影）
**Sprint 2**：是（实体级；Sprint 1 仅消费信号级占位）
**验收**
- Given interactables §2「LIGHT_TOGGLE light_state_changed(id, EXTINGUISHED/LIT) → ⑤」；cover-shadow §4。
- When 玩家对准可互光源按互动键。
- Then 发 `light_state_changed(id, state)` → E04 切换 OmniLight + 自发光 + 雾 ramp（R-05）+ 触发 E05 受影响 cell 重算。
**关联**：interactables §2；cover-shadow §4；system-breakdown §2；control-manifest R-05。

### E07-S3 · 作为（玩家）我要（触发机关产生声/光/阻）以便（多解克制唯一解）
**Sprint 2**：是（实体级；Sprint 1 仅消费信号级占位）
**验收**
- Given interactables §2「TRAP interactable_triggered(id, TRAP) → 声/光/阻（④/⑤/⑥）」。
- When 玩家触发机关（拉杆/符文/绞盘）。
- Then 发 `interactable_triggered(obj_id, TRAP, payload)` → 路由到 E04/E05/E06（声/光/阻），不新增机制。
**关联**：interactables §2；system-breakdown §2。

### E07-S4 · 作为（玩家）我要（掷烟雾临时降可见性）以便（制造脱身窗口）
**Sprint 2**：是（实体级；Sprint 1 仅消费信号级占位）
**验收**
- Given interactables §2「SMOKE interactable_triggered(id, SMOKE) → 临时 visibility×0.3（限时≈4s）」；consistency-review C3（烟雾改写 ③ 可见性）。
- When 玩家掷烟雾。
- Then 发 `interactable_triggered(id, SMOKE)`；落点区生成临时区，E05 `compute_visibility` 乘 ×0.3（≈4s 后失效）。
**关联**：interactables §2；consistency-review C3；vision-cone（visibility_multiplier）；control-manifest C-05。

### E07-S5 · 作为（系统）我要（charges 限量且按 entity-inventory 配置）以便（道具是规划工具非无限）
**Sprint 2**：是（实体级；Sprint 1 仅消费信号级占位）
**验收**
- Given interactables §2「charges 限量（MVP 每类 2–3 发，关卡补给）」；entity-inventory（互动物件实体表）。
- When 关卡加载 / 玩家触发道具。
- Then 运行时查 `charges>0` 方可触发；用尽需补给；配置来自 entity-inventory。
**关联**：interactables §2/§3；entity-inventory（互动物件）；concept §5（MVP 3–4 种）。

### E07-S6 · 作为（玩家）我要（HUD 显示当前道具/charges）以便（规划有依据）
**Sprint 2**：是（实体级；Sprint 1 仅消费信号级占位）
**验收**
- Given core-hud-a11y §2「屏幕 HUD 摘要：当前道具/charges（⑦）」；interactables §4。
- When 道具切换 / charges 变化。
- Then E09 显示当前 `InteractableType` + `charges`（图标+文字，非颜色 C-05）。
**关联**：core-hud-a11y §2；interactables §4/§7；control-manifest C-05/X-02。

### E07-S7 · 作为（系统）我要（互动物件实例注册/反注册）以便（防 orphan）
**Sprint 2**：是
**验收**
- Given Sprint 1 残留 orphans（工程报 23）；互动物件实例须引用计数。
- When 关卡加载 / 卸载 / 道具实体销毁。
- Then 注册表增删一致；关卡卸载后无悬空引用；静态扫描 orphan=0（WARN-ONLY，不进 N-7 门）。
**关联**：Tech Debt TD-S3；entity-inventory（实体生命周期）；control-manifest（无编号，治理项）。

### E07-S8 · 作为（系统）我要（道具声环/光源计入全局预算）以便（不破 G-02/R-02）
**Sprint 2**：是
**验收**
- Given DECOY 声环须计入 E06 FIFO（G-02 ≤8）；LIGHT_TOGGLE 熄灯须释放/占用 E04 实时光（R-02 ≤32）。
- When 道具触发。
- Then 预算计入对应系统；CI 断言不破 G-02/R-02。
**关联**：consistency-review R-物-1/R-物-2；control-manifest G-02/R-02；E06/E04。

## 依赖
E01（EventBus）、E04（LIGHT_TOGGLE）、E06（DECOY/TRAP 发声）、E08（TRAP/SMOKE 触发）。发出 `decoy_landed`/`light_state_changed`/`interactable_triggered`。被依赖：E06（诱饵声）、E04（熄灯）、E05（烟雾可见性）、E08（机关）、E09（道具 HUD）。

## 整 Epic 验收标准
1. 四类（DECOY/LIGHT_TOGGLE/TRAP/SMOKE）均仅派发既有事件，无新机制族。
2. `charges` 限量且按 entity-inventory 配置；用尽不可触发。
3. 诱饵半径≈8m；烟雾 visibility×0.3 限时≈4s（注入 E05）。
4. HUD 显示道具/charges（图标+文字，C-05）。

## 风险
- **R-物-1**：道具声环/光源若未计入全局预算 → 破 G-02/R-02。缓解：E06 统一 FIFO（G-02）、E04 接管 R-02（consistency-review 无硬阻塞）。
- **R-物-2**：烟雾可见性若未注入 E05 → 掩体变无敌。缓解：E07-S4 + E05-S6（C3）。

## 与架构 + 控制清单勾稽
- 架构 §2（L4，仅派发事件）；§3（道具不新机制族）。
- ADR-002（事件驱动）。
- control-manifest：G-02（声环≤8，诱饵/机关计入 E06 FIFO）、R-02（可熄光源计入 E04 ≤32）、C-03（交互提示亮度差≥3:1）、C-05（图标+标签非颜色）、X-02（机关/诱饵字幕）。
- interactables §8（Tier1 四类；Tier2 变体参数；Tier3 机关谜题复用）。
