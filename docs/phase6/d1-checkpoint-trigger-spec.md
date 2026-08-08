# D1 · 自动检查点触发规格（Checkpoint Trigger Spec）

**作者：** 文策渊（design-strategist）　**阶段：** Phase 6 打磨 · D1
**受众：** 程基岩（engine）实现 / 主理人游承峰路由
**纪律：** 本文档为「诊断 + 规格」，不改任何 `.gd` 源码；所有判定附 `file:line` 证据。

---

## 0. 诊断结论（D1 实为「双半环」缺口）

Playtest 报告 D1（Major，`docs/phase6/playtest-report.md:39,79`）只描述了**写入半环未闭**：实机从不调用 `write_slot(CHECKPOINT_SLOT_ID, …)`，`restore_checkpoint()` 在首软失败时静默 no-op（`save_manager.gd:650-654`）。

复核发现 **D1 还有伴生缺口——恢复应用半环同样未实现（见 §3）**：即便补上写入端，`restored_state` 也只被测试读取，游戏层（⑥）从不消费。两者必须**同时**闭合，否则核心循环「存→读」仍半开。

---

## ① 触发事件表（何时写检查点）

GDD 意图触发器是「玩家进入检查点区 / `#checkpoint` 锚点」（`design/gdd/systems/save-system.md:18`：「玩家进入关卡检查点区（或触发 `#checkpoint` 锚点）即静默写入最新快照」）。**代码中目前不存在该体积/锚点实体**（`grep` 无 `area_entered`/`checkpoint`/`region_entered` 的游戏逻辑；`grep` 仅 `save_ui_model.gd`/`save_slots_screen.gd` 提及 checkpoint，且后者未挂载）。

在现有信号中筛选候选（发射点均经 `grep .emit(` 核实）：

| # | 候选触发事件 | 信号 / 发射点 `file:line` | 理由 | 推荐度 |
|---|---|---|---|---|
| **1** | **进入检查点体积** `CheckpointVolume.body_entered`（玩家） | 新实体；设计锚点 `save-system.md:18`；视觉语言 `sprint2-asset-spec.md:420,632`（冷 `#3E5C76` 地面印记环，绝不用暖光） | **与 GDD §2 逐字一致**，diegetic，体积进入天然离散 → 触发稀疏，与 §6 节流天然协同。最干净、最正确。 | ★ 最佳单一接入点 |
| 2 | 潜行成功动作 `interactable_triggered`（过滤 LIGHT_TOGGLE/DECOY/TRAP 成功） | `event_bus.gd:82`；发射 `interactable_entity.gd:133` | 「刚安全推进一节点」= 合理检查点时刻；**最少新代码**（复用现有总线信号）。但属「动作」非「区域」，与 §5 diegetic 语义有偏差，且需过滤+去抖（陷阱触发不算安全）。 |  interim 备选 |
| 3 | 守卫回到巡逻 `guard_fsm_changed(new==RETURN)` | `event_bus.gd:77`；发射 `patrol_ai.gd:505` | 「脱离追捕=又安全了」语义好。但噪声大（多守卫、多次跳变），需每守卫去抖+全局冷却。 | 备选（弱） |
| 4 | 玩家每步提交 `player_step_committed` | `event_bus.gd:57`；发射 `step_commit.gd:68` | 随时可得、必触发。但 ~8 Hz（冷却 0.12s），**违反 §5「检查点 diegetic、绝不弹窗/任意自动存」**，且 §6 0.5s 冷却仅能压制频率不能解决语义错误。 | ✗ 不作为主触发 |

**最佳单一接入点（GDD 终态）= #1 `CheckpointVolume` 进入事件。** 若 Phase 6 要求以最少改动先落地，采用 **#2（过滤后 `interactable_triggered`）** 作为过渡，但需在规格中标注其 diegetic 偏差，最终仍应替换为 #1。

**Phase 6「现在接」的最佳单一接入点 = 新建 `CheckpointCoordinator`（L-world 节点）：** 它订阅 `_bus.interactable_triggered`（`interactable_entity.gd:133`）与 `_bus.guard_fsm_changed`（`patrol_ai.gd:505`），任一触发即采集 §② 七字段并调 `SaveManager.write_slot(CHECKPOINT_SLOT_ID, data)`。此节点即**写入端的唯一接入点**，使 `SaveManager`（L2）保持纯函数、不反向触达 L3/L4（`save_manager.gd:24` 单向依赖）。`CheckpointVolume`（#1）建成后，仅新增一个发射源调用同一 coordinator，写入逻辑不变。恢复应用端（§③ `CheckpointApplier`）同理订阅 `checkpoint_restored`。

---

## ② 快照 schema（传给 `write_slot` 的 data）

`write_slot(CHECKPOINT_SLOT_ID, data)` → `make_slot(slot_id, is_checkpoint, data)`（`save_manager.gd:243,258,175-188`）。**`make_slot` 只接受 11 个 GDD 字段，未知 key 被静默丢弃**（`:173-174`：「Unknown keys in `data` are DROPPED」）。故 data 必须且只能含下表字段：

| 字段（data key） | data 中类型 | 经 make_slot 规整 | 写入端采集源（实现取此处） |
|---|---|---|---|
| `checkpoint_id` | String | `str(...)`（`:181`） | 体积 id，如 `"cp_atrium_01"` |
| `player_pose` | `{pos:Vector3, facing:float, gait:int}` | `_norm_pose`/`_encode_pose`（`save_manager.gd:824-840`，Vector3→`[x,y,z]`） | 玩家节点 `global_position` + 朝向 yaw；切片中为 `Marker3D "Player"`（`sprint0_bootstrap.gd:122-125`） |
| `suspicion` | `{guard_id:int → float}` | `_norm_int_float`（`:183,864`） | 每守卫 `suspicion`（可选；恢复时强制归 0，见 §3） |
| `guard_states` | `{guard_id:int → GuardState:int}` | `_norm_int_int`（`:184,872`） | 每守卫 `GuardBrain.get_state()`（`patrol_ai.gd:243`） |
| `interactable_charges` | `{obj_id:int → int}` | `_norm_int_int`（`:185`） | **`InteractableRegistry.snapshot_charges()`**（`interactable_registry.gd:250`）✅ 已实现 |
| `light_states` | `{light_id:int → bool}`（LIT→true） | `_norm_int_bool`（`:186`） | 遍历灯：`LightModel.get_light_state(id)`（`light_model.gd:109`），`LIT`→true / `EXTINGUISHED`→false |
| `a11y_prefs` | Dictionary | pass-through（`:187`） | **省略**（偏好走 `save_prefs`，FLAG-J 字段无关） |
| `timestamp` | float | 自动填充（`:180`） | 省略（不传即取当前时间） |

**兼容性结论：** 上表 7 个字段全部落在 `SLOT_FIELD_ORDER`（`save_manager.gd:64-76`）11 字段内，`encode_slot`/`decode_slot`（`:193-215`）可往返。
**⚠ 红线：** 不得新增 `objective_progress` / `region_id` / `inventory` 等字段——它们会被 `make_slot` 静默丢弃（`:173-174`），造成「以为存了其实没存」的隐性 bug。

**为何必须含 `guard_states`/`suspicion`：** `restore_checkpoint()` 的 `_normalise_restored`（`save_manager.gd:667-687`）只重置 **snapshot 里出现过的** 守卫为 RETURN（`guard_states` 键集）。若写入端省略 `guard_states`，恢复时除「触发软失败的那个守卫」（由 `_on_soft_fail` 局部重置，`patrol_ai.gd:431-434`）外，**其余守卫不会被拉回巡逻**——回滚不完整。故写入端必须枚举全部活动守卫。

**守卫枚举源（实现注意）：** `patrol_ai.gd` 与派生类**未**加入任何 group（`grep add_to_group` 仅 `event_bus.gd:88` / `save_manager.gd:131`）。写入/应用两端需统一的可枚举源——建议 `guard_spawner.gd` 暴露 `get_active_brains()`，或给守卫加 `add_to_group("guard_brain")`（小改，路由程基岩）。

---

## ③ 恢复闭环校验（伴生缺口 = 恢复应用未实现）

`restore_checkpoint()`（`save_manager.gd:647`）流程：读 `_checkpoint_cache`/文件 → `restored_state = _normalise_restored(slot)`（`:660`）→ 延迟发射 `checkpoint_restored`（`:661`）。`restored_state` 形状（`save_manager.gd:680-687`）：`{checkpoint_id, player_pose, suspicion(全0), guard_states(全RETURN), interactable_charges, light_states}`。

**现状消费者核查（grep `restored_state` 与 `checkpoint_restored`）：**

| 消费者 | 位置 | 行为 | 是否真正应用世界态 |
|---|---|---|---|
| `restored_state` 读取 | `test_save_manager.gd:422` | 测试断言 | ✗ 测试专用 |
| `checkpoint_restored` 连接 | `save_slots_screen.gd:253-254` → `_on_checkpoint_restored`（`:496`）→ `model().on_checkpoint_restored`（`save_ui_model.gd:743`） | **仅更新 UI 只读行的 `checkpoint_id` 字符串** | ✗ UI 行刷新 |
| `checkpoint_restored` 连接 | `test_save_manager.gd:115` | 测试断言 | ✗ 测试专用 |
| **游戏层 ⑥ 应用 restored_state** | — | **不存在** | ✗ **缺口** |

且 `save_slots_screen.gd` 在竖切片中**未挂载**（`sprint0_bootstrap.gd:102-118`，报告 `:39`），故实机运行时 `checkpoint_restored` **零活跃订阅者**。

**架构意图 vs 现实：** `save_manager.gd:108-110,664-666` 与 `event_bus.gd:44-46` 明确规定「⑥ 在 `checkpoint_restored` 上应用 `restored_state`」，且该信号是 ⑥ **唯一**可订阅的 L2 存档事件。但**该消费者从未实现**。

**结论 = D1 伴生缺口：** 即便补上写入端，软失败链 `patrol_ai.gd:437-442`（`_checkpoint_sink.call()`）→ `restore_checkpoint()` 会算出 `restored_state` 并广播，但**无人把玩家位姿/其余守卫/灯/道具电荷复位到该快照**。玩家仍停留在被抓处，世界不回滚，循环依旧半开。

**规格要求（必须实现 `CheckpointApplier`，新 L4 节点）：**
1. 经 group `"save_manager"`（`save_manager.gd:131`）取 `SaveManager`；连接 `EventBus.checkpoint_restored`（架构允许 ⑥ 订阅的唯一年鉴事件）。
2. 收到后读取 `SaveManager.restored_state`（`save_manager.gd:111`，已在延迟发射前同步赋值 `:660`，消费者必可见），按序应用：
   - **玩家**：`player.global_transform`/position + facing ← `restored_state.player_pose`（`_decode_pose` 形状 `save_manager.gd:843-853`）。
   - **守卫**：遍历活动守卫，对每个调 **新增公共 API `GuardBrain.apply_checkpoint_reset()`**（复用 `_on_soft_fail` 的归零逻辑：`suspicion=0`、`exposure_timer=0`、`last_known=ZERO`、`_set_fsm(RETURN)`，但**不发 `exposure_detected`**——恢复不是被抓）。当前 `_set_fsm` 为私有（`:495`），需新增公共封装，路由程基岩。因 `guard_states` 已被 `_normalise_restored` 强制全 RETURN，applier 直接全量 reset 即可。
   - **灯**：`for id,lit in restored_state.light_states:` `LightModel.set_light_state(id, LIT if lit else EXTINGUISHED)`（`light_model.gd:113`）。
   - **道具电荷**：`InteractableRegistry.restore_charges(restored_state.interactable_charges)`（`interactable_registry.gd:254`）✅ 已实现。
3. （可选/延后）触发 ⑧ 软重开 UI（0.6s 黑场+字幕，`system-breakdown.md:48`）——该屏属 Sprint 3 未挂载，Phase 6 可仅做世界应用。
4. **必须在 `sprint0_bootstrap.gd:_ready` 挂载/启用该 applier**（与 `SaveSlotsScreen` 刻意不挂载相反——恢复应用是核心循环硬依赖，不可省略）。

---

## ④ 节流 / 频率建议

- 写入端 **已兜底节流**：`write_slot` 对 CHECKPOINT 走 `_checkpoint_write_throttled()`（`save_manager.gd:251`），`CHECKPOINT_WRITE_COOLDOWN = 0.5s`（`:54,355-360`）→ 即便触发每帧密集，最多 1 次写/0.5s；被节流者以 `success=false` 返回但 ⑧ 忽略 slot -1 toast（`:253`，§5 不弹窗）。
- **设计层仍应避免无意义高频触发**：
  - #1 体积进入天然离散，几乎不会连发；可再加「单次访问已写」去抖，避免同一体积反复刷写。
  - 若用 #2/#3：加全局去抖 + 仅对「安全推进」类事件写（过滤 LIGHT_TOGGLE/DECOY 成功、按守卫去抖 RETURN 跳变），避免每次微小交互都重拍快照。
  - **勿用 #4 `player_step_committed`** 作主触发：8 Hz 下节流仅掩盖浪费，且背离 §5 diegetic。
- 目标：触发**稀疏且对应真实新安全节点**，使滚动缓存/磁盘写是有意义的新快照，而非同点重复。

---

## ⑤ 给程基岩的实现清单（改哪个文件 / 调什么 / 是否补消费者）

| 项 | 文件 / 段 | 动作 | 备注 |
|---|---|---|---|
| A | **新建** `src/game/checkpoint_volume.gd`（Area3D） | 玩家 `body_entered` → `CheckpointProducer.produce(checkpoint_id)`；每体积带 `checkpoint_id` | 最佳触发点（#1）；视觉用冷 `#3E5C76` 印记环（`sprint2-asset-spec.md:420,632`） |
| B | **新建** `CheckpointProducer`（或并入现有玩法节点） | 采集 §② 七字段 → `SaveManager.write_slot(SaveManager.CHECKPOINT_SLOT_ID, data)`；SaveManager 经 group `"save_manager"` 取 | 不弹任何 toast（§5） |
| C | **新建** `CheckpointApplier`（L4） | 连接 `EventBus.checkpoint_restored`，读 `SaveManager.restored_state`，按 §③.2 应用玩家/守卫/灯/电荷 | **伴生缺口必做**；在 `sprint0_bootstrap.gd:_ready` 挂载 |
| D | `src/game/patrol_ai.gd` | **新增公共** `apply_checkpoint_reset()`（归零+`_set_fsm(RETURN)`，不发 exposure_detected） | 当前 `_set_fsm` 私有（`:495`）；供 applier 调用 |
| E | `src/game/guard_spawner.gd` | **无需新增枚举 API**：`GuardSpawner.live_guards()`（`guard_spawner.gd:83`）已返回 `Array[GuardBrain]`；仅给 coordinator/applier 注入 level 持有的 `GuardSpawner` 引用即可（守卫当前未入任何 group，`grep add_to_group` 仅 `event_bus.gd:88`/`save_manager.gd:131`）。 | 写入(B)/应用(C)共用 |
| F | `src/main/sprint0_bootstrap.gd` | 挂载/启用 `CheckpointApplier`（与 `SaveSlotsScreen` 不挂载相反） | 恢复应用不可省略 |
| G | `tests/unit/` | 集成测试：真实软失败 → 断言产生检查点槽文件 → 断言 `restore_checkpoint` 后玩家位姿/灯/电荷复位 | 闭合 playtest Minor（`playtest-report.md:82`） |

**签名红线：** `restore_checkpoint()` 仍须 **零参**（`save_manager.gd:641-646`，FLAG-A(a) 锁定，测试 `test_save_manager.gd:365`/`test_patrol_ai.gd:449` 双侧断言）。本规格**不改其签名**，仅新增写入端与 ⑥ 应用消费者。

**交付后验收：** 真实软失败 → `restore_checkpoint` 非 no-op → `restored_state` 被 `CheckpointApplier` 应用 → 玩家回到最近检查点体积、其余守卫回巡逻、灯/电荷回到离开时态。至此 D1 双半环闭合。
