# Sprint 1 冲刺计划 ·《灰烬之步》ASHEN STEP — Phase 5 制作

**汇编人**：游承峰（主理人 / Orchestrator）
**日期**：2026-08-02
**状态**：计划就绪，待主理人裁决开放项后进入执行
**上游**：`production/epics/epic-overview.md`（§3 Sprint 1）· `docs/sprint0-closure.md`（CONCERNS）· `design/reviews/sprint1-design-scope.md` · `production/sprints/sprint1-stories.md`

---

## 0. 冲刺目标

**核心循环闭环**——把 Sprint 0 的「最小可玩切片」扩成完整可玩的「扫描→规划→提交→读反馈→调适」循环，并让 CI GUT 冒烟全绿（闭合 N2 的 6 个失败测试）。

依赖链（最长实现链）：`E01 → E02 → E03 → E04 → E05 → E06 → E08 → E09`；E10 贯穿收口。

---

## 1. 范围纪律判定

| 维度 | 判定 |
| --- | --- |
| 四支柱 | ✅ **全守，无漂移**（逐系统见 `sprint1-design-scope.md` §2） |
| 范围边界 | ✅ **未越界**：E07 整系统 + a11y 完整包（Tier2）显式推迟 Sprint 2 |
| 设计就绪度 | ✅ **全部 READY**；8 项 GDD 缺口（G1–G8）须在 Story 开工前闭环 |
| Sprint 0 CONCERNS | ⚠️ 4 项全部映射到具体 Story（见 §4） |
| 一致性 C1–C4 | ⚠️ 全部映射到 Sprint 1 收口项（部分跨 Sprint 2） |
| **总判定** | **PASS / CONCERNS**（无硬阻塞） |

---

## 2. Sprint 1 设计范围（Do / Dont 速览）

> 完整 Do/Dont + 数值锚见 `design/reviews/sprint1-design-scope.md` §1。

**做（Do）**：
- **E03 完整**：三步态（SNEAK 1.5/0.55/0.5 · WALK 2.5/0.38/1.0 · RUN 4.0/0.24/2.0）+ ghost_trail ≤6 + 噪声半径全 surface（STONE 1.0 / GRASS 0.7 / METAL 1.2）+ 落足微光 `#C8862F` + 足音 foley（收口 Sprint 0 CONCERN #4）
- **E04 完整**：`get_cover`（降可见+断 LOS，不无敌）+ `light_state_changed` 事件驱动 cell 重算 + 可熄灯过场（R-05 ramp≤0.12/≤0.4s + V-06 ease）+ LightmapGI 单区域 bake
- **E05 完整**：锥缘 tell `vision_looming` ≤2Hz（V-02）+ 外部 `visibility_multiplier` 注入槽（C3，掩体接入）+ 锥可视化（冷白 `#9FB8C9`，C-03）
- **E06 完整**：footfall 声环 ≤8 FIFO（G-02）+ `sound_emitted` 守卫通知 + 诱饵 DECOY 声圈（信号级）+ 落足微光/足音
- **E08 核心**：五态 FSM（CALM→SUSP→ALERT→SEARCH→RETURN）+ 连续可疑度 25/60/10 + 暴露梯度 1.2s 软失败（C4）+ A* 仅状态转换（G-05）
- **E09 核心**：可疑度条（C-02 ≥7:1）+ 暴露 UI `exposure_detected` + 道具/charges 槽占位 + 面板基调 `#1B1B1F@70-85%`+`#3E5C76`
- **E10 部分**：headless GUT 全绿（含 6 tech-debt）+ control-manifest §7 部分断言

**不做（Dont，留给 Sprint 2/收尾）**：
- ❌ E07 互动物件完整系统（DECOY/LIGHT_TOGGLE/TRAP/SMOKE 四类型 + charges + entity-inventory）——Sprint 1 仅接其**事件副作用**
- ❌ a11y 完整包（色盲/时间滑杆/雾/动态模糊/文本缩放/字幕）——Tier2
- ❌ 守卫变体（循声猎犬/暗视哨兵）、多区域全量 bake、Steam 导出、完整存档/读档 UI

---

## 3. Story 拆分（33 条）

> 完整 Story 表（验收 Given/When/Then、依赖、T 恤、退出钩子、控制清单）见 `production/sprints/sprint1-stories.md`。

**产品 Story 27 条**：E01×1（S9 词汇收口）· E03×3（S5/S6/S7）· E04×4（S3/S4/S5/S7）· E05×3（S5/S6/S7）· E06×5（S1–S5）· E08×7（S1–S6/S8）· E09×4（S2/S3/S4/S6）· E10×2（S1/S2）

**tech-debt 6 条（TD-1~6）**：6 个失败 GUT 测试（全在 `test_integration_step_vision.gd`，headless 缺 SceneTree）→ 主负责 **E10-S1**（harness 修复）+ 各产品 Story 回归守卫

### 实现批次（4 批，每批独立可冒烟）

```
Batch A  词汇+光影地基   E01-S9 · E04-S3/S4/S7 · E03-S5/S6/S7
Batch B  视野完整+声音   E05-S5/S6/S7 · E06-S1/S2/S3/S5
Batch C  AI+HUD 核心     E08-S1/S2/S3/S4/S5/S6/S8 · E09-S2/S3/S4/S6
Batch D  收口            E06-S4 · E04-S5 · E10-S2 · E10-S1（签收，含 6 tech-debt）
```

> **拓扑修正（2026-08-04，batchd-design-review §1.0）**：原表有三处与实际不符，已订正——
> ① **E04-S5 孤儿**：§3 散文写 `E04×4（S3/S4/S5/S7）`，原 Batch A 却只列 S3/S4/S7，S5 从未进入任何批次（`light_model.gd` 无 ramp 实现、`test_light_model.gd` 无 ramp 测试佐证）→ 归入 Batch D。
> ② **E09-S4 已在 Batch C 完成**（`hud_slice.gd:60` + `test_hud_slice.gd:335/347`）→ 从 Batch D 移至 Batch C。
> ③ **E10-S1 已闭**（commits f8b3c58 / c1421c5 / 452614f，CI 83/83，N-7 门已落地）→ Batch D 内仅作签收，不重开。

批间冒烟：A→`test_light_model`+`test_step_commit`；B→`test_vision_cone`+`test_sound_propagation`；C→`test_patrol_ai`+`test_hud_slice`；D→全量 GUT 退出 0。

---

## 4. CONCERNS / C1–C4 收口映射

| 来源 | 归属 Story | 动作 |
| --- | --- | --- |
| Sprint0 CONCERN #1 N2 | **E10-S1** | 可运行环境跑通 headless GUT 全绿 |
| Sprint0 CONCERN #2 HUD 测试需 SceneTree | **E09 + E10-S1** | 固化 HUD 测试 harness |
| Sprint0 CONCERN #3 事件词汇 3 差异 | **E01-S9** | 补全 13 信号 + 统一签名 |
| Sprint0 CONCERN #4 落足微光/足音 | **E03-S7 + E06-S4** | emissive quad + foley |
| C1 声环≤8 FIFO | **E06-S1/S3** | VFX + E10-S2 断言 |
| C2 动态光 32 上限 | **E04 + E10-S2** | MVP≤12 + CI 盯 32 |
| C3 烟雾改写可见性 | **E05-S6** | `×external_multiplier` 槽 + 掩体接入 |
| C4 暴露软失败 | **E08-S4 + E01 minimal SaveManager** | 检查点重生 |

---

## 5. 退出标准（Sprint 1）

1. **完整核心循环可玩**：扫描（E05 锥+looming）→ 规划（E03 预演+三步态）→ 提交（E03 落足+微光/足音）→ 读反馈（E09 可疑度条/世界要素）→ 调适（E08 FSM + 暴露 1.2s 软失败 C4 跑通）。
2. **CI 冒烟全绿**：`godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests/unit -gexit` 退出 0（含 6 tech-debt 修复）。
3. **事件词汇零漂移**：E01-S9 收口后 `event_bus.gd` == `system-breakdown` §2，CI lint 无未声明信号。
4. **§7 预算断言运行**：E10-S2 跑通，声环>8 / 脉动>2Hz / ramp>0.12 等命中产告警。
5. **控制清单达标**：C-02≥7:1、V-02≤2Hz、G-02≤8、R-05 ramp≤0.12/≤0.4s 经 `@test_*`/`@ci:*` 卡门。

---

## 6. 开放项裁决（2026-08-02 用户拍板）

| # | 开放项 | **裁决** |
| --- | --- | --- |
| **D1** | RUN 红线（G1） | ✅ **留 MVP**，定位「高成本 deliberate 选项」（噪声 10m 显著引怪，非无脑冲刺）；若 playtest 成主导策略依 consistency-review 取舍1 降级 Tier2 |
| **D2** | E07 信号级 vs 实体级 | ✅ **接受信号级完成、实体级延 Sprint 2**（E06-S4/E09-S4 消费已声明信号+测试桩） |
| **D3** | 6 失败测试修复策略 | ✅ **策略 1+2 组合**（SceneTree harness 使 add_child 有效 + 纯逻辑断言降耦） |
| **D4** | Story 粒度 | ✅ **保持 33 条**，执行时按批归并 |

> **D11–D15 已裁决**（Batch D，详见 `production/sprints/batchd-design-review.md` §7，v1.1 全部 CLOSED）：D11 `surface` 仅驱动 foley/subtitle（不调制半径）· D12 DECOY 可疑度 floor `maxf(sus,THR_SUSP)` + 3.0s 每守卫冷却 · D13 熄灯 ramp 仅视觉（不影响遮蔽）· D14 静态 CI 扫描 + GUT runtime 合并计达成退出标准 #4 · D15 预算断言 WARN-ONLY，不接入 CI gate。

> QA 计划（quality-lead）按 SOP 在 Sprint 1 执行启动时产出（烟雾测试 + 回归 + 用例填充），不前置于此计划。

---

*Sprint 1 冲刺计划 v1.0 汇编完成，开放项已裁决。设计范围 `design/reviews/sprint1-design-scope.md`（文策渊）+ Story 拆分 `production/sprints/sprint1-stories.md`（程基岩）均落盘。裁决锁定后，主理人派程基岩启动 Batch A 实现。*
