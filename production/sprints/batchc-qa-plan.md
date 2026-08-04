# Sprint 1 · Batch C QA 计划 + 冒烟清单（QA Plan & Smoke Checklist）

| 字段 | 值 |
| --- | --- |
| **阶段** | Phase 5 · Sprint 1 · Batch C（E08 巡逻 AI + E09 核心 HUD + E06-S5） |
| **文档版本** | v1.0（QA 计划件；上游 `batchc-impl-spec.md` v1.0 的质量门落地件） |
| **作者** | 严守真（游戏质量保障与测试工程师 / quality-lead） |
| **任务 ID** | BATCHC-QA-01 |
| **批次范围** | 12 条 Story：E08-S1/S2/S3/S4/S5/S6/S8 · E09-S2/S3/S4/S6 · E06-S5 |
| **上游依据** | `production/sprints/batchc-impl-spec.md` v1.0（§2 常量 / §3 逐 Story / §4 三地雷 / §8 18 钩子 / §9 执行拓扑）· `production/sprints/batchc-design-review.md` v1.1（§7 D5–D10 全 CLOSED / §11 残留项）· `design/art/hud-a11y-signature.md` v1.0（D7 签字稿）· `.github/workflows/ci.yml`（fail-closed 门禁逻辑）· `tests/ci-note.md` · `tests/qa/sprint1-batchA-qa.md`（Batch A 评审口径）· 实测 `src/**` + `tests/unit/**` |
| **执行纪律** | 本文**不写任何 `src/` 或 `tests/` 代码、不做 git 操作、未运行 GUT**（引擎侧持有 Godot 二进制，实跑归程基岩）。所有命令为**供他人执行的规格**。 |
| **总判定** | **CONCERNS（无硬阻塞）** —— 18 钩子全部可落地；但发现 **4 项规格级缺口**（§3.4），其中 **2 项为「照规格实现即 CI 红」**、**1 项为「单测绿、集成死」**，须在对应步骤同提交内闭合。 |

> **本文用途**：把 Batch C 的 12 条 Story 转成**可逐条勾选的验收清单**——测试分层策略、18 钩子覆盖矩阵、三处地雷的反向回归断言、冒烟命令、S0–S3 分级与签收门、5 项非阻塞建议确认项的 QA 处置。
>
> **核心主张**：**没有测试的需求不算完成；没有反向断言的地雷不算修复。** 地雷 ①③ 的价值不在「新行为对」，而在「旧行为**再也不会**发生」——故三处地雷全部要求**反向断言（negative assertion）**，见 §3。

---

## 0. 判定速览

| 项 | 结论 |
| --- | --- |
| **钩子可落地性** | **18/18 可落地**，全部 headless 安全（无像素采样、无 Camera3D 依赖、无导航网格烘焙） |
| **测试分层** | 单元 **15** · 集成 **3**（H5 / H10 / H18）· Playtest 签收 **6 项**（无自动钩子覆盖，§1.4） |
| **新发现规格缺口** | **4 项**：N-4 第二处 HUD 双写测试（CI 红）· N-5 遗漏的 `guard_fsm_changed` emit 桩（CI 红）· **N-6 bootstrap 层 suspicion 影子写入方（地雷 ① 未真正闭合）** · N-7 `[Risky]` 未纳入 CI 门 |
| **最高危发现** | **N-6**：`sprint0_bootstrap.gd:114-121` 把 `visibility×100` 转成 **`suspicion_changed`** 发射。删掉 HUD 的 `_on_vision_stimulus` 后，该影子写入方**仍从合法信道注入假可疑度** ⇒ 地雷 ① 被「上移一层」而非消除，且**单测永远测不到**（HUD 单测不加载 bootstrap） |
| **基线**（实测，未跑 GUT） | **Scripts 7 / Passing 59 / 无 Failing 行** —— 与 CI Run #30/#32 口径一致 |
| **预期终态** | **Scripts 8 / Passing 75**（+1 新文件 `test_patrol_ai.gd` 11 例；`test_hud_slice.gd` 6→11 例；H5/H13 为改写不计增量） |
| **签收门** | **fail-closed**：无 `[Failed]` + 无 `Failing ≥1` 行 + summary 可解析 + Scripts/Passing 达预期 + 三地雷反向断言全绿。**绝不复用 `grep 'Failing 0'`**（§5.3） |
| **阻塞项** | **0**。5 项 suggest-confirm 全部非阻塞（§6） |

---

## 1. QA 策略（12 条 Story）

### 1.1 分层原则

| 层 | 判据 | 本批适用 | 数量 |
| --- | --- | --- | --- |
| **单元（Unit）** | 单一被测对象；依赖全部为桩/纯函数；无跨系统真实实例 | FSM、可疑度结算、节流、A* 计数、姿态、WCAG 纯函数、HUD 单点行为 | **15** |
| **集成（Integration）** | ≥2 个**真实**生产对象接线；验证「接线本身」而非各自逻辑 | H5（真 `GuardBrain` 替换 Stub）· H10（`GuardBrain` × `SoundPropagator`）· H18（消费真 `suspicion_from_distance`） | **3** |
| **Playtest 签收** | 无法用断言表达的手感/可读性/平衡判断 | 时间预算手感、三步态声音梯度、α 阶梯可读性、认知负荷、DECOY 有效性 | **6 项** |

> **本批不设「视觉/UI 快照测试」**：D7 签字色板已由 `HudColors` 常量 + WCAG 纯函数完全数值化（§2.3），断言色值比断言像素更强、更稳、headless 安全。**任何要求截图比对的提案视为范围蔓延，报主理人。**

### 1.2 逐 Story 测试策略

| Story | 交付实质 | 主钩子 | 层 | QA 关注点（不止「跑绿」） |
| --- | --- | --- | --- | --- |
| **E08-S1** 五态 FSM | 转换表 + 抖动防护三纪律 | H1 | 单元 | **抖动防护是本条的真正验收点**，不是转换表。`24.9↔25.1` 抖 20 次 → 信号 ≤2 次，这条不过 = 支柱四（肃穆压迫）被破坏 |
| **E08-S2** 可疑度结算 ★ | D5 脉冲口径 + clamp + stimulus 判据 | H2 H3 | 单元 | **口径错则全批失效**：必须显式断言「声音项**不乘 dt**」。E1–E6 六个边缘情况须逐条有断言，不可合并成一条 |
| **E08-S3** 10Hz 节流 | 真实时间 `_process` + 追赶上限 | H4 | 单元 | `Engine.time_scale=0.25` 下计数**不变**是 T-02/ADR-003 的硬约束，比「10Hz」本身更重要 |
| **E08-S4** 1.2s 软失败 | 契约 + seam ① | H5 H6 | **集成** + 单元 | H5 是**改写**：`ExposureGuardStub` → 真 `GuardBrain`。改写后 stub 应删除，否则留下「两个真相源」 |
| **E08-S5** A* seam ② | 时机 + 缓存纪律 | H7 | 单元 | 四步计数断言**必须四步全做**，只做「进 ALERT=1」等于没测缓存 |
| **E08-S6** 四信号 + tier | HUD 唯一数据源 + **地雷 ②** | H8 H9 H10 | 单元 + **集成** | H10 是全批**最高价值**用例（唯一能抓「单测绿集成死」的） |
| **E08-S8** 姿态可读 | 纯枚举 | H11 | 单元 | 反向断言「返回值不含 `#`」= C-05 的机械保证 |
| **E09-S2** 可疑度条 | **地雷 ① + ③** | H12 H13 H14 | 单元 | H13 的价值在**反向**断言（发 `vision_stimulus` 后条值**不变**）。另见 **N-4 / N-6** |
| **E09-S3** 世界编排 | 鸭子类型接口 | H15 | 单元 | 断言 `false` 回落与断言 `true` 同等重要（漏 `false` = 退出凝神后世界永久高亮） |
| **E09-S4** 道具 charges | D8 新签名 | H16 | 单元 | `charges==0` 的**双编码**（alpha 降 + 数字全亮）须分两条断言，不可只断 alpha |
| **E09-S6** 暴露 UI | D7 + **地雷 ③** | H17 | 单元 | 必须断言边框 `== HUD_COLOR_ALARM` 且 `!= HUD_COLOR_ALARM_FILL`（正反各一） |
| **E06-S5** 声脉冲消费 | E08 消费侧 | H18 | **集成** | **H10 与 H18 必须成对通过**；单独 H18 绿不构成 E06-S5 达标（§3.2） |

### 1.3 测试先行纪律（对齐 spec §9.1）

每步严格「**先写测试 → 跑红（确认测试确实在测东西）→ 再实现 → 跑绿 → 提交**」。

> **QA 硬要求**：新增用例必须**先观察到它红过**。一条从未红过的测试没有证明力——它可能断言了恒真表达式。特别针对 H12（纯常量断言）与 H11（枚举断言）这类「天然易恒真」的用例。

### 1.4 Playtest 签收项（**无自动钩子覆盖**，须人工签收）

以下 6 项是 spec 中**有明确数值但无断言载体**的验收面。QA 立场：**它们不阻塞 CI，但阻塞「Batch C 手感达标」的结论**。

| # | 签收项 | 来源 | 判据 | 签收人 |
| --- | --- | --- | --- | --- |
| **PT-1** | 时间预算手感 | spec §3.2 表 | 全亮开阔下 0.71s 起疑 / 1.71s ALERT / 2.91s 软失败，主观「够紧张但可补救」 | 文策渊 + 主理人 |
| **PT-2** | 三步态声音梯度 | spec §3.2 D5 表 | SNEAK 永不被听见 ✅ / WALK ≈4.3s / RUN ≈0.94s，三者手感可区分 | 文策渊 |
| **PT-3** | 攻守比 4.4:1 | spec §3.2 | 「露 1s ↔ 躲 4.4s」不令人烦躁 | 主理人 |
| **PT-4** | α 阶梯可读性（NEW-1） | spec §2.3.3 | 0.30/0.60/0.75/0.92 四档在实机暗色面板上**肉眼可分**，非仅数学单调 | 林绘澄（回签） |
| **PT-5** | 单条聚合认知负荷 | spec §3.8 C7 | 8 守卫场景下单条 argmax **不令人困惑**（「这是谁的条？」） | 文策渊 + 主理人 |
| **PT-6** | DECOY 有效性（B-1） | spec §11 B-1 | 诱饵能否实际引开守卫 | 文策渊（Batch D 复验） |

---

## 2. 测试覆盖矩阵（H1–H18 全映射）

> **列义**：**断言什么** = 被测行为；**通过判据** = 可机械判定的 PASS 条件（QA 据此判 ADEQUATE/INCOMPLETE）；**层** = 单元/集成。
> **约定**：判据中「±1 tick」= ±0.1s；所有时间为**真实时间**（不受 `Engine.time_scale` 影响）。

### 2.1 E08 巡逻 AI（H1–H11）

| H# | Story | 文件 · 钩子名 | 断言什么 | 通过判据（机械可判） | 层 |
| --- | --- | --- | --- | --- | --- |
| **H1** | E08-S1 | `test_patrol_ai.gd` · `test_fsm_transitions` | §3.1 九行转换表；D6 int 值域；抖动防护 | ① 九条转换逐条成立（CALM→SUSP@25 / SUSP→ALERT@60 / SUSP→RETURN@<10 / ALERT→SEARCH@vis≤EPS 持续 0.5s / ALERT→RETURN@软失败 / SEARCH→ALERT@vis>EPS / SEARCH→RETURN@<10 / RETURN→CALM@1.0s / RETURN→SUSP@≥25）；② `old/new` 为 **int** 且 `typeof(old)==TYPE_INT`（**不得**断言字符串）；③ **S 在 24.9↔25.1 抖动 20 次 → `guard_fsm_changed` 发射 ≤2 次**；④ 跨级 5→65 只发 **1** 次 | 单元 |
| **H2** | E08-S2 | `test_patrol_ai.gd` · `test_suspicion_thresholds` | 累积/衰减速率 + 双端钳制 | ① `vis=1.0` → 达 25 用时 0.71s ±1 tick、达 60 用时 1.71s ±1 tick；② 无刺激衰减 = 8.0 点/s ±1 tick；③ **上限截断不累积超额**：喂至饱和后断 LOS，**6.25s 内必回 ≤10**（若隐形累积超额则回落显著变慢 → 必红）；④ 下限 `S ≥ 0.0` | 单元 |
| **H3** | E08-S2 | `test_patrol_ai.gd` · `test_suspicion_stimulus_suppresses_decay` | E3/E4：`STIM_EPS` 判据 + 累积衰减互斥 | ① `vis=0.5` 的 tick 后 `ΔS == +KV×0.5×dt`（**不含** `−DECAY×dt`）；② **`vis=1e-7` 的 tick 仍扣 decay**（证明用 `>STIM_EPS` 而非 `>0.0`）；③ 有声事件的 tick 不扣 decay | 单元 |
| **H4** | E08-S3 | `test_patrol_ai.gd` · `test_fsm_tick_le_10hz` `@ci:G-04` | 真实时间节流 + 追赶上限 | ① 注入 2.0s → `decision_count ∈ [10,20]`；② **`Engine.time_scale=0.25` 下计数不变**（同样注入 2.0s 真实时间，计数落同区间）；③ 单帧注入 0.5s → 本次追赶 ≤ `MAX_CATCHUP_TICKS(3)`；④ **`after_each` 必须复位 `Engine.time_scale=1.0`**（否则污染后续用例，见 §4.4 flaky 防护） | 单元 |
| **H5** | E08-S4 | `test_step_commit.gd` · `test_exposure_grace_1_2s`（**改写**） | 1.2s 宽限 + 自救 + 软失败复位 | ① ALERT+可见 **1.0s 不**发 `exposure_detected`；② 累计 **1.2s 发**；③ 宽限内断 LOS → `exposure_timer` 归零（再喂 1.0s 仍不触发 = 自救成立）；④ 软失败后 `suspicion==0.0` **且** `fsm==GuardState.RETURN`；⑤ **`ExposureGuardStub` 已从文件中删除**（残留即「双真相源」，判 INCOMPLETE） | **集成** |
| **H6** | E08-S4 | `test_patrol_ai.gd` · `test_soft_fail_invokes_checkpoint_sink_once` | D9 seam ① | ① 注入计数 `Callable` → 一次软失败**恰调 1 次**（`==1`，不可用 `>=1`）；② **未注入时软失败不崩**（`Callable()` 空值路径） | 单元 |
| **H7** | E08-S5 | `test_patrol_ai.gd` · `test_astar_only_on_transition` `@ci:G-05` | 缓存纪律（非逐帧） | 四步**全做**：① 进 ALERT → `_astar_calls==1`；② 保持 ALERT 连跑 20 tick → **仍 ==1**；③ →SEARCH → `==2`；④ 回落 RETURN→CALM 后再进 ALERT → `==3` | 单元 |
| **H8** | E08-S6 | `test_patrol_ai.gd` · `test_suspicion_changed_carries_tier` ⚠️N-1 | tier 语义（FSM-aware） | ① 24.9→CALM · 25.0→SUSPICIOUS · 59.9→SUSPICIOUS · 60.0→ALERT；② `fsm==SEARCH` 时**覆写**为 `SusTier.SEARCH`（与 value 无关）；③ RETURN 态 tier==CALM（E10）；④ 文件头注释**点名** `test_event_bus.gd:84` 以区分 N-1 | 单元 |
| **H9** | E08-S6 | `test_patrol_ai.gd` · `test_guard_signals_emitted` | 四信号节流口径 | ① `guard_fsm_changed` 仅 `old!=new` 发；② `suspicion_changed` 受 `SUS_EMIT_EPS(0.5)` 节流（ΔS=0.4 **不发**、0.6 **发**、tier 变化时**必发**即使 ΔS<0.5）；③ `exposure_detected` 每次软失败恰 1 次；④ `guard_transform_dirty`：位移 0.4m **不发** / 0.6m **发**；转向 4° **不发** / 6° **发** | 单元 |
| **H10** ★ | E08-S6 | `test_patrol_ai.gd` · `test_guard_position_synced_to_sound_system` | **地雷 ②（W1）** | ① 注入 `SoundPropagator` 后**首帧即已 `register_guard`**（不等第一次移动）；② 移动 >`XFORM_POS_EPS(0.5m)` → propagator 内该 `guard_id` 位置**已更新为新值**；③ **端到端**：在新位置半径内 `emit()` → `target_guard_ids` **包含**该 `guard_id`；④ **反向**：移动到半径外 → `target_guard_ids` **不含**该 id（证明用的是新位置而非旧位置） | **集成** |
| **H11** | E08-S8 | `test_patrol_ai.gd` · `test_guard_posture_non_color` | C-05 形状编码 | ① 五态各返回**非空**姿态；② 姿态集合 `size()==5` 且**无重复值**（与 `GuardState` 一一对应）；③ **反向**：所有返回值**不含 `#` 字符**（= 不含色值） | 单元 |

### 2.2 E09 核心 HUD + E06-S5（H12–H18）

| H# | Story | 文件 · 钩子名 | 断言什么 | 通过判据（机械可判） | 层 |
| --- | --- | --- | --- | --- | --- |
| **H12** ★ | E09-S2 | `test_hud_slice.gd` · `test_suspicion_bar_contrast` `@ci:C-02` | **地雷 ③** D7 色板合规 | ① Carrier vs **三种**面板（`#16181D`/`#1B1B1F`/`#1C1F26`）全 **>7.0**；② `CAUTION` vs 基准 **>3.0**；③ `ALARM` vs 基准 **>3.0**；④ **★反向**：`wcag_contrast(ALARM_FILL, panel) < 3.0`；⑤ `ALARM_FILL_ALPHA_MAX <= 0.35`；⑥ `SUS_FILL_ALPHA` 四档**严格单调递增**；⑦ 合成核算：`composite(ALARM_FILL, panel, 0.35)` 上 Carrier **>7.0** 且 `ALARM` 边框 **>3.0**。**全程不采样像素** | 单元 |
| **H13** ★ | E09-S2 | `test_hud_slice.gd` · `test_suspicion_bar_updates_on_suspicion_changed`（**改写**）⚠️N-3 | **地雷 ①** 单一写入方 | ① `suspicion_changed(1, 42.0, SUSPICIOUS)` → 条值 42.0；② **★反向（本条核心）**：随后发 `vision_stimulus(1, null, 0.9)` → 条值**仍为 42.0**（证明双写已断）；③ tier 变化时图标字形切换 | 单元 |
| **H14** | E09-S2 | `test_hud_slice.gd` · `test_suspicion_bar_shows_top_guard_only` | C7 单条聚合 | ① 3 守卫 10/70/40 → 显示 **70** 且 tier==ALERT；② 平局（两守卫同值）取 **小 `guard_id`**；③ 全体 `<SUS_EMIT_EPS(0.5)` → `_suspicion.visible == false` | 单元 |
| **H15** | E09-S3 | `test_hud_slice.gd` · `test_world_element_visibility_toggle` | C8 编排（只编排不重绘） | ① 注册 3 桩 → 进 FOCUS 全体收 `set_readability_boost(true)`；② **出 FOCUS 全体收 `false`**（缺此条 = 凝神退出后世界永久高亮）；③ 无 `set_readability_boost` 方法的对象**不崩**（`has_method` 守卫）；④ **不断言任何像素** | 单元 |
| **H16** | E09-S4 | `test_hud_slice.gd` · `test_charges_display` | D8 新签名 + C-05 双编码 | ① `interactable_triggered(1, InteractableType.DECOY, {"charges":2})` → 槽显示标签 `DECOY` **且**数字 `2`；② `charges==0` → 图标 alpha `== CHARGES_DIM_ALPHA(0.4)` **且**数字 alpha **仍全亮**（分两条断言）；③ 无道具 → 槽 `visible==false` | 单元 |
| **H17** | E09-S6 | `test_hud_slice.gd` · `test_exposure_alert_ui_non_color` `@ci:V-02/V-03/C-07` | D7 + **地雷 ③** 第二落点 | ① `exposure_detected` → 暴露层可见；② 图标节点非空 **且** 形状节点非空（C-07）；③ `EXPOSURE_PULSE_HZ <= 2.0`（V-02）；④ `A11ySettings.screen_shake == false`（V-03）；⑤ **★正反各一**：边框色 `== HUD_COLOR_ALARM` **且** `!= HUD_COLOR_ALARM_FILL`；⑥ 暴露层文本 vs **合成红底** `>7.0`（C-02）；⑦ 填充 alpha `<= 0.35` | 单元 |
| **H18** | E06-S5 | `test_patrol_ai.gd` · `test_suspicion_accumulates_from_sound_event` ⚠️N-2 | D5 脉冲口径（消费侧） | ① 单次满强度声事件 → `ΔS == KS(15) × falloff`，**且用两个不同 `dt` 各跑一次得同一 ΔS**（这是「不乘 dt」的**唯一**有效证明）；② 同 tick 3 事件取 **max** 只计一次（E2）；③ `dist >= radius` → 贡献 **0**（E11）；④ `radius==0` → 贡献 0 且不崩（E12）；⑤ **不重建** `test_suspicion_from_sound_distance`（N-2） | **集成** |

### 2.3 覆盖缺口自查（QA 主动声明）

| 缺口 | 说明 | 处置 |
| --- | --- | --- |
| **E08-S5 真实寻路** | 本批仅测「时机 + 缓存」，**不测守卫会走路** | spec §3.5 已显式声明为 Sprint 1 边界。QA 认可，**不视为缺口** |
| **W2 多守卫多锥** | `set_vision_cone` 有注入点但**无钩子** | 8 守卫场景属 Sprint 2；本批建议 H9 顺带断言「注入后 `_cone.set_observer` 被调用」，**非阻塞** |
| **C-06 色盲开关** | 本批仅预留读取点，**不做开关** | spec §3.11 已声明。H17 覆盖「不开开关即色盲安全」，**这才是 Basic 档定义**，覆盖充分 |
| **E13 多层 3D 衰减** | 已知限制，MVP 单层无影响 | §6 suggest-confirm 项，QA 要求**在 H18 加一行注释**记录该限制，防止 Sprint 2 遗忘 |
| **`budget_assert.gd`** | 无 G-04/G-05/C-02 桩位 | spec §8.2 明确 Batch C **不碰 CI 脚本**。QA 认可，归 Batch D · E10-S2 |

---

## 3. 三处地雷的回归验证（L1 / L2 / L3）

> **QA 立场**：地雷的验收标准不是「新行为对」，而是「**旧行为再也不会发生**」。故三条全部要求**反向断言**。只有正向断言 = 判 **INCOMPLETE**。

### 3.1 L1 · HUD 单一写入方（`_suspicion.value` 无 `_on_vision_stimulus`）

**要求终态**：`_on_suspicion_changed` → `_refresh_top_guard()` 是 `_suspicion.value` 的**唯一**写入路径。

| 检查项 | 方法 | 通过判据 |
| --- | --- | --- |
| **L1-a** 源码删除 | 静态 grep | `grep -n '_on_vision_stimulus' src/ui/hud_slice.gd` → **0 命中**（现命中 `:46`、`:47`、`:117`） |
| **L1-b** 连接删除 | 静态 grep | `grep -n 'vision_stimulus' src/ui/hud_slice.gd` → **0 命中** |
| **L1-c** 唯一写入点 | 静态 grep | `grep -cn '_suspicion\.value' src/ui/hud_slice.gd` → **恰 1**（`_refresh_top_guard` 内） |
| **L1-d** 行为反向断言 | **H13** | 发 `suspicion_changed(1,42)` 后再发 `vision_stimulus(1,null,0.9)` → 条值**仍 42.0** |
| **L1-e ⚠️ 新增** | **N-4** | `test_suspicion_bar_clamps_to_range` 同步改写（见下） |
| **L1-f ⚠️ 新增** | **N-6** | bootstrap 影子写入方处置（见下，**决定 L1 是否真正闭合**） |

#### ⚠️ N-4（**规格遗漏 · 照规格实现即 CI 红**）

spec §8.1 的 N-3 只点名了 `test_hud_slice.gd:74 test_suspicion_bar_updates_on_vision_stimulus`。**实测发现第二处**：

```
tests/unit/test_hud_slice.gd:81  func test_suspicion_bar_clamps_to_range():
tests/unit/test_hud_slice.gd:83      _bus.vision_stimulus.emit(1, null, 1.0)
tests/unit/test_hud_slice.gd:84      assert_almost_eq(_hud._suspicion.value, 100.0, ...)
```

该用例**同样**靠 `vision_stimulus` 驱动条值。删除 `_on_vision_stimulus` 后条值恒为 `0.0` → 断言 `100.0` **必失败**。

| 项 | 内容 |
| --- | --- |
| **后果** | 只改 N-3 一条 ⇒ **步 11 提交后 CI 仍红 1 条**，且症状与 N-3 相同易被误判为「改漏了同一条」 |
| **处置** | 与地雷 ① **同一提交内**改写为 `suspicion_changed` 驱动：发 `suspicion_changed(1, 150.0, ALERT)` → 断言条值 `clampf` 到 **100.0** |
| **严重度** | **S1**（CI 阻断） |
| **归属** | E09-S2 / 步 11 |

#### ⚠️ N-6（**最高危 · 地雷 ① 未真正闭合 · 单测永远测不到**）

实测 `src/main/sprint0_bootstrap.gd`：

```
:110    _vc.vision_stimulus.connect(_bus.vision_stimulus.emit)
:111    _vc.vision_stimulus.connect(_on_vision_stimulus)
:114  func _on_vision_stimulus(guard_id, _target, visibility):
:117      var suspicion := clampf(visibility * 100.0, 0.0, 100.0)
:121      _bus.suspicion_changed.emit(guard_id, suspicion, _suspicion_tier(suspicion))
```

**bootstrap 把 `visibility×100` 转换成 `suspicion_changed` 发射。** 这意味着：

| 项 | 内容 |
| --- | --- |
| **症状** | 删掉 HUD 的 `_on_vision_stimulus` 后，假可疑度**改从合法信道 `suspicion_changed` 注入**。HUD 无法区分它与 `GuardBrain` 的真实数据 |
| **后果** | 在 demo 场景中，`GuardBrain` 与 bootstrap 影子写入方**同时**发 `suspicion_changed`：<br>· `guard_id` **相同** ⇒ `_suspicion_by_guard[gid]` 被两路以 ≥10Hz 互相覆写 ⇒ **地雷 ① 的高频闪烁原样复现，只是上移了一层**<br>· `guard_id` **不同** ⇒ HUD 认为存在一个幽灵守卫；argmax 可能被幽灵值占据 ⇒ 条显示错误守卫 |
| **为何单测抓不到** | `test_hud_slice.gd` 直接 `HudSlice.new()`，**从不加载 `sprint0_bootstrap.gd`** ⇒ H13 的反向断言**全绿**，而 demo 实机闪烁。**与地雷 ② 完全同类的「单测绿、集成死」** |
| **规格盲区** | spec §1「不碰」清单只排除了 bootstrap 的**声音**路径（"Sprint 0 遗留声音路径"），**从未提及 `:110-121` 的 vision→suspicion 影子路径**；spec §3.8 的地雷 ① 三步也只覆盖 `hud_slice.gd` |
| **建议处置** | **删除 `sprint0_bootstrap.gd:111` 的连接 + `:114-121` 的 `_on_vision_stimulus` 函数 + `_suspicion_tier` 辅助函数**（其唯一调用点在此）。`:110` 的 `_vc.vision_stimulus → _bus.vision_stimulus.emit` 转发**保留**（E05 契约，其他消费方可能需要）。理由：Batch C 之后 `GuardBrain` 成为 `suspicion_changed` 的**唯一生产发射方**（spec §2.2 S4 原话），bootstrap 的 Sprint 0 provisional shim **使命已终结**——其函数注释自己写着「E08-S2 replaces this with the real 25/60/10 threshold logic」 |
| **验证** | 静态：`grep -n 'suspicion_changed' src/` → 生产侧**只应命中 `event_bus.gd` 声明 + `patrol_ai.gd` 发射**，不得再命中 `sprint0_bootstrap.gd` |
| **严重度** | **S1**（玩法级缺陷 + 地雷 ① 名义闭合实际未闭合） |
| **归属** | E09-S2 / 步 11（与地雷 ① 同提交）。**属越界改动**（触及 spec §1 未列文件）⇒ **须报主理人裁决后执行**，QA 不擅自扩范围 |

> **QA 判定口径**：**L1 的签收以 N-6 处置结论为准。** 若主理人裁决「本批不动 bootstrap」，则 L1 判 **CONCERNS（名义闭合）**，须在 Batch D 建条目，并在 `batchc-qa-plan` 与 Story 验收里显式记为**已知集成缺陷**，不得静默放行。

### 3.2 L2 · 守卫位置回填（`_sound.update_guard` 收到活体守卫位置）

**要求终态**：`GuardBrain` 是 `SoundPropagator._guard_positions` 的活体驱动源；E06-S5 衰减链路**真实通电**。

| 检查项 | 方法 | 通过判据 |
| --- | --- | --- |
| **L2-a** 注入点存在 | 静态 grep | `grep -n 'set_sound_system' src/game/patrol_ai.gd` → 命中 |
| **L2-b** 首帧注册 | **H10 ①** | 注入后**立即**（未移动前）`SoundPropagator` 已含该 `guard_id`。**这条最易漏**——只在 `_maybe_mark_transform_dirty` 里 `update_guard` 会导致守卫**站着不动就永远不在名单里** |
| **L2-c** 移动更新 | **H10 ②** | 移动 >0.5m 后内部记录位置 == 新位置 |
| **L2-d** 端到端通电 | **H10 ③** | `emit()` 的 `target_guard_ids` **包含**该守卫 |
| **L2-e ★反向** | **H10 ④** | 守卫移出半径后 `target_guard_ids` **不含**该守卫（证明用的是**新**位置；若仍用旧位置则此条必红） |
| **L2-f 成对门** | **H10 + H18** | **两条必须同时绿**。H18 单绿不构成 E06-S5 达标（H18 可用直接注入的 falloff 通过，绕开回填链路） |
| **L2-g** 上游未改 | 静态 diff | `src/game/sound_propagation.gd` 的 `register_guard`/`update_guard`/`remove_guard`/`emit`/`suspicion_from_distance` **零改动**（Batch B 已达标；改动即越界） |

> **为什么 L2-e 反向断言不可省**：正向断言（③）在「守卫恰好一直在半径内」时，即使 `update_guard` 从未被调用也可能通过（首帧注册的位置就在半径内）。**只有把守卫移出半径**，才能区分「用了新位置」与「用了首帧旧位置」。

### 3.3 L3 · `#7A2E2E` 永不作文字/边界/图标载体

**要求终态**：`HUD_COLOR_ALARM_FILL` 只能以 `alpha ≤ 0.35` 作填充底纹。

| 检查项 | 方法 | 通过判据 |
| --- | --- | --- |
| **L3-a ★反向断言** | **H12 ④** | `wcag_contrast(HUD_COLOR_ALARM_FILL, PANEL_BASE) < 3.0` —— **这是把「误用」变成「数学不可能」的锁**。它永远为真（1.91:1），其价值是**文档化意图 + 阻止有人偷偷改亮该常量绕过审计** |
| **L3-b** alpha 上限 | **H12 ⑤** | `ALARM_FILL_ALPHA_MAX <= 0.35` |
| **L3-c** 边框正解 | **H17 ⑤** | 暴露层边框 `== HUD_COLOR_ALARM` **且** `!= HUD_COLOR_ALARM_FILL`（正反各一） |
| **L3-d** 合成后仍达标 | **H12 ⑦ / H17 ⑥** | `composite(ALARM_FILL, panel, 0.35)` 上：Carrier 文字 **>7.0**（预期 11.59:1）、`ALARM` 边框 **>3.0**（预期 3.42:1） |
| **L3-e** 禁硬编码色 | 静态 grep | `grep -nE '(Color\("#|Color\.from_string\("#)' src/ui/hud_slice.gd` → **0 命中**（现命中 `:10` `#10141C`、`:11` `#C8862F`、`:12` `#3E5C76`、`:66` `#DCE3EC`，全部须改引 `HudColors.*`） |
| **L3-f** 色值权威注释 | 静态 grep | `hud_slice.gd` 文件头含 `hud-a11y-signature.md`（D7 溯源） |
| **L3-g** 单调性 | **H12 ⑥** | `SUS_FILL_ALPHA` 四档严格单调（0.30<0.60<0.75<0.92） |

> **L3-e 特别提示**：`hud_slice.gd:10 FOCUS_TINT := Color("#10141C")` 是**凝神压暗遮罩**，不属 D7 三档色板。QA 口径：它**也须**移入 `HudColors`（或明确标注为非 alert-tier 色并保留），但**不因它判 FAIL**——判 CONCERNS，避免为形式统一而扩大改动面。

### 3.4 ⚠️ 新发现的规格缺口汇总（4 项）

| # | 缺口 | 性质 | 严重度 | 归属步骤 | 处置 |
| --- | --- | --- | --- | --- | --- |
| **N-4** | `test_hud_slice.gd:81 test_suspicion_bar_clamps_to_range` 同样靠 `vision_stimulus` 驱动，spec N-3 未点名 | **照规格实现即 CI 红** | **S1** | 步 11 / E09-S2 | 与地雷 ① 同提交改写为 `suspicion_changed(1,150.0,ALERT)` → 断言 clamp 至 100.0 |
| **N-5** | `test_event_bus.gd:65 _bus.guard_fsm_changed.emit(1, "CALM", "SUSPICIOUS")` 传**字符串**。spec §2.2 站点表 S6 **只列了 `:67` 的 `interactable_triggered`**，遗漏 `:65` | **照规格实现即 CI 红** | **S1** | 步 0-a / D6 收口 | 同提交改为 `emit(1, EventBus.GuardState.CALM, EventBus.GuardState.SUSPICIOUS)`。D6 把签名改为 int enum 后，字符串实参在 Godot 4 会触发类型错误/静默异化，`test_all_signals_can_connect_and_emit`（含 `:79` 断言）**必红** |
| **N-6** | `sprint0_bootstrap.gd:111/:114-121` 影子写入方，把 `visibility×100` 转成 `suspicion_changed` | **地雷 ① 名义闭合、实际未闭合；单测永远测不到** | **S1** | 步 11 / E09-S2 | 见 §3.1。**属越界改动，须主理人裁决** |
| **N-7** | `.github/workflows/ci.yml` 的门只 `grep -qF '[Failed]'`，**不检 `[Risky]`** | CI 门存在盲区：零断言测试报 Risky 但**判 pass** | **S2** | Batch D · E10-S2 | Batch C **不碰 CI 脚本**（spec §8.2）⇒ 本批以**人工核查 `[Risky]` 计数**兜底（§5.3 门 G4）；ci.yml 补 `[Risky]` 归 Batch D |

> **N-4 / N-5 的共性**：二者都是「spec 的收口清单漏了一行」，且**都会在实现完成、自认为做对的那一刻**让 CI 变红。**QA 建议工程在步 0-a 与步 11 动手前，先各跑一次全库 grep 自查**（命令见 §4.2 PRE-1/PRE-2），5 秒成本换一次 CI 往返。

---

## 4. 冒烟测试范围与命令

> **纪律**：本文档**未运行 GUT**。以下命令为**供他人执行的规格**，均照抄 `.github/workflows/ci.yml` 的实际调用形态，确保本地结果与 CI 可比。

### 4.1 基线捕获（**开工前必做一次**）

**目的**：锁定 Batch C 动手**之前**的绿态，使后续任何红都能明确归因为「本批引入」而非「继承状态」（这正是 Batch A 评审 §2-B 踩过的坑）。

```bash
# 前置：Godot 4.4.1 + GUT v9.3.0 置于 addons/gut/
# 在工程根目录执行
godot --headless \
  -s addons/gut/gut_cmdln.gd \
  -gdir=res://tests/unit \
  -gexit \
  -glog=3 \
  > gut_baseline.txt 2>&1 || true

# 提取与 CI 完全同口径的 summary
grep -Ei "^[[:space:]]*(scripts|tests|passing|failing)[[:space:]]*[:=]?[[:space:]]*[0-9]+" gut_baseline.txt \
  | sed -E 's/^[[:space:]]+//' | awk '!seen[$0]++' | tr '\n' ' '
```

**预期基线（静态实测推导，未跑 GUT）**：

| 项 | 值 | 依据 |
| --- | --- | --- |
| **Scripts** | **7** | `tests/unit/*.gd` 实测 7 个文件 |
| **Passing** | **59** | 逐文件 `func test_` 实测：`event_bus 4` + `hud_slice 6` + `integration_step_vision 6` + `light_model 9` + `sound_propagation 8` + `step_commit 12` + `vision_cone 14` = **59** |
| **Failing 行** | **不存在**（GUT 9.3.0 全绿时省略该行） | 与 CI Run #30 记录的 "Scripts 7 / Passing 59" **完全吻合** ⇒ 当前 59/59 全绿 |

> **若实跑基线 ≠ 7/59**：**立即停止 Batch C 开工**并报主理人。差异意味着存在未记录的漂移（例如 `test_integration_step_vision.gd` 的 6 例集成测试状态变化），继续开工会污染归因。

### 4.2 动手前静态自查（零成本，防 N-4/N-5）

```bash
# PRE-1（步 0-a 前）：找出所有需随 D6/D8 改签名的 emit 桩
grep -rn 'guard_fsm_changed\.emit\|interactable_triggered\.emit' src/ tests/
# 预期命中 2 处，均在 tests/unit/test_event_bus.gd（:65 和 :67）
# ⚠️ 两处都要改；spec §2.2 只列了 :67 —— 这是 N-5

# PRE-2（步 11 前）：找出所有依赖 vision_stimulus 驱动可疑度条的用例
grep -rn 'vision_stimulus' tests/unit/test_hud_slice.gd
# 预期命中 :74 :76 :78（N-3）和 :83（N-4）—— 两条用例都要改写

# PRE-3（步 11 前）：找出 suspicion_changed 的全部生产发射方
grep -rn 'suspicion_changed\.emit' src/
# 预期命中 sprint0_bootstrap.gd:121 —— 这是 N-6 影子写入方
# Batch C 之后此处应仅剩 patrol_ai.gd
```

### 4.3 核心回路冒烟（**SMOKE-1** · 评审者 post-build 最小命令）

**目的**：一条命令确认 `巡逻 → 侦测 → 警戒 → HUD 反映` 核心回路仍通。

```bash
godot --headless \
  -s addons/gut/gut_cmdln.gd \
  -gtest=res://tests/unit/test_patrol_ai.gd,res://tests/unit/test_hud_slice.gd \
  -gexit \
  -glog=3
```

**回路映射（这两个文件为何足以代表核心回路）**：

| 回路环节 | 覆盖钩子 | 说明 |
| --- | --- | --- |
| **巡逻**（tick 运转） | H1 H4 | 五态 FSM + 10Hz 真实时间节流 |
| **侦测**（刺激→累积） | H2 H3 H18 | 视觉速率 + 声音脉冲 + 衰减互斥 |
| **警戒**（阈值→状态→信号） | H1 H8 H9 | 25/60 上行 + tier 计算 + 四信号发射 |
| **HUD 反映** | H13 H14 | 单一写入方 + argmax 聚合显示 |
| **暴露闭环** | H17 | `exposure_detected` → 暴露层可见 |
| **声音链路通电** | **H10** | 地雷 ② —— 唯一能抓「单测绿集成死」的用例 |

> **注意**：H5 在 `test_step_commit.gd`，**不在 SMOKE-1 范围内**。SMOKE-1 是「核心回路仍活着」的快速确认，**不是签收门**。签收一律走 SMOKE-2 全量。

### 4.4 全量门禁（**SMOKE-2** · 签收唯一依据）

**与 `.github/workflows/ci.yml` 步骤 3 逐字对齐**：

```bash
godot --headless \
  -s addons/gut/gut_cmdln.gd \
  -gdir=res://tests/unit \
  -gexit \
  -glog=3 \
  > gut_output.txt 2>&1 || true
```

**预期终态**：

| 项 | 基线 | Batch C 后 | 增量来源 |
| --- | --- | --- | --- |
| **Scripts** | 7 | **8** | +1 `test_patrol_ai.gd`（新建） |
| **Passing** | 59 | **75** | +11（`test_patrol_ai.gd`：H1 H2 H3 H4 H6 H7 H8 H9 H10 H11 H18）<br>+5（`test_hud_slice.gd`：H12 H14 H15 H16 H17；H13 与 N-4 为**改写**不计增量，6→11）<br>+0（`test_step_commit.gd`：H5 改写，仍 12）<br>+0（`test_event_bus.gd`：仅改 emit 桩，仍 4） |
| **Failing 行** | 不存在 | **不存在** | — |
| **`[Risky]`** | 0 | **0** | 人工核查（N-7，CI 未覆盖） |

> **计数偏差处置**：
> - **Passing < 75** ⇒ 有钩子未落地。对照 §2 矩阵定位缺哪条，判 **INCOMPLETE**，**不放行**。
> - **Passing > 75** ⇒ 存在计划外用例。须说明来源；若属重建同名用例（N-1/N-2 警告），判 **重复覆盖**，要求合并。
> - **Scripts ≠ 8** ⇒ 文件增删越界，报主理人。

### 4.5 flaky（测试稳定性）防护

本批引入两类 flaky 风险源，QA 要求在实现时即规避：

| 风险 | 来源 | 防护要求 | 检查方法 |
| --- | --- | --- | --- |
| **`Engine.time_scale` 泄漏** | H4 需设 `time_scale=0.25` | `after_each` **必须**复位 `1.0`（`test_step_commit.gd` 现有 `after_each` 已是正确范例） | 连跑 3 次 SMOKE-2，结果须完全一致 |
| **`Time.get_ticks_msec()` 墙钟依赖** | `_process` 真实时间模式 | 单测**一律走 `tick_real(dt)` 显式注入**，**禁止**依赖 `_process` 自然驱动或 `await` 真实秒数 | `grep -n 'await.*timeout\|OS.delay' tests/unit/test_patrol_ai.gd` → 应 **0 命中** |
| **场景树 / 节点泄漏** | HUD 用例需进树 | 沿用 `add_child_autofree`（`test_hud_slice.gd:37/:44` 现有正确范例，注释已记录 ADDCHILD-AUTOFREE-01 根因） | `grep -c 'add_child_autofree' tests/unit/test_hud_slice.gd` ≥ 现有值 |
| **用例间顺序依赖** | argmax 字典 `_suspicion_by_guard` 跨用例残留 | `before_each` 重建 HUD 实例（现有模式已满足） | 用 `-gshuffle`（若 GUT 9.3.0 支持）或手工调序跑一次 |

> **flaky 判定与处置**：同一提交连跑 **3 次** SMOKE-2，任一用例出现结果翻转 ⇒ 判 **flaky**，立即**隔离**（标记 `pending` 或移出 `tests/unit`）并开 **S2** 单，**不得**放任其污染 CI 信号。「偶尔红」比「一直红」危害更大——它训练团队忽略红灯。

---

## 5. Bug 分级（S0–S3）与签收门

### 5.1 严重度分级

| 级 | 名称 | 判据 | 响应 | 是否阻断签收 |
| --- | --- | --- | --- | --- |
| **S0** | **Blocker** | 构建/导入失败；GUT 无法产出可解析 summary；解析错误（parse error）；批内既有 59 例产生**回归** | **立即停工**修复，全批暂停 | **是**（绝对） |
| **S1** | **Critical** | CI 红（任一 `[Failed]`）；三地雷任一未闭合（含反向断言缺失）；D5–D10 裁决值被违背；`@ci:*` 硬约束用例失败；**N-4 / N-5 / N-6** | 当日修复，不得进入下一步骤 | **是** |
| **S2** | **Major** | 钩子缺失或断言不完整（判 INCOMPLETE）；flaky 测试；边缘情况 E1–E13 有遗漏；硬编码色值/裸数残留；**N-7** | 本批内修复；若跨批则须主理人书面同意延期 | **是**（可经主理人裁决降级） |
| **S3** | **Minor** | 注释缺失（如 N-1 互相点名未写）；命名不一致；文档陈述性偏差（DOC-1/DOC-2）；非关键 alpha 微差 | 记录，可延 Batch D | 否 |

### 5.2 分级示例（本批具体落点）

| 现象 | 级 | 理由 |
| --- | --- | --- |
| `test_patrol_ai.gd` 解析错误导致整个 script 不加载 | **S0** | GUT summary 的 Scripts 计数异常，全批不可判 |
| 步 11 提交后 `test_suspicion_bar_clamps_to_range` 红（N-4） | **S1** | CI 阻断 |
| 步 0-a 提交后 `test_all_signals_can_connect_and_emit` 红（N-5） | **S1** | CI 阻断，且阻塞全部后续步骤 |
| H10 绿但 H18 未落地 | **S1** | 地雷 ② 成对门未满足（§3.2 L2-f） |
| H12 缺反向断言 `ALARM_FILL < 3.0` | **S1** | 地雷 ③ 的锁缺失 = 地雷未闭合 |
| bootstrap 影子写入方保留（N-6） | **S1** | 地雷 ① 名义闭合；**若主理人裁决延期则降 S2 并登记为已知集成缺陷** |
| H9 只断了 `suspicion_changed` 节流，未断 `guard_transform_dirty` 阈值 | **S2** | 钩子 INCOMPLETE |
| `hud_slice.gd` 残留 `FOCUS_TINT := Color("#10141C")` | **S2** | L3-e 硬编码色，但非 alert-tier 载体 |
| H8 未在注释里点名 `test_event_bus.gd:84`（N-1） | **S3** | 仅影响可维护性 |
| `sprint1-stories.md` E03-S5「2.5」未改（DOC-1） | **S3** | 陈述性偏差，代码/测试均为 1.25 |

### 5.3 签收门（Sign-off Gate）—— **一次运行被判 success 的充要条件**

> **fail-closed 原则**：**任何无法证明为绿的状态，一律判红。** 严禁「没看到失败信号就当过了」。

#### 门 G1 · summary 可解析（继承 `ci.yml:116-119`）

```bash
if [ "$SUMMARY" = "GUT output not parsed" ]; then
  echo "::error::GUT produced no parsable summary (crash/import issue) — job fails."
  exit 1
fi
```
**判据**：summary 必须解析出 Scripts / Passing 计数。**无法解析 = FAIL，不是 pass。** 这道门专防「崩溃/导入失败导致零输出被误读为零失败」。

#### 门 G2 · 无失败信号（继承 `ci.yml:120-126` · **正确逻辑**）

```bash
if ! grep -qF '[Failed]' gut_output.txt 2>/dev/null \
   && ! echo "$SUMMARY" | grep -qE 'Failing[[:space:]]*[:=]?[[:space:]]*[1-9][0-9]*'; then
  echo "GUT reports zero failures — job passes."
  exit 0
fi
echo "::error::GUT reports failing tests — job fails."
exit 1
```

**两条判据（缺一不可）**：
1. `gut_output.txt` 中**不含**字面量 `[Failed]`；
2. summary 中**不含** `Failing` 后跟 **≥1** 的数字。

> ### ⛔ 严禁复用 `grep 'Failing 0'` 陷阱
>
> **GUT 9.3.0 在零失败时会完全省略 `Failing` 行**（Run #30 只打印了 `Scripts 7 / Passing 59`）。旧门 `grep 'Failing 0'` 因**匹配不到**而把一次 **59/59 全绿**的运行误判为红。
>
> **正确口径：「缺少失败行」= 通过，不是 = 失败。** 判 pass 的依据是**失败信号的缺席**（`[Failed]` 不存在 且 `Failing ≥1` 不存在），而**不是**某个成功字符串的存在。
>
> 这与 G1 并不矛盾：G1 已先行拦截「完全没有输出」的基础设施故障；G2 面对的是「有合法 summary 但无失败行」的正常全绿场景。**两道门配合才是 fail-closed。**

#### 门 G3 · 计数达预期（Batch C 新增）

| 判据 | 值 |
| --- | --- |
| `Scripts` | **== 8** |
| `Passing` | **== 75** |

> G2 只能证明「没有失败」，**不能**证明「该跑的都跑了」。一个被误删的测试文件会同时满足 G1+G2 —— G3 专防这种**静默覆盖流失**。

#### 门 G4 · 无 `[Risky]`（Batch C 人工，因 N-7）

```bash
grep -c '\[Risky\]' gut_output.txt   # 预期 0
```
**判据**：`[Risky]` 计数 == 0。GUT 把**零断言**的测试标记为 Risky —— 它不算失败，因此 `ci.yml` 现有逻辑**放行**（N-7）。一条什么都不断言的测试提供**零证明力**，却会让 Passing 计数虚高、蒙混过 G3。
**本批处置**：人工核查（Batch C 不碰 CI 脚本）。**Batch D · E10-S2 应把 `[Risky]` 并入 `ci.yml` 的 G2 grep。**

#### 门 G5 · 三地雷反向断言全绿（Batch C 新增，人工核对 §3）

| 地雷 | 必须绿的反向断言 |
| --- | --- |
| **L1** | H13 ②（发 `vision_stimulus` 后条值不变）+ L1-a/b/c 静态 grep 全 0 命中 + **N-6 已处置或已由主理人书面裁决延期** |
| **L2** | H10 ④（移出半径后 `target_guard_ids` 不含该守卫）+ H10/H18 **成对**绿 |
| **L3** | H12 ④（`ALARM_FILL < 3.0`）+ H12 ⑤（alpha ≤0.35）+ H17 ⑤（边框 `!= ALARM_FILL`）+ L3-e 静态 grep 0 命中 |

> **G5 存在的理由**：反向断言可以「存在但被注释掉」或「写成恒真表达式」而仍让 G2/G3 全绿。G5 要求**人工逐条确认反向断言真实生效**（配合 §1.3 的「必须先观察到它红过」）。

#### 签收判定表

| 判定 | 条件 | 动作 |
| --- | --- | --- |
| **PASS** | G1 ∧ G2 ∧ G3 ∧ G4 ∧ G5 **全绿** | 建议主理人放行 |
| **CONCERNS** | G1–G3 绿；G4 或 G5 存在 **S2/S3** 未决项 | **可放行但须登记**：列明未决项 + 归属批次 + 责任人，主理人书面确认 |
| **FAIL** | 任一 **S0/S1** 未闭合，或 G1/G2/G3 任一红 | **不放行** |

> **质量门是建议性门控（advisory）**：QA 给判定，**最终放行权在用户/主理人**。但 **FAIL 状态下的放行必须留痕**——写明放行理由与承接批次，不得静默合并。

---

## 6. 5 项非阻塞「建议确认」（suggest-confirm）的 QA 处置

> 全部来自 `batchc-design-review.md` §11 / `batchc-impl-spec.md` §11。**共性：均不阻塞 Batch C 开工与签收**；但 QA 各有明确的「不作为的代价」与「盯住方式」，避免它们从「已知」退化为「遗忘」。

| # | 项 | 性质 | QA 处置 | 不作为的代价 | 盯住方式 |
| --- | --- | --- | --- | --- | --- |
| **NEW-1** | **可疑度条 Carrier α 阶梯** `SUS_FILL_ALPHA = 0.30/0.60/0.75/0.92`（spec §2.3.3，文策渊派生，**未经美术回签**） | 派生规格待回签 | **按现值全量落 H12 ⑥（严格单调）断言，不等回签**。理由：α 阶梯在数学上已可验证合规（单调 + 零新色相 + 相邻主档亮度比 ≥2.0×），QA 无须等待主观确认即可卡门。**同时列入 PT-4 由林绘澄实机回签** | 若美术后续改 α 值，H12 ⑥ 的**单调性断言仍成立**（只要新值单调），`hud_slice.gd` 结构不动 ⇒ **回归成本 = 改 4 个数字 + 重跑 H12** | H12 ⑥ 断言写成**遍历相邻档比较**而非硬编码四个数值 ⇒ 改值不改测试 |
| **OPEN-1** | **GuardState 成员命名** `CALM/SUSPICIOUS` vs 主理人口述 `PATROL/INVESTIGATE`（int 值域 0/1/2 已完全一致） | 命名待一句话确认 | **QA 一律断言 int 值域，绝不断言成员名字符串**。H1 ② 明确要求 `typeof(old)==TYPE_INT`。⇒ **无论后续是否改名，全部 18 钩子零改动** | 若改名，影响面为 1 处枚举 + 4 处文档（`patrol-ai` §2/§3、`system-breakdown` §2.3、`art-bible` §4.1、`sprint1-stories`），**测试侧零影响** | 在 H1 注释中写明「本用例对成员命名不敏感，仅锁 int 值域（OPEN-1）」 |
| **B-1** | **DECOY 声圈平衡**：半程单次脉冲 `15×0.5=7.5` 点 < `THR_SUSP(25)`，诱饵可能失效 | 平衡风险（属 E06-S4 / Batch D） | **Batch C 不加任何 DECOY 专属断言**（`KS_DECOY` 属 Tier2 可调参，spec 明令不在本批硬编码）。**登记为 PT-6，Batch D 复验**。QA 要求 H18 的断言**只锁通用公式** `ΔS == KS × falloff`，**不锁特定 source** ⇒ Batch D 若加 `source==DECOY` 特判，H18 **不需改写** | 若 Batch D 遗忘，诱饵机制失效 ⇒ **损支柱三（自主掌控 / 诱饵=主动解法）** | 在 Batch D QA 计划中建 **PT-6** 前置项；H18 注释标注「通用公式，DECOY 特判见 B-1 / Batch D」 |
| **E13** | **多层关卡 3D 欧氏距离**会因垂直高差衰减（MVP 单层无影响） | 已知限制 | **Batch C 不做任何多层测试**（MVP 单层，无被测对象）。QA 要求**在 H18 用例内加一行注释**记录该限制 + 指向 Sprint 2 的「分层判定 + 水平距离」改法 | Sprint 2 引入多层时，守卫可能「听不见楼上/楼下」或「隔层听见」，**且无测试会报警** | H18 注释锚点 + 列入 §2.3「覆盖缺口自查」表，随 Sprint 2 交接清单转出 |
| **DOC-1 / DOC-2** | DOC-1：`sprint1-stories.md` E03-S5 举例「SNEAK+MOSS **2.5**」应为 **1.25**（代码/GDD/`test_step_commit.gd:176` 均为 1.25）<br>DOC-2：`control-manifest` / `art-bible` / `accessibility-matrix` 中 `#7A2E2E` 表述（语义正确，讲品牌通则，非 HUD 边框误用） | 陈述性偏差 | **判 S3，Batch C 不动**。DOC-1 的**代码侧真相已被 `test_step_commit.gd:176` 锁死**（该用例断言 1.25 且当前绿）⇒ **测试即防线，文档偏差无法回流污染实现**。DOC-2 语义本就正确，仅建议补注「HUD 落地色见 `hud-a11y-signature.md`」 | 新人读 Story 举例可能误实现 2.5 —— **但会被现有测试立即拦下** ⇒ 风险已被测试吸收 | 已有测试即防线，无需新增钩子。Batch D 顺手 Edit |

> **QA 对这 5 项的统一立场**：**全部「照现状实现、按现状卡门」，无一需要等待确认。** 关键设计是——**让测试对这些未决项不敏感**（NEW-1 测单调而非测数值、OPEN-1 测 int 而非测名、B-1/E13 测通用公式而非特例）。这样无论后续如何裁决，**18 钩子零返工**。这是把「未决」的成本控制在**改常量**而非**改测试**的做法。

---

## 7. 执行清单（供工程逐步勾选）

> 对齐 spec §9.1 的 12 步 + §9.4 的 5 个检查点，**叠加本文的 QA 门**。

| 步 | 内容 | 钩子 | QA 门（本文新增） |
| --- | --- | --- | --- |
| **前置** | 基线捕获 | — | 实跑 §4.1，确认 **7/59 无 Failing 行**。**≠ 则停工报主理人** |
| **0-a** | D6+D8 契约收口 | — | 先跑 **PRE-1**（§4.2）；`test_event_bus.gd` **`:65` 与 `:67` 两处 emit 桩都要改**（**N-5**） |
| **0-b** | D7 色板 `hud_colors.gd` | — | 纯常量 + WCAG 纯函数，headless 安全；确认可被 `preload` |
| **1** | E08-S1 五态 FSM | H1 | 抖动防护（≤2 次）是本步真正验收点 |
| **2** | E08-S2 结算核 ★ | H2 H3 | **CP-1**：显式断言「声音项不乘 dt」；E1–E6 逐条有断言 |
| **3** | E08-S3 10Hz | H4 | `after_each` 复位 `Engine.time_scale=1.0`（flaky 防护） |
| **4** | E08-S4 软失败 | H5 H6 | H5 改写后**删除 `ExposureGuardStub`** |
| **5** | E08-S5 A* seam | H7 | 四步计数**全做**，缺一判 INCOMPLETE |
| **6** | E06-S5 声脉冲 | H18 | 用**两个不同 dt** 验证同一 ΔS（唯一有效的「不乘 dt」证明） |
| **7** | E08-S8 姿态 | H11 | 反向断言「不含 `#`」 |
| **8** | E08-S6 四信号 + **地雷 ②** | H8 H9 H10 | **CP-2**：H10 四条断言全做，含**反向**（移出半径） |
| **9** | E09-S3 世界编排 | H15 | 断言 `false` 回落与 `true` 同等重要 |
| **10** | E09-S4 charges | H16 | 双编码分两条断言 |
| **11** | E09-S2 + **地雷 ①③** | H12 H13 H14 | **CP-3**：同提交内改写 **N-3 + N-4 两条**用例；**N-6** 报主理人裁决；L3-e 静态 grep 0 命中 |
| **12** | E09-S6 暴露 UI + **地雷 ③** | H17 | 边框正反各一条断言 |
| **批末** | 签收 | 全部 | **CP-4**：跑 §4.4 SMOKE-2；过 **G1–G5** 五门；连跑 3 次确认无 flaky |

---

## 8. 交付摘要

| 项 | 内容 |
| --- | --- |
| **总判定** | **CONCERNS（无硬阻塞）** |
| **覆盖矩阵** | 18/18 钩子映射完成（单元 15 · 集成 3）+ 6 项 Playtest 签收 |
| **三地雷** | 全部给出**反向断言**验证方案（L1 六项 / L2 七项 / L3 七项检查） |
| **新发现规格缺口** | **4 项**：N-4（S1，CI 红）· N-5（S1，CI 红）· **N-6（S1，地雷 ① 实际未闭合）** · N-7（S2，CI 门盲区） |
| **基线** | Scripts **7** / Passing **59** / 无 Failing 行（静态实测推导，**未跑 GUT**） |
| **预期终态** | Scripts **8** / Passing **75** |
| **签收门** | **G1** summary 可解析 ∧ **G2** 无 `[Failed]` 且无 `Failing ≥1`（**缺失失败行 = 通过**）∧ **G3** 8/75 ∧ **G4** 无 `[Risky]` ∧ **G5** 三地雷反向断言全绿 |
| **待主理人裁决** | **1 项**：N-6 bootstrap 影子写入方是否在本批删除（属越界改动） |
| **落盘路径** | `production/sprints/batchc-qa-plan.md` |

---

*Batch C QA 计划 v1.0 完成。18 钩子全覆盖、三地雷全部配备反向断言、签收门五道 fail-closed。**本文未运行 GUT**（引擎侧持有 Godot 二进制），基线 7/59 为静态实测推导，与 CI Run #30 记录吻合。最重要的一条：**N-6 —— 删掉 HUD 的 `_on_vision_stimulus` 并不能闭合地雷 ①，因为 `sprint0_bootstrap.gd` 仍从合法信道注入假可疑度，而单测永远看不见它。** —— 严守真*
