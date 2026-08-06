---
status: Draft
date: 2026-08-06
deciders: 阮和鸣（提案 / 音频指导）· 程基岩 + 主理人（待裁决）
tags: [audio, bus-layout, lowpass, ducking, rtwp, pause, a11y]
upstream: docs/architecture/adr/adr-003-realtime-with-pause-time-model.md（本文澄清其音频条款）；design/audio/s3b-save-load-audio-spec.md v1.0 §1.3/§1.4/§3 硬点 5；docs/architecture/control-manifest.md T-03/V-06；design/gdd/systems/rtwp-time-model.md §5；design/art/art-bible.md §1 调性禁区
---

# ADR-005 音频总线架构与世界模式预设：lowpass/ducking 挂 World，不挂 Master

## 状态
**Draft（草案 · 待主理人 + 程基岩裁决）**

> 本 ADR **不推翻 ADR-003 的任何决策内容**，只钉死其音频条款的**实现位置**。ADR-003 保持 Accepted，无需改状态；本文落定后建议在 ADR-003 §决策的音频条目追加一行「实现位置见 ADR-005」。

## 上下文

ADR-003 的音频条款原文（L23）：

> **音频单独处理**：`Engine.time_scale` 不自动变调音频。设计选择：凝神期间**不变调**（更轻、且避免光敏 / 眩晕），仅施加轻微**全局** lowpass + ducking 增强「凝神」质感；如未来要 whoosh 慢音，对关键 `AudioStreamPlayer` 手动 `pitch_scale`，不全局。

写下这条时项目尚无任何音频实现，「全局」是一个**未被消歧的词**。截至 main `89dbffd`，源码事实（已逐项 grep 复核）：

| 事实 | 证据 |
| --- | --- |
| `project.godot` 无 `[audio]` 段、无 bus layout、无 mix_rate | `project.godot` 全文 24 行，仅 `[application]`/`[autoload]`/`[renderers]` |
| 全仓库 `src/` 零 `AudioStreamPlayer` / 零 `AudioServer` 调用 | `rg 'AudioStreamPlayer|AudioServer'` 在 `src/`、`tests/` 零命中 |
| 全仓库零音频资产，`res://arts/` 目录**根本不存在** | `git ls-files` 对 `arts/`、`*.wav`、`*.ogg` 零命中 |
| `get_tree().paused` / `process_mode` 全仓库无人使用 | 同上 grep 零命中 |

即：**S3-B 是本项目第一次真正出声**，「全局」这个词到今天才第一次需要有确切的实现位置。

**若「全局」被字面实现为挂在 `Master`**，后果是确定的、可推演的：

1. 存档 / 暂停界面下（World 预设 `PAUSED` = LPF 700 Hz），UI 音会被**二次滤波**。存档成立音「嗒」的可辨识内容在 400–900 Hz 接触带（音频规格 §2.1.2 / M-1），被 700 Hz 砍掉大半；失败音本就 LPF 900 Hz，再过一道 700 Hz 会变成一坨无法辨认的低频糊。
2. 凝神期（LPF 1200 Hz）任何 UI / 字幕提示音同样被闷掉。
3. **这是唯一一处 ADR-003 与 S3-B 音频规格会真正冲突的地方**，而冲突源自**实现位置**，不是**决策内容**。

## 决策

### D-1 · 总线树（七条，父子固定）

```
Master                      ← 零处理（无限制器 / 无压缩器 / 无 EQ）
├─ World                    ← ★ ADR-003 的 lowpass + ducking 唯一挂点
│   ├─ Music
│   ├─ Ambience
│   ├─ SFX_World            ← 足音 / 声环 / 机关 / 守卫
│   └─ Voice                ← 守卫警示语（diegetic）；当前为空，预留
└─ SFX_UI                   ← ★ 零效果器（强制）。存档 / 失败 / 拒绝
```

| Bus | 名称字符串 | 标定电平 | 效果链 |
| --- | --- | --- | --- |
| Master | `"Master"` | `0.0 dB` | **空** |
| World | `"World"` | 模式驱动（D-3） | `AudioEffectLowPassFilter` ×1（索引 0） |
| Music | `"Music"` | `-8.0 dB` | 空 |
| Ambience | `"Ambience"` | `0.0 dB` | 空 |
| SFX_World | `"SFX_World"` | `0.0 dB` | 空 |
| Voice | `"Voice"` | `0.0 dB` | 空 |
| SFX_UI | `"SFX_UI"` | `0.0 dB` | **空（强制）** |

### D-2 · ADR-003 的「全局」= 全局于「世界」

> **lowpass + ducking 效果链挂在 `World` group bus。`Master` 保持完全干净。**

`SFX_UI` 挂在 `Master` 下、**不在** `World` 下，因此在任何世界模式下都不吃世界处理。

### D-3 · World 三预设（互斥，由 `TimeController.mode` 驱动）

| mode | `World` volume | `World` LPF cutoff | 用途 |
| --- | --- | --- | --- |
| `FLOWING` | `0.0 dB` | `20500 Hz`（= 旁路） | 常态玩法 |
| `FOCUS` | `-3.5 dB` | `1200 Hz` | 凝神（ADR-003） |
| `PAUSED` | `-12.0 dB` | `700 Hz` | 暂停 / 存档界面 |

- **不变调**：三个预设**都不动 `pitch_scale`** —— ADR-003 该条原样保留。
- **不硬切**：模式切换 **120 ms** 缓动，判据「任何单帧内 bus 增益变化 ≤ 3 dB」（V-06 的听觉对偶）。
- **旁路方式**：`FLOWING` 用「cutoff 拉到 20500 Hz」而**非**切 `enabled` 开关 —— 开关切换会产生咔嗒。

### D-4 · `SFX_UI` 效果链恒为空

UI 音的滤波（LPF 2.2 k / 900 Hz）与空间感（RT60 ≤ 0.25 s）**全部烘焙进资产**。理由：可离线度量、零 CPU、且不会被后续有人调 bus 参数悄悄改掉。

### D-5 · `Master` 不挂限制器 / 压缩器

本作美学建立在瞬态与留白上。任何 Master 动态处理都会在最需要「一下」的时刻把它压平，并让安静段落抬起底噪。总和不过载由**资产电平天花板 + bus 标定值的算术**保证（音频规格 §1.5），不由处理器兜底。

### D-6 · 读档淡入的载体是 `World`，不是 `Ambience`

0.4 s 视听同源淡入操作 `World.volume_db`。若只抬 `Ambience`，Music 会在 t=0 以全电平硬切进场，且 `World` 从 `PAUSED` 切回 `FLOWING` 这一步会在可闻电平上发生（"揭盖"感）。把淡入放在 `World` 上可以「先打地板（−60 dB）再切预设」，一次解决顺序问题。

### 新增裁决（v1.0 音频规格未覆盖，本 ADR 首次给出）

| # | 项 | 取值 | 理由 |
| --- | --- | --- | --- |
| **D-7** | `World` LPF **斜率** | **12 dB/oct**（`AudioEffectFilter.db = 1` / `FILTER_12DB`） | 「隔一道门」而不是「砌一堵墙」。24 dB/oct @700 Hz 会把世界床压成毫无可辨内容的闷响，破坏 §硬点 5 方案 (c) 的全部意义（世界仍在，只是退到门后） |
| **D-8** | `World` LPF **resonance** | **0.0** | Godot `AudioEffectFilter.resonance` 默认 0.5，会在 cutoff 处产生共振峰 —— 700 Hz 的共振峰听感是一声持续的中频哨音，直接踩 art-bible §1 调性禁区 |

> D-7 / D-8 须回写音频规格 §1.3（升 v1.1），否则两份文档对 World LPF 的描述不完整。

## 备选

| 方案 | 结果 | 裁定 |
| --- | --- | --- |
| **(a) 挂 `Master`（「全局」的字面读法）** | UI 音在暂停 / 凝神下被二次滤波，存档音辨识度归零 | ❌ 本 ADR 存在的理由 |
| **(b) 不建 group bus，逐叶子 bus 各挂一个 LPF** | 4 份效果器实例、4 份 CPU、4 处可能被改歪的参数；且淡入要同时驱动 4 条总线，D-6 的"先打地板"无法原子完成 | ❌ |
| **(c) 不用 bus 效果，运行时逐 `AudioStreamPlayer` 设 filter** | Godot 无 per-player filter；只能靠 `pitch_scale` 或换流，前者被 ADR-003 明令禁止 | ❌ 技术上不成立 |
| **(d) `SFX_UI` 也挂在 `World` 下，靠 `bypass_fx` 豁免** | `bypass_fx` 是**整条链**旁路且不可缓动，切换即硬切；且把"UI 不吃世界处理"这条纪律寄托在一个布尔开关上，太脆 | ❌ |
| **(e) 挂 `World`（本文决策）** | UI 干净、世界可整体调度、淡入单点驱动、CI 可静态断言 | ✅ **采纳** |

## 与 ADR-003 的关系（逐条核对：全部保留，零推翻）

| ADR-003 音频条款 | 本 ADR 的处置 |
| --- | --- |
| `Engine.time_scale` 不自动变调音频 | ✅ 原样保留（陈述事实） |
| 凝神期间**不变调** | ✅ 原样保留，并强化为三预设**都**不动 `pitch_scale`（D-3） |
| 仅施加**轻微 lowpass + ducking** | ✅ 原样保留，并给出可施工取值（D-3：−3.5 dB / 1200 Hz） |
| **「全局」** | ⚠️ **本 ADR 唯一动作**：消歧为「全局于世界」，实现位置 = `World` group bus（D-2） |
| 未来 whoosh 慢音对关键 player 手动 `pitch_scale`，不全局 | ✅ 原样保留，本 ADR 不触及 |

> **一句话**：ADR-003 说"做什么"，ADR-005 说"挂在哪"。前者不变，后者补齐。

## 对暂停（T-03）的影响

- 暂停 / 存档界面采用 **ducking + lowpass**（`World` −12 dB / LPF 700 Hz），而非「原样继续播」或「完全静默」。完整三方案权衡见音频规格 §3 硬点 5。
  - 「完全静默」被否的关键理由：响度是相对的，把背景抽空等于把 −18 LUFS-M 的 UI 音**在相对电平上抬高约 30 dB**，直接破坏「反馈是质地不是公告」的立场。
- **与 `FOCUS` 不冲突**：`TimeController.mode` 是单值枚举，`FOCUS` 与 `PAUSED` 互斥，`−3.5 dB/1200 Hz` 与 `−12 dB/700 Hz` 是**同一条效果链上的两个预设**，永远不相乘。
- **T-03 机制未钉死不阻塞本 ADR**：control-manifest T-03 写「用显式暂停（`paused` / `time_scale=0`）」，两者并列未选定。两种机制对 bus 架构的要求**完全相同**；差异只在 `process_mode`（若选 `get_tree().paused = true`，`AudioDirector` 及其全部播放器必须 `PROCESS_MODE_ALWAYS`，否则存档界面里的 UI 音根本播不出来）。音频规格 §5.3 已给出在**两种机制下都正确**的写法。

## 后果

**正向**
- UI 音在任何世界模式下保持干净、可辨识 —— 这是 S3-B 五个 cue 中 5 个能否被听清的前提。
- 世界整体可被一个句柄调度（淡入、ducking、静音），读档淡入得以单点原子驱动（D-6）。
- 声明式 `audio_bus_layout.tres` 可 diff、可被 CI 静态读，音频架构因此能进 CI（见下）。

**负向 / 风险**
1. **多一层 group bus 的混音开销**：可忽略（Godot 的 bus 求和是 SIMD 内存加法，7 条总线在任何目标硬件上都不构成成本）。
2. **`Voice` 挂在 `World` 下是一个有前提的决定**：当前 VO 只有守卫警示语（世界内），应当随世界被 lowpass / duck。**若未来出现非世界内的旁白或系统语音**，须另开 `Voice_UI` 挂在 `SFX_UI` 同级，**不得**改动本条。
3. **本 ADR 的正确性依赖「谁来设置 `PAUSED`」**，而截至 `89dbffd` **无人设置**（见未决项 U-2）。不补则 D-3 的 `PAUSED` 预设永远不触发。

**CI 保障（建议随 D-1 一并落地）**
新增 `tests/unit/test_audio_bus_layout.gd`，headless（Dummy 音频驱动）下 `AudioServer` 仍可用、bus 索引仍可解析。断言：

| # | 断言 |
| --- | --- |
| 1 | 7 条总线存在，索引与 D-1 顺序一致 |
| 2 | 父子路由正确：`World→Master`；`Music/Ambience/SFX_World/Voice→World`；`SFX_UI→Master` |
| 3 | 标定 dB 与 D-1 表一致（Music `-8.0`，其余 `0.0`） |
| 4 | `World` 效果数 == 1 且为 `AudioEffectLowPassFilter` |
| 5 | **`SFX_UI` 效果数 == 0**（D-4 的可执行形式） |
| 6 | **`Master` 效果数 == 0**（D-5 的可执行形式） |

> 这是把音频架构纳入 CI 的最低成本方式：D-2/D-4/D-5 全部从"文档里的纪律"变成"会红的断言"。

## 未决项

| # | 未决 | 归属 | 阻塞本 ADR？ |
| --- | --- | --- | --- |
| **U-1** | **T-03 暂停机制**（`get_tree().paused` vs `Engine.time_scale = 0`）未选定 | 程基岩 | **否** —— 两种机制对 bus 架构要求相同，仅影响 `process_mode` |
| **U-2** | **`PAUSED` 是死枚举**：`src/core/time_controller.gd` L29 注释里有它，全仓库无人赋值，也无 `enter_paused()`/`exit_paused()`。不补则 D-3 的 `PAUSED` 预设不触发 | 程基岩 | **否**（架构可先落，接线后生效）。处理建议见 `design/audio/oos-resolution.md` OOS-6 |
| **U-3** | **D-7 / D-8（LPF 斜率与 resonance）是本 ADR 首次给出的取值**，音频规格 v1.0 未覆盖 | 阮和鸣回写 v1.1 | 否 |
| **U-4** | **`control-manifest.md` 无任何音频硬约束编号**（R/T/V/C/X/G 六族无一条覆盖音频）。音频规格的 `AUD-*` 编号目前不属于任何架构级清单 | 程基岩 + 主理人 | 否，但影响 accessibility-matrix 的编号治理（见 `oos-resolution.md` OOS-2 冲突 F-1） |
| **U-5** | **`architecture.md` §4 性能预算表无音频行**（无音频内存 / 同发语音数预算） | 程基岩 + 主理人 | 否。S3-B 实际占用 ≈ 31 KB PCM，量级上无风险；建议在音频批次扩大前补 |

## 联动
- 上游决策：`adr-003-realtime-with-pause-time-model.md`（本文澄清其实现位置，不改其内容）。
- 完整音频规格与全部 `AUD-*` 约束：`design/audio/s3b-save-load-audio-spec.md` v1.0（§1.3 总线 / §1.4 预设 / §3 硬点 5 论证）。
- 施工蓝图（`project.godot` 段落 + `audio_bus_layout.tres` 全文 + CI 断言）：`design/audio/oos-resolution.md` §OOS-3。
- 硬约束：`control-manifest.md` T-03（显式暂停）、V-06（禁硬切 → 听觉对偶为 120 ms 缓动）。
