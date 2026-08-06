# S3-B 残留批 — 收口裁定

**范围**：OOS-1~6 决议 + C-06 口径下游收口 + 音频子系统从零落地
**成员**：阮和鸣（audio-director）→ 林绘澄（art-director）→ 程基岩（engineering-lead），串行
**合入**：`feat/s3b-residual` → main（`89dbffd` → `c00cc91`），hotfix `55b53a9`
**裁定**：**PASS**（质量门以本地 Godot 4.4.1 亲验为准；CI 因 GitHub runner 不可用未能补验，见 §4）

---

## 1. 三棒产出

### 阮和鸣 — OOS 决议
| 项 | 产物 | 状态 |
|---|---|---|
| OOS-1 | 音频资产类目清单（4 patch 回填包） | `design/audio/asset-categories.md` |
| OOS-2 | accessibility-matrix 音频行输入 | 交林绘澄落地 |
| OOS-3 | 音频子系统落地规格（E-1~E-12 施工蓝图） | `design/audio/oos-resolution.md` |
| OOS-4 | ADR-005 音频总线架构（D-1~D-8） | `docs/architecture/adr/adr-005-...md` |
| OOS-6 | PAUSED 死枚举分阶段处理建议 | 同上 §7 |

自查 V-1~V-17 逐条 Read/Grep 源码取证。**F-3 系误判**——ADR-005 确在 `adr/` 子目录（001~004 同址）。

### 林绘澄 — 文档/审计收口
- `design/art/accessibility-matrix.md` v0.3 → **v0.4**：新增行 19-22（视觉同源 / 分路音量 / 不变调 / 不依赖音频区分）+ 编号治理注 + 覆盖表 4 行
- `design/assets/asset-manifest.md`：OOS-1 回填（三格式行 / 四前缀 / 目录树 audio 分支 / 新增 §7）
- **Group 4 旧 C-06 口径清除**：`sprint2-story-candidates.md:80`、`E09-core-hud-a11y.md:58/66/100`、`E08-patrol-ai.md:123/126` 全部由 `#7A2E2E→#C8862F` / `HUD_COLOR_ALARM_CB` 改为 `#D64545→#F0C070` + 实心三角
- 新建 `design/art/ui-badge-corrupt-spec.md` + `design/art/staging/ui_badge_corrupt.svg`

### 程基岩 — 代码落地
- `project.godot`：`[audio]` 段 + `buses/default_bus_layout` + `mix_rate=48000` + `AudioDirector` autoload
- `arts/audio/audio_bus_layout.tres`：七总线（World→Master，Music/Ambience/SFX_World/Voice→World，**SFX_UI→Master**），World 挂 LPF(cutoff 20500 / resonance 0.0 / db 1)，Music −8dB
- `src/core/audio_director.gd`（新建）：`play_cue` / `set_fade_sink` / `set_world_mode`
- `src/ui/save_slots_screen.gd`：`_fade_sink` 接线（L98/191/212/440-441）+ **L675-679 bug 修复**（corrupt 分支误用 `HUD_COLOR_ALARM_CB` → 改 `HUD_COLOR_DANGER_CB`）
- `src/core/time_controller.gd`：`enter_paused()` / `exit_paused()`（**F-5 强制同批**，复用既有 `time_scale_changed` 信号）
- `docs/architecture/control-manifest.md` v0.3：§8 音频硬约束 A-01~A-05
- `tests/unit/test_audio_bus_layout.gd`（新建）：9 个 test func

---

## 2. ★ 拦下的假绿（本批最重要的一件事）

合入 main 后，`test_audio_bus_layout.gd:241` 被查出**解析期错误**：

```gdscript
for child in director.get_children():
    if child is Tween:          # Parse Error
```

Tween 在 Godot 4 已离开 Node 体系（改为 RefCounted），`get_children()` 元素的静态类型 `Node` 与 `Tween` 无共同后代，4.4 解析器直接拒绝该收窄：

```
SCRIPT ERROR: Parse Error: Expression is of type "Node" so it can't be of type "Tween".
ERROR: Failed to load script "res://tests/unit/test_audio_bus_layout.gd" with error "Parse error".
```

**后果不是红测试，是 N-7b 危害**：Godot 在 GUT 收集前丢弃整个文件，GUT 随后打出一份只含成功加载文件的干净汇总——

```
Scripts 15   Tests 196   Passing 196   Asserts 1351      ← 这正是合入前的旧基线
```

四道闸门（Failed / Risky / N-7b / 汇总可解析）**全部放行**，整套 9 个音频测试跑了零次却报绿。与 PR #10 事故同形。

讽刺的是，程基岩在该函数注释里已写明「Tween stopped being a Node in 4.0 and is now RefCounted」——事实认知正确，但仍写下了编译器无法接受的形式。

**修法**（`55b53a9`）：换成运行时 `child.get_class() == "Tween"`，保留可追溯意图，不要求编译器推理一个不可能的转型。

---

## 3. 质量门 — 本地亲验

环境：**Godot 4.4.1-stable**（与 CI pin 的 `barichello/godot-ci:4.4.1` 同补丁号）+ GUT v9.3.0，复刻 `ci.yml` 步骤 2+3。

| 判据 | 修复前 | 修复后 |
|---|---|---|
| Scripts | 15 | **16** (+1) |
| Tests | 196 | **205** (+9) |
| Passing | 196 | **205** |
| Asserts | 1351 | **1397** (+46) |
| Failing | 0 | **0** |
| Risky/Pending | 0 | **0** |
| N-7b 命中 | **2** | **0** |

**判据是计数增长，不是"全绿"。** +9 test / +46 assert 才是这套测试真跑了的证据；修复前的四门全 0 恰恰是假绿。

附加校验：
- 源码自污染扫描 `grep -rnE 'Failed to load script|SCRIPT ERROR:.*[Pp]arse [Ee]rror' tests/unit/` → **0 命中**（新增注释虽提及 `Parse Error`，但缺 `SCRIPT ERROR:` 前缀，不匹配闸门；且注释不回显进 GUT 输出）
- 机械守卫 `test_unit_test_sources_cannot_trip_the_n7b_gate` 已执行并通过
- `.tres` 生效取证：`test_bus_tree_is_the_seven_buses_in_d1_order` 首条断言 `[7] expected to equal [7]`，断言消息自带反证「1 = engine default, meaning buses/default_bus_layout did not resolve」——七总线布局确被引擎加载，未回落默认

---

## 4. CI 状态 — GitHub runner 不可用（非代码问题）

三个 run 全部同一形态：

| run | head | 结果 |
|---|---|---|
| 31121940207 | `04a0c13` (feat/s3b-residual) | failure |
| 31121954035 | `c00cc91` (main) | failure，rerun attempt 2 同样 failure |
| 31124196713 | `55b53a9` (main, hotfix) | failure |

诊断证据：`job.conclusion = cancelled`、`runner_name` **为空**、`steps` **为空数组**、排队 9~15 分钟后被取消。**runner 从未分配，工作流一步都没执行**。仓库无 self-hosted runner，账号 billing API 无权限查询。

据此：CI 的 failure **不构成质量门信号**。本批以本地亲验为权威判据。CI 待 GitHub 侧恢复后自动补验（下次任意 push 即可确认）。

---

## 5. 已知风险与缓解

| 风险 | 严重度 | 缓解 |
|---|---|---|
| `.wav` 资产尚未产出 | 中 | 运行时降级为静音，不崩溃；已列 Sprint 4 待办（阮和鸣） |
| `wire_audio()` 无生产调用点 | 中 | 调用点注释已在 `sprint0_bootstrap.gd` 钉死，待界面挂载 story |
| A-05 分路音量设置 UI 未实现 | 低 | 归入 a11y 批次，硬约束条文已先行落 `control-manifest.md` §8 |
| accessibility-matrix 行 19-22 编号待 renumber | 低 | F-1 = Option A，待 `control-manifest` §8 落地后统一改为 A-0N；治理注已写明 |
| 阮和鸣规格需升 v1.1 | 低 | F-6：D-7/D-8、度量副本 vs 出品资产、`res://arts/` 根不存在，三条待回写 |
| CI 未补验 | 中 | 本地同版本亲验已覆盖；runner 恢复后首次 push 自动确认 |

---

## 6. 流程改进（本批教训）

1. **本地 Godot 验证通道已建立**。`.tmp_gut/godot/` 存 4.4.1-stable console 版，与 CI pin 对齐。流程固化为 skill `godot-local-gut-verify`。
2. **今后成员自陈「本地无 Godot，未实跑」时，主理人必须在合并前本地补跑**，不得直接依赖 CI。本批正是因为跳过这一步，把带解析错误的测试合进了 main。
3. **判读铁律再加一条**：核对用例数较基线的增长量，是识破假绿的唯一可靠手段——四门全 0 不是通过条件。
