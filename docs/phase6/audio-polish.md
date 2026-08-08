# Phase 6 · 音频打磨审计 + D2 根因调查 · ASHEN STEP《灰烬之步》

**Author:** 阮和鸣（Ruan Hemo）— Audio Director / 音频与声效
**Build under audit:** `main` @ `24fc2ef`（与 playtest 同源）
**Engine:** Godot 4.4.1 / GDScript 2.0；GUT v9.3.0
**Mode:** **只读审计 + 根因调查 + 提案**。未修改 `src/` 任何文件，未提交。所有 file:line 指向 `24fc2ef` 工作树。
**上游依据：** `design/audio/s3b-save-load-audio-spec.md` v1.1 · `design/audio/audio-asset-landing.md` · `design/audio/audio-asset-landing.md` 附录 · `design/art/accessibility-matrix.md` v0.5 · `arts/audio/audio_bus_layout.tres` · `src/core/audio_director.gd` · `src/ui/audio_settings_panel.gd` · `src/ui/save_slots_screen.gd` · `src/main/sprint0_bootstrap.gd` · `docs/phase6/playtest-report.md`（D2 来源）

---

## 1. 审计范围与方法

**范围（音频域）**
1. 音频资产：`.wav` 占位 / 程序化 designed v1、总线布局资源、缺失资产登记。
2. 音频总线配置：Master / World / Music / Ambience / SFX_World / Voice / SFX_UI 七路，标定 dB，效果链。
3. 混音与实现接线：`EventBus` 音频信号、 `AudioStreamPlayer` 节点、cue 触发、0.4 s 视听同源淡入、世界模式三预设。
4. 可访问性音频项实装：A-0N（A-01~A-05，见 `accessibility-matrix.md` v0.5 行 19–22）在实机是否被消费。
5. **D2 专项**：A-0N 音频项「未在实机被消费（实机未被触发/播放）」的根因定位与修复方案。

**方法**
- `grep` 音频关键词于 `src/`、`tests/`，定位接线点与调用方。
- 通读 `audio_director.gd` / `audio_settings_panel.gd` / `save_slots_screen.gd` / `sprint0_bootstrap.gd` / `audio_bus_layout.tres`。
- 核对总线布局与 `s3b-save-load-audio-spec.md` §1.3，核对 cue 表 `base_gain_db`（AUD-G1）、`play_cue` 门控（A-05）。
- 核对 GUT 测试覆盖（`test_audio_cues.gd` / `test_audio_settings_panel.gd` / `test_audio_bus_layout.gd`）以判定「代码正确但未挂载」vs「接线 bug」。
- 交叉核对 `docs/phase6/playtest-report.md` 的 D2 原记录，确保结论一致。

**物理限制（已知 gap，不重复计为缺陷、不谎报）**
- `wire_audio()` 生产挂载点仍缺（卡在「垂直切片无生产家园」）。
- 音频 path-A 真实录制 foley = 永久 known gap（作者无实采条件）。

---

## 2. 音频域现状速览（审计基准）

| 维度 | 现状 | 结论 |
| --- | --- | --- |
| **总线布局** | `audio_bus_layout.tres`：7 路（Master/World{Music,Ambience,SFX_World,Voice}/SFX_UI）。World 恰 1 个 LPF（cutoff 20500 / resonance 0.0）；SFX_UI 效果数 0；Master 0。标定：Music −8.0，余 0.0。 | ✅ 与 spec §1.3 / ADR-005 D-1 完全一致 |
| **UI 音资产** | `arts/audio/ui/sfx_ui_save_success.wav` + `sfx_ui_save_failure.wav`（designed v1 程序化合成，48k/16bit/单声道/PCM，≈32 KB）。 | ✅ 存在且格式达标；非 path-A 实录 foley（已知 gap） |
| **世界音资产** | 足音 / 检查点「咔」/ Ambience / Music / Voice：**均无资产**。 | ⚠ 已知 gap（path-A foley、AO-5 检查点音），本批不交付 |
| **Cue 表** | `audio_director.gd:76-92`，`save_success`/`save_failure`/`action_denied`，全部 `base_gain_db ≡ 0.0`（AUD-G1）。 | ✅ 正确 |
| **Cue 触发** | `save_slots_screen.gd:431-432` `_audio_sink.call(name, gain_db)`；UI 池 3  voices、AUD-R1 重触发阶梯、20 ms 偷声淡出。 | ✅ 接线正确 |
| **世界模式** | `sprint0_bootstrap.gd:92-99` `_wire_audio_director()` → `AudioDirector.set_time_controller(_time)` 已接。120 ms 墙钟 ramp，不动 pitch（A-04/V-06）。 | ✅ FOCUS ducking 在切片内生效；PAUSED 预设因无暂停菜单未触发（玩法 gap，非音频） |
| **A-05 面板** | `audio_settings_panel.gd`：五路滑杆（Master/Music/Ambience/SFX_World/SFX_UI）+ 「UI 音效」开关，写 `AudioServer.set_bus_volume_db` 与 `AudioDirector.ui_sound_enabled`。 | ⚠ **逻辑正确，但切片内从未被实例化**（见 F-2） |
| **A-0N 实装矩阵** | 见 §4 表。 | — |

**一句话**：已落地的音频代码路径（cue、淡入、世界模式、总线）**实现正确、GUT 全绿**；本审计未发现静默/误触/节点泄漏类 bug。问题集中在**生产可达性**（D2）与**资产版本控制卫生**（F-3）。

---

## 3. 发现表

> 严重度：Blocker / Major / Minor / Info。file:line 指向 `24fc2ef`。「建议修复」仅登记，本轮不改代码。

| # | 文件:行 | 问题 | 严重度 | 建议修复 |
| --- | --- | --- | --- | --- |
| **F-1** | `src/main/sprint0_bootstrap.gd:102-118`（L111 注释掉的 `screen.wire_audio(...)`）；`save_slots_screen.gd:206`（`wire_audio()` 定义，仅 `tests/unit/test_audio_cues.gd:165` 调用）；`src/main/sprint0_bootstrap.gd:102` 明示「SaveSlotsScreen NOT mounted」 | **D2 本体**：S3-B 存/读档音频 cue（承载 A-02 字幕/视觉孪生 + A-05 UI 音门控）在实机**从未被触发/播放**。存读档界面在垂直切片中无生产挂载点（仅测试构建），导致 `wire_audio()` 在实机无调用方，cue sink / fade sink 从未接通 `AudioDirector`。 | **Minor**（= D2） | 当存读档界面获得生产归属（screen-flow 批）时，在构造点加 `screen.wire_audio(get_node("/root/AudioDirector"))`（bootstrap 注释已给出确切写法）。**纯集成/接线，不改音频逻辑**。无需动 `audio_director.gd` / `save_slots_screen.gd`。 |
| **F-2** | `src/ui/audio_settings_panel.gd`（仅自身 + `.tscn` 引用；注释 L25-26「exists so a screen-flow batch can instance it」）；全仓 `src/` 无实例化调用 | **A-05 面板实现但不可达**：五路音量滑杆 + 「UI 音效」开关逻辑正确（GUT 已覆盖 `test_audio_settings_panel.gd`），但垂直切片无任何菜单/设置流挂载它，玩家在实机**无法到达**音频偏好。 | **Minor** | 与 F-1 同源：screen-flow 批把 `AudioSettingsPanel` 挂到设置菜单的音频分区即可（面板 `_ready()` 已会 `load_settings()`→ 写总线 + 经 autoload 解析 `AudioDirector`）。无需改面板逻辑。 |
| **F-3** | `.gitignore:33`（`*.import`）；`git ls-files` 仅含 `.wav`+`.tres`，`.wav.import` 在磁盘存在但未跟踪 | **资产导入设置未版本化**：WAV 的 PCM（无损）导入设置（design-doc F-1 修复）写在 `.import` 边车，而 `.gitignore` 全局忽略 `*.import`。**全新克隆 / CI 重新导入时 Godot 会用默认 QOA 有损压缩**，静默回退 spec §1.6「UI 反馈不得用有损格式」。 | **Minor**（仅在新克隆/CI 触发，当前本地不失败） | 二选一：(a) 提交两个 `.wav.import`（Godot 官方推荐）；(b) 加 CI 断言：headless 下 `ResourceLoader.load()` 后 `format == 1`（PCM）。该风险 design-doc F-2 已登记、留主理人裁定，此处确认其**仍然成立**。 |
| **F-4** | `src/ui/audio_settings_panel.gd:64-70`（仅 A-05 五路+UI 开关）；全仓 `grep mono/downmix/A-01/A-03` 无结果 | **A-01（单声道下混开关）、A-03（失败/拒绝音额外衰减档）未实现**：`accessibility-matrix.md` v0.5 行 20 把二者列在 Comprehensive 档；当前实现仅覆盖 A-05（Standard）。无 mono / 衰减控件存在。 | **Info**（Comprehensive 档，超出垂直切片范围，非缺陷） | 留待 Comprehensive 批次；实现时补到 `AudioSettingsPanel` + `AudioDirector`（A-01 可走 `AudioServer` 单声下混或素材层面；A-03 可在 `play_cue` 对 `save_failure`/`action_denied` 追加衰减档）。 |
| **F-5** | `src/ui/a11y_settings.gd`（grep `audio\|mono\|ui_sound\|Sound\|percent\|volume` **零匹配**）；`docs/phase6/playtest-report.md:57,80` | **澄清 D2 口径**：`A11ySettings` 实际**不含任何音频档字段**。playtest 所述「A-0N tier modeled in a11y_settings.gd」不准确——音频偏好独立于 `A11ySettings`，落在独立 `AudioSettingsPanel` + `SaveManager` 的 `"audio"` section。因此**不存在** `A11ySettings→AudioDirector` 的档位应用待补；真正的 A-0N 音频项就是（未挂载的）`AudioSettingsPanel` 与（未挂载的）`SaveSlotsScreen` cue。 | **Info** | 无需修代码；建议 playtest 报告把 D2 口径从「A-0N tier 未应用」收紧为「A-05 面板与 S3-B cue 在实机不可达」（= F-1/F-2）。 |
| **F-6** | `arts/audio/audio_bus_layout.tres` 全量；`audio_director.gd:232-239, 285-296, 390-486` | **验证通过（无问题）**：总线树/标定/效果数与 spec 一致；`play_cue` 首句即 A-05 门控、`cue_log` 不记静音 cue；`effective_level_db` 纯函数不含 AUD-R1 阶梯（L2 层可断言 AUD-H1）；`action_denied` 为别名解析（AUD-G1）；0.4 s 淡入 `begin/tick/end` 同源驱动（AUD-F1/F6/F7）；世界模式 120 ms 墙钟 ramp、不动 pitch（A-04/V-06）；`PROCESS_MODE_ALWAYS` 覆盖 director + UI 池 + 环境/音乐（T-03 两机制安全）。**无静默 / 误触 / 节点泄漏**。 | **Info**（pass） | 无需动作。 |
| **F-7** | `src/game/footfall_vfx.gd:32,72`（仅发 `footfall_foley` 字幕 stub）；`src/core/event_bus.gd:70` `sound_emitted` 被 `patrol_ai.gd` / `trap_entity.gd` 消费；`AudioDirector` 不订阅 `sound_emitted` | **世界音无 3D 播放（已知 gap，非 D2）**：`sound_emitted` 是玩法/AI 信号（守卫听觉、陷阱），不是音频播放信号；`AudioDirector` 刻意不订阅它（零新增事件纪律）。`footfall_vfx` 仅发 X-02 字幕 stub，无 `AudioStreamPlayer3D`。世界 foley 资产缺 = path-A 永久 known gap。无节点泄漏。 | **Info**（已知 gap） | 留足音批次：届时新增世界 SFX 播放器（默认 `PAUSABLE`）订阅 `sound_emitted`，走 `SFX_World` + `AUD-CP1~4`（检查点音前置约束）。 |

---

## 4. D2 专项：根因 + 修复方案

### 4.1 症状（来自 playtest）
`docs/phase6/playtest-report.md:57,70,80`：D2 =「A-0N audio-a11y tiering **defined, live consumption NOT observed** in the slice」；优先级 medium，建议「confirm `AudioDirector` applies the A-0N tier at runtime; add a GUT assertion for audio-tier wiring」。

### 4.2 A-0N 含义定位（来自 `accessibility-matrix.md` v0.5 行 19–22）
A-0N 是 `AUD-A1~A5` 并轨 `control-manifest.md` §8 后的音频硬约束 **A-01~A-05**：

| 编号 | 含义 | 本仓实现位置 | 实机消费状态 |
| --- | --- | --- | --- |
| **A-01** | 信息音单声道居中、下混不丢信息 | 素材层（单声源）；**下混开关未实现** | ❌ 未实现（Comprehensive，F-4） |
| **A-02** | 音频永不作为唯一通道；存/读档事件配字幕+视觉 | `save_slots_screen.gd` 字幕 sink + cue sink | ❌ **界面未挂载 → 未消费（F-1）** |
| **A-03** | 失败/拒绝音上限受约束、不制造惊吓 | 资产层已满足；**额外衰减档未实现** | ❌ 未实现（Comprehensive，F-4） |
| **A-04** | 禁 >3 Hz 振幅调制、模式切换 120 ms 缓动、不变调 | `audio_director.gd` 世界模式 ramp | ✅ **已接线**（bootstrap→set_time_controller），FOCUS 生效 |
| **A-05** | 分路音量独立可调 + UI 音开关 | `audio_settings_panel.gd` 五路 + UI 开关 | ❌ **面板未挂载 → 不可达（F-2）** |

→ D2 实际指向 **A-02 与 A-05** 的实机消费缺口（A-01/A-03 属 Comprehensive 未实现，非「已定义未消费」）。

### 4.3 代码追踪
- **生产挂载点**：`sprint0_bootstrap.gd` 是垂直切片唯一装配入口。它 _wire_audio_director()（L92-99，接 TimeController→AudioDirector，A-04 因此生效），但明确注释（L102-118）「SaveSlotsScreen is NOT mounted in this vertical slice; today it is built only by tests/unit/test_save_ui.gd」，并把 `screen.wire_audio(...)` 留在**注释**（L111）。
- **`wire_audio()` 调用方**：定义于 `save_slots_screen.gd:206`，全仓**唯一**生产调用方缺失；GUT 中由 `test_audio_cues.gd:165` 调用并验证 cue 真实触发。→ 代码路径正确、CI 已覆盖，**只是实机没有调用方**。
- **`AudioSettingsPanel` 调用方**：`src/` 内零实例化（仅自身 + `.tscn`）；注释 L25-26 自陈「exists so a screen-flow batch can instance it」。
- **`A11ySettings` 音频档**：经 grep **不存在**（F-5），故「A-0N tier 未应用」在代码层无对应对象——playtest 该表述需收紧为「A-05 面板与 S3-B cue 在实机不可达」。

### 4.4 根因判定
```
候选根因① 「定义了但未在任何玩法事件触发」（接线缺失于既有界面内）
候选根因② 「被已知 wire_audio() 生产挂载点 gap 阻断」
候选根因③ 「垂直切片本就不覆盖该场景」
```
**结论：D2 = ② + ③ 复合，且非 ①。**
- **非 ①**：界面内接线完全正确（`wire_audio` 一次性接 cue+fade 双 sink；面板 widget→总线直达；GUT 全绿）。不是「界面内漏接一根线」。
- **是 ②**：`wire_audio()` 生产挂载点确为已知 gap（任务背景明文），bootstrap 注释即其留白。
- **是 ③**：`SaveSlotsScreen` 与 `AudioSettingsPanel` 在 Sprint 0 垂直切片中**没有生产归属**（无菜单、无暂停、无设置流），故二者在实机无出生点。

根因本质：**音频子系统的「生产入口」缺失**（integration/wiring 缺口），**不是音频逻辑缺陷**。修复是给界面一个生产归属并调用既有的 `wire_audio()`，而非改 `audio_director.gd`。

### 4.5 修复方案（提案，本轮不动代码）
1. **挂载存读档界面（解 F-1/D2 主因）**：screen-flow 批把 `SaveSlotsScreen` 接入菜单/暂停/检查点后，在构造点加一行（bootstrap L111 已给）：
   ```gdscript
   screen.wire_audio(get_node("/root/AudioDirector"))   # 一次性接 cue + fade 双 sink
   ```
   - 禁止只接 `set_audio_sink()`（只接 cue sink 会触发 F-5 缺陷：load fade 永不达 `end_load_fade()`，World 总线永久停 −12 dB / LPF 700 Hz）。`wire_audio()` 已强制双接；`test_audio_bus_layout.gd:302-317` 作为 CI 守门阻止半接。
2. **挂载音频设置面板（解 F-2）**：screen-flow 批把 `AudioSettingsPanel` 挂到设置菜单音频分区。其 `_ready()` 已会 `load_settings()`→ 写五路总线 + 经 autoload 解析 `AudioDirector` 设 `ui_sound_enabled`。
3. **补生产接线冒烟测试（防回归）**：现有 `test_audio_bus_layout.gd` 只守「半接」，**不守「bootstrap 是否真的调用了 wire_audio()」**。建议加一条：在真实树内 `add_child` 一个 `SaveSlotsScreen` 并经 `wire_audio` 接 director，触发一次存/读档，断言 `AudioDirector.cue_log` 非空且总线 preset 在淡入后回到 FLOWING。这样 D2 类「生产入口缺失」可被 CI 捕获。
4. **（可选，F-3）资产导入版本化**：提交 `.wav.import` 或加 CI 断言 WAV 为 PCM，避免新克隆静默回退 QOA。

**受影响文件（修复阶段，非本轮）**：`src/main/sprint0_bootstrap.gd`（或未来 screen-flow 装配文件，新增 `wire_audio` 调用 + 面板挂载）；**不需**改 `src/core/audio_director.gd`、`src/ui/save_slots_screen.gd`、`src/ui/audio_settings_panel.gd`（逻辑已就绪）。

---

## 5. 汇总计数

**本轮音频域审计（不含 D1/D3/D4，彼属 cheng/wen）**

| 严重度 | 数量 | 条目 |
| --- | --- | --- |
| **Blocker** | 0 | — |
| **Major** | 0 | （D1 Major 属 cheng/wen 检查点逻辑，非音频域；音频域内无 Major） |
| **Minor** | 3 | **F-1（= D2）**、F-2、F-3 |
| **Info** | 4 | F-4、F-5、F-6、F-7 |
| **合计** | **7** | — |

**与 playtest 缺陷表的对应**：D2（Minor）= 本报告 F-1（根因 = `wire_audio()` 生产挂载点 gap + 垂直切片无生产归属）。F-2 为 D2 的同源伴生（A-05 面板不可达）。F-3 为资产卫生独立 Minor。**D2 根因结论：已知 `wire_audio()` 生产挂载点 gap（候选②）叠加垂直切片未覆盖该场景（候选③），非界面内接线 bug（候选①）。**

**已知 gap（不计入缺陷、诚实登记）**：`wire_audio()` 生产挂载点缺；path-A 真实 foley 永久缺；检查点「咔」资产缺；A-01/A-03 Comprehensive 档未实现。

---

## 6. 交叉影响

### 6.1 与 D1（cheng / wen，Major：滚动检查点未写入）
**强耦合，同源。** D1 的根（「`SaveSlotsScreen` 不在切片挂载、无生产调用 `write_slot(CHECKPOINT_SLOT_ID)`」，`playtest-report.md:39,79`）与 D2 的根（「`SaveSlotsScreen` 不在切片挂载、无生产调用 `wire_audio()`」）是**同一个生产入口缺失**。即：只要给存读档界面一个生产归属，D1（加 gameplay 检查点写入器）与 D2（接 `wire_audio()`）应**在同一 screen-flow 批内一并收口**。建议主理人把 D1/D2 派给同一负责人，避免两次挂载导致界面双入口或接线竞态。

### 6.2 与 perf（cheng，R-02 性能剖析）
**无冲突，零新增风险。**
- 音频常驻内存极小：2×WAV ≈32 KB，3 个 UI `AudioStreamPlayer` + 环境/音乐各 1，无流式加载。远低于 spec §7.3 预算。
- `AudioDirector._process()`（`PROCESS_MODE_ALWAYS`）每帧仅做 120 ms ramp 插值 + 偷声淡出，开销可忽略；不与 cheng 的 perf 剖析文件重叠（其剖析对象为渲染/光模型/ghost-trail）。
- `SoundPropagator` 的 `sound_emitted` 是玩法/AI 广播，已被 `patrol_ai` / `trap_entity` 消费；音频侧无额外订阅。**建议**：cheng 的 perf 剖析若触及 `sprint0_bootstrap.gd` 装配，勿改动 `_wire_audio_director()`（否则静默丢失世界模式 ducking，无 CI 报错）。

### 6.3 与 美术（lin，0/0/3/5 纯文档 hygiene，与音频无耦合）
**无耦合。** lin 的美术审计结论为 0 blocker/0 major/3 minor/5 info 且均为文档 hygiene，未触及音频。A-02 的视觉孪生（字幕/图标）由 `save_slots_screen.gd` 字幕 sink 承担，归 UI/音频域，不依赖 lin 的美术资产。A-01 单声道下混（F-4）为未来 Comprehensive 批次，与 lin 的色盲/对比度审计正交。音频域不阻挡、亦不受阻于 lin 的收尾。

### 6.4 建议派工
- **D2/F-1/F-2（音频生产可达性）**：screen-flow / 集成负责人（cheng 或 wen），与 D1 同批。音频逻辑零改动，阮和鸣只需在挂载后复核 cue/面板行为。
- **F-3（.import 版本化）**：主理人裁定（提交边车 or 加 CI 断言），工程侧执行。
- **F-4（A-01/A-03 Comprehensive 档）**：留 Comprehensive 批次，阮和鸣起规格。

---

*本报告为只读审计 + 根因调查 + 提案。所有 file:line 指向 `main @ 24fc2ef`，未修改任何 `src/` 文件、未提交。D2 根因 = 已知 `wire_audio()` 生产挂载点 gap（候选②）叠加垂直切片未覆盖该场景（候选③），非界面内接线 bug（候选①）。*
