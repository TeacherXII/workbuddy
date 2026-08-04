# Sprint 1 · Batch C 设计就绪评审（AI + HUD 核心）

| 字段 | 值 |
| --- | --- |
| **阶段** | Phase 5 · Sprint 1 · Batch C（E08 巡逻 AI + E09 核心 HUD + E06-S5） |
| **文档版本** | v1.1（裁决闭合版；设计就绪评审，非实现） |
| **作者** | 文策渊（游戏策划与叙事设计师 / design-strategist） |
| **任务 ID** | BATCHC-DESIGN-01 |
| **评审强度** | lean（仅核心节点卡质量门） |
| **批次范围** | 12 条 Story：E08-S1/S2/S3/S4/S5/S6/S8 · E09-S2/S3/S4/S6 · E06-S5 |
| **上游依据** | `design/gdd/systems/patrol-ai.md` · `design/gdd/systems/core-hud-a11y.md` · `design/gdd/systems/sound-propagation.md` · `design/gdd/system-breakdown.md` §2 · `production/epics/E08-patrol-ai.md` · `production/epics/E09-core-hud-a11y.md` · `production/sprints/sprint1-stories.md` · `production/sprints/sprint1-plan.md` · `docs/architecture/control-manifest.md` · `docs/architecture/architecture.md` §4 · `design/reviews/sprint1-design-scope.md`（G1–G8 / D1–D4） · `design/art/art-bible.md` §2/§4.1/§8/§9 · `design/art/accessibility-matrix.md` · 现存代码 `src/**` 与 `tests/unit/**`（Batch A/B 已落盘） |
| **下游衔接** | 程基岩（engineering-lead，Batch C 实现）· 严守真（quality-lead，用例填充）· 林绘澄（art-lead，§2.7 色值口径）· 主理人（§7 裁决项） |

> **本文用途**：对 Batch C 的 12 条 Story 做**动手前**的设计就绪判定，闭合工程无法自行决定的 GDD 数值/语义/边界缺口，给出可直接抄写的常量与伪码、实现顺序拓扑、测试钩子清单、事件词汇一致性结论。
>
> **纪律**：本文**不写任何 `src/` 代码、不做 git 操作**。所有「工程可抄」段落是**规格**不是实现。凡涉及改动已锁 GDD 语义的，一律列入 §7 待裁决，不擅自定稿。

---

## 0. 总判定速览

| 项 | 结论 |
| --- | --- |
| **逐 Story 判定** | **PASS 2 · CONCERNS 10 · FAIL 0** |
| **硬阻塞** | **无**。10 项 CONCERNS 全部为「数值/语义/边界未定」，可由本文 §2 一次性闭合 |
| **须开工前闭合（CONCERNS-A）** | **7 项**：C1 声音结算口径 · C2 FSM 转换表与抖动 · C3 软失败 Sprint 1 边界 · C4 A* NavServer 缺席 · C5 tier 映射与信号值域 · C6 C-02 对比度载体口径 · C7 多守卫 HUD 显示策略 |
| **可边做边定（CONCERNS-B）** | **3 项**：C8 世界要素编排接口 · C9 `interactable_triggered` 签名收口前移 · C10 隐性接线（守卫位置回填 / 多守卫视野实例） |
| **四支柱** | ✅ 全守，无支柱漂移（§6.4） |
| **设计理论四红线** | ⚠️ **命中 2 项预警**：主导策略（RUN 零成本，仅在错误结算口径下发生，§2.1 已排除）· 认知过载（8 条并列可疑度条，§2.8 已收敛）。经本文闭合后 **均解除** |
| **事件词汇一致性** | ⚠️ **2 项漂移**：`guard_fsm_changed` 值域（String vs GuardState）· `interactable_triggered` 签名（Sprint 0 形态未收口）。均给出低成本收口方案（§5） |
| **范围纪律** | ✅ 未越界。E07 实体、a11y 完整包、守卫变体、完整 SaveManager 均**显式留 Sprint 2**，本文逐条锚定边界 |
| **计划口径偏移** | ⚠️ 本批相对 `sprint1-plan.md` §实现批次有 2 处调整：**E06-S5 从 Batch B 移入**（E06 侧已在 Batch B 完成，本批仅做 E08 消费侧）· **E09-S4 从 Batch D 前移**（连带把 `interactable_triggered` 签名收口一并前移，见 §2.10） |

> **与既有判定的一致性**：`sprint1-design-scope.md` 判 E08/E09 为 **READY**（缺口 G4/G5/G7/G8）。本文不推翻该判定——READY 指「可进 Story」，本文做的是「Story 可动手」这一更细的门。G4（SaveManager）/G7（FSM 边界）/G5（道具依赖 E07）/G8（a11y 边界）在本文分别由 §2.3 / §2.2 / §2.10 / §2.7 落到可执行规格。

---

## 1. 12 条 Story 就绪判定表

> 判定口径：**PASS** = 数值/语义/边界齐全，工程可直接动手；**CONCERNS** = 无硬阻塞但存在须先约定的缺口（列缺口号，闭合方案见 §2）；**FAIL** = 缺上游依据或与已锁契约冲突，须主理人裁决后方可动手。

| # | Story | 判定 | 严重度 | 缺口 | 一句话理由 |
| --- | --- | --- | --- | --- | --- |
| 1 | **E08-S1** 五态 FSM | **CONCERNS** | A | C2 | GDD 只给了**上行阈值**（25/60），未给完整转换表、下行路径与丢失目标判据；照字面实现会在 S≈25 抖动时每 tick 发 `guard_fsm_changed` → 信号风暴 |
| 2 | **E08-S2** 连续可疑度 25/60/10 | **CONCERNS** | A | C1 | KV/KS/decay(35/15/8) 已在 GDD §3 锁为常量 ✅，但**声音项是「脉冲」还是「速率」未定**——两种解释的手感差 40 倍，错选直接触发「主导策略」红线 |
| 3 | **E08-S3** 5–10Hz 节流决策 | **PASS** | — | — | `DECISION_HZ=10.0` 已锁、真实时间口径已由 ADR-002/003 定死、G-04 上限明确；仅补测试断言口径建议（§4） |
| 4 | **E08-S4** 暴露 1.2s 宽限软失败 | **CONCERNS** | A | C3 | `GRACE_RT=1.2s` 已锁 ✅，但依赖的 **E01-S5 SaveManager 在 `src/core/` 不存在且未排进 Sprint 1 任何 Story**；须先划定 Sprint 1 软失败边界 |
| 5 | **E08-S5** A* 仅状态转换缓存 | **CONCERNS** | A | C4 | G-05 语义明确 ✅，但依赖的 **E01-S8 NavServer 封装同样不存在且未排期**；须先定 seam 使 G-05 在 headless 可验证 |
| 6 | **E08-S6** 信号发射（tier + 4 信号） | **CONCERNS** | A | C5 | `tier` 由 value 映射的规则、`SusTier.SEARCH` 的来源、`guard_fsm_changed` 的值域（String vs GuardState）、`guard_transform_dirty` 的置脏阈值——**四项全缺** |
| 7 | **E08-S8** 姿态可读（非颜色） | **PASS** | — | — | art-bible §4.1 五态姿态齐全、一一对应 `GuardState`；测试为纯枚举断言，headless 安全 |
| 8 | **E09-S2** 可疑度条（C-02 ≥7:1） | **CONCERNS** | A | C6 / C7 | **实测证明主色板在暗面板上无法达 7:1**（`#C8862F`=5.7:1）；且 G-01 允许 8 守卫，「画几条」未定 |
| 9 | **E09-S3** 世界内要素可见性编排 | **CONCERNS** | B | C8 | 上游 VFX（E05-S7 锥 / E06-S3 环 / E03-S7 残影）已在 Batch A/B 落盘 ✅，但「E09 如何提亮而不重绘」缺统一接口约定 |
| 10 | **E09-S4** 道具/charges 显示（信号级） | **CONCERNS** | B | C9 | 确认**无 E07 实体依赖** ✅，但本 Story 从 Batch D 前移，连带把 `interactable_triggered` 签名收口一并前移；`charges` 的 payload 形状未定 |
| 11 | **E09-S6** 暴露 ALERT + 软重开 UI | **CONCERNS** | A | C6 / C3 | `#7A2E2E` 对暗面板**数学上最高只能到 2.26:1**，永远无法满足 C-02；软重开 UI 的 Sprint 1 边界同 C3 |
| 12 | **E06-S5** 声音按距离衰减提可疑度 | **CONCERNS** | B | C1 | **E06 侧已在 Batch B 完成**（`suspicion_from_distance` + 2 条测试，防御式写法已达标 ✅）；本批只剩 E08 消费侧，口径随 C1 一并闭合 |

**计数**：PASS **2** ｜ CONCERNS **10**（A 级 7 / B 级 3）｜ FAIL **0**。

---

## 2. 缺口闭合表（工程可直接抄）

> 本节每一项给出：**缺口描述 → 闭合结论 → 可抄常量/伪码 → 边缘情况**。凡标 ⚖️ 的是**改动已锁 GDD 语义**，须主理人在 §7 拍板后方可定稿；其余为「GDD 已隐含、本文只做显式化」，工程可直接执行。

### 2.1 【C1 · A 级】E08-S2 可疑度动力学 — 声音项结算口径 ⚖️

#### 缺口
GDD `patrol-ai` §2 写作微分式：
```
dS/dt = vision_vis × kV(35) + sound_in_range × kS(15) − (stimulus?0:decay(8))
```
但 `sound_emitted` 是**离散事件**（`sound-propagation` §2「离散声事件」），不是持续量。把它按 `dS/dt × dt` 结算还是按「事件即时加成」结算，GDD 未言明。**两种解释相差约 40 倍**。

#### 数值论证（决定性）
以 Batch B 已落盘常量为准：`GAIT_INTENSITY = {SNEAK 0.3, WALK 0.6, RUN 1.0}`（`sound_propagation.gd:25`）、`noise_radius = 5.0 × surface_factor × gait_factor`、`GAIT_PARAMS.step_duration = {SNEAK 0.55, WALK 0.38, RUN 0.24}`。守卫位于声圈**半程**（falloff = intensity × 0.5）：

| 步态 | 单步 falloff | 步频 | **速率口径**净增速 | **脉冲口径**净增速 | 速率口径到 25 | 脉冲口径到 25 |
| --- | --- | --- | --- | --- | --- | --- |
| SNEAK | 0.15 | 1.8/s | −6.6 pts/s | **−2.5 pts/s** | 永不 | **永不**（潜行安全 ✅） |
| WALK | 0.30 | 2.6/s | −5.1 pts/s | **+5.8 pts/s** | 永不 | **≈4.3s** |
| RUN | 0.50 | 4.2/s | −4.7 pts/s | **+26.6 pts/s** | **永不** | **≈0.94s**（→ALERT ≈2.3s） |

> 净增速已计入「stimulus tick 抑制衰减」：有声事件的 tick 不扣 decay，其余 tick 扣 `8 × 0.1`。

**结论**：
- **速率口径** ⇒ RUN 在守卫脚边全速奔跑也**永远不会被听见**（净 −4.7 pts/s）。声音轴彻底失效，诱饵机制失效（支柱三 自主掌控受损），且 **RUN 变成零成本最优解 → 直接命中「主导策略」设计红线**，并使 `sprint1-design-scope` §6 的风险 **R6 爆发**。
- **脉冲口径** ⇒ SNEAK 永不被听见（潜行是奖励）、WALK 需持续走动 ~4.3s、RUN ~0.94s 起疑 / ~2.3s 进 ALERT。**梯度清晰、三步态各有位置、R6 被数值自然抑制**，与 consistency-review 取舍1「RUN 是高成本 deliberate 选项」严丝合缝。

#### 闭合结论（已 CLOSED · D5 采纳脉冲口径）
**声音按事件脉冲结算，视觉按速率结算。两者单位不同，须在 GDD §3 显式标注。**

| 常量 | 值 | **单位** | 权威出处 |
| --- | --- | --- | --- |
| `KV` | **35.0** | **点 / 秒**（乘 `vision_vis∈[0,1]` 与 `dt`） | patrol-ai §3（已锁） |
| `KS` | **15.0** | **点 / 次声事件**（乘 `falloff∈[0,1]`，**不乘 dt**） | patrol-ai §3（值已锁，单位本文显式化） |
| `DECAY` | **8.0** | **点 / 秒**（乘 `dt`） | patrol-ai §3（已锁） |
| `THR_SUSP` / `THR_ALERT` / `THR_RETURN` | **25.0 / 60.0 / 10.0** | 点 | patrol-ai §3（已锁） |
| `DECISION_HZ` | **10.0** | Hz（真实时间） | patrol-ai §3 / G-04（已锁） |
| `TICK_DT` | **0.1** | 秒（= 1/DECISION_HZ） | 派生 |
| `STIM_EPS` | **0.001** | 无量纲 | **本文新增**（浮点判据，见边缘情况 E3） |
| `SUS_EMIT_EPS` | **0.5** | 点 | **本文新增**（信号节流，见 §2.5） |
| `MAX_CATCHUP_TICKS` | **3** | 次 | **本文新增**（防卡顿螺旋，见边缘情况 E5） |

#### 可抄伪码（单守卫，一次 tick 的完整结算顺序）
```gdscript
# 每帧调用；delta_real 必须是真实时间（不受 Engine.time_scale 影响，ADR-002/003）
func tick_real(delta_real: float) -> void:
    _accum += delta_real
    var n := 0
    while _accum >= TICK_DT and n < MAX_CATCHUP_TICKS:
        _decide(TICK_DT)
        _accum -= TICK_DT
        n += 1
    if n >= MAX_CATCHUP_TICKS:
        _accum = 0.0            # E5: 长卡顿后丢弃积压，不做时间补偿螺旋

func _decide(dt: float) -> void:
    # ① 采样本 tick 的两路刺激（由信号回调在 tick 间累积到 _pending_*）
    var vis: float   = _pending_vision        # [0,1]，vision_stimulus 的最新值
    var snd: float   = _pending_sound_max     # [0,1]，本 tick 内所有声事件 falloff 的 MAX（E2）
    var had_sound: bool = _pending_sound_count > 0

    # ② stimulus 判据：视觉或声音任一非零即抑制衰减（E3）
    var stimulus: bool = (vis > STIM_EPS) or had_sound

    # ③ 累积：视觉按速率、声音按脉冲
    var d: float = KV * vis * dt
    if had_sound:
        d += KS * snd                         # 不乘 dt —— 单位是「点/次」

    # ④ 衰减：与累积互斥，同一 tick 不会既加又减（E4）
    if not stimulus:
        d -= DECAY * dt

    # ⑤ 双端钳制（E1）
    suspicion = clampf(suspicion + d, 0.0, 100.0)

    # ⑥ FSM 转换（§2.2）→ ⑦ tier 计算与信号发射（§2.5）
    _step_fsm(vis, dt)
    _emit_if_changed()

    # ⑧ 清空本 tick 的脉冲缓冲
    _pending_sound_max = 0.0
    _pending_sound_count = 0
```

#### 边缘情况（≥3 类，须有测试覆盖）
| # | 情况 | 规定行为 | 理由 |
| --- | --- | --- | --- |
| **E1** | `S` 超出 `[0,100]` | **双端钳制** `clampf(S, 0.0, 100.0)`；上限 100 **截断不累积超额** | 若允许超 100 隐形累积，玩家断 LOS 后的「隐形惩罚时间」不可读，违反支柱一「读出还差多少被发现」 |
| **E2** | 同一 tick 内到达 **多个** `sound_emitted` | **取 falloff 的 max，不求和** | 求和会让「密集小声」优于「单次大声」，制造反直觉的刷分策略；`max` 语义 = 「守卫注意到最响的那个」 |
| **E3** | `vision_vis` 为 `1e-7` 级浮点噪声 | 用 `> STIM_EPS(0.001)` 判 stimulus，**不用 `> 0.0`** | 裸 `>0.0` 会让衰减因浮点残值永不启动，守卫「永远记仇」 |
| **E4** | 同一 tick 既有刺激又想衰减 | **互斥**：`stimulus == true` 时 `decay` 项恒为 0 | GDD 公式 `(stimulus?0:decay)` 的字面含义，本文只做显式化 |
| **E5** | 一帧 `delta_real` 达 0.5s（卡顿/断点） | 固定步长追赶，**上限 3 次**，超出丢弃积压 | 不追赶 → 慢放下 AI 变慢（违反 ADR-002/003）；无上限追赶 → 卡顿后一次性补 5 tick 造成可疑度突跳 |
| **E6** | `sound_emitted` 在两次 tick 之间到达 3 次 | 全部并入下一次 tick，按 E2 取 max，**只计一次脉冲** | 防止高频声源绕过 10Hz 节流（G-04） |

#### 派生时间预算表（供 playtest 校准 / QA 断言取值）
**累积侧**（`GRACE_RT=1.2s` 已含在末列）：

| 场景 | `vision_vis` | dS/dt | → 25 (SUSPICIOUS) | → 60 (ALERT) | → 软失败 |
| --- | --- | --- | --- | --- | --- |
| 全亮开阔 | 1.00 | +35.0 | **0.71s** | **1.71s** | **2.91s** |
| 掩体后（×0.6，`VIS_MULT_COVER`） | 0.60 | +21.0 | 1.19s | 2.86s | 4.06s |
| 半影 | 0.50 | +17.5 | 1.43s | 3.43s | 4.63s |
| 烟雾（×0.3，`VIS_MULT_SMOKE`） | 0.30 | +10.5 | 2.38s | 5.71s | 6.91s |
| 暗处 `L ≤ L_DARK(0.20)` | 0.00 | −8.0 | — | — | — |

**衰减侧**（断 LOS 后，`DECAY=8.0`）：

| 从 | 到 | 需时 |
| --- | --- | --- |
| 100 | 60（跌出 ALERT 带） | 5.00s |
| 60 | 25（跌出 SUSPICIOUS 带） | 4.375s |
| 60 | 10（进 RETURN） | **6.25s** |
| 100 | 0（完全遗忘） | 12.50s |

> **设计评注**：攻守比 `KV/DECAY = 4.4:1` —— 「露头 1 秒需躲 4.4 秒回本」。该梯度既惩罚鲁莽又给足补救窗口（支柱一）。经检查**不存在「快速闪烁露头」套利**：露 0.1s 得 +3.5 点，躲 0.44s 归零，净收益为零、净成本为时间。✅ 无主导策略。

---

### 2.2 【C2 · A 级】E08-S1 FSM 完整转换表与抖动防护

#### 缺口
`patrol-ai` §2 只给了 `SUSPICIOUS≥25 / ALERT≥60 / SEARCH=ALERT且丢失目标 / RETURN=S<10且回归巡逻`。**未定义**：下行路径、「丢失目标」的时间判据、SEARCH 退出条件、RETURN 退出条件。照字面实现，S 在 25.0 附近抖动会导致 `CALM↔SUSPICIOUS` 每 tick 翻转 → 8 守卫 × 10Hz = **80 次/秒 `guard_fsm_changed`**，同时姿态（E08-S8）疯狂切换 → 破坏支柱四「肃穆压迫」。

#### 闭合结论：**下行只经 RETURN**（无需引入额外滞后带常量）

| 起 | 止 | 条件 | 备注 |
| --- | --- | --- | --- |
| `CALM` | `SUSPICIOUS` | `S ≥ 25` | 上行 |
| `SUSPICIOUS` | `ALERT` | `S ≥ 60` | 上行；进入时触发 A*（§2.4） |
| `SUSPICIOUS` | `RETURN` | `S < 10` | **下行统一走 RETURN** |
| `ALERT` | `SEARCH` | `vision_vis ≤ STIM_EPS` **持续** `LOST_TARGET_RT` | 丢失目标；进入时触发 A* 去 `last_known`（§2.4） |
| `ALERT` | `RETURN` | 软失败触发（`exposure_timer ≥ 1.2s`） | 强制，见 §2.3 |
| `SEARCH` | `ALERT` | `vision_vis > STIM_EPS` | 重新捕获 |
| `SEARCH` | `RETURN` | `S < 10` | **靠 decay 自然超时**（60→10 ≈ 6.25s），不引入 `SEARCH_TIMEOUT` 常量 |
| `RETURN` | `CALM` | 归位完成 | Sprint 1 最小化：进入 RETURN 后经过 `RETURN_SETTLE_RT` 即视为归位 |
| `RETURN` | `SUSPICIOUS` | `S ≥ 25` | 归位途中被重新惊动，**允许打断** |
| 任意 | `RETURN` | 软失败 | 强制路径 |

**新增常量**（本文提出，值为设计建议）：

| 常量 | 值 | 单位 | 依据 |
| --- | --- | --- | --- |
| `LOST_TARGET_RT` | **0.5** | 秒（真实时间） | 短于 `GRACE_RT(1.2s)` 的一半——玩家断 LOS 后能明确看到守卫「转为搜寻」，是补救窗口的可读反馈（支柱一） |
| `RETURN_SETTLE_RT` | **1.0** | 秒（真实时间） | Sprint 1 SEARCH/RETURN 最小化（`sprint1-design-scope` R1）；Sprint 2 换成「到达巡逻锚点」的真实判据 |

#### 抖动防护三条纪律
1. **无逐级下行**：不存在 `ALERT→SUSPICIOUS→CALM`。任何下行只在 `S<10` 时一次性进 `RETURN`。25/60 只作上行阈值 ⇒ **结构性消除阈值抖动，无需 hysteresis 常量**。
2. **`guard_fsm_changed` 仅在 `old != new` 时发**。
3. **`suspicion_changed` 节流**：仅当 `abs(S − S_last_emitted) ≥ SUS_EMIT_EPS(0.5)` **或** `tier` 变化时发射。8 守卫 × 10Hz 全速广播 = 80 信号/s，节流后典型 < 15 信号/s。

#### 边缘情况
| # | 情况 | 规定行为 |
| --- | --- | --- |
| **E7** | 纯声音把 `S` 推过 60，但守卫**从未见过目标**（`last_known` 为空） | 进 `ALERT` 后因 `vision_vis ≤ EPS` 持续 0.5s **立即转 `SEARCH`**，`last_known` 取**最近一次声事件的 `origin`**（见 §2.6 last_known 写入优先级）。守卫不会「对着空气拔刀」 |
| **E8** | `CALM` 下 `S` 已是 0，继续衰减 | 由 `clampf` 兜底，**不发** `suspicion_changed`（被 `SUS_EMIT_EPS` 节流吃掉），FSM 无动作 |
| **E9** | 同一 tick 内 `S` 从 5 直接跳到 65（大脉冲 + 高可见度） | **允许跨级**：`CALM → ALERT` 一步到位，只发**一次** `guard_fsm_changed(CALM, ALERT)`，不补发中间态 |

---

### 2.3 【C3 · A 级】E08-S4 / E09-S6 软失败在 Sprint 1 的边界 ⚖️

#### 缺口（并含一项计划缺失）
`sprint1-stories` E08-S4 依赖「**E01-S5**（SaveManager 检查点）」、E09-S6 依赖「E08-S4、**E01-S5**」。经核查：

- `src/core/` 现有 `a11y_settings / event_bus / input_manager / spatial_hash_grid / spatial_query_wrapper / time_controller` —— **无 `save_manager.gd`**。
- **E01-S5 未出现在 `sprint1-stories.md` 的任何 Sprint 1 Story 中**（Sprint 1 的 E01 只有 S9 词汇收口，已在 Batch A 闭合）。

即：**Batch C 有两条 Story 依赖一个既未实现、也未排期的 L2 服务**。这正是 `sprint1-design-scope` §3 缺口 **G4** 与风险 **R7** 所预警的位置。

#### 闭合结论：**Sprint 1 只做「逻辑软失败契约 + 一个注入 seam」，不做任何存档 I/O**

**E08-S4 在 Sprint 1 的 In Scope（做）**
1. `ALERT` 且 `vision_vis > STIM_EPS` 时累加 `exposure_timer += dt`（真实时间）。
2. `exposure_timer ≥ GRACE_RT(1.2)` → 发 `exposure_detected(guard_id, target)`。**这是本 Story 唯一的对外契约。**
3. 发信号后 GuardBrain **自身内部**执行软失败复位：`suspicion = 0.0` · `exposure_timer = 0.0` · `fsm → RETURN` · `last_known = Vector3.ZERO`。
4. 调用注入的检查点回调 `_checkpoint_sink.call()`（Sprint 1 注入 **no-op / 测试计数桩**）。

**E08-S4 在 Sprint 1 的 Out of Scope（不做，做了即范围蔓延）**
- ❌ 任何 `SaveManager` / `ConfigFile` / `user://` 存档 I/O
- ❌ 玩家实体位置重生、世界状态回滚、道具/charges 还原
- ❌ 重开过场动画、淡入淡出、关卡重载

**E09-S6 在 Sprint 1 的边界**
- ✅ 收到 `exposure_detected` → 显示暴露 ALERT 覆盖层（配色/编码见 §2.7）
- ✅ 显示**静态**「软重开提示条」（文本 + 图标，`V-06` ease 淡入，禁硬切）
- ✅ 读 `A11ySettings.screen_shake`（已存在于 `a11y_settings.gd:15`，默认 `false`）决定是否屏震 —— **V-03 在本批即可断言达标**
- ❌ 不接 SaveManager、不做真实重生、不做重开确认交互

#### seam 规格（使 Sprint 2 接线为 O(1) 改动，零返工）
```gdscript
# GuardBrain 暴露一个 Callable 注入点，不引入任何新类、不依赖 L2 未实现服务
var _checkpoint_sink: Callable = Callable()      # 默认空 = no-op

func set_checkpoint_sink(sink: Callable) -> void:
    _checkpoint_sink = sink

func _on_soft_fail(target: Node) -> void:
    suspicion = 0.0
    exposure_timer = 0.0
    last_known = Vector3.ZERO
    _set_fsm(GuardState.RETURN)                  # 强制路径（§2.2）
    _bus.exposure_detected.emit(guard_id, target)
    if _checkpoint_sink.is_valid():
        _checkpoint_sink.call()                  # Sprint 2 在此接 SaveManager.restore_checkpoint()
```
- **Sprint 1 注入**：测试桩 `func(): _restore_count += 1`，断言「软失败恰好触发 1 次检查点请求」。
- **Sprint 2 注入**：`SaveManager.restore_checkpoint` —— 仅改一行注入代码，`GuardBrain` 本身不动。

> **架构正当性**：L3（GuardBrain）通过 `Callable` 依赖注入向上解耦，不直接引用 L2 未实现服务，符合 `architecture.md` §2 单向依赖。这不是权宜之计，而是正确分层。

---

### 2.4 【C4 · A 级】E08-S5 A* 与缺席的 NavServer

#### 缺口
E08-S5 依赖「**E01-S8**（NavServer 封装）」。`src/core/` 无 `nav_server.gd`，且 **E01-S8 同样未排进 Sprint 1 任何 Story**。若直接用 `NavigationAgent3D`，headless CI 下需要 `NavigationRegion3D` + 烘焙导航网格，`@test_astar_only_on_transition` 将**不可测**，`@ci:G-05` 形同虚设。

#### 闭合结论：**G-05 的可测内容是「触发时机 + 缓存契约」，与寻路后端无关 → 用 Provider seam**
```gdscript
# 路径提供者接口（GuardBrain 只依赖这个签名，不依赖 Navigation* 任何类型）
#   request_path(from: Vector3, to: Vector3) -> PackedVector3Array
var _path_provider: Callable = Callable()
var _cached_path: PackedVector3Array = PackedVector3Array()
var _path_dirty: bool = true

func _set_fsm(next: GuardState) -> void:
    if next == fsm: return
    var prev := fsm
    fsm = next
    # G-05: A* 仅在【状态转换】进入 ALERT / SEARCH 时触发一次
    if next == GuardState.ALERT or next == GuardState.SEARCH:
        _path_dirty = true
    _bus.guard_fsm_changed.emit(guard_id, _state_name(prev), _state_name(next))

func _ensure_path() -> void:
    if not _path_dirty: return                    # 缓存命中 —— 非逐帧
    if _path_provider.is_valid():
        _cached_path = _path_provider.call(global_pos, last_known)
    _path_dirty = false
```
- **Sprint 1 注入**：计数桩 `func(a, b): _astar_calls += 1; return PackedVector3Array([a, b])`。
- **Sprint 2 注入**：真实 `NavServer.request_path`（E01-S8）—— GuardBrain 不动。
- **G-05 的完整 headless 断言**（可直接抄进用例）：
  1. 进入 `ALERT` → `_astar_calls == 1`
  2. 随后连续 20 次 `tick_real` 保持 `ALERT` → `_astar_calls` **仍为 1**（缓存生效、非逐帧）
  3. `ALERT → SEARCH` → `_astar_calls == 2`
  4. 回落 `RETURN → CALM` 后再次进 `ALERT` → `_astar_calls == 3`

> **Sprint 1 边界声明**：本批**不做**真实寻路移动、不做导航网格烘焙、不做守卫位移动画。E08-S5 在 Sprint 1 的交付物是**「A* 请求的时机与缓存纪律」**，不是「守卫会走路」。

---

### 2.5 【C5 · A 级】E08-S6 tier 映射、信号值域、置脏阈值

#### C5-a · `tier` 如何由 `value` 映射（并与 `GuardState` 区分）

**`SusTier` ≠ `GuardState`，是两个语义不同的枚举，绝不可混用：**

| | `GuardState` | `SusTier` |
| --- | --- | --- |
| **成员** | `CALM, SUSPICIOUS, ALERT, SEARCH, RETURN`（**5**） | `CALM, SUSPICIOUS, ALERT, SEARCH`（**4**，无 RETURN） |
| **语义** | AI **行为**状态机 | HUD **显示带** |
| **驱动** | 阈值 + 目标丢失 + 软失败 | `value` 映射（`SEARCH` 除外） |
| **消费** | E08 自身行为 + E08-S8 姿态 | E09-S2 图标/亮度档 |
| **声明位置** | `GuardBrain`（L3） | **`EventBus`（L2）**，已存在 `event_bus.gd:16` ✅ |

**映射规则**（`system-breakdown` §2.3 明写「SEARCH 由 E08 FSM 在丢失目标后进入，**非连续阈值带成员**」⇒ 必须 FSM-aware）：
```gdscript
func compute_tier(s: float, state: GuardState) -> EventBus.SusTier:
    if state == GuardState.SEARCH:
        return EventBus.SusTier.SEARCH          # FSM 覆写（§2.3 明文）
    if s >= THR_ALERT:   return EventBus.SusTier.ALERT
    if s >= THR_SUSP:    return EventBus.SusTier.SUSPICIOUS
    return EventBus.SusTier.CALM
```
**`RETURN` 的 tier 归属（关键边缘情况 E10）**：`RETURN` 无对应 tier 成员。因进入 `RETURN` 的唯一常规条件是 `S < 10`，故按 value 映射必得 `SusTier.CALM`（眼睛图标）。⇒ **正确且无需特判**。唯一例外是软失败强制进 `RETURN`，但那一刻 `suspicion` 已被复位为 `0.0`，同样落在 `CALM`。✅ 自洽。

**HUD 图标对照**（供 E09-S2 直接使用）：

| `SusTier` | 图标 | value 区间 |
| --- | --- | --- |
| `CALM` | 眼（👁 轮廓） | `[0, 25)` |
| `SUSPICIOUS` | 问号（?） | `[25, 60)` |
| `ALERT` | 感叹号（!） | `[60, 100]` |
| `SEARCH` | 放大镜 | 由 FSM 覆写，与 value 无关 |

#### C5-b · `guard_fsm_changed` 值域漂移 ⚖️

| 出处 | 签名 |
| --- | --- |
| `system-breakdown.md` §2.2 | `guard_fsm_changed(guard_id:int, old:GuardState, new:GuardState)` |
| `sprint1-stories.md` §4 ③ | `guard_fsm_changed(guard_id:int, old:String, new:String)` |
| **已落盘** `src/core/event_bus.gd:35` | `signal guard_fsm_changed(guard_id: int, old: String, new: String)` |

两份权威文档不一致，实现随 Story 走了 `String`。

**推荐方案 R1（低风险，本文建议）**：**保持 `String`**，并做两件小事：
1. 在 `event_bus.gd` 补 `enum GuardState { CALM, SUSPICIOUS, ALERT, SEARCH, RETURN }` 作为**值域的唯一权威来源**；发射方一律用 `EventBus.GuardState.keys()[state]` 转字符串，杜绝手写字面量拼写漂移。
2. Edit `system-breakdown.md` §2.2 该行，注明「传输为 `GuardState` 的**键名字符串**」。

**理由**：
- `GuardState` 的行为语义属 L3（`GuardBrain`），而 EventBus 在 L2 —— **L2 不应依赖 L3 类型**（`architecture.md` §2 单向依赖）。把枚举提到 L2 作**词汇表共享类型**（与既有 `LightState` / `SusTier` 完全同构）是正确解，而传字符串则连枚举序号变更都不会破坏契约，**抗漂移性更强**。
- 改动量 = EventBus 新增 1 个 enum + 文档 1 行注释，**零回归**（Batch A CI Run #32 59/59 不受影响）。

**备选 R2（严格对齐 §2）**：改签名为 int enum。需同步改 `event_bus.gd` + `test_event_bus.gd::test_event_vocabulary_complete` 断言 + 所有连接方。风险低但非零，且会让已绿的 Batch A 产生回归面。**不推荐**。

→ 已 CLOSED · **D6**（主理人推翻评审 R1，改采 int enum 对齐）

#### C5-c · `guard_transform_dirty` 的置脏阈值（GDD 完全未给）
`system-breakdown` §2.1 写「守卫 transform 变化**超阈值**」，但**阈值数值缺失**。E05 无法确定何时重算。

| 常量 | 建议值 | 依据 |
| --- | --- | --- |
| `XFORM_POS_EPS` | **0.5 m** | 目标最远在 `RANGE=14m`，0.5m 侧移在该距离约合 2°，仅为 `EDGE_MARGIN_DEG(8°)` 预警带的 1/4 ⇒ 不会漏报锥缘 tell；且 0.5m ≪ `SpatialHashGrid3D.CELL(14.0)`，不会跨 cell 漏检 |
| `XFORM_YAW_EPS_DEG` | **5.0°** | 同为 `EDGE_MARGIN_DEG(8°)` 的 5/8，留足余量 |
| 节流频率 | **≤10Hz** | 检测直接挂在 FSM 决策 tick 上（`DECISION_HZ=10.0`），**天然满足 G-03**，无需额外计时器 |

```gdscript
func _maybe_mark_transform_dirty() -> void:
    var moved := global_pos.distance_to(_last_dirty_pos) >= XFORM_POS_EPS
    var turned := absf(rad_to_deg(angle_diff(yaw, _last_dirty_yaw))) >= XFORM_YAW_EPS_DEG
    if moved or turned:
        _last_dirty_pos = global_pos
        _last_dirty_yaw = yaw
        _bus.guard_transform_dirty.emit(guard_id)
```

#### C5-d · 四信号发射时机汇总（E08-S6 验收清单）

| 信号 | 发射时机 | 节流 | 消费方 |
| --- | --- | --- | --- |
| `suspicion_changed(guard_id, value, tier)` | tick 末 | `abs(ΔS) ≥ 0.5` **或** tier 变化 | E09-S2 |
| `guard_fsm_changed(guard_id, old, new)` | `_set_fsm` 内 | 仅 `old != new` | E09（姿态/调试）|
| `exposure_detected(guard_id, target)` | `exposure_timer ≥ 1.2s` | 每次软失败 **恰好 1 次** | E09-S6 + 失败流 |
| `guard_transform_dirty(guard_id)` | tick 内位姿超阈值 | `XFORM_POS_EPS` / `XFORM_YAW_EPS_DEG` | E05 视野重算 |

---

### 2.6 【C1 附属】E06-S5 距离衰减 — 越界与防御式公式（**已达标，本文仅确认 + 补口径**）

#### 现状核查（Batch B 已落盘）
`src/game/sound_propagation.gd:203`：
```gdscript
func suspicion_from_distance(intensity: float, dist: float, radius: float) -> float:
    if radius <= 0.0:
        return 0.0                      # ✅ 防除零（含负半径）
    var d: float = max(0.0, dist)       # ✅ 防负距离
    var factor: float = 1.0 - (d / radius)
    return max(0.0, intensity * factor) # ✅ dist ≥ radius -> 0（含 dist == radius 取 0）
```
测试 `test_suspicion_from_sound_distance` / `test_suspicion_from_sound_distance_zero_radius_safe` 已覆盖 `d=0 / d=R/2 / d=R / d=1.5R / R=0`。

**判定：团队点名的三项越界防护（`dist≥radius`→0、`radius=0` 防除零、intensity 单位）在 E06 侧已全部达标 ✅。** Batch C **不需要**重写这个函数。

#### 本文补充的口径（Batch C 消费侧须遵守）

| 项 | 规定 | 依据 |
| --- | --- | --- |
| **`intensity` 单位** | **无量纲 `[0,1]`**，由 gait 派生：`SNEAK 0.3 / WALK 0.6 / RUN 1.0` | `sound-propagation` §3 `intensity: float # 0..1`；`sound_propagation.gd:25 GAIT_INTENSITY`（已锁） |
| **`dist` / `radius` 单位** | **米（世界单位）** | `noise_radius = 5.0 × surface × gait`，单位米 |
| **`dist` 度量** | **3D 欧氏距离** `origin.distance_to(guard_pos)` | 与 `sound_propagation.gd:118` 的 in-radius 精筛口径**保持一致**，否则圈内判定与衰减值不自洽 |
| **返回值域** | `[0, intensity] ⊂ [0, 1]` | 由上式保证 |
| **结算口径** | **脉冲**：`S += KS(15) × falloff`，**不乘 dt** | §2.1 |
| **同 tick 多声源** | 取 **max** | §2.1 边缘情况 E2 |
| **`last_known` 写入优先级** | ① `vision_vis > STIM_EPS` → 写目标**真实位置**（优先）；② 无视觉但有声事件 → 写 `payload.origin`；③ 两者皆无 → **不写**（保留旧值） | GDD 未定义但 E08-S5 的 A* 目标点依赖它 ⇒ 必须显式化 |

#### 边缘情况
| # | 情况 | 规定行为 |
| --- | --- | --- |
| **E11** | 守卫恰在 `dist == radius` 边界 | 返回 **0**（闭区间外沿取 0）。与 `emit()` 的 `distance_to(gp) <= radius` 收录判据组合后，结果是「边界守卫被通知但贡献 0」—— **无害且行为确定**，不需改 `emit()` |
| **E12** | `radius = 0`（退化声事件） | 返回 0，`emit()` 的 grid 查询也返回空 ⇒ 全链路静默，不崩 |
| **E13** | 多层关卡下守卫与声源垂直高差大 | 3D 距离会因高差而衰减 —— MVP 单层关卡下 y 近似恒定，无影响。**Sprint 2 若引入多层，须改为「分层判定 + 水平距离」**，本文标记为已知限制 |

#### ⚠️ 平衡风险 B-1（Batch D 复验项，不阻塞本批）
DECOY 声圈 `radius ≈ 8m`（`sound-propagation` §2）。若 `intensity = 1.0`，守卫在半程处单次脉冲仅 `15 × 0.5 = 7.5` 点 —— **远不足 `THR_SUSP(25)`**，守卫不会前往调查，**诱饵机制失效**（损支柱三「诱饵=主动解法，克制唯一解」）。
建议在 E06-S4（Batch D）复验时采用：`source == DECOY` 的声事件**额外无条件写入 `last_known = origin`**（不加权），使守卫一旦因任何原因进入 `SUSPICIOUS/SEARCH` 即优先前往诱饵点。若 playtest 仍不足，再考虑 `KS_DECOY` 专属系数（Tier2 可调参数，**不在 Batch C 硬编码**）。

---

### 2.7 【C6 · A 级】E09-S2 / E09-S6 对比度实测口径 ⚖️ ★核心发现

#### 缺口
`control-manifest` C-02 要求「关键指示（可疑度/暴露）对比度 **≥7:1**」。但 art-bible §2 主色板 + §8.1 面板基调（`#1B1B1F` @70–85% 叠在 `#10141C` 之上）经**实测**：

**面板合成底色**：`#1B1B1F` @80% over `#10141C` = **`#191A1E`**（相对亮度 `L = 0.0104`）

| 前景色 | 用途 | vs 面板@70% | vs 面板@85% | C-01 (≥4.5) | **C-02 (≥7)** |
| --- | --- | --- | --- | --- | --- |
| `#DCE3EC` 亮文本 | 数值/图标 | **13.57:1** | **13.44:1** | ✅ | **✅** |
| `#9FB8C9` 冷白 | 次级/边界 | **8.50:1** | **8.42:1** | ✅ | **✅** |
| `#C8862F` 烛琥珀 | 强调/填充 | 5.77:1 | 5.71:1 | ✅ | **❌** |
| `#3E5C76` 阴影蓝 | 描边 | 2.50:1 | 2.48:1 | ❌ | ❌ |
| `#7A2E2E` 血锈 | **暴露危险色** | **1.89:1** | **1.87:1** | ❌ | **❌** |

**决定性事实**：`#7A2E2E` 的相对亮度为 `0.0629`。即便把背景压到**纯黑**（`L=0`），其对比度上限也只有 `(0.0629+0.05)/0.05 = **2.26:1**`。
⇒ **在这套暗色 UI 中，`#7A2E2E` 满足 C-02 ≥7:1 是数学上不可能的。** 这不是配色选得不好，是物理上无解。

同时 art-bible §2.4 立了红线：「**禁止引入色板外的新色相**」。⇒ 不能靠换个亮红色绕过。

#### 闭合结论：**C-02 的被测对象是「可读载体」，不是「语义色填充」**

这不是为了通过而放宽标准——**GDD 自己就是这么写的**：
- `core-hud-a11y` §5：「可疑度条**亮度递增 + 图标（眼/?/!）+ 数字**（C-02）」
- `patrol-ai` §7：「可疑度条：图标+数字+亮度递增，**颜色仅辅助**（C-02 ≥7:1，关键指示）」
- `control-manifest` C-05：「机制信息编码 = **亮度 + 形状 + 图标 三重**，不依赖单一色相」
- `control-manifest` C-07：「`#7A2E2E` **绝不单独使用**（必配形状/脉动/图标）」

**⇒ 语义色本就被 GDD 定义为「仅辅助」，承载可读性的是图标字形、数字文本、条边界描边。C-02 理应测这些载体。**

**正式口径裁决（供工程与 QA 共用）**：

| | **被 C-02 测量**（≥7:1，硬门） | **不被 C-02 测量**（辅助层） |
| --- | --- | --- |
| 元素 | 数值文本 · 图标字形 · 条边界描边 · 填充与轨道的**亮度边界** | 语义色**填充**（`#C8862F` 系 / `#7A2E2E`） |
| 取色 | **`#DCE3EC`（13.4:1）** 主用；`#9FB8C9`（8.4:1）次用 | 按 art-bible §2 原样，不改色相 |
| 附加约束 | — | 必配形状 + 图标 + 脉动（C-05/C-07 强制常开） |

**落地色值表（工程直接抄）**：

| 元素 | 色值 | 对面板 `#191A1E` 对比度 | 卡的门 |
| --- | --- | --- | --- |
| 可疑度**数值文本** | `#DCE3EC` | **13.4:1** | C-02 ✅ |
| tier **图标字形** | `#DCE3EC` | **13.4:1** | C-02 ✅ |
| 条**边界描边**（1px） | `#DCE3EC` | **13.4:1** | C-02 ✅ |
| 面板**外描边** | `#3E5C76` | 2.5:1 | 装饰，不卡门（art §8.1） |
| 条填充 · CALM 档 | `#7A5A24` | 2.71:1 | 辅助层 |
| 条填充 · SUSPICIOUS 档 | `#A8712A` | 4.14:1 | 辅助层 |
| 条填充 · ALERT 档 | `#E8A94A` | **8.34:1** | 辅助层（顺带达标）|
| 暴露覆盖层填充 | `#7A2E2E` | 1.87:1 | 辅助层，**必须**配 `#DCE3EC` 图标 + 形状 + ≤2Hz 脉动 |
| 暴露层**文本/图标** | `#DCE3EC` | **13.4:1** | C-02 ✅ |

> 三档填充均为 `#C8862F` 的**明度变体（同色相 H≈33°）**，未引入新色相，**不违反 art-bible §2.4**。三档亮度依次递增（`L` = 0.116 → 0.203 → 0.460），满足 GDD「亮度递增」要求，相邻档亮度比 ≈1.75× / 2.27×，色盲三类下仍可区分（靠亮度，C-04/C-05）。
> **D7 已由林绘澄签字稿 v1.0 CLOSED**：三档明度变体 `#7A5A24`/`#A8712A`/`#E8A94A` 作废，改用签字色板（`#D64545` 警报边框/图标 + `#7A2E2E` 仅低不透明填充 α≤0.35）。

#### 工程如何「实测」（headless 安全，不采样像素）
纯函数 + 预合成，**不依赖渲染**：
```gdscript
# 放在 HUD 或工具脚本；QA 直接对常量断言
static func _lin(c: float) -> float:
    return c / 12.92 if c <= 0.04045 else pow((c + 0.055) / 1.055, 2.4)

static func relative_luminance(c: Color) -> float:
    return 0.2126 * _lin(c.r) + 0.7152 * _lin(c.g) + 0.0722 * _lin(c.b)

static func wcag_contrast(fg: Color, bg: Color) -> float:
    var a := relative_luminance(fg)
    var b := relative_luminance(bg)
    var hi: float = maxf(a, b)
    var lo: float = minf(a, b)
    return (hi + 0.05) / (lo + 0.05)

# 面板半透明底色须先按 alpha 预合成，再参与计算（不做屏幕采样）
static func composite(fg: Color, bg: Color, alpha: float) -> Color:
    return Color(
        fg.r * alpha + bg.r * (1.0 - alpha),
        fg.g * alpha + bg.g * (1.0 - alpha),
        fg.b * alpha + bg.b * (1.0 - alpha))
```
**断言写法**（`@test_suspicion_bar_contrast`）：
```gdscript
var panel := HudSlice.composite(Color("#1B1B1F"), Color("#10141C"), 0.80)
assert_gt(HudSlice.wcag_contrast(Color("#DCE3EC"), panel), 7.0, "C-02: 数值文本 ≥7:1")
assert_gt(HudSlice.wcag_contrast(HudSlice.ICON_COLOR, panel), 7.0, "C-02: tier 图标 ≥7:1")
assert_gt(HudSlice.wcag_contrast(HudSlice.BODY_TEXT, panel), 4.5, "C-01: 正文 ≥4.5:1")
```
✅ 纯数值、无场景树、无 Camera3D、无像素读取 ⇒ headless CI 完全可跑。

#### C-06 / C-07 三重编码在本批的具体落点
`sprint1-design-scope` §1.7 已明确 **a11y 完整包（含 C-06 色盲模式开关）属 Sprint 2**；`accessibility-matrix` §2 第 3 行同时规定「色盲三重编码（亮度+形状+图标）」在 **Basic 档即为「强制(开)」**，第 4 行「色盲模式开关」在 Basic 档为「可用未默认」。两者**不矛盾**，Batch C 的落点因此非常清晰：

| 项 | Batch C | Sprint 2（E09-S5）|
| --- | --- | --- |
| **C-05/C-07 三重编码** | ✅ **常开、无开关**：亮度档 + 形状（条形/覆盖层轮廓）+ 图标（眼/?/!/放大镜） | 图标库可扩展 |
| **C-06 色盲替换色**（`#7A2E2E`→`#C8862F`）| ❌ **不做开关**；仅预留读取点 `A11ySettings.color_blind_mode`（字段已存在 `a11y_settings.gd:13`） | 接开关 + 着色器替换 |
| **V-02 脉动 ≤2Hz** | ✅ 常量 `EXPOSURE_PULSE_HZ = 2.0`（对齐 `vision_cone.gd:30 CONE_VFX_PULSE_HZ`），可断言 | — |
| **V-03 屏震** | ✅ 读 `A11ySettings.screen_shake`（默认 `false`），可断言默认关 | 幅度可调 |
| **V-06 转场 ease** | ✅ 暴露层 ease 淡入，禁硬切 | — |

> **设计纪律**：Batch C 交付的暴露 UI **必须在不开任何 a11y 开关的情况下就已色盲安全**。这正是 `accessibility-matrix` Basic 档的定义。开关是增强，不是达标前提。

---

### 2.8 【C7 · A 级】E09-S2 多守卫可疑度显示策略（认知过载红线）

#### 缺口
`core-hud-a11y` §2 写「可疑度（**贴近相关守卫 或 HUD 一角细条**）」—— 二选一未定。而 `G-01` 允许同区 **MVP ≤8 守卫**。若逐守卫各画一条 ⇒ 屏上最多 8 条可疑度条 + 道具槽 + 凝神态 + 落点预演 + 暴露层。**直接命中设计理论红线「认知过载」**，且违反 art-bible §8.1「极简、克制」与支柱四「肃穆压迫」（HUD 是「世界的低声注解」，不是仪表盘）。

#### 闭合结论：Sprint 1 **只画一条聚合条**

| 项 | 规定 |
| --- | --- |
| **条数** | **恰好 1 条**，固定于 HUD 一角 |
| **数据源** | 全体守卫中 `suspicion` **最高**的那一个（`argmax`） |
| **显示内容** | 该守卫的 `value`（数字）+ 其 `tier` 图标 + 对应亮度档填充 |
| **平局** | 取 `guard_id` 最小者（确定性，便于测试） |
| **全体 `S < SUS_EMIT_EPS`** | 整条**隐藏**（`visible = false`），HUD 归于沉寂 —— 支柱四 |
| **不做** | ❌ 逐守卫世界内 near-diegetic 细条（留 Sprint 2）· ❌ 守卫列表/小地图 · ❌ 多条并列 |

```gdscript
# HUD 侧维护 guard_id -> value/tier 的字典，每次 suspicion_changed 更新后重算 argmax
func _on_suspicion_changed(guard_id: int, value: float, tier: int) -> void:
    _suspicion_by_guard[guard_id] = {"value": value, "tier": tier}
    _refresh_top_guard()        # argmax by value, tie-break by smallest guard_id
```

#### ⚠️ 附带发现：现有 HUD 存在**双写冲突**，E09-S2 必须一并修掉
`src/ui/hud_slice.gd` 当前有**两个**处理器同时写同一个 `_suspicion` 进度条：
```gdscript
func _on_vision_stimulus(_g, _t, visibility): _suspicion.value = clampf(visibility * 100.0, 0, 100)  # ← Sprint 0 占位
func _on_suspicion_changed(_g, value, _tier):  _suspicion.value = clampf(value, 0, 100)               # ← 真实数据源
```
Sprint 0 时 E08 不存在，用 `vision_stimulus` 临时驱动是合理的。但 **Batch C 一旦让 GuardBrain 开始发 `suspicion_changed`，两路会以 10Hz 互相覆写** —— 可疑度条会在「瞬时可见度 ×100」与「累积可疑度」之间**高频闪烁**，玩家完全无法读数，直接摧毁 E09-S2 的核心价值。

**E09-S2 的必做动作**：**移除** `_on_vision_stimulus` 对可疑度条的直写（连同 `_bus.vision_stimulus` 的连接，若无其他用途），使 `suspicion_changed` 成为**唯一数据源**。
**回归风险**：现有 `test_hud_slice.gd::test_suspicion_bar_updates_on_vision_stimulus`（第 74 行）断言的正是这条即将被移除的旧行为 ⇒ **该用例须由 E09-S2 改写为 `suspicion_changed` 驱动**，否则 Batch C 一上线 CI 即红。**请 quality-lead 与 engineering-lead 同步此项。**

---

### 2.9 【C8 · B 级】E09-S3 世界内要素编排接口

#### 缺口
验收要求「凝神压暗时**提亮**可读要素」，而 GDD §2 又要求「本系统只编排/**不重绘**」。上游 VFX 已在 Batch A/B 落盘（`vision_cone.attach_cone_vfx` / `sound_propagation.request_ring` / `footfall_vfx.gd`），但**均未暴露任何「可读性提升」入口** —— E09 无从下手，除非越界直接改各系统的 material。

#### 闭合结论：约定一个 3 行的统一接口，各绘制系统各实现一次
```gdscript
# 约定（非新类、非继承，鸭子类型即可）：
#   func set_readability_boost(on: bool) -> void
# 语义：on=true 时把该系统的世界内要素提到「凝神可读档」，false 回常态。
# 各系统内部自行决定怎么提（锥 -> alpha 提到 CONE_VFX_ALPHA_MAX；环 -> alpha 提升；残影 -> 延长淡出）。
# E09 只调这个方法，绝不触碰对方的 material/shader —— 满足「只编排不重绘」。
```
| 系统 | 落点 | 建议实现 |
| --- | --- | --- |
| E05 锥（`vision_cone.gd`） | 已有 `CONE_VFX_ALPHA_MIN(0.06)` / `MAX(0.30)` | boost 时锁定到 `MAX`，常态回脉动区间 |
| E06 环（`sound_propagation.gd`） | 已有 `RING_COLOR` | boost 时提 alpha 一档 |
| E03 残影（`footfall_vfx.gd`） | 已有 ghost trail | boost 时延长淡出时长 |

**E09 侧**：注册一个 `Array[Object]` 的编排清单，`time_scale_changed(mode == "FOCUS")` 时对全体调 `set_readability_boost(true)`，退出 FOCUS 时 `false`。
**测试口径**（headless 安全）：用 `Object` 桩记录 `boost_calls`，断言「进 FOCUS → 全体收到 `true`；出 FOCUS → 全体收到 `false`」，不断言任何像素。

> Batch C 的实际改动量 = E09 新增编排清单 + 三个系统各加一个 3 行方法。**不改任何绘制逻辑**，范围可控。

---

### 2.10 【C9 · B 级】E09-S4 信号级边界与签名收口前移

#### 确认：**本批无 E07 实体依赖** ✅
- `sprint1-stories` §0 明写「E07 实体（可投诱饵/互动物件）属 Sprint 2；Sprint 1 可消费信号并渲染占位」。
- 代码核查：`src/**` 中**没有任何 `interactable_triggered` 的发射方**（仅 `event_bus.gd` 声明 + `test_event_bus.gd` 测试桩发射）。
- ⇒ E09-S4 完全靠测试桩驱动，**无实体阻塞**。判定成立。

#### 但有一项被前移的连带工作 ⚖️
`docs/sprint1-batchA-impl.md` §4 明确记录：`decoy_landed` / `interactable_triggered` 维持 Sprint 0 形态，「按计划由 **E06-S4 / E09-S4（Batch D）** 收口」。
现 **E09-S4 被前移到 Batch C** ⇒ `interactable_triggered` 的签名收口**一并前移到本批**。

| | 现状 `event_bus.gd:37` | `system-breakdown` §2.2 目标 |
| --- | --- | --- |
| 签名 | `interactable_triggered(id: int, kind: String)` | `interactable_triggered(obj_id:int, type:InteractableType, payload)` |

**建议：在 Batch C 一并收口（成本极低，且不收口就会二次漂移）**
1. `event_bus.gd` 补 `enum InteractableType { DECOY, LIGHT_TOGGLE, TRAP, SMOKE }`（取自 `interactables` §3，四成员已锁）。
2. 签名改为 `interactable_triggered(obj_id: int, type: InteractableType, payload: Dictionary)`。
3. `test_event_bus.gd:67` 的 emit 桩同步（1 行）。
4. **改动面极小**：无生产发射方，只有 1 处测试桩 + 新增 HUD 消费方。

**理由**：若不收口，E09-S4 的 HUD 只能拿 `kind: String` 猜类型再手工映射图标 —— 那正是 E01-S9「无拼写漂移」要根除的东西，且 Sprint 2 接真实 E07 时必然返工两次。
→ 已 CLOSED · **D8**（本批收口 `interactable_triggered` 为 `(obj_id:int, type:InteractableType, payload:Dictionary)`）

#### `payload` 形状（GDD 未定义，本文提出最小集）
```gdscript
# Sprint 1 只需 charges 一个字段即可满足 E09-S4「显示 InteractableType + charges」
payload = { "charges": int }        # >= 0；0 表示耗尽（HUD 置灰但仍显示，不隐藏）
```
`interactables` §3 的 `charges: int`（MVP 每类 2–3 发）是唯一来源。Sprint 2 若需补 `pos` / `cooldown`，按 Dictionary 追加即可，**不破坏本批契约**。

#### E09-S4 显示规格（对齐 C-05 非颜色 / X-01 文本缩放）
| 元素 | 规定 |
| --- | --- |
| 类型 | **图标 + 文字标签**（`DECOY`/`LIGHT`/`TRAP`/`SMOKE`），**形状编码，不靠色相** |
| charges | 阿拉伯数字，色 `#DCE3EC`（13.4:1，过 C-01 且顺带过 C-02） |
| `charges == 0` | 图标降至 40% alpha + 数字保持全亮 —— **靠 alpha 与数字双编码**，不用颜色表达「不可用」 |
| 无道具 | 整槽隐藏 |
| X-01 | 文本节点用 `Label` + theme font size 变量，**不写死像素**，为 Sprint 2 的 100–150% 缩放预留 |

---

### 2.11 【C10 · B 级】三项「不在任何 Story 验收里」的隐性接线任务 ⚠️

这三项若漏做，**单元测试仍会全绿，但集成层静默失效**。必须写进 Batch C 的工程清单。

| # | 任务 | 证据 | 漏做后果 |
| --- | --- | --- | --- |
| **W1** | **GuardBrain 必须回填守卫位置到 E06** | `sound_propagation.gd:44-47` 注释原文：「The guard/AI system populates and updates this on `guard_transform_dirty` (**Batch C**); Batch B exposes the API and tests it. **Without it, `emit()` cannot distance-filter.**」 | `_guard_positions` 恒空 ⇒ `emit()` 的 `target_guard_ids` 恒空 ⇒ **E06-S5 全链路静默失效**，而 `test_sound_propagation` 因直接注入位置仍全绿 |
| **W2** | **多守卫 ↔ 多 VisionCone 实例的持有关系** | `vision_cone.gd:72 set_observer(pos, forward)` 是**单观察者**模型 | G-01 允许 8 守卫，但谁创建/驱动 8 个 `VisionCone`、`guard_id` 如何与实例对应，无 Story 覆盖 ⇒ 多守卫场景下视野只有 1 个生效 |
| **W3** | **`guard_transform_dirty` → E05 重算 → E06 位置更新 的三方闭环** | `patrol-ai` §4 只说「→③ 视野重算」，未提 ④ | 守卫移动后声音距离用旧位置计算 |

**建议接线**（GuardBrain 内，一处搞定 W1 + W3）：
```gdscript
func _maybe_mark_transform_dirty() -> void:
    if moved or turned:
        _bus.guard_transform_dirty.emit(guard_id)     # → E05 视野重算
        _sound.update_guard(guard_id, global_pos)     # → E06 距离精筛（W1，API 已就绪）
```
**W2 归属建议**：由 Batch C 的 `GuardBrain` **持有**自己的 `VisionCone` 实例并在构造时 `set_observer`，`guard_id` 与实例 1:1。这是最小改动，且与「守卫变体经参数覆盖」（Tier2）的架构方向一致。

---

## 3. 批内实现顺序（依赖拓扑 + 可并行项）

### 3.1 拓扑图

```
【前置 · 已在 Batch A/B 落盘 ✅】
  E01-S9 事件词汇  ·  E05-S5/S6/S7 视野完整  ·  E06-S1/S2/S3 声音  ·  E04 光影  ·  E03 步进
  E06-S5(E06 侧)  suspicion_from_distance() + 2 测试   ← 本批不重做
                              │
╔═════════════════════════════╪══════════════════════════════════════════╗
║  Batch C                    ▼                                          ║
║                                                                        ║
║  ── 阶段 1（串行地基，必须最先）─────────────────────────────────      ║
║   ① E08-S1  五态 FSM 骨架        [闭合 C2 后开工]                      ║
║        │  产出：GuardState 枚举 + _set_fsm + 转换表                    ║
║        ▼                                                               ║
║   ② E08-S2  连续可疑度 25/60/10  [闭合 C1 后开工] ★批内最关键          ║
║        │  产出：tick_real/_decide 结算核 + clamp + stimulus 判据       ║
║        │                                                               ║
║  ── 阶段 2（三路并行，均只依赖 ①②）──────────────────────────────     ║
║        ├──────────────┬──────────────┬───────────────┐                ║
║        ▼              ▼              ▼               ▼                ║
║   ③ E08-S3       ④ E08-S4       ⑤ E08-S5       ⑫ E06-S5(E08 侧)      ║
║     10Hz 节流      1.2s 软失败     A* seam         声脉冲累加          ║
║     [PASS]         [闭合 C3]       [闭合 C4]       [随 C1]             ║
║        │              │              │               │                ║
║        └──────────────┴──────┬───────┴───────────────┘                ║
║                              ▼                                         ║
║  ── 阶段 3（信号出口，依赖 ①②④）─────────────────────────────────     ║
║   ⑥ E08-S6  四信号发射 + tier    [闭合 C5 后开工]                      ║
║        │  ★ HUD 的唯一数据源；含 W1/W3 接线                            ║
║        │                                                               ║
║        ├──── ⑦ E08-S8  姿态可读  [PASS，纯枚举，可提前到阶段 2 并行]   ║
║        │                                                               ║
║  ── 阶段 4（HUD 消费，依赖 ⑥）───────────────────────────────────      ║
║        ├──────────────┬──────────────┐                                ║
║        ▼              ▼              ▼                                ║
║   ⑧ E09-S2       ⑪ E09-S6       ⑨ E09-S3                             ║
║     可疑度条        暴露 UI         世界编排                           ║
║     [闭合C6/C7]    [闭合C6/C3]     [闭合 C8]                           ║
║     ★含双写冲突修复                 ▲ 只依赖 Batch A/B，可提前         ║
║                                                                        ║
║  ── 全程独立（信号级，任意时刻可插入）──────────────────────────       ║
║   ⑩ E09-S4  道具/charges  [闭合 C9]   ← 与 E08 零耦合                 ║
╚════════════════════════════════════════════════════════════════════════╝
                              │
                              ▼
              批末冒烟：test_patrol_ai + test_hud_slice 全绿
```

### 3.2 并行度与关键路径

| 阶段 | Story | 可并行？ | 说明 |
| --- | --- | --- | --- |
| 1 | E08-S1 → E08-S2 | **串行** | S2 的结算核写在 S1 的 FSM 骨架里；顺序颠倒会返工 |
| 2 | E08-S3 / S4 / S5 / E06-S5 / **E08-S8** | **4–5 路并行** | 互不依赖；E08-S8 是纯枚举，可从阶段 3 提前到此并行 |
| 3 | E08-S6 | **串行汇聚** | 必须等 S1/S2/S4 定稿（tier 与 exposure 都要发信号） |
| 4 | E09-S2 / S6 / S3 | **3 路并行** | 三者互不依赖；**E09-S3 只依赖 Batch A/B，可与阶段 1 同时起步** |
| 全程 | E09-S4 | **完全独立** | 与 E08 零耦合，任何时候插入 |

**关键路径**：`E08-S1 → E08-S2 → E08-S6 → E09-S2/S6`（**4 跳**）。其余 8 条均可挂在旁路并行。
**最早可起步项（不必等任何闭合）**：**E09-S3**（C8 为 B 级，接口约定 3 行即可定）、**E08-S8**（PASS）。建议这两条先行，为关键路径腾出并行带宽。

### 3.3 批内冒烟检查点
| 检查点 | 时机 | 内容 |
| --- | --- | --- |
| **CP-1** | 阶段 1 完成 | `test_patrol_ai.gd` 的 FSM + 阈值用例全绿；手工验证 S 在 25/60 附近**不抖动**（C2 已闭合的直接证据）|
| **CP-2** | 阶段 3 完成 | 四信号全部可 `emit`/`connect`；`test_event_bus.gd` 不回归 |
| **CP-3** | 阶段 4 完成 | `test_hud_slice.gd` 全绿（**含被改写的 `test_suspicion_bar_updates_*`**，见 §2.8）|
| **CP-4** | 批末 | `test_patrol_ai` + `test_hud_slice` 全绿 + 既有 4 个测试文件零回归（对齐 `sprint1-plan` 批间冒烟口径）|

---

## 4. 测试钩子清单（供 quality-lead / engineering-lead 直接使用）

> 来源：`sprint1-stories.md` 各 Story「退出钩子」栏，逐条核对后补全「断言要点」与「新增/改写」标记。
> **约定**：`@ci:*` 类硬约束在本批**一律落为 GUT 单测断言**（headless 可跑）；`tests/ci/budget_assert.gd` 的扩展属 **E10-S2（Batch D）**，Batch C **不碰 CI 脚本**，以免造成 Batch D 返工。

### 4.1 主表

| # | Story | 测试文件 | 钩子名 | 断言要点 | 状态 |
| --- | --- | --- | --- | --- | --- |
| 1 | E08-S1 | `tests/unit/test_patrol_ai.gd` | `test_fsm_transitions` | 按 §2.2 转换表逐条：CALM→SUSP@25 · SUSP→ALERT@60 · SUSP→RETURN@<10 · ALERT→SEARCH@丢失 0.5s · SEARCH→ALERT@重捕 · RETURN→CALM@1.0s · **S 在 24.9↔25.1 抖动 20 次，`guard_fsm_changed` 发射 ≤2 次**（抖动防护） | **新建文件** |
| 2 | E08-S2 | `test_patrol_ai.gd` | `test_suspicion_thresholds` | `vis=1.0` 时 0.71s 达 25 / 1.71s 达 60（±1 tick）· 衰减 8/s · **`clampf` 上限 100 不超额**（喂 200 点后断 LOS，6.25s 内必回 10）· `S≥0` 下限 | **新建** |
| 3 | E08-S2 | `test_patrol_ai.gd` | `test_suspicion_stimulus_suppresses_decay` | 有 `vis>EPS` 的 tick **不扣 decay**；`vis=1e-7` 时**仍扣**（`STIM_EPS` 判据，边缘 E3） | **新建**（本文建议补） |
| 4 | E08-S3 | `test_patrol_ai.gd` | `test_fsm_tick_le_10hz` ｜ `@ci:G-04` | 注入 2.0s 真实时间 → `decision_count ∈ [10, 20]`（5–10Hz 区间）· **`Engine.time_scale = 0.25` 下计数不变**（真实时间口径，T-02/ADR-003） | **新建** |
| 5 | E08-S4 | `tests/unit/test_step_commit.gd` | `test_exposure_grace_1_2s` | **把现有 `ExposureGuardStub` 换成真 `GuardBrain`**：ALERT+可见 1.0s **不触发**、1.2s **触发**；宽限期内断 LOS → `exposure_timer` 回落可自救；软失败后 `suspicion==0` 且 `fsm==RETURN` | **改写**（现名 `test_exposure_grace_1_2s_triggers_soft_fail`，第 124 行）|
| 6 | E08-S4 | `test_patrol_ai.gd` | `test_soft_fail_invokes_checkpoint_sink_once` | 注入计数 `Callable`，断言软失败**恰好调用 1 次**；未注入时不崩（§2.3 seam） | **新建**（本文建议补） |
| 7 | E08-S5 | `test_patrol_ai.gd` | `test_astar_only_on_transition` ｜ `@ci:G-05` | 按 §2.4 四步：进 ALERT=1 · 保持 20 tick 仍=1 · 转 SEARCH=2 · 回落再进 ALERT=3 | **新建** |
| 8 | E08-S6 | `test_patrol_ai.gd` | `test_suspicion_changed_carries_tier` | **验证 tier 值本身正确**：24.9→CALM · 25.0→SUSPICIOUS · 59.9→SUSPICIOUS · 60.0→ALERT · `fsm==SEARCH` 时**覆写**为 SEARCH（§2.5）· RETURN 态下 tier==CALM（边缘 E10） | **新建** ⚠️ 见 §4.2 重名警告 |
| 9 | E08-S6 | `test_patrol_ai.gd` | `test_guard_signals_emitted` | 四信号全覆盖：`guard_fsm_changed` 仅 `old!=new` 发 · `suspicion_changed` 受 `SUS_EMIT_EPS(0.5)` 节流 · `exposure_detected` 每次软失败恰 1 次 · `guard_transform_dirty` 按 0.5m/5° 阈值发 | **新建** |
| 10 | E08-S6 | `test_patrol_ai.gd` | `test_guard_position_synced_to_sound_system` | **W1 接线**：守卫移动超阈值后，`SoundPropagation._guard_positions[guard_id]` 已更新（防静默失效，§2.11） | **新建**（本文建议补，**高价值**）|
| 11 | E08-S8 | `test_patrol_ai.gd` | `test_guard_posture_non_color` | 五态各返回**唯一非空**姿态枚举/字符串；姿态集合与 `GuardState` 一一对应；断言返回值**不含任何色值字段**（C-05） | **新建** |
| 12 | E09-S2 | `tests/unit/test_hud_slice.gd` | `test_suspicion_bar_contrast` ｜ `@ci:C-02` | 用 §2.7 纯函数：数值文本/图标 vs 合成面板 **>7.0**；正文 **>4.5**（C-01）。**不采样像素** | **新建** |
| 13 | E09-S2 | `test_hud_slice.gd` | `test_suspicion_bar_updates_on_suspicion_changed` | 条值只由 `suspicion_changed` 驱动；tier 变化时图标切换 | **改写**（原 `test_suspicion_bar_updates_on_vision_stimulus` 第 74 行，见 §2.8 双写冲突）⚠️ |
| 14 | E09-S2 | `test_hud_slice.gd` | `test_suspicion_bar_shows_top_guard_only` | 3 守卫分别 10/70/40 → 条显示 **70** 且 tier==ALERT；平局取小 `guard_id`；全体 <0.5 时整条隐藏（§2.8） | **新建**（本文建议补）|
| 15 | E09-S3 | `test_hud_slice.gd` | `test_world_element_visibility_toggle` | 注册 3 个编排桩 → 进 FOCUS 全体收到 `set_readability_boost(true)`；出 FOCUS 收到 `false`（§2.9，不断言像素） | **新建** |
| 16 | E09-S4 | `test_hud_slice.gd` | `test_charges_display` | 桩发 `interactable_triggered(1, DECOY, {"charges":2})` → 槽显示类型标签 + 数字 2；`charges==0` → 图标 alpha 降档但数字仍全亮；无道具 → 槽隐藏 | **新建** |
| 17 | E09-S6 | `test_hud_slice.gd` | `test_exposure_alert_ui_non_color` ｜ `@ci:V-02/V-03/C-07` | `exposure_detected` → 暴露层可见；**图标节点非空 + 形状节点非空**（C-07 不单色）；`EXPOSURE_PULSE_HZ <= 2.0`（V-02）；`A11ySettings.screen_shake == false` 默认关（V-03）；暴露层文本 vs 面板 **>7:1**（C-02） | **新建** |
| 18 | E06-S5 | `test_patrol_ai.gd` | `test_suspicion_accumulates_from_sound_event` | **E08 消费侧**：单次满强度声事件 → `S += 15×falloff`（**脉冲，不乘 dt**）· 同 tick 3 事件取 **max** 只计一次（边缘 E2）· `dist≥radius` 事件贡献 0 | **新建** ⚠️ 见 §4.2 重名警告 |

### 4.2 ⚠️ 三处钩子重名 / 已存在警告（务必阅读，否则会误判「已完成」或造成 CI 红）

| # | 冲突 | 说明与处置 |
| --- | --- | --- |
| **N-1** | `test_suspicion_changed_carries_tier`（新，`test_patrol_ai.gd`） **vs** `test_suspicion_changed_carries_tier_parameter`（已存在，`test_event_bus.gd:84`） | **职责不同，不是重复**：已存在的只验证「信号能带 3 个参数」（词汇层，E01-S9）；新增的验证「**发射方算出的 tier 值正确**」（语义层，E08-S6）。**须在两处注释里互相点名**，否则易被当作重复而漏做 |
| **N-2** | `test_suspicion_from_sound_distance`（`sprint1-stories` E06-S5 栏所列） | **已在 Batch B 落盘**（`test_sound_propagation.gd:139` + `:154` 零半径版）。Batch C **不要重建同名用例**；E08 消费侧请用新名 `test_suspicion_accumulates_from_sound_event` |
| **N-3** | `test_suspicion_bar_updates_on_vision_stimulus`（`test_hud_slice.gd:74`，已存在且**当前绿**） | 该用例断言的正是 §2.8 要移除的旧行为。**E09-S2 若只加新逻辑而不改这条，Batch C 上线即 CI 红**。必须与 §2.8 的双写冲突修复**同一次提交内完成** |

### 4.3 `@ci:*` 硬约束在本批的落法

| 约束 | 本批落法 | Batch D（E10-S2） |
| --- | --- | --- |
| `G-04` ≤10Hz | GUT：`test_fsm_tick_le_10hz` 计数断言 | — |
| `G-05` A* 仅转换 | GUT：`test_astar_only_on_transition` 计数断言 | — |
| `C-02` ≥7:1 | GUT：`wcag_contrast()` 纯函数断言 | 可选加入 budget_assert |
| `V-02` ≤2Hz | GUT：常量断言 `EXPOSURE_PULSE_HZ <= 2.0` | `budget_assert._check_pulse_frequency` 已有桩位 ✅ |
| `V-03` 屏震默认关 | GUT：`A11ySettings.screen_shake == false` | — |
| `C-07` 危险不单色 | GUT：断言图标/形状节点非空 | — |

> `tests/ci/budget_assert.gd` 现有 R-02/R-04/R-05/R-06/G-02/V-02 六个桩位，**无 G-04/G-05/C-02**。Batch C **不新增桩位**，全部走 GUT。

---

## 5. 一致性勾稽结论（对照 `system-breakdown` §2 事件词汇）

### 5.1 本批涉及的 4 个信号 × 三方比对

| 信号 | `system-breakdown` §2（权威） | `event_bus.gd`（已落盘） | 本批消费/发射 | 判定 |
| --- | --- | --- | --- | --- |
| `suspicion_changed` | `(guard_id:int, value:float[0..100], tier:SusTier)` | `(guard_id:int, value:float, tier:SusTier)` ✅ | 发 E08-S6 / 消 E09-S2 | ✅ **一致** |
| `exposure_detected` | `(guard_id:int, target:Node)` | `(guard_id:int, target:Node)` ✅ | 发 E08-S4 / 消 E09-S6 | ✅ **一致** |
| `guard_transform_dirty` | `(guard_id:int)` | `(guard_id:int)` ✅ | 发 E08-S6 / 消 E05 | ✅ **一致**（阈值本文补，§2.5-c）|
| `guard_fsm_changed` | `(guard_id:int, old:GuardState, new:GuardState)` | `(guard_id:int, old:String, new:String)` ⚠️ | 发 E08-S6 | ⚠️ **值域漂移** → §2.5-b / 裁决 D6 |
| `interactable_triggered` | `(obj_id:int, type:InteractableType, payload)` | `(id:int, kind:String)` ⚠️ | 消 E09-S4 | ⚠️ **签名漂移**（Sprint 0 残余，收口前移）→ §2.10 / 裁决 D8 |

### 5.2 共享类型比对（`system-breakdown` §2.3）

| 类型 | §2.3 | `event_bus.gd` | 判定 |
| --- | --- | --- | --- |
| `LightState` | `LIT \| EXTINGUISHED` | ✅ 已声明 | ✅ |
| `SusTier` | `CALM \| SUSPICIOUS \| ALERT \| SEARCH` | ✅ 已声明（`NONE→CALM` 已收口） | ✅ |
| `GuardState` | `CALM \| SUSPICIOUS \| ALERT \| SEARCH \| RETURN` | ❌ **未声明** | ⚠️ 建议补到 L2 作值域权威（§2.5-b R1）|
| `InteractableType` | （§2.2 引用，成员见 `interactables` §3：`DECOY\|LIGHT_TOGGLE\|TRAP\|SMOKE`） | ❌ **未声明** | ⚠️ 建议随 D8 一并补 |
| `SoundSource` | `FOOTFALL\|DECOY\|TRAP\|AMBIENT` | 以 `const` 字符串镜像（`sound_propagation.gd:32-35`） | ✅ 可接受（Batch B 既定） |

### 5.3 数值一致性（跨 GDD / 代码 / Story）

| 数值 | GDD | 代码 | Story | 判定 |
| --- | --- | --- | --- | --- |
| `THR_SUSP/ALERT/RETURN` | 25/60/10 | 待建 | 25/60/10 | ✅ |
| `KV/KS/DECAY` | 35/15/8 | 待建 | 35/15/8 | ✅ 值一致；**单位待 D5 显式化** |
| `GRACE_RT` | 1.2s 真实时间 | 桩 1.2 ✅ | 1.2s | ✅ |
| `DECISION_HZ` | 10.0（G-04 ≤10） | 待建 | ≤10Hz | ✅ |
| `GAIT_INTENSITY` | 由 gait 派生（未给具体值） | `0.3/0.6/1.0` | — | ✅ 代码为权威（Batch B 已锁） |
| `RING_CAP` | 8（G-02） | 8 ✅ | 8 | ✅ |
| `EXPOSURE/CONE PULSE` | ≤2Hz（V-02） | 锥 2.0 ✅ | ≤2Hz | ✅ |
| `VIS_MULT_COVER/SMOKE` | 0.6 / 0.3 | 0.6 / 0.3 ✅ | — | ✅ |

**发现一处历史陈述性偏差（非本批、不阻塞，供记录）**：`sprint1-stories.md` E03-S5 验收举例「SNEAK+MOSS **2.5**」，但按已锁公式 `5.0 × MOSS(0.5) × SNEAK(0.5) = **1.25**`，代码与测试（`test_step_commit.gd:181`）均为 **1.25**。**代码/GDD 为权威，Story 举例文字过时**。建议 Batch D 收口时顺手 Edit 该行，本批不动。

### 5.4 一致性总结论
> **本批 4 个点名信号中，3 个（`suspicion_changed` / `exposure_detected` / `guard_transform_dirty`）与 E01-S9 收口契约完全一致，零漂移 ✅。**
> **`guard_fsm_changed` 存在值域漂移（String vs GuardState），`interactable_triggered` 存在 Sprint 0 残余签名漂移** —— 两项均已给出低成本收口方案（§2.5-b R1 / §2.10），改动面合计 = EventBus 新增 2 个 enum + 改 1 个签名 + 改 1 处测试桩 + 2 行文档注释，**不触及 Batch A/B 任何生产代码，零回归风险**。待 §7 D6/D8 拍板后由本批一并收口。

---

## 6. 设计理论四红线复查

| 红线 | 状态 | 说明 |
| --- | --- | --- |
| **主导策略** | ⚠️→✅ | **命中预警**：若声音按「速率口径」结算，RUN 变成零成本最优解（§2.1 实测：净 −4.7 pts/s，永不被听见），直接违反支柱一并使 `sprint1-design-scope` 风险 **R6 爆发**。**采纳脉冲口径后解除**（RUN ≈0.94s 起疑 / ≈2.3s 进 ALERT，成本显著）。另检查「快速闪烁露头」套利：净收益为零 ⇒ 无套利 ✅ |
| **经济失衡** | ✅ | 攻守比 `KV/DECAY = 4.4:1`（露 1s ↔ 躲 4.4s）梯度合理；三步态在声音轴上区分明确（SNEAK 永不被听见 / WALK 4.3s / RUN 0.94s）；`charges` 经济属 E07（Sprint 2），本批不触及 |
| **认知过载** | ⚠️→✅ | **命中预警**：G-01 允许 8 守卫，逐守卫画条 ⇒ 屏上 8 条 + 道具槽 + 凝神态 + 预演 + 暴露层。**§2.8 收敛为「单条聚合（取最高）+ 全体沉寂时隐藏」后解除**。E09-S4 槽位亦保持克制（图标+文字，无冗余装饰） |
| **支柱漂移** | ✅ | E08 服务 支柱一（暴露可恢复：1.2s 宽限 + 软失败 + 可读回落）+ 支柱四（渐升警戒 + 姿态庄重）；E09 服务 支柱二（克制 juicy）+ 支柱三（可访问性基底）；E06-S5 服务 支柱一（噪声是可权衡的承诺）+ 支柱三（诱饵解法）。**无「无主」Story，无反向违背** |

**补充红线自查 · 范围蔓延**：本批四处高风险蔓延点均已显式锚定 ——
❌ 完整 SaveManager（§2.3 边界）· ❌ 真实寻路移动 / 导航烘焙（§2.4 边界）· ❌ a11y 完整包与 C-06 开关（§2.7 边界）· ❌ E07 实体（§2.10 边界）。**任何越界须报主理人裁决。**

---

## 7. 裁决项（全部 CLOSED · v1.0 → v1.1）

> **全部 6 项（D5–D10）已由主理人 / 美术签字 CLOSED**（采纳值见下表「状态 / 采纳值」列，与 `batchc-impl-spec.md` 完全一致）。工程可按下表「采纳值」直接动手，无需再等待拍板。

| # | 裁决项 | 选项 | 推荐 | 状态 / 采纳值 |
| --- | --- | --- | --- | --- |
| **D5** ★ | **声音项结算口径**（§2.1） | (a) **脉冲**：`S += KS(15) × falloff`，单位「点/次」<br>(b) **速率**：`S += KS × falloff × dt`，单位「点/秒」 | **(a) 脉冲** | **CLOSED** — 采纳 (a) 脉冲：`S += KS(15) × falloff`，**不乘 dt**；视觉仍按速率 `KV(35) × vis × dt`。基线式 `dS/dt = vision_vis×KV(35) + sound×KS(15) − (stimulus?0:decay(8))` |
| **D6** | **`guard_fsm_changed` 值域**（§2.5-b） | (a) **保持 `String`** + EventBus 补 `GuardState` 枚举<br>(b) 改为 int enum，严格对齐 §2 | **(b)** ★ | **CLOSED** — 主理人**推翻评审 R1**，改采 (b) int enum 对齐：`EventBus.GuardState{CALM=0,SUSPICIOUS=1,ALERT=2,SEARCH=3,RETURN=4}`，签名 `(guard_id:int, old:GuardState, new:GuardState)` |
| **D7** | **可疑度条三档明度变体取值**（§2.7） | `#7A5A24` / `#A8712A` / `#E8A94A`（三档明度变体） | 采纳签字色板 | **CLOSED** — 林绘澄签字稿 v1.0 定 `#D64545` 警报边框/图标 + `#7A2E2E` 仅低不透明填充 α≤0.35；原三档明度变体**作废** |
| **D8** | **`interactable_triggered` 签名收口是否前移到 Batch C**（§2.10） | (a) **本批收口**为 `(obj_id:int, type:InteractableType, payload:Dictionary)`<br>(b) 维持 Sprint 0 形态 | **(a)** | **CLOSED** — 本批收口为 `(obj_id:int, type:InteractableType, payload:Dictionary)`；`InteractableType{DECOY,LIGHT_TOGGLE,TRAP,SMOKE}` |
| **D9** | **E01-S5 / E01-S8 的排期归属**（§2.3 / §2.4） | (a) **本批用 seam 占位**，两条 L2 Story 正式排入 **Sprint 2**<br>(b) 临时插入 Sprint 1 补做 | **(a)** | **CLOSED** — seam 占位 `_checkpoint_sink` / `_path_provider`；E01-S5 SaveManager / E01-S8 NavServer 正式排入 **Sprint 2** |
| **D10** | **新增设计常量确认**（§2.1 / §2.2 / §2.5） | `LOST_TARGET_RT=0.5s` · `RETURN_SETTLE_RT=1.0s` · `STIM_EPS=0.001` · `SUS_EMIT_EPS=0.5` · `MAX_CATCHUP_TICKS=3` · `XFORM_POS_EPS=0.5m` · `XFORM_YAW_EPS_DEG=5.0` | 全部采纳 | **CLOSED** — 7 常量全部采纳（值可 playtest 后调；定稿后建议 Edit `patrol-ai` §3 常量块收录） |

**无 FAIL、无硬阻塞。** 上述 6 项（D5–D10）现已**全部 CLOSED**，12 条 Story 全部具备动手条件；实现规格见 `batchc-impl-spec.md`。

---

## 8. 交付摘要

| 项 | 内容 |
| --- | --- |
| **判定** | PASS 2（E08-S3 / E08-S8）· CONCERNS 10（A 级 7 / B 级 3）· **FAIL 0** |
| **闭合缺口** | 10 项（C1–C10），含团队点名的全部 6 处 |
| **新增可抄常量** | 7 个（D10）+ 完整 FSM 转换表 + 三档色值 + 时间预算表 |
| **发现的隐性风险** | 3 项 ★：HUD 可疑度条**双写冲突**（§2.8，不修即 CI 红）· 守卫位置**回填缺失**（§2.11 W1，不做即链路静默失效）· `#7A2E2E` **数学上无法达 C-02**（§2.7，需口径裁决） |
| **待裁决** | **0 项**（D5–D10 全部 CLOSED，见 §7） |
| **落盘路径** | `production/sprints/batchc-design-review.md` |

---

*Batch C 设计就绪评审 v1.0 → v1.1（裁决闭合版）完成。总判定 **PASS / CONCERNS（无硬阻塞）**。§7 六项裁决（D5–D10）**全部 CLOSED**，12 条 Story 即可全部动手；实现规格见 `batchc-impl-spec.md`。建议 E09-S3 与 E08-S8 立即起步（不依赖关键路径），为关键路径 `E08-S1→S2→S6→E09-S2/S6` 腾出并行带宽。—— 文策渊*
