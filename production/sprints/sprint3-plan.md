# Sprint 3 计划 · 滑期段（守卫变体 / 手动存档 UI / Tech Debt 收口）

> 主理人：游承峰 ｜ 阶段：Phase 5 制作（Sprint 3）｜ 批序：A → B → C
> 来源：`epic-overview.md` §Sprint 3 + `sprint2-stories.md` §2 滑期表
> 主线基线：main = `57dcf96`（Sprint 2 三批 A/B/C 已收口，GUT 122/122，CI 双绿）

## 1. Phase 0 诊断

| 项 | 取值 |
| --- | --- |
| 引擎 | Godot 4.4（Forward+ / Vulkan / GDScript） |
| 目标平台 | Desktop / PC（RTwP 潜行） |
| 评审强度 | **lean / 全委托**：用户授权「全权交给你 / 不用我去看」→ 主理人核验 + CI 门 + 自主合并，不要求人工 PR 审阅 |
| 进入阶段 | Phase 5 制作（Sprint 3），按冲刺循环推进 |
| 质量门 | N-7（裸 `[Risky]` 误红防护）+ `budget_assert` WARN-ONLY + GUT 全绿；Sprint 1 已锁断言零漂移 |

## 2. 范围（三批）

### S3-A · 守卫变体（E08 · S7 / S9 / S10）
- **E08-S7** 变体参数覆盖：循声猎犬 `KV15 / KS30 / 感知半径×1.6 / 锥 11m·30°`；暗视哨兵 `vision_light_floor = 0.05`。复用 `GuardBrain` FSM，不新增系统/机制族。
- **E08-S9** 变体实例化 + `entity-inventory` 类型绑定，由资产驱动参数覆盖，计入 G-01 守卫预算（≤8 MVP / ≤16 Tier2）。
- **E08-S10** 变体 FSM 合并验证：基类阈值契约 `THR_SUSP=25 / THR_ALERT=60 / THR_RETURN=10 / DECISION_HZ=10` 不被污染。**强制「参数对象」模式，禁止运行时 mut 类常量**（FLAG-B 中-高）。
- 新增 `tests/unit/test_guard_variants.gd`（E08-S7/S9/S10）+ G-01 守卫预算断言扩展（WARN-ONLY）。

### S3-B · 手动存档/读档 UI（E11 · SAV-S5）
- 暂停菜单槽列表（时间戳 / 检查点 id / 缩略占位）、存 / 读 / 覆盖确认 / 删除入口；与检查点滚动槽（`-1`）共存。
- 数据层 Sprint 2 已交（`write_slot` / `read_slot` / 3 槽上限 / 体积门），本批为纯表现层增量。
- a11y 合规：正文 ≥4.5:1（C-01）/ 关键指示 ≥7:1（C-02）/ **焦点环 `#F0C070`（C-06 现行裁决值，非旧 `#C8862F`）** / 读档字幕（X-02）/ 无 >3Hz 频闪（V-01）。
- 音频：成功单声低音「嗒」、失败闷响 + ⚠、读档 0.4s 淡入。
- ⚠️ 追溯：GDD §8 将手动存档列 Tier1，本次为有意延后（FLAG-K），建议 GDD §8 同步注记（文策渊责任域）。

### S3-C · Tech Debt 收口（TD-S1 ~ TD-S4）
- **TD-S1** `hud_slice.gd:432` `set_aim_preview` 用 `get_viewport().get_camera_3d()`，headless 下可能 null → 缓存 + 空判 + 测试注入。
- **TD-S2** 凝神压暗/提亮（`_dim` + `_set_world_boost`）无具名常量且未纳入 a11y 雾管控 → 常量化入 `HudColors`。（原 `FOCUS_TINT` 实测不存在，已降级。）
- **TD-S3** 全局 orphans 治理（守卫/其余实例；互动物件部分 `E07-S7` 已覆盖）；**不进 N-7 门**。
- **TD-S4** 跨 Sprint 全量债务 + QA 门收口（S1+2+3 全量五退出标准 + 上述 TD 项）。

## 3. 退出标准（Sprint 3，来自 epic-overview）

1. 守卫变体不破核心（Tier2 16 同行不破动态光 32，R-02，光 LOD ADR-004）；变体 FSM 合并无状态污染（FLAG-B）。
2. 手动存档/读档 UI 闭环：槽列表 / 存 / 读 / 覆盖确认 + 与检查点滚动槽共存。
3. Tech Debt 收口 + GUT 全绿 + `budget_assert` WARN-ONLY 无破门 + N-7 门不因裸 `[Risky]` 误红（E10）。

## 4. 铁律（继承 Sprint 2 收口纪律）

- **N-7 门正则**：`\[Risky\]:|\[Pending\]:|\[Risky\] Script was skipped`；测试/注释中**禁写**方括号包 `Risky`/`Pending`。
- **E01-S9 事件词汇冻结**：本 Sprint **零新增信号**（守卫变体复用既有 `suspicion_changed`/`guard_fsm_changed`/`exposure_detected`/`guard_transform_dirty`）。
- **FLAG-J**：`save_manager.gd` 不得硬编码 a11y 字段名（注释亦禁）。
- **写入即钳制** + **反向断言防 rot-while-green**（继承 Batch C 手法）。
- 本地 `godot` 不在 PATH → 靠 CI 实跑 GUT；PR 由主理人核验 + 合并（成员禁自合）。

## 5. 已知风险与缓解

| 风险 | 缓解 |
| --- | --- |
| FLAG-B（中-高）：变体参数覆盖若实现为运行时 mut 类常量 → 破 Sprint 1 阈值测试 | 强制「参数对象」模式（E08-S10）；合并测试断言基类阈值契约不漂移 |
| S3-B 与 TD-S1/S2 都碰 `hud_slice.gd` | 批序 B 在 A 后、C 紧随，顺序合并避免并行改同文件冲突 |
| C-06 取值 `#F0C070` 已裁决，旧文档 `#C8862F` 仍残留 | 所有新 UI/代码用现行值；旧文档收口归文策渊/林绘澄责任域（待跟） |
| `@ci:no-orphans`（TD-S3）不进 N-7 门 | TD-S3 仅 WARN-ONLY，失败不破构建 |

## 6. 批序与分支

- 分支：`feat/s3-a` → `feat/s3-b` → `feat/s3-c`，均 PR 至 `main`，顺序合并（每批基于已合并的 main）。
- S3-A（守卫变体，独立文件）→ S3-B（存档 UI，碰 hud_slice）→ S3-C（Tech Debt，碰 hud_slice）。

## 7. 待跟下游文档（非本 Sprint 工程域，登记）

- **Group 3 · 真·C-06 告警映射旧值 `#C8862F`（已作废→`#F0C070`）**：`hud-a11y-signature.md` / `sprint2-asset-spec.md` / `batchc-impl-spec.md` / GDD `patrol-ai.md` / `core-hud-a11y.md` / `ux-spec.md` 中作为**告警/危险映射色**的残留 → 改 `#F0C070`。归林绘澄。
- **Group 2 · 焦点环色 `#C8862F`（独立、仍生效的美术规范，非 C-06）**：`art-bible.md` §9.4(L295) / `accessibility-matrix.md` 行13/§3.1/§4 / `ux-spec.md` §3.3/§2.3 A14。⚠️ 此前把焦点环标成「(C-06)」是**标注错误**——焦点环与 C-06 告警映射是两件事，只是恰好同 HEX。
  - **O-1 裁决（主理人，2026-08-05）**：焦点环必须满足 C-02（关键指示 ≥7:1）。`#C8862F` vs `#1B1B1F` = **5.65:1，不达标，拒绝**。默认 **Option A**：全局焦点环 → `#F0C070`（10.20:1，稳过 C-02，保留烛琥珀品牌），由林绘澄美术签字后改 `art-bible.md` §9.4 / `accessibility-matrix.md` 行13。备选 Option C：`#DCE3EC` 2px(13.28:1)+内衬 `#F0C070` 1px（最高对比、零语义撞色，但偏系统 UI 感，需林绘澄评品牌）。S3-B 规格已用 `#F0C070` + EC-11（频率/形状常驻编码）缓解色盲撞色。
  - **FLAG-L（新立，中-高）**：`#F0C070` 被告警映射 + 焦点环两语义共用；根治 = 把「焦点环」登记为独立语义槽位，勿再借告警色族。
- **SAV-S5 AC 修正**：原「焦点环 `#C8862F`(C-06)」标注错误 → 改「焦点环 `#F0C070`（O-1 Option A，C-02 达标）」。
- GDD §8 Tier1 vs 排期注记（FLAG-K）：**已闭环**（save-system.md §8 已有 Tier1 注记），无待办。
