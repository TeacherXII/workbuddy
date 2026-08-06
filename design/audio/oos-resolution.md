# S3-B 超范围项决议 —— OOS-1 ~ OOS-6 收口

| 字段 | 值 |
| --- | --- |
| **项目** | ASHEN STEP《灰烬之步》 |
| **引擎 / 平台** | Godot 4.4 · GDScript ｜ PC（键鼠 + 手柄） |
| **Sprint / 批次** | Sprint 3 · **S3-B 残留收口**（Task **AUD-OOS-1**，P0） |
| **文档版本** | **v1.0** |
| **作者** | 阮和鸣（Audio Director / 音频与声效） |
| **上游** | `design/audio/s3b-save-load-audio-spec.md` **v1.0 §6.3**（OOS-1~6 的登记处）· main `89dbffd` 源码实况 |
| **性质** | **规格 / 决议文档**。本文作者**未修改任何 `.gd`、未修改 `project.godot`、未修改 `asset-manifest.md` / `accessibility-matrix.md`、未执行任何 git 操作**。全部产出为可施工文本，由主理人中转给责任人。 |
| **配套产出** | `design/audio/asset-categories.md`（OOS-1 回填包）· `docs/architecture/adr/adr-005-audio-bus-architecture-and-world-mode-presets.md`（OOS-4 草案） |

---

## 0. 自查记录 —— 本文全部引用的源码依据

> 纪律要求「不要凭记忆」。以下每一条都在写作前实际 Read / Grep 复核过，命令与结果如实登记。凡与我 v1.0 规格有出入的，在末列标注。

| # | 断言 | 复核方式 | 结果 | 与 v1.0 规格 |
| --- | --- | --- | --- | --- |
| V-1 | `project.godot` 零 `[audio]` 段 / 零 bus_layout / 零 mix_rate | Read 全文（24 行） | ✅ 属实。仅 `[application]` / `[autoload]`（只有 `SaveManager`）/ `[renderers]` | 一致 |
| V-2 | `src/` 零 `AudioStreamPlayer`、零 `AudioServer` | `rg 'AudioStreamPlayer\|AudioServer\|bus_layout\|mix_rate'` 全仓库 | ✅ 属实。命中全部落在 `.md` 文档里，`.gd` 零命中 | 一致 |
| V-3 | 零音频资产 | `git ls-files \| grep -E 'arts/\|\.wav\|\.ogg\|\.tres'` | ✅ 零命中 | 一致 |
| V-4 | **`res://arts/` 目录根本不存在** | `ls arts` → no such file；`git ls-files` 零命中 | ✅ 属实 | ⚠️ **规格 §1.6 写「沿用 `res://arts/` 根」，实际这个根还没落地**。见 §9 冲突 F-2 |
| V-5 | `time_controller.gd` L29 `var mode := "FLOWING"  # FLOWING \| FOCUS \| PAUSED` | Read 全文（120 行） | ✅ 逐字属实 | 一致 |
| V-6 | `PAUSED` 全仓库无人设置 | `rg 'PAUSED' --glob '*.gd'` | ✅ **全仓库 `.gd` 仅 1 处命中，即 L29 的注释本身**。无 `enter_paused()` / `exit_paused()` | 一致 |
| V-7 | `save_slots_screen.gd` L83 `var _audio_sink: Callable` | `sed -n '80,86p'` | ✅ L83 逐字属实 | 一致 |
| V-8 | L150 `func set_audio_sink(sink: Callable)` | `sed -n '146,156p'` | ✅ L150 属实（L146 为 `set_subtitle_sink`） | 一致 |
| V-9 | L342–343 `_audio_sink.call(name, gain_db)` | `sed -n '336,348p'` | ✅ 属实（L340 `func _cue`，L341 `cue_log.append`，L342 `if _audio_sink.is_valid():`，L343 `.call(...)`） | 一致 |
| V-10 | cue 常量 L46–48 | `sed -n '40,52p'` | ✅ `CUE_SUCCESS` L46 / `CUE_FAILURE` L47 / `CUE_DENIED` L48，注释含 `# same thud, -3dB` | 一致 |
| V-11 | §5.6 四个插入点行号 | `sed -n '738,752p'` / `'784,792p'`；`wc -l` = 825 | ✅ `_begin_load_fade()` **L742**、`_end_load_fade()` **L749**、tick 淡入块 **L788–789** —— 三处逐一对上 | 一致 |
| V-12 | 无 `get_tree().paused` / `process_mode` | 同 V-2 的 grep | ✅ `.gd` 零命中 | 一致 |
| V-13 | ADR 命名惯例 | `ls docs/architecture/adr/` | ⚠️ **ADR 实际在 `docs/architecture/adr/` 子目录**，不在 `docs/architecture/` 下。命名 `adr-00N-<kebab-slug>.md`（001 render-pipeline / 002 stealth-compute-model / 003 realtime-with-pause-time-model / 004 lighting-and-shadow-budget） | 派工单写 `docs/architecture/adr-005-*.md`，**已按实际惯例落到 `adr/` 子目录**。见 §9 冲突 F-3 |
| V-14 | ADR front-matter 格式 | Read adr-003 / adr-004 | 两者均 `status: Accepted`（**首字母大写**）、`date` / `deciders` / `tags` / `upstream`，正文 `## 状态 / ## 上下文 / ## 决策 / ## 备选 / ## 后果` | 派工单写 `status: draft`，**已按仓库大小写惯例写作 `status: Draft`**，语义相同 |
| V-15 | `control-manifest.md` 是否有音频约束编号 | Read 全文（103 行） | ⚠️ **R/T/V/C/X/G 六族共 30 条，无一条覆盖音频**。§7 CI 断言 5 条也无音频 | 影响 OOS-2 编号治理，见 §9 冲突 **F-1** |
| V-16 | `architecture.md` §4 性能预算表是否有音频行 | `sed -n '103,135p'` | ⚠️ **无音频内存 / 同发语音数预算行** | 见 §9 冲突 F-4 |
| V-17 | `.gitignore` 是否屏蔽音频二进制 | Read 全文 | ✅ 不屏蔽 `*.wav` / `*.ogg` / `*.tres`，无 LFS 配置 | 无阻塞 |

> **结论**：v1.0 规格 §6.3 对 OOS-1 / OOS-2 / OOS-3 / OOS-6 的四条描述**全部经源码证实，无一条需要撤回**。新发现三处规格未覆盖的事实：V-4（`arts/` 根不存在）、V-15（无音频约束编号体系）、V-16（无音频性能预算行）。

---

## 1. 六项决议速览

| # | 议题 | 决议 | 产出位置 | 责任人（经主理人） | 阻塞 S3-B？ |
| --- | --- | --- | --- | --- | --- |
| **OOS-1** | asset-manifest 无音频类目 | **回填 4 个 patch**（格式行 / 前缀 / 目录树 / 新增 §7） | 本文 §2 + `asset-categories.md` | 林绘澄 | 否 |
| **OOS-2** | accessibility-matrix 无音频 a11y 行 | **补 4 行（19~22）+ 编号治理注 + 覆盖表 4 行**；**编号归属须先裁决** | 本文 §3 | 林绘澄（收口）· 程基岩（编号） | 否 |
| **OOS-3** | project.godot 零音频子系统 | **给出完整施工蓝图**：`[audio]` 段 + `audio_bus_layout.tres` 全文 + autoload + CI 断言 | 本文 §4 | 程基岩 | **是**（E-1~E-5 是 S3-B 出声的前提） |
| **OOS-4** | 建议新开 ADR-005 | **草案已写**（`status: Draft`），澄清「全局 lowpass」挂 World 不挂 Master | 本文 §5 + ADR 文件 | 主理人 + 程基岩 | 否（§1.4 已给裁决，可先施工） |
| **OOS-5** | `save_manager.gd` 无 `delete_slot()` | **无动作** —— 工程侧已自行登记为 follow-up | 本文 §6 | 程基岩（已登记） | 否 |
| **OOS-6** | `PAUSED` 死枚举 | **不删，标注 + 接线**（两阶段：P0 注释诚实化，P1 补 `enter_paused()`） | 本文 §7 | 程基岩 | 否 |

---

## 2. OOS-1 · 音频类目清单（给林绘澄）

> **可粘贴的 patch 文本在 `design/audio/asset-categories.md`**（4 个 patch 块 + 精确插入行号 + 回填后自检清单）。本节给**类目本体**，即"到底有哪几个类目、各是什么状态"。
> **权威源**：`design/audio/s3b-save-load-audio-spec.md` v1.0 §1.6 / 附录 B。本节与 `asset-categories.md` 均为其投影，三者冲突以音频规格为准。

### 2.1 类目本体（6 事件 → 2 实际资产 → 3 个"不产资产"条目）

| # | 类目 | 服务事件 | 实际文件 | 格式 | 调用方增益 | 有效 MaxM | 状态 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| **A-1** | **主成功音**「嗒」 | 存档成功 | `res://arts/audio/ui/sfx_ui_save_success.wav` | 48 kHz / 16-bit / 单声道 / PCM · 110 ms | `0.0 dB` | −18.0 LUFS-M | **待制作** |
| **A-2** | **主失败音**「顿」 | 存档失败 · 读档失败 | `res://arts/audio/ui/sfx_ui_save_failure.wav` | 48 kHz / 16-bit / 单声道 / PCM · 220 ms | `0.0 dB` | −20.0 LUFS-M | **待制作** |
| **A-3** | **删除成功（别名）** | 删除成功 | **无文件 —— 复用 A-1 同一 stream** | — | `-1.0 dB` | −19.0 | **不产资产** |
| **A-4** | **禁用动作（别名）** | `action_denied` | **无文件 —— 复用 A-2 同一 stream** | — | `-3.0 dB` | −23.0 | **不产资产** |
| **A-5** | **读档成功（无 UI 音）** | 读档成功 | **无文件、无 cue** | — | — | — | **不产资产** |
| （工程侧） | 总线布局资源 | — | `res://arts/audio/audio_bus_layout.tres` | Godot 资源 | — | — | **待程基岩建**（E-2，见 §4.3） |

### 2.2 新增的 4 个命名前缀（扩 asset-manifest §1.3）

| 前缀 | 含义 | 示例 |
| --- | --- | --- |
| `sfx` | 音效。第二段为**域**：`ui` / `foot` / `obj` / `guard` | `sfx_ui_save_success.wav`、`sfx_foot_stone_a.wav` |
| `amb` | 环境床 | `amb_nave_bed.ogg` |
| `mus` | 音乐 | `mus_nave_drone.ogg` |
| `vo` | 配音（预留，当前为空） | `vo_guard_alert_a.ogg` |

- 变体用 `_a` / `_b` / `_c`，**不用 `_01`**（与 `_lodN` 的数字风格区分，避免 CI 命名断言误读）。
- 音频资产**无 LOD 概念**，`_lodN` 对这四个前缀不适用。

### 2.3 ★ 交给林绘澄时必须一起交的三条纪律

1. **A-3 / A-4 绝不可回填成「待制作」。** 它们是**别名**（同一个 stream，不同调用方增益），不是资产。若有人照着清单去渲染一个"已经低 3 dB"的 `action_denied` 文件，运行时会和 `save_slots_screen.gd` L285 已传的 `-3.0` **叠加成 −6 dB**，而这个错误**对现有 CI 完全隐形**（`test_save_ui.gd` 只断言调用方参数，看不见 cue 表）。这就是音频规格 **AUD-G1**「cue 表 `base_gain_db` 恒为 0.0」存在的全部理由。
2. **A-5 不是遗漏，是裁决。** 读档成功故意无声：世界重新出现本身就是反馈。改由 `World` bus 沿 `−60 → 0 dB` 与视觉 `_fade` 遮罩**同帧同曲线**回来（0.4 s）。`test_save_ui.gd` L980–981 已断言读档成功时 cue 数为 0。
3. **A-1 / A-2 是电平有序对。** 硬约束 **AUD-H1**：失败族有效响度 ≤ 成功族有效响度，当前余量 1.0 dB。**任何一侧改响度，另一侧必须同步复核**，不能单独调。

### 2.4 附带发现（不阻塞，但请林绘澄知悉）

`res://arts/` 目录**在仓库里根本不存在**（V-4）。asset-manifest §1.3 的目录树目前是**纯约定，尚未落地任何文件**。因此 `arts/audio/` 将是 `arts/` 下**第一个真实存在**的子目录 —— E-1「建目录」不是在已有树上挂枝，是种下这棵树的第一根。

---

## 3. OOS-2 · accessibility-matrix 音频 a11y 行（行文本 + 精确插入位置）

> 目标文件：`design/art/accessibility-matrix.md`（当前 **v0.3**，作者林绘澄，全文 224 行）。**本文作者未修改该文件**，以下为待收口的行文本。
> ⚠️ **落地前须先裁决 §3.5 的编号归属冲突 F-1**，否则新行会破坏该文件 §2 表前注「所有约束编号严格对应 control-manifest.md，无新增未定义约束」这条自述纪律。

### 3.1 主插入点 —— 矩阵表追加 4 行

**位置：L85 之后、L86（空行）之前**（即现矩阵最后一行「行 18 降低认知负荷」之后，紧接追加）。

```markdown
| 19 | 音频提示视觉同源（每条承载信息的音必有视觉孪生） | 听障·认知 | **强制(开)** 音频**永不作为唯一通道**：S3-B 全部 6 个存档/读档事件均配字幕（X-02，说话者「系统」）+ 视觉；读档成功的听觉回归与 `_fade` 遮罩**同帧读同一个 `world_fade_alpha()` 返回值**，非两条独立曲线 · 极低（规格纪律，零运行时成本） | **强制(开)** + 全量 UI 音事件逐条覆盖审计 · 极低 | **强制(开)** + 与行 15 音景图标联动（图标是**冗余**不是替代）· 低 | X-02 / C-05 / **AUD-A2**（音频域，见表后注） |
| 20 | 分路音量独立可调 + UI 音开关 | 听障·认知 | **可用未默认** 持久化通道已存在（`SaveManager.save_prefs("audio", …)`，`test_save_manager.gd` L448 已在测），但**无设置 UI** · 低 | **默认开** Master / Music / Ambience / SFX_World / SFX_UI **五路独立**滑杆 + 「UI 音」总开关；★ 关闭 UI 音后字幕与视觉通道**不得**随之失效（由行 19 兜底）· 中（设置 UI + 持久化，**逻辑交程基岩**） | **默认开** + 单声道下混开关（**AUD-A1**）+ 失败/拒绝音额外衰减档（听觉敏感）· 中 | **AUD-A5 / AUD-A1 / AUD-A3**（音频域） |
| 21 | 凝神 / 暂停期音频不变调 | 眩晕·光敏·认知 | **强制(开)** 三个世界预设（FLOWING / FOCUS / PAUSED）**均不动 `pitch_scale`**（ADR-003 原决策）；模式切换 **120 ms 缓动**、单帧增益变化 ≤3 dB（V-06 的听觉对偶）；**禁止 >3 Hz 周期性振幅调制**（V-01 的听觉对偶）· 极低（bus 参数纪律） | **强制(开)** · 极低 | **强制(开)** + 世界 ducking 深度可调（**不得**借此解除「不变调」铁律）· 低 | ADR-003 / **ADR-005** / V-01·V-06 的听觉对偶 **AUD-A4 / AUD-V6** |
| 22 | 状态区分不依赖音频通道（双向不塌缩） | 听障·色盲·认知 | **强制(开)** C-05 三重编码（亮度+形状+图标）**三维全部为视觉** —— 色盲档**不得**引入「靠听声区分状态」作为补偿；反向亦然：静音 / 听障玩家不因缺声丢失任何状态信息 · 极低（编码纪律） | **强制(开)** · 极低 | **强制(开)** + 行 15 音景可视化作为**冗余通道**，不得成为唯一载体 · 中 | C-05 / C-06 / C-07 / X-02 / **AUD-A2** |
```

**与现有行 15 的分工（须一并写清，否则会被读成重复）**：
- **行 15**「音频提示可视化增强」= **Comprehensive 增强层**，做的是「把音景**额外**画出来」（类型图标 + 方向指示）。
- **行 19**「音频提示视觉同源」= **Basic 强制底线**，做的是「任何音**本来就**必须有视觉/字幕孪生」。
- 一个是锦上添花，一个是准入条件。**行 19 是行 15 的前提，不是它的子集。**

### 3.2 表后注 —— 编号治理块

**位置：L96 之后、L97（空行）之前**（即现有「⚠️ 行 3 / 行 4 告警色治理三件套」注块结束之后，作为第二个注块追加）。

```markdown
> **⚠️ 行 19–22 的编号治理 —— `AUD-*` 不是 control-manifest 编号**
>
> `docs/architecture/control-manifest.md` v0.2 的六族约束（R-01~09 / T-01~04 / V-01~06 / C-01~07 / X-01~02 / G-01~05，共 30 条）**无一条覆盖音频**，§7 的 5 条 CI 断言同样不含音频。因此行 19–22 引用的 `AUD-*` 编号，其**权威源是 `design/audio/s3b-save-load-audio-spec.md` v1.0 §1.7**（AUD-A1~A5）与 §1.4（AUD-V6），**不属于 control-manifest**。
>
> 这意味着本文 §2 表前注「所有约束编号严格对应 `control-manifest.md`，无新增未定义约束」**对行 19–22 暂不成立**。两条出路，待主理人裁决：
> - **(A · 推荐)** 程基岩在 `control-manifest.md` 新增 §8「音频硬约束」，编号 **A-01~A-05**，取值直接引用音频规格 §1.7；本文行 19–22 改引 `A-0N`，§3.3 覆盖表增 5 行。**编号体系保持单一权威源。**
> - **(B · 最小改动)** 行 19–22 直接引 `AUD-*`，并保留本注块作为显式豁免声明。代价是本文从此有两套编号来源。
>
> 在裁决落地前，行 19–22 的**约束内容全部有效**（它们是可执行的规格），仅**编号归属**待定。
```

### 3.3 §3.3 约束编号覆盖核对表 —— 追加 4 行

**位置：L150 之后、L151（空行）之前**（覆盖表最后一行「§8.1 / §8.2 / §8.4」之后）。

```markdown
| AUD-A1 | 行 20 | Comprehensive | 单声道居中 / 下混不丢信息（**音频域编号**，见 §2 表后注） |
| AUD-A2 | 行 19 / 行 22 | 三档强制 | 音频永不作为唯一通道（**音频域编号**） |
| AUD-A4 / AUD-V6 | 行 21 | 三档强制 | 禁 >3 Hz 振幅调制 / 模式切换 120 ms 缓动（V-01 / V-06 的听觉对偶，**音频域编号**） |
| AUD-A5 / AUD-A3 | 行 20 | Standard / Comprehensive | 分路音量与 UI 音开关 / 失败音不制造惊吓（**音频域编号**） |
```

### 3.4 §3.3 结论句 —— 须改写（现文已为假）

**位置：L152**。现文断言「Comprehensive 的 6 项增强**全部复用既有约束编号，未新增任何约束编号**」—— 加入行 19–22 后这句话不再成立，必须同步改，否则重蹈 v0.1「与 §9 逐项数值一致」那种**过期的概括性断言**（该文件 §3.1 自己已为此写过修订说明）。

```markdown
> **结论**：control-manifest 全部 18 条可访问性硬约束（C-01~07、X-01/02、V-01~06、T-01/02）+ 雾底座（R-04/R-05）均在矩阵中显式出现；行 14/15/16/17/18 及行 10 的 Comprehensive 增强**全部复用既有约束编号**。**例外：行 19–22（音频侧）引用 `AUD-*` 音频域编号** —— control-manifest 现无任何音频约束，编号归属待裁决（见 §2 表后注）；这四行的约束**内容**已由 `design/audio/s3b-save-load-audio-spec.md` v1.0 定义并可执行，仅**编号体系**待并轨。
```

### 3.5 其余四处同步（一并给出，避免半截回填）

| # | 位置 | 动作 |
| --- | --- | --- |
| a | **L9 版本行** | `v0.3` → **`v0.4`**，摘要追加：「（S3-B · OOS-2 音频 a11y 收口：新增行 19–22 + 编号治理注）｜前版 v0.3…」 |
| b | **L11 上游依据** | 末尾追加：`；design/audio/s3b-save-load-audio-spec.md **v1.0** §1.7 音频可访问性基线（AUD-A1~A5）；docs/architecture/adr/adr-005-…md（Draft）` |
| c | **L178 之后（§5 下游衔接）** | 追加 bullet：`- **音频侧（新增，v0.4）**：行 20 的五路音量滑杆与「UI 音」开关属设置 UI + 持久化，**逻辑交程基岩**（持久化通道 `SaveManager.save_prefs("audio", …)` 已存在，只差 UI）；行 19/21/22 为规格纪律，由音频指导在 design/audio/ 维护，本文只做分级启用登记，**不复制取值**。` |
| d | **L184 之前** | 插入 v0.4 变更记录块（新版在前，沿用该文件惯例）：<br>`**v0.4 变更记录（Sprint 3 · S3-B OOS-2 音频 a11y 收口）**`<br>`\| 1 \| 矩阵表 \| 新增行 19–22（视觉同源 / 分路音量 / 不变调 / 不依赖音频区分）\| 音频规格 v1.0 §1.7、ADR-003、ADR-005(Draft) \|`<br>`\| 2 \| §2 表后 \| 新增「AUD-* 编号治理」注块 \| control-manifest 无音频约束（v0.2 全文核对）\|`<br>`\| 3 \| §3.3 \| 覆盖表增 4 行；**结论句改写**（原「未新增任何约束编号」已为假）\| 同上 \|`<br>`\| 4 \| §5 \| 新增音频侧下游衔接 bullet \| 行 20 逻辑归属程基岩 \|` |

---

## 4. OOS-3 · 音频子系统落地规格（给程基岩，E-1 ~ E-5 的施工蓝图）

> **这是 S3-B 唯一的阻塞项。** V-1~V-3 已证实：本项目**从未出过声** —— 无 `[audio]` 段、无 bus layout、无 `AudioStreamPlayer`、无音频资产、连 `res://arts/` 根目录都不存在。E-1~E-5 是**从零建音频子系统**，请按此估工，不要按"加两个音效"估。

### 4.1 E-1 · 目录

```
res://arts/audio/
  ui/            ← sfx_ui_*.wav        （S3-B：2 个文件）
  world/         ← sfx_foot_* / sfx_obj_* / sfx_guard_*   （空，后续批次）
  ambience/      ← amb_*.ogg           （空）
  music/         ← mus_*.ogg           （空）
  vo/            ← vo_*.ogg            （空，预留）
  audio_bus_layout.tres                ← E-2
```

`.gitignore` 不屏蔽 `*.wav` / `*.ogg` / `*.tres`，无 LFS 配置；两个资产合计 ≈ 31 KB，**直接 commit 即可**（V-17）。空目录 Git 不跟踪，建议只建实际有文件的 `ui/`，其余随批次生长。

### 4.2 E-3 · `project.godot` 的 `[audio]` 段

**插入位置：L9（`config/features=…`）之后、L11（`[autoload]`）之前。** 这不是随手选的位置 —— Godot 保存 `project.godot` 时按 section 名**字母序**归一化（`application` < `audio` < `autoload` < `renderers`），放这里可避免编辑器下次保存时产生无谓 diff。

```ini
[audio]

; S3-B (E11 / SAV-S5) — the project's first audio subsystem.
; Bus tree & world-mode presets: docs/architecture/adr/adr-005-audio-bus-architecture-and-world-mode-presets.md
; Full spec: design/audio/s3b-save-load-audio-spec.md §1.3 / §1.4 / §5.1
; mix_rate: Godot defaults to 44100. Every shipped asset is 48 kHz, so leaving
; the default silently resamples all of them at runtime.
buses/default_bus_layout="res://arts/audio/audio_bus_layout.tres"
driver/mix_rate=48000
```

**并在 `[autoload]` 段末（现 L18 `SaveManager=…` 之后）追加：**

```ini
; S3-B (E11 / SAV-S5). The audio layer must outlive the screen that triggers it:
; _end_load_fade() hides SCR_SLOTS at t=0.4s while the World bus is still being
; snapped to 0dB, and a cue must not be cut off when its host screen unloads.
; NOTE: src/core/audio_director.gd must have NO `class_name` — same Godot 4
; autoload-shadowing trap as save_manager.gd above.
AudioDirector="*res://src/core/audio_director.gd"
```

| 项 | 取值 | 说明 |
| --- | --- | --- |
| `audio/driver/mix_rate` | **`48000`** | 全部资产 48 kHz。**零回归风险** —— 当前无任何音频资产（V-3），没有东西会被这次改动影响 |
| `audio/buses/default_bus_layout` | `res://arts/audio/audio_bus_layout.tres` | 见 §4.3 |
| `audio/driver/output_latency` | **不设，留默认 15 ms** | 输出缓冲**只会让音频更晚**，永不更早 —— 而 AUD-F5 的容差正是「音频滞后 ≤40 ms 可接受、超前 0 ms 容忍」。默认值天然安全，动它没有收益 |
| autoload 顺序 | **`AudioDirector` 放在 `SaveManager` 之后** | 后续 a11y 批次的音量持久化要读 `SaveManager.save_prefs("audio", …)`；先注册的先 `_ready()` |

### 4.3 E-2 · `audio_bus_layout.tres` 全文（可直接落盘）

**路径：`res://arts/audio/audio_bus_layout.tres`**

```
[gd_resource type="AudioBusLayout" load_steps=2 format=3]

[sub_resource type="AudioEffectLowPassFilter" id="AudioEffectLowPassFilter_world"]
resource_name = "World LPF (ADR-005 D-2/D-7/D-8)"
cutoff_hz = 20500.0
resonance = 0.0
db = 1

[resource]
bus/0/name = "Master"
bus/0/solo = false
bus/0/mute = false
bus/0/bypass_fx = false
bus/0/volume_db = 0.0
bus/0/send = "Master"
bus/1/name = "World"
bus/1/solo = false
bus/1/mute = false
bus/1/bypass_fx = false
bus/1/volume_db = 0.0
bus/1/send = "Master"
bus/1/effect/0/effect = SubResource("AudioEffectLowPassFilter_world")
bus/1/effect/0/enabled = true
bus/2/name = "Music"
bus/2/solo = false
bus/2/mute = false
bus/2/bypass_fx = false
bus/2/volume_db = -8.0
bus/2/send = "World"
bus/3/name = "Ambience"
bus/3/solo = false
bus/3/mute = false
bus/3/bypass_fx = false
bus/3/volume_db = 0.0
bus/3/send = "World"
bus/4/name = "SFX_World"
bus/4/solo = false
bus/4/mute = false
bus/4/bypass_fx = false
bus/4/volume_db = 0.0
bus/4/send = "World"
bus/5/name = "Voice"
bus/5/solo = false
bus/5/mute = false
bus/5/bypass_fx = false
bus/5/volume_db = 0.0
bus/5/send = "World"
bus/6/name = "SFX_UI"
bus/6/solo = false
bus/6/mute = false
bus/6/bypass_fx = false
bus/6/volume_db = 0.0
bus/6/send = "Master"
```

**逐项说明（每个数字都有理由，请勿"顺手调整"）**

| 项 | 值 | 理由 |
| --- | --- | --- |
| **索引顺序** | Master(0) → World(1) → Music(2) / Ambience(3) / SFX_World(4) / Voice(5) → SFX_UI(6) | ★ **Godot 硬性要求：bus 的 `send` 目标索引必须小于自身索引。** 顺序不能随便改，否则布局加载失败或路由静默错乱 |
| `bus/1/effect/0` | `AudioEffectLowPassFilter`，`enabled = true` | ADR-005 D-2：ADR-003 的 lowpass/ducking **唯一挂点**。`enabled` 恒为 true —— 旁路靠把 cutoff 拉到 20500，**不靠切开关**（开关切换会咔嗒） |
| `cutoff_hz = 20500.0` | FLOWING 预设 = 旁路 | 20500 是 Godot `AudioEffectFilter.cutoff_hz` 的上限值 |
| `resonance = 0.0` | ADR-005 **D-8** | Godot 默认 **0.5**，会在 cutoff 处产生共振峰。700 Hz 的共振峰听感是一声持续中频哨音，直接踩 art-bible §1 调性禁区。**必须显式写 0.0** |
| `db = 1` | `FILTER_12DB`，ADR-005 **D-7** | 「隔一道门」不是「砌一堵墙」。24 dB/oct @700 Hz 会把世界床压成毫无可辨内容的闷响，方案 (c) 的意义（世界仍在，只是退到门后）随之消失 |
| `bus/2/volume_db = -8.0` | Music 标定 | 音乐是影子不是存在（规格 §1.3） |
| **Master / SFX_UI 效果链为空** | 强制 | ADR-005 D-4 / D-5。UI 音的滤波与空间感**全部烘焙进资产**；Master 任何动态处理都会压平瞬态、抬起底噪 |
| `bus/0/send = "Master"` | Master 自送 | Godot 对 0 号总线的 `send` 有时归一化为省略。**若编辑器回存后这一行消失，属正常，不影响语义**（Master 无上级） |

> **落地后请做一次 round-trip**：用编辑器打开工程 → Audio 面板确认七条总线与父子关系 → 不改任何值直接重存布局 → `git diff`。若 diff 只有格式归一化（如上面的 `bus/0/send`），说明属性名全对；若某个属性凭空消失，说明那个名字写错了被 Godot 丢弃 —— **这是发现拼写错误最快的方式**。

### 4.4 E-5 · `process_mode`（两种暂停机制下都正确的写法）

| 节点 | 数量 | Bus | `process_mode` |
| --- | --- | --- | --- |
| `AudioDirector`（autoload 根） | 1 | — | **`PROCESS_MODE_ALWAYS`** |
| `AudioStreamPlayer`（UI 池） | **3** | `SFX_UI` | **`PROCESS_MODE_ALWAYS`** |
| `AudioStreamPlayer`（环境床） | 1 | `Ambience` | **`PROCESS_MODE_ALWAYS`** |
| `AudioStreamPlayer`（音乐） | 1 | `Music` | **`PROCESS_MODE_ALWAYS`** |
| 世界音效播放器（后续批次） | — | `SFX_World` | 默认 `PAUSABLE`（**应当**随世界冻结） |

**为什么 `ALWAYS` 是硬要求**：control-manifest **T-03 写「用显式暂停（`paused` / `time_scale=0`）」，两者并列、至今未选定**（V-12 证实两种都还没实现）。若最终选 `get_tree().paused = true`，默认的 `PAUSABLE` 会让**存档成功音根本播不出来** —— 因为存档界面**只存在于暂停期间**。设 `ALWAYS` 在两种机制下都正确，因此**不必等 T-03 拍板**。

### 4.5 E-10 · CI 断言（把架构纪律变成会红的测试）

新增 `tests/unit/test_audio_bus_layout.gd`。headless（Dummy 音频驱动）下 `AudioServer` 仍可用、bus 索引仍可解析。

| # | 断言 | 守护的决策 |
| --- | --- | --- |
| 1 | `AudioServer.bus_count == 7`，且索引 0–6 名称依次为 `Master/World/Music/Ambience/SFX_World/Voice/SFX_UI` | D-1 |
| 2 | 路由：`World→Master`；`Music/Ambience/SFX_World/Voice→World`；**`SFX_UI→Master`** | **D-2**（`SFX_UI` 不在 World 下是整份规格的地基） |
| 3 | `volume_db`：Music `-8.0`，其余全 `0.0` | D-1 标定 |
| 4 | `World` 效果数 == 1 且为 `AudioEffectLowPassFilter` | D-2 |
| 5 | **`SFX_UI` 效果数 == 0** | D-4 |
| 6 | **`Master` 效果数 == 0** | D-5 |
| 7 | `AudioDirector.get_children()` 中**无 `Tween` 实例** | AUD-F2（禁止音频层持有自己的时间源）—— 把"同源驱动"从纪律变成断言 |

### 4.6 ★ 与 E-6（`_fade_sink` 第 4 个 sink）的依赖关系

**依赖方向**

| 关系 | 结论 |
| --- | --- |
| OOS-3（E-1/E-2/E-3/E-5）→ E-6 | **不依赖**。总线层可独立落地并独立通过 E-10 的 7 条断言 |
| E-6 → OOS-3 | **强依赖**。`set_load_fade(a)` 操作的就是 `World` bus 的 `volume_db`；没有 `World` bus，`begin/set/end_load_fade` 三个方法**没有落点** |
| A-1 / A-2 两个 cue 的播放 → E-6 | **不依赖**。`save_slots_screen.gd` L83 / L150 / L342–343 的 `_audio_sink` **已经预埋好**（V-7~V-9 逐行证实），`screen.set_audio_sink(AudioDirector.play_cue)` 签名完全匹配，**该文件零改动即可接通 5 个 cue 中的全部 5 个** |

**E-6 要改的四处（行号经 V-11 逐一复核，基于当前 825 行版本）**

| # | 位置 | 现有代码 | 插入 |
| --- | --- | --- | --- |
| 1 | **L150 `set_audio_sink()` 之后** | — | `set_fade_sink()` 定义 + `var _fade_sink: Callable = Callable()` |
| 2 | **L742 `_begin_load_fade()`**，L746 `_set_alpha(_fade, 1.0)` 之后 | `_fade.visible = true` / `_set_alpha(_fade, 1.0)` | `_fade_sink.call("begin", 0.0)` |
| 3 | **L788–789 tick 淡入块内、同一帧** | `if before == …LOADING_FADE and _fade != null and _fade.visible:` / `_set_alpha(_fade, 1.0 - world_fade_alpha())` | 改为 `var a := world_fade_alpha()` → `_set_alpha(_fade, 1.0 - a)` → `_fade_sink.call("tick", a)`。★ **必须读同一个 `a`**，不得各调一次 `world_fade_alpha()` |
| 4 | **L749 `_end_load_fade()`** 第一行、`visible = false` **之前** | `if _fade != null: _fade.visible = false` | `_fade_sink.call("end", 1.0)` |

**★ 施工顺序陷阱（本节最重要的一条，请程基岩裁决）**

E-6 与 E-11（`TimeController.enter_paused()/exit_paused()`，见 §7）之间存在一个**只在特定落地顺序下才出现**的可闻缺陷：

> **若 E-11 先落地而 E-6 未落地**：打开存档界面 → `World` 进 `PAUSED`（−12 dB / LPF 700 Hz）→ 玩家读档 → 屏幕卸载。此时**没有任何代码把 `World` 切回 `FLOWING`** —— 因为读档淡入（`end_load_fade()` 把 World 吸附到 0 dB）是这条路径上**唯一的复位点**，而它由 `_fade_sink` 驱动，也就是由 E-6 提供。
>
> **后果**：读档回到世界后，`World` 永久停在 −12 dB / 700 Hz。听感是「世界闷在门后再也没出来」，而且它**不会崩、不会报错、CI 也抓不到**，只会被某次试玩时"感觉整个游戏变闷了"发现。

**缓解（三选一，归程基岩裁量）**：
1. **E-6 与 E-11 同批落地**（推荐，最简单）；
2. E-11 的 `exit_paused()` 在读档路径上被显式调用 —— 但**当前 `save_slots_screen.gd` 无任何此类调用**（V-6 / V-12），需要额外接线，请确认由谁调；
3. E-11 暂不落地，`PAUSED` 保持未接线（则 ducking 不发生，但也不会卡住）。

> 换句话说：**E-11 单独落地是三种组合里唯一有害的一种。** 要么两个都上，要么都不上。

### 4.7 工程侧动作清单（对齐规格 §5.9，标注本次收口的增补）

| # | 动作 | 优先级 | 本次收口的增补 |
| --- | --- | --- | --- |
| E-1 | 建 `res://arts/audio/{ui,world,ambience,music,vo}/` | P0 | ⚠️ `res://arts/` **根目录也不存在**（V-4），需一并创建 |
| E-2 | 建 `audio_bus_layout.tres` 并在 `project.godot` 引用 | P0 | ✅ **全文已给**（§4.3），含 D-7 / D-8 两个新取值 |
| E-3 | `project.godot` 设 `mix_rate=48000` | P0 | ✅ **完整段落已给**（§4.2），含插入位置与字母序理由 |
| E-4 | 新建 `src/core/audio_director.gd` autoload（**不加 `class_name`**） | P0 | API 见规格 §5.5，本次无变更 |
| E-5 | 播放器 `PROCESS_MODE_ALWAYS`（世界音效除外） | P0 | ✅ 表已给（§4.4） |
| E-6 | `save_slots_screen.gd` 加 `_fade_sink` + 4 个插入点 | P0 | ✅ 行号已复核（§4.6）；⚠️ **新增施工顺序陷阱，须与 E-11 同批** |
| E-7 | 接线 `set_audio_sink(...)` + `set_fade_sink(...)` | P0 | `set_audio_sink` 侧**零改动即通** |
| E-8 | AUD-G1（cue 表 `base_gain_db ≡ 0`，`action_denied` 为别名） | P0 | 见 §2.3 纪律 1 |
| E-9 | AUD-R1 重触发阶梯 + `set_retrigger_ladder_enabled()` | P1 | — |
| E-10 | `tests/unit/test_audio_bus_layout.gd` | P1 | ✅ **7 条断言已给**（§4.5），新增第 7 条（无 Tween） |
| E-11 | `TimeController.enter_paused()/exit_paused()` | P1 | ⚠️ **见 §7 与 §4.6 施工顺序陷阱** |
| E-12 | asset-manifest 回填音频类目 | P2 | ✅ **回填包已给**（`asset-categories.md`），转林绘澄 |

---

## 5. OOS-4 · ADR-005 草案

**路径：`docs/architecture/adr/adr-005-audio-bus-architecture-and-world-mode-presets.md`**

> ⚠️ 派工单写的是 `docs/architecture/adr-005-*.md`。**实际惯例是 `docs/architecture/adr/` 子目录**（V-13：001~004 全在 `adr/` 下，`docs/architecture/` 根只有 `architecture.md` 与 `control-manifest.md`）。已按**实际惯例**落地，若主理人另有安排请指示移动。

**状态**：`status: Draft`（仓库惯例首字母大写，adr-003/004 均为 `Accepted`；语义等同派工单要求的 `draft`）。

**核心决策摘要**

| # | 决策 | 一句话 |
| --- | --- | --- |
| D-1 | 七条总线树 | `Master / World[Music, Ambience, SFX_World, Voice] / SFX_UI` |
| **D-2** | **ADR-003 的「全局」= 全局于「世界」** | lowpass + ducking 挂 **`World` group bus**，`Master` 保持完全干净 |
| D-3 | World 三预设 | `FLOWING 0 dB/20500 Hz` · `FOCUS −3.5 dB/1200 Hz` · `PAUSED −12 dB/700 Hz`，120 ms 缓动，三者互斥、均不动 `pitch_scale` |
| D-4 | `SFX_UI` 效果链恒为空 | UI 音的滤波与空间感全部烘焙进资产 |
| D-5 | `Master` 不挂限制器 / 压缩器 | 保护瞬态与留白；不过载由资产电平 + bus 标定的算术保证 |
| D-6 | 读档淡入载体 = `World` | 可"先打地板再切预设"，一次解决顺序问题 |
| **D-7** | World LPF 斜率 **12 dB/oct** | **新增裁决**（v1.0 未覆盖）：隔一道门，不是砌一堵墙 |
| **D-8** | World LPF resonance **0.0** | **新增裁决**：Godot 默认 0.5 会在 700 Hz 产生共振哨音，踩 art-bible §1 红线 |

**与 ADR-003 的关系**：**逐条核对，零推翻**。ADR-003 的四条决策内容（不自动变调 / 凝神不变调 / 仅轻微 lowpass+ducking / 未来 whoosh 手动 `pitch_scale` 不全局）**全部原样保留**；本 ADR 唯一动作是把**「全局」这个未消歧的词**钉死为「全局于世界」。ADR-003 保持 `Accepted`，无需改状态；建议落定后在其 §决策音频条目追加一行「实现位置见 ADR-005」。

**对暂停的影响**：ducking + lowpass（`World` −12 dB / LPF 700 Hz）。与 `FOCUS`（−3.5 dB / 1200 Hz）**互斥不叠加**，因为 `TimeController.mode` 是单值枚举。**T-03 机制未选定不阻塞本 ADR** —— 两种暂停机制对 bus 架构的要求完全相同，差异只在 `process_mode`（§4.4 已给两种都正确的写法）。

**未决项（ADR 内已登记 U-1~U-5）**：T-03 机制未选定 · `PAUSED` 死枚举 · D-7/D-8 须回写音频规格 v1.1 · control-manifest 无音频约束编号 · architecture §4 无音频预算行。**五条均不阻塞 ADR 落定。**

---

## 6. OOS-5 · `save_manager.gd` 无 `delete_slot()` —— 无动作

`save_slots_screen.gd` 在 L336–337 自己做 `DirAccess.remove_absolute()`（L2 持久化职责落在 L5 界面层）。**工程侧已在该处自行标注为 follow-up**，本次仅确认音频侧也看到了同一处，**不重复登记、不提新要求**。与音频无耦合。

---

## 7. OOS-6 · `PAUSED` 死枚举处理建议（给程基岩）

### 7.1 事实确认

| # | 事实 | 证据 |
| --- | --- | --- |
| 1 | `PAUSED` 在**全仓库 `.gd` 文件中只出现 1 次**，就是 L29 注释里的那个词本身 | `rg 'PAUSED' --glob '*.gd'` → 单条命中 `src/core/time_controller.gd:29` |
| 2 | 无 `enter_paused()` / `exit_paused()`，无任何 `mode = "PAUSED"` 赋值 | 同上 |
| 3 | **文件自身已经自相矛盾**：L6–8 的文件头文档块只列了 `FLOWING` 与 `FOCUS` 两个 bullet，**根本没提 `PAUSED`**；只有 L29 的行尾注释在承诺第三个状态 | Read `time_controller.gd` L1–29 |

> **问题的本质不是"多了一个枚举值"，而是"一句注释在承诺一个不存在的状态"。** 任何读这一行的人（音频、粒子 T-04、未来 UI 动效）都会以为可以 `match mode` 到 `PAUSED`，然后写出一段**永远不会执行**的分支。

### 7.2 裁决：**不要删除，标注 + 接线（两阶段）**

**为什么不能删** —— `PAUSED` 在**两份设计文档里有下游承诺**，删掉会制造文档/代码缺口：

| 文档 | 位置 | 承诺 |
| --- | --- | --- |
| `docs/architecture/control-manifest.md` | **T-03** | 「完全冻结：用显式暂停（`paused` / `time_scale=0`），非玩法常态。仅菜单/设置」 |
| `design/art/accessibility-matrix.md` | **行 10 Comprehensive** | 「凝神可长期锁定 + **显式暂停读场辅助（T-03）**」 —— 这是一条**已承诺给玩家的可访问性特性** |
| `design/audio/s3b-save-load-audio-spec.md` | §1.4 / §3 硬点 5 | World 预设 `PAUSED`（−12 dB / 700 Hz）由 `TimeController.mode` 驱动 |

删枚举 = 把这三条承诺同时变成孤儿。**保留并诚实标注**是唯一不制造新债的选项。

### 7.3 阶段 1（P0，纯注释，零行为变更）—— 建议 diff

```diff
--- a/src/core/time_controller.gd
+++ b/src/core/time_controller.gd
@@ -26,7 +26,17 @@ const USER_MIN := 0.1       # T-02 lower clamp (physics stability floor)
 const USER_MAX := 1.0       # T-01 upper clamp
 const FLOWING_SCALE := 1.0
 
-var mode := "FLOWING"       # FLOWING | FOCUS | PAUSED
+## L2 time mode. FLOWING and FOCUS are live and wired.
+##
+## ⚠ "PAUSED" IS DECLARED BUT NOT WIRED (verified S3-B, main 89dbffd):
+## nothing in this repository ever assigns it, and enter_paused()/exit_paused()
+## do not exist. Any consumer that branches on mode == "PAUSED" is writing dead
+## code until E-11 lands. Do NOT read the value list below as「已实现」.
+##
+## It is kept (not deleted) because three documents already promise it:
+## control-manifest T-03 (显式暂停), accessibility-matrix 行 10 Comprehensive
+## (显式暂停读场辅助), and design/audio/s3b-save-load-audio-spec.md §1.4
+## (World bus PAUSED preset, -12dB / LPF 700Hz).
+## Tracked: design/audio/oos-resolution.md OOS-6 · audio spec §5.7 (AO-2).
+var mode := "FLOWING"       # FLOWING | FOCUS | PAUSED(declared, NOT wired)
```

**同时建议修一处自相矛盾**（L6–8 文件头，只列了两个状态，与 L29 不一致）：

```diff
 #   - FLOWING : time_scale = 1.0 (normal play)
 #   - FOCUS   : time_scale = user_scale (default 0.25, eased ramp, V-06)
+#   - PAUSED  : declared only — see the `mode` docstring below. No code path
+#               sets it yet (E-11). control-manifest T-03 has not picked
+#               between get_tree().paused and time_scale = 0 either.
```

> 阶段 1 的价值：**零风险、零行为变更、五分钟**，但它把"一个会骗人的注释"变成"一条准确的说明"。在 E-11 落地前，这是把 OOS-6 的**危害**（诱导下游写死代码）降为零的最小动作。

### 7.4 阶段 2（P1 = E-11，真正接线）—— 建议形态

规格 §5.7 已比较过两个方案，此处只重申推荐并补一处**必须一并解决的接线缺口**：

| 方案 | 评价 |
| --- | --- |
| (i) UI 直调 `AudioDirector.set_world_mode("PAUSED")` | 可行，但把时间语义分散到 L5，违背 architecture §2「时间统一由 L2 管理」 |
| **(ii) `TimeController` 补口（推荐）** | 新增 `enter_paused()` / `exit_paused()`，**复用既有信号** `time_scale_changed(old, 0.0, "PAUSED")`。**零新增事件** ✅（不触 E01-S9 冻结）；音频只需订阅一次即同时拿到 FOCUS 与 PAUSED |

若采 (ii)，`AudioDirector` 的唯一订阅就是：

```gdscript
time_controller.time_scale_changed.connect(
	func(_old, _new, mode): set_world_mode(mode))
```

**★ 两个必须一并回答的问题（否则 E-11 会引入 §4.6 的可闻缺陷）**：

1. **谁调 `enter_paused()` / `exit_paused()`？** 当前 `save_slots_screen.gd` 里**没有任何暂停相关调用**（V-6 / V-12）。存档界面的打开/关闭路径上需要新增两处调用点，请确认由谁负责。
2. **读档路径上谁复位？** 读档时屏幕直接卸载，若 `exit_paused()` 未被调用且 E-6 也未落地，`World` 会永久停在 −12 dB / 700 Hz。**详见 §4.6 施工顺序陷阱 —— E-11 与 E-6 必须同批落地。**

3. **`enter_paused()` 用哪种暂停机制？** T-03 至今并列未选（`get_tree().paused` vs `time_scale = 0`）。**音频侧不需要这个答案**（§4.4 的 `PROCESS_MODE_ALWAYS` 两种都对），但 `enter_paused()` 的实现本身需要，属程基岩裁量。

---

## 8. 未回写项 —— 我自己的规格需要升 v1.1

诚实登记：本次收口产生了 3 处 v1.0 未覆盖或表述不完整的内容，须由我回写 `s3b-save-load-audio-spec.md` v1.1（**本次未改动该文件**，等主理人排期）。

| # | 项 | 位置 | 内容 |
| --- | --- | --- | --- |
| **C-1** | World LPF 斜率与 resonance | §1.3 | 补 D-7（12 dB/oct）/ D-8（resonance 0.0）—— v1.0 只说了"挂一个 `AudioEffectLowPassFilter`"，没给这两个参数，工程侧照 v1.0 施工会拿到 Godot 默认的 resonance 0.5，产生 700 Hz 共振哨音 |
| **C-2** | 度量副本 vs 出品资产的静音差异 | §1.5.3 vs §1.6 | §1.5.3 要求「被测文件首尾各补 ≥400 ms 静音」，§1.6 要求「文件起始静音 ≤5 ms」。**这两条描述的是不同的两个文件** —— 度量用**补过静音的副本**，出品用**≤5 ms 起音的正式资产**。v1.0 没说清，照字面读会以为自相矛盾 |
| **C-3** | `res://arts/` 根不存在 | §1.6 | v1.0 写「沿用 `res://arts/` 根」，实际该根目录在仓库中不存在（V-4）。措辞应改为「遵循 asset-manifest §1.3 **声明**的 `res://arts/` 约定（该目录树尚未落地）」 |

---

## 9. 需主理人裁决的冲突点

| # | 冲突 | 我的判断 | 需要的裁决 | 阻塞？ |
| --- | --- | --- | --- | --- |
| **F-1** | **`control-manifest.md` 无任何音频约束编号**（六族 30 条 + §7 五条 CI 断言，全部不含音频）。OOS-2 的四行若引 `AUD-*`，会破坏 accessibility-matrix §2 自述的「所有约束编号严格对应 control-manifest」纪律 | 推荐 **Option A**：程基岩在 control-manifest 新增 §8「音频硬约束」`A-01~A-05`，取值引用音频规格 §1.7；矩阵四行改引 `A-0N`。保持编号单一权威源 | **A（并轨）还是 B（豁免声明）** | 否（内容有效，仅编号待定） |
| **F-2** | **`res://arts/` 目录根本不存在**（V-4）。asset-manifest §1.3 的目录树是纯约定，我的规格 §1.6 建立在这个约定之上 | 非冲突，属"约定尚未落地"。`arts/audio/` 将是第一个真实子目录 | 确认 `res://arts/` 仍是既定资产根（若已改用别的根，我和林绘澄都要改） | 否 |
| **F-3** | **ADR 路径与派工单不符**：派工单写 `docs/architecture/adr-005-*.md`，实际惯例是 `docs/architecture/adr/`（V-13） | 已按**实际惯例**落到 `adr/` 子目录 | 确认位置（若要移动请指示） | 否 |
| **F-4** | **`architecture.md` §4 性能预算表无音频行**（V-16）。音频内存与同发语音数至今无架构级预算 | S3-B 实际占用 ≈ 31 KB PCM，**量级上零风险**。我在 `asset-categories.md` §7.3 提了一组建议上限（UI 常驻 ≤512 KB / 流式解码 ≤4 MB / UI 同发 3） | 是否要程基岩把音频行补进 §4 预算表 | 否 |
| **F-5** | **E-11 单独落地会产生可闻缺陷**（§4.6）：`World` 永久卡在 −12 dB / 700 Hz，不崩不报错、CI 抓不到 | 强烈建议 **E-6 与 E-11 同批落地**，或两个都不上 | 请在排期时把 E-6 / E-11 绑成一个工作项 | **是**（若排期把二者拆开） |
| **F-6** | **D-7 / D-8 是我在本次收口中新给的取值**，v1.0 规格未覆盖 | 已写进 ADR-005，须回写规格 v1.1（§8 C-1） | 是否现在就排 v1.1 回写 | 否 |

> **无一处需要推翻 v1.0 规格。** F-1/F-2/F-4 是**上游文档的空白**（音频此前不存在，没人为它留位置），F-3 是派工单笔误，F-5 是**新发现的施工顺序风险**，F-6 是我自己的补充。规格 §6.3 对 OOS-1/2/3/6 的四条描述经源码逐条证实，全部成立。

---

## 10. Handoff 清单（全部经主理人中转，本文作者未直接联系任何人）

### → 林绘澄（Art Director）

| # | 事项 | 材料 |
| --- | --- | --- |
| 1 | 把 4 个 patch 回填进 `design/assets/asset-manifest.md` | `design/audio/asset-categories.md` §1–§4（含精确插入行号 + 回填后自检清单） |
| 2 | ★ **A-3 / A-4 状态列必须保持「不产资产」** | `asset-categories.md` §7.2 纪律 1 / 本文 §2.3 |
| 3 | 新增 §7 时**不要重编号现有 §6** | `asset-categories.md` §4 的加粗提醒 |
| 4 | 把 4 行 a11y 行收口进 `accessibility-matrix.md`（升 v0.4） | 本文 §3.1–§3.5（8 处插入位置全部给了行号） |
| 5 | ⚠️ **§3.4 的结论句必须同步改写** —— 现文「未新增任何约束编号」加入新行后即为假 | 本文 §3.4 |
| 6 | ⚠️ 回填前先等 **F-1 编号归属裁决** | 本文 §9 |

### → 程基岩（Engineering Lead）

| # | 事项 | 材料 |
| --- | --- | --- |
| 1 | E-2 `audio_bus_layout.tres` —— **全文可直接落盘** | 本文 §4.3（含 7 条总线、索引顺序硬约束、D-7/D-8 取值、round-trip 验证法） |
| 2 | E-3 `project.godot` `[audio]` 段 + autoload —— **完整段落 + 插入位置** | 本文 §4.2（插在 L9 后 L11 前，字母序理由已给） |
| 3 | E-5 `process_mode` 表（两种暂停机制下都正确） | 本文 §4.4 |
| 4 | E-10 CI 断言 7 条 | 本文 §4.5（新增第 7 条：断言 `AudioDirector` 无 `Tween`） |
| 5 | ★ **E-6 / E-11 施工顺序陷阱** —— E-11 单独落地会让 World 永久闷在 −12 dB | 本文 §4.6 + §7.4 |
| 6 | OOS-6 `PAUSED` —— **不删，两阶段**：P0 注释诚实化（diff 已给）、P1 接线 | 本文 §7.3 / §7.4 |
| 7 | ADR-005 会签（`status: Draft`） | `docs/architecture/adr/adr-005-…md` |
| 8 | F-1：是否在 control-manifest 新增 §8 音频约束 `A-01~A-05` | 本文 §9 |
| 9 | E-4 `audio_director.gd` **不得加 `class_name`**（与 `save_manager.gd` 同一个 Godot 4 坑） | 规格 §5.1 / 本文 §4.2 注释 |

### → 主理人

- 裁决 **F-1**（编号并轨 A / 豁免声明 B）、**F-3**（ADR 路径）、**F-4**（音频进不进架构预算表）、**F-6**（v1.1 回写排期）。
- 排期时**把 E-6 与 E-11 绑成一个工作项**（F-5）。
- 确认 **F-2**（`res://arts/` 仍是既定资产根）。

---

*OOS-1~6 收口 v1.0 完成。本文作者产出规格文本三份（本文 · `asset-categories.md` · `adr-005-…md`），**未修改任何 `.gd`、未修改 `project.godot`、未修改 `asset-manifest.md` / `accessibility-matrix.md`、未执行任何 git 操作**。所有源码引用见 §0 自查记录，逐条可复现。*
