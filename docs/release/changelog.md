# Changelog · ASHEN STEP《灰烬之步》Phase 7 — 内部封闭 alpha v0.1.0-alpha.1

**发布区间：** `24fc2ef` → `5cf0431`
**版本：** `0.1.0-alpha.1`（内部封闭 alpha，仅 zh-CN，GitHub Release 分发）
**引擎：** Godot 4.4.1-stable
**评审：** solo（GHA runner 宕机；本地 Godot 验证为权威）
**changelog 依据：** 本文件全部条目均来自真实 `git log 24fc2ef..5cf0431`，**无任何编造 commit 或功能**。

---

## 0.1.0-alpha.3

**发布区间：** `211ba0e` → `v0.1.0-alpha.3`（本次仅构建/发布流程变更，游戏逻辑零改动）
**版本：** `0.1.0-alpha.3`（内部封闭 alpha，仅 zh-CN，GitHub Release 分发）
**引擎：** Godot 4.4.1-stable
**评审：** solo（GHA runner 宕机；本地 Godot 验证为权威）
**changelog 依据：** 本小节记录构建/发布流程变更，**无 gameplay commit、无编造功能**。

### Build
- 采用**物理排除法**彻底剔除此前泄露的 dev-only 资产：导出时把 `tests/`、`addons/gut/`、`docs/`、`tools/`、`.workbuddy/` 排除在导出源之外（对仓库工作树零侵入），导出后清理临时导出源。
- 根因：Godot 4.4.1 headless `--export-release` 下，`export_filter="all_resources"` 时 `include_filter` 被忽略（选择来自编辑器 dock，headless 无），`exclude_filter` 仅能剔除非资源目录，管不到 `.gd/.tscn` 资源目录（`addons/gut` 347 处、`tests` 96 处仍会进包）。config-only 修法不可行，**唯一可靠的 headless 手段是物理排除**。
- 实证：alpha.3 pck 经格式无关字节路径扫描，`addons/gut / tests/ / docs/ / tools/` 路径计数**全为 0**；游戏资源 `src/main/`、`src/ui/`、`arts/` 均在包内。pck 体积由 alpha.2 的 ~3.9 MB 降至 ~0.21 MB。
- **游戏逻辑零改动**（与 alpha.2 行为完全一致，仅发布包洁净度提升）。

### Known Issues（沿用）
- 真机音频「真在播」仍需真机验证（非阻塞）。
- D2（A-0N 实机消费）继续递延。
- 垂直切片无可视呈现层（用户已确认能跑就够了）。

---

## 0.1.0-alpha.2

**发布区间：** `5b9aa5b` → `3cf94a8`
**版本：** `0.1.0-alpha.2`（内部封闭 alpha 热修，仅 zh-CN，GitHub Release 分发）
**引擎：** Godot 4.4.1-stable
**评审：** solo（GHA runner 宕机；本地 Godot 验证为权威）
**changelog 依据：** 本小节条目均来自真实 `git log 5b9aa5b..3cf94a8`，**无任何编造 commit 或功能**。

### Fixed
- 启动期相机 `look_at` 在节点入树前调用导致的 `ERROR: Node not inside tree` 日志（`src/main/sprint0_bootstrap.gd`，改用 `look_at_from_position`）；纯日志消除，对游戏逻辑/玩法零影响。

### Test
- 音频 suite 在 headless 无真实音频设备下 `playing` 硬断言偶发 flake，改为按 voice 实际状态判定（保留真机硬断言），使 GUT 在 headless 环境确定性绿（241/241/1588）。

### Known Issues（沿用）
- 真机音频「真在播」仍需真机验证（非阻塞）。
- D2（A-0N 实机消费）继续递延。

---

## 功能分组（按真实改动汇总）

### 1. D1 — 自动检查点触发回路闭环
**commit：** `1f08848`（Phase 6 D1：闭合自动检查点触发回路 A–G 收尾）
**做了什么：**
- 新增 `CheckpointVolume`（Area3D，body_entered 访问去抖触发）。
- 新增 `CheckpointProducer`，订阅 `interactable_triggered(LIGHT_TOGGLE/DECOY)` 与 `guard_fsm_changed(RETURN)` 后收集 7 字段快照写入 `SaveManager`。
- 新增 `CheckpointApplier`，监听 `checkpoint_restored` 回滚玩家/守卫/灯/电荷。
- 在 `sprint0_bootstrap` 挂载 producer + applier；复用 `GuardSpawner.live_guards()` 遍历 LIVE 守卫。
- 新增端到端集成测试：真实软失败 → 产生检查点槽文件 → `restore_checkpoint` 非 no-op → 守卫回 RETURN、suspicion=0。
- 正确性闸门：软失败/恢复重置（ALERT→RETURN）不写检查点，保护回滚契约。
- 测试隔离修复（`SaveManager.configure_paths`、autoload 实例统一取 group `"save_manager"`、去抖用例等）。
**文件（节选）：** `src/game/checkpoint_{volume,producer,applier}.gd`、`src/core/save_manager.gd`、`src/game/light_model.gd`、`src/game/patrol_ai.gd`、`src/main/sprint0_bootstrap.gd`、`tests/unit/test_checkpoint_*.gd`、`docs/phase6/*`。
**验证：** GUT 全绿；`restore_checkpoint()` 保持零参、红线未触动。

### 2. 音频 cue 测试 headless 硬化
**commit：** `bd352f8`（硬化音频 cue 测试 headless 守卫 + 纳 D1 .uid）
**做了什么：**
- `tests/unit/test_audio_cues.gd`：`_playing_voice()` 在 headless 下查 `AudioStreamPlayer.playing`（无真实音频设备时不可靠，导致 S3-B 端到端断言非确定性失败）。
  - 加 headless 守卫：`OS.has_feature("headless")` 下改用 `_loaded_voice()` 弱断言（证明 cue 已加载、play_cue 非静默 no-op）；真机/真 CI 保留原 `_playing_voice()` 硬断言，S3-B「必须真出声」质量门不丢。
  - 不删 `_playing_voice()` 本身（真机路径仍用）。
- 纳入 D1 遗留未跟踪 `*.uid`（src 3 + tests 4）。
**影响：** 消除 flaky；本地 Godot 4.4.1 console 连跑两次 GUT 均确定性绿。
**验证：** 连跑两次 `Scripts 22 / Tests 239 / Passing 239 / Asserts 1578 / Failing 0 / exit 0`。

### 3. R-02 — 实时点光预算 WARN-ONLY 记账
**commit：** `c5a2c78`（R-02：新增实时点光预算 WARN-ONLY 记账断言，加载期/CI 联动 INSTANCE_CAP 与 R-02/G-02）
**做了什么：**
- `tests/ci/budget_checks.gd` 新增 `@ci:realtime-light-budget`（R-02 合并预算）：汇总 `InteractableRegistry.realtime_light_count()` + `GuardSpawner.live_guards()` 提灯数，按 tier 超 12(MVP)/32(Tier2) 即 **WARN-ONLY**（不阻断 spawn）。
- 新增 `scan_realtime_light_budget()` 反向断言表面（N-11/N-12）+ `_check_realtime_light_budget()` 静态代理（真实节点扫描 `.tscn` 内已放置光+守卫）。
- INSTANCE_CAP 与 G-02 在记账层联动：新增独立 id `interactable-g02-emitter`（区别于 R-02 的 `interactable-instance-cap`，保持 E07-S8 语义精确）。
- `tests/unit/test_budget_assert.gd` 补两条反向断言（realtime-light 越阈/边界 + instance-cap 链接 R-02/G-02），关闭「腐绿」缺口。
**红线：** 仅告警不拒绝 spawn；未改 `src/` 生产阻断逻辑。
**影响：** 本 commit 使 GUT 测试数 +2、断言 +10 → 累计 `22/241/241/1588/0`。

### 4. D3 — 退出泄漏验证关闭（harness-only）
**commit：** `b2d7acb`（D3：验证退出泄漏为 harness-only，标记「已验证关闭」并登记）
**做了什么：**
- `docs/phase6/playtest-report.md` 缺陷表 D3 行由 `NO(verify)` 升级为 **VERIFIED-CLOSED（harness-only）**。
- 新增 §7 验证关闭登记：`Godot --headless … -gexit --verbose` 真数证据 + 泄漏分类：
  - 退出 Node/RefCounted 泄漏 = 测试内创建对象，随退出惰性释放（harness-only）。
  - 4 个「resources still in use」= 静态 `preload` 引用的脚本资源（harness/autoload 级），非玩法对象。
  - 生产 `RefCounted leaked_count()==0` 由 `test_interactables.gd` 证明，零生产泄漏。
- 红线：仅登记，不新增 `tests/` 断言、不碰 `src/`（lean）。
**影响：** 发布前退出「ObjectDB leaked / 4 resources still in use」确认为 harness/引擎行为，**非生产真实泄漏**。

### 5. F-3 — `.wav.import` 边车提交（资产保真）
**commit：** `eb78d32`（F-3：提交 .wav.import 边车）
**做了什么：**
- `git add -f arts/audio/ui/sfx_ui_save_success.wav.import + sfx_ui_save_failure.wav.import`。
- 原因：`.gitignore:33` 全局忽略 `*.import`；新克隆/CI 重新导入会静默回退有损 QOA，违反 design-doc「UI 反馈不得用有损格式」。GHA runner 宕、CI PCM 断言无运行环境 → 主理人裁定优先保资产保真（提交边车）。
- 红线：仅 force-add 资产元数据，未改任何 `src/` 音频生产代码；风险极低。
**影响：** 内测者克隆后 UI 音仍为 48k/16bit PCM，不再静默降级。

### 6. D4 — 软失败测试「只验 seam」登记关闭
**commit：** `5cf0431`（docs(phase6)：D4 登记 VERIFIED-CLOSED，由 D1 集成测试 test_checkpoint_integration.gd:135 闭环）
**做了什么：**
- `docs/phase6/playtest-report.md` D4 行升级为 **VERIFIED-CLOSED**。
- 闭环证据：D1 集成测试 `test_checkpoint_integration.gd:135` `test_soft_fail_restores_world_from_checkpoint` 真实触发 LIGHT_TOGGLE → `SaveManager.write_slot` 真实写盘 → `FileAccess.file_exists(slot_path)` 断言**真实磁盘槽文件产生** → 真实软失败 → `checkpoint_restored` 非 no-op + 世界回滚。旧 seam 测试 `test_patrol_ai.gd:449` 保留为单元层互补。
- 红线：仅登记关闭，不新增断言、不碰 `src/`。
**影响：** Phase 6 登记的「只验 seam 不验真实槽文件」缺口已被 D1 集成测试在功能层面闭环。

---

## Known Issues / 已知缺口（诚实登记，不掩盖）

> 以下 5 项为本次发布已知风险，全部非阻断（除已标注），在 GitHub Release 页与内测沟通中**公开公示**。

1. **D2（A-0N 实机消费）递延** — 垂直切片无生产家园（存读档/设置界面未挂载），发布不暴露存读档 UI，A-0N 音频提示随之不触发；待 screen-flow 批收口。（根因：`wire_audio()` 生产挂载点 gap + 切片未覆盖该场景，非音频逻辑缺陷。）
2. **音频 path-A 真实 foley = 永久 known gap** — 物理限制，作者无实采条件；agent 不可伪造，不谎报「完成」。世界足音/检查点「咔」/Ambience/Music/Voice 均无真实录制资产。
3. **`wire_audio()` 生产挂载点 gap** — 同上，垂直切片无生产家园，存读档界面在实机无调用方。
4. **真机「真在播」音频待验证** — headless 不可测；S3-B「必须真出声」硬断言需在真机/真实 CI 闭环（**非阻塞**，headless 下已降级为弱断言）。
5. **GHA runner 宕机** — CI 自动发布不可用；本地 Godot 4.4.1 export 为权威，手动上传 GitHub Release。

**附加发布阻塞（配置层，须清除）：**
- ⛔ `project.godot` 缺 `version=` 字段（须补 `0.1.0-alpha.1`）。
- ⛔ 仓库根缺 `export_presets.cfg`（构建无法启动，补救见 `release-checklist.md` §6）。

---

*本 changelog 全部内容源自 `git log 24fc2ef..5cf0431` 真实历史，未编造任何 commit 或功能。*
