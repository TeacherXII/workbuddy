# 系统 GDD · 存档/读档系统（save-system / SaveManager）
**Phase 2 · 八节 GDD · 优先级 P2（L2 持久化服务，Sprint 2 完整层）**

> 上游：`design/concept/game-concept.md` §5（存档/读档 为 Tier1 显式要求）；`docs/architecture/architecture.md` §3.2（L2 服务层：SaveManager）、§6（数据落地）；`docs/architecture/control-manifest.md` §7（CI 断言 N-7 等）；**`production/epics/E11-save-manager.md`（E11 SaveManager — 主理人裁决自 E01-S5 剥离为独立 epic；story 编号 `SAV-S1~S6`，S2 交 SAV-S1/S2/S3/S4/S6、S3 交 SAV-S5）**；`src/game/patrol_ai.gd`（D9 seam：`_checkpoint_sink`）。
> 前驱：Sprint 1 **minimal** SaveManager 仅满足 C4（检查点重生，内存态 last-checkpoint pose，无磁盘持久化、无版本化、无手动存档）。本 GDD 将其升级为完整 L2 持久化层。

---

## 1. 系统目标与支柱对齐
- **目标**：提供统一的 L2 持久化层——（a）**检查点自动持久化**：软失败时从最近检查点恢复，支撑「暴露=软失败→重规划」核心循环（⑥ 发 `exposure_detected` → SaveManager.restore_checkpoint）；(b) **手动存档/读档**：暂停菜单写入/读取玩家选择的槽位，承载自主掌控；(c) **偏好持久化**：代理 A11ySettings 等玩家偏好（色盲、时间缩放等）落盘。
- **支柱对齐**：
  - 支柱一 **步步为营**：软失败可恢复、检查点密度可调，失误即「重新规划机会」（概念 §3 Dynamics）。
  - 支柱三 **自主掌控**：手动存档让玩家 Own 自己的进度与节奏。
- **为何存在**：Sprint 1 minimal 仅够 C4 重生；完整存档/读档 UI 与偏好持久化是概念 Tier1 显式要求，且是 ⑥ 软失败恢复、⑧ 设置菜单、E09 a11y 偏好的落地基座。

## 2. 核心机制与规则
- **两类存档**：
  1. **检查点（Checkpoint）**：滚动单槽（逻辑 id `CHECKPOINT_SLOT_ID = -1`）。玩家进入关卡检查点区（或触发 `#checkpoint` 锚点）即静默写入最新快照；软失败时 `restore_checkpoint()` 还原此快照，可疑度清零、守卫回 `RETURN`/巡逻（世界部分重置）。**玩家不手动操作**。
  2. **手动存档（Manual）**：暂停菜单「存档」写入玩家选定槽（id `0..MAX_MANUAL_SLOTS-1`，`MAX_MANUAL_SLOTS = 3`）；「读档」还原任意手动槽。含覆盖确认（同名/非空槽二次确认）。
- **版本化**：`SAVE_VERSION = 2`（Sprint 1 minimal 视为 v1 不兼容态，启动时若发现 v1 直接忽略并重建，不迁移——minimal 无磁盘数据，故无迁移负担）。读取时 `slot.version != SAVE_VERSION` → 拒绝并标记损坏（UI 提示「存档版本不匹配」）。
- **偏好委托**：`A11ySettings` 不再直接 `ConfigFile`，改为调用 `SaveManager.save_prefs("a11y", dict)` / `load_prefs("a11y") -> Dictionary`；首次启动一次性迁移既有 `user://a11y.cfg`（若存在）入偏好库后删除旧文件。其他 L2 偏好（音量、画质预设）同机制扩展。
- **异步落盘**：写盘走 `ResourceLoader`/`Thread` 异步或 `await` 分帧，避免卡帧（§6 预算）。

## 3. 数据模型与状态
```gdscript
const SAVE_VERSION: int = 2
const CHECKPOINT_SLOT_ID: int = -1
const MAX_MANUAL_SLOTS: int = 3
const SAVE_DIR: String = "user://saves/"
const PREFS_PATH: String = "user://prefs.json"

struct SaveSlot:                       # 存于 user://saves/slot_{id}.json
    var version: int = SAVE_VERSION
    var slot_id: int                   # -1=检查点, 0..2=手动
    var is_checkpoint: bool
    var timestamp: float               # Time.get_unix_time_from_system()
    var checkpoint_id: String          # 逻辑检查点键（软失败恢复定位）
    var player_pose: Dictionary        # {pos:Vector3, facing:float, gait:Gait}
    var suspicion: Dictionary[int, float]      # guard_id -> S（手动存档连续性）
    var guard_states: Dictionary[int, GuardState]   # guard_id -> 状态枚举
    var interactable_charges: Dictionary[int, int]  # entity_id -> 剩余 charges
    var light_states: Dictionary[int, bool]         # light_id -> lit?
    var a11y_prefs: Dictionary         # 委托自 A11ySettings（冗余镜像，便于单槽携带）

class SaveManager:                    # L2 单例
    var _slots: Dictionary[int, SaveSlot]
    func write_slot(id: int, data: Dictionary) -> void
    func read_slot(id: int) -> SaveSlot
    func save_prefs(section: String, data: Dictionary) -> void
    func load_prefs(section: String) -> Dictionary
    func restore_checkpoint() -> void          # D9 seam 目标
    func has_checkpoint() -> bool
```
- 检查点快照只存「世界差异态」（灯/道具 charges/守卫态/玩家位姿），静态关卡几何不存。
- 手动槽额外存 `suspicion`/`guard_states` 以实现「任意时刻冻结世界」的读档体验。

## 4. 与其他系统的接口
- **依赖**：L2 EventBus（发事件）、L2 FileAccess/ConfigFile（落盘）、⑤ 灯状态查询、⑦ 道具 charges 查询、⑥ 守卫态查询、② 玩家位姿。
- **发出（新增词汇，见 `system-breakdown.md` §2 + `consistency-review.md` §5）**：
  - `save_completed(slot_id: int, success: bool)` → ⑧（吐司/错误提示）
  - `load_completed(slot_id: int, success: bool)` → ⑧（读档完成回调）
  - `checkpoint_restored(checkpoint_id: String)` → ⑥/⑧（触发世界重置/软重开 UI）
- **被依赖（关键衔接）**：
  - ⑥ `patrol_ai.gd` 的 D9 seam：`_checkpoint_sink: Callable`（`set_checkpoint_sink(sink)` 第 174 行）——Sprint 2 注入 `SaveManager.restore_checkpoint`，**仅改 1 行**。软失败时 ⑥ 调 `_checkpoint_sink.call()`，由 SaveManager 还原。
  - ⑧ 设置菜单「存档/读档」按钮 → 调 `write_slot`/`read_slot`。
  - `A11ySettings` → `save_prefs`/`load_prefs`。
- **联动 ADR**：事件驱动（ADR-002）；落盘异步，不在玩法 tick 内同步 IO。

## 5. 玩家交互与反馈
- **检查点**：进入检查点区有低饱和微光环 + 轻「咔」foley（diegetic，不弹窗）；软失败恢复有 0.6s 黑场 + 「在灰烬中重燃」字幕（肃穆，非惩罚感）。
- **手动存档/读档 UI**（暂停菜单，⑧ 管辖）：槽列表显示时间戳/检查点 id/缩略（占位）；覆盖确认弹窗；读档后 0.4s 淡入。
- **偏好**：设置菜单即时生效并落盘（调 `save_prefs`），下次启动自动 `load_prefs`。
- **Sensation（克制）**：存档成功 = 单声低音「嗒」（非庆祝音）；失败 = 闷响 + 红色 ⚠（C-02 ≥7:1）。

## 6. 边界与性能约束
- **落盘异步**：写盘不阻塞主线程；`write_slot` 立即返回，完成发 `save_completed`（§4）。检查点写入限频（`CHECKPOINT_WRITE_COOLDOWN ≥ 0.5s`），避免同区每帧写。
- **体积**：单槽 JSON ≤ 32KB（仅差异态）；`MAX_MANUAL_SLOTS=3` 上限防失控。
- **版本/损坏**：`version` 不匹配或 JSON 解析失败 → 拒绝 + UI 标记，绝不静默吞错。
- **CI 断言（control-manifest §7，N-7）**：Orphans 23（工程报数）**不参与 N-7 门**（见 `batchd-qa-plan.md`）；本系统单测覆盖 `write→read` 往返、版本拒绝、prefs 委托。
- **架构联动**：`architecture.md` §3.2（L2 服务）、§6（数据落地）；不直接触引擎底层（经 L2/事件）。

## 7. 可访问性考量
- **偏好即 a11y 基座**：色盲模式、时间缩放、字幕等经 `save_prefs` 持久化，跨会话保留（X-02/T-01/C-05 体验连续）。
- **UI 对比度**：存档/读档界面正文 ≥4.5:1（**C-01**）、关键指示 ≥7:1（**C-02**）；焦点环 `#C8862F` 细描边（色盲安全，**C-06**）。
- **字幕**：检查点恢复/读档完成带字幕（**X-02**），说话者=「世界/系统」。
- **无频闪**：存档成功反馈无 >3Hz 频闪（**V-01**）。

## 8. 范围分层归属
> **裁决更新（Sprint 2 收口）**：本系统独立为 **epic E11**；**Sprint 2 只交数据层**，手动存档/读档 **UI** 滑 Sprint 3（scope §7.2 FLAG-2 RESOLVED）。
>
> **⚠️ Tier1 口径注记（FLAG-K 闭环，锁库前追加）**：**「手动存档 UI」滑 Sprint 3，「存档数据层」Sprint 2 交付。**
> 本系统在 `game-concept.md` §5 中属 **Tier1 必做**，该定级**不变**——滑期的**只是 UI 呈现层**，不是能力本身。为消除「GDD Tier1 ↔ 排期」双真相源，此处明确拆分口径：
>
> | 层 | 内容 | Sprint | 状态 |
> | --- | --- | --- | --- |
> | **数据层**（Tier1a） | `write_slot` / `read_slot`（含手动槽 `0..2` 完整读写路径与磁盘格式）· 检查点滚动槽 · `restore_checkpoint` · 偏好委托 · `SAVE_VERSION` 版本化 · 异步落盘 · 3 事件广播 | **Sprint 2** | 必交（`sprint2-stories.md` §3 退出标准 2） |
> | **UI 层**（Tier1b） | 暂停菜单槽列表 · 覆盖确认弹窗 · 缩略图占位 · 版本不匹配/损坏的 ⑧ 视觉提示 | **Sprint 3** | 有意延后（`sprint2-stories.md` §2 S3-B / `SAV-S5`） |
>
> **为何可安全延后**：数据层在 S2 已完整落地（含手动槽读写 API 与 `success:false` 返回），S3 的 `SAV-S5` 是**纯表现层增量，不回头改 L2**。故 Tier1 能力的**技术风险已在 S2 消解**，S3 仅补玩家可见入口。
> **排期真相源**：`production/sprints/sprint2-stories.md`（S2 范围）与 `sprint3-stories.md`（S3 滑期项，待建）；本 GDD 只定义能力与分层，不再另立排期口径。

- **Tier1a（Sprint 2 必做 · 数据层）**：检查点自动持久化 + `restore_checkpoint` 注入 ⑥（D9 seam）+ 偏好委托 A11ySettings + `SAVE_VERSION` 版本化 + **手动槽 `0..2` 的 `write_slot`/`read_slot` API 与磁盘格式** + 异步落盘 + 3 事件广播（`save_completed`/`load_completed`/`checkpoint_restored`，D16 已入权威词汇表）。
- **Tier1b（滑 Sprint 3 · UI 层）**：暂停菜单槽列表、**覆盖确认弹窗**、缩略图占位、版本不匹配/损坏的 ⑧ 视觉提示。数据层已在 S2 给出 `success:false`，S3 仅接呈现。
- **Tier2（期望，滑 Sprint 3+）**：多槽云同步/自动备份、存档缩略图（实图）、损坏自动修复向导。
- **Tier3（拓展）**：「最干净通关」记录持久化（复用槽结构）；均复用，不新增系统。
- **范围纪律**：本系统是概念 §5「存档/读档」Tier1 的落地，属既有 L2 服务补全，**未新增平行机制族**；E08 守卫变体、E07 道具均为其数据消费者，非新系统。
