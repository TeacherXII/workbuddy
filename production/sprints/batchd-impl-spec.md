# Sprint 1 · Batch D 实现规格（Implementation-Ready Spec）

> **一句话裁定（退出标准）**：**全部 5 条 Sprint 1 退出标准在 Batch D 按本文全量落地后均可满足**（D14 口径已锁、C4 按已锁定裁决计达成、G-05 标 N/A 属范围决策而非缺口）；但「可满足」≠「已达成」——若 E10-S2 以恒真桩交差，标准 #4 将字面绿、实质空（N-11），这是本批唯一需要人盯的「假达成」通道。

| 字段 | 值 |
| --- | --- |
| **阶段** | Phase 5 · Sprint 1 · Batch D（E06-S4 DECOY 声圈 + E04-S5 熄灯过场 + E10-S2 §7 预算断言 + E10-S1 签收） |
| **文档版本** | v1.0（**实现就绪规格**；上游 `batchd-design-review.md` v1.1 的裁决落地件） |
| **作者** | 文策渊（design-strategist） |
| **任务 ID** | BATCHD-IMPL-01 |
| **裁决状态** | **D11 / D12 / D13 / D14 / D15 全部由主理人游承峰锁定为 A 案。评审 §7 五项裁决、§2 C11–C22 十二条缺口，全部 CLOSED。** |
| **批次范围** | 3 条可实施 Story：**E06-S4 · E04-S5 · E10-S2**；1 条签收：E10-S1（零代码改动） |
| **上游依据** | `batchd-design-review.md` v1.1（C11–C22 / §5.2 九处变更点 / N-8~N-12）· `batchc-impl-spec.md`（H1–H18 钩子基线、常量体例）· `design/gdd/systems/interactables.md`· `design/gdd/system-breakdown.md` §2 · `docs/architecture/control-manifest.md` §7 · 现存 `src/**` / `tests/**` / `.github/workflows/ci.yml` |
| **下游衔接** | 程基岩（engineering-lead，按 §8 顺序实现）· 严守真（quality-lead，按 §7 填充 H19–H29） |
| **测试钩子编号** | **H19 – H29（11 条）**，接续 Batch C 的 H1–H18 |
| **地雷编号** | **N-8 – N-12（5 枚）**，接续 Batch C 的 N-4 – N-7 |

> **本文用途**：Batch D 的**唯一权威实现落地件**——文件路径（新建/修改）、精确函数与信号签名、全部常量及其溯源、非显然逻辑的伪码、H19–H29 测试钩子、N-8~N-12 的实现级落点、执行顺序拓扑。
>
> **纪律**：本文**不写任何 `src/` 或 `tests/` 代码、不做 git 操作**。所有 GDScript 段落是**规格**不是实现。凡本文与上游 Story / 评审文字冲突处，**以本文为准**（本文已吸收 5 项主理人裁决 + 3 项事实修正）。
>
> **数值纪律**：本批**唯一的新增自由数值**是 `DECOY_REDIRECT_COOLDOWN_RT = 3.0`（D12-A 主理人明确确认）。其余全部常量均可溯源到 GDD / control-manifest / 既有代码，本文**不发明任何数字**。

---

## 0. 裁决收口速览（本文的全部前提）

| # | 裁决 | 锁定值 | 状态 | 落点 |
| --- | --- | --- | --- | --- |
| **D11** | `decoy_landed` 的 `surface` 语义 | **仅驱动 foley / 字幕变体**（复用 `FootfallVFX.FOOTFALL_SUBTITLE`）；**`radius` 恒 8.0**；Sprint 1 **不引入** `SURFACE_FACTOR` 半径调制 | **CLOSED** | §3.2 · §3.3 · §3.4 |
| **D12** | DECOY 如何真的生效（N-9） | 命中即 `sus = maxf(sus, THR_SUSP)` + **`DECOY_REDIRECT_COOLDOWN_RT = 3.0` s**（真实时钟，逐守卫）。**复用既有 `THR_SUSP=25.0`；不新增标度；不动 `intensity` 归一化；不加 `KS_DECOY`** | **CLOSED** | §3.5 · §6 N-9 |
| **D13** | E04-S5 ramp 性质（N-10） | **visual-only**；遮蔽 / 光照等级在 `toggle_light()` **瞬间一次性翻转**；ramp 期间**无逐帧重算**；`mark_cell_dirty` 全程**恰调 1 次** | **CLOSED** | §4 · §6 N-10 |
| **D14** | 退出标准 #4 验收口径 | **static 扫描 + GUT 运行时断言合并计为达成**。static → **R-02 / R-04 / R-06 / C-02**（+ V-06 弱扫）走 `budget_assert.gd` **真实扫描**；runtime → **R-05 / G-02 / V-02 / G-04 / G-05** 走 **GUT**。**⛔ 禁止恒真桩** | **CLOSED** | §5 · §6 N-11 |
| **D15** | budget_assert 何时接 gate | Batch D **WARN-ONLY**：exit 0、摘要不含 `[Risky]`、**不得写入 `.github/workflows/ci.yml`**。升级为 gate 排 Sprint 2 | **CLOSED** | §5.6 · §6 N-12 |

### 0.1 三项已接受的事实修正（**推翻评审 v1.0 文字，勿照旧实现**）

| # | 修正 | 影响 |
| --- | --- | --- |
| **M-1** | **`Surface` 是文档级抽象，代码库无此类型**。落地类型为 **`String`**（依据 `step_commit.gd:57`、`footfall_vfx.gd:32`、`SURFACE_FACTOR` 以 String 为键）。最终签名 `signal decoy_landed(pos: Vector3, surface: String, radius: float)`，**无默认参数**（GDScript signal 的默认值不会被 `emit()` 套用） | 写 `Surface` 直接编译失败；写默认值会给出「参数可省」的错误预期，直通 N-8 |
| **M-2** | **G-04 与 C-02 都已实现**（`patrol_ai.gd:34 DECISION_HZ=10.0` / `:70 decision_count`；`hud_colors.gd:31` CARRIER = **13.74:1**）。**缺的是自动断言，不是行为**。⇒ 两者**均不写 CI 恒真桩**：G-04 走 **GUT 断言**（H27），C-02 走 `budget_assert.gd` 的**真实数值扫描**（复用 `wcag_contrast`，非重写） | 评审 §2 C21 给出的 `contrast_ratio` / `_srgb_lin` / `_luminance` 三个函数名**在代码库中不存在**，照抄 = 编译失败或双份 WCAG 实现。以 §5.4 为准 |
| **M-3** | **B-1 拒绝维持**：`patrol_ai.gd:297` 的 `if vis > STIM_EPS:` 保护**保留**，`source==DECOY` **不做**无条件 `last_known` 写入 | 无条件写入 = DECOY 变成无视线判定的万能脱身键（**主导策略红线**）。D12-A 的 suspicion floor 已让 DECOY 生效，无需再破坏优先级 |

---

## 1. 本批交付物文件清单

| # | 文件 | 状态 | 归属 Story | 说明 |
| --- | --- | --- | --- | --- |
| **F1** | `src/core/event_bus.gd` | **修改** | E06-S4（契约前置） | 改 1 条签名（`:38`）+ 删 2 处 DEFERRED/NOTE 注释（`:8` / `:36`） |
| **F2** | `src/game/sound_propagation.gd` | **修改** | E06-S4 | 追加 2 常量 + 新增 `_on_decoy_landed()` + `_bind_bus()` 内连接 + 删 `:31` 延期注释 |
| **F3** | `src/game/patrol_ai.gd` | **修改** | E06-S4 | 追加 1 常量 + 2 状态变量；`_on_sound_emitted` 加 DECOY 标记；**`_decide()` 内加 floor**（不得放在 `_on_sound_emitted`，否则击穿 G-04） |
| **F4** | `src/game/light_model.gd` | **修改** | E04-S5 | 追加 6 常量 + 2 纯函数 + ramp 状态机（3 变量 / 4 方法 / 1 信号） |
| **F5** | `tests/ci/budget_assert.gd` | **修改** | E10-S2 | 5 项真实扫描（R-02/R-04/R-06/V-06/C-02）+ 删 3 桩改文件头注释（R-05/G-02/V-02）+ 保持 WARN-ONLY |
| **T1** | `tests/unit/test_event_bus.gd` | **修改** | E06-S4 | **`:60` emit 补参 + `:79` 改全参值断言 + 新增签名契约测试**（★ N-8，**必须与 F1 同 commit**） |
| **T2** | `tests/unit/test_sound_propagation.gd` | **修改** | E06-S4 | H19 / H20 / H21 |
| **T3** | `tests/unit/test_patrol_ai.gd` | **修改** | E06-S4 | H30-系列：H24 / H25 / H26（DECOY 消费侧 + N-9 反向断言） |
| **T4** | `tests/unit/test_light_model.gd` | **修改** | E04-S5 | H22 / H23（含 N-10 守卫） |
| **T5** | `tests/unit/test_budget_assert.gd` | **新建** | E10-S2 | H28 / H29（C-02 数值 + WARN-ONLY 守卫） |
| **T6** | `tests/unit/test_hud_slice.gd` | **不改** | E10-S2 | V-02 承载已存在（`:377` `assert_lte(HudSlice.EXPOSURE_PULSE_HZ, 2.0)`），仅在 F5 文件头引用 |
| **D1** | `design/gdd/system-breakdown.md:51` | **修改（文档）** | E06-S4 | `surface:Surface` → 标注「文档级类型名，落地为 String」（§5.2 第 9 项） |

> **不碰**：`.github/workflows/ci.yml`（**D15-A 显式禁令**，见 §5.6）· `src/ui/hud_colors.gd`（C-02 已达标，只读不改）· `src/ui/hud_slice.gd` · `src/game/vision_cone.gd` · `src/game/footfall_vfx.gd`（D11-A 只**读取** `FOOTFALL_SUBTITLE` 常量，不改文件）· 任何 `save_manager.gd` / `nav_server.gd`（D9 延 Sprint 2）。

---

## 2. 全批常量表（单一权威源，工程直接抄）

> **溯源等级**：`GDD` = 设计文档已锁 · `CM` = control-manifest 逐行 · `CODE` = 既有代码复用 · **`D12★`** = 主理人确认的唯一新增自由值 · `DERIVED` = 由已锁值派生并留余量（沿用 Batch C 对 `GRACE_RT` 的处理惯例）。

| 常量 | 值 | 单位 | 落点文件 | 溯源 | 断言钩子 |
| --- | --- | --- | --- | --- | --- |
| `DECOY_RADIUS` | **8.0** | m | `sound_propagation.gd`（追加于 `:33 SOURCE_DECOY` 附近） | **GDD** `interactables.md:19` 「radius≈8m」 | H19 |
| `DECOY_INTENSITY` | **1.0** | –（归一化 [0,1]） | `sound_propagation.gd` | **GDD/CODE** DECOY 为满响事件；域 [0,1] 由 `patrol_ai.gd:31 KS=15.0` × `suspicion_from_distance` 反推 | H19 |
| `DECOY_REDIRECT_COOLDOWN_RT` | **3.0** | s（真实时钟） | `patrol_ai.gd` | **D12★ 主理人确认的唯一新增自由值** | H25 |
| `THR_SUSP` | 25.0 | 点 | `patrol_ai.gd:27` | **CODE 复用，不改** | H24 · H26 |
| `STIM_EPS` | 0.001 | – | `patrol_ai.gd:40` | **CODE 复用，不改**（M-3 的 `vis` 保护判据） | H24 |
| `DECISION_HZ` / `TICK_DT` | 10.0 / 0.1 | Hz / s | `patrol_ai.gd:34/35` | **CODE 复用，不改**（G-04） | H27 |
| `SOURCE_DECOY` | `"DECOY"` | String | `sound_propagation.gd:33` | **CODE 复用，不改** | H19 |
| `RING_CAP` | 8 | 个 | `sound_propagation.gd:22` | **CM** G-02 `:82` | H21 |
| `FOG_BASE_MAX` | **0.05** | –（密度） | `light_model.gd` | **CM** R-04 `:21` | H22 |
| `FOG_RAMP_PEAK` | **0.12** | –（**base 之上的增量峰值**） | `light_model.gd` | **CM** R-05 `:22`（经 C15 修正解读：雾密度增量，非光能量） | H22 |
| `FOG_RAMP_MAX_RT` | **0.4** | s | `light_model.gd` | **CM** R-05 `:22` 硬顶 | H22 |
| `FOG_RAMP_RT` | **0.30** | s | `light_model.gd` | **DERIVED**：唯一取值点，留 25% 余量防帧抖动顶穿 0.4s 硬顶 | H22 · H23 |
| `VIGNETTE_EASE` | `Tween.EASE_IN_OUT` | – | `light_model.gd` | **CM** V-06 `:50`「缓动，禁硬切闪光」 | H22 |
| `VIGNETTE_TRANS` | `Tween.TRANS_SINE` | – | `light_model.gd` | **CM** V-06 `:50`（**禁 `TRANS_LINEAR`**——线性即硬切观感） | H22 · H28 |
| `LIGHT_BUDGET_MVP` | **12** | 个 | `budget_assert.gd` | **CM** R-02 `:19` | H28 |
| `LIGHT_BUDGET_TIER2` | **32** | 个 | `budget_assert.gd` | **CM** R-02 `:19` | H28 |
| `CONTRAST_MIN_C02` | **7.0** | :1 | `budget_assert.gd` | **CM** C-02 `:59` | H28 |
| `HUD_COLOR_PANEL_BASE` | `#16181D` | – | `hud_colors.gd:30` | **CODE 只读** | H28 |
| `HUD_COLOR_CARRIER` | `#DCE3EC` | –（13.74:1） | `hud_colors.gd:31` | **CODE 只读** | H28 |
| `HUD_COLOR_ALARM_FILL` | `#7A2E2E` | –（**1.91:1，FILL ONLY**） | `hud_colors.gd:35` | **CODE 只读 · ⛔ 必须排除出 C-02 白名单，否则假红（N-12）** | H28（**反向断言**） |

**硬编码红线**（承 `sprint1-stories.md` §5）：以上全部走常量。玩法/预算逻辑中**不得出现裸数** `8.0 / 1.0 / 3.0 / 25.0 / 0.05 / 0.12 / 0.4 / 0.30 / 12 / 32 / 7.0`。

---

## 3. E06-S4 · DECOY 声圈 ≈8m（★ 含 N-8 专章 + N-9 支柱级拆除）

### 3.1 ★★ N-8 专章：`decoy_landed` 签名变更的**假绿检测机制** ★★

> 这是本批**最高优先级**的一节。请工程与 QA 逐字执行，**不接受「注意一下」式处理**。

#### 3.1.1 假绿机理（已在 GUT 源码层核实为真，非推测）

读 `addons/gut/signal_watcher.gd`：

```
:122  watch_signals(obj)  →  对 obj 的【每一条】signal，统一 connect 到【同一个】变参回调
:77   func _on_watched_signal(arg1=ARG_NOT_SET, arg2=ARG_NOT_SET, ... arg11=ARG_NOT_SET)
:79-97  回调把 != ARG_NOT_SET 的实参收集成数组后记录
```

⇒ 当 `signal decoy_landed(pos, surface, radius)` 被 **1 参** `emit(Vector3(0,0,1))` 调用时：

| 层 | 行为 |
| --- | --- |
| Godot 引擎 | `push_error("Error calling from signal ...")` —— **这是 error log，不是断言失败** |
| GUT watcher | 记录为 `[[Vector3(0,0,1)]]`（参数数组长度 1，watcher 不校验 arity） |
| `assert_signal_emitted(_bus, "decoy_landed")`（`test.gd:699`） | **PASS ✅** |
| CI | **全绿** |
| 实际契约 | **已断裂**（消费侧 `_on_decoy_landed(pos, surface, radius)` 永远收不到调用） |

**结论：N-8 是真实的、可复现的、会让 CI 说谎的缺陷。** 必须用「机制」而非「纪律」来防。

#### 3.1.2 检测机制 ①：**`get_signal_list()` 契约测试**（copy-paste-ready，**推荐首选**）

这条测试**不依赖 emit**，直接对信号的**声明形状**下断言。它在「有人改了签名却没改测试」时**必然红**，且不受 GUT watcher 变参机制影响。

```gdscript
# tests/unit/test_event_bus.gd —— 新增（★ N-8 主防线）
# 契约测试：直接断言 signal 的【声明形状】（参数个数 + 顺序 + 类型），
# 不经过 emit / watcher，因此免疫 GUT signal_watcher 的变参吞参问题。
# 若有人改 decoy_landed 签名而不同步本测试 → 本测试【必然 RED】。
func test_decoy_landed_signature_contract() -> void:
	var found: Dictionary = {}
	for sig in _bus.get_signal_list():
		if sig["name"] == "decoy_landed":
			found = sig
			break
	assert_false(found.is_empty(), "decoy_landed signal must exist on EventBus")

	var args: Array = found["args"]
	# ① arity 必须恰为 3 —— 这一条就锁死了 N-8 的 1 参 emit 场景
	assert_eq(args.size(), 3,
		"decoy_landed arity must be 3 (pos, surface, radius); got %d" % args.size())
	# ② 参数名（防止顺序被人对调）
	assert_eq(args[0]["name"], "pos")
	assert_eq(args[1]["name"], "surface")
	assert_eq(args[2]["name"], "radius")
	# ③ 参数类型（M-1：surface 是 String，不是文档级的 `Surface`）
	assert_eq(args[0]["type"], TYPE_VECTOR3, "pos must be Vector3")
	assert_eq(args[1]["type"], TYPE_STRING,  "surface must be String (doc-level `Surface` has no GDScript counterpart)")
	assert_eq(args[2]["type"], TYPE_FLOAT,   "radius must be float (metres)")
```

#### 3.1.3 检测机制 ②：**全参值断言**（替换 `test_event_bus.gd:79` 的按名断言）

`assert_signal_emitted` 只校验「发过」，必须升级为校验「发了什么」。

```gdscript
# tests/unit/test_event_bus.gd:60  —— 修改 emit 桩（补足 3 参）
_bus.decoy_landed.emit(Vector3(0, 0, 1), "STONE", 8.0)

# tests/unit/test_event_bus.gd:79  —— 按名断言 → 全参值断言
# ★ 只保留 assert_signal_emitted 是 N-8 的假绿源：1 参 emit 也会通过。
assert_signal_emitted_with_parameters(
	_bus, "decoy_landed", [Vector3(0, 0, 1), "STONE", 8.0])

# 兜底（可选，更显式的 arity 取证）：
var p: Array = get_signal_parameters(_bus, "decoy_landed")
assert_eq(p.size(), 3, "emitted arg tuple must carry all 3 params (N-8 guard)")
```

> **两条机制的分工（都要，不可二选一）**：
> - **机制 ①** 防「**声明**被改而测试没跟上」——即使全项目没有任何 `emit`，它也照样红。
> - **机制 ②** 防「**发射侧**少传参」——`emit` 桩一旦回退到 1 参，参数元组比对立刻失败。
> - 单用 ② 有盲区：若有人把签名改回 1 参并同步把 emit 改回 1 参，② 会绿；此时靠 ① 兜住。

#### 3.1.4 检测机制 ③（可选加固，非阻塞）：把 `push_error` 计入失败

GUT 有 `assert_no_new_orphans()` 一类的环境级断言，但**不提供** `push_error` 捕获。若 CI 侧要加固，可在 headless 运行后 grep Godot stderr 中的 `Error calling from signal`：

```
# .github/workflows/ci.yml —— 【本批不做，登记为 Sprint 2 备选】
# godot --headless ... 2>&1 | tee gut.log
# ! grep -q "Error calling from signal" gut.log
```

⚠ **本批不实施**：这会改 `ci.yml`，与 D15-A「Batch D 不动 CI 门」的精神相邻，且 `push_error` 噪声未经校准。**登记为 Sprint 2 观察项**（同 D15 的升级窗口）。

#### 3.1.5 ★ 九处变更点全清单（评审 §5.2 逐条，缺一即红或假绿）

| # | 文件:行 | 现状 | 变更 | 提交约束 | 风险 |
| --- | --- | --- | --- | --- | --- |
| **1** | `src/core/event_bus.gd:38` | `signal decoy_landed(pos: Vector3)` | → 三参签名（§3.2） | **C1** | — |
| **2** | `src/core/event_bus.gd:8` | `# ... DEFERRED -> Batch D, E06-S4.` | **删除** DEFERRED 注释 | C1 | 词汇零漂移取证（退出标准 #3） |
| **3** | `src/core/event_bus.gd:36` | `# NOTE: Sprint 0 shape retained (§2 wants DecoyPayload{...})` | **删除**，替换为 §3.2 的说明块 | C1 | 同上 |
| **4** | `tests/unit/test_event_bus.gd:60` | `_bus.decoy_landed.emit(Vector3(0,0,1))` | → 补 `, "STONE", 8.0` | **C1（硬约束）** | ★★ **N-8 假绿源** |
| **5** | `tests/unit/test_event_bus.gd:79` | `assert_signal_emitted(_bus,"decoy_landed")` | → `assert_signal_emitted_with_parameters(...)` 全参值断言 | **C1（硬约束）** | ★★ **N-8 防护** |
| **5b** | `tests/unit/test_event_bus.gd`（新增） | — | 新增 `test_decoy_landed_signature_contract()`（§3.1.2） | **C1（硬约束）** | ★★ **N-8 主防线** |
| **6** | `src/game/sound_propagation.gd:31` | `# ... E06-S4 (DECOY) is Batch D.` | **删除**延期注释 | C2 | — |
| **7** | `src/game/sound_propagation.gd` | 无监听器 | 新增 `_on_decoy_landed()` + `_bind_bus()` 连接（§3.4） | C2 | — |
| **8** | `src/game/patrol_ai.gd` | 无 DECOY 分支 | `_on_sound_emitted` 打标 + **`_decide()` 内**加 floor（§3.5） | C3 | ★★ **支柱级（N-9）**；放错位置将击穿 **G-04** |
| **9** | `design/gdd/system-breakdown.md:51` | `surface:Surface` | 标注「文档级类型名，落地为 `String`」 | C2 或 C3（文档） | 防未来再漂移 |

#### 3.1.6 ★★ 提交边界硬规则（不可协商）

```
┌────────────────────────────────────────────────────────────────────┐
│ 【C1 · 原子提交】签名变更 + 测试更新 必须落在【同一个 commit】       │
│                                                                    │
│   变更点 1 · 2 · 3   (src/core/event_bus.gd)                       │
│              +                                                     │
│   变更点 4 · 5 · 5b  (tests/unit/test_event_bus.gd:60 / :79 / 新增)│
│                                                                    │
│   ⛔ 禁止拆成两个 commit。任何中间态都是坏态：                       │
│      · 先改 src 后改 test → 中间 commit 处于【假绿】（N-8 全形态）  │
│      · 先改 test 后改 src → 中间 commit 处于【真红】（阻塞他人）    │
│   ⛔ 禁止「先合签名、测试留 TODO」。                                │
│   ✅ 验收：该 commit 单独 checkout 出来跑 GUT 必须全绿，            │
│      且 Godot stderr 中【无】"Error calling from signal"。          │
└────────────────────────────────────────────────────────────────────┘
```

> 变更点 **6·7**（消费侧接线）与 **8**（floor）可以另起 commit（C2 / C3），因为它们**只新增监听器 / 分支，不改契约形状**——不存在中间态假绿。

---

### 3.2 F1 · `src/core/event_bus.gd`（契约前置，**批内最先做**）

**文件路径**：`src/core/event_bus.gd` — **修改**

```gdscript
# ── 替换 :38；同时删除 :8 的 DEFERRED 注释与 :36 的 NOTE ────────────────
## E06-S4 (Batch D). DecoyPayload per system-breakdown §2 L51.
## `surface` is a String key into StepCommit.SURFACE_FACTOR /
## FootfallVFX.FOOTFALL_SUBTITLE ("STONE"/"GRASS"/"METAL"/"MOSS"/"WOOD").
## The doc-level type name `Surface` has NO GDScript counterpart — String is the
## codebase-wide convention (step_commit.gd:57, footfall_vfx.gd:32).  [M-1]
## `radius` is METRES; nominal value SoundPropagator.DECOY_RADIUS (8.0).
## [D11-A] `surface` drives foley/subtitle variant ONLY — it does NOT modulate radius.
## ⚠ NO DEFAULT PARAMETERS: GDScript does not apply signal default values on emit();
##   a short emit() raises "Error calling from signal" at runtime, which GUT's
##   variadic signal watcher will NOT surface as a test failure. See N-8.
signal decoy_landed(pos: Vector3, surface: String, radius: float)
```

**变更规模**：1 条签名 + 2 处注释删除 + 1 处说明块新增。**无枚举变更、无其他签名变更。**

**回归面**：`grep -rn "decoy_landed" src/ tests/` 当前仅命中 `event_bus.gd`（声明 + 2 注释）与 `test_event_bus.gd`（`:60` emit / `:79` assert）。**无生产发射方、无生产消费方** ⇒ 回归面 = **1 源文件 3 行 + 1 测试文件 2 行 + 1 新增测试**。

---

### 3.3 F2-a · DECOY 常量组

**文件路径**：`src/game/sound_propagation.gd` — **修改**（追加于 `:33 const SOURCE_DECOY := "DECOY"` 附近；同时删除 `:31` 的「E06-S4 (DECOY) is Batch D」延期注释）

```gdscript
# ── E06-S4 (Batch D) DECOY constants ─────────────────────────────────────────
const DECOY_RADIUS := 8.0        # m  interactables.md §2 "radius≈8m"
                                 #    [D11-A] CONSTANT — no SURFACE_FACTOR modulation
                                 #    in Sprint 1. Revisit with E07 entity (Sprint 2).
const DECOY_INTENSITY := 1.0     # -  normalised loudness [0,1]. DECOY is a
                                 #    full-loudness event (contrast: footfall intensity
                                 #    is gait/surface-modulated). Do NOT raise above 1.0
                                 #    — that breaks the [0,1] contract shared with
                                 #    footfall and pollutes suspicion_from_distance.
```

---

### 3.4 F2-b · DECOY 监听器（E06-S4 消费侧）

**文件路径**：`src/game/sound_propagation.gd` — **修改**（新增方法 + `_bind_bus()` / `_ready()` 内连接）

**新增函数签名**：

```gdscript
func _on_decoy_landed(pos: Vector3, surface: String, radius: float) -> void
```

**连接点**（与既有 `_bind_bus()` / `_ready()` 的 EventBus 连接惯例一致）：

```gdscript
# _bind_bus() 内，与既有连接并列
if not _bus.decoy_landed.is_connected(_on_decoy_landed):
	_bus.decoy_landed.connect(_on_decoy_landed)
```

**实现伪码**（`emit()` 现签名为 `func emit(payload: Dictionary) -> Dictionary`，`:120-148`）：

```gdscript
func _on_decoy_landed(pos: Vector3, surface: String, radius: float) -> void:
	# E06-S4: DECOY is a SIGNAL-LEVEL sound source in Sprint 1.
	# The E07 physical throwable entity is deferred to Sprint 2 (plan D2).
	#
	# [D11-A] `surface` goes into the payload for foley/subtitle variant selection ONLY.
	#         It MUST NOT participate in the radius computation.
	var r: float = radius if radius > 0.0 else DECOY_RADIUS   # 边缘情况 ①
	emit({
		"origin":    pos,
		"radius":    r,
		"intensity": DECOY_INTENSITY,
		"source":    SOURCE_DECOY,
		"surface":   surface,          # ← 只读，供 foley/字幕；不进任何数值公式
	})
```

> **不新增位置参数**：`surface` 塞进 payload 字典（沿用 `step_commit.gd:71` 既有做法），避免二次签名漂移。

**D11-A 的 foley / 字幕落法**（`surface` 因此**不是死参数**）：

```gdscript
# 消费 surface 的唯一去处 —— 复用 FootfallVFX 既有查表，零新增映射表。
# FootfallVFX.FOOTFALL_SUBTITLE (footfall_vfx.gd:20-26) 已含
#   "STONE"/"GRASS"/"METAL"/"MOSS"/"WOOD" 五键。
# 未知键 → 回落到 FootfallVFX.footfall_subtitle() 的既有缺省分支（边缘情况 ③）。
```

**边缘情况（≥3 类）**：

| # | 情形 | 处理 | 断言 |
| --- | --- | --- | --- |
| ① | `radius <= 0.0`（发射方误传 / 未初始化） | 回落 `DECOY_RADIUS`（8.0），**不静默发一个半径 0 的哑声圈** | H19 |
| ② | `pos` 落在场景外 / 无守卫在范围内 | `emit()` 的 `target_guard_ids` 为空数组，**不报错、不发 ring**。DECOY 是「投出去没人听见」的合法结果 | H19 |
| ③ | `surface` 为未知字符串或空串 | **不崩、不抛**。foley 走 `FootfallVFX` 既有缺省；**数值路径完全不受影响**（D11-A 下 `surface` 不进公式，这是该裁决的额外鲁棒性收益） | H20 |
| ④ | 同帧多次 `decoy_landed` | 各自独立 `emit()`；声环受 `RING_CAP=8` FIFO 约束（G-02），**DECOY 不得绕过 FIFO** | H21 |

---

### 3.5 F3 · DECOY 重定向语义（★★ N-9 支柱级拆除 · D12-A）

**文件路径**：`src/game/patrol_ai.gd` — **修改**

#### 3.5.1 N-9 数值证明（为什么必须做这件事）

```
suspicion_from_distance(intensity, dist, radius) = max(0, intensity × (1 − dist/radius))
falloff_max = 1.0 × (1 − 0/8) = 1.0                    ← 声源正在守卫脚下
gain_max    = KS(15.0) × falloff_max(1.0) = 15.0 pts
THR_SUSP    = 25.0 pts
                    15.0 < 25.0   ⇒  数学上不可能
```

⇒ **单次 DECOY 在任何距离上都无法把 CALM 守卫推过 SUSPICIOUS**（半径中点 4m 处仅 7.5 pts）。玩家须在 `DECAY=8.0 pts/s` 衰减内连投 ≥2 次，而投掷物是限量资源（HUD `_item_charge_count`）。**核心玩法动词静默失效，且不会有任何测试变红。**

#### 3.5.2 新增常量与状态

```gdscript
# ── E06-S4 (Batch D) DECOY redirect [D12-A] ──────────────────────────────────
const DECOY_REDIRECT_COOLDOWN_RT := 3.0   # s (real clock) anti-spam, PER GUARD.
                                          # ★ The ONLY new free value in Batch D;
                                          #   principal-confirmed (D12-A).
var _last_decoy_rt: float = -999.0        # s (real clock); sentinel = "never"
var _pending_decoy: bool = false          # set by _on_sound_emitted, consumed in _decide
```

> **不新增** `KS_DECOY`、**不改** `KS=15.0`、**不改** `intensity` 归一化域、**不新增**任何可疑度标度。**复用 `THR_SUSP`。**

#### 3.5.3 ★ 落点纪律：floor 必须写在 `_decide()` 内，**不得**写在 `_on_sound_emitted()`

| | 写在 `_on_sound_emitted()`（❌） | 写在 `_decide()`（✅） |
| --- | --- | --- |
| 触发频率 | = **声音事件频率**（无上限） | = `DECISION_HZ` = **10Hz** |
| G-04 | **击穿**（`:84` 可疑度 FSM ≤10Hz） | 合规 |
| `decision_count`（`:70`） | 不递增 → H27 的 G-04 断言**测不到这条路径** | 正常纳入统计 |

```gdscript
# ── ① src/game/patrol_ai.gd :272-292 `_on_sound_emitted(payload)` 内 ──────────
#    位置：在既有 falloff 计算与 `_pending_sound_max` 更新之后。
#    这里【只打标，不改 suspicion】。
var src: String = payload.get("source", "")
if src == SoundPropagator.SOURCE_DECOY:
	_pending_decoy = true
	# 注意：last_known 不在此处写。沿用既有 _update_last_known 的
	# 「①可见→真实目标位 ②否则→声源 ③否则→保留」优先级即可 —— [M-3]

# ── ② src/game/patrol_ai.gd :224-257 `_decide(dt)` 内 ────────────────────────
#    位置：在 `_update_last_known(vis)` 【之后】，在 FSM 阈值判定【之前】。
#    理由：先让 last_known 按既有优先级落定（vis 保护在此生效），
#         再用 floor 把 suspicion 抬到阈值，守卫才会「去调查那个 last_known」。
if _pending_decoy:
	var now_rt: float = Time.get_ticks_msec() / 1000.0
	if (now_rt - _last_decoy_rt) >= DECOY_REDIRECT_COOLDOWN_RT:
		# [D12-A] DECOY 的设计意图是「重定向注意力」而非「叠加警觉」——
		#         因此用 floor（maxf）而非累加，复用既有 THR_SUSP，不引入新标度。
		#         maxf 保证：已 ALERT(60) 的守卫不会被 DECOY【降】到 25。
		suspicion = maxf(suspicion, THR_SUSP)
		_last_decoy_rt = now_rt
	_pending_decoy = false   # ★ 无论是否过冷却，都必须清标（否则冷却结束时补触发）
```

> **`maxf` 而非赋值的三条理由**：(a) 已 ALERT 的守卫不应被假声**降级**（否则 DECOY 成了「降警戒神器」，主导策略红线）；(b) 与 `THR_SUSP` 语义一致——DECOY 保证「至少到调查线」，不保证「刚好在调查线」；(c) 与既有 clamp[0,100] 不冲突，无需额外夹紧。

**边缘情况（≥3 类）**：

| # | 情形 | 处理 | 断言 |
| --- | --- | --- | --- |
| ① | 守卫**正看着玩家**（`vis > STIM_EPS`）时 DECOY 落地 | `last_known` **仍指向玩家真实位置**（`patrol_ai.gd:297` 的 `vis` 保护，**M-3 保留**）。suspicion 仍会被 floor 抬到 ≥25，但守卫不会被拉走 —— 这正是「DECOY 不是万能脱身键」的机制保证 | **H24** |
| ② | 冷却窗口（3.0s）内连投第 2 枚 | **不重复 floor**。但 `_pending_decoy` 仍被清标；声圈/foley 照常发（视听反馈不欺骗玩家：「响了，但守卫已经在调查了」） | **H25** |
| ③ | 已 ALERT（`suspicion ≈ 60+`）时 DECOY 落地 | `maxf(60, 25) = 60` —— **不降级**。DECOY 对已警戒守卫无「降温」作用 | H24 |
| ④ | 暂停（RTwP）中 DECOY 落地 | `_pending_decoy` 置位后**等到下一个决策 tick 才结算**；`Time.get_ticks_msec()` 走真实钟，与 `patrol_ai.gd:199` / `step_commit.gd:138-147` 既有约定一致 | H27（旁证） |
| ⑤ | `_pending_decoy` 与 `_pending_sound_max` 同 tick | **两者并行不冲突**：`_pending_sound_max` 走既有 `KS × falloff` 累加路径，floor 在其后执行取 max。**DECOY 既贡献常规增益，又保底到阈值** | H26 |

#### 3.5.4 ★★ N-9 **反向断言**：防止未来有人拆掉 floor 退回纯 `KS×falloff`

> **交付物 4 的正面回答。** 常规测试只证明「加了 floor 之后能过」；一旦有人（重构、合并冲突、"简化"）删掉 floor，常规测试可能因为测试里连投了两次而**依然绿**。反向断言的职责是：**让「退回纯 KS×falloff 路径」这件事本身变红。**

**H26 · `test_decoy_single_throw_crosses_threshold_via_floor`**（`tests/unit/test_patrol_ai.gd`）

```gdscript
# ★★ N-9 REVERSE ASSERTION ★★
# 本测试的存在意义：若有人移除 DECOY suspicion floor 并退回纯 KS×falloff 路径，
# 本测试【必须 RED】。
#
# 数学护栏：KS(15.0) × falloff_max(1.0) = 15.0 < THR_SUSP(25.0)
#   ⇒ 纯累加路径下，【单次】DECOY 在【任何】距离上都不可能跨过 25.0。
#   ⇒ 因此「单次 DECOY 后 suspicion >= THR_SUSP」这一断言，
#      在没有 floor 的实现下【数学上不可能通过】。这就是反向锁。
func test_decoy_single_throw_crosses_threshold_via_floor() -> void:
	var brain := _make_calm_guard()          # suspicion == 0.0, fsm == CALM
	assert_eq(brain.suspicion, 0.0)

	# 【前置护栏】先把「纯路径不够」这件事本身断言下来。
	# 若未来有人改了 KS 或 THR_SUSP 让 15 >= 25 成立，本断言会红并提示
	# 「N-9 的数学前提已变，请重新评估本测试的反向锁是否仍成立」。
	assert_lt(GuardBrain.KS * 1.0, GuardBrain.THR_SUSP,
		"N-9 premise: pure KS x falloff must be INSUFFICIENT. " +
		"If this fires, the reverse-assertion below is no longer a valid lock.")

	# 【单次】DECOY，且刻意放在半径中点（4m）—— 连 falloff_max 都拿不到，
	# 纯路径下只有 7.5 pts。这样即使有人把 falloff 调满也救不回来。
	_emit_decoy(brain, dist_m = 4.0, surface = "STONE")
	_advance_decision_ticks(brain, 1)        # 走一个 _decide() tick

	# 【反向锁】纯 KS×falloff 路径下此处必为 7.5 → 断言必红。
	assert_gte(brain.suspicion, GuardBrain.THR_SUSP,
		"A SINGLE decoy must reach THR_SUSP. Pure KS x falloff yields only %.1f pts " % (GuardBrain.KS * 0.5) +
		"at mid-radius — if this fails, the D12-A suspicion floor has been removed " +
		"or bypassed. DECOY is a core verb; it MUST work on one throw. [N-9]")
	assert_eq(brain.fsm_state, EventBus.GuardState.SUSPICIOUS,
		"floor must actually drive the FSM, not just the scalar")
```

> **为什么这条锁是牢的**：
> 1. **测距点选在 4m（半径中点）** 而非 0m。纯路径上限 15，中点仅 7.5 —— 留出 3.3× 的差距，任何「微调 KS 就能蒙混过关」的路都被堵死（要蒙混需把 `KS` 提到 ≥50，那会同时让 Batch C 的 **H2 `test_suspicion_thresholds`** 变红）。
> 2. **单次投掷**（不连投）。这是 N-9 的原始失效场景，也是设计意图（DECOY 是限量资源）。
> 3. **前置护栏断言** `KS × 1.0 < THR_SUSP`。它让「数学前提被改」和「floor 被删」两种失败**给出不同的错误信息**，避免后人误判。
> 4. **同时断言 `fsm_state`**。防止有人只把 scalar 抬上去却没让 FSM 跟着转（半吊子修复）。

---

## 4. E04-S5 · 可熄灯过场（D13-A · visual-only）

### 4.1 现状取证（这是一条真正的孤儿 Story）

| 证据 | 内容 |
| --- | --- |
| `sprint1-plan.md:55` vs `:62` | 散文写 `E04×4（S3/S4/S5/S7）`，批次拓扑 Batch A 只列 `S3/S4/S7` —— **S5 从未进入任何批次** |
| `src/game/light_model.gd` | **无任何 ramp / fog / vignette 状态**（`class LightModel extends RefCounted`） |
| `tests/unit/test_light_model.gd` | 覆盖 S1/S2/S3/S4/S7，**无 ramp 测试** |

⇒ 本 Story 是**从零新增**，不是修补。

### 4.2 F4-a · 常量组

**文件路径**：`src/game/light_model.gd` — **修改**（新增常量块）

```gdscript
# ── E04-S5 extinction cutscene (R-04 / R-05 / V-06) [D13-A] ──────────────────
# R-05 原文（control-manifest :22）：「熄灯过场雾 ramp ≤ 0.12 且持续 ≤ 0.4s 后回落」
# ★ C15 修正：0.12 是【叠加在体积雾 base 密度之上的增量峰值】（无量纲密度），
#   不是光能量。绝对峰值密度 = base(≤0.05) + delta(≤0.12) = ≤ 0.17。
const FOG_BASE_MAX    := 0.05              # -  R-04 ceiling (control-manifest :21)
const FOG_RAMP_PEAK   := 0.12              # -  R-05 additive peak ABOVE base (:22)
const FOG_RAMP_MAX_RT := 0.4               # s  R-05 hard ceiling on ramp lifetime (:22)
const FOG_RAMP_RT     := 0.30              # s  chosen lifetime; 0.30 <= 0.40 (25% margin
                                           #    against frame-jitter overshoot, same
                                           #    convention as Batch C GRACE_RT)
const VIGNETTE_EASE   := Tween.EASE_IN_OUT # V-06 「缓动（ease），禁硬切闪光」(:50)
const VIGNETTE_TRANS  := Tween.TRANS_SINE  # V-06 no flash, no step. ⛔ NEVER TRANS_LINEAR.
```

### 4.3 F4-b · ramp 纯函数（静态，headless 安全，可单测）

```gdscript
# 归一化过场进度 t ∈ [0,1]，t = elapsed_rt / FOG_RAMP_RT
# 单峰 sin：0 → peak @ t=0.5 → 0，保证 R-05 原文的「后回落」
static func fog_ramp_delta(t: float) -> float:
	var u := clampf(t, 0.0, 1.0)
	return FOG_RAMP_PEAK * sin(PI * u)

static func fog_density_at(t: float, base: float) -> float:
	return minf(base, FOG_BASE_MAX) + fog_ramp_delta(t)
```

### 4.4 F4-c · ramp 状态机（新增函数与信号签名）

**新增信号**：

```gdscript
## E04-S5. Emitted every visual frame during the extinction ramp.
## [D13-A] VISUAL-ONLY: consumers MUST NOT feed this back into occlusion,
## light-level or any gameplay read. See N-10.
signal fog_ramp_tick(density_delta: float, progress: float)
```

**新增状态**：

```gdscript
var _ramp_active: bool = false
var _ramp_start_rt: float = 0.0      # s, real clock (Time.get_ticks_msec()/1000.0)
var _ramp_light_id: int = -1         # 待在 ramp 末释放实时光的灯 id（R-02，见 §4.6）
```

**新增方法签名**：

| 签名 | 职责 |
| --- | --- |
| `func begin_extinction_ramp(light_id: int) -> void` | 启动/**重置** ramp（不叠加）。**由 `toggle_light()` 在状态已翻转之后调用** |
| `func update_ramp() -> void` | 每视觉帧推进；到期收尾。**不接受 `dt` 参数**——强制走真实钟（见边缘情况 ④） |
| `func is_ramp_active() -> bool` | 供测试与消费方查询 |
| `func ramp_progress() -> float` | 返回 `t ∈ [0,1]`，供测试断言 |

**实现伪码**：

```gdscript
func begin_extinction_ramp(light_id: int) -> void:
	# 边缘情况 ①：过场中再次 toggle → 【重置】而非叠加。
	# 两条 sin 叠加峰值可达 0.24，直接击穿 R-05(0.12)。
	_ramp_start_rt = Time.get_ticks_msec() / 1000.0
	_ramp_light_id = light_id
	_ramp_active = true
	# ⚠ 此处【不】调用 mark_cell_dirty —— 它已由 toggle_light() 调过恰好 1 次。[N-10]

func update_ramp() -> void:
	if not _ramp_active:
		return
	var now_rt: float = Time.get_ticks_msec() / 1000.0
	var t: float = 0.0 if FOG_RAMP_RT <= 0.0 else (now_rt - _ramp_start_rt) / FOG_RAMP_RT
	# 边缘情况 ③：FOG_RAMP_RT<=0 或 dt 尖峰 → clampf 保证 t>1 时 delta 归 0
	fog_ramp_tick.emit(fog_ramp_delta(t), clampf(t, 0.0, 1.0))
	if t >= 1.0:
		_ramp_active = false
		_release_realtime_light(_ramp_light_id)   # ★ R-02 释放【在 ramp 末】，见 §4.6
		_ramp_light_id = -1
```

### 4.5 ★ N-10 解耦规则（D13-A 裁决正文，写死进实现）

```
E04-S5 的 ramp 是 **VISUAL-ONLY**。

① 遮蔽判定 / 光照等级在 toggle_light() 的【瞬间】一次性翻转。
   light_state_changed 只 emit 一次；mark_cell_dirty 只调用一次
   —— 与 E04-S4/S7 现有行为【完全不变】。

② ramp 只驱动三样东西：
   · 体积雾 density delta（R-04 / R-05）
   · vignette 缓动（V-06）
   · 实时光释放时点（R-02，见 §4.6）
   三者【皆不参与】可见性 / 光照等级 / 任何 gameplay 计算。

③ 因此 ramp 【不得】读写任何 gameplay 状态，
   【不得】再次触发 mark_cell_dirty 或任何重算。
```

**三条理由**：(a) **ADR-002 合规**——重算次数从 `0.30s × 60fps = 18 次` 降回 **1 次**；(b) **机制可预测**——玩家按下即生效，不存在「灯看着还亮但已算作暗」的 0.3s 灰区（gameplay reads 与视觉脱钩）；(c) V-06 的柔和过场目的**本就是视觉的**。

### 4.6 ★ R-02 × V-06 的隐藏耦合（必须显式实现）

```
实时光的【释放】（OmniLight3D 数量 −1）必须发生在 ramp【结束】时，
而不是 ramp 开始时。

开始就删灯 ⇒ 光在视觉上还在衰减、灯却已被移除 ⇒ 产生硬切闪光 ⇒ 违反 V-06。
```

⇒ 落在 `update_ramp()` 的 `t >= 1.0` 分支内调 `_release_realtime_light()`（§4.4 伪码已体现）。

### 4.7 边缘情况汇总（≥3 类）

| # | 情形 | 处理 | 断言 |
| --- | --- | --- | --- |
| ① | 过场期间再次 toggle | **重置** `_ramp_start_rt`，保持**单条** ramp。⛔ 不叠加（叠加峰值 0.24 击穿 R-05） | **H23** |
| ② | `base` 已超 R-04 上限 | `fog_density_at` 用 `minf(base, FOG_BASE_MAX)` 夹紧，防上游配错雾吃掉 R-05 余量 | H22 |
| ③ | `FOG_RAMP_RT <= 0` / dt 尖峰（headless、断点、加载卡顿） | `clampf(t,0,1)` 保证 `t>1` 时 `sin(PI×1)=0` → delta 归 0，**不会卡在峰值永久浓雾** | H22 |
| ④ | 暂停（RTwP） | ramp 走**实时钟** `Time.get_ticks_msec()`（同 `patrol_ai.gd:199` / `step_commit.gd:138-147` 既有约定），暂停不冻结在半程。**`update_ramp()` 刻意不收 `dt` 参数**，从签名层杜绝有人误传游戏时钟 | H23 |
| ⑤ | ramp 未结束时对象被释放 | `_ramp_active` 随对象销毁自然失效；`_release_realtime_light` 不执行 —— 灯节点也随场景销毁，无泄漏 | — |

---

## 5. E10-S2 · §7 预算断言（D14-A 分流 + D15-A WARN-ONLY）

### 5.1 现状取证

`tests/ci/budget_assert.gd`（74 行，`extends SceneTree`）：**6 个检查全部是 `_warn(..."TODO: implement scan")` 桩**，exit 0。这正是 **N-11「恒真断言」的雏形形态**。

### 5.2 ★ D14-A 分流表（**唯一权威**）

```
凡「可由静态资产 / 常量表判定」者 → tests/ci/budget_assert.gd 真实扫描
凡「只有运行时才有值」者          → GUT 单测承载，budget_assert 中【明确不写桩】

⛔ 写恒真桩比不写更危险：它让退出标准 #4 在【字面上】被满足，实质是空壳。[N-11]
```

| 红线 | 定义（control-manifest 行号） | 分流 | 承载 | 本批动作 |
| --- | --- | --- | --- | --- |
| **R-02** | 动态点光同屏 MVP≤12 / Tier2≤32 (`:19`) | **static** | `budget_assert.gd` 扫 `.tscn` 的 `OmniLight3D`/`SpotLight3D` 节点数 | **实现真实扫描** |
| **R-04** | 体积雾 base ≤0.05 (`:21`) | **static** | 扫 `Environment` / `FogVolume` 资源的 density | **实现真实扫描** |
| **R-05** | 雾 ramp ≤0.12 且 ≤0.4s (`:22`) | **runtime** | `test_light_model.gd::test_light_toggle_ramp_within_budget`（**H22**，本批由 E04-S5 提供） | **删桩 → 文件头注释** |
| **R-06** | 静态几何 LightmapGI 烘焙 (`:23`) | **static** | 扫 `.tscn` 中 `LightmapGI` 存在性 + 静态 mesh 的 UV2 | **实现真实扫描** |
| **V-02** | 暴露脉动 ≤2Hz (`:46`) | **runtime** | `test_hud_slice.gd:377` `assert_lte(HudSlice.EXPOSURE_PULSE_HZ, 2.0)` + `test_vision_cone.gd:174`（**Batch C 已有**） | **删桩 → 文件头注释** |
| **V-06** | 转场缓动、禁硬切 (`:50`) | **static（弱）** | 扫 `light_model.gd` 的 `VIGNETTE_TRANS` 非 `TRANS_LINEAR` | **实现（弱扫）** |
| **G-02** | 同屏声环 ≤8 (`:82`) | **runtime** | `test_sound_propagation.gd::test_ring_vfx_capped_at_eight`（**Batch B 已有**） | **删桩 → 文件头注释** |
| **G-04** | 可疑度 FSM ≤10Hz (`:84`) | **runtime** | `patrol_ai.gd:34 DECISION_HZ` + `:70 decision_count`（**Batch C 已实现**）→ **H27** GUT 断言 | **不新增桩**（M-2） |
| **G-05** | A* 仅状态转换触发 (`:85`) | **runtime** | Sprint 1 **无 A\* 实现** | **不写桩**，标 Sprint 2 |
| **C-02** | 关键指示对比度 ≥7:1 (`:59`) | **static** | 扫 `hud_colors.gd` 常量表，**复用 `HudColors.wcag_contrast()`** | **实现真实扫描** |

### 5.3 F5-a · 文件头（防止后人补回恒真桩）

```gdscript
# tests/ci/budget_assert.gd —— 文件头必须写清分流
#
# [D14-A] STATIC-FEASIBLE budgets are scanned here with REAL scans.
# [D14-A] RUNTIME-ONLY budgets are deliberately NOT scanned here.
#         A static scan of a runtime quantity is an ALWAYS-PASS assertion, which
#         would satisfy Sprint 1 exit criterion #4 in letter and void it in
#         substance. Do NOT "helpfully" add stubs for the entries below. [N-11]
#
#   R-05 -> tests/unit/test_light_model.gd::test_light_toggle_ramp_within_budget
#   G-02 -> tests/unit/test_sound_propagation.gd::test_ring_vfx_capped_at_eight
#   V-02 -> tests/unit/test_hud_slice.gd (EXPOSURE_PULSE_HZ) +
#           tests/unit/test_vision_cone.gd (CONE_VFX_PULSE_HZ)
#   G-04 -> src/game/patrol_ai.gd DECISION_HZ / decision_count (Batch C)
#           asserted by tests/unit/test_patrol_ai.gd::test_fsm_tick_le_10hz
#   G-05 -> no A* in Sprint 1; revisit in Sprint 2
#
# [D15-A] WARN-ONLY in Batch D: always exit 0, never print "[Risky]",
#         and this file MUST NOT be referenced from .github/workflows/ci.yml.
#         Gate promotion is a Sprint 2 decision. [N-12]
```

### 5.4 F5-b · C-02 真实扫描（★ 修正 C21 的函数名）

> ⛔ **评审 v1.0 C21 给出的 `contrast_ratio` / `_srgb_lin` / `_luminance` 三个名字在代码库中不存在。**
> `src/ui/hud_colors.gd` 实际暴露：`static func relative_luminance(c: Color)`（`:54`）、`static func wcag_contrast(fg: Color, bg: Color) -> float`（`:58`）。
> **必须复用，不得重写**——重写会产生双份 WCAG 实现，与 Batch C 的 H12 用不同代码算同一红线。

```gdscript
const HudColors := preload("res://src/ui/hud_colors.gd")

# C-02: 关键指示（可疑度 / 暴露）【载体】对比度 >= 7:1 vs panel base
# ★ 载体白名单 —— 只有「承载信息的前景色」入 C-02。
#   HUD_COLOR_ALARM_FILL (#7A2E2E, 1.91:1) 是 hud_slice.gd:367 标注的
#   "FILL ONLY, a <= 0.35"，【非信息载体】。把它算进来会产生【假红】[N-12]。
const C02_CARRIERS := ["HUD_COLOR_CARRIER"]      # 显式白名单，新增载体须显式登记
const CONTRAST_MIN_C02 := 7.0

func _check_contrast_c02() -> void:
	var base: Color = HudColors.HUD_COLOR_PANEL_BASE
	for name in C02_CARRIERS:
		var fg: Color = HudColors.get(name)
		var r: float = HudColors.wcag_contrast(fg, base)
		if r < CONTRAST_MIN_C02:
			_warn("C-02", "%s contrast %.2f:1 < %.1f:1" % [name, r, CONTRAST_MIN_C02])
```

### 5.5 F5-c · 其余 static 扫描（R-02 / R-04 / R-06 / V-06）

**扫描面现状**：`src/main/sprint0.tscn` 是仓库中**唯一**的 `.tscn`；无 `.glb` / `.mesh` 静态网格资产。

⇒ **诚实标注**：这四项扫描在 Batch D 的**实际覆盖面接近空集**，但它们**不是恒真桩**——区别在于：

| | 恒真桩（❌ N-11） | 真实扫描但输入为空（✅ 本批） |
| --- | --- | --- |
| 代码 | `_warn("TODO: implement scan")` | 真的遍历 `.tscn`、真的数节点、真的比阈值 |
| 加一个超标资产后 | **仍然 pass** | **立刻告警** |
| 性质 | 假断言 | 真断言，当前样本为空 |

```gdscript
# R-02: 逐 .tscn 统计 OmniLight3D / SpotLight3D 实例数
const LIGHT_BUDGET_MVP := 12
const LIGHT_BUDGET_TIER2 := 32
# 扫描面：res://src/main/**.tscn（当前仅 sprint0.tscn）
# 计数口径：递归子节点；【排除】编辑器专用节点与 owner==null 的运行时 spawn 占位
# ⚠ 继承场景 / 实例场景可能重复计数 —— 这正是 D15-A 要求 WARN-ONLY 的原因 [N-12]

# R-04: 扫 Environment.volumetric_fog_density / FogVolume 的 density
#       与 LightModel.FOG_BASE_MAX (0.05) 比

# R-06: 扫 .tscn 中 LightmapGI 节点存在性；对静态 MeshInstance3D 检查 UV2
#       ⚠ 当前仓库无静态网格资产 → 本项当前无命中，属【真扫空集】而非恒真

# V-06（弱扫）: 断言 LightModel.VIGNETTE_TRANS != Tween.TRANS_LINEAR
#              且 VIGNETTE_EASE 为 EASE_IN_OUT / EASE_IN / EASE_OUT 之一
```

### 5.6 F5-d · ★ D15-A：WARN-ONLY 硬约束

```
① 所有检查一律走 _warn(...)，【永远 exit 0】。
② 摘要中【绝不】出现 "[Risky]" 字样
   —— ci.yml:120-145 的 N-7 门对 "[Risky]" 是 fail-closed，一出现即挂全线。
③ ⛔【不得】在 .github/workflows/ci.yml 中新增对 budget_assert.gd 的任何引用。
```

> **现状核查**：`grep -n "budget_assert" .github/workflows/ci.yml` → **零命中**。
> ⇒ D15-A 的「不接 gate」在事实层面**已经成立**。
> ⇒ **本批的真实风险不是「去解绑」，而是工程「顺手把它加进 ci.yml」。** 因此上面第 ③ 条写成显式禁令，并由 **H29** 守卫。

---

## 6. 地雷汇总索引（N-8 ~ N-12 · 工程 checklist）

| # | 地雷 | 严重度 | 落点 Story | **实现级落点（文件:函数）** | 验证钩子 | 漏做后果 |
| --- | --- | --- | --- | --- | --- | --- |
| **N-8** | `decoy_landed` 改签名产生**假绿** | 🔴 高 | E06-S4 | **①** `src/core/event_bus.gd:38` 签名 + `tests/unit/test_event_bus.gd:60/:79` **同 commit（C1）**<br>**②** `test_event_bus.gd` 新增 `test_decoy_landed_signature_contract()`（`get_signal_list()` 契约测试，§3.1.2）<br>**③** `:79` 改 `assert_signal_emitted_with_parameters`（§3.1.3） | **H19** + `test_decoy_landed_signature_contract` | 引擎 log 有 error、测试全绿、契约实际断裂；消费侧 `_on_decoy_landed` 永不被调用 |
| **N-9** | DECOY **数学上不可能**单次触发 SUSPICIOUS | 🔴 **支柱级** | E06-S4 | `src/game/patrol_ai.gd`：常量 `DECOY_REDIRECT_COOLDOWN_RT` + `_pending_decoy` 标记（`_on_sound_emitted`）+ **`_decide()` 内** `suspicion = maxf(suspicion, THR_SUSP)`（§3.5.3） | **H26（反向断言）** + H24 + H25 | 核心玩法动词静默失效；**且不会有任何测试变红** |
| **N-10** | ramp × dirty-cell 双重重算 | 🟠 中 | E04-S5 | `src/game/light_model.gd`：`begin_extinction_ramp()` / `update_ramp()` **均不调** `mark_cell_dirty`；仅 `toggle_light()` 调 1 次（§4.4 / §4.5） | **H23**（`mark_cell_dirty` 调用计数 == 1） | 0.30s×60fps = **18 次重算**，违 ADR-002；产生「光看着亮、判定已暗」灰区 |
| **N-11** | 恒真断言让退出标准 #4 **空壳满足** | 🔴 高 | E10-S2 | `tests/ci/budget_assert.gd`：**删除** `_check_light_extinction_ramp`(R-05) / `_check_sound_rings`(G-02) / `_check_pulse_frequency`(V-02) 三桩 → 改文件头注释指向承载单测（§5.3）；R-02/R-04/R-06/V-06/C-02 落**真实扫描**（§5.4/§5.5） | **H28**（C-02 真值 ≈13.74，非恒真）+ **H29** | 退出标准 #4 字面达成、实质为零 |
| **N-12** | 首版扫描接 fail-closed gate → 假红挂全线 | 🟠 中 | E10-S2 | `budget_assert.gd`：全 `_warn` / exit 0 / 无 `[Risky]`；**`ci.yml` 零新增引用**（§5.6）；C-02 **载体白名单**排除 `ALARM_FILL`（§5.4） | **H29** | 一次误判（运行时 spawn 光 / 继承场景重复计数 / `ALARM_FILL` 1.91:1）挂掉整条流水线 |

> **地雷分布规律（承 Batch C 观察）**：**N-8 / N-9 / N-11 三枚都不会让任何测试变红**——它们是「**绿着烂掉**」型，与 Batch C 的三枚同类。本批的应对是：三枚全部配**反向断言 / 契约断言**，而非仅配正向用例。
>
> **建议固化为常规评审问项**（已在评审 §8.1 提出）：*「本次改动会不会制造一个恒真断言或假绿断言？」*

---

## 7. 测试钩子映射表（H19 – H29 · 接续 Batch C 的 H1–H18）

> **约定**（承 Batch C §8）：`@ci:*` 类硬约束在本批**按 D14-A 分流**——static 项落 `budget_assert.gd` 真实扫描，runtime 项落 GUT 断言。

| H# | Story | 测试文件 | 钩子名 | 断言要点 | 状态 |
| --- | --- | --- | --- | --- | --- |
| **H19** | E06-S4 | `test_sound_propagation.gd` | `test_decoy_sound_radius` | `decoy_landed(pos,"STONE",8.0)` → `sound_emitted` payload：`source=="DECOY"` · `radius==8.0` · `origin==pos` · `intensity==1.0`；**`radius<=0` 时回落 8.0**（边缘 ①）；范围内无守卫 → `target_guard_ids` 空且不报错（边缘 ②） | 新增 |
| **H20** | E06-S4 | `test_sound_propagation.gd` | `test_decoy_surface_is_foley_only` | **D11-A 取证**：`surface` 出现在 payload 中（非死参数）；**`surface` 取 `"MOSS"` 与 `"STONE"` 时 `radius` 完全相同**（反向证明未引入 `SURFACE_FACTOR` 半径调制）；未知 surface 不崩（边缘 ③） | 新增 |
| **H21** | E06-S4 | `test_sound_propagation.gd` | `test_decoy_respects_ring_cap` `@ci:G-02` | 连发 12 次 DECOY → 声环实例 ≤ `RING_CAP(8)`；**DECOY 不得绕过 FIFO**（G-02 覆盖新来源，边缘 ④） | 新增 |
| **H22** | E04-S5 | `test_light_model.gd` | `test_light_toggle_ramp_within_budget` `@ci:R-05` | `fog_ramp_delta` **峰值 ≤ 0.12**（采样 t=0..1 取 max）· `FOG_RAMP_RT(0.30) <= FOG_RAMP_MAX_RT(0.4)` · `t>1` 时 delta **归 0**（边缘 ③）· `fog_density_at` 在 `base=0.9` 时被 `minf` 夹到 `0.05+delta`（边缘 ②）· `VIGNETTE_TRANS != Tween.TRANS_LINEAR`（V-06） | 新增（**R-05 唯一承载**） |
| **H23** | E04-S5 | `test_light_model.gd` | `test_light_ramp_single_recompute` | ★ **N-10 守卫**：整段 ramp 内 `mark_cell_dirty` **恰被调用 1 次**（注入计数 spy）；**过场中再 toggle → 峰值仍 ≤0.12**（重置不叠加，边缘 ①）；ramp 走**实时钟**，`Engine.time_scale` 变化不影响进度（边缘 ④）；**光释放发生在 `t>=1.0` 而非 `t==0`**（R-02×V-06 耦合，§4.6） | 新增（**高价值**） |
| **H24** | E06-S4 | `test_patrol_ai.gd` | `test_decoy_redirect_respects_vision_guard` | ★ **M-3 取证**：`vis > STIM_EPS` 时 DECOY 落地 → `last_known` **仍为玩家真实位置**（`vis` 保护未被削弱）；`vis == 0` 时 → `last_known` 为声源位；**已 ALERT(60) 时 `maxf` 不降级**（边缘 ③） | 新增 |
| **H25** | E06-S4 | `test_patrol_ai.gd` | `test_decoy_redirect_cooldown` | 冷却窗（`DECOY_REDIRECT_COOLDOWN_RT=3.0`）内第 2 次 DECOY **不重复 floor**（边缘 ②）；3.0s 后第 3 次**恢复生效**；冷却走**真实钟**；**`_pending_decoy` 在冷却内也被清标**（不得在冷却结束时补触发） | 新增 |
| **H26** | E06-S4 | `test_patrol_ai.gd` | `test_decoy_single_throw_crosses_threshold_via_floor` | ★★ **N-9 反向断言**（§3.5.4 全文）：前置护栏 `KS×1.0 < THR_SUSP`；**半径中点 4m 单次投掷** → `suspicion >= THR_SUSP` 且 `fsm == SUSPICIOUS`。**移除 floor ⇒ 本测试数学上必红** | 新增（★★ **本批最高价值**） |
| **H27** | E10-S2 | `test_patrol_ai.gd` | `test_fsm_tick_le_10hz`（**扩展既有**） | **G-04 runtime 承载**（M-2：行为已实现，本批补断言）：追加断言「**DECOY floor 路径不额外增加 `decision_count`**」——即高频 `decoy_landed` 轰炸下 `decision_count` 仍 ∈[10,20]/2s。**证明 floor 确实在 `_decide()` 内而非 `_on_sound_emitted` 内**（§3.5.3） | **扩展**（勿新建同名，见 §7.1 N-13） |
| **H28** | E10-S2 | `test_budget_assert.gd` | `test_budget_assert_contrast_c02` | **复用 `HudColors.wcag_contrast()`**（非重写）：`CARRIER` vs `PANEL_BASE` ≈ **13.74**（`assert_almost_eq`，容差 0.05）；**★反向断言** `HUD_COLOR_ALARM_FILL` **不在** `C02_CARRIERS` 白名单内，且其对比度 **< 3.0**（证明「不入 C-02」是刻意的，不是遗漏） | 新建文件 |
| **H29** | E10-S2 | `test_budget_assert.gd` | `test_budget_assert_is_warn_only` | ★ **N-11 + N-12 双守卫**：① 构造必然告警的输入 → 仍 **exit 0**；② 摘要文本**不含** `"[Risky]"`；③ **`.github/workflows/ci.yml` 全文不含 `"budget_assert"`**（D15-A 显式禁令的可执行守卫）；④ **`budget_assert.gd` 全文不含 `"TODO: implement scan"`**（恒真桩已清除的取证） | 新建（**高价值**） |

### 7.1 重名 / 已存在警告（必读）

| # | 冲突 | 处置 |
| --- | --- | --- |
| **N-13** | `test_fsm_tick_le_10hz` **已存在**于 `tests/unit/test_patrol_ai.gd`（Batch C 的 **H4**） | **H27 是「扩展既有用例」，不是新建同名用例。** 在原用例内追加「DECOY 轰炸下 `decision_count` 不变」的断言段即可。新建同名会 GUT 报重复。 |
| **N-14** | `test_decoy_sound_radius` 在 `sprint1-stories.md` 的 E06-S4 exit hook 中已被点名 | 名称保持一致（**H19**），不要改名，否则 Story 验收钩子指向落空。 |
| **N-15** | `test_light_toggle_ramp_within_budget` 在 `sprint1-stories.md` E04-S5 与 `budget_assert.gd` 文件头**双处引用** | 名称保持一致（**H22**）。**E10-S2 必须排在 E04-S5 之后**，否则 §5.3 文件头会指向一个不存在的测试（§8 硬约束 b）。 |
| **N-16** | `test_ring_vfx_capped_at_eight` **已存在**（Batch B，`test_sound_propagation.gd`） | **H21 是新增的 DECOY 专项**（验证新声源不绕过 FIFO），与既有用例职责不同，两处注释须互相点名。 |

### 7.2 `@ci:*` 硬约束本批落法（D14-A 分流的可执行形态）

| 约束 | 分流 | 本批承载 | 备注 |
| --- | --- | --- | --- |
| **R-02** ≤12/≤32 | static | `budget_assert._check_light_count()` 真实扫描 | 当前扫描面 = `sprint0.tscn` 单文件 |
| **R-04** ≤0.05 | static | `budget_assert._check_fog_density()` 真实扫描 | — |
| **R-05** ≤0.12/≤0.4s | **runtime** | **H22** GUT | **删桩**，文件头注释指向 |
| **R-06** LightmapGI | static | `budget_assert._check_lightmap()` 真实扫描 | 当前无静态网格资产，属「真扫空集」 |
| **V-02** ≤2Hz | **runtime** | `test_hud_slice.gd:377` + `test_vision_cone.gd:174`（**Batch C 已有**） | **删桩**，文件头注释指向 |
| **V-06** 缓动禁硬切 | static（弱） | `budget_assert` 断言 `VIGNETTE_TRANS != TRANS_LINEAR` | + H22 内同项断言 |
| **G-02** ≤8 | **runtime** | `test_ring_vfx_capped_at_eight`（Batch B）+ **H21**（DECOY 专项） | **删桩** |
| **G-04** ≤10Hz | **runtime** | **H27**（扩展 Batch C H4） | **不新增桩**（M-2） |
| **G-05** A* | — | Sprint 1 无实现 | **不写桩**，标 Sprint 2 |
| **C-02** ≥7:1 | static | `budget_assert._check_contrast_c02()`（**复用 `wcag_contrast`**）+ **H28** | 载体白名单，排除 `ALARM_FILL` |

---

## 8. 工程执行顺序拓扑（依赖排序 · 测试先行）

### 8.0 ★ 提交边界硬规则（先读这一条）

| 编号 | 规则 | 理由 |
| --- | --- | --- |
| **C1** | **`event_bus.gd:38` 签名变更 + `test_event_bus.gd:60/:79` 更新 + 新增契约测试，必须落在【同一 commit】** | 拆开必产生中间态：先 src 后 test = **假绿**（N-8 全形态）；先 test 后 src = **真红**（阻塞他人）。⛔ 禁止「先合签名、测试留 TODO」 |
| **C2** | **E10-S2 必须排在 E04-S5 之后** | R-05 的运行时承载 `test_light_toggle_ramp_within_budget`（H22）由 E04-S5 提供。先做 E10-S2 会让 §5.3 的文件头注释指向一个**不存在的测试** |
| **C3** | 步 1（E06-S4）与步 3（E04-S5）**可并行** | 不同文件、零共享符号：`event_bus.gd`/`sound_propagation.gd`/`patrol_ai.gd` **vs** `light_model.gd` |

### 8.1 线性执行清单（每步「先写测试 → 再实现 → 跑绿 → 提交」）

| 步 | 内容 | 文件 | 钩子 | 前置 | 提交 | 说明 |
| --- | --- | --- | --- | --- | --- | --- |
| **0** | **E10-S1 签收**（零代码改动） | — | — | 无 | — | CI 83/83，N-7 门已 fail-closed。**仅签收，不重开** |
| **1** | ★★ **E06-S4 契约收口 · N-8 原子提交** | `event_bus.gd`（F1）+ `test_event_bus.gd`（T1） | `test_decoy_landed_signature_contract` | 0 | **C1（原子）** | 变更点 **1·2·3·4·5·5b**。**必须最先**：后续所有 emit/connect 依赖新签名。验收：该 commit 单独 checkout 跑 GUT 全绿 **且 stderr 无 `Error calling from signal`** |
| **2** | **E06-S4 消费侧 · 声音链路** | `sound_propagation.gd`（F2）+ `test_sound_propagation.gd`（T2）+ `system-breakdown.md:51`（D1） | **H19 H20 H21** | 1 | C2 | 变更点 **6·7·9**。常量组 + `_on_decoy_landed` + `_bind_bus` 连接 + 文档 `Surface`→String 注记 |
| **3** | ★★ **E06-S4 支柱级 · N-9 floor** | `patrol_ai.gd`（F3）+ `test_patrol_ai.gd`（T3） | **H24 H25 H26** | 2 | C3 | 变更点 **8**。⚠ **floor 必须在 `_decide()` 内**（§3.5.3），放错位置击穿 G-04。**H26 是本批最高价值的反向断言，务必先写测试后写实现** |
| **4** | ⚡ **E04-S5 熄灯过场**（可与步 1–3 并行） | `light_model.gd`（F4）+ `test_light_model.gd`（T4） | **H22 H23** | 0 | C4 | 常量组 + 2 纯函数 + ramp 状态机。⚠ **`mark_cell_dirty` 全程 1 次**（N-10）；⚠ **光释放在 ramp 末**（R-02×V-06） |
| **5** | **E10-S2 预算断言**（**必须最后做**） | `budget_assert.gd`（F5）+ `test_budget_assert.gd`（T5） | **H27 H28 H29** | **3, 4**（硬约束 C2） | C5 | 5 项真实扫描 + 删 3 桩改注释 + WARN-ONLY。⛔ **不得改 `ci.yml`** |

### 8.2 拓扑图

```
【前置 · Batch A/B/C 已落盘 ✅】
  E01-S9 事件词汇 · E04-S3/S4/S7 光影 · E05 视野 · E06-S1/S2/S3/S5 声音
  E08 巡逻 AI（THR_SUSP / KS / DECISION_HZ / decision_count）· E09 HUD（hud_colors 13.74:1）
  E10-S1 CI 83/83 + N-7 fail-closed 门
                              │
╔═════════════════════════════╪═══════════════════════════════════════════════════╗
║ Batch D                     ▼                                                   ║
║                    ┌──────────────────┐                                         ║
║                    │ 步 0 · E10-S1 签收│（零代码）                               ║
║                    └────────┬─────────┘                                         ║
║          ┌──────────────────┴───────────────────┐                               ║
║          ▼                                      ▼                               ║
║ ── E06-S4 链（串行 3 步）──────────      ⚡ ── E04-S5（完全独立，最早可起）──     ║
║                                                                                 ║
║  ① 步1 · 契约收口 ★★C1 原子提交★★              ④ 步4 · 熄灯过场                  ║
║     event_bus.gd:38 签名                          light_model.gd               ║
║     + test_event_bus.gd:60/:79                    常量组 + fog_ramp_delta       ║
║     + test_decoy_landed_signature_contract        + ramp 状态机                 ║
║     ★★ N-8 假绿在此拆除 ★★                        ★★ N-10 在此拆除 ★★           ║
║     [契约测试]                                    [H22 H23]                     ║
║          │                                             │                        ║
║          ▼                                             │                        ║
║  ② 步2 · 消费侧声音链路                                 │                        ║
║     sound_propagation.gd                               │                        ║
║     DECOY 常量 + _on_decoy_landed                      │                        ║
║     + system-breakdown.md:51 注记                      │                        ║
║     [H19 H20 H21]                                      │                        ║
║          │                                             │                        ║
║          ▼                                             │                        ║
║  ③ 步3 · N-9 支柱级 floor ★★                            │                        ║
║     patrol_ai.gd  _decide() 内                         │                        ║
║     maxf(sus, THR_SUSP) + 3.0s 冷却                    │                        ║
║     ★★ N-9 在此拆除（H26 反向断言）★★                    │                        ║
║     [H24 H25 H26]                                      │                        ║
║          │                                             │                        ║
║          └──────────────────┬──────────────────────────┘                        ║
║                             ▼                                                   ║
║           ── 步 5 · E10-S2（硬约束 C2：必须最后）──────────                       ║
║              budget_assert.gd                                                   ║
║              真扫 R-02/R-04/R-06/V-06/C-02                                      ║
║              删桩 R-05/G-02/V-02 → 文件头注释                                    ║
║              ★★ N-11 + N-12 在此拆除 ★★  ⛔ 不动 ci.yml                          ║
║              [H27 H28 H29]                                                      ║
╚═════════════════════════════════════════════════════════════════════════════════╝
                              │
                              ▼
     批末冒烟：test_event_bus / test_sound_propagation / test_patrol_ai /
               test_light_model / test_budget_assert 全绿
             + 既有测试文件零回归 + stderr 无 "Error calling from signal"
```

### 8.3 并行度与关键路径

| 阶段 | 内容 | 并行度 | 说明 |
| --- | --- | --- | --- |
| 步 0 | E10-S1 签收 | — | 零代码 |
| 步 1→2→3 | E06-S4 三步 | **串行** | 契约 → 消费侧 → floor，顺序颠倒必返工 |
| 步 4 | E04-S5 | **完全独立** | ⚡ **建议与步 1 同时起步**，为关键路径腾并行带宽 |
| 步 5 | E10-S2 | **串行汇聚** | 硬约束 C2：必须等 步 3 + 步 4 定稿 |

**关键路径**：`步1 → 步2 → 步3 → 步5`（**4 跳**）。E04-S5 可全程挂旁路，只需在步 5 前完成。

**⚡ 立即可并行起步的两条**：**步 1（E06-S4 契约收口）** 与 **步 4（E04-S5）**。

### 8.4 批内冒烟检查点

| CP | 时机 | 内容 |
| --- | --- | --- |
| **CP-0** | 步 1 完成 | `test_event_bus.gd` 全绿（新签名零回归）；**契约测试 `test_decoy_landed_signature_contract` 绿**；**Godot stderr 无 `Error calling from signal`**（N-8 已拆的直接证据） |
| **CP-1** | 步 3 完成 | **H26 绿**（N-9 已拆的直接证据）；**H27 绿**（floor 未击穿 G-04）；手工验证：单次 DECOY 能让 CALM 守卫真的转身去查 |
| **CP-2** | 步 4 完成 | **H23 绿**（`mark_cell_dirty` 计数 == 1，N-10 已拆）；手工验证：熄灯瞬间遮蔽即刻翻转、雾在 0.30s 内起落、无硬切闪光 |
| **CP-3** | 步 5 完成 | **H29 绿**（exit 0 / 无 `[Risky]` / `ci.yml` 无 `budget_assert` / 无 `TODO: implement scan`）；**H28 绿**（C-02 真值 ≈13.74，非恒真） |
| **CP-4** | 批末 | 五个测试文件全绿 + 既有测试**零回归**（对齐 `sprint1-plan` 批间冒烟口径）；CI 仍全绿且 N-7 门未被触发 |

---

## 9. Sprint 2 交接清单

| 项 | 本批状态 | Sprint 2 动作 | 返工量 |
| --- | --- | --- | --- |
| **E07 DECOY 实体** | 仅**信号级**声源（`decoy_landed` 契约已冻结） | 真实可投掷物件 + charges 消耗 + 发射 `decoy_landed` | **零契约返工**（D11-A 签名已冻结） |
| **`SURFACE_FACTOR` 半径调制** | **D11-A 明确不做** | 若平衡需要，再议「MOSS 0.5 → 4m」 | 小（改 `_on_decoy_landed` 一行 `r` 计算 + 一条测试） |
| **`budget_assert` 升级为 gate** | **D15-A：WARN-ONLY，不接 N-7 门** | 观察一轮告警噪声后升级；届时需处理运行时 spawn 光 / 继承场景重复计数 | 中 |
| **`push_error` 计入 CI 失败** | §3.1.4 登记为备选，**本批不做** | 与 gate 升级同窗口评估 | 小 |
| **G-05 A\*** | Sprint 1 **无实现**，标 N/A（**不写桩**） | 随 E01-S8 NavServer 落地后补 `budget_assert` 或 GUT 断言 | 小 |
| **E01-S5 SaveManager** | D9 已延（`_checkpoint_sink` seam 就位） | 实现后注入 `set_checkpoint_sink()` | **改 1 行注入** |
| **E01-S8 NavServer** | D9 已延（`_path_provider` seam 就位） | 实现后注入 `set_path_provider()` | **改 1 行注入** |
| **R-06 静态网格 UV2** | 当前仓库**无静态网格资产**（真扫空集） | 美术资产入库后扫描自动生效 | **零**（扫描器已就位） |
| **多层关卡声音（E13）** | 3D 欧氏距离 | 改「分层判定 + 水平距离」 | 中 |

---

## 10. 残留与未闭合项

| # | 项 | 性质 | 阻塞？ | 处置 |
| --- | --- | --- | --- | --- |
| **无裁决残留** | D11–D15 **五项全 CLOSED**；C11–C22 **十二条全 CLOSED** | — | **否** | 见评审 v1.1 §7 / §7.2 |
| **R-1** | R-02/R-04/R-06 三项静态扫描当前**覆盖面近乎空集**（仓库仅 `sprint0.tscn`，无 `.glb`/`.mesh`） | **真实扫描 + 空输入**，**不是**恒真桩（区别见 §5.5 对照表） | 否 | 已在 §5.5 显式标注。资产入库后自动生效，无需返工 |
| **R-2** | `sprint1-stories.md` E03-S5 举例「SNEAK+MOSS 2.5」应为 **1.25** | 陈述性偏差（承 Batch C 的 DOC-1），代码/GDD/测试均为 1.25 | 否 | Batch D 可顺手 Edit；本文不改 `src/`/`tests/`，此项属文档域，**建议主理人授权后一并修正** |
| **R-3** | 评审 v1.0 §2 C21 的三个函数名与代码库不符 | **已修正**（评审 v1.1 加 ⛔ 修正块；本文 §5.4 给出正确版本） | 否 | ✅ 已闭合 |
| **G-05** | Sprint 1 无 A\* 实现 → 控制清单标 **N/A** | **范围决策**，非缺口 | 否 | Sprint 2 随 NavServer 处理 |

> **结论：无 FAIL、无硬阻塞、无未闭合的裁决项。** D11–D15 五项裁决全部 CLOSED；C11–C22 十二条缺口全部 CLOSED；N-8~N-12 五枚地雷全部有实现级落点 + 验证钩子；H19–H29 十一条钩子全部映射到 Story 与断言要点。

---

## 11. 设计红线复查（收口后终态）

| 红线 | 状态 | 说明 |
| --- | --- | --- |
| **主导策略** | ✅ **解除** | 曾有两处风险：**①** B-1 建议的「`source==DECOY` 无条件写 `last_known`」会让 DECOY 成为**无视线判定的万能脱身键** → **M-3 拒绝，保留 `vis > STIM_EPS` 保护**。**②** D12-A 若写成 `suspicion = THR_SUSP`（赋值）会让 DECOY 成为「**降警戒神器**」（把 ALERT 60 打回 25）→ 规格明确用 **`maxf`**（§3.5.3）。**③** 3.0s 冷却封堵「连投刷 floor」套利 |
| **经济失衡** | ✅ | DECOY floor **复用既有 `THR_SUSP`，不新增标度、不改 `KS`、不改 `intensity` 归一化** ⇒ 对既有攻守比 `KV/DECAY = 4.4:1` **零扰动**。投掷物 charges 经济属 E07（Sprint 2） |
| **认知过载** | ✅ | Batch D **零新增 HUD 元素**。E04-S5 的雾/vignette 是**环境层**且 ≤0.30s 单峰；`surface` 只换 foley 变体，**不新增需要玩家学习的规则** |
| **支柱漂移** | ✅ | E06-S4 → **支柱一**（可读的因果：投出去 → 守卫真的去查）+ **支柱四**（渐升警戒，`maxf` 不降级）；E04-S5 → **支柱二**（克制的 juicy，V-06 缓动禁硬切）；E10-S2 → **支柱三**（a11y 基底可执行化，C-02 从注释变断言）。**无「无主」Story** |
| **范围蔓延** | ✅ | 四处高风险点显式锚定：❌ E07 实体（§9）· ❌ `SURFACE_FACTOR` 半径调制（D11-A）· ❌ gate 升级（D15-A）· ❌ `ci.yml` 改动（§5.6 禁令）。**任何越界须报主理人裁决** |
| **视觉漂移** | ✅ | 本批**不新增任何色值**；`budget_assert` 对 `hud_colors.gd` **只读不改**；V-06 的 `TRANS_SINE`/`EASE_IN_OUT` 直接溯源 control-manifest `:50` |
| **「绿着烂掉」防线** | ✅ **本批重点** | N-8（契约测试 + 全参值断言）· N-9（**反向断言 H26**）· N-11（删恒真桩 + H29 取证）三枚「不会变红」型地雷，**全部配了会红的机制**，而非仅配正向用例 |

---

*Batch D 实现规格 v1.0 完成。**3 条 Story 全部可动手**；建议 **步 1（E06-S4 契约收口）** 与 **步 4（E04-S5）** 两条立即并行起步。五枚地雷（假绿签名 / DECOY 数学失效 / ramp 重复重算 / 恒真桩 / 首版扫描接 gate）均已落到具体文件、函数与验证钩子。**唯一不可拆分的提交是步 1（C1 原子提交）。** —— 文策渊 · design-strategist*
