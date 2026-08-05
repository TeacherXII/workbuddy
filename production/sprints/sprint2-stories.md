# Sprint 2 Story 拆分 ·《灰烬之步》ASHEN STEP — Phase 5 制作

| 字段 | 值 |
| --- | --- |
| **阶段** | Phase 5 · Sprint 2（互动物件实体级 / SaveManager 数据层 / a11y 完整包） |
| **文档版本** | **v1.1（锁库前 FLAG 闭环版）** — 在 v1.0 基础上：**FLAG-A RESOLVED(a)** 签名锁零参 · **FLAG-I RESOLVED** 并入 SAV-S2 · **FLAG-K RESOLVED** GDD §8 已加注。v1.0 内容：守卫变体 + 手动存档 UI + Tech Debt 已滑 Sprint 3；E11 正式新立 |
| **作者** | 程基岩（工程负责人 / engineering-lead） |
| **引擎** | Godot 4.4（Forward+ / Vulkan，GDScript）· PC·Steam |
| **上游依据** | `design/gdd/systems/save-system.md`（★ 存档权威 GDD）· `design/reviews/sprint2-design-scope.md` §3 数值锚/§7 FLAG · `production/epics/epic-overview.md` §1/§3 · `production/epics/E07~E09/E11-*.md` · `docs/architecture/architecture.md` §2/§4 · `docs/architecture/control-manifest.md` §7 · `src/core/{event_bus,a11y_settings}.gd` · `src/game/patrol_ai.gd` · `src/ui/{hud_slice,hud_colors}.gd` · `tests/unit/*.gd` · `tests/ci/budget_assert.gd` |
| **下游衔接** | `tests/`（验证驱动用例，归 Phase 5 quality-lead 填充，本拆分只定契约与退出钩子）· 逐 Story 实现（本 Sprint）· `production/sprints/sprint3-stories.md`（滑期项，待建） |

> **用途**：把 Sprint 2 **三大必交范围**（E07 互动物件实体级 / SaveManager 数据层 / a11y 完整包 Tier2）拆成可测试、可独立冒烟的 Story。沿用 `epic-overview` 编号体系；每条 Story 标注：Epic/GDD、Given/When/Then 验收（可被 `tests/` 覆盖）、依赖、T 恤码、退出钩子（GUT 测试或 CI 断言）、触发的 control-manifest 硬约束。
>
> **纪律**：验证驱动——先写/补测试，再实现；任何信号签名/事件词汇改动须经 `E01-S9` 收口，`tests/` 与 `E10-S2` 断言零漂移。**N-7 门铁律**：严禁在测试里写裸 `[Risky]`（仅 GUT 真实 risky token `\[Risky\]:|\[Pending\]:|\[Risky\] Script was skipped` 触发失败，Sprint 1 已踩坑）。新增预算断言一律 WARN-ONLY，绝不发 `[Risky]` 字面。
>
> **数值单一真相源**：存档相关常量以 `design/gdd/systems/save-system.md` §3/§6 与 `sprint2-design-scope.md` §3 数值锚为准，本文**不另立数字**（v0.1 草案的 `schema_version=1` / `≤64KB` / `ConfigFile` 口径已作废，见 §5 FLAG-H）。

---

## 0. Sprint 2 范围与主理人裁决

**Sprint 1 已收口（核心循环闭环）**：E03/E04/E05/E06/E08(核心)/E09(核心)/E10 完成；E07 仅消费信号级（`decoy_landed`/`interactable_triggered`/`light_state_changed` 已在 EventBus 声明，HUD 渲染占位），**实体级留 Sprint 2**；SaveManager 为 D9-seam 占位（`GuardBrain._checkpoint_sink` 零参 no-op）；a11y 仅 Sprint 0 切片（`A11ySettings` 仅 color_blind_mode/time_scale_min/screen_shake/fog_enabled(bool)/motion_blur/text_scale=1.0）。

### 0.1 主理人裁决（本版收口依据）

| # | 裁决 | 影响 |
| --- | --- | --- |
| **裁决 1** | **按建议滑期**：守卫变体（E08 变体）+ 手动存档/读档 UI + Tech Debt → **全部滑 Sprint 3** | 采纳 `sprint2-design-scope.md` §7 FLAG-1/2/3；本文 §1 只留三批，滑期项集中入 §2 |
| **裁决 2** | **E11 正式新立**（SaveManager 从 E01 剥离为独立 epic） | `E11-save-manager.md` 由「提案」转「正式」；`epic-overview.md` §1 去 ⚠️建议 标记；原 E01-S5 归属迁 E11 |

**Sprint 2 必交（三范围）**
1. **E07 互动物件完整系统（实体级）**：DECOY / LIGHT_TOGGLE / TRAP / SMOKE 四类实体 + `charges` 限量 + entity-inventory 配置。
2. **E11 SaveManager 数据层**：versioned schema + 检查点滚动槽写/读 + `restore_checkpoint` 注入 D9 seam + 偏好委托。**不含手动存档 UI**（滑 S3）。
3. **E09 a11y 完整包 Tier2**：色盲枚举 / 时间滑杆 / 雾三态 / 动模糊 / 文本缩放 / 字幕 + A11ySettings 完整模型。

**评审强度**：完整 QA 门（对齐 Sprint 1 五退出标准，范围收窄至 S2 三范围 —— 见 §3）。

---

## 1. Sprint 2 Story 总表（三批）

> **T 恤码**：XS（<½ 点，纯配置/声明）/ S（单函数/单信号）/ M（单系统核心逻辑）/ L（多系统状态机/寻路）。仅量级非人天。
> **批次归属（裁决后重排）**：**Batch A（存档基座 / E11 数据层）→ Batch B（互动物件实体级 / E07）→ Batch C（a11y 完整包 / E09）**。与 `sprint2-design-scope.md` §5 Batch 1/2/3 对齐（其 Batch 3 的「变体 + 存档 UI」已滑 S3，Batch 4 整体滑 S3）。
> **退出钩子**：`@test_*` = 需在 `tests/unit/` 新增/补强的 GUT 测试；`@ci:*` = `tests/ci/budget_assert.gd` 静态断言（WARN-ONLY，绝不 `[Risky]`）。
> **批间并行**：Batch B（E07）在 Batch A 的 SAV-S1 落地后即可并行启动（E07 仅消费 `interactable_charges` 字段契约，不依赖写盘实现）。

### Batch A — 存档基座（E11 SaveManager **数据层**）★ FLAG-A 已裁决（零参，见 §5）

> **本批边界**：只做**数据层 + 注入**，不做任何玩家可见的存档/读档界面。`write_slot`/`read_slot` API 在本批完整落地（含手动槽 id `0..2` 的读写路径），Sprint 3 的 SAV-S5 只在其上加 UI —— 这样 S3 是纯表现层增量，不回头改 L2。

#### SAV-S1 · 存档数据模型 + `SAVE_VERSION` 版本字段前置
- **Epic / GDD**：E11 · `save-system.md` §3（数据模型）/§2（版本化）· `architecture.md` §2（L2 存档服务）
- **验收（G/W/T）**
  - Given `SaveSlot` 含：`version:int` / `slot_id:int` / `is_checkpoint:bool` / `timestamp:float` / `checkpoint_id:String` / `player_pose` / `suspicion` / `guard_states` / `interactable_charges` / `light_states` / `a11y_prefs`（GDD §3 逐字）。
  - When 定义数据结构并序列化（JSON 落 `SAVE_DIR = user://saves/slot_{id}.json`）。
  - Then `version` 字段**必须是写入时的第一个字段且恒等于 `SAVE_VERSION = 2`**（FLAG-A 缓解①：版本前置，任何读取路径先读版本再解析其余）；序列化/反序列化可逆；只存「世界差异态」，静态关卡几何不存（GDD §3）。
- **常量**：`SAVE_VERSION=2` · `CHECKPOINT_SLOT_ID=-1` · `MAX_MANUAL_SLOTS=3` · `SAVE_DIR="user://saves/"` · `PREFS_PATH="user://prefs.json"`
- **依赖**：E01（A11ySettings 接口）
- **T 恤**：M
- **退出钩子**：`@test_save_slot_roundtrip`（`tests/unit/test_save_manager.gd`）、`@ci:save-schema-has-version`
- **控制清单**：无硬约束（内部契约）

#### SAV-S2 · `write_slot` / `read_slot` 数据层 API（滚动检查点槽 + 手动槽读写，异步落盘）
- **Epic / GDD**：E11 · `save-system.md` §2（两类存档）/§3（API）/§6（异步 + 写冷却 + 体积）
- **验收（G/W/T）**
  - Given 两类槽：检查点滚动单槽（`CHECKPOINT_SLOT_ID=-1`，静默写入）与手动槽（`0..MAX_MANUAL_SLOTS-1`）。
  - When 玩家进入检查点区（或 `#checkpoint` 锚点）触发静默写入 / 上层调 `write_slot(id, data)` `read_slot(id)`。
  - Then 写盘**异步不阻塞主线程**，`write_slot` 立即返回、完成发 `save_completed(slot_id, success)`；检查点写入限频 `CHECKPOINT_WRITE_COOLDOWN ≥ 0.5s`（防同区每帧写）；单槽 JSON **≤ 32KB**（WARN-ONLY）。
  - Then 读取发 `load_completed(slot_id, success)`。
  - Then **★ 事件词汇 E01-S9 收口闭环（FLAG-I RESOLVED，并入本 Story，成本 XS）**：3 个新信号 `save_completed(slot_id:int, success:bool)` / `load_completed(slot_id:int, success:bool)` / `checkpoint_restored(checkpoint_id:String)` 须在**同一批**内完成三处逐字一致：① `src/core/event_bus.gd` 声明；② `design/gdd/system-breakdown.md` §2 共享事件词汇表登记；③ E01-S9 的 CI lint 断言「无未声明信号 / 无拼写漂移」通过。**三者零漂移方可 Story 退出**；不另开 `E01-S9b` Story。
  - Note `guard_spawned`（E08 变体）**随变体滑 S3**，本 Sprint **不声明**，不得顺手加入词汇表。
- **依赖**：SAV-S1、**E01-S9 收口（已并入本 Story 验收，不再是外部前置）**
- **T 恤**：M（含并入的 E01-S9 收口 XS）
- **退出钩子**：`@test_write_read_slot_roundtrip` `@test_checkpoint_write_cooldown_0_5s`（`tests/unit/test_save_manager.gd`）、`@ci:save-size-budget`、**`@ci:event-vocab-zero-drift`**（E01-S9 lint，断言 `event_bus.gd` ↔ `system-breakdown.md` §2 逐字一致，WARN-ONLY 口径不变）
- **控制清单**：无硬约束（体积 WARN-ONLY；事件词汇零漂移属项目铁律，非 control-manifest 编号约束）

#### SAV-S3 · `restore_checkpoint()` + D9 seam 注入 ★**FLAG-A 已裁决：签名锁零参**
- **Epic / GDD**：E11 · `save-system.md` §2/§4（D9 seam）· `patrol-ai` §2（C4 软失败重生）· consistency-review C4
- **✅ 签名已锁（FLAG-A RESOLVED，采纳口径 (a)）**：`func restore_checkpoint() -> void` —— **零参，与 GDD `save-system.md` §4 逐字一致**。注入即 `set_checkpoint_sink(SaveManager.restore_checkpoint)` **一行**，`src/game/patrol_ai.gd` 与 Sprint 1 已绿测试**零改动**。**口径 (b) 扩参 `(checkpoint_data: Dictionary)` 已否决，实现期不得单边扩参**；若后续确需上下文，须重开 FLAG 并经主理人裁决，不得在 Story 内自行变更。
- **验收（G/W/T）**
  - Given `GuardBrain._checkpoint_sink: Callable` 现为**零参** no-op（`src/game/patrol_ai.gd:119` 声明 / `:174` 注入口 / `:366-371` `_on_soft_fail` 内 `.call()`）；GDD §4 定 Sprint 2 注入 `SaveManager.restore_checkpoint`，**仅改 1 行**。
  - When 软失败触发（暴露宽限 `GRACE_RT=1.2s` 真实时间达）→ `E08-S4` 调 `_checkpoint_sink.call()`。
  - Then `restore_checkpoint()` 还原最近检查点：玩家位姿、可疑度清零、守卫 FSM 回 `RETURN`/巡逻、灯/道具差异态还原；发 `checkpoint_restored(checkpoint_id)` → E09 软重开 UI。
  - Then **★ arity 契约测试 `@test_checkpoint_sink_arity_contract`（FLAG-A 缓解②，强制落地）**：断言 `SaveManager.restore_checkpoint` 的形参个数 **== 0**，且注入 sink 的**实参个数 == 形参个数**（`_checkpoint_sink.call()` 零实参）。`test_patrol_ai.gd::test_soft_fail_invokes_checkpoint_sink_once`（`:413`）加**反向断言**同锁零参。**二者必须同批改动，禁止单边漂移**（batchd R7 / 同类 N-8）。
  - Then 因签名锁定为零参，**Sprint 1 已绿的 `test_patrol_ai.gd` 用例不需修改**，仅**新增**反向 arity 断言（只增不减，对齐 §3 退出标准 4）。
- **依赖**：SAV-S1/S2、E08-S4（Sprint 1 已锁 1.2s 宽限）、E09-S6（软重开 UI 占位）
- **T 恤**：M
- **退出钩子**：`@test_checkpoint_sink_arity_contract`（`tests/unit/test_save_manager.gd` + `test_patrol_ai.gd` 反向断言）、`@test_restore_resets_suspicion_and_guards`
- **控制清单**：C4（检查点粒度，非阻塞）

#### SAV-S4 · 偏好委托 `save_prefs`/`load_prefs` + `a11y.cfg` 一次性迁移
- **Epic / GDD**：E11 · `save-system.md` §2（偏好委托）/§3 · `a11y_settings.gd`（Sprint 0 切片）
- **验收（G/W/T）**
  - Given `A11ySettings` 现直接用 `ConfigFile` 落 `user://a11y.cfg`；GDD 要求改为委托 `SaveManager.save_prefs("a11y", dict)` / `load_prefs("a11y") -> Dictionary`，落 `PREFS_PATH = user://prefs.json`。
  - When 设置变更（即时）或首次启动。
  - Then 偏好经委托落盘/读盘；首次启动**一次性迁移**既有 `user://a11y.cfg`（若存在）入偏好库后删除旧文件；缺字段用默认值补全（向前兼容）。
  - Then **API 必须字段无关**（`section:String → Dictionary` 通用键值），不硬编码 a11y 字段名 —— 否则与 E09-S7 形成循环依赖（见 §5 FLAG-J）。
- **依赖**：SAV-S1（不依赖 E09-S7；由本 Story 的字段无关约束解环）
- **T 恤**：S
- **退出钩子**：`@test_prefs_delegation_roundtrip` `@test_legacy_a11y_cfg_migrated_once`（`tests/unit/test_save_manager.gd`）
- **控制清单**：无

#### SAV-S6 · 版本拒绝 + 损坏处理（绝不静默吞错）
- **Epic / GDD**：E11 · `save-system.md` §2（版本化）/§6（版本/损坏）
- **验收（G/W/T）**
  - Given Sprint 1 minimal 无磁盘数据，故**存档槽无迁移负担**（GDD §2：v1 视为不兼容态，发现即忽略并重建，**不做 v0→v1 迁移**）。
  - When 读入 `slot.version != SAVE_VERSION` 的槽，或 JSON 解析失败。
  - Then **拒绝该槽并标记损坏**，`load_completed(slot_id, false)`，上层 UI 提示「存档版本不匹配」；进程不崩溃、不静默吞错、不覆盖写回。
  - Note 唯一的真实迁移路径是 `a11y.cfg → prefs.json`（归 SAV-S4），不在本 Story。
- **依赖**：SAV-S1/S2
- **T 恤**：S
- **退出钩子**：`@test_version_mismatch_rejected_not_crash` `@test_corrupt_json_rejected_not_swallowed`（`tests/unit/test_save_manager.gd`）
- **控制清单**：无

### Batch B — 互动物件实体级（E07 完整）

#### E07-S1 · DECOY 实体（投出诱饵生成可控噪声圈）
- **Epic / GDD**：E07 · `interactables` §2（DECOY `decoy_landed(pos,surface,radius≈8m) → ④`）
- **验收（G/W/T）**
  - Given `InteractableType.DECOY`（玩家携带物件）；玩家复用 E03 aim 逻辑选落点；`charges[DECOY]>0`。
  - When 投掷诱饵。
  - Then 发 `decoy_landed(pos,surface,radius≈8m)` → E06 生成 DECOY 声事件；`charges[DECOY]−1`；用尽不可投（E07-S5）。
- **依赖**：E06-S4（DECOY 声圈，Sprint 1）、E03（aim）、E07-S5
- **T 恤**：M
- **退出钩子**：`@test_decoy_spawn_emits_decoy_landed_and_decrements_charges`（`tests/unit/test_interactables.gd`）
- **控制清单**：G-02（声环≤8，计入 E06 FIFO）、C-05（非颜色提示）

#### E07-S2 · LIGHT_TOGGLE 实体（熄灯/点亮可互光源）
- **Epic / GDD**：E07 · `interactables` §2（LIGHT_TOGGLE `light_state_changed(id, EXTINGUISHED/LIT) → ⑤`）
- **验收（G/W/T）**
  - Given `InteractableType.LIGHT_TOGGLE`（世界互动物件，关卡布置、就近触发）；信号签名 `(light_id:int, state:LightState)`（Sprint 1 E01-S9 已冻结，**不得改**）。
  - When 玩家对准可互光源按互动键。
  - Then 发 `light_state_changed(id, state)` → E04 切换 OmniLight + 自发光 + 雾 ramp（R-05）+ E05 受影响 cell 重算。
- **依赖**：E04-S4/S5（Sprint 1）、E05（cell 重算）、E07-S5
- **T 恤**：M
- **退出钩子**：`@test_light_toggle_emits_light_state_changed`（`tests/unit/test_interactables.gd`）
- **控制清单**：R-02（可熄光源计入 E04 ≤32）、R-05（ramp≤0.12/≤0.4s）、G-03（事件驱动 O(cell)）

#### E07-S3 · TRAP 实体（内部 FSM + 触发机关声/光/阻路由）
- **Epic / GDD**：E07 · `interactables` §2 · `sprint2-design-scope.md` §2.1（TRAP FSM）
- **验收（G/W/T）**
  - Given `InteractableType.TRAP`（世界互动物件）；内部 FSM `IDLE→ARMED→TRIGGERED→RECOVER/SPENT`；拉杆/符文/绞盘映射既有的声/光/阻动词。
  - When 玩家触发机关。
  - Then 发 `interactable_triggered(obj_id, TRAP, payload)` → 路由到 E04/E05/E06（声/光/阻），**不新增机制族、不新增事件词汇**。
- **依赖**：E04/E05/E06、E07-S5
- **T 恤**：M
- **退出钩子**：`@test_trap_fsm_transitions` `@test_trap_routes_to_sound_light_block`（`tests/unit/test_interactables.gd`）
- **控制清单**：G-02/R-02（路由后计入对应预算）

#### E07-S4 · SMOKE 实体（`smoke_factor` 注入 E05，解决 C3）
- **Epic / GDD**：E07 · `interactables` §2 · consistency-review C3 · `sprint2-design-scope.md` §2.1
- **验收（G/W/T）**
  - Given `InteractableType.SMOKE`（玩家携带物件）；C3 要求烟雾改写 E05 可见性。
  - When 玩家掷烟雾。
  - Then 落点区生成临时区，E05 `compute_visibility` 按 `vis = base × cover × smoke` 乘 **`smoke_factor = 0.3`**；**限时 ≈4s** 后失效；`charges[SMOKE]−1`。
- **依赖**：E05-S6（`visibility_multiplier` 注入，Sprint 1 C3）、E07-S5
- **T 恤**：M
- **退出钩子**：`@test_smoke_applies_visibility_0_3_for_4s`（`tests/unit/test_interactables.gd` + `test_vision_cone.gd` 联动）
- **控制清单**：C-03（亮度差非色相）、C-05（非颜色提示）

#### E07-S5 · charges 双模型 + entity-inventory 配置加载
- **Epic / GDD**：E07 · `interactables` §2（charges MVP 每类 2–3 发）· `entity-inventory` · `sprint2-design-scope.md` §2.1（charges 双模型）
- **验收（G/W/T）**
  - Given **双模型**：世界物件（LIGHT_TOGGLE/TRAP）持自身 charges；玩家携带物件（DECOY/SMOKE）按类型计背包 charges。关卡 entity-inventory 配置每类初始值（2–3）。
  - When 关卡加载 / 玩家触发道具。
  - Then 运行时查对应模型 `charges>0` 方可触发；用尽需补给（Sprint 2 仅配置不实现补给 UI）；配置来自 entity-inventory。
  - Then charges 余量以 `interactable_charges: Dictionary[int,int]`（entity_id → 余量）形态暴露给 E11 存档（SAV-S1 字段契约）。
- **依赖**：entity-inventory（资产）、E07-S1~S4、SAV-S1（字段契约）
- **T 恤**：S
- **退出钩子**：`@test_charges_gate_blocks_when_zero` `@test_charges_dual_model_world_vs_carried`（`tests/unit/test_interactables.gd`）
- **控制清单**：无

#### E07-S6 · HUD 道具/charges 显示
- **Epic / GDD**：E07 · `core-hud-a11y` §2（当前道具/charges）/ `interactables` §4
- **验收（G/W/T）**
  - Given `interactable_triggered` 已被 `hud_slice._on_interactable_triggered` 消费（Sprint 1 占位）。
  - When 道具切换 / charges 变化。
  - Then E09 显示当前 `InteractableType` + `charges`（图标+文字，非颜色 C-05）；色值一律取 `HudColors.HUD_COLOR_*`，**不得写颜色字面量**（hud_slice.gd 文件头纪律）。
- **依赖**：E09-S4（Sprint 1）、E07-S1~S5
- **T 恤**：S
- **退出钩子**：`@test_hud_shows_interactable_charges`（`tests/unit/test_hud_slice.gd` 扩展）
- **控制清单**：C-05（图标+标签非颜色）、X-02（机关/诱饵字幕）

#### E07-S7 · 互动物件实例注册/反注册（防 orphan）
- **Epic / GDD**：E07 · `entity-inventory`（实体生命周期）
- **验收（G/W/T）**
  - Given 互动物件实例须引用计数（本 Story **仅覆盖互动物件**；守卫/全局 orphans 治理属 TD-S3，已滑 S3）。
  - When 关卡加载 / 卸载 / 道具实体销毁。
  - Then 注册表增删一致；关卡卸载后无悬空引用；静态扫描互动物件 orphan 数为 0（WARN-ONLY，**不进 N-7 门**）。
- **依赖**：E07-S1~S4
- **T 恤**：S
- **退出钩子**：`@ci:no-orphan-interactables`（`tests/ci/budget_assert.gd`，WARN-ONLY）
- **控制清单**：无（治理项）

#### E07-S8 · 道具声环/光源计入全局预算
- **Epic / GDD**：E07 · control-manifest G-02/R-02 · consistency-review R-物-1/R-物-2
- **验收（G/W/T）**
  - Given DECOY 声环须计入 E06 FIFO（G-02 ≤8）；LIGHT_TOGGLE 熄灯须释放/占用 E04 实时光（R-02 ≤32）。
  - When 道具触发。
  - Then 预算计入对应系统；CI 断言不破 G-02/R-02。
- **依赖**：E07-S1/S2、E06/E04
- **T 恤**：S
- **退出钩子**：`@ci:G-02` `@ci:R-02`（`tests/ci/budget_assert.gd`）
- **控制清单**：G-02（声环≤8）、R-02（动态光≤32）

### Batch C — a11y 完整包 Tier2（E09）

> **批次前提已解除阻塞**：v0.1 草案的 FLAG-C 曾判定「`FOCUS_TINT` 硬编码迁移是 a11y 生效的前置」。**取证后该前提不成立**（`FOCUS_TINT` 在代码库中不存在；`hud_slice.gd` 文件头声明「NO hard-coded colour literal」，Sprint 0 字面量 `#10141C` 等已由 landmine 3 移除，`_dim.color` 读 `HudColors.HUD_COLOR_PANEL_BASE`）。**故 Batch C 不被已滑 S3 的 Tech Debt 阻塞**，见 §5 FLAG-C（已降级）。

#### E09-S5a · 色盲模式完整枚举 + 危险色映射 + 图标
- **Epic / GDD**：E09 · `core-hud-a11y` §7 · control-manifest C-05/C-06/C-07
- **验收（G/W/T）**
  - Given 色盲模式须为完整枚举（OFF/PROTAN/DEUTAN/TRITAN）；危险 `#D64545` → **`#F0C070`** + 图标（C-06）；绝不单色（C-07）。
    - **【v0.2 口径校正 · 2026-08-05 主理人】** 本条原写「`#7A2E2E` → `#C8862F`」，该口径已被 `design/art/accessibility-matrix.md` v0.2（§迁移清单第 2 条，依据 art-bible v0.3 §9.1 FLAG-2 完整修正）**明文作废**：警戒本就是 `#C8862F`，映射后警戒/警报两档亮度比塌缩至 **1.00:1**——等于在无障碍功能内部再犯一次 C-05。现行取值 `#F0C070`（vs 警戒 1.81:1，vs 面板 10.55:1，烛琥珀系明度变体、不引入新色相）。同步依据：`accessibility-matrix.md:186/194/205`（本文件在其待校正下游清单内，责任人「主理人」）。
  - When 玩家切换色盲模式。
  - Then 危险色映射生效于 HUD/世界要素；图标三重编码（亮度+形状+图标）；色值经 `HudColors` 取，不写字面量。
- **依赖**：E09-S7、E05/E08（图标渲染）
- **T 恤**：S
- **退出钩子**：`@test_colorblind_enum_maps_danger_color`（`tests/unit/test_a11y_settings.gd`）
- **控制清单**：C-05（非颜色）、C-06（色盲映射）、C-07（危险不单色）

#### E09-S5b · 时间缩放滑杆 [0.1,1.0] 默认 0.25
- **Epic / GDD**：E09 · `core-hud-a11y` §7 · control-manifest T-01/T-02 · `a11y_settings.gd`（现仅 `time_scale_min=0.1`）
- **验收（G/W/T）**
  - Given `time_scale_user ∈ [0.1, 1.0]`，默认 0.25；须驱动 `TimeController`（E02）。
  - When 玩家拖动时间滑杆。
  - Then `Engine.time_scale` 经 `time_scale_changed` 设到目标值（ramp≈0.15s 缓动，非硬切）；玩家输入实时不受缩放（ADR-003）。
- **依赖**：E09-S7、E02（TimeController）
- **T 恤**：S
- **退出钩子**：`@test_time_slider_bounds_default_0_25`（`tests/unit/test_a11y_settings.gd` + `test_step_commit.gd` 联动）
- **控制清单**：T-01（范围）、T-02（缓动 ramp）、V-06（ease）

#### E09-S5c · 眩晕控制（屏震关 / 雾三态 / 动模糊关）
- **Epic / GDD**：E09 · `core-hud-a11y` §7 · control-manifest V-01/V-03/V-04/V-05
- **验收（G/W/T）**
  - Given `screen_shake=false` 默认关（V-03）；`fog_option{FULL,REDUCED,OFF}` 三态（V-04，现 `fog_enabled:bool` 仅两态须扩）；`motion_blur=false` 默认关（V-05）。
  - When 玩家切换。
  - Then 屏震/雾/动模糊按设置生效于 VFX 层（**含凝神压暗 `_dim` 与 `_set_world_boost` 路径**）；禁 >3Hz 频闪（V-01）。
- **依赖**：E09-S7、VFX 层（E03/E04 残影/雾）
- **T 恤**：S
- **退出钩子**：`@test_fog_option_tri_state_and_motion_blur_off`（`tests/unit/test_a11y_settings.gd`）
- **控制清单**：V-01（禁>3Hz 频闪）、V-03（屏震关）、V-04（雾选项）、V-05（动模糊关）

#### E09-S5d · 文本缩放 [1.0,1.5] + 字幕
- **Epic / GDD**：E09 · `core-hud-a11y` §7 · control-manifest X-01/X-02
- **验收（G/W/T）**
  - Given `text_scale ∈ [1.0, 1.5]`（X-01，现固定 1.0）；`subtitles=true` 说话者+图标（X-02）。
  - When 玩家调整文本缩放 / 开关字幕。
  - Then UI 文本按 `text_scale` 缩放且 **150% 上限不破版**；字幕显示说话者+图标。
- **依赖**：E09-S7、E09-S6（字幕载体）
- **T 恤**：S
- **退出钩子**：`@test_text_scale_range_and_subtitles`（`tests/unit/test_a11y_settings.gd`）
- **控制清单**：X-01（文本缩放）、X-02（字幕）

#### E09-S7 · A11ySettings 完整数据模型 + 接 SaveManager 偏好委托
- **Epic / GDD**：E09 · `a11y_settings.gd`（Sprint 0 切片）· `save-system.md` §2（偏好委托）· SAV-S4
- **验收（G/W/T）**
  - Given Sprint 0 切片仅 `color_blind_mode:String / time_scale_min:float / screen_shake:bool / fog_enabled:bool / motion_blur:bool / text_scale:float=1.0`。
  - When 扩展为完整 Tier2 模型。
  - Then 新增 `colorblind_mode` 四态枚举（OFF/PROTAN/DEUTAN/TRITAN）、`time_scale_user:float[0.1,1.0]`、`fog_option:int{FULL,REDUCED,OFF}`、`subtitles:bool`；**落盘改走 `SaveManager.save_prefs("a11y", dict)` / `load_prefs("a11y")`**（不再直接 `ConfigFile`）；缺字段向后兼容默认。
- **依赖**：SAV-S4（字段无关的偏好委托 API，Batch A）、E09-S5a~S5d
- **T 恤**：M
- **退出钩子**：`@test_a11y_settings_full_model_roundtrip`（`tests/unit/test_a11y_settings.gd`）、`@ci:a11y-values-in-range`
- **控制清单**：无（数据契约）

---

## 2. **Sprint 3 滑期段**（裁决 1：以下 Story 明确不在 Sprint 2 范围）

> 以下 Story **不计入 Sprint 2 退出标准、不计入 Sprint 2 CI 预算门、不在 Sprint 2 排期**。保留原 Story ID 以维持可追溯性，待 `production/sprints/sprint3-stories.md` 建立后迁入。
> 三组滑期依据 `sprint2-design-scope.md` §7 FLAG-1/2/3，主理人已按建议全数采纳。

### S3-A · 守卫变体（E08，对应设计 FLAG-1）

| Story | 标题 | T 恤 | 滑期理由 / 备注 |
| --- | --- | --- | --- |
| **E08-S7** | 守卫变体参数覆盖（猎犬/哨兵） | M | Tier2「期望」非「必做」；纯参数覆盖加法。设计定值：**猎犬 `KV15/KS30`、听觉半径 ×1.6、锥 11m·30°**；**哨兵 `vision_light_floor=0.05`**（`L_DARK=0.20` 阴影里仍 `vis≈0.5`）。阈值 25/60/10、DECAY 8、GRACE 1.2s、≤10Hz **全部不变**，**零新事件** |
| **E08-S9** | 变体实例化与 entity-inventory 类型绑定 | S | 依赖 E08-S7；`guard_spawned` 事件词汇随本组滑 S3 再经 E01-S9 收口 |
| **E08-S10** | 变体 FSM 合并验证（阈值契约不污染） | S | **FLAG-B 的缓解措施本身**，必须与 E08-S7 同批落地，不得单独提前或滞后 |

- **滑期后 Sprint 2 影响**：无。守卫变体不参与 S2 任一退出标准；G-01（守卫 ≤8/16）在 S2 维持 Sprint 1 口径。
- **兜底选项（未启用）**：设计 FLAG-1 曾提「若需保核心张力可只留暗视哨兵」；主理人裁决为**全滑**，本兜底不启用。

### S3-B · 手动存档/读档 UI（E11，对应设计 FLAG-2）

| Story | 标题 | T 恤 | 滑期理由 / 备注 |
| --- | --- | --- | --- |
| **SAV-S5** | 手动存档/读档 UI（槽列表 / 覆盖确认 / 删除入口 / 缩略占位） | M | 便利功能，非软失败核心循环必需。**S2 已交付其全部数据层**（`write_slot`/`read_slot`/3 槽上限/体积门），S3 为**纯表现层增量**，不回头改 L2 |

- **S3 时的验收**：暂停菜单槽列表显示时间戳/检查点 id；非空槽二次确认；读档后 0.4s 淡入；UI 正文 ≥4.5:1（C-01）/关键指示 ≥7:1（C-02）/焦点环 `#C8862F`（C-06）；读档完成字幕（X-02）。
- **✅ 追溯已闭环（FLAG-K RESOLVED）**：`save-system.md` §8 将「手动存档/读档槽（写入/读取/覆盖确认）」列为 **Tier1 必做**。本次滑期是对 GDD Tier1 **UI 层**的**有意延后**（Tier1 定级不变）。GDD §8 已追加「Tier1 口径注记」，明示「**手动存档 UI 滑 Sprint 3，数据层 Sprint 2 交付**」并给出 Tier1a/Tier1b 分层表，GDD↔排期双真相源已消除（见 §5 FLAG-K）。

### S3-C · Tech Debt 收口（对应设计 FLAG-3，用户已标「非阻塞」）

| Story | 标题 | T 恤 | 滑期理由 / 备注（含取证修正） |
| --- | --- | --- | --- |
| **TD-S1** | `hud_slice` 相机引用治理 | S | `hud_slice.gd:432` `set_aim_preview` 用 `get_viewport().get_camera_3d()`，headless 下可能为 null。治理 = 缓存 + 空判 + 测试注入 |
| **TD-S2** | 凝神染色逻辑常量化 / 纳入 a11y 雾管控 | XS | **⚠️ 原描述已作废**：v0.1 写「`hud_slice.gd:10` 硬编码 `FOCUS_TINT := Color("#10141C")`」——**取证后该常量与该字面量均不存在**（文件头明示 Sprint 0 字面量已由 landmine 3 移除，`_dim.color` 读 `HudColors.HUD_COLOR_PANEL_BASE`）。**真实剩余债** = 凝神压暗/提亮（`_dim` + `_set_world_boost`）无具名常量、且未纳入 a11y 雾选项统一管控。治理粒度（仅注释 vs 常量化入 `hud_colors.gd`）= 设计 scope §9-3 未决项，随本组滑 S3 一并裁决 |
| **TD-S3** | 全局 orphans 治理（引用计数 + 关卡路） | M | 残留 orphans（工程报 23 / 历史 46），**不进 N-7 门**（batchd R2）。**互动物件部分已由 S2 的 E07-S7 覆盖**；本 Story 只剩守卫/其余实例 |
| **TD-S4** | 全量债务 + QA 门收口 | M | 范围 = Sprint 1+2+3 全量五退出标准 + 上述 TD 项。**Sprint 2 自身的 CI 收口不依赖本 Story**（见 §3 说明） |

---

## 3. Sprint 2 退出标准（完整 QA 门，范围 = 三必交项）

1. **互动物件实体级闭环**：DECOY/LIGHT_TOGGLE/TRAP/SMOKE 四类均生成实体并派发**既有**事件（零新事件词汇）；TRAP 内部 FSM 可转换；烟雾 `smoke_factor=0.3` 限时 ≈4s 注入 E05（C3 解决）；`charges` 双模型限量且按 entity-inventory 配置，用尽不可触发（E07-S1~S8 全过 + GUT）。
2. **SaveManager 数据层可用**：`SaveSlot` 含前置 `version=SAVE_VERSION(2)`，`write_slot`/`read_slot` 往返可逆；检查点滚动槽静默写入（冷却 ≥0.5s）+ 异步不阻塞主线程；`restore_checkpoint` 注入 D9 seam 且 **arity 契约测试通过**；偏好委托 `save_prefs/load_prefs` 生效 + `a11y.cfg` 一次性迁移；版本不匹配/损坏被拒绝且不崩溃、不静默吞错；单槽 ≤32KB（WARN-ONLY）（SAV-S1~S4/S6 + GUT）。**3 个新事件词汇（`save_completed`/`load_completed`/`checkpoint_restored`）经 E01-S9 收口闭环**，`event_bus.gd` ↔ `system-breakdown.md` §2 逐字一致、CI lint 零漂移（并入 SAV-S2，FLAG-I）。**手动存档 UI 不在本标准内**（滑 S3）。
3. **a11y 完整包 Tier2 生效**：色盲四态枚举 / 时间滑杆 [0.1,1.0] 默认 0.25 / 屏震关 / 雾三态 / 动模糊关 / 文本缩放 [1.0,1.5] 不破版 / 字幕，全部**驱动对应系统（非空转）**；A11ySettings 完整模型经 SaveManager 偏好委托落盘（E09-S5a~S5d/S7 + GUT + E10 自检）。
4. **CI 全绿且零回归**：GUT 在 `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests/unit -gexit` 下全绿（**基线 95/95，新增用例只增不减**）；`budget_assert` WARN-ONLY 无破门；**N-7 门不因裸 `[Risky]` 误红**；Sprint 1 已锁断言（R-02/R-04/R-05/G-02/G-04/G-05/V-02/V-06/C-02）零漂移。

> **关于 Sprint 2 的 QA 门归属**：v0.1 草案把「完整 QA 门收口」放在 TD-S4，而 TD-S4 已随 Tech Debt 滑 S3。**Sprint 2 不因此失去质量门** —— 标准 4 由各 Story 自带的 `@ci:*` 钩子 + Sprint 1 已上线的 `E10-S2` 断言承担，不单列 Story。TD-S4 在 S3 承担的是**跨 Sprint 全量**债务与门收口，二者不重叠。

---

## 4. 测试框架脚手架计划

> **复用**：headless SceneTree harness 已在 `tests/unit/test_integration_step_vision.gd` 建立，Sprint 2 直接复用（`godot --headless` 下跑）。GUT v9.3.0（`-gexit` 退出码门）。**铁律**：新增测试一律正常 `@test_*` + WARN-ONLY 预算断言，绝不发裸 `[Risky]`（N-7 门仅认 GUT 真实 risky token）。
> **基线取证**：本机 `grep -rh "^func test_" tests/unit/*.gd` = **95** 测试函数 / **9** 个 unit 脚本（已复核，与主理人 95/95 一致）。本机 `godot` 不在 PATH，无法实跑。

### 4.1 新增 / 扩展 unit 测试文件（Sprint 2）

| 文件 | 覆盖 Story | 关键测试 |
| --- | --- | --- |
| `test_save_manager.gd`（**新建**） | SAV-S1~S4/S6 | slot roundtrip · write/read slot · 检查点写冷却 0.5s · **sink arity 契约** · restore 重置可疑度/守卫 · prefs 委托 roundtrip · `a11y.cfg` 一次性迁移 · 版本不匹配拒绝 · 损坏 JSON 拒绝不吞错 |
| `test_interactables.gd`（**新建**） | E07-S1~S8 | decoy 落点+charges−1 · light_toggle 信号 · TRAP FSM 转换 + 路由 · smoke_factor 0.3≈4s · charges 双模型门 · 预算计入 |
| `test_a11y_settings.gd`（**新建**） | E09-S5a~S5d/S7 | 色盲四态映射 · 时间滑杆边界+默认 0.25 · 雾三态+动模糊关 · 文本缩放+字幕 · 完整模型经 prefs 委托 roundtrip |
| `test_patrol_ai.gd`（**扩展**） | SAV-S3 | `test_soft_fail_invokes_checkpoint_sink_once`（`:413`）**反向 arity 断言**：sink 实参数与 `restore_checkpoint` 形参数一致；未注入时仍不崩 |
| `test_hud_slice.gd`（**扩展**） | E07-S6 | HUD charges 显示（图标+文字，非颜色） |

> **滑 Sprint 3 的测试文件**：`test_guard_variants.gd`（E08-S7/S9/S10）**不在 Sprint 2 建立**；TD-S1（`test_aim_preview` 无相机依赖修复）、TD-S2（凝神染色常量）、TD-S3（全局 orphans）相关测试同步滑 S3。

### 4.2 Harness 需求
- **SaveManager 测试隔离**：持久化测试**绝不污染**真实 `user://saves/` 与 `user://prefs.json`。用测试专属目录（如 `user://__test_saves/` + `user://__test_prefs.json`）在 `before_all` 设、`after_all` 清理；写读在同测试内闭环。**`a11y.cfg` 迁移测试必须先造一个假的旧文件再验删除**，不得触碰开发机真实档。
- **异步落盘断言**：`write_slot` 立即返回，故断言须 `await` `save_completed` 信号（或 harness 提供同步落盘开关），**不得用固定 `sleep` 猜时序**（flaky 源）。
- **Headless 安全**：所有渲染相关断言（HUD/相机/雾）判 `Engine.get_main_loop()` / `get_viewport()` 非空再断言，避免 Sprint 1 `cam.look_at()` 类脆弱点（注：其根因修复 TD-S1 已滑 S3，故 **Sprint 2 新增 HUD 测试必须自带 null-guard**，不能依赖 TD-S1）。
- **时间控制**：a11y 时间滑杆 / 检查点冷却测试用真实时间（真实钟，非 `time_scale`）；涉及 `Engine.time_scale` 的用例 `after_each` **必须复位为 1.0**（Sprint 1 flaky 防护纪律）。

### 4.3 CI 预算门（`tests/ci/budget_assert.gd`，全部 WARN-ONLY）

**Sprint 2 新增项（仅保留 S2 相关）**

| 断言 | 归属 Story | 内容 |
| --- | --- | --- |
| `@ci:save-schema-has-version` | SAV-S1 | 存档结构缺 `version` 字段或非首字段 → WARN |
| `@ci:save-size-budget` | SAV-S2 | 单槽 JSON **≤ 32 KB**，超出 WARN（口径对齐 GDD §6，非草案的 64KB） |
| `@ci:a11y-values-in-range` | E09-S7 | 读偏好库校验 `time_scale_user ∈ [0.1,1.0]`、`text_scale ∈ [1.0,1.5]`、`fog_option ∈ {0,1,2}`、`colorblind_mode ∈ {0..3}`，缺失/越界 WARN |
| `@ci:no-orphan-interactables` | E07-S7 | **仅互动物件**实例引用计数平衡，orphan>0 WARN（**不进 N-7 门**） |
| `@ci:interactable-instance-cap` | E07-S7/S8 | 同行互动物件实例 ≤16（Tier2 上限，关联 R-02），WARN-ONLY |

**滑 Sprint 3（本 Sprint 不加）**：`@ci:no-orphans`（全局 orphans，TD-S3）· `@ci:N-7-clean` / `@ci:budget-assert-warn-only` 的**全量**收口（TD-S4）· 变体相关 G-01 扩展断言（E08-S9）。

**不变项（Sprint 1 已上线，维持零漂移）**：R-02(光≤32) / R-04(雾≤0.05) / R-05(ramp≤0.12) / R-06(UV2) / G-02(声环≤8) / V-02(脉动≤2Hz) / V-06(ease) / C-02(对比≥7:1)；N-7 门正则 `\[Risky\]:|\[Pending\]:|\[Risky\] Script was skipped` **不变**；`budget_assert` 始终 `exit 0`（D15-A，lean 不阻塞构建）。

---

## 5. 架构风险 FLAG（收口版）

> 状态标记：**OPEN** = 需主理人/上游裁决；**MITIGATED** = 缓解已写入 Story，实现期执行即可；**CLOSED** = 取证后消解。

### FLAG-A · SaveManager 版本化 + C4 seam arity（高｜**✅ RESOLVED (a) — 主理人采纳「零参」口径，签名已锁**）

> **裁决结论**：采纳**口径 (a) 零参**。`SAV-S3` 的签名锁定为 `func restore_checkpoint() -> void`，与权威 GDD `save-system.md` §4「⑥ 调 `_checkpoint_sink.call()` …… **仅改 1 行**」逐字一致。
> **落地约束（已写入 SAV-S3）**：
> 1. 注入 = `set_checkpoint_sink(SaveManager.restore_checkpoint)` **一行**；`src/game/patrol_ai.gd` 与 Sprint 1 已绿测试**零改动**。
> 2. **arity 契约测试 `@test_checkpoint_sink_arity_contract` 仍强制落地**——它锁的是「两侧一致」而非某个特定 arity，故不因签名定稿而豁免；断言 `restore_checkpoint` 形参数 == 0 且 sink 实参数 == 形参数。
> 3. `test_patrol_ai.gd:413` 加**反向断言**同锁零参；二者同批改动，**禁止单边漂移**。
> 4. **口径 (b) 扩参 `(checkpoint_data: Dictionary)` 已否决**。实现期若判定确需 GuardBrain 侧上下文（如触发者 `guard_id`），**须重开 FLAG 交主理人裁决**，不得在 Story 内自行扩参。
> 5. 写入侧由「玩家进入检查点区」触发（SAV-S2），与软失败**读取**路径解耦——分层保持干净。
>
> **① 版本化子项**：维持原缓解，见下（`SAVE_VERSION` 前置 + CI 断言），本次裁决不改动。

**原风险记录（存档备查）**
**风险**：① 版本字段若后置或缺失，旧/异版档读入即崩；② `GuardBrain._checkpoint_sink` 现为**零参** `.call()`（`patrol_ai.gd:366-371`），Sprint 2 接真实 `SaveManager.restore_checkpoint` 时若单边扩参，`test_soft_fail_invokes_checkpoint_sink_once`（`test_patrol_ai.gd:413`）与调用点即刻漂移崩溃（batchd R7，同类 N-8）。

**缓解（已写入 Story，Batch A 内执行）**
1. **`schema_version` 前置**（SAV-S1）：`version` 恒为写入的第一个字段、恒等 `SAVE_VERSION=2`；**所有读取路径先读版本再解析其余**。配 `@ci:save-schema-has-version` + `@test_version_mismatch_rejected_not_crash`（SAV-S6）。
2. **`_checkpoint_sink` 扩参契约测试**（SAV-S3）：新增 `@test_checkpoint_sink_arity_contract`，断言注入 sink 的实参个数 == `restore_checkpoint` 形参个数；`test_patrol_ai.gd:413` 同步加反向断言。**二者必须同批改动，禁止单边漂移**（参考 batchd R7）。

**~~⚠️ 本 FLAG 仍 OPEN 的原因（须开工前定稿一个口径）~~ —— 已由上方裁决关闭，以下为决策留痕**：权威 GDD `save-system.md` §4 明确写「⑥ 调 `_checkpoint_sink.call()`，由 SaveManager 还原……**仅改 1 行**」，即**设计侧口径是零参**（SaveManager 内部持有最近检查点，无需 GuardBrain 传参）；而本工程草案 v0.1 假设扩为 `(checkpoint_data: Dictionary)`。
- **口径 (a) 零参（GDD 现状，工程推荐）** ← **✅ 已采纳**：`set_checkpoint_sink(SaveManager.restore_checkpoint)` 一行注入，`patrol_ai.gd` 与既有测试**零改动**，风险面最小；写入侧由「玩家进入检查点区」触发（SAV-S2），与软失败读取路径解耦——分层更干净。
- **口径 (b) 扩参 `(checkpoint_data)`** ← **❌ 已否决**：仅当 restore 确需 GuardBrain 侧上下文（如触发者 guard_id）时才有必要，代价是改调用点 + 改 Sprint 1 已绿测试。
- **无论选哪个，arity 契约测试都必须落地**（它锁的是「两侧一致」，不是某个特定 arity）。**建议采纳 (a)** —— **主理人已拍板 (a)，SAV-S3 最终签名 = `func restore_checkpoint() -> void`（零参）。**

### FLAG-B · 守卫变体 FSM 合并污染（中-高｜**DEFERRED → Sprint 3**）
变体若以运行时 mut 实例常量实现参数覆盖，将破坏 Sprint 1 已锁阈值测试（THR_SUSP=25/THR_ALERT=60/THR_RETURN=10/DECISION_HZ=10）。缓解 = **用参数对象/overlay 而非改类常量**，并由 E08-S10 合并验证卡门。**随 E08 变体整组滑 S3，Sprint 2 不承担**；S3 开工时 E08-S10 必须与 E08-S7 同批。

### FLAG-C · a11y 与 HUD 耦合（**已降级：中 → 低**｜**CLOSED（阻塞前提消解）/ 残留观察项**）
**原判定作废**：v0.1 称「`FOCUS_TINT` 硬编码（TD-S2）不迁入 `HudColors` 则 a11y 雾选项无法统一管控，是 E09-S5c 的前置」。**取证结论**：`FOCUS_TINT` 常量与 `#10141C` 字面量在 `src/`、`tests/` 中**均不存在**；`hud_slice.gd` 文件头明示「This file must contain NO hard-coded colour literal」，Sprint 0 字面量已由 landmine 3 移除，`_dim.color = _with_alpha(HudColors.HUD_COLOR_PANEL_BASE, 0.35)`。
**结论**：**a11y 完整包（Batch C）不被已滑 S3 的 Tech Debt 阻塞**，裁决 1 的滑期在此点上无隐藏耦合。
**残留（低，非阻塞）**：凝神压暗/提亮（`_dim` / `_set_world_boost`）尚未纳入 a11y 雾选项统一管控 —— 已写入 E09-S5c 验收（「含凝神压暗路径」），治理粒度归 S3 的 TD-S2。

### FLAG-D · orphans 技术债（低-中｜**部分 MITIGATED / 其余 DEFERRED → S3**）
互动物件部分由 **E07-S7**（Sprint 2）以引用计数 + 关卡卸载清理覆盖，配 `@ci:no-orphan-interactables`；守卫及全局部分随 **TD-S3** 滑 S3。全程**不进 N-7 门**（batchd R2）。

### FLAG-E · CI N-7 误红（纪律，非新风险｜**MITIGATED**）
Sprint 1 已踩坑——严禁在测试里写裸 `[Risky]`。Sprint 2 新测试一律正常 `@test_*` + WARN-ONLY 预算断言，绝不发 `[Risky]` 字面（仅 GUT 真实 risky token 触发门）。

### FLAG-F · 取证偏差（HEAD 不一致，低｜**CLOSED**）
本地 `git rev-parse HEAD` = `9ca499d`，主理人称 main HEAD = `be15521`（Merge PR #3）。`9ca499d` 是 `be15521` 的父提交，**内容一致**，仅 CI 文本微调，无功能差异。当前工作分支 `plan/sprint-2`。

### FLAG-G · GUT 测试数（取证，低｜**CLOSED**）
本机静态计数实测 **95** 测试函数 / **9** 个 unit 脚本，与主理人 95/95 一致；`batchd-qa-plan.md` 记载的 94/94 为陈旧残留（scripts=9 口径一致）。本机 `godot` 不在 PATH，无法实跑，依赖工程报数 + 静态计数。

### FLAG-H · 工程草案与权威 GDD 的存档数值冲突（**中**｜**MITIGATED — 本版已全数改判 GDD 口径**）
v0.1 工程草案早于 `design/gdd/systems/save-system.md` 落盘，五处数值/形态冲突。**本版一律以 GDD 为单一真相源**，草案口径作废：

| 项 | v0.1 草案（**作废**） | **本版 = GDD `save-system.md`** |
| --- | --- | --- |
| 版本字段 | `schema_version:int`，首版 = 1 | `version:int`，`SAVE_VERSION = 2` |
| 落盘形态 | `ConfigFile` → `user://save_slot_N.cfg` | JSON → `user://saves/slot_{id}.json`；偏好 `user://prefs.json` |
| 单档体积 | ≤ 64 KB | **≤ 32 KB** |
| 旧档处理 | v0→v1 **双向迁移** | 版本不匹配 → **拒绝 + 标记损坏，不迁移**；唯一迁移是 `a11y.cfg → prefs.json` |
| 新信号 | 建议 `checkpoint_saved/loaded` | `save_completed` / `load_completed` / `checkpoint_restored` |
| 槽模型 | 未定义 | 检查点滚动槽 `-1` + 手动槽 `0..2`（`MAX_MANUAL_SLOTS=3`） |

**若主理人对任一行有异议，请以此表为裁决单**——工程侧一律照 GDD 执行，不自行另立数字。

### FLAG-I · SaveManager 新增 3 个事件词汇须经 E01-S9 收口（中｜**✅ RESOLVED — 已并入 SAV-S2 验收，不另开 Story**）

> **裁决结论**：采纳工程建议 —— **并入 `SAV-S2` 验收**，**不**单列 `E01-S9b` Story。成本 **XS**，不改变 Batch A 的 T 恤总量与排期。

GDD §4 新增 `save_completed(slot_id:int, success:bool)` / `load_completed(slot_id:int, success:bool)` / `checkpoint_restored(checkpoint_id:String)`，属**事件词汇表扩充**。项目铁律是「事件词汇零漂移，任何信号增改须经 E01-S9 收口，`event_bus.gd` 与 `system-breakdown.md` §2 必须逐字一致，并由 CI lint 断言无未声明信号」。

**落地位置（已写入 SAV-S2 验收第 3 条）**
1. `src/core/event_bus.gd` 声明 3 信号；
2. `design/gdd/system-breakdown.md` §2 共享事件词汇表登记（逐字一致）；
3. E01-S9 CI lint 断言「无未声明信号 / 无拼写漂移」通过 —— 退出钩子 `@ci:event-vocab-zero-drift`。

**三处须同批完成、零漂移方可 SAV-S2 退出。** E01-S9 在 Sprint 1 已闭合，本次为**再次开启**收口一轮（3 个信号），闭合后回到冻结态。
- 另注：`guard_spawned`（设计 §6 提及，属 E08 变体）**随变体滑 S3**，本 Sprint **不声明**，不得顺手加入词汇表。

### FLAG-J · a11y 数据模型 ↔ 偏好持久化循环依赖（**中**｜**CLOSED — 本版已解环**）
v0.1 中 SAV-S4 依赖 E09-S7、E09-S7 又依赖 SAV-S4，构成跨批（A↔C）循环，会导致 Batch A 无法独立收口。
**解法（已写入验收）**：SAV-S4 的偏好 API **必须字段无关**（`save_prefs(section:String, data:Dictionary)` / `load_prefs(section) -> Dictionary`，不硬编码任何 a11y 字段名）。于是依赖变为单向 **SAV-S4（Batch A，机制）→ E09-S7（Batch C，字段模型）**，环解除，Batch A 可独立退出。此约束与 GDD §2「偏好委托……其他 L2 偏好（音量、画质预设）同机制扩展」一致。

### FLAG-K · 手动存档 UI 滑期造成 GDD Tier1 与排期不一致（低｜**✅ RESOLVED — GDD §8 已加注，双真相源消除**）

> **闭环动作**：`design/gdd/systems/save-system.md` §8 已追加「**Tier1 口径注记（FLAG-K 闭环）**」——明确「**手动存档 UI 滑 Sprint 3，数据层 Sprint 2 交付**」，并以 Tier1a（数据层 / S2）÷ Tier1b（UI 层 / S3）分层表定死口径。

`save-system.md` §8 把「手动存档/读档槽（写入/读取/覆盖确认）」列为 **Tier1 必做**，而裁决 1 将其 UI 滑 S3。工程侧已按裁决执行（S2 只交数据层）。
**关键澄清（已写入 GDD）**：`game-concept.md` §5 的 **Tier1 定级不变**——滑期的**只是 UI 呈现层**，不是能力本身；数据层（含手动槽 `0..2` 的完整读写 API 与磁盘格式）在 S2 已交付，S3 的 `SAV-S5` 是**纯表现层增量，不回头改 L2**。
**排期真相源统一**：GDD 只定义能力与分层，排期一律以 `sprint2-stories.md` / `sprint3-stories.md` 为准。**不阻塞 Sprint 2 实现**。

---

## 6. Epic 结构（裁决 2 后的定稿）

> 总表见 `production/epics/epic-overview.md` §1（E11 已正式列入）+ §3 Sprint 2 段。

- **E11 · 存档与设置持久化（SaveManager）— 正式新立**（裁决 2）。从 E01 剥离：E01 保留 EventBus / Grid / SpatialQuery / TimeController / LightState / NavServer / InputManager / A11ySettings **接口**；E11 承载 SaveManager 的真实持久化实现（schema / 槽读写 / 检查点 / 偏好委托 / 版本拒绝）。**原 `E01-S5` 的 SaveManager 职责整体迁入 E11 的 SAV-S1~S6**（`E01-S8` NavServer 不受影响，仍归 E01 且仍为 seam 占位）。Sprint 2 交数据层（SAV-S1~S4/S6），Sprint 3 交 UI（SAV-S5）。
- **E07 升级**：S1~S6 从「信号级(Sprint 1)」升级为「实体级(Sprint 2)」；新增 S7（实例注册/orphan）、S8（预算计入）。**全部 8 条留 Sprint 2**。
- **E08**：S1~S6/S8 Sprint 1 已闭；**S7/S9/S10 变体三条滑 Sprint 3**。
- **E09**：S5 拆 S5a~S5d + 新增 S7（完整模型 + 偏好委托）；**5 条全部留 Sprint 2**；S6 软重开 UI 在 SAV-S3 落地后接 `checkpoint_restored` 实信号。

*Sprint 2 Story 拆分 v1.0（裁决收口）完成。逐 Story 实现见 Phase 5；用例填充交 quality-lead。滑期项待 `sprint3-stories.md` 建立后迁入。*
