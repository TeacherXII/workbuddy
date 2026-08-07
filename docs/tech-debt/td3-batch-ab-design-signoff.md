# TD#3 — Batch A/B 三项遗留 CONCERN 设计签字（Design Sign-off）

- **签字人**：文策渊（design-strategist / 游戏策划负责人）
- **范围**：MEMORY 待办登记的三项 Batch A/B 遗留 CONCERN（prefs version-first 无守护 / set_event_bus 陷阱 / INSTANCE_CAP=16 需设计签字）
- **纪律**：本文件仅做「诊断 + 裁决 + 文档」，未改动任何 `.gd` 源码、未触碰 `.tmp_gut/`，未 git commit。所有裁定附代码证据（file:line）供主理人独立复验。

---

## ① prefs version-first 无守护

### CONCERN 原文
槽存档（slot）路径强制「version-first」不变式（`save_manager.gd:192` `encode_slot` 走 `SLOT_FIELD_ORDER` 保证 version 在磁盘首位；`read_slot` 先 `raw.has("version")`，没有即 CORRUPT）。关切点：PREFS（无障碍偏好 a11y / legacy a11y 迁移）的序列化读路径是否也强制同样的 version-first 门？还是能不经版本校验就解析/套用 prefs（schema-drift 守卫缺口）？

### 核查的代码路径与证据
- **槽的 version-first 门（对照基准）**
  - `save_manager.gd:192` `encode_slot` 走 `SLOT_FIELD_ORDER`（`version` 在索引 0）。
  - `save_manager.gd:304` `read_slot`：`if not raw.has("version")` → `_reject(... REASON_MISSING_VERSION)`；结构必须先过版本门才解析其余字段。
- **prefs 写路径（有 version，但仅写出）**
  - `save_manager.gd:738-751` `_write_prefs`：line 740 写 `out["version"] = SAVE_VERSION`（首位），line 750 `JSON.stringify(out, "", false)`（`sort_keys=false` 保序）。→ 写路径确实 version-first。
- **prefs 读路径（关键：无 version 校验门）**
  - `save_manager.gd:721-735` `_read_prefs_file`：
    - line 727-732 解析 `JSON.parse_string`，若 `not (parsed is Dictionary)` → `push_error` + `return {}`（rebuild from defaults，loud but recoverable）；
    - **line 734 `raw.erase("version")`** —— version 被当作 bookkeeping key 直接抹掉，**没有 `raw.has("version")` 校验，没有版本比对**。
  - 读路径在抹除 version 后按 key 直接返回 sections，**不依赖 version 在首位、不校验版本**。
- **legacy a11y 迁移（一次性，非版本门）**
  - `save_manager.gd:758-784` `_migrate_legacy_config_once`：仅将 Sprint 0 `a11y.cfg` 合入 prefs 后删除，属一次性迁移，不是每读必过的守卫。
- **字段级 schema-drift 吸收（prefs 的实际守卫）**
  - `a11y_settings.gd:320-337` `from_dict`：缺字段用当前默认值补全（line 326 `float(data.get("time_scale_user", _time_scale_user))`）；每个赋值走**校验/钳制属性**；
  - `a11y_settings.gd:199-202` `normalize_colorblind_mode`（未知值 → OFF）、line 206-209 `normalize_fog_option`（未知值 → FULL）；
  - `a11y_settings.gd:80-92` `CB_MODE_ALIASES`：新旧拼写（如 `DEUTERANO`/`DEUTAN`）统一回退到同一枚举 → 跨代偏好文件免迁移加载。
  - `a11y_settings.gd:350-354` `load()` → `_resolve_save_manager()` → `from_dict(sm.load_prefs(section))`。

### 裁定
**ACCEPTED-AS-DESIGN**（prefs 无需与 slot 同等的 version-first 硬门）

### 理由
prefs 与 slot 在结构本质不同，硬门对 prefs 既不必要也可由更轻的机制等价覆盖：

1. **prefs 可重建，slot 不可**。a11y 默认值随包发布且正确（`a11y_settings.gd:238-248` `default_values()`）。损坏/缺失的 prefs 文件由 `_read_prefs_file` 重建为默认（line 731），硬拒绝无收益且不会丢失玩家进度；而 slot 是玩家存档、不可重建，故须 reject-not-migrate（SAV-S6）。
2. **prefs 无位置/顺序依赖**。顶层是扁平 key-value，section 为不透明 dict（`save_manager.gd:691-697` SAV-S4 字段无关委托）。`_read_prefs_file` 直接 `erase("version")` 后按 key 返回（line 734），不依赖 version 在首位；等价的结构安全性已由「顶层非 Dictionary → 重建默认」（line 728-732）提供。
3. **schema-drift 在字段层被吸收**。每个 section 模型 `from_dict` 防御式解析 + 默认补全 + 钳制/校验属性 + alias 回退（`a11y_settings.gd:199-226`、`320-337`），版本漂移以字段粒度安全降级，而非整体损坏或需版本门拦截。

结论：prefs 的 version-first 守卫缺口不构成设计缺陷；顶层-Dictionary 校验 + 字段级默认/校验/alias 回退已覆盖 schema-drift。

### 前瞻备注（非阻塞）
`version` 字段仅写出（line 740）不读不校验。若未来 prefs 语义出现破坏性变更、且必须靠 version 区分，则需补门。当前设计以「字段级兼容 + 可重建」取代硬门，对可重建 prefs 属合理取舍。

---

## ② set_event_bus 陷阱

### CONCERN 原文
依赖注入 `set_event_bus(bus)` 广泛用于 `save_manager.gd:137` / `hud_slice.gd:219` / `patrol_ai.gd:153` / `save_slots_screen.gd:168` / `sound_propagation.gd:74`。多处注释声明「`_ready()` 与 `set_event_bus()` 可能任意序运行，二者皆幂等」。风险 = 若某消费者 `_ready` 里既存信号连接又用尚未注入的 bus，可能漏连/报错；或 `_ready` 与 `set_event_bus` 都做信号连接导致双连。

### 核查的代码路径与证据（逐消费者）
- **`save_manager.gd:137`** `set_event_bus` → 仅 `_bus = bus`，**不连任何入站信号**（发送侧）。发射经 `_emit_now`（`save_manager.gd:794`）→ `_resolve_bus()` 解析后 `callv("emit_signal", ...)`。无入站连接 → 无双连/漏连风险。**✓ 安全**
- **`hud_slice.gd:219`** `set_event_bus` → 存 bus + `_connect_bus()`（line 221）。`_connect_bus`（`224-241`）：null 守卫（line 225）；每条信号 `if not ...is_connected` 防双连（line 228/234/236/238/240）。`_ready`（line 205-213）亦经 `_connect_bus`（line 213）。两路径皆 `is_connected` 守卫 → 幂等、任意序安全。**✓ 安全**
- **`patrol_ai.gd:153`** `set_event_bus` → 存 bus + `_bind_bus()`（line 155）。`_bind_bus`（`158-165`）：null 守卫（line 159），`is_connected` 防双连（line 162/164）。`_ready`（`144-149`）不连 bus（只 `_register_with_sound` + `set_checkpoint_sink`）；set_event_bus 是唯一连 bus 点且 `is_connected` 守卫 → 任意序安全。**✓ 安全**
- **`save_slots_screen.gd:168`** `set_event_bus` → 存 bus + `_connect_bus()`（line 170）。`_connect_bus`（`246-254`）：null 守卫（line 247），`is_connected` 防双连（line 249/251/253）。`_ready`（line 156-162）亦经 `_connect_bus`（line 160）。**✓ 安全**
- **`sound_propagation.gd:74`** `set_event_bus` → **仅 `_bus = bus`，不调用 `_bind_bus`**。绑定只发生在 `_ready`（`68-71` → `_bind_bus()` line 71）。`_bind_bus`（`107-113`）有 `is_connected` 守卫，但**只有 `_ready` 触发它**。
  - **生产接线** `sprint0_bootstrap.gd:152-153`：`_sound.set_event_bus(_bus)` 先于 `add_child(_sound)` → `_ready` 用已注入 bus 连接 → 当前正常。
  - **风险**：若 `SoundPropagator` 改为场景挂载（`_ready` 先跑、bus 为 null → `_bind_bus` 空转）后经 `set_event_bus` 注入，则 bus 被存但**永不绑定** → `player_step_committed` / `decoy_landed` 永不达 `SoundPropagator` → 脚步/诱饵声静默失效（E06-S2/S4）。这正是「漏连」。此路径**违背了** `hud_slice.gd:227` / `patrol_ai.gd:161` / `save_slots_screen.gd:245` 注释所声明的「`_ready` 与 `set_event_bus` 任意序皆可」项目不变量。
  - （旁证：`vision_cone.gd:83` 的 `set_event_bus` 同样仅存 bus、靠 `_ready` bind，属本项目同款 idiom；但本次签字范围限定上述 5 个消费者。）

### 裁定
**NEEDS-CHANGE**（仅 `sound_propagation` 一项；其余 4 项 ACCEPTED-AS-DESIGN）

### 理由
5 个消费者中 4 个（`save_manager` 发送侧、`hud_slice`、`patrol_ai`、`save_slots_screen`）均通过 `is_connected` 守卫 + 双路径 bind 实现任意序幂等，与项目既定不变量一致。唯 `sound_propagation.gd:74` 的 `set_event_bus` 仅存 bus、不 bind，使其无法在「`set_event_bus` 晚于 `_ready`」时建立连接，与既定不变量不一致，存在真实漏连风险——当前仅因 `sprint0_bootstrap.gd:152-153` 严格保持「先 `set_event_bus` 后 `add_child`」而幸免，属顺序脆弱依赖。该脆弱性是此 CONCERN 被登记为待办所针对的「陷阱」。

---

## ③ INSTANCE_CAP=16

### CONCERN 原文
`src/game/interactables/interactable_registry.gd:48`：`const INSTANCE_CAP := 16`，注释称取自 R-02 实时光(≤12 MVP) 与 G-02 声环(≤8)。CI 守卫 `tests/unit/test_interactables.gd:531` 断言 `INSTANCE_CAP <= BudgetChecks.LIGHT_BUDGET_TIER2`；`:540-545` 反断言「超出即 WARN、恰好等于合法」。请核对 16 与 G-01（守卫 ≤8/16 预算）一致、与 R-02/G-02 推导自洽，并确认注释里的预算数字与控制清单/架构文档一致。

### 核查的代码路径与证据
- **源码与注释**：`interactable_registry.gd:48` `const INSTANCE_CAP := 16`；注释（line 43-47）称源自 R-02 实时光(≤12 MVP) 与 G-02 声环(≤8)，留 BLOCK-only 余量。
- **控制清单（权威）** `docs/architecture/control-manifest.md`：
  - line 19 R-02 动态点光同屏 **MVP ≤12 / Tier2 ≤32**；
  - line 86 G-01 同区活动守卫 **MVP ≤8 / Tier2 ≤16**；
  - line 87 G-02 同屏声环 VFX **≤8**。
- **架构文档** `docs/architecture/architecture.md`：line 21/144/147 守卫上限 MVP 8 / Tier2 16；line 147 明确「Tier2 守卫 16 逼近动态光 32 上限」。
- **CI 守卫** `tests/ci/budget_checks.gd`：line 57 `LIGHT_BUDGET_TIER2 := 32`；`_check_interactable_instance_cap`（line 355-383）line 363 `if cap > LIGHT_BUDGET_TIER2` → warn → `16 ≤ 32` 通过。注释 line 350-351：R-02 ≤12 MVP / ≤32 Tier2、G-02 ≤8。
- **测试** `tests/unit/test_interactables.gd`：line 531 `assert_lte(INSTANCE_CAP, LIGHT_BUDGET_TIER2)`（16 ≤ 32）；line 540-545 反断言 `16+1`→WARN、`16`→合法。

### 裁定
**ACCEPTED-AS-DESIGN**（数字全部自洽、无漂移）

### 理由
- `16 == G-01 Tier2 (≤16)`（`control-manifest.md:86`）—— 注释虽未点名 G-01，但 16 恰等于同区活动守卫 Tier2 上限，为实际贴合的约束。✓
- CI 守卫 `16 ≤ LIGHT_BUDGET_TIER2(32)` 与 R-02 Tier2 一致；反断言 16 合法 / 17 警告正确。✓
- G-02(≤8) 为独立运行时守卫（`test_sound_propagation.gd` 持有），不应与实例上限相等；`16 > 8` 属预期。✓
- 与 `architecture.md:147`「Tier2 守卫 16 逼近动态光 32 上限」一致。

结论：`INSTANCE_CAP=16` 与 G-01 Tier2、R-02 Tier2、G-02 全部自洽；CI 守卫与测试通过；注释所引预算数字（R-02 ≤12 MVP、G-02 ≤8）与 `control-manifest.md` 一致，无数字漂移。

### 非阻塞备注（纯文档清晰度，不阻塞）
`interactable_registry.gd:45` 注释将 16 的推导归为「R-02 ≤12 MVP 与 G-02 ≤8」，但两者均 < 16，推导叙述略含糊（真实贴合约束是 G-01 Tier2 ≤16）。建议补一句点名 G-01，非缺陷。

---

## Backlog 登记结论

| 项 | CONCERN | 裁定 | 待办状态转移 |
|---|---|---|---|
| ① | prefs version-first 无守护 | ACCEPTED-AS-DESIGN | 待办 → **关闭**（无需改码） |
| ② | set_event_bus 陷阱 | NEEDS-CHANGE（仅 `sound_propagation`；其余 4 项 ACCEPTED-AS-DESIGN） | 待办 → **路由 engineering-lead（程基岩）返工**；`sound_propagation` 关闭后整体关闭 |
| ③ | INSTANCE_CAP=16 | ACCEPTED-AS-DESIGN | 待办 → **关闭**（附非阻塞文档建议） |

---

## 返工规格（交程基岩）

> 仅 TD#3-② 触发。签字人未改动源码。

**文件**：`src/game/sound_propagation.gd`
**位置**：`set_event_bus`（line 74-76）

**当前代码**：
```gdscript
func set_event_bus(bus: EventBus) -> void:
	_bus = bus
```

**改为**：
```gdscript
func set_event_bus(bus: EventBus) -> void:
	_bus = bus
	_bind_bus()
```

**理由**：使 `set_event_bus` 与 `hud_slice`/`patrol_ai`/`save_slots_screen` 同构，满足「`_ready` 与 `set_event_bus` 任意序皆可」的项目不变量。`_bind_bus`（`sound_propagation.gd:107-113`）已用 `is_connected` 守卫，添加后**不引入双连**；关闭「`set_event_bus` 晚于 `_ready`」时的漏连（脚步/诱饵声静默失效 E06-S2/S4）风险。

**影响面 / 零破坏确认**：
- 仅 `SoundPropagator` 一文件。
- 生产接线 `sprint0_bootstrap.gd:152-153`（先 `set_event_bus` 后 `add_child`，`_ready` 再 bind 一次）行为不变——`is_connected` 去重。
- 测试 `test_sound_propagation.gd:36` / `test_interactables.gd:129` 等已显式 `_bind_bus`，行为不变。
