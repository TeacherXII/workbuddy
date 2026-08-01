---
status: Accepted
date: 2026-07-31
deciders: 程基岩
tags: [rtwp, time-scale, slow-mo, engine]
upstream: design/concept/game-concept.md §2 Mechanics (步进提交/凝神)、风险5；design/art/art-bible.md §8.4、§9.3
---

# ADR-003 时间模型：Engine.time_scale 实现 RTwP

## 状态
**Accepted（已采纳，Phase 2 基线）**

## 上下文
RTwP 需要：常态时间流动；按住「凝神」进慢放预览（世界减速、玩家仍实时读 / 规划）；松开提交下一步。风险5 明确「慢放用时间缩放而非额外模拟」。

## 决策
采用 **单一全局 `Engine.time_scale`** 驱动世界模拟：
- 常态 `time_scale = 1.0`；凝神 `0.1–0.3`（默认 0.25，用户 0.1–1.0 可调，下限 0.1 防物理不稳）。
- `time_scale` 自动缩放 `_process` / `_physics_process` 的 `delta`、`AnimationPlayer` / `Tween` / `AnimationTree` —— 步进动画、足迹残影预演、落足 Pose 冻结均随之减速 / 定格，无需双模拟。
- **玩家输入走实时事件**（`InputEvent`，不受 `time_scale` 影响）——慢放中玩家仍可规划、步进提交。
- **完全暂停**（`get_tree().paused = true` 或 `time_scale = 0`）仅用于菜单 / 设置，不作常规玩法。
- **音频单独处理**：`Engine.time_scale` 不自动变调音频。设计选择：凝神期间**不变调**（更轻、且避免光敏 / 眩晕），仅施加轻微全局 lowpass + ducking 增强「凝神」质感；如未来要 whoosh 慢音，对关键 `AudioStreamPlayer` 手动 `pitch_scale`，不全局。

## 备选
- **独立固定步模拟 + 渲染解耦**：拒绝——复杂度高、易与渲染 / 物理失同步，lean 范围不值。
- **逐系统手动 delta 缩放**：拒绝——各系统不一致，难维护。
- **回合制 / 纯暂停步进**：拒绝——破坏 RTwP 流动感与 Sensation 支柱。

## 后果
- **正向**：慢放近乎零额外成本（物理步更少 = 更省 CPU）；动画 / 残影天然减速。
- **负向 / 风险**：
  1. **音频不自动变调**（按设计接受，需显式 lowpass / ducking 接线）。
  2. **粒子需手动同步**：`GPUParticles3D` / `CPUParticles3D` 有独立 `.time_scale`，须在凝神时同步设置，否则尘埃 / 声环动画不与世界同速（control-manifest T-04）。
  3. **极低下限**：`time_scale` 远低于 0.1 时固定步物理有效步频下降，不建议 < 0.1（control-manifest T-02）。
  4. **输入实时**：玩法代码不得把输入读取放进受 `time_scale` 缩放的 process 逻辑里做「冷却」，否则慢放时冷却变慢——冷却计时须用真实时间。
- **联动**：时间缩放范围硬约束见 `control-manifest.md` T-01~T-04；步进提交实现见后续 GDD。
