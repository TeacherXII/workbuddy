# Sprint 1 Story 拆分 ·《灰烬之步》ASHEN STEP — Phase 5 制作

| 字段 | 值 |
| --- | --- |
| **阶段** | Phase 5 · Sprint 1（核心循环闭环） |
| **文档版本** | v0.1（工程侧 Story 拆分，供主理人汇编冲刺计划） |
| **作者** | 程基岩（工程负责人 / engineering-lead） |
| **引擎** | Godot 4.4（Forward+ / Vulkan，GDScript）· PC·Steam |
| **上游依据** | `production/epics/epic-overview.md`（§1 Epic 总表 / §3 Sprint 编排 / §5 Sprint 0 速查）· `docs/sprint0-closure.md`（4 项 CONCERNS）· `production/epics/E03~E10-*.md` · `src/game/{step_commit,light_model,vision_cone}.gd` · `tests/unit/*.gd` · `docs/architecture/control-manifest.md` §7 · `docs/architecture/architecture.md` §4 · `design/gdd/system-breakdown.md` §2 事件词汇 |
| **下游衔接** | `tests/`（验证驱动用例，归 Phase 5 quality-lead 填充，本拆分只定契约与退出钩子）· 逐 Story 实现（本 Sprint）· `production/sprints/sprint0-stories.md` 已闭合 |

> **用途**：把 Sprint 1 的「核心循环闭环」目标拆成可测试、可独立冒烟的 Story。所有 Story 沿用 `epic-overview` 编号体系（Sprint 0 切片版见 §5 速查，本表做「完整」版），新 Epic（E06/E08）从 S1 起。每条 Story 标注：GDD 系统、Given/When/Then 验收（可被 `tests/` 覆盖）、依赖、T 恤码、退出钩子（GUT 测试或 CI 断言）、触发的 control-manifest 硬约束（R/T/V/C/X/G）。
>
> **纪律**：验证驱动——先写/补测试，再实现；任何信号签名/事件词汇改动须经 `E01-S9` 收口，`tests/` 与 `E10-S2` 断言零漂移。

---

## 0. Sprint 1 范围与 Sprint 0 边界

**Sprint 0 已闭合（切片）**：E01-S1/S2/S3/S4/S6、E02-S1/S2/S3、E03-S1~S4、E04-S1/S2、E05-S1~S4、E09-S1、E10-S1（冒烟桩）。详见 `epic-overview` §5。

**Sprint 1 做「完整」版**（来自 `epic-overview` §3 Sprint 1 项）：
- E03 完整：三步态（含 RUN）/ ghost_trail / 噪声半径全 surface
- E04 完整：`get_cover` + `light_state_changed` + 可熄灯过场（R-05 ramp≤0.12/≤0.4s + vignette ease V-06）
- E05 完整：锥缘 tell `vision_looming` ≤2Hz（V-02）+ 外部 `visibility_multiplier` 注入（C3）+ 锥可视化
- E06 完整：footfall 声环 ≤8 FIFO（G-02）+ 诱饵 DECOY + `sound_emitted`
- E08 核心：Calm→…→Alert FSM + 连续可疑度 25/60/10 + 暴露梯度 1.2s 软失败（C4）+ A* 仅状态转换缓存（G-05）+ `guard_transform_dirty`
- E09 核心：可疑度条（C-02 ≥7:1）+ 暴露 UI `exposure_detected` + 道具/charges 显示
- E10：headless GUT 全绿（含 6 失败测试修复）+ control-manifest §7 部分断言
- **横切**：E01-S9 事件词汇收口（CONCERN 3）+ 6 个失败 GUT 测试 tech-debt（CONCERN 1/N2）

> **E07 不在 Sprint 1**：E06-S4（DECOY 声圈）与 E09-S4（道具/charges）依赖 E07 信号契约——`decoy_landed`/`interactable_triggered` 已在 Sprint 0 EventBus 声明，故 Sprint 1 可消费信号并渲染占位，但 **E07 实体（可投诱饵/互动物件）属 Sprint 2**。这两条 Story 标记为「信号级可测，实体级待 Sprint 2」。

---

## 1. Sprint 1 Story 总表

> T 恤码：**XS**（<½ 点，纯配置/声明）/ **S**（单函数/单信号）/ **M**（单系统核心逻辑）/ **L**（多系统状态机/寻路）。仅量级非人天。
> 退出钩子：`@test_*` = 需在 `tests/unit/` 新增/补强的 GUT 测试；`@ci:*` = `tests/ci/budget_assert.gd` 或 CI lint 断言。

### 1.1 E03 · 步进提交 / 读—步循环（完整版）

#### E03-S5 · 噪声半径全 surface（MOSS 元数据接入）
- **Epic / GDD**：E03 · `stealth-step-commit` §2
- **验收（G/W/T）**
  - Given `noise_radius = BASE(5.0)×surface_factor×gait_factor`；surface_factor 现为 STONE1.0/GRASS0.7/METAL1.2，Sprint 0 缺 MOSS 元数据。
  - When 提交一步且 surface 取地面元数据（asset-manifest §3.1），surface ∈ {STONE,GRASS,METAL,MOSS}。
  - Then `noise_radius` 正确：SNEAK+MOSS 2.5 / WALK+GRASS 3.5 / RUN+METAL 12.0 等；payload 携带 surface 字段供 E06。
- **依赖**：E03-S4（commit payload）、asset-manifest §3.1（surface 元数据）
- **T 恤**：S
- **退出钩子**：`@test_noise_radius_all_surfaces`（`tests/unit/test_step_commit.gd` 扩充）
- **控制清单**：G-02（声环上限由 E06 校验）、C-02（后续 HUD）

#### E03-S6 · 三步态完整（RUN 接入 + 全参数）
- **Epic / GDD**：E03 · `stealth-step-commit` §2（consistency-review 取舍1）
- **验收（G/W/T）**
  - Given 参数表 SNEAK 1.5/0.55/0.5、WALK 2.5/0.38/1.0、RUN 4.0/0.24/2.0。Sprint 0 仅 SNEAK/WALK。
  - When 玩家经 E01 InputManager 切到 RUN 并提交。
  - Then 落足距离/step_duration/噪声系数按 RUN 应用；`step_duration` 受 `time_scale` 缩放（ADR-003）；RUN 文案提示「高成本 deliberate 选项」。
- **依赖**：E03-S2（Sprint 0 步态切换）、E01-S6（InputManager）
- **T 恤**：S
- **退出钩子**：`@test_gait_run_noise_and_step`（`tests/unit/test_step_commit.gd`）
- **控制清单**：T-02（time_scale 缩放）、C-05（RUN 反馈形状编码）

#### E03-S7 · 落足微光 / 足音 / 残影可视实体（VFX 落地）
- **Epic / GDD**：E03 · `stealth-step-commit` §5/§7（CONCERN 4：可视实体待 Sprint 1）
- **验收（G/W/T）**
  - Given art-bible §1「物理/触觉反馈非庆祝」；微光 `#C8862F` emissive quad（非实时光，省 R-02）；足音 foley 带音景图标（X-02）；ghost_trail ≤6 Tween 淡出（受 time_scale，T-04）。
  - When 角色落足。
  - Then 落点 emissive quad 微光（≤10% 画面，C-06 主色板）+ surface 变体足音 foley + ghost_trail ≤6；全部随 `time_scale` 同步（T-04）。
- **依赖**：E03-S4（commit 钩子）、E06-S3（声环 VFX 同屏协调）
- **T 恤**：M
- **退出钩子**：`@test_footfall_vfx_present`（`tests/unit/test_step_commit.gd`，headless 安全：用 `Engine.get_main_loop()` 判空跳过渲染断言）
- **控制清单**：R-02（微光非实时光）、C-06（主色板）、X-02（足音字幕）、T-04（粒子/残影同步）

### 1.2 E04 · 掩体 / 阴影与可熄灯（完整版）

#### E04-S3 · get_cover 查询（降可见度 + 断 LOS）
- **Epic / GDD**：E04 · `cover-shadow` §2（Sprint 0 仅 S1/S2）
- **验收（G/W/T）**
  - Given `get_cover(pos)`：位于遮挡体邻接半影且断 LOS 候选；掩体不无敌，仅降 visibility 系数 + LOS 中断。
  - When E05/E08 评估 target。
  - Then `get_cover` 返回 bool；仅降 visibility 并提供 LOS 中断（不保证无敌）。
- **依赖**：E04-S1（get_light_level）、E01-S3（SpatialQueryWrapper LOS）
- **T 恤**：S
- **退出钩子**：`@test_get_cover_blocks_los`（`tests/unit/test_light_model.gd` 或新 test_cover）
- **控制清单**：C-03（光池 vs 阴影靠亮度非色相）、G-03（非逐帧）

#### E04-S4 · light_state_changed 事件 + LightState 注册（完整签名）
- **Epic / GDD**：E04 · `cover-shadow` §4；system-breakdown §2（信号 `light_state_changed(light_id, state{LIT,EXTINGUISHED})`）
- **验收（G/W/T）**
  - Given E01-S9 收口后信号签名为 `(light_id:int, state:LightState{LIT,EXTINGUISHED})`（当前 `event_bus.gd` 误为 `(point, level)`，须改）。
  - When 光源状态经 E07 熄灯动作变更。
  - Then LightState 字典更新，`light_state_changed` 发射，E05 仅重算受影响 cell（ADR-002）。
- **依赖**：E01-S9（签名收口）、E04-S1
- **T 恤**：M
- **退出钩子**：`@test_light_state_changed_emitted_with_state`（`tests/unit/test_light_model.gd`）
- **控制清单**：R-02（熄灯释放实时光）、G-03（事件驱动 O(cell)）

#### E04-S5 · 可熄灯过场（R-05 ramp + V-06 ease）
- **Epic / GDD**：E04 · `cover-shadow` §2/§5
- **验收（G/W/T）**
  - Given 熄灭 → OmniLight3D 关 + 自发光熄暗 + 局部雾 ramp≤0.12 且 ≤0.4s 回落（R-05）+ 暗角收拢 ease（V-06）。
  - When 玩家熄灯。
  - Then 释放 R-02 实时光预算；局部体积雾 ramp≤0.12/≤0.4s 后回落；vignette ease 非硬切；重亮反向。
- **依赖**：E04-S4
- **T 恤**：M
- **退出钩子**：`@test_light_toggle_ramp_within_budget`（断言 ramp 斜率≤0.12、时长≤0.4s）`@ci:R-05`
- **控制清单**：R-04（雾 base≤0.05）、R-05（ramp≤0.12/≤0.4s）、V-06（ease 转场）、R-02

#### E04-S7 · 事件驱动仅重算受影响 cell
- **Epic / GDD**：E04 · `cover-shadow` §4（ADR-002）
- **验收（G/W/T）**
  - Given `light_state_changed`/`cover_state_changed` 到达，仅受影响 cell 内目标重算（O(cell) 非全图），节流非逐帧（G-03）。
  - When dirty 信号到达。
  - Then 仅受影响 cell 内目标 LightLevel 重算；无全图重算。
- **依赖**：E04-S4、E01-S2（Grid cell）
- **T 恤**：S
- **退出钩子**：`@test_light_change_recomputes_only_dirty_cell`（`tests/unit/test_light_model.gd`）
- **控制清单**：G-03（≤10Hz/事件置脏）、R-06（LightmapGI）

### 1.3 E05 · 视野锥（完整版）

#### E05-S5 · 锥缘 tell（vision_looming ≤2Hz，V-02）
- **Epic / GDD**：E05 · `vision-cone` §2/§5
- **验收（G/W/T）**
  - Given 玩家在锥缘外 margin=8° 内且守卫转身将扫及 → `vision_looming(guard_id)`；锥缘 shader 脉动 ≤2Hz、幅度温和（V-02）；不靠色相（C-05）。
  - When 玩家进入锥缘 8° 预警带。
  - Then 发 `vision_looming`（经 E01-S9 声明）→ E09 锥缘 tell；脉动频率 ≤2Hz（CI 断言 V-02）。
- **依赖**：E05-S2、E01-S9（声明 vision_looming）
- **T 恤**：S
- **退出钩子**：`@test_vision_looming_emitted_at_edge`（`tests/unit/test_vision_cone.gd` 扩充）`@ci:V-02`
- **控制清单**：V-02（脉动≤2Hz）、C-05（非色相）、V-01（禁>3Hz 频闪）

#### E05-S6 · 外部 visibility_multiplier 注入（烟雾/掩体，C3）
- **Epic / GDD**：E05 · `vision-cone` §2；consistency-review C3
- **验收（G/W/T）**
  - Given `compute_visibility` 接受外部 `visibility_multiplier`（烟雾 ×0.3、掩体 ×0.6）；不新增系统。
  - When 目标处于烟雾区（E07 SMOKE）或掩体（E04 get_cover）。
  - Then 结果 × multiplier；掩体/烟雾不再变无敌。
- **依赖**：E04-S3、E07（SMOKE 信号，Sprint 2 实体；Sprint 1 用测试桩注入 multiplier）
- **T 恤**：S
- **退出钩子**：`@test_visibility_multiplier_smoke`（`tests/unit/test_vision_cone.gd`）
- **控制清单**：R-03（掩体降可见非无敌）、C-04（亮度编码）

#### E05-S7 · 锥可视化完整（脉动 shader + 地面光斑，C-03）
- **Epic / GDD**：E05 · `vision-cone` §3/§5（Sprint 0 仅静态 patch）
- **验收（G/W/T）**
  - Given 挂守卫的半透明 MeshInstance3D 地面光斑，冷白 `#9FB8C9` 低不透明；边界脉动 ≤2Hz（V-02）。
  - When 守卫在场。
  - Then 地面半透明冷白锥 patch 可见；锥缘脉动 tell ≤2Hz；亮度差 ≥3:1（C-03）。
- **依赖**：E05-S1（锥几何）、E05-S5（looming 驱动脉动）
- **T 恤**：M
- **退出钩子**：`@test_cone_vfx_pulse_rate`（`tests/unit/test_vision_cone.gd`，headless 用 shader 参数常量断言）`@ci:V-02`
- **控制清单**：V-02（脉动≤2Hz）、C-03（亮度差≥3:1）、C-04（不靠色相）、R-02（锥 VFX 非实时光）

### 1.4 E06 · 声音传播（新 Epic，S1 起）

#### E06-S1 · emit 声事件 + 网格通知半径内守卫
- **Epic / GDD**：E06 · `sound-propagation` §2/§4（ADR-002）
- **验收（G/W/T）**
  - Given `emit(payload)` 经 E01 Grid 查 radius 内守卫 → `sound_emitted(SoundPayload)` → E08。
  - When `emit` 调用。
  - Then 半径内守卫逐个收到 `sound_emitted`；成本 O(半径内守卫)。
- **依赖**：E01-S2（Grid）、E01-S1（EventBus）
- **T 恤**：M
- **退出钩子**：`@test_sound_emitted_notifies_guards_in_radius`（`tests/unit/test_sound_propagation.gd` 新增）
- **控制清单**：G-01（守卫≤8/16）、G-03（非逐帧）

#### E06-S2 · 用 E03 noise_radius 发落足声
- **Epic / GDD**：E06 · `sound-propagation` §2；`stealth-step-commit` §2
- **验收（G/W/T）**
  - Given `player_step_committed` 携带 noise_radius / surface / gait。
  - When E03 发 `player_step_committed`。
  - Then E06 生成 `SoundPayload{origin=to, radius=noise_radius, intensity=由 gait 派生, source=FOOTFALL}`（半径不改写，由 E03 公式给定）。
- **依赖**：E03-S4、E03-S5（noise_radius）
- **T 恤**：S
- **退出钩子**：`@test_footfall_emits_sound_with_radius`（复用 `test_integration_step_vision` 逻辑，转单测）
- **控制清单**：G-02（声环上限）、C-02（后续 HUD）

#### E06-S3 · 声环 VFX ≤8 FIFO（G-02）
- **Epic / GDD**：E06 · `sound-propagation` §2/§6；consistency-review C1
- **验收（G/W/T）**
  - Given `RING_CAP=8`，FIFO 淘汰最旧环（Tween/shader 自毁）。
  - When 并发生成 >8 环。
  - Then 同屏存活 ≤8；CI 断言同屏>8 告警（§7）。
- **依赖**：E06-S1
- **T 恤**：M
- **退出钩子**：`@test_ring_vfx_capped_at_eight`（`tests/unit/test_sound_propagation.gd`）`@ci:G-02`
- **控制清单**：G-02（声环≤8）、C-05（同心圆形状编码）、T-04（粒子同步）

#### E06-S4 · 诱饵 DECOY 声圈 ≈8m（信号级，实体待 Sprint 2）
- **Epic / GDD**：E06 · `sound-propagation` §2；`interactables` §2（DECOY）
- **验收（G/W/T）**
  - Given E07 `decoy_landed(pos,surface,radius≈8m)` 信号（Sprint 0 已声明于 EventBus）。
  - When E06 收到 `decoy_landed`。
  - Then 生成 `SoundPayload{source=DECOY, radius≈8m}` 并通知守卫（减其对玩家路径权重，E08）。
  - *注*：E07 可投诱饵实体属 Sprint 2；本 Story 消费已声明信号 + 测试桩触发。
- **依赖**：E07（信号契约，Sprint 2 实体）、E06-S1
- **T 恤**：S
- **退出钩子**：`@test_decoy_sound_radius`（用 `decoy_landed` 桩触发）
- **控制清单**：G-02、C-05

#### E06-S5 · 按距离衰减提可疑度（→ E08）
- **Epic / GDD**：E06 · `sound-propagation` §2；`patrol-ai` §2（KS15）
- **验收（G/W/T）**
  - Given `sound_in_range = intensity×(1−dist/radius)` 来自 `sound_emitted`。
  - When `sound_emitted` 到达 E08。
  - Then E08 按 `intensity×(1−dist/radius)` 累加可疑度（`suspicion += KS15×该项`）。
- **依赖**：E06-S1、E08-S2
- **T 恤**：S
- **退出钩子**：`@test_suspicion_from_sound_distance`（与 E08 共测）
- **控制清单**：G-04（FSM 节流）、C-02

### 1.5 E08 · 巡逻 AI 与可疑度 FSM（新 Epic，S1 起，核心）

#### E08-S1 · 五态 FSM（Calm→Suspicious→Alert→Search→Return）
- **Epic / GDD**：E08 · `patrol-ai` §2
- **验收（G/W/T）**
  - Given FSM 五态；暴露是可见升级非瞬死。
  - When 可疑度跨阈值。
  - Then 状态按阈值转换；状态靠姿态+道具非颜色（art §4.1）。
- **依赖**：E05-S4（`vision_stimulus`）、E06-S5（`sound_emitted`）
- **T 恤**：M
- **退出钩子**：`@test_fsm_transitions`（`tests/unit/test_patrol_ai.gd` 新增）
- **控制清单**：C-05（非颜色）、G-01（守卫≤8/16）

#### E08-S2 · 连续可疑度 25/60/10
- **Epic / GDD**：E08 · `patrol-ai` §2/§3
- **验收（G/W/T）**
  - Given S∈[0,100]；THR_SUSP=25、THR_ALERT=60、THR_RETURN=10。
  - When 累加/衰减。
  - Then S 连续；≥25→SUSPICIOUS、≥60→ALERT、<10→RETURN。
- **依赖**：E08-S1
- **T 恤**：M
- **退出钩子**：`@test_suspicion_thresholds`（`tests/unit/test_patrol_ai.gd`）
- **控制清单**：C-02（≥7:1 HUD）

#### E08-S3 · 5–10Hz 节流决策（G-04）
- **Epic / GDD**：E08 · `patrol-ai` §2；ADR-002
- **验收（G/W/T）**
  - Given 决策 ≤10Hz，真实时间不随 `time_scale`（ADR-002/003）。
  - When 守卫决策 tick。
  - Then 决策频率 ≤10Hz（慢放下仍 5–10Hz）。
- **依赖**：E02-S3（真实时间冷却纪律）
- **T 恤**：S
- **退出钩子**：`@test_fsm_tick_le_10hz`（`tests/unit/test_patrol_ai.gd`）`@ci:G-04`
- **控制清单**：G-04（≤10Hz）、T-02（真实时间）

#### E08-S4 · 暴露 1.2s 宽限软失败（C4，替换 Sprint 0 桩）
- **Epic / GDD**：E08 · `patrol-ai` §2/§3；consistency-review C4
- **验收（G/W/T）**
  - Given ALERT + 持续 visibility>0 累计宽限 1.2s 真实时间 → `exposure_detected` → 软失败（最近检查点重生，C4）。
  - When 守卫 ALERT 且玩家持续可见。
  - Then 累计真实时间达 1.2s → `exposure_detected` → 经 E01-S5 检查点重生；宽限期内断 LOS/熄灯/诱饵降 S 可自救。
- **依赖**：E08-S2、E01-S5（SaveManager 检查点）
- **T 恤**：M
- **退出钩子**：`@test_exposure_grace_1_2s`（`tests/unit/test_step_commit.gd` 的 `ExposureGuardStub` 升级为真实 `GuardBrain`）
- **控制清单**：C-04（亮度编码）、V-03（屏震默认关）

#### E08-S5 · A* 仅状态转换触发并缓存（G-05）
- **Epic / GDD**：E08 · `patrol-ai` §8；ADR-002
- **验收（G/W/T）**
  - Given A* 仅 CALM→ALERT/SEARCH 触发并缓存，非逐帧。
  - When FSM 进入 ALERT/SEARCH。
  - Then 经 E01-S8（NavServer）发起 `NavigationAgent3D` 寻路并缓存；非逐帧。
- **依赖**：E01-S8（NavServer 封装）
- **T 恤**：M
- **退出钩子**：`@test_astar_only_on_transition`（`tests/unit/test_patrol_ai.gd`）`@ci:G-05`
- **控制清单**：G-05（A* 仅状态转换）、R-01（Forward+）

#### E08-S6 · 信号发射（含 tier + 4 信号契约）
- **Epic / GDD**：E08 · `patrol-ai` §4；system-breakdown §2
- **验收（G/W/T）**
  - Given `suspicion_changed(guard_id,value,tier)`（**tier 为 Sprint 0 缺失项，本 Story 补**）、`guard_fsm_changed(guard_id,old,new)`、`exposure_detected`、`guard_transform_dirty` 均经 E01-S9 声明。
  - When 状态变更。
  - Then 对应信号发射（`guard_transform_dirty` → E05 重算）。
- **依赖**：E01-S9（信号收口）、E08-S1/S2/S4
- **T 恤**：M
- **退出钩子**：`@test_suspicion_changed_carries_tier` + `@test_guard_signals_emitted`（`tests/unit/test_patrol_ai.gd`）
- **控制清单**：C-02（tier 驱动 HUD 图标）、G-03（transform 重算）

#### E08-S8 · 姿态可读（非颜色，C-05/C-07）
- **Epic / GDD**：E08 · `patrol-ai` §2/§5/§7；art-bible §4.1
- **验收（G/W/T）**
  - Given 姿态：CALM 垂灯 / SUSPICIOUS 举灯转身 / ALERT 拔刃灯高举 / SEARCH 灯左右扫 / RETURN 归位。
  - When 守卫处于某状态。
  - Then 姿态/提灯状态传达 FSM；不依赖色相（C-05）；可疑度条图标+数字+亮度（C-02）。
- **依赖**：E08-S1
- **T 恤**：S
- **退出钩子**：`@test_guard_posture_non_color`（`tests/unit/test_patrol_ai.gd`，断言姿态枚举非颜色）
- **控制清单**：C-05、C-07、C-02

### 1.6 E09 · 核心 HUD 与可访问性（完整版，核心）

#### E09-S2 · 可疑度条（C-02 ≥7:1）
- **Epic / GDD**：E09 · `core-hud-a11y` §5；`patrol-ai` §5
- **验收（G/W/T）**
  - Given HUD 显示图标（眼/?/!）+ 数字 + 亮度递增；关键指示对比度 ≥7:1（C-02）。
  - When E08 发 `suspicion_changed(guard_id,value,tier)`。
  - Then 图标+数字+亮度递增（颜色仅辅助）；对比度 ≥7:1。
- **依赖**：E08-S6（带 tier 信号）、E01-S9
- **T 恤**：M
- **退出钩子**：`@test_suspicion_bar_contrast`（`tests/unit/test_hud_slice.gd`，CI 对比度断言）`@ci:C-02`
- **控制清单**：C-02（≥7:1）、C-05（图标编码）、C-01（≥4.5:1）

#### E09-S3 · 世界内要素可见性编排
- **Epic / GDD**：E09 · `core-hud-a11y` §2（Sprint 0 仅预演+锥 patch）
- **验收（G/W/T）**
  - Given 世界内要素（锥/光池/声环/残影）由对应系统绘制，本系统只编排可见性。
  - When 各系统绘制要素 + 凝神压暗。
  - Then E09 管辖可见性开关（凝神压暗时提亮可读要素）；世界平面俯视可读。
- **依赖**：E05-S7、E04-S5、E06-S3、E03-S7
- **T 恤**：S
- **退出钩子**：`@test_world_element_visibility_toggle`（`tests/unit/test_hud_slice.gd`）
- **控制清单**：C-03（世界亮度差）、V-06（ease）

#### E09-S4 · 道具 / charges 显示（信号级，实体待 Sprint 2）
- **Epic / GDD**：E09 · `core-hud-a11y` §2；`interactables` §4
- **验收（G/W/T）**
  - Given HUD 显示 `InteractableType` + `charges`（图标+文字）。
  - When E07 道具切换/charges 变化（Sprint 0 已声明 `interactable_triggered`）。
  - Then HUD 渲染占位（图标+文字，非颜色 C-05）；E07 实体属 Sprint 2。
- **依赖**：E07（信号契约，Sprint 2 实体）
- **T 恤**：S
- **退出钩子**：`@test_charges_display`（`tests/unit/test_hud_slice.gd`）
- **控制清单**：C-05（非颜色）、X-01（文本缩放）

#### E09-S6 · 暴露 ALERT + 软重开 UI（C4）
- **Epic / GDD**：E09 · `core-hud-a11y` §5；`patrol-ai` §2
- **验收（G/W/T）**
  - Given 暴露 `#7A2E2E` + 脉动(≤2Hz V-02) + 图标 + 可关屏震(V-03)；绝不单色(C-07)；色盲模式→`#C8862F` 高亮+图标(C-06)。
  - When E08 发 `exposure_detected`。
  - Then HUD 显示暴露 ALERT；屏震默认关；触发软重开 UI（经 E01-S5，C4）。
- **依赖**：E08-S4、E01-S5
- **T 恤**：M
- **退出钩子**：`@test_exposure_alert_ui_non_color`（`tests/unit/test_hud_slice.gd`）`@ci:V-02/V-03/C-07`
- **控制清单**：C-06、C-07、V-02（≤2Hz）、V-03（屏震默认关）、C-02

### 1.7 E10 · 发布 / CI / 质量门（完整版，部分）

#### E10-S1 · headless GUT 全绿（harness 修复 6 失败测试）
- **Epic / GDD**：E10 · `release-ci` §；control-manifest §7
- **验收（G/W/T）**
  - Given Sprint 0 末 `godot --headless` GUT 冒烟 17/24 通过，6 个 `test_integration_step_vision.gd` 因 headless 缺 SceneTree 失败（CONCERN 1/N2）。
  - When CI 在 push/PR 触发（修正 harness，见 §2）。
  - Then 全部 `tests/unit/*` 在 `godot --headless` 跑通，退出码 0；6 个集成测试由 SceneTree harness 或断言降耦修复。
- **依赖**：全部实现 Story + §2 tech-debt
- **T 恤**：M
- **退出钩子**：CI `godot --headless -s res://addons/gut/gut_cmdln.gd -gdir=res://tests/unit -gexit` 退出 0
- **控制清单**：§7（CI 卡质量门）

#### E10-S2 · §7 预算静态断言（部分）
- **Epic / GDD**：E10 · `release-ci` §；control-manifest §7
- **验收（G/W/T）**
  - Given §7 断言：实时光>32 / 雾>0.05 or ramp>0.12/>0.4s / 缺 UV2 / 声环>8 / 脉动>2Hz。
  - When `godot --headless -s res://tests/ci/budget_assert.gd` 运行。
  - Then 命中项产告警记录（lean 不阻断）；与 `tests/ci/budget_assert.gd` 一致。
- **依赖**：E04-S5（ramp 断言）、E06-S3（声环断言）、E05-S7（脉动断言）
- **T 恤**：M
- **退出钩子**：`@ci:R-05/G-02/V-02/...`（`tests/ci/budget_assert.gd` 扩充）
- **控制清单**：R-02/R-04/R-05/R-06/G-02/V-02（§7 全列）

---

## 2. 6 个失败 GUT 测试的 tech-debt Story

**现象**：`docs/sprint0-closure.md` CONCERN 1/N2 —— Sprint 0 末 `godot --headless` GUT 冒烟 17/24 通过，6 个失败测试全部位于 `tests/unit/test_integration_step_vision.gd`，根因是 **headless 下缺 SceneTree**：这些测试 `before_each` 调 `add_child(_bus/_step/_vc)`，需有效场景树；CI 命令/headless 主循环未提供 → 加载即失败。

**根因归属**：测试逻辑本身正确（`compute_visibility` / `player_step_committed` payload / `sound_emitted` / ghost_trail 数组均纯逻辑），失败纯属**测试 harness 缺 SceneTree**，故主负责 Story = **E10-S1**（harness 修复），各产品 Story 负责**回归守卫**（确保对应逻辑有 headless 安全的断言）。

**修复策略（三选一，按优先级）**：
1. **SceneTree 测试 harness（首选）**：GUT 运行时会将测试脚本加入场景树，故 `add_child` 本应可用；根因多为 CI 命令或 headless 缺主循环。修复 = 确保 `tests/README.md` 的 headless 命令在 CI 中携带有效 `SceneTree`（GUT 默认提供），并加一个 `test_suite_setup`  fixture 显式 `add_child` 到 `get_tree().root`。不引入 `@tool`（@tool 不提供 SceneTree，治标不治本）。
2. **断言降耦（兜底）**：把 6 个集成测试中的纯逻辑断言（payload dict、visibility 数值、ghost_trail 数组）抽成不依赖 `add_child` 的单元断言（直接 `StepCommit.new()` / `VisionCone.new()` 调 `compute_visibility`，不进树）。树相关部分仅保留真正需树的（如 `EventBus` group 连接）→ 用 harness 或 `@tool` 初始化补足。
3. **`@tool` 初始化（仅限 L2 RefCounted/纯逻辑）**：对 `LightModel`（已是 RefCounted）等无需树的依赖，去括号 `add_child`；对必须进树的 `EventBus`/`StepCommit`/`VisionCone` 仍走策略 1。

| TD | 失败测试 | 归属产品 Story | 负责修 Story | 修复策略 |
| --- | --- | --- | --- | --- |
| **TD-1** | `test_commit_emits_sound_with_landing_payload` | E03-S7 / E06-S2 | **E10-S1**（harness）+ E06-S2 回归 | 策略1：SceneTree harness 使 `_step`/`_bus` `add_child` 有效；声音 payload 断言转纯单元（策略2） |
| **TD-2** | `test_event_bus_wiring_carries_step_commit` | E01-S9 / E03-S4 | **E10-S1** + E01-S9 回归 | 策略1：harness 使 `_bus` 进树；`player_step_committed` 转发断言为纯逻辑 |
| **TD-3** | `test_visibility_in_light_pool_is_full` | E05-S2 / E04-S1 | **E10-S1** + E05-S2 回归 | 策略2：`compute_visibility` 纯函数，去掉 `add_child(_vc/_bus)`，直接 `VisionCone.new()` 断言 |
| **TD-4** | `test_visibility_in_shadow_is_zero` | E05-S2 / E04-S1 | **E10-S1** + E05-S2 回归 | 策略2：同上，纯逻辑断言 |
| **TD-5** | `test_commit_landing_in_shadow_yields_zero_visibility` | E05-S2 / E04-S1 / E03-S4 | **E10-S1** + E05-S2 回归 | 策略2+1：commit+shadow 逻辑纯断言；`add_child` 仅保留必要项 |
| **TD-6** | `test_ghost_trail_capped_at_six` | E03-S7 | **E10-S1** + E03-S7 回归 | 策略2：`ghost_trail` 是 `StepCommit` 纯数组，直接 `StepCommit.new()` 循环 commit+tick_real 断言，去 `add_child` |

> **退出钩子**：E10-S1 合格后，上述 6 测试在 `godot --headless` 退出码 0；各 TD 对应 `@test_*` 由归属产品 Story 的退出钩子覆盖（不另起测试文件）。

---

## 3. Sprint 1 实现顺序建议（基于依赖 DAG，4 批，每批可独立冒烟）

**DAG**：`E01 → E02 → E03 → E04 → E05 → E06 → E08 → E09`（E07 并行但不在 Sprint 1；E10 贯穿收口）。

```
Batch A  词汇+光影地基（无玩法依赖，可先冒烟）
  ├─ E01-S9   事件词汇收口（前置！所有信号改动必经）
  ├─ E04-S3   get_cover
  ├─ E04-S4   light_state_changed（完整签名，依赖 E01-S9）
  ├─ E04-S7   受影响 cell 重算
  ├─ E03-S5   噪声半径全 surface
  ├─ E03-S6   三步态完整（RUN）
  └─ E03-S7   落足微光/足音/残影 VFX
        │
Batch B  视野完整 + 声音（依赖 Batch A 的光影/噪声）
  ├─ E05-S5   vision_looming（依赖 E01-S9）
  ├─ E05-S6   visibility_multiplier 注入
  ├─ E05-S7   锥可视化（脉动 shader）
  ├─ E06-S1   emit + 网格通知
  ├─ E06-S2   落足声（依赖 E03-S4/S5）
  ├─ E06-S3   声环 ≤8 FIFO
  └─ E06-S5   距离衰减提可疑度（依赖 E08-S2，可后置到 Batch C 初）
        │
Batch C  AI + HUD 核心（依赖 Batch B 的 vision_stimulus / sound_emitted / 词汇）
  ├─ E08-S1   五态 FSM
  ├─ E08-S2   连续可疑度 25/60/10
  ├─ E08-S3   5–10Hz 节流（G-04，依赖 E02-S3）
  ├─ E08-S4   暴露 1.2s 软失败（依赖 E01-S5）
  ├─ E08-S5   A* 仅状态转换（依赖 E01-S8）
  ├─ E08-S6   信号发射（tier + 4 信号，依赖 E01-S9）
  ├─ E08-S8   姿态可读
  ├─ E09-S2   可疑度条（C-02）
  ├─ E09-S3   世界内可见性编排
  ├─ E09-S6   暴露 ALERT UI
  └─（E06-S5 / E09-S4 信号级可插入此批）
        │
Batch D  CI 收口（依赖全部实现）
  ├─ E06-S4   DECOY 声圈（信号级，依赖 E07 信号）
  ├─ E09-S4   道具/charges 显示（信号级）
  ├─ E10-S1   headless GUT 全绿（含 §2 的 6 tech-debt）
  └─ E10-S2   §7 预算静态断言
```

**批间冒烟点**：A 末跑 `test_light_model` + `test_step_commit` 全绿；B 末跑 `test_vision_cone` + `test_sound_propagation`；C 末跑 `test_patrol_ai` + `test_hud_slice`；D 末跑全量 `godot --headless` GUT 退出 0。每批独立可测，不阻塞后续规划。

---

## 4. 事件词汇收口 Story（CONCERN 3：3 项残留差异落到具体 Story）

**根因**：Sprint 0 `event_bus.gd` 仅声明 9 个信号，且 2 个签名与 `system-breakdown.md` §2 不一致。收口由 **E01-S9** 统一负责（非 E01-S1，S1 已在 Sprint 0 闭合）。

| 残留差异 | system-breakdown §2 正确契约 | 当前 `event_bus.gd` | 负责 Story | 改动 |
| --- | --- | --- | --- | --- |
| **① `light_state_changed` 签名** | `(light_id:int, state:LightState{LIT,EXTINGUISHED})` | `(point:Vector3, level:float)` ❌ | **E01-S9** + E04-S4 | 改为 `(light_id:int, state:LightState)`；同步 E04-S4 发射方 |
| **② `suspicion_changed` 缺 tier** | `(guard_id:int, value:float[0..100], tier:SusTier)` | `(guard_id:int, value:float)` ❌ 缺 tier | **E01-S9** + E08-S6 | 加 `tier:SusTier` 参数；E08-S2 计算 tier 并随信号发出 |
| **③ 4 个未来信号未声明** | `cover_state_changed(cell:Vector3i)`、`vision_looming(guard_id:int)`、`guard_transform_dirty(guard_id:int)`、`guard_fsm_changed(guard_id:int, old:String, new:String)` | 全部缺失 ❌ | **E01-S9** | 补声明 4 信号；分别被 E04-S7 / E05-S5 / E08-S6→E05 / E08-S6 消费 |

**E01-S9 · 事件词汇收口（Sprint 1 新增）**
- **Epic / GDD**：E01 · `engineering-base`；`system-breakdown` §2；consistency-review §1.3
- **验收（G/W/T）**
  - Given `system-breakdown` §2 词汇表（13 信号 + 8 共享类型）。
  - When E01-S9 收口 EventBus。
  - Then `event_bus.gd` 信号集 == §2 词汇表（修正 ① ② + 补 ③ 4 信号）；CI lint 断言「无未声明信号 / 无拼写漂移」。
- **依赖**：无（地基，须最早落地，Batch A 首位）
- **T 恤**：S
- **退出钩子**：`@test_event_vocabulary_complete`（`tests/unit/test_event_bus.gd` 新增，断言全部 13 信号可 `emit`/`connect`）`@ci:no-undeclared-signal`
- **控制清单**：§7（CI lint）、C-02（tier 驱动）

---

## 5. 预算 / 控制清单勾稽汇总

> 每条 Story 触发的 control-manifest 硬约束（供 E10 CI 断言 / quality-lead 用例填充）。

| Story | R | T | V | C | X | G | 备注 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| E03-S5 | — | — | — | — | — | G-02 | 噪声半径供声环 |
| E03-S6 | — | T-02 | — | C-05 | — | — | RUN 受 time_scale |
| E03-S7 | R-02 | T-04 | — | C-06 | X-02 | — | 微光非实时光/字幕 |
| E04-S3 | — | — | — | C-03 | — | G-03 | 掩体降可见 |
| E04-S4 | R-02 | — | — | — | — | G-03 | 熄灯释放实时光 |
| E04-S5 | R-04,R-05,R-02 | — | V-06 | — | — | — | ramp≤0.12/≤0.4s |
| E04-S7 | R-06 | — | — | — | — | G-03 | O(cell) 重算 |
| E05-S5 | — | — | V-01,V-02 | C-05 | — | — | 脉动≤2Hz |
| E05-S6 | R-03 | — | — | C-04 | — | — | 掩体/烟雾注入 |
| E05-S7 | R-02 | — | V-02 | C-03,C-04 | — | — | 亮度差≥3:1 |
| E06-S1 | — | — | — | — | — | G-01,G-03 | 网格通知 |
| E06-S2 | — | — | — | C-02 | — | G-02 | 落足声 |
| E06-S3 | — | T-04 | — | C-05 | — | G-02 | 声环≤8 FIFO |
| E06-S4 | — | — | — | C-05 | — | G-02 | DECOY≈8m |
| E06-S5 | — | — | — | C-02 | — | G-04 | 距离衰减 |
| E08-S1 | — | — | — | C-05 | — | G-01 | 五态 FSM |
| E08-S2 | — | — | — | C-02 | — | — | 25/60/10 |
| E08-S3 | — | T-02 | — | — | — | G-04 | ≤10Hz |
| E08-S4 | — | — | V-03 | C-04 | — | — | 屏震默认关 |
| E08-S5 | R-01 | — | — | — | — | G-05 | A* 仅转换 |
| E08-S6 | — | — | — | C-02 | — | G-03 | tier/transform |
| E08-S8 | — | — | — | C-05,C-07,C-02 | — | — | 姿态非色相 |
| E09-S2 | — | — | — | C-01,C-02,C-05 | — | — | ≥7:1 |
| E09-S3 | — | — | V-06 | C-03 | — | — | ease |
| E09-S4 | — | — | — | C-05 | X-01 | — | 文本缩放 |
| E09-S6 | — | — | V-02,V-03 | C-06,C-07,C-02 | — | — | 暴露非单色 |
| E10-S1 | — | — | — | — | — | — | CI 全绿 |
| E10-S2 | R-02,R-04,R-05,R-06 | — | V-02 | — | — | G-02 | §7 断言 |
| E01-S9 | — | — | — | — | — | — | 词汇 lint |

**硬编码纪律红线**（供实现时查）：所有阈值/预算不得散落硬编码——`L_DARK/L_BRIGHT`（E04-S2 已暴露）、`HALF_ANGLE/ RANGE/ TICK_HZ`（E05 常量）、`MAX_GHOST=6`（E03）、`RING_CAP=8`（E06）须引用常量；CI `grep` 断言禁止裸数（如 `0.25`、`10` 锥频）直接出现在玩法逻辑。

---

## 6. Sprint 1 退出标准（供主理人汇编冲刺计划）

1. **完整核心循环可玩**：扫描（E05 锥+looming）→ 规划（E03 预演+三步态）→ 提交（E03 落足+微光/足音）→ 读反馈（E09 可疑度条/世界要素）→ 调适（E08 FSM + 暴露 1.2s 软失败 C4 跑通）。
2. **CI 冒烟全绿**：`godot --headless` GUT 退出 0（含 §2 的 6 个 tech-debt 测试修复，E10-S1）。
3. **事件词汇零漂移**：E01-S9 收口后 `event_bus.gd` == `system-breakdown` §2（修正 light_state_changed / suspicion_changed tier / 补 4 信号），CI lint 无未声明信号。
4. **§7 预算断言运行**：E10-S2 跑通，声环>8 / 脉动>2Hz / ramp>0.12 等命中产告警。
5. **控制清单达标**：C-02≥7:1、V-02≤2Hz、G-02≤8、R-05 ramp≤0.12/≤0.4s 等经对应 `@test_*` / `@ci:*` 钩子卡门。

---

## 7. 待主理人裁决 / 开放项

- **E07 信号级 vs 实体级**：E06-S4 / E09-S4 在 Sprint 1 仅消费已声明信号 + 测试桩，实体（可投诱饵/互动物件）留 Sprint 2——请确认是否接受「信号级完成、实体级延期」。
- **TD 修复策略选定**：§2 给出策略1（harness，首选）/2（断言降耦）/3（@tool）——建议默认策略1+2 组合，请裁决是否允许在 CI 依赖 GUT 自带 SceneTree。
- **Story 数量与粒度**：本拆分共 **27 条产品 Story + 6 条 tech-debt = 33 条**（E03×3 / E04×4 / E05×3 / E06×5 / E08×7 / E09×4 / E10×2 / E01×1 / TD×6）。若需更粗粒度合并，可在汇编时按批归并。
- **知识缺口**：Godot 4.4 `add_child` 在 headless GUT 的 SceneTree 行为以本环境静态审查为准（N2 未实跑）；正式 harness 修复须在本可运行环境 `godot --headless` 验证（同 Sprint 0 N2 闭合动作）。
