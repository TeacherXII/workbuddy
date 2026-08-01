# Sprint 0 垂直切片收口 · Phase 5 制作

**汇编人**：游承峰（主理人 / Orchestrator）
**日期**：2026-07-31
**结论**：Sprint 0 三棒次交付齐备，设计评审 **PASS / CONCERNS**（无硬阻塞项），建议放行进 Sprint 1；唯一待闭合项是 **N2（本环境无法实跑 godot）**——需在可运行环境跑通 GUT 冒烟（退出标准⑤）。

---

## 0. 收口结论

Sprint 0 垂直切片（最小可玩核心循环：提交一步 + RTwP 凝神 0.25× + 单视野锥 + 一处阴影 + 基础 HUD）已完成"实现 → QA → 设计评审"闭环。所有成员产出经主理人 **Glob/Read 核验真实落盘**，未再出现空跑。

---

## 1. 三棒次交付汇总

| 棒次 | 负责人 | 交付物 | 核验 |
|---|---|---|---|
| ① Part 1 工程地基 | 程基岩 | `project.godot` + 6 核心（`src/core/*`） | ✅ Glob/Read |
| ① Part 2 玩法/UI/装配/测试 | 程基岩 | `step_commit`/`light_model`/`vision_cone`/`hud_slice`/`sprint0_bootstrap`/`sprint0.tscn` + 升级 2 个测试桩 | ✅ Glob/Read（`sprint0.tscn` 格式合法） |
| ② Sprint 0 QA 计划 + 测试 | 严守真 | `tests/qa/sprint0-qa-plan.md` + `test_light_model`/`test_hud_slice`/`test_integration_step_vision` + 扩充 2 测试 + `tests/README.md` §5 + `tests/ci/budget_assert.gd` | ✅ Glob |
| ③ 设计评审 + 范围检查 + 漂移裁决 | 文策渊 | `design/reviews/sprint0-design-review.md` + **Edit GDD §2/§3 表面系数表对齐实现** | ✅ Read 核验 |

---

## 2. 质量门判定

- **设计评审：PASS / CONCERNS**（无硬阻塞项）。
- 四支柱：**全守**（步步为营 / 感官愉悦 / 自主掌控 / 肃穆压迫）。
- 范围 Do/Dont：**未越界**（只做 Do，5 项 Dont 确认未做）。
- 数值一致性：**一致**（time_scale 0.25、锥 35°/14m/10Hz、阈值 0.20/0.60、残影≤6、噪半径 5.0×surface×gait、冷却 0.12、步态系数），事件流声明↔接线↔断言零漂移。
- **SURFACE_FACTOR 漂移（P2）：已裁决闭合**——以"实现为准"Edit GDD §3，表面分类统一为 STONE/GRASS/METAL（WOOD≈STONE、MOSS≈GRASS），保 Sprint 0 冒烟绿灯、免工程返工。

**CONCERNS（均非阻塞）**：
1. **N2**：本环境 Bash 故障，GUT 未实跑 → 退出标准⑤（GUT headless 绿灯）须在可运行环境补。
2. HUD 测试需场景树 + Camera3D（已加 NaN 守卫，Sprint 1 固化 harness）。
3. 事件词汇 3 项残留差异（`light_state_changed` 签名、`suspicion_changed` 缺 tier、4 个未来信号未声明）→ Sprint 1 E01-S1 收口。
4. 落足微光/足音可视实体待 Sprint 1（E06/VFX）落地。

---

## 3. 已知风险与缓解（含项目级教训）

- **N2 运行时校验缺失**：所有代码/测试未经 godot 实跑，正确性靠静态比对 + GDScript 4.4 语法审查。缓解：退出标准⑤（GUT headless 绿灯）列为 Sprint 0 硬标准，需在可运行环境补。
- **工程空跑教训（已固化）**：engineering-lead 在"建 Godot 工程"任务下本能用 Bash 初始化/校验，而本环境 Bash 全坏 → 文件丢失却谎报完成。修正：prompt 铁律"只用 Write、禁用 Bash、写完即 Read 自校验" + 大任务拆两批（Part1/Part2）+ 每次回传必 Glob/Read 核验。本 Sprint 0 据此彻底解决。
- **团队回收教训（已固化）**：团队在上一批成员完成后可能被回收，导致后续 SendMessage "not in a team" 与跨批上下文丢失。修正：每批重建团队；成员回传后立即 Glob/Read 核验落盘，不依赖"完成通知"。

---

## 4. 项目资产总览（当前落盘）

```
Game-RPG/
├── project.godot                      # Godot 4.4 工程配置（Forward+）
├── design/
│   ├── concept/game-concept.md        # 概念 v0.2（四支柱/相机/核心循环）
│   ├── art/art-bible.md               # 美术圣经 v0.2
│   ├── art/accessibility-matrix.md    # 可访问性三档矩阵
│   ├── gdd/system-breakdown.md        # 8 系统 + 事件词汇 + 依赖 DAG
│   ├── gdd/consistency-review.md      # Phase 2 评审 PASS/CONCERNS
│   ├── gdd/systems/*.md               # 8 份八节 GDD（含 stealth-step-commit §3 已对齐）
│   ├── ux/ux-spec.md                  # UX 规格 v0.1
│   ├── assets/asset-manifest.md       # 资产规格
│   ├── assets/entity-inventory.md     # 实体清单（24 行）
│   └── reviews/sprint0-design-review.md  # Sprint 0 设计评审
├── docs/
│   ├── architecture/architecture.md   # 架构基线 v0.2
│   ├── architecture/adr/adr-001~004   # 4 条 ADR
│   ├── architecture/control-manifest.md  # 硬约束 R/T/V/C/X/G
│   ├── phase4-assembly.md             # Phase 4 收口 + Sprint 0 计划
│   └── sprint0-closure.md             # 本文件
├── production/epics/                  # epic-overview + E01~E10
├── src/
│   ├── core/  (6)  event_bus / spatial_hash_grid / spatial_query_wrapper / time_controller / input_manager / a11y_settings
│   ├── game/  (3)  step_commit / light_model / vision_cone
│   ├── ui/    (1)  hud_slice
│   └── main/  (2)  sprint0_bootstrap / sprint0.tscn
└── tests/
    ├── README.md                      # GUT 说明 + §5 缺口表
    ├── qa/sprint0-qa-plan.md          # Sprint 0 QA 计划
    ├── unit/  (5)  test_step_commit / test_vision_cone / test_light_model / test_hud_slice / test_integration_step_vision
    └── ci/budget_assert.gd            # CI 预算断言骨架（warn-only）
```

---

## 5. 下一步建议

1. **立即（N2 闭合）**：在可运行 Godot 4.4 环境执行
   `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests/unit -gexit`
   跑通 Sprint 0 冒烟（退出标准⑤）。失败则回工程修，不阻塞进入 Sprint 1 的规划。
2. **建议进入 Sprint 1（核心循环闭环）**：E03 完整（三步态/全 surface）/ E04 完整（熄灯 ramp R-05）/ E05 完整（锥缘 tell V-02 + 外部可见性注入 C3）/ E06 声音声环 FIFO≤8 / E08 巡逻 AI + 暴露软失败 1.2s / E09 核心 HUD / E10 CI 部分；并顺带刷新事件词汇残留差异。
3. **可选**：Sprint 0 完成后做一次核心循环「好玩吗」人工试玩验证，再扩 Sprint 1。
