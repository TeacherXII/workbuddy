# Batch D 设计就绪评审（Design-Readiness Review）

> 《灰烬之步》ASHEN STEP · Sprint 1 收口批次
> 评审人：文策渊（design-strategist） · 日期：2026-08-04
> **文档版本：v1.1（裁决收口版）** —— v1.0 为待裁决稿；v1.1 落地主理人游承峰对 **D11–D15 的全数裁决（一律 A 案）**，并将 **C11–C22 全部标 CLOSED**。
> 评审强度：**full** · 前序：`batchc-design-review.md` / `batchc-impl-spec.md` / `batchc-qa-plan.md`
> **下游落地件：`production/sprints/batchd-impl-spec.md`**（实现就绪规格；凡本文与该文冲突处，**以 impl-spec 为准**）
> 命名说明：本文 **C11+** 为「缺口闭合常量」（承接 Batch C 的 C1–C10）；控制清单的 **C-01/C-02/C-03** 带连字符，指对比度红线，两者不同名空间。

---

## §0 速览

| 项 | 结果 |
| --- | --- |
| 判定 | **READY 1 · CONCERNS 3 · BLOCKED 0**（CONCERNS 的闭合方案已全数裁决通过） |
| 范围 | E06-S4（DECOY 声圈）· E04-S5（可熄灯过场）· E10-S2（§7 预算静态断言）· E10-S1（签收） |
| 预诊断验证 | 5 条 **全部确认**（3 条需补充修正，见 §1.0） |
| 缺口闭合 | **C11–C22（12 条）全部 CLOSED** —— 逐条映射到 D11–D15 裁决，见 §7.2 |
| 待裁决 | **无。** D11–D15 已由主理人游承峰**全数裁决为 A 案**（§7 表内标 CLOSED + 采纳值） |
| 隐性地雷 | **5 枚**（N-8 ~ N-12），其中 **N-9 为支柱级**：DECOY 在当前数值下**数学上不可能**单次生效。**5 枚全部有实现级落点 + 验证钩子**（impl-spec §6） |
| Sprint 1 退出标准 | **5 条全部可满足**（D14 口径已锁、C4 按已锁定裁决计达成；详见 §8.3） |

**一句话结论（v1.0）**：Batch D 没有 BLOCKED，但**不是一个「收口批次」**——它含 1 条孤儿 Story（E04-S5）、1 个全桩文件（`budget_assert.gd`）、1 处签名漂移（`decoy_landed`），以及一枚会让核心玩法动词 DECOY 静默失效的数值地雷。按本文 C11–C22 执行可全部闭合。

**一句话结论（v1.1 裁决后）**：**五项裁决全数落 A 案，C11–C22 十二条缺口全部 CLOSED，零未闭合裁决项、零 BLOCKED。** Batch D 自此成为真正的收口批次——工程可直接按 `batchd-impl-spec.md` §8 拓扑动手。

---

## §1 逐 Story 判定

### §1.0 五条预诊断的验证结论

| # | 主理人预诊断 | 验证 | 证据 |
| --- | --- | --- | --- |
| 1 | E09-S4 已在 Batch C 完成 | ✅ **确认** | `src/ui/hud_slice.gd:60` `EventBus.InteractableType.DECOY: "DECOY"`；`tests/unit/test_hud_slice.gd:335,347` 已断言 `interactable_triggered` 消费。Batch C 的 D8 已冻结签名 `(obj_id:int, type:InteractableType, payload:Dictionary)`。→ **应移出 Batch D** |
| 2 | E10-S1 已闭（CI 83/83） | ✅ **确认**（签收制） | `.github/workflows/ci.yml:129–136` N-7 `[Risky]` 门已落地，fail-closed 覆盖 `[Failed]` 与不可解析摘要。提交 f8b3c58 / c1421c5 / 452614f。本批**仅签收，不重开** |
| 3 | E04-S5 是孤儿 Story | ✅ **确认**，且**比预期更孤** | `sprint1-plan.md:55` 散文写 `E04×4（S3/S4/S5/S7）`，但 `:62` 批次拓扑 Batch A 只列 `E04-S3/S4/S7`，S5 从未进入任何批次；`src/game/light_model.gd` **无任何 ramp / fog / vignette 状态**；`tests/unit/test_light_model.gd` 覆盖 S1/S2/S3/S4/S7 而**无 ramp 测试**。三处独立证据互证 |
| 4 | E10-S2 比计划大 | ✅ **确认**，但**方向需修正** | `tests/ci/budget_assert.gd` 74 行**全桩**，6 个检查全部 `_warn(..."TODO: implement scan")`、exit 0。G-04/G-05/C-02 **无桩**。**但**：G-04 已由 `patrol_ai.gd:34 DECISION_HZ := 10.0` + `:70 decision_count`（G-04 断言计数器）+ `MAX_CATCHUP_TICKS` 在 Batch C 落地；C-02 已由 `src/ui/hud_colors.gd:31` `HUD_COLOR_CARRIER` **13.74:1** 满足。→ 缺的不是「实现」而是「**自动断言**」，见 §6 |
| 5 | `decoy_landed` 签名漂移 | ✅ **确认**，且**类型判断需修正** | `src/core/event_bus.gd:38` `signal decoy_landed(pos: Vector3)`，`:8` 与 `:36` 均留 DEFERRED 注释。`system-breakdown.md:51` 写 `DecoyPayload{pos, surface:Surface, radius:float}` —— 但 **`Surface` 类型在代码库中不存在**：`step_commit.gd:57 commit(..., surface: String)`、`SURFACE_FACTOR` 以 String 为键、`footfall_vfx.gd:32 signal footfall_foley(surface: String, ...)`。`Surface` 是文档级抽象，落地类型是 **String** |

> **修正 1**（对预诊断 4）：不要为 G-04 写 CI 扫描桩——它已实现且属 runtime-only，静态扫描只会产生恒真断言（N-11）。
> **修正 2**（对预诊断 5）：签名用 `surface: String`，不是 `Surface`。写 `Surface` 会直接编译失败。
> **修正 3**（对 Batch C QA 的 B-1 建议）：B-1 建议「`source==DECOY` **无条件**写 `last_known`」——**本评审不采纳「无条件」**，理由见 §2 C14。

---

### §1.1 判定表

| Story | 判定 | 核心理由 | 闭合项 |
| --- | --- | --- | --- |
| **E10-S1** headless GUT 全绿 | 🟢 **READY**（签收） | CI 83/83，N-7 门已落地且 fail-closed。无剩余设计缺口 | — |
| **E06-S4** DECOY 声圈 ≈8m | 🟡 **CONCERNS ×3** | ①签名漂移未收口 ②`surface` 参数语义未定义（存在成为死参数的风险）③**DECOY 在当前数值下单次投掷数学上无法触发 SUSPICIOUS**（N-9） | C11 · C12 · C13 · C14 · D11 · D12 |
| **E04-S5** 可熄灯过场 | 🟡 **CONCERNS ×3** | ①孤儿 Story，`light_model.gd` 零实现 ②R-05「ramp≤0.12」此前被误读为光能量，实为**体积雾密度增量** ③ramp 与 E04-S7 dirty-cell 重算存在顺序/重复重算竞态（N-10） | C15 · C16 · C17 · C18 · D13 |
| **E10-S2** §7 预算静态断言 | 🟡 **CONCERNS ×2** | ①全桩文件，6 检查皆 TODO ②**static-feasible 与 runtime-only 未分流**，若一律写成静态扫描将产出恒真断言，使退出标准 #4 被空壳满足（N-11） | C19 · C20 · C21 · C22 · D14 · D15 |

**判定口径**：CONCERNS = 设计缺口明确且已在 §2 给出可直接落地的闭合方案，不阻塞开工；BLOCKED = 缺口需外部输入才能定义。本批 **无 BLOCKED**。

---

## §2 缺口闭合（C11–C22）

> 全部为 copy-paste-ready。每条标注**来源溯源**，无发明数值。
>
> **v1.1 状态**：**C11–C22 十二条全部 CLOSED**。每条标题后标注闭合依据（哪条裁决）与是否被裁决改写。逐条 ↔ 裁决映射汇总见 **§7.2**。落地实现规格见 `batchd-impl-spec.md`。

### C11 · `decoy_landed` 最终签名 【E06-S4】 ✅ **CLOSED**（D11-A 确认；签名冻结，无改写）

```gdscript
# src/core/event_bus.gd —— 替换 :38，并删除 :8 与 :36 的 DEFERRED 注释
## E06-S4 (Batch D). DecoyPayload per system-breakdown §2 L51.
## `surface` is a String key into StepCommit.SURFACE_FACTOR / FootfallVFX.FOOTFALL_SUBTITLE
## ("STONE"/"GRASS"/"METAL"/"MOSS"/"WOOD"); the doc-level type name `Surface` has no
## GDScript counterpart — String is the codebase-wide convention (step_commit.gd:57,
## footfall_vfx.gd:32). radius is METRES.
signal decoy_landed(pos: Vector3, surface: String, radius: float)
```

**溯源**：`interactables.md:19` `decoy_landed(pos, surface, radius≈8m)`；`system-breakdown.md:51`；类型选择依 `step_commit.gd:57` / `footfall_vfx.gd:32`。

> ⚠ **不要加默认参数**。GDScript 的 signal 声明即使语法上接受默认值，`emit()` 也**不会**套用——参数个数不足会在运行时抛 "Error calling from signal"。这直接引出 N-8（见 §8）。

### C12 · DECOY 常量组 【E06-S4】 ✅ **CLOSED**（D11-A 确认；`DECOY_RADIUS` 恒 **8.0**，不引入 `SURFACE_FACTOR` 半径调制）

```gdscript
# src/game/sound_propagation.gd —— 追加到 :33 SOURCE_DECOY 附近
const DECOY_RADIUS := 8.0        # m    interactables.md §2 "radius≈8m"
const DECOY_INTENSITY := 1.0     # -    normalised loudness [0,1]; DECOY is a
                                 #      full-loudness event (contrast: footfall
                                 #      intensity is gait/surface-modulated)
```

**溯源**：`interactables.md:19` ≈8m。`intensity` 归一化域 [0,1] 由 `patrol_ai.gd:29–34` 的 `KS := 15.0 # pts/event (x falloff)` 与 `suspicion_from_distance` 反推确定——见 §2 C14 的数值推导。

### C13 · DECOY 监听器（E06-S4 消费侧） 【E06-S4】 ✅ **CLOSED**（D11-A 落地：`surface` 仅进 payload 驱动 foley/字幕变体，**不参与半径计算**）

```gdscript
# src/game/sound_propagation.gd —— 新增；在 _ready() 中连接 EventBus.decoy_landed
func _on_decoy_landed(pos: Vector3, surface: String, radius: float) -> void:
	# E06-S4: DECOY is a signal-level sound source in Sprint 1. The E07 entity
	# (physical throwable) is deferred to Sprint 2 per plan D2.
	var r: float = radius if radius > 0.0 else DECOY_RADIUS
	emit(pos, DECOY_INTENSITY, r, SOURCE_DECOY, surface)
```

> `emit()` 的既有形参表需据 `sound_propagation.gd` 现签名对齐；若现 `emit()` 不收 `surface`，则按 `step_commit.gd:71` 的既有做法把 `surface` 塞进 payload 字典，**不新增位置参数**（避免二次签名漂移）。

### C14 · DECOY 重定向语义 —— 修正 B-1 【E06-S4】★ 关键 ✅ **CLOSED**（D12-A 采纳：`maxf(sus, THR_SUSP)` + **3.0s** 冷却；3.0 为主理人确认的**唯一新增自由数值**）

**先给数值推导（这是 N-9 的证明）：**

- `sound_propagation.gd`：`suspicion_from_distance(intensity, dist, radius) = max(0, intensity × (1 − dist/radius))`
- `patrol_ai.gd:271–292`：`falloff = suspicion_from_distance(...)`，`_pending_sound_max = maxf(_pending_sound_max, falloff)`
- `patrol_ai.gd:30`：`KS := 15.0 # pts/event sound gain (× falloff; [D5] NOT × dt)`
- `patrol_ai.gd:27`：`THR_SUSP := 25.0`

单次 DECOY 的**理论最大**可疑度增益（`intensity=1.0`、`dist=0`、即守卫脚下爆响）：

```
gain_max = KS × (1.0 × (1 − 0/8)) = 15.0 × 1.0 = 15.0 pts
15.0 < THR_SUSP (25.0)
```

→ **单次 DECOY 在任何距离上都无法把 CALM 守卫推过 SUSPICIOUS 阈值**。在半径中点（4m）更只有 7.5 pts（与 Batch C QA 的 B-1 观测吻合）。玩家需在 `DECAY := 8.0 pts/s` 衰减之内连投 **≥2 次**才能生效——而 HUD 的 `_item_charge_count` 表明投掷物是限量资源。**核心玩法动词在数值上失效**。

**闭合方案（推荐 C 案，见 D12 供裁决）：**

```gdscript
# src/game/patrol_ai.gd —— 在 _on_sound_emitted 内，falloff 计算之后
const DECOY_REDIRECT_COOLDOWN_RT := 3.0   # s (real) anti-spam, per guard
var _last_decoy_rt: float = -999.0

# ...inside _on_sound_emitted, after `if falloff <= 0.0: return`
var src: String = payload.get("source", "")
if src == SoundPropagator.SOURCE_DECOY:
	_pending_decoy_origin = origin
	_pending_decoy = true
```

```gdscript
# —— 在决策 tick 内（_step 中，_update_last_known 之前）
if _pending_decoy and (now_rt - _last_decoy_rt) >= DECOY_REDIRECT_COOLDOWN_RT:
	# DECOY 的设计意图是「重定向注意力」而非「提升警觉」——因此用 floor 而非累加，
	# 复用既有 THR_SUSP，不引入新的可疑度标度。
	suspicion = maxf(suspicion, THR_SUSP)
	_last_decoy_rt = now_rt
_pending_decoy = false
```

**★ 对 Batch C QA B-1 的修正**：B-1 建议「`source==DECOY` **无条件**写 `last_known`」。**本评审不采纳「无条件」**。`patrol_ai.gd:297–305` 的 `_update_last_known` 现有写入优先级为「①看得见→真实目标位 ②否则→声源 ③否则→保留」。这条 `vis > STIM_EPS` 保护是**正确的设计**：正在直视玩家的守卫不应被一枚假声拉走，否则 DECOY 变成无视线判定的万能脱身键（主导策略红线）。

→ **保留 `vis` 保护**。DECOY 的 `last_known` 写入沿用既有第 ② 优先级即可，**无需新增分支**；只需上面的 suspicion floor 让守卫真的进入 SUSPICIOUS 去调查。这同时也正好实现了 `sound-propagation.md §2`「DECOY reduces guard's weighting of player path」——守卫的 `last_known` 被引向假声，而非玩家真实路径。

### C15 · R-05 的正确解读 —— 这是**雾密度**，不是光能量 【E04-S5】★ 关键修正 ✅ **CLOSED**（D13-A 确认解读；ramp 为纯视觉量）

`control-manifest.md:22` 原文：

> | R-05 | **熄灯过场雾 ramp** | **≤ 0.12 且持续时间 ≤ 0.4s** 后回落 | 美术 §3.3「黑暗吞没」 |

配合 `control-manifest.md:21`：`R-04 | 体积雾密度（base） | ≤ 0.05`。

→ R-05 的 `0.12` 是**熄灯过场期间叠加在体积雾 base 密度之上的增量峰值**（无量纲密度值），`0.4s` 是该增量的**存续上限**。绝对峰值密度 ≤ `0.05 + 0.12 = 0.17`。

这条修正很重要：此前把 0.12 读作「光能量 ramp」会得到「幅度 ≤0.12 但要从 1.0 降到 0」的自相矛盾，进而逼出「per-frame delta」的臆测单位。按原文读则完全自洽，**无需发明任何单位**。

### C16 · E04-S5 过场常量组 【E04-S5】 ✅ **CLOSED**（D13-A 确认；6 常量全部溯源 control-manifest，仅 `FOG_RAMP_RT=0.30` 为余量取值）

```gdscript
# src/game/light_model.gd —— 新增
# ── E04-S5 extinction cutscene (R-04 / R-05 / V-06) ──────────────────────────
const FOG_BASE_MAX := 0.05          # -  R-04 ceiling (control-manifest §7 L21)
const FOG_RAMP_PEAK := 0.12         # -  R-05 additive peak ABOVE base (L22)
const FOG_RAMP_MAX_RT := 0.4        # s  R-05 hard ceiling on ramp lifetime (L22)
const FOG_RAMP_RT := 0.30           # s  chosen lifetime; 0.30 <= 0.40 with margin
const VIGNETTE_EASE := Tween.EASE_IN_OUT   # V-06 "缓动（ease），禁硬切闪光" (L50)
const VIGNETTE_TRANS := Tween.TRANS_SINE   # V-06 no flash, no step
```

**溯源**：全部逐行对应 `control-manifest.md:21/22/50`。`FOG_RAMP_RT := 0.30` 是唯一的自由取值，选择依据：留 25% 余量避免帧抖动把实测值顶过 0.4s 硬顶（同 Batch C 对 `GRACE_RT` 的处理惯例）。

### C17 · ramp 曲线（可直接实现） 【E04-S5】 ✅ **CLOSED**（D13-A 确认；sin 单峰 + 4 类边缘情况全部保留为验收项 **H22 / H23**）

```gdscript
# 归一化过场进度 t ∈ [0,1]，t = elapsed_rt / FOG_RAMP_RT
# 单峰：升到 FOG_RAMP_PEAK 再回落到 0，保证「后回落」(R-05 原文)
static func fog_ramp_delta(t: float) -> float:
	var u := clampf(t, 0.0, 1.0)
	return FOG_RAMP_PEAK * sin(PI * u)      # 0 -> peak @ t=0.5 -> 0

static func fog_density_at(t: float, base: float) -> float:
	return minf(base, FOG_BASE_MAX) + fog_ramp_delta(t)
```

**边缘情况（≥3 类，按输出规范）**：

1. **过场期间再次 toggle**：不叠加第二条 ramp。以「重置 `elapsed_rt = 0` 并保持单条 ramp」处理，否则两条 sin 叠加峰值可达 0.24，**直接击穿 R-05**。
2. **`base` 已超 R-04**：`fog_density_at` 用 `minf(base, FOG_BASE_MAX)` 夹紧，防止上游配错雾把 R-05 的余量吃掉。
3. **`FOG_RAMP_RT <= 0` / dt 尖峰（headless、断点、加载卡顿）**：`clampf(t,0,1)` 保证 `t>1` 时 delta 归 0（`sin(PI×1)=0`），不会出现「过场卡在峰值」的永久浓雾。
4. **暂停（RTwP）**：ramp 必须走**实时钟**（`Time.get_ticks_msec()`，同 `patrol_ai.gd:199` 与 `step_commit.gd:138–147` 的既有约定），否则暂停时过场冻结在半程。

### C18 · ramp 与 E04-S7 dirty-cell 的解耦 【E04-S5】★ 关键 ✅ **CLOSED**（**D13-A 直接采纳本条为裁决正文**：visual-only，遮蔽/光照等级在 `toggle_light()` 瞬间一次性翻转，ramp 期间**不做逐帧重算**）

**问题**（N-10）：`light_model.gd` 的 E04-S7 在光态变化时 `mark_cell_dirty` 触发遮蔽重算。若 ramp 期间逐帧 mark dirty，0.30s × 60fps = **18 次重算**，违反 ADR-002「O(cell) 非 O(all)」的节流精神，且可能连带撞 G-03。

**闭合规则（写入实现规范，供程基岩执行）：**

```
E04-S5 的 ramp 是 **visual-only**。
① 遮蔽判定在 toggle 瞬间一次性切换，`light_state_changed` 只 emit 一次，
   `mark_cell_dirty` 只调用一次 —— 与 E04-S4/S7 现有行为完全不变。
② ramp 只驱动：体积雾 density delta（R-04/R-05）+ vignette 缓动（V-06）
   + 实时光释放（R-02）。三者皆不参与可见性计算。
③ 因此 ramp 不得读写任何 gameplay 状态，也不得再次触发重算。
```

**三条理由**：(a) ADR-002 合规，重算次数从 18 降回 1；(b) 机制可预测——玩家按下即生效，不存在「光看着还亮但已算作暗」的 0.3s 灰区（gameplay reads 脱钩）；(c) V-06 的柔和过场目的本就是**视觉**的。

**R-02 的例外**：实时光的**释放**（`OmniLight3D` 数量 −1）应发生在 ramp **结束**时，而非开始时——否则光在视觉上还在衰减、灯却已被移除，产生硬切闪光，反而违反 V-06。这一条要显式写进实现规范。

### C19 · E10-S2 分流原则 —— static-feasible vs runtime-only 【E10-S2】★ 关键 ✅ **CLOSED**（**D14-A 直接采纳本条分流表为验收口径**：static 项走 `budget_assert.gd` 真实扫描，runtime 项走 GUT，**二者合并计为退出标准 #4 达成**；**恒真桩为明令禁止项**）

```
凡「可由静态资产/常量表判定」者 → 进 tests/ci/budget_assert.gd（CI 扫描）
凡「只有运行时才有值」者        → 由 GUT 单测承载，budget_assert 中**明确不写桩**
```

写恒真桩比不写更危险：它让退出标准 #4「§7 预算断言运行」在字面上被满足，实质是空壳（N-11）。

| 红线 | 定义（control-manifest 行号） | 分流 | 承载 |
| --- | --- | --- | --- |
| R-02 | 动态点光同屏 MVP≤12 / Tier2≤32 (`:19`) | **static** | `.tscn` 扫 `OmniLight3D`/`SpotLight3D` 节点数 |
| R-04 | 体积雾 base ≤0.05 (`:21`) | **static** | 扫 `FogVolume`/`Environment` 资源的 density |
| R-05 | 雾 ramp ≤0.12 且 ≤0.4s (`:22`) | **runtime** | `@test_light_toggle_ramp_within_budget`（E04-S5） |
| R-06 | 静态几何 LightmapGI 烘焙 (`:23`) | **static** | 扫 `.tscn` 中 `LightmapGI` 存在性 + 静态 mesh 的 UV2 |
| V-02 | 暴露脉动 ≤2Hz (`:46`) | **runtime** | HUD 脉动单测（Batch C 已有） |
| V-06 | 转场缓动、禁硬切 (`:50`) | **static（弱）** | 扫 `Tween.TRANS_*`/`EASE_*` 常量，非 `TRANS_LINEAR` 硬切 |
| G-02 | 同屏声环 ≤8 (`:82`) | **runtime** | `test_sound_propagation.gd` `RING_CAP=8` |
| G-04 | 可疑度 FSM ≤10Hz (`:84`) | **runtime** | `patrol_ai.gd:34 DECISION_HZ` + `:70 decision_count` 断言（**Batch C 已实现**） |
| G-05 | A* 仅状态转换触发、路径缓存 (`:85`) | **runtime** | Sprint 1 无 A* 实现 → **不写桩**，标注 Sprint 2 |
| C-02 | 关键指示对比度 ≥7:1 (`:59`) | **static** | 扫 `hud_colors.gd` 常量表算对比度 |

### C20 · `budget_assert.gd` 落地范围 【E10-S2】 ✅ **CLOSED**（D14-A 确认；R-02/R-04/R-06/V-06/C-02 落**真实扫描**，R-05/G-02/V-02 **删桩改注释**，G-04/G-05 **不新增桩**）

**实现**：R-02 · R-04 · R-06 · V-06 · C-02（5 项 static-feasible）
**删除桩**：`_check_light_extinction_ramp`（R-05）· `_check_sound_rings`（G-02）· `_check_pulse_frequency`（V-02）→ 改为文件头注释指向承载单测
**不新增**：G-04（已实现，runtime）· G-05（Sprint 1 无实现）

```gdscript
# tests/ci/budget_assert.gd —— 文件头必须写清分流，防止后人补回恒真桩
# RUNTIME-ONLY budgets are deliberately NOT scanned here. A static scan of a
# runtime quantity is an always-pass assertion, which would satisfy the Sprint 1
# exit criterion #4 in letter and void it in substance.
#   R-05 -> tests/unit/test_light_model.gd::test_light_toggle_ramp_within_budget
#   G-02 -> tests/unit/test_sound_propagation.gd (RING_CAP == 8)
#   V-02 -> tests/unit/test_hud_slice.gd (pulse frequency)
#   G-04 -> src/game/patrol_ai.gd DECISION_HZ / decision_count (Batch C)
#   G-05 -> no A* in Sprint 1; revisit in Sprint 2
```

### C21 · C-02 静态断言（把注释变成可执行校验） 【E10-S2】 ✅ **CLOSED**（D14-A 确认为 static 扫描项）· ⚠ **v1.1 已修正函数名**

`src/ui/hud_colors.gd` 已把对比度写在注释里（`:31` CARRIER **13.74:1** ✅）。注释不会失败，改色会静默漂移。

> ### ⛔ v1.1 修正 —— v1.0 本条给出的代码**不可照抄**
>
> v1.0 写的 `_srgb_lin` / `_luminance` / `contrast_ratio` 三个函数名，**与代码库实际暴露的 API 不符**：`src/ui/hud_colors.gd` 已在 Batch C 落地 `static func relative_luminance(c: Color)`（`:54`）与 `static func wcag_contrast(fg: Color, bg: Color) -> float`（`:58`）。
>
> **照抄 v1.0 的后果**：在 `budget_assert.gd` 里重写一份 WCAG 实现 = ①**双份公式**（改一处漏一处的漂移源）②与 Batch C 的 `test_hud_slice.gd::test_suspicion_bar_contrast`（H12）用不同实现算同一红线，两处可能给出不同结论。
>
> **正确落法（以 `batchd-impl-spec.md` §5.4 为准）**：**复用** `HudColors.wcag_contrast()`，`budget_assert.gd` 内**不重写任何 WCAG 数学**。

```gdscript
# tests/ci/budget_assert.gd —— ✅ 正确版本（复用既有纯函数，零重复实现）
# C-02: 关键指示（可疑度/暴露）载体 >= 7:1 vs panel base
# WCAG 数学唯一权威源 = src/ui/hud_colors.gd:54/58（Batch C 落地，headless 安全）
const HudColors := preload("res://src/ui/hud_colors.gd")

func _check_contrast_c02() -> void:
	var base: Color = HudColors.HUD_COLOR_PANEL_BASE
	# 载体白名单 —— 只有「信息载体」入 C-02；填充色不入（见下方假红警告）
	for entry in [["CARRIER", HudColors.HUD_COLOR_CARRIER]]:
		var r: float = HudColors.wcag_contrast(entry[1], base)
		if r < 7.0:
			_warn("C-02", "%s contrast %.2f:1 < 7:1" % [entry[0], r])
```

**溯源**：`control-manifest.md:59` C-02 ≥7:1；`hud_colors.gd:30/31`（色值）、`:54/:58`（函数）。
**注意 `HUD_COLOR_ALARM_FILL`（1.91:1）不参与 C-02** —— 它是 `hud_slice.gd:367` 标注的「FILL ONLY, a ≤ 0.35」，非信息载体。扫描时必须按载体白名单，否则**假红**（N-12）。

### C22 · budget_assert 在 Batch D 保持 WARN-ONLY 【E10-S2】 ✅ **CLOSED**（D15-A 采纳：Batch D **WARN-ONLY**，**不得**接入 N-7 fail-closed 门）

```gdscript
# 保持 exit code 0；不产出 "[Risky]" 字样。
```

> **v1.1 现状核查**：`grep -n "budget_assert" .github/workflows/ci.yml` → **零命中**。即 `budget_assert.gd` 目前**根本未被 CI 引用**，D15-A 的「不接 gate」在事实层面已成立。
> ⚠ 因此 D15 的真实风险不是「要去解绑」，而是**工程在 Batch D 顺手把它加进 `ci.yml`**。impl-spec §5.6 已把「**不得新增 ci.yml 引用**」写成显式禁令 + H29 守卫。

**理由**：`ci.yml:129–136` 的 N-7 门是 fail-closed —— 只要出现 `[Risky]` 或 Risky/Pending 非零就挂 CI。真实扫描**首次上线**必然有误判（运行时 spawn 的光、继承场景/实例场景的重复计数、编辑器专用节点）。首发即接 gate = 用一个未经校准的扫描器去卡整条流水线。

→ Batch D：真实扫描 + WARN-ONLY + 把命中项打进摘要。
→ Sprint 2：观察一个迭代的告警噪声后再升级为 gate（列入 D15）。

---

## §3 实现顺序拓扑

> **v1.1**：本节的 3 条硬约束**全部保留且已强化**，完整线性执行清单（含每步的钩子、前置、提交边界）见 `batchd-impl-spec.md` **§8**。其中约束 1（签名 + 测试同 commit）已升格为 **§8.0 提交边界硬规则**。

```
        ┌──────────────────────────────────────────────┐
        │ 0. E10-S1 签收（无代码改动）                  │
        └──────────────────────────────────────────────┘
                          │
      ┌───────────────────┴───────────────────┐
      ▼                                       ▼
┌─────────────────────┐             ┌─────────────────────┐
│ 1. E06-S4 词汇收口   │             │ 3. E04-S5 熄灯过场   │
│  C11 signal 改签名   │             │  C15 R-05 解读修正   │
│  ⚠ 同 commit 必须改  │             │  C16 常量组          │
│    test_event_bus:60 │             │  C17 ramp 曲线       │
│    （N-8 假绿风险）  │             │  C18 与 S7 解耦 ★    │
└──────────┬──────────┘             └──────────┬──────────┘
           ▼                                   │
┌─────────────────────┐                        │
│ 2. E06-S4 消费侧     │                        │
│  C12 常量 / C13 监听 │                        │
│  C14 重定向语义 ★    │                        │
└──────────┬──────────┘                        │
           └─────────────┬──────────────────────┘
                         ▼
        ┌──────────────────────────────────────────────┐
        │ 4. E10-S2 预算断言（必须最后做）              │
        │  C19 分流 / C20 范围 / C21 C-02 / C22 WARN    │
        └──────────────────────────────────────────────┘
```

**排序依据（3 条硬约束）：**

1. **E06-S4 的签名改动必须与 `test_event_bus.gd:60` 同一 commit**。拆开会产生一个中间态红/假绿 commit（N-8）。
2. **E10-S2 必须排在 E04-S5 之后**。R-05 的承载单测 `@test_light_toggle_ramp_within_budget` 由 E04-S5 提供；先做 E10-S2 会导致 C20 的文件头注释指向一个不存在的测试。
3. **步骤 1 与步骤 3 可并行**（不同文件、无共享符号：`event_bus.gd`/`sound_propagation.gd`/`patrol_ai.gd` vs `light_model.gd`）。

---

## §4 测试钩子表

> **v1.1 编号说明**：本表的钩子已在 `batchd-impl-spec.md` §7 中**接续 Batch C 的 H1–H18 编号为 H19–H29（11 条）**，并补齐断言级细节。**工程/QA 请以 impl-spec §7 为准**，本表仅作设计意图溯源。

| Story | 钩子 | 类型 | 断言要点 | 状态 |
| --- | --- | --- | --- | --- |
| E06-S4 | `test_decoy_sound_radius` | 新增 | `decoy_landed(pos,"STONE",8.0)` → `sound_emitted` payload 的 `source=="DECOY"`、`radius==8.0`、`origin==pos` | 待写 |
| E06-S4 | `test_decoy_signature_arity` | 新增 | **必须断言 payload 值，不能只断言 emitted**（N-8 假绿防护） | 待写 |
| E06-S4 | `test_decoy_redirect_threshold` | 新增 | 单次 DECOY → 守卫进入 SUSPICIOUS；且 `vis > STIM_EPS` 时**不**被重定向（C14 保护） | 待写 |
| E06-S4 | `test_decoy_redirect_cooldown` | 新增 | 冷却内第二次 DECOY 不重复 floor（防刷） | 待写 |
| E06-S4 | `test_event_bus.gd:60` | **改** | `emit(Vector3(0,0,1))` → `emit(Vector3(0,0,1), "STONE", 8.0)` | ⚠ 必改 |
| E04-S5 | `@test_light_toggle_ramp_within_budget` `@ci:R-05` | 新增 | `fog_ramp_delta` 峰值 ≤0.12；ramp 存续 ≤0.4s；`t>1` 时归 0 | 待写 |
| E04-S5 | `test_light_ramp_single_recompute` | 新增 | **整段 ramp 内 `mark_cell_dirty` 只被调用 1 次**（C18/N-10 守卫） | 待写 |
| E04-S5 | `test_light_ramp_retoggle_no_stack` | 新增 | 过场中再 toggle → 峰值仍 ≤0.12（C17 边缘情况 1） | 待写 |
| E04-S5 | `test_light_ramp_realtime_clock` | 新增 | ramp 走实时钟，暂停不冻结（C17 边缘情况 4） | 待写 |
| E10-S2 | `test_budget_assert_contrast` | 新增 | `contrast_ratio` 对 `HUD_COLOR_CARRIER`/`PANEL_BASE` 得 ≈13.74，且 `ALARM_FILL` 不入 C-02 白名单 | 待写 |
| E10-S2 | `test_budget_assert_exit_zero` | 新增 | WARN-ONLY：有告警时仍 exit 0、且摘要**不含** `[Risky]`（C22/N-11 守卫） | 待写 |
| E10-S1 | — | 签收 | CI 83/83 | ✅ |

---

## §5 事件词汇一致性

### §5.1 `decoy_landed` 最终签名（冻结）

```gdscript
signal decoy_landed(pos: Vector3, surface: String, radius: float)
```

- `pos`: Vector3，世界坐标，米
- `surface`: String，`SURFACE_FACTOR` / `FOOTFALL_SUBTITLE` 的键（`"STONE"|"GRASS"|"METAL"|"MOSS"|"WOOD"`）
- `radius`: float，米，标称 `DECOY_RADIUS = 8.0`
- **无默认参数**（GDScript signal emit 不套用默认值）

### §5.2 全部变更点（缺一即红或假绿）

| # | 文件:行 | 现状 | 变更 | 风险 |
| --- | --- | --- | --- | --- |
| 1 | `src/core/event_bus.gd:38` | `signal decoy_landed(pos: Vector3)` | → C11 三参签名 | — |
| 2 | `src/core/event_bus.gd:8` | `# ... DEFERRED -> Batch D, E06-S4.` | 删除 DEFERRED 注释 | 词汇零漂移取证 |
| 3 | `src/core/event_bus.gd:36` | `# NOTE: Sprint 0 shape retained (§2 wants DecoyPayload{...})` | 删除，改为 C11 的说明块 | 同上 |
| 4 | `tests/unit/test_event_bus.gd:60` | `_bus.decoy_landed.emit(Vector3(0,0,1))` | → 补 `"STONE", 8.0` | ★ **N-8 假绿源** |
| 5 | `tests/unit/test_event_bus.gd:79` | `assert_signal_emitted(_bus,"decoy_landed")` | 追加参数值断言 | ★ N-8 防护 |
| 6 | `src/game/sound_propagation.gd:31` | `# ... E06-S4 (DECOY) is Batch D.` | 删除延期注释 | — |
| 7 | `src/game/sound_propagation.gd` | 无监听器 | 新增 C13 `_on_decoy_landed` + `_ready` 连接 | — |
| 8 | `src/game/patrol_ai.gd` `_on_sound_emitted` | 无 DECOY 分支 | 新增 C14 floor + cooldown | 支柱级（N-9） |
| 9 | `design/gdd/system-breakdown.md:51` | `surface:Surface` | 标注「文档级类型名，落地为 String」 | 防未来再漂移 |

### §5.3 未受影响（确认无需改动）

`hud_slice.gd:60`（`InteractableType.DECOY` 是**枚举**，与 `decoy_landed` 无耦合）· `test_hud_slice.gd:335/347`（走 `interactable_triggered`，Batch C D8 已冻结）· `sound_propagation.gd:33 SOURCE_DECOY`（String 常量，复用不改）。

---

## §6 控制清单红线逐行审查

| 红线 | 原文（行号） | Batch D 触及 | 判定 | 依据 / 动作 |
| --- | --- | --- | --- | --- |
| **R-02** | 动态点光 MVP≤12 / Tier2≤32 (`:19`) | E04-S5 · E10-S2 | 🟢 | 熄灯**释放**光，只会降低计数。C18 规定释放时点在 ramp 末（防 V-06 硬切）。E10-S2 静态扫描 |
| **R-04** | 体积雾 base ≤0.05 (`:21`) | E04-S5 · E10-S2 | 🟢 | C16 `FOG_BASE_MAX`；C17 `minf(base, FOG_BASE_MAX)` 夹紧。静态扫描 |
| **R-05** | 熄灯过场雾 ramp ≤0.12 且 ≤0.4s 后回落 (`:22`) | E04-S5 · E10-S2 | 🟡→🟢 | **此前误读为光能量，已由 C15 修正为雾密度增量**。C16 `FOG_RAMP_PEAK=0.12` / `FOG_RAMP_RT=0.30`；C17 sin 单峰保证「后回落」。**runtime-only**，由单测卡门（C19） |
| **R-06** | 静态几何 LightmapGI 烘焙 (`:23`) | E10-S2 | 🟢 | 静态扫描 `.tscn`。Batch D 不新增静态几何 |
| **V-02** | 暴露脉动 ≤2Hz (`:46`) | E10-S2 | 🟢 | Batch C 已实现；**runtime-only**，删桩改注释（C20） |
| **V-06** | 转场缓动，禁硬切闪光 (`:50`) | E04-S5 | 🟡→🟢 | C16 `TRANS_SINE`/`EASE_IN_OUT`。⚠ **R-02 光释放时点是 V-06 的隐藏依赖**——ramp 开始就删灯 = 硬切，C18 已规定放到 ramp 末 |
| **G-02** | 同屏声环 ≤8 (`:82`) | E06-S4 | 🟡 | DECOY **新增一类声环发射源**，`RING_CAP=8` 的 FIFO 需覆盖 DECOY。E06-S3 的 FIFO 是按声环实例计数还是按来源分桶？→ 若分桶则 DECOY 可能突破 8。**runtime-only**，须在 `test_decoy_sound_radius` 里附带断言 |
| **G-03** | 锥体重算 ≤10Hz/守卫 (`:83`) | E04-S5（间接） | 🟢 | C18 保证 ramp 不触发重算；`patrol_ai.gd:438` 已在 10Hz tick 内满足 |
| **G-04** | 可疑度 FSM ≤10Hz (`:84`) | E06-S4（间接） | 🟢 | **Batch C 已实现**：`patrol_ai.gd:34 DECISION_HZ=10.0`、`:35 TICK_DT=0.1`、`:70 decision_count`、`MAX_CATCHUP_TICKS=3`。C14 的 DECOY floor **必须放在决策 tick 内**，不得在 `_on_sound_emitted` 里直接改 suspicion——否则声音事件频率 = 决策频率，**击穿 G-04** |
| **G-05** | A* 仅状态转换触发 (`:85`) | — | ⚪ N/A | Sprint 1 无 A* 实现。**不写桩**（C20），Sprint 2 处理 |
| **C-02** | 关键指示对比度 ≥7:1 (`:59`) | E10-S2 | 🟡→🟢 | 已由 `hud_colors.gd:31` CARRIER **13.74:1** 满足，但只是注释。C21 把它变成可执行断言。⚠ `ALARM_FILL` 1.91:1 需排除，否则假红 |

**红线净结论**：Batch D 无红线违规。两处需要显式写进实现规范的隐藏耦合：**① R-02 光释放时点 ↔ V-06**（C18）；**② C14 的 DECOY floor 必须在决策 tick 内 ↔ G-04**。

---

## §7 裁决项（D11–D15）—— **全部 CLOSED**

> **裁决状态**：主理人游承峰已于 v1.1 对 **D11–D15 五项全数裁决**，**一律采纳推荐 A 案**。以下表格保留原议题与选项以备溯源，并追加 **采纳值 / 状态 / 落点** 三列。**本节不再重开讨论。**

| # | 议题 | 选项 | 裁决 | **采纳值（锁定）** | 状态 | 落点 |
| --- | --- | --- | --- | --- | --- | --- |
| **D11** | `decoy_landed` 的 `surface` 语义——它会不会是死参数？ | **A** 仅驱动 foley 字幕变体（复用 `footfall_vfx.FOOTFALL_SUBTITLE`），radius 恒 8.0<br>**B** 同时用 `SURFACE_FACTOR` 调制半径（MOSS 0.5 → 4m）<br>**C** Sprint 1 先不传，签名退回两参 | **A** | `surface` **只**驱动 foley / 字幕变体，复用 `FootfallVFX.FOOTFALL_SUBTITLE`（`footfall_vfx.gd:20-26`）；**`radius` 恒定 8.0**；Sprint 1 **不引入** `SURFACE_FACTOR` 半径调制 | ✅ **CLOSED** | C11 · C12 · C13<br>impl-spec §3.2 / §3.4 |
| **D12** | DECOY 单次投掷如何真的生效（N-9） | **A** suspicion floor `maxf(sus, THR_SUSP)` + 3s 冷却（C14）<br>**B** 提高 DECOY intensity 至 >1.667（破坏 [0,1] 归一化契约）<br>**C** 新增 `KS_DECOY := 30.0`（半径中点仍只有 15 pts，不保证生效）<br>**D** 接受「需连投 2 次」，改为设计意图 | **A** | 命中即 `sus = maxf(sus, THR_SUSP)` + **`DECOY_REDIRECT_COOLDOWN_RT = 3.0` s（真实时钟，逐守卫）**——主理人确认的**唯一新增自由数值**。**复用既有 `THR_SUSP=25.0`；不新增标度；不动 `intensity` 归一化；不加 `KS_DECOY`** | ✅ **CLOSED** | C14<br>impl-spec §3.5 / §6 N-9 |
| **D13** | E04-S5 的 ramp 是纯视觉还是影响遮蔽（N-10） | **A** visual-only，遮蔽在 toggle 瞬间一次切换（C18）<br>**B** ramp 期间渐变遮蔽（逐帧重算） | **A** | ramp **visual-only**；遮蔽 / 光照等级在 `toggle_light()` **瞬间一次性翻转**；ramp 期间**无逐帧重算**；`mark_cell_dirty` 全程**恰调 1 次** | ✅ **CLOSED** | C15 · C16 · C17 · C18<br>impl-spec §4 / §6 N-10 |
| **D14** | 退出标准 #4「§7 预算断言运行」的验收口径 | **A** static-feasible 项由 CI 扫描 + runtime 项由 GUT 承载，**合并计为达成**<br>**B** 要求全部 10 项都在 CI 里跑<br>**C** 只认 CI 扫描，runtime 项记未达成 | **A** | **static 扫描 + GUT 运行时断言合并计为达成**。static 项 **R-02 / R-04 / R-06 / C-02**（+V-06 弱扫）→ `budget_assert.gd` **真实扫描**；runtime 项 **R-05 / G-02 / V-02 / G-04 / G-05** → **GUT 断言**。**⛔ 明令禁止恒真桩（N-11）** | ✅ **CLOSED** | C19 · C20 · C21<br>impl-spec §5 |
| **D15** | budget_assert 何时接入 N-7 gate | **A** Batch D 保持 WARN-ONLY，Sprint 2 观察一轮后升级<br>**B** Batch D 直接接 gate | **A** | Batch D **WARN-ONLY**：exit 0、摘要不含 `[Risky]`、**不得写入 `.github/workflows/ci.yml`**。升级为 gate 排 Sprint 2（观察一轮告警噪声后） | ✅ **CLOSED** | C22<br>impl-spec §5.6 / §6 N-12 |

### §7.1 裁决落地记录（v1.1 已执行）

| # | 动作 | 文件 | 说明 |
| --- | --- | --- | --- |
| B1 | §0 速览改写 | 本文 | 「待裁决 D11–D15」→「**无**」；退出标准「3+2 有条件」→「**5 条全部可满足**」；追加 v1.1 结论行 |
| B2 | C11–C22 全数标 **CLOSED** | 本文 §2 | 每条标题追加闭合依据（对应裁决 + 是否被改写） |
| B3 | §7 表追加 采纳值 / 状态 / 落点 三列 | 本文 §7 | 五项 CLOSED |
| B4 | **C21 函数名修正** | 本文 §2 C21 | v1.0 的 `contrast_ratio` / `_srgb_lin` / `_luminance` **与代码库不符**（实为 `wcag_contrast` / `relative_luminance`），照抄会造成双份 WCAG 实现。已加 ⛔ 修正块 + 正确版本 |
| B5 | §8.3 退出标准结论改写 | 本文 §8.3 | 2 条「有条件」的条件均已消解 |
| B6 | **新建实现规格** | `production/sprints/batchd-impl-spec.md` | 三条 Story 的文件/签名/常量/伪码/H19–H29 钩子/N-8~N-12 落点/执行拓扑 |

> **未执行（纪律）**：本文与 impl-spec **均未触碰 `src/` 与 `tests/`**。所有 GDScript 段落是**规格**不是实现。

### §7.2 C11–C22 ↔ 裁决 映射闭合表（逐条取证，一条不漏）

| 缺口 | 归属 Story | 闭合裁决 | 是否被裁决**改写** | 终态 |
| --- | --- | --- | --- | --- |
| **C11** `decoy_landed` 三参签名 | E06-S4 | D11-A | 否（原样冻结） | ✅ CLOSED |
| **C12** `DECOY_RADIUS=8.0` / `DECOY_INTENSITY=1.0` | E06-S4 | D11-A | 否；**并由 D11-A 明确排除** B 案的 `SURFACE_FACTOR` 半径调制 | ✅ CLOSED |
| **C13** `_on_decoy_landed` 监听器 | E06-S4 | D11-A | **是（轻微收窄）**：`surface` 仅入 payload 供 foley/字幕，**不得**参与 `r` 计算 | ✅ CLOSED |
| **C14** DECOY floor + 冷却 + 保留 `vis` 保护 | E06-S4 | **D12-A** | 否；3.0s 冷却获主理人**明确确认**。B-1「无条件写 `last_known`」的拒绝**维持**（`patrol_ai.gd:297` `vis > STIM_EPS` 保护保留） | ✅ CLOSED |
| **C15** R-05 = 雾密度增量（非光能量） | E04-S5 | D13-A | 否 | ✅ CLOSED |
| **C16** 6 条过场常量 | E04-S5 | D13-A | 否 | ✅ CLOSED |
| **C17** sin 单峰 ramp + 4 类边缘情况 | E04-S5 | D13-A | 否 | ✅ CLOSED |
| **C18** ramp ↔ dirty-cell 解耦 | E04-S5 | **D13-A（本条即裁决正文）** | 否 | ✅ CLOSED |
| **C19** static vs runtime 分流表 | E10-S2 | **D14-A（本条即验收口径）** | **是（分桶微调）**：**C-02 归 static**（扫 `hud_colors.gd` 常量，用 `wcag_contrast`）；**G-04 归 runtime**（已实现，缺的是自动断言，走 GUT **不写 CI 桩**） | ✅ CLOSED |
| **C20** `budget_assert.gd` 落地范围 | E10-S2 | D14-A | 否 | ✅ CLOSED |
| **C21** C-02 可执行断言 | E10-S2 | D14-A | **是（函数名修正）**：改用既有 `HudColors.wcag_contrast()`，见 B4 | ✅ CLOSED |
| **C22** WARN-ONLY | E10-S2 | **D15-A** | 否；追加「**不得写入 ci.yml**」显式禁令 | ✅ CLOSED |

**合计：12 / 12 CLOSED。零遗留、零未闭合裁决项。**

---

## §8 交付小结

### §8.1 隐性地雷清单（N-8 ~ N-12，承接 Batch C 的 N-4~N-7）

> **v1.1 拆除状态**：**5 枚全部有实现级落点 + 验证钩子**，逐枚落点见 `batchd-impl-spec.md` **§6 地雷汇总索引**。
> **N-8 已升级为专章处理**（impl-spec **§3.1**）：给出 **可复制粘贴的检测机制**（`get_signal_list()` 契约测试 + 全参值断言），而非「注意一下」式建议。**N-8 的假绿机理已在 `addons/gut/signal_watcher.gd:77-97 / :122` 源码层核实为真**（变参回调 `_on_watched_signal(arg1..arg11=ARG_NOT_SET)` 会吞掉参数个数不符，`assert_signal_emitted` 照常通过）。

| # | 地雷 | 严重度 | 机理 | 拆除 |
| --- | --- | --- | --- | --- |
| **N-8** | `decoy_landed` 改签名可能产生**假绿**而非红 | 🔴 高 | `test_event_bus.gd:60` 用 1 参 emit 一个 3 参 signal。Godot 抛的是 `push_error("Error calling from signal")`，**不是断言失败**；而 GUT 的 signal watcher 用变参回调记录发射，`assert_signal_emitted`（`:79`）**很可能仍然通过**。结果：引擎日志有错、测试全绿、契约实际断裂 | ①签名与测试同 commit 改（§3 约束 1）②`:79` 必须**断言参数值**而非仅断言 emitted（§4）③CI 若可行，把 `push_error` 计入失败 |
| **N-9** | DECOY **数学上不可能**单次触发 SUSPICIOUS | 🔴 支柱级 | `gain_max = KS(15.0) × falloff_max(1.0) = 15.0 < THR_SUSP(25.0)`。即使爆响在守卫脚下也不够。需在 `DECAY=8 pts/s` 内连投 ≥2 次，而投掷物限量。**核心玩法动词静默失效，且不会有任何测试变红** | C14 suspicion floor（D12-A）+ `test_decoy_redirect_threshold` |
| **N-10** | ramp × dirty-cell 双重重算 / 顺序竞态 | 🟠 中 | ramp 期间若逐帧 `mark_cell_dirty` → 0.30s×60fps = 18 次重算，违 ADR-002；且产生「光看着亮、判定已暗」的灰区 | C18 visual-only 解耦（D13-A）+ `test_light_ramp_single_recompute` |
| **N-11** | 恒真断言让退出标准 #4 被**空壳满足** | 🔴 高 | R-05/G-02/V-02/G-04 皆为运行时量。若为凑齐「10 项断言」而写静态桩，扫描永远 pass → 退出标准字面达成、实质为零。当前 `budget_assert.gd` 74 行全 `_warn("TODO")` 正是这个形态的雏形 | C19 分流 + C20 明令删桩改注释 + `test_budget_assert_exit_zero` |
| **N-12** | 真实扫描首发即接 fail-closed gate → 假红挂全线 | 🟠 中 | `ci.yml:129–136` 的 N-7 对 `[Risky]` fail-closed。R-02 静态计数会误判运行时 spawn 的光、继承/实例场景；C-02 若把 `ALARM_FILL`(1.91:1) 计入载体亦会假红 | C22 保持 WARN-ONLY（D15-A）+ C21 载体白名单 |

> **地雷分布规律**（值得主理人注意）：N-8 / N-9 / N-11 三枚**都不会让任何测试变红**——它们是「绿着烂掉」型。Batch C 的三枚地雷同样偏此类。建议把「本次改动会不会制造一个恒真/假绿断言」固化为后续批次的常规评审问项。

### §8.2 计划文档修正

已按授权修正 `production/sprints/sprint1-plan.md`（详见该文件 §3）：E09-S4 移出 Batch D（Batch C 已完成）· E10-S1 标注已闭 · E04-S5 补入 Batch D 拓扑（消除 `E04×4` 散文与拓扑表的孤儿不一致）。**未触碰 `src/` 与 `tests/`。**

### §8.3 Sprint 1 五条退出标准可满足性 —— **v1.1 裁决后重估**

> **v1.0 结论**：3 条无条件满足 · 2 条有条件满足（条件为「C4 按已锁裁决计达成」+「D14 待拍板」）。
> **v1.1 变化**：**D14 已裁决为 A**；C4 早已按已锁定裁决计达成 ⇒ **两个条件全部消解**。

| # | 退出标准 | v1.0 | **v1.1（裁决后）** | 说明 |
| --- | --- | --- | --- | --- |
| 1 | 完整核心循环可玩 | 🟡 有条件 | 🟢 **满足** | E04-S5 补齐后「熄灯过场」缺口消除。C4 暴露软失败按**已锁定裁决**以 seam-placeholder 计达成（`_checkpoint_sink` Callable 被以正确实参调用即可；真 SaveManager 随 E01-S5 延 Sprint 2）。**该裁决已锁，不再是待办条件** |
| 2 | CI 冒烟全绿 | 🟢 | 🟢 **满足** | E10-S1 已闭，83/83；N-7 门 fail-closed 已落地。**D15-A 保证 Batch D 不给该门引入新的假红面** |
| 3 | 事件词汇零漂移 | 🟢 | 🟢 **满足** | C11 收口 `decoy_landed` 后 `event_bus.gd` == `system-breakdown` §2。§5.2 全 9 处变更点已在 impl-spec §3.1 落为逐行 checklist（含第 9 项文档侧 `Surface`→String 注记） |
| 4 | §7 预算断言运行 | 🟡 有条件 | 🟢 **满足** | **条件已消解**：D14-A 锁定「static 扫描 + GUT 运行时断言合并计为达成」。且 D14-A 同时**明令禁止恒真桩**，因此这条是**实质满足**而非空壳满足（N-11 已拆） |
| 5 | 控制清单达标 | 🟢 | 🟢 **满足** | C-02 已达（13.74:1，C21 补可执行断言）· V-02 ≤2Hz（Batch C）· G-02 ≤8（`RING_CAP`）· R-05 ≤0.12/≤0.4s（C16/C17 + H22）· G-04 ≤10Hz（Batch C 已实现，H27 补断言）。G-05 因 Sprint 1 无 A* 实现，标 N/A 而非未达 |

**净结论（v1.1）**：**5 / 5 全部满足，零有条件项、零阻塞项。**

> **诚实附注（不粉饰）**：上述「满足」的严格含义是 **「Batch D 按 impl-spec 全量落地后可满足」**，不是「今天已满足」。三条未动工 Story 若任一漏做，对应标准立即回落：
> - 漏 **E06-S4** → 标准 **3** 回落（签名仍漂移）；且 **1** 实质回落（DECOY 动词失效，N-9）
> - 漏 **E04-S5** → 标准 **1**、**5** 回落（无熄灯过场；R-05 无运行时承载）
> - 漏 **E10-S2** → 标准 **4** 回落
> - **E10-S2 若用恒真桩交差** → 标准 **4** 字面绿、实质空（**N-11**，本批最需要盯住的一种「达成」）
>
> 即：**可满足性 = 已确证；实际达成 = 取决于执行纪律。** 唯一本批无法消解的残留是 **G-05 标 N/A**（Sprint 1 无 A\*），这是范围决策而非缺口。

---

*Batch D 设计就绪评审 **v1.1（裁决收口版）** 完成。**D11–D15 五项裁决全数 CLOSED；C11–C22 十二条缺口全数 CLOSED；无未闭合裁决项、无 BLOCKED。** 实现规格见 `production/sprints/batchd-impl-spec.md`（工程唯一权威落地件）。—— 文策渊 · design-strategist*
