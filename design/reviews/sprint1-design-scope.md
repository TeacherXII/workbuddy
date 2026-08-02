# Sprint 1 设计范围与范围纪律检查 ·《灰烬之步》ASHEN STEP（Phase 5 · 制作 · Sprint 1 核心循环闭环）

> **作者**：文策渊（design-strategist / 设计策略师）
> **上游依据**：`production/epics/epic-overview.md` §3 Sprint 1（第 92–94 行）· `docs/sprint0-closure.md` CONCERNS（第 34–38 行）· `design/gdd/consistency-review.md`（C1–C4）· `design/concept/game-concept.md`（四支柱）· `design/gdd/systems/*.md`（8 份八节 GDD）· `design/gdd/system-breakdown.md` §2 事件词汇 · `docs/architecture/architecture.md` §4 预算 · `docs/architecture/control-manifest.md` §7 断言
> **评审强度**：lean（仅核心节点卡质量门）
> **用途**：供主理人汇编 Sprint 1 冲刺计划。本文件定义 E03/E04/E05/E06/E08/E09/E10 的 Sprint 1 设计范围（Do/Dont）、四支柱贴合、设计就绪度、范围纪律与 CONCERNS 归属、事件词汇残留收口、范围风险缓解。

---

## 0. 范围纪律判定（速览）

| 项 | 判定 |
| --- | --- |
| 四支柱是否守住（Sprint 1 范围） | ✅ **全守，无支柱漂移**（逐系统见 §2） |
| 范围 Do/Dont 是否越界（vs epic-overview §3 Sprint 1） | ✅ **未越界**（E07 全系统显式推迟 Sprint 2；a11y 完整包显式 Sprint 2） |
| 设计就绪度（E03–E10 可否进 Story 实现） | ✅ **全部 READY**；8 项缺口（5 项 GDD 文档 Edit/补全 + 3 项范围边界声明）须在 Story 开工前闭环（见 §3 缺口表） |
| 事件词汇残留差异（Sprint 0 收口项） | ⚠️ **3 项全部归属 E01-S1 + 对应产生/消费系统**（见 §5） |
| Sprint 0 的 4 项 CONCERNS | ⚠️ **全部映射到 Sprint 1 具体 Epic/Story**（见 §4） |
| 一致性评审 C1–C4 | ⚠️ **全部映射到 Sprint 1 收口项**（部分需在 Sprint 2 收尾，见 §4） |
| 范围纪律总判定 | **PASS / CONCERNS**（无硬阻塞；CONCERNS 均为非阻塞的收口/缓解项，须在 Sprint 1 跟踪） |

> 说明：本判定与 Sprint 0 收口（PASS/CONCERNS）口径一致，且比 Sprint 0 更收敛——Sprint 0 的 4 项 CONCERNS 在本 Sprint 1 均有明确归属，无新增 FAIL。

---

## 1. Sprint 1 设计范围（Do / Dont）

> 基线：`epic-overview.md` 第 92–94 行「Sprint 1 — 核心循环闭环」包含项。下列 Do/Dont 严格对齐 GDD 八节数值与架构 §4 / control-manifest 硬约束。
> **范围边界铁律**：E07（互动物件完整系统）不在 Sprint 1；Sprint 1 仅接入 E07 的**事件副作用**（DECOY 声事件、light_state_changed 由熄灯触发），E07 道具/charges/类型在 Sprint 2。a11y 完整包（色盲/时间滑杆/雾/动态模糊/文本缩放/字幕）为 Tier2，Sprint 2；Sprint 1 仅做核心 HUD 的可读性基底。

### 1.1 主数值对齐锚（全 Epic 共用，强制一致）

| 数值 | 权威值（GDD/架构/ADR/清单） | Sprint 1 约束 |
| --- | --- | --- |
| 凝神 time_scale | T-02 / ADR-003：默认 **0.25**（区间 0.1–0.3，下限 0.1） | E02 已锁；E09 仅读显示 |
| 锥几何 / 频率 | vision-cone §2 / G-03 / ADR-002：half_angle **35°** / range **14m** / TICK_HZ **10**（错峰） | E05 完整锁定 |
| 光影阈值 | cover-shadow §2：`L_DARK=0.20` / `L_BRIGHT=0.60` | E04 完整锁定 |
| 噪声公式 | stealth-step-commit §2：`noise_radius = 5.0 × surface_factor × gait_factor` | surface `STONE 1.0 / GRASS 0.7 / METAL 1.2`；gait `SNEAK 0.5 / WALK 1.0 / RUN 2.0` |
| 声环上限 | sound-propagation §2 / G-02：同屏 **≤8**（FIFO 自毁） | E06 完整锁定 |
| 暴露宽限 | patrol-ai §2：`GRACE_RT=1.2s`（真实时间，非缩放） | E08 完整锁定 |
| 暴露/锥缘脉动 | V-02：`PULSE_HZ_MAX ≤ 2Hz`，幅度温和 | E05/E08 完整锁定 |
| 熄灯过场 | R-05：雾 ramp **≤0.12 且 ≤0.4s** 回落；vignette ease（V-06 禁硬切） | E04 完整锁定 |
| FSM 决策 | G-04：`DECISION_HZ ≤10Hz` | E08 完整锁定 |
| A* 寻路 | G-05：仅状态转换触发并缓存，非逐帧 | E08 完整锁定 |
| 动态光上限 | R-02：MVP **≤12** / Tier2 **≤32**（光 LOD） | Sprint 1 场景守 MVP≤12；E10 §7 断言盯 32 硬顶 |
| 残影上限 | stealth-step-commit §3：`TRAIL_MAX=6` | E03 完整锁定 |
| 提交冷却 | stealth-step-commit §2：`COMMIT_COOLDOWN_RT ≥0.12s`（真实时间） | E03 已锁 |
| 凝神 ramp | V-06：ramp **≈0.15s** ease | E02 已锁 |
| 对比度 | C-02 关键指示 **≥7:1**；C-03 世界要素 **≥3:1** | E09 完整锁定 |

---

### 1.2 E03 步进提交 / 读—步循环（GDD ①，P1）— 完整

**Do（必须做出）**
- 三步态完整：`SNEAK(1.5m/0.55s/0.5)` / `WALK(2.5m/0.38s/1.0)` / `RUN(4.0m/0.24s/2.0)`，参数严格取 §2 表；`RUN` 为「高成本 deliberate 选项」（噪声 10m、仍受提交间隙约束，非无脑冲刺，见 §3 缺口 G1）。
- `ghost_trail` Tween alpha 淡出（≤6 步），残影受 `time_scale` 缩放（ADR-003）。
- 噪声半径全 surface：实现 `BASE 5.0 × surface_factor(STONE 1.0/GRASS 0.7/METAL 1.2) × gait_factor`；surface 元数据落 `asset-manifest §3.1`（STONE/GRASS/METAL 分类，见 §3 缺口 G2）。
- 落足微光 emissive quad `#C8862F`（≤10% 画面，art-bible §2.1）+ surface 足音 foley 变体（X-02 字幕带音景图标）——收口 Sprint 0 CONCERN #4（VFX）。
- 下一步预演（aim_point ghost footprint + 落点微光，世界内非屏框）。
- 读间隙纪律：`IDLE` 才接受提交 + `COMMIT_COOLDOWN_RT 0.12s` 真实时间兜底（杜绝连击，概念 §3 红线）。

**Dont（留给 Sprint 2 / 收尾）**
- ❌ 幽灵回放（ghost-trail 对比，Tier2 §8）——仅复用 `ghost_trail` 数据，不新增系统。
- ❌ 完整「安全步」轻提示 UI（可关，§7）——Sprint 1 仅保预演常驻可见；提示 UI 入 Sprint 2 a11y。

> 建议 Story（待主理人编号）：E03-S5（三步态 + RUN + 全 surface 噪声）· E03-S6（ghost_trail 淡出 + 落足微光 emissive + surface 足音 foley）。

---

### 1.3 E04 掩体/阴影与可熄灯（GDD ⑤，P1）— 完整

**Do（必须做出）**
- `get_cover(pos) -> bool`：位于遮挡体邻接半影且断 LOS 候选；掩体**不无敌**——降低 visibility 系数 + 提供 LOS 中断（具体系数接入方式见 §3 缺口 G3）。
- `light_state_changed(light_id, state:LightState)` 事件驱动 cell 重算（ADR-002，仅 O(cell) 非全图）；发射方为可熄灯触发（Sprint 1 由**最小熄灯互动物**或测试桩驱动，完整 E07 道具在 Sprint 2）。
- 可熄灯过场：光源 `LIT↔EXTINGUISHED`；雾 `ramp ≤0.12 且 ≤0.4s` 回落（R-05）+ `vignette` 收拢 ease（V-06）+ 咔哒/风声 foley。
- `get_light_level` 静态层接 **LightmapGI 真烘焙**（R-06）于至少 1 个区域（Sprint 0 为 mock）；动态层叠可互光源/提灯（受 R-02 上限）。
- 阈值 `L_DARK=0.20` / `L_BRIGHT=0.60` 暴露给 E05/E08（已锁）。

**Dont（留给 Sprint 2 / 收尾）**
- ❌ 光 LOD 细节（Tier2 远处提灯降自发光近似/关实时光，ADR-004）——Sprint 1 仅守 MVP 动态光 ≤12，32 上限由 E10 §7 断言盯硬顶。
- ❌ 彩窗 SpotLight 光柱（美术 §3.4）——Tier2。
- ❌ 多区域全量 LightmapGI bake + E10 资产管线整合——Sprint 2（退出标准收尾）。

> 建议 Story：E04-S3（get_cover）· E04-S4（light_state_changed 事件驱动 cell 重算）· E04-S5（可熄灯过场 R-05 + vignette V-06）· E04-S6（LightmapGI 单区域 bake R-06）。

---

### 1.4 E05 视野锥（GDD ③，P2）— 完整

**Do（必须做出）**
- 单/多守卫锥：half_angle **35°** / range **14m** / TICK_HZ **10**（错峰，G-03）；LOS 经 L2 SpatialQueryWrapper；光影敏感度 `L≥0.60→1.0`、`L≤0.20→≈0`。
- 锥缘 tell：`vision_looming(guard_id)` 发出 + 锥缘 shader 脉动 **≤2Hz**（V-02），幅度温和，不靠色相（C-05）。
- 外部 `visibility_multiplier` 注入槽（C3 收口）：`compute_visibility` 接受 `external_multiplier`（默认 1.0），掩体/烟雾经此衰减；**Sprint 1 仅加槽 + 默认 1.0 + 掩体接入**（见 §3 缺口 G3），SMOKE 生产源在 Sprint 2（E07）。
- 锥可视化：半透明 `MeshInstance3D` 地面光斑冷白 `#9FB8C9`，亮度差 ≥3:1（C-03）。
- 事件驱动重算：`guard_transform_dirty` / `light_state_changed` / `player_step_committed` 立即置脏相关 cell。

**Dont（留给 Sprint 2 / 收尾）**
- ❌ 守卫变体（暗视哨兵降 L 阈值 / 循声猎犬降视觉权重）——Tier2，参数覆盖不新增系统。
- ❌ SMOKE 烟雾源生产（E07 SMOKE → ③ 衰减）——Sprint 2；Sprint 1 仅预留 `visibility_multiplier` 注入点。
- ❌ 多锥/广角变种——Tier3。

> 建议 Story：E05-S5（锥缘 tell vision_looming + 脉动 shader V-02）· E05-S6（compute_visibility 加 external_multiplier 槽 + 掩体接入，C3 槽）· E05-S7（锥可视化 patch 冷白 #9FB8C9 + C-03）。

---

### 1.5 E06 声音传播（GDD ④，P2）— 完整

**Do（必须做出）**
- footfall 声环 VFX：离散声事件 → 扩张同心圆（Tween/shader 自毁），**同屏 ≤8**（G-02），超出 FIFO 淘汰最旧环（`RING_CAP=8`）。
- `sound_emitted(SoundPayload)` 守卫通知：网格查 `radius` 内守卫 → ⑥ 按 `intensity×(1−dist/radius)` 提可疑度（O(半径内守卫)）。
- 诱饵 `DECOY` 声事件渲染：接收 `decoy_landed`（Sprint 1 由**最小 decoy 桩/关卡放置**驱动；完整 E07 诱饵道具/charges 在 Sprint 2），生成可控半径声环 + 通知守卫。
- 落足微光 emissive quad `#C8862F` + surface 足音 foley（X-02 字幕）——与 E03 协同收口 Sprint 0 CONCERN #4。
- 噪声半径不改写（由 E03 公式给定），仅传播/可视化/通知。

**Dont（留给 Sprint 2 / 收尾）**
- ❌ 完整 E07 互动物件系统（DECOY/LIGHT_TOGGLE/TRAP/SMOKE 四类型 + charges 限量 + entity-inventory 配置）——Sprint 2；Sprint 1 仅接其**声学副作用**。
- ❌ TRAP 机关声事件完整链路——Sprint 2（依赖 E07）。

> 建议 Story：E06-S1（footfall 声环 VFX ≤8 FIFO G-02）· E06-S2（DECOY 声事件渲染 + 最小 decoy 桩）· E06-S3（sound_emitted 守卫通知）· E06-S4（落足微光 emissive + surface 足音 foley X-02）。

---

### 1.6 E08 巡逻 AI 与可疑度 FSM（GDD ⑥，P3）— 核心

**Do（必须做出）**
- 五态 FSM 骨架 `CALM→SUSPICIOUS→ALERT→SEARCH→RETURN` 全实现；Sprint 1 重点连通 `CALM→SUSP→ALERT→暴露→软重开`，SEARCH/RETURN 行为最小化存在（见 §6 风险 R1）。
- 连续可疑度 `S∈[0,100]`；阈值 `SUSPICIOUS≥25` / `ALERT≥60` / `RETURN S<10`；决策 `DECISION_HZ ≤10Hz`（G-04，真实时间）。
- 暴露梯度（非瞬死）：`ALERT + 持续 visibility>0 累计 1.2s 真实时间` → `exposure_detected(guard_id, target)` → **软失败**：最近安全检查点重生，可疑度清零，守卫回 RETURN/巡逻。宽限期内玩家可断 LOS/熄灯/诱饵自救。
- A* 仅状态转换触发 + 缓存路径（G-05），经 L2 NavServer；`guard_transform_dirty(guard_id)` 置脏视野重算。
- 发出 `suspicion_changed(guard_id, value, tier)`（**3 参，含 tier**）/`guard_fsm_changed`/`exposure_detected`/`guard_transform_dirty`。
- 暴露脉动 `#7A2E2E` + 图标 +（可关）屏震（V-03），≤2Hz（V-02），色盲模式→`#C8862F`（C-06/C-07）。

**Dont（留给 Sprint 2 / 收尾）**
- ❌ 守卫变体（循声猎犬/暗视哨兵）——Tier2，参数覆盖。
- ❌ SEARCH「last-known 拓宽调查 + 多守卫协同包抄」智能深化——Sprint 1 最小，Sprint 2 打磨。
- ❌ 完整 SaveManager 存档/读档 + 软重开 UI——Sprint 1 仅 minimal 检查点 store/restore 支撑 C4（见 §3 缺口 G4），完整在收尾。

> 建议 Story：E08-S1（五态 FSM 骨架）· E08-S2（连续可疑度 25/60/10 + 决策 ≤10Hz G-04）· E08-S3（暴露梯度 1.2s + exposure_detected + 软重开 C4）· E08-S4（A* 仅状态转换 G-05 + guard_transform_dirty）· E08-S5（suspicion_changed 3参 + guard_fsm_changed 发出）。

---

### 1.7 E09 核心 HUD 与可访问性（GDD ⑧，P4）— 核心

**Do（必须做出）**
- 可疑度条：图标（眼/?/!）+ 数字 + 亮度递增，对比度 **≥7:1**（C-02）；贴近相关守卫或 HUD 一角细条。
- 暴露 UI：`exposure_detected` → `#7A2E2E` + 脉动 + 图标 +（可关）屏震（C-07/V-03），≤2Hz（V-02）。
- 道具/charges 显示**槽位 UI**（Sprint 1 接最小数据源/调试值；真实 E07 道具数据在 Sprint 2，见 §3 缺口 G5）。
- 面板基调：半透明暗面板 `#1B1B1F`@70–85% + `#3E5C76` 细描边，替换 Sprint 0 占位 ProgressBar（art-bible §8.1）。
- 世界内要素（锥/光池/声环/残影/预演）仅编排可见性，不重绘。

**Dont（留给 Sprint 2 / 收尾 — 关键防蔓延）**
- ❌ **完整 a11y 包**（色盲模式 C-05/C-06/C-07、时间缩放滑杆 T-01/T-02、屏震关 V-03、雾选项 V-04、动态模糊关 V-05、文本缩放 X-01、字幕 X-02）——Tier2，Sprint 2。**Sprint 1 不滑入**（见 §6 风险 R2）。
- ❌ 照片模式 UI / 「最干净通关」排行榜 UI——Tier3。

> 建议 Story：E09-S2（可疑度条 C-02 ≥7:1 + 图标/数字）· E09-S3（暴露 UI exposure_detected C-07/V-03）· E09-S4（道具/charges 槽 UI 占位）· E09-S5（面板基调 #1B1B1F@70-85% + #3E5C76 描边）。

---

### 1.8 E10 发布 / CI / 质量门（L1 / 管线）— Sprint 1 部分

**Do（必须做出）**
- headless GUT 冒烟实跑：在可运行 Godot 4.4 环境执行 `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests/unit -gexit` 跑通 Sprint 0+Sprint 1 用例（**收口 Sprint 0 CONCERN N2**，退出标准⑤）。
- `control-manifest.md` §7 部分静态断言（warn-only，不阻断）：`R-02` 实时光 >32 警告 · `R-04/R-05` 雾 base>0.05 / ramp>0.12 或 >0.4s 警告 · `G-02` 同屏声环 >8 警告 · `V-02` 暴露脉动 shader >2Hz 警告。
- HUD 测试 harness 固化：headless 下 `add_child(Camera3D, current=true)` + NaN 守卫（收口 Sprint 0 CONCERN HUD-N2）。

**Dont（留给 Sprint 2 / 收尾）**
- ❌ Steam 导出 + 完整 §7 断言 + draw call ≤400 实测——Sprint 2 退出标准。
- ❌ 预算校验 harness 全量（尘埃 additive 上限 R-08 等）——Sprint 2。

> 建议 Story：E10-S2（headless GUT 冒烟实跑 — N2 闭合）· E10-S3（control-manifest §7 部分断言）· E10-S4（HUD 测试 harness 固化 — HUD-N2）。

---

## 2. 四支柱贴合核对（无支柱漂移）

> 逐系统对照 `system-breakdown.md` §5 与 GDD §1；每个系统服务 ≥1 支柱，确认无「无主」系统、无反向违背。

| Epic / 系统 | 服务支柱 | 说明（Sprint 1 落点） | 漂移？ |
| --- | --- | --- | --- |
| E03 步进提交 | 支柱一● / 支柱二● | 三步态 deliberate 承诺 + 落足微光/足音/残影质地反馈 | 无 |
| E04 掩体/阴影 | 支柱一● / 支柱三● / 支柱二● / 支柱四● | 阴影可消耗资源（规划）+ 可熄灯主动造影（多解）+ 熄灯「黑暗吞没」质地 + 暗即安全 | 无 |
| E05 视野锥 | 支柱四● / 支柱一● | 锥缘 tell「被注视」压迫 + 威胁一眼可读支撑规划 | 无 |
| E06 声音传播 | 支柱一● / 支柱三● | 噪声是可权衡承诺 + 诱饵=主动解法克制唯一解 | 无 |
| E08 巡逻 AI | 支柱一● / 支柱四● | 暴露可恢复（失误=重规划机会）+ 渐升警戒庄重紧张 | 无 |
| E09 核心 HUD | 支柱二● / 支柱三● | 克制 juicy 反馈 + 道具/可读性让玩家 Own 体验；四支柱均不破坏 | 无 |
| E10 发布/CI | （间接服务全部） | 预算守门（R/T/V/C/X/G）间接守护四支柱的可实现性 | 无 |

**结论**：Sprint 1 全部 7 个 Epic 各自服务 ≥1 支柱，无支柱漂移。未新增平行系统大类（E07 整系统推迟，仅接其事件副作用），严守概念 §5 范围纪律。

---

## 3. 设计就绪度评审（逐 Epic，E03–E10）

> 判定口径：READY（GDD 八节齐全、数值明确、可进 Story）／READY-with-gaps（GDD 基本就绪，但列明 Story 落地前须补的缺口）／NOT-READY。
> 结论：**全部 READY**；共 8 项缺口（G1–G8）。其中 **G1/G2/G3/G4/G6 为须 Story 开工前闭环的 GDD/资产/代码缺口**（多为 Edit 公式或刷新残留值，非阻塞）；**G5/G7/G8 为范围边界声明**（非缺陷，仅锚定 Sprint 1 不做项）。

| Epic | 就绪度 | GDD 缺口 / 待补项（Story 开工前） |
| --- | --- | --- |
| E03 | ✅ READY | **G1（RUN 红线裁决）**：`RUN` 为「高成本 deliberate 选项」（consistency-review 取舍1），但 §8 Tier1 已列三步态为必做；Sprint 1 含 RUN，须主理人最终裁决 RUN 留 MVP 还是降级 Tier2。GDD 已定义数值（4.0m/0.24s/2.0），缺口仅为裁决。**G2（surface 元数据）**：`asset-manifest §3.1` 须落 STONE/GRASS/METAL 分类（Sprint 0 §4.4 残留，非 GDD 本身问题）。 |
| E04 | ✅ READY | **G3（cover→visibility 接线）**：§2 称 `get_cover`「降低 visibility 系数并提供 LOS 中断」，但 §3 返回 `bool`、且 E05 可见性公式**无 cover 项**。须定义 cover 经 E05 `external_multiplier` 衰减（默认 1.0，入掩体 <1.0）。建议与 C3 槽合并（见 §4/§5）。无数值缺漏。 |
| E05 | ✅ READY | **G3（公式缺外部乘子）**：§2 可见性公式 `visibility = InCone ? clamp01((L−L_DARK)/(L_BRIGHT−L_DARK)) : 0.0` **缺少 `× external_multiplier` 项**。须 Edit §2 公式追加该槽（默认 1.0）以收口 C3（掩体+烟雾注入）。属 GDD 文档 Edit，非机制新增。 |
| E06 | ✅ READY | **G6（残留示例刷新）**：§2 示例仍用旧分类 `SNEAK+STONE=3.0m / WALK+WOOD=5.0m / RUN+STONE=12.0m`（WOOD/MOSS + 旧 STONE 1.2）。须刷新为 `STONE/GRASS/METAL`：SNEAK+STONE=2.5m / WALK+STONE=5.0m / RUN+STONE=10.0m（Sprint 0 §4.4 残留）。数值与机制无误。 |
| E08 | ✅ READY | **G4（SaveManager 检查点）**：C4 软失败依赖 L2 SaveManager 检查点语义，但 Sprint 0 E01 **未实现 SaveManager**（仅 EventBus/Grid/TimeController/Input/A11ySettings 接口）。Sprint 1 须 E01 加 minimal SaveManager（检查点 store/restore）或 E08 软重开用轻量区域重置；完整存档/读档留收尾。**G7（FSM 边界）**：SEARCH/RETURN 智能深度须在 Story 内明确最小集（见 §6 R1）。 |
| E09 | ✅ READY | **G5（道具数据依赖 E07）**：道具/charges 显示依赖 E07（Sprint 2）。Sprint 1 仅做槽位 UI + 最小数据源；真实数据接线 Sprint 2。**G8（a11y 包边界）**：完整 a11y 开关为 Tier2/Sprint 2，Sprint 1 不做（防蔓延，见 §6 R2）。无数值缺漏（C-02 ≥7:1 已定义）。 |
| E10 | ✅ READY | 无 GDD 缺口。`control-manifest.md` §7 断言目录已齐（R-02/R-04/R-05/G-02/V-02）；Sprint 1 取「部分断言」（见 §1.8 Do）。N2 运行时校验在可运行环境补。 |

**缺口汇总（须在 Sprint 1 Story 开工前闭环）**：
- G1 RUN 红线裁决 → 主理人拍板（consistency-review 取舍1）。
- G2 surface 元数据 → `asset-manifest §3.1` 刷新（E03 联动）。
- G3 cover→visibility 接线 + 公式加 `external_multiplier` → **Edit E05 §2 公式**（与 C3 合并收口）。
- G6 E06 §2 示例刷新（WOOD→STONE/GRASS/METAL）。
- G4 minimal SaveManager → E01 Sprint 1 补（C4 前置）。
- G5/G7/G8 → 范围边界声明，非 GDD 缺陷。

---

## 4. 范围纪律与 CONCERNS 归属

### 4.1 Sprint 0 的 4 项 CONCERNS → Sprint 1 具体 Epic/Story

| # | Sprint 0 CONCERN（sprint0-closure 第 34–38 行） | Sprint 1 归属 | 收口动作 |
| --- | --- | --- | --- |
| 1 | **N2**：本环境 Bash 故障，GUT 未实跑（退出标准⑤） | **E10-S2** | 在可运行 Godot 4.4 环境跑通 headless GUT 冒烟（Sprint 0+Sprint 1 用例） |
| 2 | **HUD 测试需场景树 + Camera3D**（已加 NaN 守卫） | **E09 + E10-S4** | 固化 HUD 测试 harness（headless `Camera3D(current=true)` + NaN 守卫），纳入 E10 质量门 |
| 3 | **事件词汇 3 项残留差异**（`light_state_changed` 签名 / `suspicion_changed` 缺 tier / 4 信号未声明） | **E01-S1**（+ 产生/消费系统） | 补全 EventBus 全 §2 信号 + 统一签名（详见 §5） |
| 4 | **落足微光/足音可视实体待 Sprint 1** | **E03-S6 + E06-S4** | emissive quad `#C8862F`（≤10% 画面）+ surface 足音 foley（X-02 字幕） |

### 4.2 一致性评审 C1–C4 → Sprint 1 收口项

| # | CONCERN | Sprint 1 收口（本 Sprint） | 跨 Sprint 收尾（若需） |
| --- | --- | --- | --- |
| C1 | 声环 ≤8 FIFO（G-02） | **E06-S1**：`RING_CAP=8` FIFO 自毁已实现于 GDD，Sprint 1 落地 VFX + E10-S3 断言 `>8` 警告 | —（已闭环） |
| C2 | Tier2 16 守卫逼近动态光 32 上限 | **E04**（守 MVP 动态光 ≤12）+ **E10-S3**（§7 断言实时光 >32 警告） | 光 LOD 远处降实时光（ADR-004）在 **Sprint 2**（Tier2 ≤32） |
| C3 | 烟雾如何改写 ③ 可见性 | **E05-S6**：`compute_visibility` 加 `× external_multiplier` 槽（默认 1.0）+ 掩体接入（解 G3） | SMOKE 生产源在 **E07 Sprint 2**（SMOKE→③ 衰减） |
| C4 | 暴露软失败依赖 SaveManager 检查点 | **E08-S3** + **E01 minimal SaveManager**（G4）：`exposure_detected`→软重开（检查点重生） | 完整存档/读档 + 软重开 UI 在 **收尾** |

> 与 `epic-overview.md` §6 口径一致（C1→E06 / C2→E04,E10 / C3→E05,E07 / C4→E08,E01）。本表补 Sprint 1 具体 Story 与跨 Sprint 边界。

---

## 5. 事件词汇残留差异收口（Sprint 1）

> 来源：`sprint0-closure` CONCERN #3 / `sprint0-design-review.md` §3.3。3 项差异全部由 **E01-S1（EventBus 全 §2 信号声明 + 签名统一）** 在 Sprint 1 启动时收口，对应产生/消费系统在 Sprint 1 落地使用。

| 残留差异 | 目标签名（对齐 system-breakdown §2） | 负责 Story | 产生/消费系统（Sprint 1 落地） |
| --- | --- | --- | --- |
| **① `light_state_changed` 签名** | `light_state_changed(light_id:int, state:LightState{LIT,EXTINGUISHED})` | **E01-S1**（声明+统一）；发射方 **E04-S4** | 发：E04（可熄灯）；消：E05（视野重算 cell） |
| **② `suspicion_changed` 缺 tier** | `suspicion_changed(guard_id:int, value:float[0..100], tier:SusTier)` | **E01-S1**（声明 3 参）；发射 **E08-S5**；消费 **E09-S2** | 发：E08；消：E09 |
| **③ 4 个未来信号未声明** | `guard_transform_dirty(guard_id:int)` · `cover_state_changed(cell:Vector3i)` · `vision_looming(guard_id:int)` · `guard_fsm_changed(guard_id, old:GuardState, new:GuardState)` | **E01-S1**（全声明） | 发/消：E08（guard_transform_dirty/guard_fsm_changed）、E04（cover_state_changed）、E05（vision_looming→E09） |

**收口纪律**：
- E01-S1 须在 Sprint 1 第一棒完成，作为一致性评审 §1.3 闭合性前置（CI lint 断言「无未声明信号」）。
- 签名以 `system-breakdown.md` §2 为唯一权威；EventBus 旧 `light_state_changed(point, level)` 二参形态**废弃**。
- 顺带刷新 `system-breakdown.md` §2.3 共享类型 `Surface`：`STONE | WOOD | MOSS` → `STONE | GRASS | METAL`（解 G2/G6 残留）。

---

## 6. 范围风险与缓解（Sprint 1 范围蔓延点）

| # | 蔓延点 | 风险 | 缓解（锚定范围） |
| --- | --- | --- | --- |
| R1 | **E08 FSM 变复杂** | SEARCH「last-known 拓宽调查 + 多守卫协同包抄」智能、守卫变体被拉入 Sprint 1 | Sprint 1 锁「核心五态 + CALM→SUSP→ALERT→暴露→软重开 + 最小 RETURN（S<10 重置）」；SEARCH 仅最小存在；**守卫变体（循声猎犬/暗视哨兵）显式 Sprint 2**（Tier2 参数覆盖，不新增系统） |
| R2 | **E09 a11y 滑入 Tier2** | 完整 a11y 包（色盲/时间滑杆/雾/动态模糊/文本缩放/字幕）被诱入 Sprint 1 | Sprint 1 E09 = 可疑度条 C-02 + 暴露 UI + 道具槽占位 + 面板基调；**a11y 完整包显式 Sprint 2（Tier2）**；以 MoSCoW Should / GDD §8 Tier2 锚定，评审卡门 |
| R3 | **E05 visibility_multiplier 槽 → 拉进 SMOKE** | 为验证槽而把 E07 SMOKE 生产源做进 Sprint 1 | Sprint 1 仅加注入点 + 默认 1.0 + **掩体接入**；SMOKE 生产在 **E07 Sprint 2** |
| R4 | **E04 真实 LightmapGI 全量烘焙** | 多区域 bake + E10 资产管线被拉入 Sprint 1（重、耗时） | Sprint 1 仅 **1 区域 bake（R-06）+ 动态层**；多区域/资产管线整合 **Sprint 2** |
| R5 | **E06 DECOY 诱饵 → 拉进 E07 道具系统** | 为喂 DECOY 而实现完整 E07 互动物件（四类型+charges+entity-inventory） | Sprint 1 E06 仅接 **DECOY 声事件渲染 + 最小 decoy 桩/关卡放置**；完整 E07 **Sprint 2** |
| R6 | **E03 RUN 成主导策略（红线）** | RUN 噪声 10m 仍可能被玩家当最优解，违反「步步为营」 | RUN 受提交间隙 + 高噪声（10m 显著引怪）约束非无脑冲刺；playtest 调 `GRACE`/噪声；若成主导策略依 consistency-review 取舍1 **降级 RUN 为 Tier2**（主理人裁决 G1） |
| R7 | **E08 软失败引 SaveManager 全量** | C4 软重开诱使实现完整存档/读档 | Sprint 1 E01 仅 **minimal SaveManager（检查点 store/restore）** 支撑软重开；完整存档/读档 + 软重开 UI **收尾** |
| R8 | **设计理论四红线复查缺位** | 多系统引入后现「主导策略/经济失衡/认知过载/支柱漂移」 | 定期复查（ux-spec §8 口径）；当前无四项，但 E06/E07/E08 扩张后须防「单一最优解」与「HUD 信息过载」（E09 槽位克制） |

**通用纪律**：任何 Story 若欲越 §1 Do 边界（触碰 E07 整系统 / a11y 完整包 / 守卫变体 / 多区域 bake / Steam 导出），须在评审标「范围蔓延」并报主理人裁决，不擅自定稿。

---

## 7. 退出标准对齐（Sprint 1，epic-overview 第 94 行）

1. 完整「扫描→规划→提交→读反馈→调适」循环可玩（E03 三步态 + E05 锥 + E06 声 + E08 FSM + E09 HUD 串联）。
2. 暴露软失败（宽限 1.2s → 检查点重生，C4）跑通（E08-S3 + E01 minimal SaveManager）。
3. CI 冒烟 + 预算断言部分绿灯（E10-S2 headless GUT + E10-S3 §7 部分断言：R-02/R-04/R-05/G-02/V-02）。
4. 事件词汇零漂移（E01-S1 收口 3 项残留，§5）。

---

*Sprint 1 设计范围文档 v1.0 完成。范围纪律判定 **PASS / CONCERNS**：四支柱全守、范围未越界（E07 整系统 + a11y 完整包显式推迟）、设计全部 READY（5 项 GDD 缺口 Story 开工前补）、Sprint 0 的 4 项 CONCERNS 与一致性 C1–C4 全部有 Sprint 1 归属。供主理人汇编冲刺计划。*
