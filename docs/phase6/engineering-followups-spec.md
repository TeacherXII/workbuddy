# Phase 6 工程待决项修复规格（R-02 / D3 / F-3）

> 主理人汇编自三份已落盘报告，提炼根因、修复口径、验收标准与文件清单。
> 全部归 `engineering-lead`（程基岩）实现；lean 评审级别，非阻塞。
> 来源：`docs/phase6/perf-report.md`（R-02）、`docs/phase6/playtest-report.md`（D3）、`docs/phase6/audio-polish.md`（F-3）。

## 通用纪律（铁律）
- 本地 Godot 4.4.1 console 跑 GUT：**只看实时控制台真数，绝不只看 `gut_output.txt`**（该文件会假绿）。
- 每项改完跑一遍确认 `Scripts 22 / Tests 239 / Passing 239 / Asserts 1578 / Failing 0 / exit 0`；三项全做完**连跑两次**确认确定性绿。
- commit 到 main（用户全权委托），中文 message 按项分述；回传 commit hash + 真数 + 改动清单 + 是否触动 `src/` 生产逻辑。
- **红线**：不破 D1 已锁红线（`restore_checkpoint()` 零参、`make_slot` 字段约束、`SaveManager` 纯函数）；R-02 只 WARN-ONLY 不引入运行时拒绝；F-3 只 force-add 资产元数据，不改音频生产代码。

---

## R-02 · INSTANCE_CAP 与实时点光预算未联动

### 根因（perf-report.md:79-87, 95）
`INSTANCE_CAP=16`（interactable）与 R-02（实时点光 ≤12 MVP / 32 Tier2）、G-02（声环 VFX ≤8）只在关卡作者层约束，**无运行时拒绝/告警**。
最坏情况：MVP 船 = 16 个 LIT 互动物（各占 1 实时光）+ 8 守卫提灯 = **24 实时光 > R-02 MVP(12)**，但 `INSTANCE_CAP` 远未触发 → R-02 被静默突破。Tier2 船 = 16 + 16 = 32 贴 R-02 Tier2 天花板。`sound_ring_emitter_count()` 可达 16 > G-02(8) 软语义。

### 修复口径（WARN-ONLY，不阻断）
1. 仿 `tests/ci/budget_assert.gd` 的 WARN-ONLY 模式，新增**加载期/CI 记账断言**：
   - 汇总实时光数 = `InteractableRegistry` 实时光（**先核实 `realtime_light_count()` 是否存在**；若不存在，在 `interactable_registry.gd` 补一个只读方法返回实时光数）+ 活守卫提灯数（`guard_spawner.live_guards()` 计数）。
   - 按 tier（MVP/Tier2）超 R-02(12/32) 即 `push_warning`（**不阻断 spawn**）。
2. 把 `INSTANCE_CAP` 与 R-02/G-02 在**记账层**联动（仍不阻断，保持 lean）。逻辑预算 G-01~G-05 已硬约束，无需额外动作。

### 验收
- 不阻断运行时；超阈仅告警。
- 新增断言**不导致任何 GUT 失败**（WARN-ONLY 不算失败）。
- 建议补一条测试：构造超阈数据，断言 `push_warning` 被调用（或至少不报错）。

---

## D3 · 退出时 32 orphan + 资源泄漏

### 根因（playtest-report.md:81）
32 GUT orphans + "ObjectDB instances leaked at exit" + "2 resources still in use at exit"。GUT note **排除 pre-run / GUT-freed orphans**；`test_interactables.gd` 已证明生产 RefCounted `leaked_count()==0`（**零生产泄漏**）。yan 判定：**NO (verify)** —— 疑似 harness-only，发布前需 `--verbose` 确认。

### 修复口径（先验证后修）
1. 用 `Godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests/unit -gexit --verbose` 跑，抓取 orphan/leak 追踪（模式见 `local_gut.txt:5557-5569`）。
2. 分类：GUT harness 自身（autoload、测试节点未 free）vs 生产代码真实泄漏。
3. 若发现**生产节点泄漏** → 修复（queue_free / free 或 RefCounted 生命周期）；若确认**全为 harness-only** → 标记 D3「已验证关闭」，在 `playtest-report.md` 或 tech-debt 登记，**不强制加断言**（lean）。

### 验收
- `--verbose` 追踪证据落盘（回传贴关键行）。
- 若修复：GUT 仍 `22/239/239/1578/0`、exit 0；退出资源计数改善或文档确认 harness-only。
- **不得为消除 harness orphan 而削弱测试 teardown 真实性**。

---

## F-3 · `.wav.import` 未版本化

### 根因（audio-polish.md:111, 125, 151）
`.wav.import` 被 `.gitignore` 忽略（`*.import`），新克隆 / CI 重新导入时静默回退有损 QOA。当前本地不触发。

### 修复口径（主理人裁定：提交边车）
- GHA runner 宕、CI 不跑 → CI PCM 断言无运行环境；优先**提交 `.wav.import` 边车**保资产保真。
- 执行：用 Glob 定位项目内所有 `**/*.wav.import`，`git add -f`（force-add 被忽略文件），**单独 commit**。
- 注：runner 恢复后，再补一条 CI 断言 WAV 为 PCM（可选后续，**不在本次**）。

### 验收
- `git ls-files` 可见 `.wav.import`；不破坏 GUT（`22/239/0`）。
- 风险极低。

---

## 提交与回传
- 建议按 R-02 / D3 / F-3 **分三个 commit**（message 中文，便于追溯），最后由主理人统一 push。
- 回传：每个 commit 的 hash + GUT 真数（连跑两次一致）+ 改动/新增文件清单 + 是否触动 `src/` 生产逻辑。
