# Release Checklist · ASHEN STEP《灰烬之步》Phase 7 — 内部封闭 alpha

**文档类型：** 发布清单（建议 + 门控判定）
**负责人：** 路远行（release-ops-lead）
**生成日期：** 2026-08-08
**发布定位：** 内部封闭 alpha（vertical slice，小范围封闭 playtest，不公开推广）
**分发渠道：** GitHub Release（本地 Godot export 打包 zip + Release 页 + changelog）
**本地化范围：** 仅 zh-CN（简体中文）
**评审强度：** solo（GHA runner 自 2026-08-07 宕机；本地 Godot 4.4.1 验证为权威，无 CI）
**发布区间：** `24fc2ef` → `5cf0431`

> ⚠️ **本轮为只读盘点 + 文档产出**：未改动任何 `src/` 生产代码；未实际执行 Godot export（export 由主理人后续执行）。本清单中的命令仅作为步骤记录。

---

## 1. 发布门控总判定（go / no-go）

| 门控项 | 状态 | 说明 |
|---|---|---|
| 版本号字段存在且已填 | ✅ PASS | `project.godot:8` 已升 `config/version="0.1.0-alpha.2"`（本次 hotfix commit；基线 `3c8054a` 首补）。 |
| `export_presets.cfg` 存在 | ✅ PASS | 仓库根已生成 Windows Desktop 预设（commit `3c8054a`），`--export-release "Windows Desktop"` 可引用。 |
| 本地 GUT 确定性绿 | ✅ PASS | 权威真数 `22 / 241 / 241 / 1588 / 0`，本地连跑两次确定性绿（主理人亲验）；Release 质量附件 `gut_output_0.1.0-alpha.2.txt` 已落盘。 |
| 已知缺口公示 | ✅ 已登记 | 5 项已知风险全部写入 `changelog.md` 与 `go-live.md`，不掩盖。 |
| 本地化范围 | ✅ PASS | 仅 zh-CN，无多语言框架（见 `localization.md`）。 |
| 资产保真（F-3） | ✅ PASS | `.wav.import` 边车已 force-add（commit `eb78d32`），新克隆不再静默回退 QOA。 |

**门控结论：GO · 发布质量门 PASS（内部封闭 alpha / prerelease）。** 本次为 hotfix `0.1.0-alpha.2`：非行为性启动日志修复（`look_at` → `look_at_from_position`，纯日志消除、对玩法零影响）+ 音频 headless 测试守卫（确定性绿 241/241/1588）；两个原 BLOCKER（版本字段 + `export_presets.cfg`）已于 `3c8054a` 清除。正式 QA 重签已按最小变更范围收敛为自动化门验证（GUT 确定性绿为权威）。非阻塞收尾：① 真机音频「真在播」仍需真机验证；② D2（A-0N 实机消费）继续递延。

> 注：发布区间 `24fc2ef→5cf0431`（changelog 覆盖 gameplay 改动）；`762aec1`/`3c8054a` 为发布准备文档与构建配置，非玩家可见 gameplay 改动，不进 changelog 区间。

---

## 2. 建议版本号

**建议版本：`0.1.0-alpha.1`**

**命名理由（内部 alpha 语义）：**
- `0.y.z` — 语义化版本主版本号为 0，表示正式 1.0 前的开发期；垂直切片属 pre-1.0。
- `alpha` — 内部预发布质量标识，对应"封闭 alpha、不公开推广"定位。
- `.1` — 本切片首个 alpha 构建序号；后续内部 alpha 递增末位（`0.1.0-alpha.2` …），不占用正式 patch 位。

**必须执行：** `project.godot` 当前**缺 `version=` 字段**，需在主理人导出前补入 `[application]` 段：
```ini
[application]
config/name="ASHEN STEP Sprint0"
version="0.1.0-alpha.1"          ; ← 新增（当前缺失）
run/main_scene="res://src/main/sprint0.tscn"
config/features=PackedStringArray("4.4")
```
> 另注（非阻塞，cosmetic）：`config/name` 仍为 "Sprint0"，而 HUD 文案已写"灰烬之步 · Sprint1"（`src/ui/hud_slice.gd:257`）。发布前建议统一命名口径，避免内测者困惑。

---

## 3. 构建步骤（本地 Godot 4.4.1 headless export）

> 因 GHA runner 宕机，CI 自动发布不可用；本地 Godot 4.4.1 console 验证为权威，构建产物由主理人手动导出后上传 GitHub Release。

**前置条件（BLOCKER 清除后才能跑）：**
1. `export_presets.cfg` 已存在（§6 补救）。
2. `project.godot` 已补 `version="0.1.0-alpha.1"`。

**导出命令（记录用，由主理人执行）：**
```bat
Godot_v4.4.1-stable_win64_console.exe --headless ^
  --export-release "Windows Desktop" ^
  build\ash-step-0.1.0-alpha.1-win64\ASHEN_STEP.exe
```
- 预设名 `"Windows Desktop"` 必须与 `export_presets.cfg` 中定义的 preset name **完全一致**（区分大小写与空格）。
- `--export-release`（非 `--export`）确保不带调试符号。
- 导出路径 `build\ash-step-0.1.0-alpha.1-win64\` 为本地暂存，导出后整体打包 zip（见 §4）。
- 若改用自定义预设名（如 `ash-step-win64`），命令与 cfg 须同步。

**导出后产物（预期）：**
- `ASHEN_STEP.exe`（含内嵌 PCK，或分离 `.pck` 取决于预设配置）
- 依赖数据目录（与 exe 同目录或 `_pck` bundle）

---

## 4. Artifact 命名规范

| 产物 | 命名 | 说明 |
|---|---|---|
| 导出目录 | `build/ash-step-0.1.0-alpha.1-win64/` | 本地暂存，不入库（建议在 `.gitignore` 加 `build/`）。 |
| 发布 zip | `ASHEN_STEP_0.1.0-alpha.1_win64.zip` | 内部 alpha 统一大写 + 下划线 + 平台后缀，便于 GitHub Release 排序。 |
| GitHub Release tag | `v0.1.0-alpha.1` | 与版本号同值。 |
| Release title | `ASHEN STEP 灰烬之步 · 内部封闭 alpha v0.1.0-alpha.1` | 明确"内部封闭"避免误公开。 |
| GUT 证据 | `gut_output_0.1.0-alpha.1.txt` | 导出前 GUT 真数落盘，随 Release 作为质量附件。 |

**zip 内容约定：** 仅含运行必需文件（exe + pck + 数据目录）；**不含** `addons/`（GUT 为开发期依赖，不应进发布包）、`tests/`、`docs/`、源码。

---

## 5. 验证项（本地 GUT 确定性绿）

**发布质量门（权威真数）：**
```
Scripts   22
Tests     241
Passing   241
Asserts   1588
Failing   0
Exit code 0   ("All tests passed!")
```

**GUT 计数核对（重要，透明登记）：**
- 本区间 `bd352f8`（音频 cue 测试硬化）记录 `22/239/239/1578/0`。
- 后续 `c5a2c78`（R-02 点光预算）新增 `tests/unit/test_budget_assert.gd`（+2 测试 / +10 断言）→ 累计 `22/241/241/1588/0`，与 Phase 6 D3（`playtest-report.md` §7.1）、D4（§8.3）最终验证报告、以及本任务规格一致。
- ⚠️ **on-disk `gut_output.txt` 当前为旧值 `239/1578`**，是 `c5a2c78` 之前的产物，**已过时**。发布前必须由主理人重新跑一次真实 GUT（见下）并落盘新证据，确认 `241/1588` 后再打 tag。

**复跑命令（记录用）：**
```bat
Godot_v4.4.1-stable_win64_console.exe --headless ^
  -s addons/gut/gut_cmdln.gd -gdir=res://tests/unit -gexit --verbose ^
  > gut_output_0.1.0-alpha.1.txt 2>&1
```
> 纪律（engineering-followups-spec.md）：**只看实时控制台真数，不唯 `gut_output.txt`**——该文件会假绿。连跑两次确认确定性绿（计数一致）后再放行。

---

## 6. `export_presets.cfg` 缺失补救步骤（RELEASE BLOCKER）

**现状：** 仓库根目录无 `export_presets.cfg`。Godot 4.x 的 `--export-release <preset>` 要求预设名在 `export_presets.cfg` 中已定义，否则构建立即失败。

**补救方案 A（推荐，GUI 编辑器生成，最稳）：**
1. 用 Godot 4.4.1 编辑器打开本项目。
2. 菜单 `Project → Export`（导出）→ `Add…`（添加…）→ 选 **Windows Desktop** → 预设名保持默认 `Windows Desktop`（与 §3 命令一致）。
3. 在预设中确认：
   - `Export Path`：`build/ash-step-0.1.0-alpha.1-win64/ASHEN_STEP.exe`（或留空，由命令行 `--export-release` 路径覆盖）。
   - 架构：x86_64（默认）。
   - `Embed Pck`：勾选（单 exe 便于分发）；或留分离 `.pck`。
   - `Export with Debug`：**不勾**（我们用 `--export-release`）。
4. 保存项目 → 编辑器在仓库根生成 `export_presets.cfg`。
5. `git add export_presets.cfg && git commit -m "build: 新增 Windows Desktop 导出预设（内部 alpha）"`——保证导出可复现。
   - 已确认 `.gitignore` 无 `export_presets` / `.cfg` 规则，不会被忽略。

**补救方案 B（无 GUI，手写 cfg，风险较高）：**
- 手写 `export_presets.cfg` 需严格匹配 Godot 4.4 ini 结构（`[preset.0]`、`name="Windows Desktop"`、`platform="Windows Desktop"`、`[preset.0.options]` 等）。手写易因字段缺失导致导出异常。**仅在无法启动编辑器时采用**，且导出后必须实机烟测一次。模板示例（节选，非完整）：
```ini
[preset.0]
name="Windows Desktop"
platform="Windows Desktop"
runnable=true
advanced_options=false
dedicated_server=false
custom_features=""
export_filter="all_resources"
include_filter=""
exclude_filter=""
export_path="build/ash-step-0.1.0-alpha.1-win64/ASHEN_STEP.exe"
patches=PackedStringArray()
encryption_include_filters=""
encryption_exclude_filters=""
seed=0
encrypt_pck=false
encrypt_directory_pck=false

[preset.0.options]
custom_template/debug=""
custom_template/release=""
variant/extensions_support=false
architectures/architecture="x86_64"
```
> 方案 B 仅作应急参考；正式发布前仍建议用方案 A 由编辑器生成权威 cfg。

**清除条件：** `export_presets.cfg` 已存在且 `git ls-files` 可见 → BLOCKER 解除。

---

## 7. 跨部门发布勾选清单

| 部门 | 项 | 状态 |
|---|---|---|
| **代码（程基岩）** | GUT `22/241/241/1588/0` 复跑绿；`export_presets.cfg` 生成；`version` 字段补入 | ☐ 待主理人执行 |
| **内容（文策渊）** | 垂直切片玩法内容齐备；非生产界面（存读档/设置）不挂载已确认 | ✅（按设计） |
| **商店/分发（路远行）** | GitHub Release 创建、zip 上传、Release 页文案含已知问题公示 | ☐ 待执行 |
| **法务/合规** | 内部封闭 alpha，无公开商店评级需求；第三方资产（GUT 为 dev-only 不进包）许可核对 | ✅（内部，低风险） |
| **社区（路远行）** | 内测名单分发、已知缺口沟通稿、反馈收集渠道就绪 | ☐ 待执行 |
| **音频（阮和鸣）** | 已知 gap（path-A foley / wire_audio 挂载点）已在 changelog 公示，不谎报完成 | ✅ 已登记 |
| **QA（严守真）** | D3/D4 已 VERIFIED-CLOSED 登记；已知风险写入 known-issues | ✅ 已登记 |

---

## 8. 回滚预案（热修/回滚）

- **发布包回滚：** GitHub Release 保留上一可用 tag；若 `v0.1.0-alpha.1` 出现阻断性问题，内测者回退至上一 alpha tag（或撤销该 Release，标记 Draft/删除）。
- **热修流程（简化但留审计）：** 修复 → 本地 GUT 复跑绿 → 本地 export 新 zip（`0.1.0-alpha.2`）→ 新 Release tag + 补丁说明 + 回滚预案随附。
- **字符串冻结：** 本次仅 zh-CN，无字符串表；冻结后除热修外不改玩家可见文案。
- 上线 / 热修 / 回滚等高影响动作须**人工审批**（用户掌舵）。

---

*本清单为发布准备文档，未执行任何导出或代码改动。BLOCKER 两项（version 字段、export_presets.cfg）清除后转 GO。*
