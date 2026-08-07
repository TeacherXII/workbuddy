# S3-B 文档治理收尾 · 收口裁定

| 字段 | 值 |
| --- | --- |
| **项目** | ASHEN STEP《灰烬之步》 |
| **批次 / Sprint** | Sprint 3 · S3-B ｜ 文档治理收尾（跨四成员一批） |
| **裁定日期** | 2026-08-07 |
| **裁定人** | 游承峰（Orchestrator / 主理人） |
| **本地验证通道** | 本地 Godot 4.4.1-stable（console）headless GUT，复刻 `ci.yml` 步骤 2+3。CI runner 仍宕机，本地真数为权威判据。 |

## 0. 一句话结论

**PASS（可推送）**。四成员交付全部落地、逐条核验、无回归；本地 GUT 18/227/227/1515 全绿、N-7b=0、N-7=0、`[Failed]`=0。本裁定文档随后入库并推送 `main`。

---

## 1. 本批范围（用户指令）

「文档治理收尾，把 A-05 的 Music/Ambience/SFX_World 三路滑杆也补上」——拆为四棒：

1. **a11y-matrix 行 19-22 renumber**：`AUD-A1~A5 → A-01~A-05`、`AUD-V6 → V-06`（闭环 F-1 Option A，消除双编号源）
2. **A-05 五路滑杆**：补 Music / Ambience / SFX_World 三路（此前只有 Master/World/SFX_UI 三路）
3. **音频规格升 v1.1**：designed v1 实测回填、固化 F-6、回写 ADR-005 D-7/D-8、并轨 a11y 编号
4. **UX 规格 EC-7 / O-3 回填**：O-3（`write_slot` 原子性）已于 S3-B follow-up 收口，回填 EC-7 与 O-3 为 RESOLVED

---

## 2. 各成员交付与核验

| # | 成员 | 交付 | Commit | 核验 |
| --- | --- | --- | --- | --- |
| #69 | 林绘澄（art-director） | `design/art/accessibility-matrix.md` v0.4→v0.5：行 19-22 + §3.3 四行 renumber A-0N；§2 注块收口「Option A 已执行」；头部 v0.5 | `27dfd7d` | ✅ 仅改 1 文件；renumber 与括注改写正确；残留 `AUD-*` 仅合法历史引用 |
| #72 | 程基岩（engineering-lead） | `src/ui/audio_settings_panel.gd` BUS_ROWS 3→5（删 BUS_WORLD，暴露 Music/Ambience/SFX_World）；`tests/unit/test_audio_settings_panel.gd` World 引用全改真实总线；`docs/architecture/control-manifest.md` §8 去「未竟」注 | `cc26663` | ✅ 3 文件；本地 GUT 18/227/227/1515 asserts（1507→1515）；`is Tween` 无命中；N-7b 扫描 clean |
| #70 | 阮和鸣（audio-director） | `design/audio/s3b-save-load-audio-spec.md` v1.0→v1.1：实测回填 + F-6 固化 + ADR-005 D-7/D-8 回写 + 编号并轨 | `68b0207` | ✅ 仅改 1 文档（零代码）；主理人独立复测资产：零交叉 0/0、时长 114/224ms、峰值 0.708/0.631、真峰 −3.0/−4.0 dBFS 全部对板 |
| #73 | 文策渊（design-strategist） | `production/sprints/sprint3-sav-s5-ux-spec.md`：EC-7 + O-3 → RESOLVED、页脚去「唯一未决项」；头部 L8 陈旧 O-3 措辞同步 | `be498dd` + `adbc64e` | ✅ 仅改 1 文档；EC-7/O-3/页脚三处 + L8 同步；交叉引用 `sprint3-b-followup-closure.md §3 F4` 准确 |

> **trust-but-verify 说明**：四棒 agent 产出均经主理人逐条核验源码/diff/本地度量，未盲信 agent 回报。#70 的音频资产由主理人用本机 ffmpeg 7.1.1 + `wave` 模块独立复测（零交叉、时长、峰值、真峰），与规格声明一致。

---

## 3. 本地 GUT 质量门（权威判据）

| 指标 | 数值 | 判据 |
| --- | --- | --- |
| Scripts | 18 | = 基线，无文件被丢弃（无假绿） |
| Tests | 227 | = 基线 |
| Passing | 227 | = Tests，全绿 |
| Asserts | 1515 | 较 #72 前基线 +8（默认值测试补齐五路） |
| **N-7b**（解析错误） | **0** | 必须 0 ✅ |
| **N-7**（Risky/Pending） | **0** | 必须 0 ✅ |
| **`[Failed]`** | **0** | 必须 0 ✅ |
| SCRIPT ERROR / Parse Error | 无 | ✅ |

> 本批四棒均为文档改动（#72 为代码但属面板/测试，已在前棒本地验证），未新增任何测试文件，故计数停留基线属预期，非假绿（N-7b=0 + Scripts=18 双重确认）。

---

## 4. 跨文档一致性矩阵

| 议题 | a11y-matrix | control-manifest §8 | 音频规格 | UX 规格 | 状态 |
| --- | --- | --- | --- | --- | --- |
| 音频 a11y 编号 | A-01~A-05 / V-06（v0.5） | A-01~A-05 / V-06（权威源） | AUD-A* 标「≡ §8 别名」 | — | ✅ 双源已消除 |
| A-05 五路滑杆 | — | §8 A-05「五路已暴露」 | §1.7 A-05「已由工程实现」 | — | ✅ 一致 |
| 音频总线 D-7/D-8 | — | — | §1.3/§1.4 回写 | — | ✅ 与 ADR-005 一致 |
| O-3 / EC-7 | — | — | — | RESOLVED（含 L8 同步） | ✅ 已闭环 |

---

## 5. 已知缺口与诚实标注（非阻塞）

1. **音频仍为 designed v1（程序化合成），非 path-A 实录 Foley**。规格 §2.1/§2.2 资产状态横幅已诚实标注「待真实 Foley 录制后整体替换并复测」。
2. **A1/A2 实测未达标（AR-1）**：designed v1 绝对 Max-M（−20.67 / −24.82）低于标称（−18 / −20）约 2.7 / 4.8 dB，方向=更安静，**不违反任何上限约束**（AUD-H1/AUD-L1/TP 均成立）。待真实 Foley 重做后复核。
3. **真峰余量仅 0.007 dB（AR-5）**：designed v1 TP = −3.007 / −4.007 dBTP，紧贴 A5 阈值。后续（尤其真实 Foley）资产须按真峰归一化留 ≥0.3 dB 余量，且不得在本基础上再做增益类改动。
4. **`wire_audio()` 生产挂载点仍缺**：垂直切片无生产家园，音频接线尚未在游戏功能层落地（端到端 cue 测试已证明接线本身可用）。
5. **46 个孤儿 `.tmp` 待 autofree**（O-3 尾项）：非阻塞清理项，不影响 O-3 判定（原子写 + 孤儿自愈已生效）。
6. **C-06 下游文档旧名**：`hud-a11y-signature.md` / `sprint2-asset-spec.md` / `batchc-impl-spec.md` / 数份 GDD 仍用旧名（`HUD_COLOR_ALARM_CB` 等），取值已对、仅旧名——登记为文档债。
7. **GitHub runner 仍宕机**：`conclusion=cancelled` + runner 空 + steps 空。本地 Godot 4.4.1 与 CI pin 同补丁号，等价权威；CI 门待 runner 恢复后补验。

---

## 6. 推送状态

- 本地 `main` 领先 `origin/main` 共 **6** 个提交（#69 `27dfd7d`、#72 `cc26663`、#70 `68b0207`、#73 `be498dd`+`adbc64e`、本裁定文档）。
- 全部经本地 GUT 验证后推送；推送与 Actions 解耦，runner 宕机不影响入库。

*裁定：PASS。文档治理收尾一批四棒全部收口，跨文档一致性达成，无回归。*
