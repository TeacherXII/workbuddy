# Sprint 1 · Batch A 闭合（词汇 + 光影地基）

**汇编人**：游承峰（主理人 / Orchestrator）
**日期**：2026-08-02
**状态**：✅ 实现完成 + 设计评审 PASS + QA 收口（CONCERNS 已修）→ **可进 Batch B**
**上游**：`production/sprints/sprint1-plan.md`（Batch A 编排）· `production/sprints/sprint1-stories.md`（§1.1/§1.2/§4）· `docs/sprint1-batchA-impl.md`（程基岩实现说明）· `docs/sprint1-batchA-design-review.md`（文策渊）· `tests/qa/sprint1-batchA-qa.md`（严守真）

---

## 1. 本批交付（7 Story 全实现）

| Story | 内容 | 落盘 |
| --- | --- | --- |
| **E01-S9** | 事件词汇收口：修正 `light_state_changed`(light_id,state) + `suspicion_changed` 加 tier + 补 4 信号（cover_state_changed/vision_looming/guard_transform_dirty/guard_fsm_changed）+ 枚举 LightState/SusTier | `src/core/event_bus.gd` |
| **E04-S3** | `get_cover(pos)` 盖板查询（降可见+LOS 中断候选，非无敌） | `src/game/light_model.gd` |
| **E04-S4** | `light_state_changed` 完整签名 + LightState 字典注册 | `src/game/light_model.gd` |
| **E04-S7** | 受影响 cell 仅重算（O(cell)，非全图） | `src/game/light_model.gd` |
| **E03-S5** | 噪声半径全 surface（MOSS 0.5） | `src/game/step_commit.gd` |
| **E03-S6** | 三步态完整（RUN 4.0/0.24/2.0，高成本 deliberate） | `src/game/step_commit.gd` |
| **E03-S7** | 落足微光 `#C8862F` + 足音字幕 + ghost_trail≤6（headless 安全） | `src/game/footfall_vfx.gd` + `step_commit.gd` |

**连带修复**（E01-S9 签名破坏性改动的必要后果）：`src/main/sprint0_bootstrap.gd`（suspicion_changed 改发 3 参）、`src/ui/hud_slice.gd`（handler 对齐 3 参）。

**测试**（headless 安全纯逻辑）：新建 `tests/unit/test_event_bus.gd`（4 例）；扩 `test_light_model.gd`（+3：get_cover/light_state_changed/dirty cell）；扩 `test_step_commit.gd`（+3：noise_radius/gait_run/footfall_vfx）。

---

## 2. 质量门判定

### 2.1 设计评审（文策渊）→ **PASS**
- 范围纪律：四支柱全守（步步为营/肃穆压迫经 E03 步进 + E04 光影服务）。
- **两大 GDD 词汇冲突已收口为单一事实来源**：
  - **Surface**：权威集 `{STONE, GRASS, METAL, MOSS}`，`SURFACE_FACTOR = 1.0/0.7/1.2/0.5`；`WOOD` 仅资产材质→映射 STONE（资产旧值作废为命名权重，非玩法乘子）。
  - **SusTier**：`CALM|SUSPICIOUS|ALERT|SEARCH`（CALM = 可疑度 <25），system-breakdown §2.3 的 `NONE` 已改为 `CALM`。
  - 回写 GDD 6 处：`stealth-step-commit.md` §2/§3、`system-breakdown.md` §2.3、`asset-manifest.md` §3.1、`patrol-ai.md` §3、`ux-spec.md` 世界锚表。
- **代码常量一致性**：`SURFACE_FACTOR` 与 `SusTier` 已与裁决完全一致 → **程基岩无需改常量**。

### 2.2 QA 冒烟就绪（严守真）→ **CONCERNS（已修）**
- 三文件断言 API 与实现完全一致；新增/扩展测试纯逻辑、headless 安全 → 非 FAIL。
- 发现的 4 条：
  - **A（已修）**：`test_light_model.gd` 漏 `watch_signals(_lm)` → 程基岩已补第 18 行，消除 GUT 9.3.0 虚假失败风险。
  - **B（预期纠偏，非缺陷）**：CI 整体退出码在 **Batch D 之前都会 RED**（继承 Sprint 0 的 6 个 TD 失败），Batch A 成功标准为**三新测试文件各自全绿**，不是整体 0。
  - **C（已随设计评审解决）**：GDD 缺口（MOSS/STONE/SusTier）已由文策渊收口，测试与实现一致不阻 CI。
  - **D（前瞻）**：`footfall_vfx.gd` 进树路径的 headless 安全归 Batch D 校验。
- 另：2 处过时 GAP 注释（step_commit.gd / event_bus.gd）已清理为权威来源引用。

---

## 3. ⚠️ 给用户的关键预期

**推送 Batch A 后，GitHub Actions 整体仍会 RED**——这是预期内的，因为 Sprint 0 遗留的 6 个集成测试（`test_integration_step_vision.gd`）失败要等到 **Batch D（E10-S1）** 才修复。

**判断 Batch A 是否成功的唯一标准**：在 Actions 日志里看这三个测试文件是否各自全绿：
- `test_event_bus`（4 例）
- `test_light_model`（既有 6 + 新增 3 = 9 例）
- `test_step_commit`（既有 8 + 新增 3 = 11 例）

不要因为整体退出码非 0 误判 Batch A 坏了。**整体 CI 绿是 Sprint 1 退出标准 #2，由 Batch D 达成。**

---

## 4. 批间冒烟预期（A 末，待用户 push 后 CI 验证）

| 文件 | 例数 | 预期 |
| --- | --- | --- |
| `test_event_bus` | 4 | 全绿 |
| `test_light_model` | 9 | 全绿（含 watch_signals 修复后） |
| `test_step_commit` | 11 | 全绿 |
| `test_integration_step_vision` | 6 | 仍失败（继承，Batch D 修） |

---

## 5. 下一步：Batch B（视野完整 + 声音）

依赖 Batch A 的光影/噪声地基，包含：E05-S5（vision_looming）/ E05-S6（visibility_multiplier 注入）/ E05-S7（锥可视化脉动）/ E06-S1（emit+网格通知）/ E06-S2（落足声）/ E06-S3（声环≤8 FIFO）/ E06-S5（距离衰减提可疑度，可后置 Batch C 初）。

**Batch B 开工前置**：仅「2 处注释清理」顺手项（已完成），无代码常量改动需求 → **可直接进 Batch B**。

---

*Batch A 闭合 v1.0。实现 `docs/sprint1-batchA-impl.md`（程基岩）+ 设计评审 `docs/sprint1-batchA-design-review.md`（文策渊）+ QA `tests/qa/sprint1-batchA-qa.md`（严守真）均落盘。主理人汇编，待用户 push 验证 CI 三文件绿，再派程基岩启动 Batch B。*
