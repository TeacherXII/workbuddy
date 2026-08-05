# Epic E11 · 存档与设置持久化（SaveManager）

- **对应 GDD**：`design/gdd/systems/save-system.md`（存档/读档系统，Phase 2 八节 GDD）★ 数值与接口的**单一真相源**
- **层**：L2 基础设施 / 服务层（架构 §2 · §3.2 L2 服务：SaveManager · §6 数据落地）
- **依赖**：E01（EventBus / InputManager / A11ySettings 接口）
- **DAG 优先级**：P1（存档基座，先于 E09 偏好持久化 / E08 检查点重生 / E07 charges 持久化）
- **MoSCoW**：**Must** ｜ **T 恤**：M
- **状态**：**正式新立（主理人裁决 2，已从 E01 剥离）**。原 `E01-S5`「SaveManager 完整层」职责整体迁入本 epic 的 SAV-S1~S6；E01 保留 SaveManager **接口**声明与其余 L2 服务。`E01-S8` NavServer 不受影响（仍归 E01，仍为 seam 占位）。
- **排期**：**Sprint 2 = 数据层**（SAV-S1/S2/S3/S4/S6）｜**Sprint 3 = 手动存档/读档 UI**（SAV-S5，主理人裁决 1 滑期）
- **上游**：`save-system.md` 全节；architecture §3.2/§6；consistency-review C4（检查点粒度，已由本 epic 落位）；control-manifest §7（本 epic 新增体积/版本 WARN-ONLY 断言）；`production/sprints/sprint2-stories.md` §1 Batch A / §5 FLAG-A。

## 目标
把 Sprint 1 的 D9-seam 占位（`GuardBrain._checkpoint_sink` 零参 no-op，内存态 last-checkpoint pose，无磁盘持久化/无版本化/无手动存档）升级为**真实 L2 持久化层**：

1. **检查点自动持久化** —— 软失败时从最近检查点恢复，支撑「暴露 = 软失败 → 重规划」核心循环（⑥ 发 `exposure_detected` → `SaveManager.restore_checkpoint`）。服务**支柱一 步步为营**（失误 = 重新规划机会）。
2. **手动存档/读档** —— 玩家自选槽写入/读取，服务**支柱三 自主掌控**（Own 自己的进度与节奏）。**UI 部分 Sprint 3 交付**。
3. **偏好持久化** —— 代理 `A11ySettings` 等玩家偏好落盘，是 E09 a11y 完整包的落地基座。

## 范围（In Scope）

### Sprint 2（数据层）
- **数据模型 + 版本化**：`SaveSlot`（GDD §3 逐字）；`version` 字段**前置**且恒等 `SAVE_VERSION = 2`；JSON 落 `SAVE_DIR = user://saves/slot_{id}.json`。只存「世界差异态」（灯 / 道具 charges / 守卫态 / 玩家位姿），静态关卡几何不存。
- **两类槽**：检查点滚动单槽（`CHECKPOINT_SLOT_ID = -1`，玩家不手动操作，进入检查点区静默写入）+ 手动槽（`0..MAX_MANUAL_SLOTS-1`，`MAX_MANUAL_SLOTS = 3`）。`write_slot` / `read_slot` 数据层 API 在 Sprint 2 完整落地（含手动槽读写路径）。
- **检查点恢复**：`restore_checkpoint()` 注入 ⑥ `patrol_ai._checkpoint_sink`（D9 seam，**仅改 1 行**）；还原玩家位姿 + 可疑度清零 + 守卫回 `RETURN`/巡逻 + 灯/道具差异态。
- **偏好委托**：`save_prefs(section, data)` / `load_prefs(section)` 落 `PREFS_PATH = user://prefs.json`；`A11ySettings` 不再直接 `ConfigFile`；首次启动**一次性迁移** `user://a11y.cfg` 后删除旧文件。**API 字段无关**（通用 `String → Dictionary`），以便音量/画质等同机制扩展。
- **异步落盘**：写盘不阻塞主线程，`write_slot` 立即返回、完成发 `save_completed`；检查点写入限频 `CHECKPOINT_WRITE_COOLDOWN ≥ 0.5s`。
- **版本/损坏处理**：`version != SAVE_VERSION` 或 JSON 解析失败 → **拒绝 + 标记损坏 + UI 提示**，绝不静默吞错、绝不覆盖写回。Sprint 1 minimal 无磁盘数据，故**存档槽无迁移负担**（v1 视为不兼容态，发现即忽略重建）。

### Sprint 3（表现层，已滑期）
- 手动存档/读档 UI：暂停菜单槽列表（时间戳 / 检查点 id / 缩略占位）、覆盖确认、删除入口、读档 0.4s 淡入。

### Out of Scope
- 云同步 / 自动备份 / 存档缩略图 / 损坏自动修复向导（GDD §8 Tier2，滑后）。
- 「最干净通关」记录持久化（GDD §8 Tier3，复用槽结构，不新增系统）。
- 不破坏 Sprint 1 minimal 已满足的 C4；不在玩法 tick 内做同步 IO。

## 数据模型（GDD §3，工程侧不另立）
```gdscript
const SAVE_VERSION: int = 2
const CHECKPOINT_SLOT_ID: int = -1
const MAX_MANUAL_SLOTS: int = 3
const SAVE_DIR: String = "user://saves/"
const PREFS_PATH: String = "user://prefs.json"
# CHECKPOINT_WRITE_COOLDOWN >= 0.5s（GDD §6）· 单槽 JSON <= 32KB（GDD §6）

# SaveSlot（存于 user://saves/slot_{id}.json）
#   version:int(前置) · slot_id:int · is_checkpoint:bool · timestamp:float
#   checkpoint_id:String · player_pose:Dictionary · suspicion:Dictionary[int,float]
#   guard_states:Dictionary[int,GuardState] · interactable_charges:Dictionary[int,int]
#   light_states:Dictionary[int,bool] · a11y_prefs:Dictionary

# SaveManager（L2 单例）
#   write_slot(id, data) · read_slot(id) -> SaveSlot
#   save_prefs(section, data) · load_prefs(section) -> Dictionary
#   restore_checkpoint()  # D9 seam 目标 · has_checkpoint() -> bool
```

## 关键 Story 列表（详 `sprint2-stories.md` §1 Batch A）

### SAV-S1 · 存档数据模型 + `SAVE_VERSION` 版本字段前置
**Sprint 2**：是 ｜ **T 恤**：M
**验收**
- Given `SaveSlot` 含 GDD §3 全字段；常量 `SAVE_VERSION=2` / `CHECKPOINT_SLOT_ID=-1` / `MAX_MANUAL_SLOTS=3` / `SAVE_DIR` / `PREFS_PATH`。
- When 定义结构并序列化（JSON → `user://saves/slot_{id}.json`）。
- Then `version` 为写入的**第一个字段**且恒等 2，所有读取路径**先读版本再解析其余**（FLAG-A 缓解①）；序列化/反序列化可逆；只存世界差异态。
**退出钩子**：`@test_save_slot_roundtrip` · `@ci:save-schema-has-version`
**关联**：save-system §2/§3；architecture §3.2/§6。

### SAV-S2 · `write_slot` / `read_slot` 数据层 API（异步落盘 + 写冷却）
**Sprint 2**：是 ｜ **T 恤**：M
**验收**
- Given 检查点滚动槽（`-1`，静默写入）+ 手动槽（`0..2`）。
- When 进入检查点区触发静默写入 / 上层调 `write_slot` `read_slot`。
- Then 写盘**异步不阻塞主线程**，立即返回、完成发 `save_completed(slot_id, success)`；检查点写入限频 `≥0.5s`；单槽 ≤32KB（WARN-ONLY）；读取发 `load_completed(slot_id, success)`。
**退出钩子**：`@test_write_read_slot_roundtrip` · `@test_checkpoint_write_cooldown_0_5s` · `@ci:save-size-budget`
**关联**：save-system §2/§3/§6；E01-S9（新事件词汇收口，见 FLAG-I）。

### SAV-S3 · `restore_checkpoint()` + D9 seam 注入 ★**FLAG-A 高风险**
**Sprint 2**：是 ｜ **T 恤**：M
**验收**
- Given `GuardBrain._checkpoint_sink: Callable` 现为**零参** no-op（`patrol_ai.gd:119` 声明 / `:174` 注入口 / `:366-371` `.call()`）；GDD §4 定注入 `SaveManager.restore_checkpoint`，**仅改 1 行**。
- When 软失败触发（`GRACE_RT=1.2s` 真实时间达）→ E08-S4 调 `_checkpoint_sink.call()`。
- Then 还原玩家位姿 + 可疑度清零 + 守卫回 `RETURN`/巡逻 + 灯/道具差异态；发 `checkpoint_restored(checkpoint_id)` → ⑥/⑧（世界重置 / 软重开 UI）。
- Then **★ arity 契约测试**：断言注入 sink 实参个数 == `restore_checkpoint` 形参个数。基线口径 = GDD 的**零参**；若扩为 `(checkpoint_data: Dictionary)`，`test_patrol_ai.gd:413` 必须**同批同步改**，禁止单边漂移（batchd R7 / 同类 N-8）。签名须在开工前定稿（FLAG-A OPEN）。
**退出钩子**：`@test_checkpoint_sink_arity_contract` · `@test_restore_resets_suspicion_and_guards`
**关联**：save-system §2/§4；patrol-ai §2；consistency-review C4；E09-S6。

### SAV-S4 · 偏好委托 `save_prefs`/`load_prefs` + `a11y.cfg` 一次性迁移
**Sprint 2**：是 ｜ **T 恤**：S
**验收**
- Given `A11ySettings` 现直接 `ConfigFile` 落 `user://a11y.cfg`；GDD 要求改为委托落 `user://prefs.json`。
- When 设置变更（即时）或首次启动。
- Then 经 `save_prefs("a11y", dict)` / `load_prefs("a11y")` 落盘读盘；首次启动**一次性迁移**旧 `a11y.cfg`（若存在）后删除；缺字段默认补全。
- Then **API 必须字段无关**（不硬编码 a11y 字段名），否则与 E09-S7 构成循环依赖（FLAG-J 解环约束）。
**退出钩子**：`@test_prefs_delegation_roundtrip` · `@test_legacy_a11y_cfg_migrated_once`
**关联**：save-system §2/§3；a11y_settings.gd；E09-S7。

### SAV-S5 · 手动存档/读档 UI（槽列表 / 覆盖确认 / 删除入口）
**Sprint 2**：**否 —— 滑 Sprint 3**（主理人裁决 1；对应设计 `sprint2-design-scope.md` §7 FLAG-2）｜ **T 恤**：M
**滑期理由**：便利功能，非软失败核心循环必需；其**全部数据层已在 Sprint 2 交付**（`write_slot`/`read_slot`/3 槽上限/体积门），S3 为纯表现层增量，不回头改 L2。
**Sprint 3 验收（预置）**
- Given 暂停菜单「存档 / 读档 / 删除」入口；槽列表显示时间戳 / 检查点 id / 缩略（占位）。
- When 玩家存档 / 读档 / 覆盖非空槽。
- Then 非空槽二次确认；UI 反馈成功/失败（成功 = 单声低音「嗒」，失败 = 闷响 + ⚠）；读档后 0.4s 淡入；正文 ≥4.5:1（C-01）/ 关键指示 ≥7:1（C-02）/ 焦点环 `#C8862F`（C-06）/ 读档完成字幕（X-02）/ 无 >3Hz 频闪（V-01）。
**⚠️ 追溯**：GDD §8 将手动存档槽列为 **Tier1**；本次为对 Tier1 的**有意延后**，建议 GDD §8 同步注记（`sprint2-stories.md` §5 FLAG-K）。
**关联**：save-system §5/§7/§8；core-hud-a11y §2。

### SAV-S6 · 版本拒绝 + 损坏处理（绝不静默吞错）
**Sprint 2**：是 ｜ **T 恤**：S
**验收**
- Given Sprint 1 minimal 无磁盘数据 → **存档槽无迁移负担**（v1 视为不兼容态，发现即忽略重建，**不做 v0→v1 迁移**）。
- When 读入 `version != SAVE_VERSION` 的槽，或 JSON 解析失败。
- Then **拒绝并标记损坏**，`load_completed(slot_id, false)`，UI 提示「存档版本不匹配」；不崩溃、不静默吞错、不覆盖写回。
- Note 唯一真实迁移路径 `a11y.cfg → prefs.json` 归 SAV-S4。
**退出钩子**：`@test_version_mismatch_rejected_not_crash` · `@test_corrupt_json_rejected_not_swallowed`
**关联**：save-system §2/§6。

## 依赖
**依赖**：E01（EventBus / InputManager / A11ySettings 接口）；L2 FileAccess/JSON；⑤ 灯状态查询、⑦ 道具 charges 查询、⑥ 守卫态查询、② 玩家位姿（读取快照源）。
**发出（新增事件词汇，须经 E01-S9 收口 —— 见 FLAG-I）**：
- `save_completed(slot_id: int, success: bool)` → ⑧（吐司/错误提示）
- `load_completed(slot_id: int, success: bool)` → ⑧（读档完成回调）
- `checkpoint_restored(checkpoint_id: String)` → ⑥/⑧（世界重置 / 软重开 UI）

**被依赖**：E08（检查点重生 C4，D9 seam 注入）、E09（偏好持久化 SAV-S4 + E09-S7；软重开 UI E09-S6）、E07（`interactable_charges` 持久化）。

## 整 Epic 验收标准
1. `SaveSlot` 含**前置** `version = SAVE_VERSION(2)`；序列化/反序列化可逆；只存世界差异态。
2. `write_slot`/`read_slot` 往返可逆；检查点滚动槽静默写入且限频 ≥0.5s；写盘异步不阻塞主线程。
3. `restore_checkpoint` 注入 D9 seam（仅改 1 行）并还原玩家 + 守卫状态（C4）；**arity 契约测试通过**，两侧签名零漂移。
4. 偏好委托 `save_prefs`/`load_prefs` 生效；`a11y.cfg` 一次性迁移后删除；API 字段无关。
5. 版本不匹配 / JSON 损坏 → 拒绝 + 标记 + UI 提示，不崩溃不吞错。
6. 单槽 ≤32KB（WARN-ONLY）；新增预算断言一律 WARN-ONLY，绝不发裸 `[Risky]`（N-7 门纪律）。
7. **（Sprint 3）** 手动存档/读档 UI 可用，覆盖确认 + 对比度 + 字幕达标。

## 风险
- **R-SAV-1（=FLAG-A ①）**：版本字段若后置/缺失 → 异版档读入崩溃。**缓解**：SAV-S1 版本前置 + 先读版本再解析 + `@ci:save-schema-has-version` + SAV-S6 拒绝路径测试。
- **R-SAV-2（=FLAG-A ②）**：`_checkpoint_sink` 两侧 arity 单边漂移 → GuardBrain 调用崩溃（batchd R7）。**缓解**：SAV-S3 双向 arity 契约测试；GDD 口径为零参「仅改 1 行」，扩参与否须开工前定稿。
- **R-SAV-3**：单槽无限增长（全量快照）→ 破 32KB 体积预算。**缓解**：只存世界差异态（GDD §3）+ `@ci:save-size-budget` + `MAX_MANUAL_SLOTS=3` 上限。
- **R-SAV-4**：同步 IO 落在玩法 tick 内 → 卡帧。**缓解**：SAV-S2 异步落盘 + 检查点写冷却 ≥0.5s；测试用信号 `await` 而非固定 sleep。
- **R-SAV-5**：偏好 API 若硬编码 a11y 字段 → 与 E09-S7 循环依赖，Batch A 无法独立收口。**缓解**：SAV-S4 字段无关约束（FLAG-J 已解环）。

## 与架构 + 控制清单勾稽
- 架构 §2（L2 服务层，L3/L5 经事件与 Callable 单向依赖，不反向耦合）、§3.2（SaveManager）、§6（数据落地）。
- ADR-002（事件驱动；3 个新信号经 E01-S9 收口，`event_bus.gd` 与 `system-breakdown.md` §2 逐字一致）；落盘异步，不在玩法 tick 内同步 IO。
- control-manifest §7：本 epic 新增 `save-size-budget`(≤32KB) / `save-schema-has-version`，**均 WARN-ONLY，不触发 N-7 门**；N-7 正则 `\[Risky\]:|\[Pending\]:|\[Risky\] Script was skipped` 不变。
- consistency-review **C4 已由本 epic 落位**（检查点滚动槽 + `restore_checkpoint` 注入 D9 seam），由 CONCERN 转「已解决」。
- a11y（GDD §7）：偏好即 a11y 基座；存档 UI 对比度 C-01/C-02、焦点环 C-06、字幕 X-02、无频闪 V-01（随 SAV-S5 在 S3 卡门）。
- 关联：`production/sprints/sprint2-stories.md` §1 Batch A / §5 FLAG-A · FLAG-H · FLAG-I · FLAG-J · FLAG-K。

*E11 v1.0 — 正式 epic（主理人裁决 2 新立）。Sprint 2 交数据层（SAV-S1/S2/S3/S4/S6），Sprint 3 交 UI（SAV-S5）。*
