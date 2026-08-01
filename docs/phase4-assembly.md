# Phase 4 预制作 · 汇编交付与首个冲刺计划

**项目**：《灰烬之步》ASHEN STEP（Godot 4.4 / PC-Steam / lean 评审 / 黑暗奇幻 RTwP 潜行 / 小而精）
**汇编人**：游承峰（主理人 / Orchestrator）
**日期**：2026-07-31
**上游**：Phase 1 概念(v0.2) · Phase 2 GDD(PASS/CONCERNS) · Phase 3 架构基线(风险5 PASS) + 可访问性三档

---

## 0. 阶段判定

Phase 3 质量门（风险 5：RTwP + 视野锥 + 声音传播 + 可疑度 FSM 性能）已 **PASS**，架构基线 + 可访问性分级就绪。
→ 进入 **Phase 4 预制作**，并经三路并发 + 串行补做完成。现汇编收口，建议放行至 **Phase 5 制作（Sprint 0 垂直切片）**。

---

## 1. 三路交付清单（成员产出，已落盘核验）

| 路 | 成员 | 交付物 | 状态 |
|---|---|---|---|
| UX 规格 | 文策渊 | `design/ux/ux-spec.md`（v0.1，8 章，四支柱无漂移） | ✅ 落盘核验 |
| 资产规格 | 林绘澄 | `design/assets/asset-manifest.md` + `design/assets/entity-inventory.md`（24 行实体清单） | ✅ 落盘 |
| Epic/Story + 测试脚手架 | 程基岩 | `production/epics/epic-overview.md` + `E01`–`E10`（10 份）+ `tests/` 脚手架（GUT + 2 冒烟桩 + CI 占位） | ✅ 落盘核验 |

> 注：UX 规格首轮因团队回收空跑，已在新团队 `game-rpg-studio-p4b` 重做并强制 Read 自校验落盘。资产与工程两路首次即落盘。

---

## 2. 一致性闭合（Phase 2 CONCERNS C1–C4 已归属）

Phase 2 评审的 4 项非阻塞 Concern 在 Phase 4 被明确指派到对应 Epic，无遗留：

| Concern | 内容 | 归属 Epic |
|---|---|---|
| C1 | 声环 FIFO ≤8 自毁纪律 | E06（sound-propagation） |
| C2 | Tier2 光 LOD ≤32 切换 | E04 + E10（cover-shadow + 发布/CI 预算断言） |
| C3 | 烟雾 visibility 注入通道 | E05 + E07（vision-cone + interactables） |
| C4 | 暴露软失败检查点粒度（SaveManager） | E08 + E01（patrol-ai + 工程基座） |

---

## 3. 质量门判定（Phase 4 → Phase 5）

**判定：PASS（lean，可放行）**，非阻塞项如下：

- **N1（测试缺口）**：当前 `tests/` 仅 2 个冒烟桩（覆盖 E02/E03/E05 核心契约）。声音 FIFO、FSM 阈值、掩体/熄灯、互动物件 charges、HUD 对比度、性能预算 harness 待 **Phase 5 由 quality-lead 填充**（`tests/README.md` §5 已列缺口表）。→ 不阻塞 Sprint 0（退出标准只需 GUT 冒烟 headless 绿灯）。
- **N2（环境限制）**：本环境 Bash 工具异常（所有命令 exit 1 无输出），无法实跑 `godot --headless` / `wc`。成员产出语法正确但未经实跑；**首轮真实 CI 跑通是 Sprint 0 退出硬标准之一**，需在可运行环境验证。
- **N3（纹理密度/UV2 流程）**：`Texel Density` 精确值与 LightmapGI bake/UV2 流程待程基岩与林绘澄 final（`art-bible §5.3` / `ADR-004`）。→ 不阻塞 Sprint 0（切片用 mock `get_light_level`）。

---

## 4. 首个冲刺计划 · Sprint 0 垂直切片

**目标**：用最小可玩核心循环验证「读—步」deliberate 手感是否成立（支柱一 步步为营 / 支柱二 感官愉悦），不追求完整度。

**切片 Epic 子集**（完整定义见 `production/epics/epic-overview.md` §3/§4）：
- E01（切片）：EventBus 全信号声明、SpatialHashGrid3D（cell=14m，ADR-002）、SpatialQueryWrapper（LOS 统一遮挡）、TimeController 接口、InputManager 最小（凝神+步态）、A11ySettings 持久化接口。
- E02（完整）：FOCUS↔FLOWING，`time_scale=0.25`（ramp 0.15s，T-02），`time_scale_changed` 信号，冷却用真实时间。
- E03（切片）：提交一步（SNEAK/WALK）+ aim_point 预演 + `player_step_committed`（noise_radius = 5.0×surface×gait）+ 落足微光/足音/残影(≤6)。
- E04（切片）：最小 `get_light_level`（mock 返回 [0,1]）+ 阈值 `L_DARK=0.20`/`L_BRIGHT=0.60` + 一处阴影池 mock。
- E05（切片）：单守卫单锥（half_angle 35° / range 14m，10Hz 错峰 G-03）+ `compute_visibility`（InCone×LOS×光影）+ `vision_stimulus`。
- E09（切片）：落点预演（ghost footprint + `#C8862F` 微光）+ 凝神态读出 + 可疑度占位条。

**退出标准（Exit Criteria）**：
1. FOCUS 中选 aim_point → 松开提交一步 → 角色走到落点并留微光/足音/残影。
2. 进入凝神 `time_scale` 切 **0.25**（断言 `tests/unit/test_step_commit.gd`）；输入在慢放下仍实时（ADR-003）。
3. 单守卫锥 10Hz：玩家在光池（L≥0.60）`vision_stimulus` 报 visibility≈1.0；暗处（L≤0.20）≈0（断言 `tests/unit/test_vision_cone.gd`）。
4. 基础 HUD 显示预演 + 凝神态 + 可疑度占位。
5. `tests/` GUT 冒烟在 `godot --headless` 下跑通（解决 N2 前为待验证项）。

**明确 Dont**：不做完整 FSM/暴露软失败流、声环 VFX/诱饵/烟雾/多守卫 A*、完整 a11y 面板、LightmapGI 实烘焙、Steam 导出。

---

## 5. 已知风险与缓解

| 风险 | 影响 | 缓解 |
|---|---|---|
| 团队上下文回收导致成员空跑（UX 首轮已发生） | 产出丢失、进度回退 | 重做时强制 Read 自校验落盘；后续每次成员回传后主理人立即 Glob/Read 核验再汇编 |
| 本环境 Bash 异常，无法实跑 godot/CI | 测试与构建未经实跑，N2 | Sprint 0 退出强约束包含可运行环境 headless 跑通；CI 草案已就位 |
| 并发 API 限流（429，Phase 2 曾触发） | 成员失败 | design+art 并发、engineering 单独串行；避免 design+engineering 同发 |
| Phase 2 CONCERNS C1–C4 未闭环 | 集成时回归 | 已在 §2 归属到具体 Epic，Sprint 排期内消化 |
| 文本缩放/色盲等 a11y 仅预留接口 | Sprint 2 才完整 | `A11ySettings` 接口在 E01 切片先落地，避免后期返工 |

---

## 6. 下一步建议

1. **进入 Phase 5 制作**：以 Sprint 0 垂直切片开局，按 `epic-overview.md` §3/§4 的 Epic 子集排期。
2. **每 Sprint 收口**：由 quality-lead 产 QA 计划与冒烟测试，design-strategist 做设计评审与范围检查，主理人回顾。
3. **首轮真实环境验证**：在可运行 Godot 的环境中跑通 `tests/` 冒烟 + CI，闭合 N2。
4. **可选垂直切片试玩**：Sprint 0 完成后做一次核心循环「好玩吗」人工验证，再扩到 Sprint 1 闭环。
