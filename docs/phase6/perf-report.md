# Phase 6 性能剖析报告 · ASHEN STEP《灰烬之步》

**Author:** 程基岩（Cheng / engineering-lead）
**Build under test:** `main` @ `24fc2ef`（working tree clean）
**Engine:** Godot 4.4.1-stable（win64 console，headless）
**Scope:** 性能剖析 + 现状评估 + 本地基线门方案（**只分析、只报告，未改任何 `.gd` 源码、未碰 `.tmp_gut/`、未 commit**）

---

## 0. 做了什么（可独立复验）

| # | 命令（实跑） | 结果 |
|---|---|---|
| 1 | `GODOT=.../.tmp_gut/godot/Godot_v4.4.1-stable_win64_console.exe; "$GODOT" --version` | `4.4.1.stable.official.49a5bc7b6`，exit 0、stdout 真实非空 → **shell 能正常启动 Godot，非已知「exit 0 空 stdout」失灵** |
| 2 | `find src -name '*.gd' \| wc -l` | 30 个脚本 |
| 3 | `wc -l $(find src -name '*.gd') \| tail -1` | 9208 总行数 |
| 4 | `cd Game-RPG; t0=$(date +%s%3N); "$GODOT" --headless --quit >/dev/null 2>&1; t1=...; echo $((t1-t0))` | **warm headless boot = 480 ms**（引擎+autoload+脚本编译缓存命中） |
| 5 | 静态通读：`interactable_registry / patrol_ai / sound_propagation / save_manager / guard_spawner / spatial_hash_grid / vision_cone` + `control-manifest.md` | 见 §1/§4 |
| 6 | grep 全仓 `Performance\|get_monitor\|OS.get_ticks\|TIME_PROCESS` | 游戏代码 **0 处**；唯一 `Performance.get_monitor` 在 `addons/gut/orphan_counter.gd`（GUT 自带）→ **游戏当前零运行时性能埋点** |
| 7 | grep 确认 `save_manager.gd:266` `call_deferred("_flush_write", …)` | 磁盘 IO 已离游戏 tick（异步），无逐帧 IO 热点 |

> 说明：冷编译/重导入耗时本可用 `--import --quit` 计时，但会清掉共享的 `.godot` 缓存、拖慢本地 GUT 验证通道；为不扰动既有验证态，**本次未强制冷缓存**，warm boot 480ms 作为可复现下界。需要冷数可随时补测。

---

## 1. 现状 · headless 能测 / 不能测

**热路径（静态）**
- `GuardBrain._process()`（patrol_ai.gd:258）→ 读墙钟 → `tick_real()` 固定 10Hz 步进（`DECISION_HZ=10`、`TICK_DT=0.1`，`MAX_CATCHUP_TICKS=3` 防死亡螺旋）。每个 `_decide()` 是 **O(1) 纯逻辑**：stimulus/accumulate/decay/clamp → `_update_last_known` → decoy floor → `_step_exposure/_step_fsm` → `_ensure_path`（命中缓存则跳过 A*）→ `_maybe_mark_transform_dirty` → `_emit_if_changed`。**决策内部无跨守卫循环**。
- `SoundPropagator.emit()`（sound_propagation.gd:157）：`SpatialHashGrid3D.query_radius` 取候选（CELL=14m，半径≤14m ⇒ 最多 3×3×3=27 桶 + 候选数），精确 in-radius 过滤，ring FIFO（`RING_CAP=8`，`_can_render()` 下 headless 为 no-op），广播。已确认 **emit 成本有界且极小**。
- `VisionCone`（vision_cone.gd:27 `TICK_HZ=10.0`，:76 随机错峰）→ **G-03（≤10Hz/守卫锥体重算）已在代码层执行**。
- `InteractableRegistry`：spawn/despawn 为 O(1) 字典操作；`realtime_light_count()` / `sound_ring_emitter_count()` 为 O(N) 记账函数，**非逐帧调用**。
- `SaveManager`：写盘全部 `call_deferred`（:266 / :791），`_flush_write` 走原子 staging+rename，**无逐帧 IO**。

**headless 能测（已拿真数）**：启动/引擎初始化/autoload/脚本编译耗时（480ms warm）。
**headless 不能测**：真实渲染帧时间、GPU、VFX（cone VFX / 提灯火 / ghost-trail cap 6）。headless 无渲染管线与显示器，`_process` 循环无渲染负载，帧 delta 不具代表性——与 yan 三轮 Playtest「Headless GUT does not measure frame-time/CPU/GPU」结论一致。

---

## 2. 可测项真实数字

| 指标 | 数值 | 来源 |
|---|---|---|
| Godot 版本 | 4.4.1.stable | `--version`（真） |
| 项目规模 | 30 脚本 / 9208 LOC | `find`+`wc -l`（真） |
| Warm headless 启动 | **480 ms** | 计时（真，下界） |
| 游戏内运行时埋点 | **0** | grep（真） |

> 真实帧时间：headless 不可测，本任务**未编造**任何 FPS/帧耗时数字。

---

## 3. 基线门方案（debug-only · 只设计不实现）

分两道门，明确职责边界：

### 3.1 逻辑基线门（headless 可跑，fail-closed）
- **场景**：`tests/perf/bench_baseline.gd`（debug-only，置于 `tests/` 下、**不进 PCK/不挂载到发布游戏**，仅由 perf gate 调用）。
- **结构**：spawn `N=16` 个 interactable（逼近 `INSTANCE_CAP=16`） + `M=16` 守卫（Tier2 G-01 上限）+ 触发 `K=8` 次声波传播；用 `GuardBrain.tick_real()` / `SoundPropagator.emit()` 在固定循环里跑 `T=600` tick（模拟 60s @ 10Hz）。
- **打点**：`OS.get_ticks_usec()` 包住热循环，记录 avg/min/max / 中位数 tick 成本，写 JSON 到 `user://perf_baseline.json`。
- **阈值依据**：因每 tick 逻辑为 O(1) 且被 G-03/G-04 限频，预期成本 sub-ms/tick；**先在本机采基线，阈值 = 中位数 × 2.0（留 50%+ 余量）**。该门本质是**回归探测器**——一旦有人在 `_decide` 里引入 O(N) 循环即报错。
- **接入**：`tools/perf_gate.sh` 调 `Godot --headless --script tests/perf/bench_baseline.gd`，grep JSON 阈值越界；越界 → `exit 1`（fail-closed，同 `assert_lint` 思路），走 `.tmp_gut` 本地验证通道。

### 3.2 帧时间门（窗口化，非 headless）
- R-09 目标 60fps@1080p。需**最小窗口实例**（`--video-driver vulkan`，小窗）带 W-spawn，采 `Performance.get_monitor(Performance.TIME_PROCESS)` + FPS ≥10s，断言 avg ≥60fps。
- **需显示器/带 GPU 的 CI**——超出 headless 范围，即 yan 所指「minimal windowed smoke」。本门仅描述，待有显示环境再落地。

> 以上两门均为方案，**未创建任何文件**，待主理人裁决后实施。

---

## 4. 预算余量风险点

| 预算 | 状态 | 风险 |
|---|---|---|
| G-01 守卫 ≤8/16 | **硬拒**（spawn 返回 null + `over_budget_rejections`） | 无 |
| G-02 声环 VFX ≤8 | **硬 FIFO 自毁** | 无（渲染层安全） |
| G-03/G-04/G-05 | **代码层限频/限触发** | 无 |
| R-02 实时点光 ≤12(MVP)/32(Tier2) | **仅关卡作者约束，无运行时拒绝** | ⚠ **主风险** |
| INSTANCE_CAP=16（interactable） | **WARN-ONLY，超了只 push_warning 仍 spawn** | ⚠ 与 R-02/G-02 未联动 |

**核心缺口**：`INSTANCE_CAP=16` 既不在 R-02(12 MVP) / G-02(8) 边界处拒绝也不告警。最坏情况——
- **MVP 船**：16 个全 LIT 互动物（各占 1 实时光）+ 8 守卫提灯 = **24 实时光 > R-02 MVP(12)**，但 interactable 上限 16 远未触发 → **R-02 被静默突破**。
- **Tier2 船**：16 LIT 互动物 + 16 守卫提灯 = **32 = R-02 Tier2 天花板**（贴边）。
- `sound_ring_emitter_count()` 可达 16（全 trap），> G-02(8) 软语义（G-02 的 VFX 硬 FIFO 仍安全，但「发射源预算」被突破）。

**建议（非本次改动，交主理人裁决）**：仿现有 `tests/ci/budget_assert.gd` 的 WARN-ONLY 模式，加一个**加载期/CI 记账断言**——汇总 `InteractableRegistry.realtime_light_count()`（互动物光）+ 活守卫数（提灯），按 tier 超 R-02 即告警；把 INSTANCE_CAP 与 R-02/G-02 在**记账层**联动起来（仍不阻断，保持 lean 评审）。逻辑预算（G-01~G-05）均已硬约束，无需额外动作。

---

## 5. 结论

- 逻辑预算（G-01/G-02/G-03/G-04/G-05）**已在代码层硬约束**，AI/声波/注册表热路径均为 O(1)/有界，**无逻辑层热点**，headless 可测的启动耗时 480ms（下界）。
- **真实帧时间 headless 不可测，未编造**。需 §3.2 窗口化门补全（yan 已标注 medium）。
- **逼近上限的真实风险在 R-02 实时光**：INSTANCE_CAP 与 R-02/G-02 未联动，MVP 船可在合法互动物/守卫数下静默突破 R-02。建议补一个 WARN-ONLY 加载期记账断言。
- 基线门方案见 §3（逻辑门 headless 可跑 fail-closed；帧时间门需窗口环境）。两门均未实施。
