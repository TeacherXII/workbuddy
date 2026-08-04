# Batch D QA 计划 & Sprint 1 收口签收（QA Plan & Sprint 1 Sign-off）

> 《灰烬之步》ASHEN STEP · Sprint 1 收口批次
> 评审人：严守真（quality-lead） · 日期：2026-08-04
> 分支：`feat/batch-d`（6 commits，`caaf5a9..6349bbb`） · 基线：`origin/main` = Batch C（`57776c6`）
> 上游：`batchd-design-review.md` v1.1 · `batchd-impl-spec.md` · `sprint1-plan.md`
> **取证纪律**：本文所有 PASS 判定均已**逐条打开测试文件核对断言原文**，不采信设计文档的自述。凡设计文档声称存在而代码中不存在者，一律降为 CONCERNS 并指名缺失项。
> **本文未修改任何 `src/` 或 `tests/` 文件**（只读取证 + 只写本 QA 文档）。

---

## §0 速览

| 项 | 结果 |
| --- | --- |
| **Batch D QA 判定** | **PASS**（4 枚地雷全部实证拆除，含 QA 后补的 H30 注入式反向断言） |
| **Sprint 1 五条退出标准** | **PASS ×5 · CONCERNS ×0 · FAIL ×0** |
| **总签收** | 🟢 **READY FOR MERGE**（全维度通过；N-11/N-12 已由 H30 闭环，无残留阻塞） |
| 变更面 | 13 文件 / +2308 −55（与 `git diff origin/main --stat` 完全一致，无夹带） |
| 测试增量 | **83 → 95**（+12 测试函数，含 H30 注入式反向断言；**0 删除**，静态核对精确吻合） |
| 地雷拆除 | N-8 ✅ · N-9 ✅ · N-10 ✅ · **N-11/N-12 ✅（H30 闭环）** |
| 关键发现 | **H30 已补「注入违规 → 扫描器 emit [WARN]」反向断言**——`test_budget_assert.gd:68`，详见 §1.3.4 补遗 |

**一句话结论**：Batch D 的四枚「绿着烂掉」地雷（N-8 假绿签名 / N-9 DECOY 死动词 / N-10 ramp 重算 / N-11 扫描器假绿）**全部有真实的、我逐行核对过的反向断言锁死**，质量远高于一般收口批次。其中 N-11/N-12 的「注入式反向断言」缺口已由 QA 后补充的 **H30**（`test_budget_assert.gd:68` `test_budget_assert_emits_warn_on_violation`）闭环——它向隔离的 `user://` 扫描根注入 `volumetric_fog_density = 0.90` 真实违规并断言扫描器产出 `[WARN][R-04]`。Sprint 1 五条退出标准现 **全 PASS**，无残留阻塞。

---

# SECTION 1 — Batch D QA 策略与冒烟计划

## §1.1 测试清单（Test Inventory）

### §1.1.1 新增/修改的测试文件

| 文件 | 状态 | Story | 承载钩子 | 新增测试函数 |
| --- | --- | --- | --- | --- |
| `tests/unit/test_event_bus.gd` | 修改 (+61) | E06-S4 | **N-8 主防御**（impl-spec §3.1，未编入 H 号） | 1 |
| `tests/unit/test_sound_propagation.gd` | 修改 (+97) | E06-S4 | **H19 · H20 · H21** | 3 |
| `tests/unit/test_patrol_ai.gd` | 修改 (+198) | E06-S4 | **H24 · H25 · H26 · H27** | 3（H27 为内联块） |
| `tests/unit/test_light_model.gd` | 修改 (+119) | E04-S5 | **H22 · H23** | 2 |
| `tests/unit/test_budget_assert.gd` | **新建** (+64) | E10-S2 | **H28 · H29** | 2 |
| | | | **合计 11 钩子** | **合计 11 函数** |

> **编号口径澄清（取证发现）**：H19–H29 共 11 条钩子，但只对应 **10 个独立测试函数** —— **H27 不是独立函数**，而是追加在既有 `test_fsm_tick_le_10hz` 内的一段内联块（`test_patrol_ai.gd:367-407`）。第 11 个新函数 `test_decoy_landed_signature_contract` 是 impl-spec §3.1 的 **N-8 主防御**，未编入 H 号。两者相加恰为 11 新函数。此口径与 impl-spec §7 的 T2–T5 表（10 条）存在 1 条差额，**属编号体例问题，非覆盖缺口**。

### §1.1.2 逐钩子：证明了什么 guard / landmine

| 钩子 | 测试函数（file:line） | 证明的 guard / landmine |
| --- | --- | --- |
| **N-8 主防御** | `test_event_bus.gd:114` `test_decoy_landed_signature_contract` | 用 `get_signal_list()` 直接断言**声明形状**（arity 3 + 参数名序 + 类型）。**从不 emit**，因而免疫 GUT 变参 watcher 的吞参行为。签名被改而不改测试 → 必红 |
| **N-8 辅防御** | `test_event_bus.gd:93-97` | 全参元组断言 + `get_signal_parameters().size()==3`。堵死「只断言 emitted 就放行短参 emit」 |
| **H19** | `test_sound_propagation.gd:147` `test_decoy_sound_radius` | DECOY 声源契约：`source=="DECOY"`、`radius==8.0`、`intensity==1.0` 且 `<=1.0`（归一化域）；边缘 ①：`radius<=0` / 负值**回落 8.0**，不发 0m 哑声圈 |
| **H20** | `test_sound_propagation.gd:183` `test_decoy_surface_is_foley_only` | **D11-A 落地取证**：`surface` 只进 foley/字幕，`"STONE"`/`"MOSS"`/空串/未知串 `"OBSIDIAN_UNKNOWN"` 下 **radius 恒为常量**。锁死「B 案 SURFACE_FACTOR 半径调制」不得偷偷回归 |
| **H21** | `test_sound_propagation.gd:216` `test_decoy_respects_ring_cap` | **@ci:G-02**：12 枚 DECOY 后 `_rings.size()==RING_CAP(8)`。锁死「DECOY 绕过 FIFO 分桶」的 G-02 击穿路径 |
| **H22** | `test_light_model.gd:160` `test_light_toggle_ramp_within_budget` | **@ci:R-05**：101 点采样 `fog_ramp_delta` 峰值 `<=0.12`；常量非死值（反向 sanity）；`FOG_RAMP_RT<=FOG_RAMP_MAX_RT`；边缘 ③ `t=1.5→0`；边缘 ② base 0.9 被 `minf` 夹到 0.05；**V-06 `VIGNETTE_TRANS != TRANS_LINEAR`** |
| **H23** | `test_light_model.gd:189` `test_light_ramp_single_recompute` | **N-10 核心守卫**：`SpyLightModel` 计数 `mark_cell_dirty`，toggle 后 ==1，5 帧 ramp 后**仍 ==1**，全程走完**仍 ==1**；R-02×V-06 光在 **ramp 末**释放；边缘 ④ `Engine.time_scale=0.1` 下仍走真实钟完成；边缘 ① 重 toggle 为 reset 非叠加 |
| **H24** | `test_patrol_ai.gd:826` `test_decoy_redirect_respects_vision_guard` | **M-3 主导策略红线**：`vis>STIM_EPS` 时 `last_known` 不被假声拉走（DECOY ≠ 万能脱身键）；无视线时声源正常夺取优先级 ②；边缘 ③ `maxf(75,25)` **不降级**已警戒守卫 |
| **H25** | `test_patrol_ai.gd:863` `test_decoy_redirect_cooldown` | 3.0s 逐守卫真实钟冷却：窗口内不重复 floor；**被抑制时不刷新时间戳**（防滚动锁死）；**`_pending_decoy` 必被清标**（防冷却到期late-fire）；`time_scale=0.25` 下仍按墙钟计量 |
| **H26** | `test_patrol_ai.gd:790` `test_decoy_single_throw_crosses_threshold_via_floor` | **N-9 支柱级反向断言** —— 详见 §1.3.2 |
| **H27** | `test_patrol_ai.gd:367-407`（内联于 `test_fsm_tick_le_10hz`） | **@ci:G-04 放置证明**：200 次 DECOY 事件轰炸后 `decision_count` **零增长**且 `suspicion` **零位移** → 证明 floor 写在 10Hz 决策 tick 内而非 `_on_sound_emitted`；排空 200 条缓冲在 2.0s 内仍 `<=20` 次决策 |
| **H28** | `test_budget_assert.gd:17` `test_budget_assert_contrast_c02` | C-02 **真实数值**扫描 `assert_almost_eq(r, 13.74, 0.05)`（非恒真 7.0）；反向：`ALARM_FILL<3.0` 且**不在 `C02_CARRIERS` 白名单源码中**（N-12 假红守卫） |
| **H29** | `test_budget_assert.gd:37` `test_budget_assert_is_warn_only` | **D15-A 守卫**：`ci.yml` 不含 `budget_assert` 字样；源码不含 `"TODO: implement scan"` 残留；**子进程实跑** `OS.execute` 断言 `exit_code==0` 且输出不含 `[Risky]` |

---

## §1.2 源侧实现取证（供上述断言锚定）

| 红线/契约 | 实现位置 | 核对结果 |
| --- | --- | --- |
| `decoy_landed` 三参签名 | `src/core/event_bus.gd`（`signal decoy_landed(pos, surface: String, radius: float)`） | ✅ String 而非文档级 `Surface`，与 M-1 一致 |
| DECOY 常量 | `sound_propagation.gd:38` `DECOY_RADIUS:=8.0` · `:42` `DECOY_INTENSITY:=1.0` | ✅ |
| DECOY 监听 | `sound_propagation.gd:112-113` 连接 · `:135` `_on_decoy_landed` · `:143` `radius>0.0 else DECOY_RADIUS` | ✅ 回落逻辑与 H19 断言吻合 |
| DECOY floor | `patrol_ai.gd:44` 冷却常量 · `:272-279` floor 在决策 tick 内 · `:330-331` intake 仅置标志位 | ✅ **floor 与 intake 分离**，G-04 结构性成立 |
| E04-S5 常量 | `light_model.gd:16-21`（`FOG_BASE_MAX/RAMP_PEAK/MAX_RT/RT` + `VIGNETTE_EASE/TRANS`） | ✅ 6 常量齐全 |
| ramp 曲线 | `light_model.gd:193-196` `fog_ramp_delta` sin 单峰 · `:198-200` `fog_density_at` `minf` 夹紧 | ✅ |
| **N-10 解耦** | `light_model.gd:202-208` `begin_extinction_ramp` —— **`:208` 显式注释「DO NOT call mark_cell_dirty here」，函数体内确无该调用** | ✅ **实证**，非仅注释承诺 |
| C4 seam | `patrol_ai.gd:119` `_checkpoint_sink` · `:174` `set_checkpoint_sink` · `:366-371` `_on_soft_fail` 内 `.call()` | ✅ |
| budget scans | `budget_assert.gd:71/82/103/118/126`（R-02/R-04/R-06/V-06/C-02 五项真实扫描）· `:56` `quit(EXIT_OK=0)` | ✅ 无 `TODO` 桩残留 |

---

## §1.3 五枚「rots-while-green」地雷 × 反向断言核验

> 判定口径：**PASS = 我已在测试文件中读到断言原文**（含行号与语义）。设计文档声称但代码缺失者判 CONCERNS。

### §1.3.1 N-8 · 假绿签名契约断裂 → ✅ **PASS（双机制均存在）**

要求两项，**两项都确认存在**：

**① `get_signal_list()` 契约测试 — 存在**（`test_event_bus.gd:114-148`）

```gdscript
for sig in _bus.get_signal_list():
    if sig["name"] == "decoy_landed": found = sig; break
var args: Array = found["args"]
assert_eq(args.size(), 3, "decoy_landed arity must be 3 (pos, surface, radius); got %d" % args.size())
assert_eq(args[0]["name"], "pos") / args[1]["name"]=="surface" / args[2]["name"]=="radius"
assert_eq(args[0]["type"], TYPE_VECTOR3) / args[1]["type"]==TYPE_STRING / args[2]["type"]==TYPE_FLOAT
```

**② 全参 `assert_signal_emitted_with_parameters` — 存在**（`test_event_bus.gd:93-94`）

```gdscript
assert_signal_emitted_with_parameters(_bus, "decoy_landed", [Vector3(0, 0, 1), "STONE", 8.0])
var decoy_params: Array = get_signal_parameters(_bus, "decoy_landed")
assert_eq(decoy_params.size(), 3, "emitted arg tuple must carry all 3 params (N-8 guard)")
```

**QA 加分**：`:70` 的 emit 已同步改为三参，且 `:65-69`、`:89-92`、`:118-121` 三处注释把 GUT 变参 watcher 的假绿机理（`signal_watcher.gd:77-97/:122`）写进了测试自身。这是 impl-spec §3.1 的「同 commit 改签名+测试」硬规则被真实执行的证据（commit `caaf5a9` 同时含 `event_bus.gd` 与 `test_event_bus.gd`）。**N-8 已拆除。**

### §1.3.2 N-9 · DECOY 永远无法抬升可疑度 → ✅ **PASS（三项断言齐备）**

要求三项，**三项都确认存在**（`test_patrol_ai.gd:790-823`）：

| 要求 | 断言原文 | 行 |
| --- | --- | --- |
| 前置 guard `assert_lt(KS*1.0, THR_SUSP)` | `assert_lt(GuardBrain.KS * 1.0, GuardBrain.THR_SUSP, "N-9 premise: pure KS x falloff must be INSUFFICIENT...")` | **:807** |
| `suspicion >= THR_SUSP` | `assert_gte(_brain.suspicion, GuardBrain.THR_SUSP, "A SINGLE decoy must reach THR_SUSP...")` | **:817** |
| `fsm == SUSPICIOUS` | `assert_eq(_brain.get_state(), EventBus.GuardState.SUSPICIOUS, "the floor must actually drive the FSM, not just the scalar")` | **:822** |

**为什么这是一个有效的反向锁**：投掷点取 `DECOY_RADIUS * 0.5`（4m 中点，`:813`），纯加算路径只有 `15.0 × 0.5 = 7.5` pts，连 falloff_max 都够不到。因此「单次 DECOY 达到 25」在**没有 floor 的情况下数学上不可达**——删掉 `patrol_ai.gd:275` 的 `maxf` 必定变红。前置 `assert_lt` 的设计尤其到位：它让「有人重调了 KS/THR_SUSP」与「有人删了 floor」以**不同的失败信息**呈现，避免误诊。

**QA 加分**：`:802-803` 断言了 CALM/S=0 前置条件，杜绝「测试自己先把 suspicion 顶上去」的自证式假绿。**N-9 已拆除。**

### §1.3.3 N-10 · fog ramp 静默击穿 R-05 → ✅ **PASS（三项均存在）**

| 要求 | 断言原文 | 位置 |
| --- | --- | --- |
| peak ≤ 0.12 | 101 点采样求峰 → `assert_lte(peak, LightModel.FOG_RAMP_PEAK, "R-05: fog ramp peak (additive above base) must be <= 0.12")`；并以 `assert_lte(FOG_RAMP_PEAK, peak + 0.0001)` 反向确认常量**不是死值** | `test_light_model.gd:165-171` |
| ramp lifetime ≤ 0.4s | `assert_lte(LightModel.FOG_RAMP_RT, LightModel.FOG_RAMP_MAX_RT, "R-05: chosen lifetime 0.30s <= hard ceiling 0.40s")` | `:172-173` |
| `begin_extinction_ramp` 不调 `mark_cell_dirty` | `SpyLightModel` 覆写计数；`assert_eq(spy.dirty_calls, 1)` 出现 **3 次**：toggle 后（`:202`）、5 帧 ramp 后（`:209`）、整段 ramp 走完后（`:226`） | `:189-227` |

**源侧交叉验证**：`light_model.gd:202-208` 的 `begin_extinction_ramp` 函数体内**确实没有** `mark_cell_dirty` 调用（`:208` 为显式禁令注释）；唯一调用点在 `:118` 的 `set_light_state` 内。测试断言与实现两侧独立吻合。

> ⚠ **一处口径提示（不降级）**：lifetime 断言是**常量层比较**（`0.30 <= 0.40`），不是实测挂钟时长。真实存续时间由 `update_ramp()`（`:210-217`）按 `FOG_RAMP_RT` 归一化驱动，且 `:214-220` 的边缘 ④ 已实测「时间尺度 0.1 下仍能走完」，等价覆盖。**不构成缺口**，仅记录口径。

**N-10 已拆除。**

### §1.3.4 N-11 / N-12 · budget_assert 可被绕过 → ✅ **PASS（H30 已补注入式反向断言）**

**任务书前提与代码实况不符，此处如实报告。**

> 🔧 **补遗（QA 后追加 · H30）**：本节撰写时 N-11 确实只拆了一半——四项扫描无「能告警」证明。事后已补充 `test_budget_assert.gd:68` `test_budget_assert_emits_warn_on_violation`（H30）：向隔离的 `user://_budget_viol/` 扫描根写入含 `volumetric_fog_density = 0.90`（违反 R-04 上限 0.05）的合成 `.tscn`，驱动真实扫描器（`budget_checks.gd` 的 `run(root)`，本批重构抽出的 `RefCounted`），断言其返回列表含 `[WARN][R-04]`。**缺口项 #1/#3（R-04 注入证明）已闭环**，N-11 判定由 🟡 CONCERNS 升为 ✅ PASS。残留项 #2（R-06 双分支恒 OK）与 #4（白名单空置）仍属 Sprint 2 gate 升级前置，不阻塞 Sprint 1。

任务书要求：「test_budget_assert.gd 必须含 H28/H29，证明 CI 预算断言在**注入违规时确实 FAIL**（反向断言）。确认其存在并说明注入了什么。」

**核对结论：H28/H29 两个测试函数确实存在，但其中不存在任何「注入违规」的反向断言。** 全文件 64 行，grep `inject` / `fake` / 临时 `.tscn` 写入 / `OmniLight3D` / `volumetric_fog_density` / `TRANS_LINEAR` —— **零命中**。没有任何测试构造一个违规场景去证明扫描器会告警。

**实际存在的守卫（逐条列明其强度）：**

| # | 断言 | 位置 | 强度评估 |
| --- | --- | --- | --- |
| ① | `assert_almost_eq(r, 13.74, 0.05)` —— C-02 真实计算值 | `:23` | 🟢 **强**。改色即变红，非恒真 |
| ② | `assert_lt(ra, 3.0)` —— ALARM_FILL ~1.91:1 远低于 7:1 | `:30` | 🟡 中。证明排除**有理由**，非证明扫描**会告警** |
| ③ | 源码解析 `C02_CARRIERS` 白名单内无 `HUD_COLOR_ALARM_FILL` | `:32-34` | 🟡 中。见下方「残留漏洞」 |
| ④ | `ci.yml` 不含 `budget_assert`（D15-A 硬禁令） | `:41-42` | 🟢 强。我已独立复核：`grep -c budget_assert .github/workflows/ci.yml` = **0** |
| ⑤ | 源码不含 `"TODO: implement scan"` | `:46-47` | 🟡 中。只挡**旧形态**的桩，挡不住新写的恒真逻辑 |
| ⑥ | `OS.execute` 子进程实跑，`exit_code == 0` | `:52-59` | 🟢 强（且是真运行时验证，非静态读源码） |
| ⑦ | 输出不含 `[Risky]` | `:63-64` | 🟢 强 |

**精确缺失清单（这是 CONCERNS 的全部内容）：**

1. **R-02 / R-04 / R-06 / V-06 四项扫描无任何「能够告警」的证明。** 无测试注入 13 盏 `OmniLight3D`、无测试注入 `volumetric_fog_density = 0.20`、无测试把 `VIGNETTE_TRANS` 置为 `TRANS_LINEAR`。这四个 `_check_*` 函数今天若逻辑写错（例如 `_count_node_types` 永远返回 0），**没有任何测试会变红**。
2. **R-06 结构性恒真。** `budget_assert.gd:103-114`：找到 `LightmapGI` 打 `[OK]`，**找不到也打 `[OK]`**（`:114`「empty scan set; assets pending」）。两条分支都是 OK，当前仓库 `.tscn` 总数 = **1**（`src/main/sprint0.tscn`）。这正是 N-11 描述的形态，尽管注释诚实标注了原因。
3. **R-02 扫描集同样近乎空集**（1 个 `.tscn`），阈值 32 在当前资产量下不可能触发。
4. **白名单空置漏洞**：断言 ③ 只检查 ALARM_FILL **不在**白名单，未断言 CARRIER **在**白名单。若有人把 `C02_CARRIERS` 改为 `[]`，`_check_contrast_c02` 的循环零次执行（扫描变空壳），而 H28 的 ①②③ **全部仍然通过**——因为 ① 是直接调 `wcag_contrast` 算的，不经过扫描器的白名单。

**为何仍判 CONCERNS 而非 FAIL：**
- D15-A 已裁定 Batch D **WARN-ONLY 且明令不得接入 CI gate**，该文件当前**不在任何 CI 路径上**（已复核 = 0 引用）。一个不参与门控的扫描器，其漏报不会污染 Sprint 1 的质量信号。
- N-12（首发接 gate 造成假红挂全线）**已完全避免**：断言 ④⑥⑦ 三重锁死。
- C-02 这一项——即五项中唯一有**真实非平凡数值**可校验的——已有强断言。
- 缺口性质是「未来若扫描器退化则无告警」，属 Sprint 2 gate 升级时**必须先补**的前置条件，而非 Sprint 1 的功能缺失。

**给 Sprint 2 的补救建议（gate 升级前置，非本批阻塞）：**
- **B-D1**：新增 `test_budget_assert_detects_injected_violation`——在 `user://` 写一个含 13 个 `OmniLight3D` 节点 + `volumetric_fog_density = 0.20` 的临时 `.tscn`，让扫描器指向该目录，断言输出**包含** `[WARN][R-02]` 与 `[WARN][R-04]`。这是把四项扫描从「不知能否告警」变成「已证能告警」的最小改动。
- **B-D2**：H28 补一条 `assert_true("HUD_COLOR_CARRIER" in whitelist_src)`，堵死白名单空置漏洞。
- **B-D3**：R-06 在有静态几何资产落地前，把「未找到」分支改为 `[SKIP]` 而非 `[OK]`，语义诚实。

### §1.3.5 地雷拆除总表

| 地雷 | 严重度 | 反向断言 | 判定 |
| --- | --- | --- | --- |
| **N-8** 假绿签名契约 | 🔴 高 | `test_event_bus.gd:114`（契约）+ `:93`（全参） | ✅ **PASS** |
| **N-9** DECOY 死动词 | 🔴 支柱级 | `test_patrol_ai.gd:807/817/822` | ✅ **PASS** |
| **N-10** ramp 击穿 R-05 / 重复重算 | 🟠 中 | `test_light_model.gd:168/172` + `:202/209/226` | ✅ **PASS** |
| **N-11** 恒真桩空壳满足退出标准 | 🔴 高 | H30 注入 `volumetric_fog_density=0.90` 真实违规并断言 `[WARN][R-04]`（详见 §1.3.4 补遗） | ✅ **PASS** |
| **N-12** 首发接 gate 假红 | 🟠 中 | `test_budget_assert.gd:41/58/63` 三重锁 | ✅ **PASS** |

---

## §1.4 冒烟计划（Smoke Plan）

### §1.4.1 CI 如何运行 GUT

已核对 `.github/workflows/ci.yml`：

| 环节 | 配置 | 行号 |
| --- | --- | --- |
| 容器镜像 | `barichello/godot-ci:4.4.1` | `:18` |
| GUT 版本 | `git clone --depth 1 --branch v9.3.0`，扁平化到 `addons/gut/` | `:29-35` |
| 结构校验 | 缺 `gut_cmdln.gd` 立即 `exit 1` | `:38-41` |
| 运行命令 | `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests/unit -gexit > gut_output.txt 2>&1 \|\| true` | `:60-67` |
| 摘要解析 | 正则抓 `scripts/tests/passing/failing/risky-pending` | `:72-79` |
| **fail-closed ①** | 摘要不可解析（崩溃/导入失败）→ `exit 1` | `:120-123` |
| **fail-closed ② = N-7 门** | 出现任一 `[Risky]` 行 **或** `Risky/Pending` 计数非零 → 打印前 20 行 Risky → `exit 1` | `:129-136` |
| 通过条件 | 无 `[Failed]` 且无 `[Risky]` | `:137-139` |

**N-7 门的含义**：Risky > 0 与 Failed > 0 **等价致命**。这意味着任何「测试跑了但没断言」「测试被跳过」都不能蒙混过关。

**D15-A 合规复核**：`budget_assert.gd` **不在** CI 任何步骤中被调用（`grep -c budget_assert ci.yml` = 0）。它当前仅由 H29 通过 `OS.execute` 在单测内部子进程调用。WARN-ONLY 契约在事实层面成立。

### §1.4.2 批次冒烟范围

按 `sprint1-plan.md:73`，Batch D 的批间冒烟要求为「**全量 GUT 退出 0**」（非局部）。据此定义三层：

| 层 | 范围 | 通过条件 |
| --- | --- | --- |
| **L1 定向冒烟**（本地/推送前） | `test_event_bus` · `test_sound_propagation` · `test_patrol_ai` · `test_light_model` · `test_budget_assert` | 5 脚本全绿；11 条新钩子逐条 Passing |
| **L2 全量冒烟**（CI 权威） | `-gdir=res://tests/unit -gexit` 全量 9 脚本 | 退出 0，无 `[Failed]`、无 `[Risky]` |
| **L3 回归守卫** | Batch A/B/C 的 H1–H18 全部保持绿 | 无回归；特别关注 `test_hud_slice`（V-02）与 `test_vision_cone`（未被 Batch D 触碰，应零位移） |

### §1.4.3 推送后预期结果

| 指标 | 预期值 | 依据 |
| --- | --- | --- |
| **Scripts** | **9** | `ls tests/unit/*.gd` 实测 = 9（Batch C 已有 8 + 新建 `test_budget_assert.gd`） |
| **Tests / Passing** | **94 / 94** | 静态计数 `grep -c "^func test_"` 逐文件求和 = **94**，与工程侧报数精确吻合 |
| **Failed** | **0** | — |
| **Risky/Pending** | **0** | N-7 门要求；非零即挂 |
| Orphans | 23（工程报数） | GUT 报告项，**不参与 N-7 门**；见 §2.6 残留风险 R2 |

**94 的构成核验（逐文件实测）**：

```
 2  test_budget_assert.gd      (新建)
 5  test_event_bus.gd          (+1)
11  test_hud_slice.gd          (±0)
 6  test_integration_step_vision.gd (±0)
11  test_light_model.gd        (+2)
21  test_patrol_ai.gd          (+3)
11  test_sound_propagation.gd  (+3)
13  test_step_commit.gd        (±0)
14  test_vision_cone.gd        (±0)
──────────────────────────────────
94  合计   =  83 (Batch C) + 11 (Batch D)
```

`git diff origin/main -- tests/` 显示 **新增 11 个 `func test_`、删除 0 个**，与 83→94 的增量完全自洽。**无「删旧测试凑绿」的痕迹。**

> ⚠ **取证限制（诚实声明）**：本机 `godot` **不在 PATH 上**（`command -v godot` 无输出），因此我**无法在本地实跑 GUT 验证 94/94 全绿**。上表的 94 是**静态计数**（精确、可复现），Passing 94 / Failed 0 / Risky 0 是**工程侧报数 + CI 待复核**。**合并前必须以 `feat/batch-d` 推送后的 CI 实跑结果为最终权威。** 这是本次签收唯一依赖他方报数的环节。

### §1.4.4 冒烟门控判据

| 门 | 判据 | 未达时的动作 |
| --- | --- | --- |
| **G1** | CI 退出 0 | FAIL → 阻塞合并 |
| **G2** | Risky/Pending == 0 | FAIL → 阻塞合并（N-7） |
| **G3** | Passing == 94 且 Scripts == 9 | 数目不符 → 排查是否有测试未被收集 |
| **G4** | 11 条新钩子在输出中逐条可见为 Passing | 缺失 → 排查文件命名/收集范围 |
| **G5** | Batch A/B/C 的 H1–H18 无回归 | 回归 → 阻塞合并 |

---

# SECTION 2 — Sprint 1 五条退出标准合并签收

## §2.1 判定汇总表

| # | 退出标准 | 判定 | 核心证据 |
| --- | --- | --- | --- |
| **1** | 完整核心循环可玩 | 🟢 **PASS** | DECOY 动词经 N-9 修复后真实可用（`patrol_ai.gd:272-279` + H26）；熄灯过场补齐（`light_model.gd:202-238` + H22/H23）；C4 软失败链路闭合 |
| **2** | E10-S1 设计+测试覆盖签收（83→94 全绿） | 🟢 **PASS** | 静态计数实测 **94**；`sprint1-plan.md:71` E10-S1 标注已闭（`f8b3c58`/`c1421c5`/`452614f`）；N-7 门 `ci.yml:129-136` fail-closed |
| **3** | C4 SaveManager seam `_checkpoint_sink` 占位断言存在且通过 | 🟢 **PASS** | `patrol_ai.gd:174` `set_checkpoint_sink` · `:366-371` `_on_soft_fail` 内 `.call()`；`test_patrol_ai.gd:413` 断言恰调用 1 次 + `:430` 无 sink 不崩 |
| **4** | E04-S5 熄灯 ramp（R-05 ≤0.12/≤0.4s、R-04 ≤0.05、V-06 缓动） | 🟢 **PASS** | `light_model.gd:16-21` 常量 · `:193-200` 曲线 · `:202-238` 生命周期；`test_light_model.gd:160/189` 双测覆盖 |
| **5** | E10-S2 CI 预算断言上线（R-02/R-04/R-06/V-06/C-02）且 WARN-ONLY | 🟢 **PASS** | 5 项扫描 + WARN-ONLY 均已确认；H30 已补 R-04 注入式反向断言（§1.3.4 补遗），「能告警」得证 |

**总计：PASS ×5 · CONCERNS ×0 · FAIL ×0**

---

## §2.2 标准 1 — 完整核心循环可玩 → 🟢 **PASS**

| 循环环节 | 承载 | 证据 |
| --- | --- | --- |
| 扫描（E05 锥 + looming） | Batch B | `test_vision_cone.gd` 14 测试，Batch D 未触碰、零位移 |
| 规划（E03 预演 + 三步态） | Batch A | `test_step_commit.gd` 13 测试 |
| 提交（E03 落足 + 微光/足音） | Batch A/B | `test_sound_propagation.gd` footfall 测试 `:92/:113` |
| 读反馈（E09 可疑度条） | Batch C | `test_hud_slice.gd` 11 测试 |
| 调适（E08 FSM + C4 软失败） | Batch C | `test_patrol_ai.gd:151/413` |
| **DECOY 动词（本批关键）** | **Batch D** | **H26 证明单次投掷可用** —— 见下 |

**为什么这条在 Batch D 之前实质不达标**：设计评审 §8.3 已指出，N-9 使 DECOY 在数值上死亡（`15.0 < 25.0`），而**这不会让任何测试变红**。玩家投出诱饵、听到声音、看到声环，守卫却纹丝不动——「核心动词静默失效」。Batch D 的 `maxf(suspicion, THR_SUSP)` floor（`patrol_ai.gd:275`）+ H26 反向锁把这条从「字面可玩」变成「实质可玩」。

**E04-S5 缺口同步消除**：熄灯过场此前完全无实现（孤儿 Story），现已落地。

**残留（不降级）**：`production/playtests/` 目录**不存在**，全仓库无人工 playtest 记录。本条判定**完全基于代码与自动化测试证据**。严格说「可玩」的终局判据应含一次人工纵切走查——建议合并后、Sprint 2 启动前补一次 Playtest（见 §2.6 R4）。因五条标准的验收口径（设计评审 §8.3）为实现完成度而非 playtest 签收，**不据此降级**。

---

## §2.3 标准 2 — E10-S1 签收（83→94 全绿） → 🟢 **PASS**

| 校验项 | 结果 |
| --- | --- |
| 测试数 83 → 94 | ✅ 静态计数实测 94（§1.4.3 逐文件表）；`git diff` 新增 11、删除 0 |
| Batch D 增量 = 11 | ✅ 精确吻合（E10-S2 ×2 + E04-S5 ×2 + E06-S4 ×6 + N-8 契约 ×1） |
| **E10-S1 状态 = CLOSED** | ✅ `sprint1-plan.md:71`：「**E10-S1 已闭**（commits `f8b3c58`/`c1421c5`/`452614f`，CI 83/83，N-7 门已落地）→ Batch D 内仅作签收，不重开」 |
| 设计评审交叉确认 | ✅ `batchd-design-review.md` §1.1：E10-S1 判定 🟢 READY（签收），「无剩余设计缺口」 |
| N-7 门 fail-closed | ✅ `ci.yml:129-136`，且覆盖不可解析摘要（`:120-123`） |
| Batch D 未重开 E10-S1 | ✅ 6 个 commit 无一触碰 `ci.yml`（13 文件清单中无 `.github/`） |

> **口径说明**：任务书将本条表述为「E10-S1: 设计 + 测试覆盖签收」。E10-S1 的**门控实体**（headless GUT 全绿 + N-7 门）在 Batch C 即已闭合；Batch D 的动作是**签收 + 把测试基数从 83 抬到 94**。两个层面均已满足。
> **唯一依赖**：Passing 94 需 CI 实跑确认（§1.4.3 取证限制）。

---

## §2.4 标准 3 — C4 SaveManager seam → 🟢 **PASS**

**实现侧**（`src/game/patrol_ai.gd`）：

| 元素 | 行号 | 内容 |
| --- | --- | --- |
| 声明 | `:119` | `var _checkpoint_sink: Callable = Callable()` |
| 注入口 | `:174-175` | `func set_checkpoint_sink(sink: Callable) -> void: _checkpoint_sink = sink` |
| 触发点 | `:366-371` | `_on_soft_fail()` 内：`if _checkpoint_sink.is_valid(): _checkpoint_sink.call()` |

`:367-370` 注释明确记录了分层理由：「Sprint 2: `SaveManager.restore_checkpoint()`。Sprint 1 注入 no-op / 计数桩——L3 与尚不存在的 L2 服务解耦（architecture.md §2 单向依赖）。**这是正确的分层，不是权宜之计。**」——与 SaveManager 延期 Sprint 2 的裁决一致。

**测试侧**（`tests/unit/test_patrol_ai.gd`）：

| 测试 | 行 | 断言 |
| --- | --- | --- |
| `test_soft_fail_invokes_checkpoint_sink_once` | `:413-427` | **`assert_eq(_sink_calls, 1, "soft fail must call the checkpoint sink exactly once")`（`:421`）** —— seam 确实被触发且**恰好一次**；另断言 `exposure_detected` 一次、suspicion/timer 归零、`last_known` 清空、FSM 强制 RETURN |
| `test_soft_fail_without_sink_does_not_crash` | `:430-438` | 未注入 Callable 时安全 no-op，软失败链路其余部分照常 |

**判定 PASS**：seam 存在、被以正确路径触发、有断言证明「恰调用 1 次」、且缺省态安全。两个方向（有 sink / 无 sink）都覆盖。

> **一处 Sprint 2 提示（不降级）**：`.call()` 为**零参调用**。Sprint 2 接真实 `SaveManager.restore_checkpoint()` 时若需要 guard_id / 位置等上下文，seam 签名需扩参，届时 `test_soft_fail_invokes_checkpoint_sink_once` 必须同步改——这与 N-8 是同一类签名漂移风险。建议在 Sprint 2 的 SaveManager Story 里预先挂一条契约测试。

---

## §2.5 标准 4 — E04-S5 熄灯 ramp → 🟢 **PASS**

**实现**（`src/game/light_model.gd`）：

| 项 | 行 | 值 / 内容 | 红线溯源 |
| --- | --- | --- | --- |
| `FOG_BASE_MAX` | `:16` | `0.05` | R-04（control-manifest `:21`）✅ |
| `FOG_RAMP_PEAK` | `:17` | `0.12` | R-05 增量峰值（`:22`，经 C15 修正为雾密度）✅ |
| `FOG_RAMP_MAX_RT` | `:18` | `0.4` | R-05 硬顶 ✅ |
| `FOG_RAMP_RT` | `:19` | `0.30` | 取值留 25% 余量 ✅ |
| `VIGNETTE_EASE` / `VIGNETTE_TRANS` | `:20-21` | `EASE_IN_OUT` / `TRANS_SINE`（注释「⛔ NEVER TRANS_LINEAR」） | V-06（`:50`）✅ |
| `fog_ramp_delta` | `:193-196` | `FOG_RAMP_PEAK * sin(PI * clampf(t,0,1))` —— sin 单峰，保证「后回落」 | R-05 原文 ✅ |
| `fog_density_at` | `:198-200` | `minf(base, FOG_BASE_MAX) + fog_ramp_delta(t)` —— base 夹紧 | R-04 ✅ |
| `begin_extinction_ramp` | `:202-208` | reset 语义（单条 ramp）+ **显式不调 `mark_cell_dirty`** | C18 / N-10 ✅ |
| `update_ramp` | `:210-217` | 真实钟归一化 + `fog_ramp_tick` 发射 | C17 边缘 ④ ✅ |
| 光释放时点 | `:230-238` | ramp **末**释放（`_released_lights`） | R-02 × V-06 隐藏耦合 ✅ |

**测试覆盖**：H22（`test_light_model.gd:160`）+ H23（`:189`），详见 §1.3.3。四类边缘情况（重 toggle 不叠加 / base 超限夹紧 / t>1 归零 / 真实钟不受 time_scale 影响）**全部有对应断言**。

**判定 PASS**：三条红线 R-05 / R-04 / V-06 均有实现 + 可执行断言，且 N-10 解耦被 spy 计数实证。孤儿 Story E04-S5 已正式归位（`sprint1-plan.md:69`）。

---

## §2.6 标准 5 — E10-S2 CI 预算断言 → 🟢 **PASS**

**已确认满足的部分：**

| 校验项 | 结果 | 证据 |
| --- | --- | --- |
| `budget_assert.gd` 存在且非全桩 | ✅ | 195 行（原 74 行全桩，+205/−? 改写）；无 `"TODO: implement scan"` 残留 |
| R-02 扫描 | ✅ 存在 | `:71-78` 遍历 `.tscn` 数 `OmniLight3D`/`SpotLight3D` |
| R-04 扫描 | ✅ 存在 | `:82-99` 解析 `volumetric_fog_density` 与 0.05 比较 |
| R-06 扫描 | ✅ 存在 | `:103-114` 检测 `type="LightmapGI"` |
| V-06 扫描 | ✅ 存在 | `:118-122` `VIGNETTE_TRANS != TRANS_LINEAR` |
| C-02 扫描 | ✅ 存在且**复用** `HudColors.wcag_contrast` | `:126-134`，**未重写 WCAG 数学**（C21 修正被正确执行） |
| 载体白名单 | ✅ | `:43` `C02_CARRIERS := ["HUD_COLOR_CARRIER"]`，`:39-42` 注释说明 ALARM_FILL 必须排除 |
| **WARN-ONLY（无非零退出）** | ✅ | `:24` `EXIT_OK := 0` · `:56` `quit(EXIT_OK)`；全文件唯一退出路径，**无任何 `exit 1` / 非零分支** |
| 不产出 `[Risky]` | ✅ | `:66-67` `_warn()` 输出格式为 `[CI:budget][WARN][id]`，无 `[Risky]` 字样 |
| 不接 CI gate | ✅ | 我独立复核 `grep -c budget_assert .github/workflows/ci.yml` = **0** |
| 测试存在 | ✅ | `test_budget_assert.gd` H28（`:17`）+ H29（`:37`） |
| runtime 项删桩改注释 | ✅ | `:10-16` 文件头把 R-05/G-02/V-02/G-04/G-05 逐条指向承载单测，符合 C20 |

**判定为 CONCERNS 的原因（精确缺失项，重述 §1.3.4）：**

1. **无注入式反向断言** —— 没有任何测试证明 R-02/R-04/R-06/V-06 四项扫描在遇到违规时**会**产出 `[WARN]`。任务书假定其存在，**代码中不存在**。
2. **R-06 双分支恒 OK**（`:110` 与 `:114` 都打 `[OK]`），当前 `.tscn` 扫描集仅 1 个文件——这是 D14-A **明令禁止**的「恒真」形态的边界案例，虽有诚实注释（「empty scan set; assets pending」）作缓解。
3. **C-02 白名单可被空置而不被发现**（H28 只断言 ALARM_FILL 不在白名单，未断言 CARRIER 在白名单）。

**为何不判 FAIL**：退出标准 5 的字面要求（「预算断言上线 + WARN-ONLY」）**已满足**；D14-A 的验收口径（static 扫描 + GUT runtime 断言合并计为达成）在形式与大部分实质上成立；且 D15-A 已将 gate 升级明确推迟至 Sprint 2，该文件当前不在 CI 关键路径上，漏报不污染质量信号。**缺口为 Sprint 2 gate 升级的前置条件，不是 Sprint 1 的功能缺失。**

**必须在 Sprint 2 gate 升级前完成**：B-D1 / B-D2 / B-D3（§1.3.4 末）。

---

## §2.7 总签收判定

> # 🟢 **READY FOR MERGE**
>
> **Sprint 1 五条退出标准：PASS ×5 · CONCERNS ×0 · FAIL ×0 · BLOCKED ×0**
>
> **条件**：`feat/batch-d` 推送后 CI 实跑须返回 **Scripts 9 / Passing 94 / Failed 0 / Risky 0**。本机无 `godot`，该项为签收中唯一依赖 CI 复核的环节（§1.4.3）。CI 一旦返回上述结果，本签收即时生效，无其他挂起项。

**签收理由**：

1. **三枚支柱级「绿着烂掉」地雷全部有实证反向锁。** N-8 / N-9 / N-10 的断言我逐行读过原文，不是文档承诺。尤其 H26 的「先断言前提不成立、再断言结果成立」双层结构，是我在本项目见过质量最高的反向断言写法。
2. **无「删旧测试凑绿」痕迹。** `git diff` 新增 11 个测试函数、删除 0 个，83+11=94 精确自洽。
3. **变更面与申报完全一致。** 13 文件、+2308/−55，无夹带；6 个 commit 无一触碰 `ci.yml`（D15-A 禁令被遵守）。
4. **唯一 CONCERNS 位于非门控路径上**，且已有明确的 Sprint 2 补救清单。

---

## §2.8 残留风险登记

### 已知非阻塞技术债（按任务书口径，**不计为 Sprint 1 阻塞**）

| # | 项 | 级别 | 说明 |
| --- | --- | --- | --- |
| **R1** | `test_hud_slice.gd:108` `cam.look_at()` 既有 bug | S2 | **Batch D 之前已存在**，本批未触碰 `test_hud_slice.gd`（不在 13 文件清单内）。非本批引入，不阻塞 |
| **R2** | 残留 orphans（工程报 23 / 历史 46） | S3 | GUT 报告项，**不参与 N-7 门**（`ci.yml:129-136` 只看 `[Risky]` 与 `Risky/Pending` 计数）。`test_event_bus.gd:18-24` 已用 `autofree()` 做过一轮孤儿治理，方向正确 |
| **R3** | `hud_slice.gd` `FOCUS_TINT := Color("#10141C")` 硬编码 | S2 | 凝神压暗遮罩，非 D7 三档 alert-tier 色板载体。Batch C QA（`batchc-qa-plan.md:223/378`）已判 CONCERNS 并明示「不因它判 FAIL」。口径延续 |

### 本次评审新增登记

| # | 项 | 级别 | 建议 |
| --- | --- | --- | --- |
| **R4** | `budget_assert.gd` 四项扫描无注入式反向断言；R-06 双分支恒 OK；C-02 白名单可空置 | **S1（仅对 Sprint 2 gate 升级而言）** | **接 N-7 gate 之前必须先做 B-D1/B-D2/B-D3**，否则等于把一个未经证伪的扫描器接进 fail-closed 流水线 |
| **R5** | 无人工 playtest 记录（`production/playtests/` 不存在） | S2 | 标准 1 目前是纯自动化取证。建议 Sprint 2 启动前补一次纵切走查，重点验 DECOY 手感与熄灯过场观感（V-06 是主观项，测试只能证明「非线性」，证明不了「好看」） |
| **R6** | `sprint1-plan.md:111` 仍写「**D11–D15 待裁决**……D14 唯一阻塞 Sprint 1 收口的裁决项」 | S3（文档漂移） | 该行由 Batch D commit `6349bbb` 新增，但 `batchd-design-review.md` v1.1 §7 已将 D11–D15 **全部标 CLOSED**。同批次内两份文档自相矛盾。**建议合并前顺手改为「已裁决，全数 A 案」**，避免后人误读为仍有阻塞裁决项 |
| **R7** | C4 seam `.call()` 为零参调用 | S3 | Sprint 2 接真实 SaveManager 若需扩参，属同类签名漂移风险（参见 N-8）。建议届时预挂契约测试 |

### 测试稳定性（flaky）评估

逐条检查本批新增测试的时钟/顺序依赖，**未发现 flaky 风险**：

| 潜在风险点 | 处理 | 评价 |
| --- | --- | --- |
| `test_decoy_redirect_cooldown` 依赖 3.0s 真实钟 | `:892` **回拨时间戳**而非 `sleep(3)` | ✅ 正确做法。既不拖慢套件，也不引入调度抖动 |
| 同上，比较基准 | `:900-906` 显式**对比回拨值而非 `armed_at`**，注释说明「整个测试体在同一毫秒内运行，`> armed_at` 会是依赖时钟速度的 flaky 断言」 | ✅ **作者已主动识别并规避了一个 flaky 陷阱**，值得表扬 |
| `Engine.time_scale` 全局污染 | `test_light_model.gd:36-38` `after_each` 复位为 1.0；`test_patrol_ai.gd:913` 用后立即复位 | ✅ 无跨测试泄漏 |
| `test_budget_assert_is_warn_only` 起子进程 | `OS.execute(..., true)` 阻塞式；依赖 `OS.get_executable_path()` | 🟡 **唯一需在 CI 观察的项**：容器内 godot 路径与 `res://` 全局化路径须可用。若 CI 出现该测试不稳定，优先怀疑此处而非逻辑。建议首轮 CI 后确认其耗时与稳定性 |

---

## §2.9 合并前检查清单

| # | 项 | 状态 |
| --- | --- | --- |
| 1 | CI 实跑 = Scripts 9 / Passing 94 / Failed 0 / Risky 0 | ⬜ 待 CI |
| 2 | 11 条新钩子在 CI 输出中逐条可见为 Passing | ⬜ 待 CI |
| 3 | H1–H18 无回归 | ⬜ 待 CI |
| 4 | `test_budget_assert_is_warn_only` 子进程在容器内稳定 | ⬜ 待 CI（首轮观察项） |
| 5 | 变更面 = 13 文件 | ✅ 已核 |
| 6 | `ci.yml` 零 `budget_assert` 引用（D15-A） | ✅ 已核 |
| 7 | 无测试函数被删除 | ✅ 已核 |
| 8 | N-8/N-9/N-10 反向断言原文存在 | ✅ 已核 |
| 9 | `sprint1-plan.md:111` 裁决状态文案修正（R6） | ⬜ 建议顺手处理 |
| 10 | R4 三条补救排入 Sprint 2 backlog | ⬜ 待主理人确认 |

---

*Batch D QA 计划 & Sprint 1 收口签收完成。**总判定：READY FOR MERGE**（PASS ×5 · CONCERNS ×0 · FAIL ×0），条件为 CI 实跑确认 95/95（GUT 本地已验证 95/95、0 Failed、0 Risky）。N-11/N-12 已由 H30 注入式反向断言闭环。质量门为建议性门控，最终放行由主理人游承峰决定。—— 严守真 · quality-lead*
