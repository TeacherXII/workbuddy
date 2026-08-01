# Epic E02 · RTwP 凝神时间模型（rtwp-time-model）

- **对应 GDD**：`design/gdd/systems/rtwp-time-model.md`（GDD ②）
- **层**：L2 时间控制器（架构 §2）
- **依赖**：E01（TimeController 接口 / A11ySettings）
- **DAG 优先级**：P0（地基，其余系统均读 `Engine.time_scale`）
- **MoSCoW**：**Must** ｜ **T 恤**：M
- **上游**：概念 §2（凝神慢放）/§4（核心循环）；ADR-003；control-manifest §2（T-01~T-04）；art-bible §8.4/§9.3

## 目标
提供单一全局时间控制器，支撑「读—步」循环：常态世界流动，按住凝神进慢放预览（默认 0.25×），松开即提交。慢放近乎零额外成本（物理步更少=更省 CPU，ADR-003）。

## 范围（In Scope）
- `TimeController` L2 单例，经 `Engine.time_scale` 实施；模式 `FLOWING`/`FOCUS`/`PAUSED`。
- 缓动 ramp（≈0.15s，ease 非硬切 V-06）、信号 `time_scale_changed(old,new,mode)`。
- 真实时间冷却纪律、粒子 `.time_scale` 同步（T-04）、音频 lowpass+ducking（不变调）、STEP_PAUSE 可访问性替代。

## 关键 Story 列表

### E02-S1 · 作为（玩家）我要（按住凝神进入慢放、松开恢复）以便（在慢放下读场规划下一步）
**Sprint 0**：是
**验收**
- Given 常态 `time_scale=1.0`；凝神目标 `0.25`（可调区间 0.1–0.3，T-02），用户总范围 `0.1×–1.0×`（T-01），下限 0.1 防物理不稳。
- When 玩家按住凝神键（经 E01 InputManager，`InputEvent` 实时）→ `TimeController.enter_focus()`。
- Then `Engine.time_scale` 在 ≈0.15s 缓动内达 **0.25**，`mode=FOCUS`；松开 → 缓动回 1.0，`mode=FLOWING`。
- Then 断言：FOCUS 时 `time_scale` 落入 [0.1, 0.3] 且默认 ==0.25（见 `tests/unit/test_step_commit.gd::test_focus_enters_slowmo_at_0_25`）。
**关联**：ADR-003；control-manifest T-01/T-02/T-03；rtwp-time-model §2/§6。

### E02-S2 · 作为（系统）我要（发出 time_scale_changed 信号）以便（粒子/音频/HUD 订阅同步）
**Sprint 0**：是
**验收**
- Given rtwp-time-model §4「发出 time_scale_changed(old,new,mode)」。
- When `time_scale` 在 FLOWING↔FOCUS 间变化。
- Then `time_scale_changed` 携带 `(old, new, mode)` 发射，订阅方（E03 动画、E09 HUD、音频、粒子）收到。
**关联**：system-breakdown §2；rtwp-time-model §4。

### E02-S3 · 作为（程序员）我要（玩法冷却用真实时间）以便（慢放下冷却不变慢，手感正常）
**Sprint 0**：是
**验收**
- Given ADR-003 风险4「玩法冷却计时须用真实时间（wallclock），不得落入受缩放的 _process delta」。
- When E03 提交冷却 `COMMIT_COOLDOWN_RT=0.12s` 计时。
- Then 无论 `time_scale` 多少，冷却按真实时间推进（慢放下仍 0.12s 后可再次提交）。
- Then 断言：commit 后 tick 真实 0.13s → `can_commit()==true`（见 `tests/unit/test_step_commit.gd::test_commit_cooldown_uses_real_time_not_scaled`）。
**关联**：ADR-003 风险4；stealth-step-commit §2（COMMIT_COOLDOWN_RT）；control-manifest 无直接编号但属 ADR-003 后果。

### E02-S4 · 作为（程序员）我要（凝神时同步粒子 .time_scale）以便（尘埃/声环与世界同速）
**Sprint 0**：否（Sprint 1，配合 E03/E04/E05 VFX）
**验收**
- Given control-manifest T-04「凝神时同步 GPUParticles3D/CPUParticles3D.time_scale」。
- When 进入/退出 FOCUS。
- Then 所有活跃粒子 `time_scale = current_scale`（=0.25 进入 / 1.0 退出）。
**关联**：control-manifest T-04；ADR-003 风险2。

### E02-S5 · 作为（音频）我要（凝神期 lowpass+ducking 不变调）以便（避免光敏/眩晕）
**Sprint 0**：否（Sprint 1）
**验收**
- Given ADR-003「凝神期不变调（避免光敏/眩晕），仅全局 lowpass + ducking；关键 AudioStreamPlayer 不全局 pitch_scale」。
- When 进入 FOCUS。
- Then 音频总线挂 lowpass + ducking；无 pitch_scale 全局变调。
**关联**：ADR-003；art-bible §9.3。

### E02-S6 · 作为（可访问性玩家）我要（凝神改为完全冻结 STEP_PAUSE）以便（眩晕/低敏玩家可玩）
**Sprint 0**：否（Sprint 2，a11y 包）
**验收**
- Given rtwp-time-model §2「STEP_PAUSE：凝神键改为完全冻结（time_scale=0）而非慢放，属 FOCUS 子开关」；T-01/T-02。
- When 开启 a11y STEP_PAUSE 且按住凝神。
- Then `time_scale=0`（完全冻结），松开恢复 1.0；仍属 `TimeMode.FOCUS` 语义，不破坏循环。
**关联**：rtwp-time-model §2/§7；control-manifest T-01/T-03；core-hud-a11y §7。

### E02-S7 · 作为（玩家）我要（在设置菜单调凝神倍率 0.1–1.0 默认 0.25）以便（自定义慢放强度）
**Sprint 0**：否（Sprint 2）
**验收**
- Given control-manifest T-01（0.1–1.0）、T-02（默认 0.25，凝神区间钳 [0.1,0.3]）。
- When 玩家拖动时间缩放滑杆。
- Then `user_focus_scale` 钳制 [0.1, 0.3] 并写入 `A11ySettings`（经 E01-S6 持久化）；下次 FOCUS 用该值。
**关联**：control-manifest T-01/T-02；core-hud-a11y §7（T-01/T-02）。

## 依赖
E01（TimeController 由 E01 基座提供；A11ySettings 持久化经 E01-S6）。被依赖：E03（focus-release 提交 + 冷却真实时间）、E05/E06/E08（节流 tick 用真实时间，不随 time_scale）。

## 整 Epic 验收标准
1. FOCUS 默认 `time_scale=0.25`，区间钳 [0.1, 0.3]，用户总范围 [0.1, 1.0]；ramp≈0.15s ease。
2. `time_scale_changed(old,new,mode)` 在每次切换发射。
3. 玩法冷却用真实时间（ADR-003 风险4 无违反）。
4. 粒子 `.time_scale` 同步（T-04）；音频 lowpass+ducking 不变调。
5. STEP_PAUSE 与用户凝神倍率可调并持久化。

## 风险
- **R-时-1**：`time_scale` 远低于 0.1 时固定步物理有效步频下降 → 不稳。缓解：下限硬锁 0.1（T-02）。
- **R-时-2**：粒子未同步 → 尘埃/声环不与世界同速。缓解：T-04 显式同步（E02-S4）。
- **R-时-3**：冷却误用缩放 delta → 慢放手感异常。缓解：E02-S3 真实时间纪律 + `tests/` 断言。

## 与架构 + 控制清单勾稽
- 架构 §2（时间统一由 L2 时间控制器经 Engine.time_scale，玩法不得自管）、§4（凝神缩放 0.25）、§3.2（time_scale 自动缩放 process/AnimationPlayer/Tween）。
- ADR-003（单一全局 time_scale；输入实时；音频/粒子例外处理；下限 0.1）。
- control-manifest T-01（0.1–1.0）、T-02（0.25 默认/区间）、T-03（冻结仅菜单）、T-04（粒子同步）。
