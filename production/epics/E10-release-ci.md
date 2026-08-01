# Epic E10 · 发布 / CI / 质量门（Release / CI）

- **对应模块**：control-manifest §7（CI/构建期静态断言）+ asset-manifest §1.3/§6（资产校验）
- **层**：L1 / 管线
- **依赖**：全部 Epic（作为收口质量门）
- **DAG 优先级**：贯穿（每个 Sprint 收口），不占独立 DAG 位
- **MoSCoW**：**Must** ｜ **T 恤**：M
- **上游**：control-manifest §7；asset-manifest §1.3/§1.4/§1.5/§6；architecture §4 预算；ADR-004（UV2）；tests/README.md

## 目标
把「架构 §4 预算 + control-manifest 硬约束」变成可自动卡门的质量门：Godot headless 跑 GUT 冒烟测试 + 资产/预算静态断言，确保 lean 评审下核心节点不被漂移项悄悄突破；并最终产出 Steam 导出。

## 范围（In Scope）
- 测试脚手架（框架归工程，用例归 Phase 5 quality-lead）：`tests/README.md` + `tests/unit/*` + `tests/ci-note.md` + `.github/workflows/ci.yml` + `tests/ci/budget_assert.gd`。
- CI 静态断言（control-manifest §7）：动态光 >32、雾 >0.05 / ramp >0.12·>0.4s、缺 UV2、声环 >8、脉动 >2Hz。
- 性能预算验证 harness：守卫 8/16、锥 10Hz、射线峰值、draw call ≤400（asset-manifest §1.5）。
- Steam 构建/导出流程。

## 关键 Story 列表

### E10-S1 · 作为（工程）我要（Godot headless 跑 GUT 冒烟）以便（每次推送质量门绿灯）
**Sprint 0**：是
**验收**
- Given tests/README.md「GUT 作为 lean 默认；headless 命令 `godot --headless -s res://addons/gut/gut_cmdln.gd -gdir=res://tests/unit -gprefix=test_ -gsuffix=.gd -gexit`」。
- When CI 在 push/PR 触发。
- Then `godot --headless` 加载 GUT 并跑通 `tests/unit/test_step_commit.gd` + `test_vision_cone.gd` 冒烟桩，退出码 0；断言失败则非零。
- Then 断言：见 `tests/unit/test_step_commit.gd`（提交落点 / time_scale 0.25 / 冷却真实时间 / 暴露 1.2s）。
**关联**：tests/README.md；tests/ci-note.md；control-manifest §7（CI 卡质量门）；ADR-003/002（被测契约）。

### E10-S2 · 作为（工程）我要（跑 §7 预算静态断言）以便（漂移被告警）
**Sprint 0**：否（Sprint 1）
**验收**
- Given control-manifest §7「实时光 >32 → 警告(R-02)；volumetric_fog_density >0.05 或 ramp >0.12/>0.4s → 警告(R-04/R-05)；静态网格缺 UV2 → 警告(ADR-004)；声环 >8 → 警告(G-02)；暴露脉动 >2Hz → 警告(V-02)」。
- When `godot --headless -s res://tests/ci/budget_assert.gd` 运行。
- Then 上述任一命中则产告警记录（lean 不阻断构建，记「漂移」待主理人裁决）；断言脚本与 `tests/ci/budget_assert.gd` 一致。
**关联**：control-manifest §7；ADR-004（UV2）；R-/G-/V- 约束；asset-manifest §6。

### E10-S3 · 作为（发布）我要（产出 Steam 导出）以便（可分发）
**Sprint 0**：否（Sprint 2）
**验收**
- Given 概念「PC/Steam」；architecture §1「Godot --headless 导出」。
- When release 流程触发。
- Then 产出 Windows Steam 构建（x86_64，Vulkan）；含手柄映射与存档目录；回退预设 Compatibility（无 Vulkan 时关体雾/动态 GI，保 LightmapGI，ADR-001）。
**关联**：architecture §1；ADR-001（Compatibility 回退）；concept（PC/Steam）。

### E10-S4 · 作为（性能）我要（实测预算达标）以便（60fps@1080p GTX1060 档）
**Sprint 0**：否（Sprint 2 / 收尾）
**验收**
- Given architecture §4「同区活动守卫 ≤8/≤16、锥 10Hz、射线峰值 MVP≈160/s·Tier2≈480/s、动态点光 ≤12/≤32、雾 base≤0.05、声环 ≤8」；asset-manifest §1.5「draw call ≤400/frame」。
- When 在目标档跑性能剖析。
- Then 守卫 8/16、锥 10Hz、射线峰值、动态光 32、雾 0.05、声环 8、draw call ≤400 全部达标；超标项触发 E10-S2 断言告警。
**关联**：architecture §4；asset-manifest §1.5；control-manifest R-02/R-04/G-01/G-02/G-03；ADR-004。

## 依赖
全部 Epic（质量门贯穿）。被依赖：无（终端管线）。与 E01 协作：E01-S7 提供命名/UV2 校验基座，E10-S2 提供运行时断言。

## 整 Epic 验收标准
1. `godot --headless` GUT 冒烟在 CI 跑通且为质量门（失败阻断合并）。
2. §7 静态断言（光>32 / 雾 / UV2 / 声环>8 / 脉动>2Hz）可运行并产告警。
3. Steam 导出产出（Sprint 2）。
4. 性能预算 harness 实测达标（draw call ≤400、守卫 8/16、锥 10Hz 等）。

## 风险
- **R-CI-1**：断言误报/漏报 → 漂移漏网。缓解：断言清单与 control-manifest §7 逐条对齐，quality-lead 复审。
- **R-CI-2**：GUT 在 headless 加载失败（addon 未启用）。缓解：tests/README.md 明确 project.godot 启用片段 + addon 放置。
- **R-CI-3**：lean 下断言仅告警不阻断 → 漂移累积。缓解：告警入评审记录，主理人裁决（control-manifest §7 末段）。

## 与架构 + 控制清单勾稽
- 架构 §1（构建/CI：`Godot --headless` 导出 + 编辑器断言脚本，校验 UV2/动态光上限/声环上限）、§4（性能预算表，本 Epic 实测对象）。
- ADR-001（Compatibility 回退预设）、ADR-004（UV2 前置）。
- control-manifest §7（CI/构建期静态断言，逐条对应本 Epic 断言）、R-02/R-03/R-04/R-05/R-06/R-08（被测上限）、G-02/G-03（声环/锥）、V-02（脉动）、C-/X-（HUD 合规由 E09 落地、本门抽查）。
- asset-manifest §1.3（命名）/§1.4（UV2/压缩）/§1.5（draw call≤400、三角面、VRAM）/§6（CI 断言）。
- **用例缺口（交 Phase 5 quality-lead）**：`tests/unit/` 当前仅冒烟桩（step-commit + vision-cone）；完整用例（声音 FIFO≤8 计数、FSM 阈值、光 LOD 32 上限、HUD 对比度、a11y 开关生效）由 quality-lead 按各 Epic Story 验收标准填充——框架已就绪，见 `tests/README.md` 缺口表。
