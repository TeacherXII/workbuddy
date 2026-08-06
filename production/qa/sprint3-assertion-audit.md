# Sprint 3 · S3-B 收口 — 断言可信度审计

> 触发：主理人核验 PR #10 的 CI 日志时，从**真绿 run** 里捞出 3 条运行时 `SCRIPT ERROR`，
> 追下去发现两条标着 `[Passed]` 的断言其实什么都没验证。
> N-7 / N-7b / N-11 / N-12 都假设"打了 `[Passed]` 的断言真的跑了、真的比了"——
> 这次证明这个假设会漏：假绿可以是 `Passed` 而非 `Risky`，现有门全抓不到。
>
> 基线：`Scripts 14 / Tests 184 / Passing 184 / 0 failing / 0 risky`（main `525cc7d`）。

## 1. 为什么做这次审计

PR #10 第一次 CI 是**假绿**（`conclusion=success` 但 35 个新测零跑，打出旧基线 149），
靠用例数核对识破。但更隐蔽的一层是：即便测试真的跑了，断言本身也可能失效却仍打 `Passed`。
本次在日志里肉眼撞见两颗这样的"哑弹"，遂升级为全量审计，回答一个问题：
**184 个 Passing 里，有多少是真的？**

## 2. 审计方法

| 类别 | 方法 | 工具 |
|---|---|---|
| **A 类** · GUT API 参数误用 | 静态扫描：比对 GUT v9.3.0 各 `assert_*` 的真实签名，源码里把断言消息传给非 `text` 形参即报警 | `tests/ci/assert_lint.py` `scan_a_class` |
| **B 类** · 断言在求值前崩溃蒸发 | 交叉比对：每个 `test_*` 函数的**源码断言条数** vs **gut_output.txt 运行时条数**，不相等即嫌疑 | `assert_lint.py` `scan_b_class` |
| **C 类** · 恒真 / 自证循环 | 人工 + 结构审查：期望值与实测值来自同一表达式、或测试根本没走到真实代码路径 | 人工 |
| **D 类** · 断言从未执行 | 提前 return / 被跳过 / 分支永不进入 | 人工 + B 类交叉比对辅助 |

> 数字对不上比人眼读代码可靠得多——这是本次的核心方法论。

## 3. 发现清单

### 3.1 真实哑弹（3 个，已全部修复）

| ID | 文件:行 | 类 | 根因 | 修复 |
|---|---|---|---|---|
| **F2** | `tests/unit/test_budget_assert.gd:36` | B | 常量指向 `budget_assert.gd`，但 `const C02_CARRIERS` 实际在 `tests/ci/budget_checks.gd:76`。`split()` 无分隔符 → 返回单元素数组 → `[1]` 越界 → 整条断言崩溃，**从未执行**。Batch D 那颗 N-12 反向守卫一直是空炮。 | 改读 `BUDGET_CHECKS`；加**解析守卫** `assert_eq(c02_parts.size(), 2)`（声明再被挪走就当场红，而非静默蒸发）；补正向外推 `assert_true("HUD_COLOR_CARRIER" in ...)` 堵"空白名单让扫描静默绿"的洞。 |
| **F3** | `tests/unit/test_light_model.gd:128` | A | GUT `assert_signal_emitted_with_parameters(obj, sig, params, index=-1)` 第 4 参是 **index(int) 不是消息**，传了字符串 → `signal_watcher.gd` 内部崩溃 → params=null → 打出 `[Passed]: ... got <null>`。**信号参数从未被验证。** | 删掉第 4 个 String 参数；该断言不接受自定义消息，意图改在注释里说明。 |
| **C-1** | `tests/unit/test_hud_slice.gd` | C | `cam.look_at()` 在 `add_child` **之前**调用，节点未入树 → 硬报错变静默 no-op，测试从未真正跑过带角度的相机（恒等朝向通过）。 | `look_at()` 移到 `add_child_autofree` 之后；新增**独立**检查"改瞄准点预览必须移动"（`assert_ne(_hud._preview.position, first_pos)`），堵死"镜像自证"——旧断言两边都调 `cam.unproject_position` 减同一半尺寸，相机怎么转都报 delta=0。 |

### 3.2 误报（linter 局限，非 bug，1 个）

| ID | 文件:行 | 类 | 说明 |
|---|---|---|---|
| **B-FP** | `tests/unit/test_save_ui.gd:701` `test_focus_ring_and_danger_substitute_survive_a_hue_collapse` | B（误报） | B 类扫描报"5 跑 vs 6 源"。实际是**分支测试**：`if separation >= MIN` 走早返回分支（1 条断言），`else` 走塌缩分支（5 条）。当前 `HUD_COLOR_FOCUS == HUD_COLOR_DANGER_CB == #F0C070`（同色），只跑塌缩分支的 5 条。源码 6 条断言跨两个分支，单次运行只能执行一个分支——linter 不做控制流分析，误判为蒸发。line 707 那条是对"未来颜色被重新分开"的防御性断言，当前状态不会进该分支，**属正常死分支，不是 bug**。 |

## 4. 分类计数

| 类 | 真实发现 | 已修 | 误报/局限 |
|---|---|---|---|
| A | 1 | 1 ✅ | 0 |
| B | 2（F2 + F3 的 SCRIPT ERROR 表现） | 2 ✅ | 1（B-FP 分支发散） |
| C | 1 | 1 ✅ | 0 |
| D | 0 | — | 0 |

- **A 类静态全量扫描（`assert_lint.py --tests-dir tests`）：修复后 0 findings** → 全代码库无残留的"消息误传非 text 形参 / 元数溢出"类哑弹。
- B 类扫描在**修复前**真实 run 上抓出 4 条，其中 3 条是真实哑弹（已修），1 条是上述误报。

## 5. 头条答案：184 个 Passing 里有多少是真的？

- **确认假绿：3 个**（F2 / F3 / C-1），现已全部改为真正验证。
- A 类静态扫描 **0 残留**。
- B 类扫描唯一剩余标志是已知误报（分支发散），非真实缺陷。
- **结论**：修复后，已知假绿已清零；184 个 Passing 中，3 个从"假"变"真"，其余 181 个始终为真。
- **诚实边界**：B 类扫描不做控制流分析（分支发散会误报，也会漏掉藏在分支里的真蒸发）；带循环 `for/while` 的测试被 deliberately 跳过（`loops > 0` 不报）；D 类"分支永不进入"需人工 review。因此"100% 无残留哑弹"无法靠本次扫描绝对证明，但**已知假绿已全清，且 A 类静态门已就位**作为回归防护。

## 6. 防再犯机制

`tests/ci/assert_lint.py`（330 行，本次新增，未接 CI）：

- **A 类**：GUT v9.3.0 签名表 + 静态扫描，抓"消息误传非 text 形参 / 元数溢出 / 未知断言"。自带 selftest（植入 7 个缺陷全抓、0 误报），"不能自己失败的 linter 就是我们要抓的 bug"。
- **B 类**：源码断言条数 vs gut_output.txt 运行时条数交叉比对，抓蒸发 / 测试内 SCRIPT ERROR。
- `looks_like_message` 特意拒绝"以字面量开头的表达式"（避免 10 个误报）。

### 接入状态与局限（待办）

- **本次未接 CI**：避免在工程侧 F1 改 `ci.yml` 的同一文件上制造合并冲突；且 B 类有分支发散误报（B-FP），直接接会阻塞 main。
- **后续 PR**（两个前置条件满足后）：
  1. 确认 `barichello/godot-ci:4.4.1` 容器含 `python3`（在步骤 3 之后加一步 `python3 tests/ci/assert_lint.py --tests-dir tests --gut-log gut_output.txt`，并对 python3 缺失做 `::warning::` 降级）。
  2. B 类需补控制流感知（或显式标注分支测试）以消除 B-FP 类误报，否则门会被良性分支打红。

## 7. 给主理人的建议

1. 本次审计价值不在修那 3 条，而在给出可信答案：**已知假绿已清零，A 类静态门就位**。
2. `assert_lint.py` 接 CI 前先解决 python3 可用性与 B 类分支误报，否则门会自伤。
3. 后续新增测试强制走 A 类静态扫描（pre-commit 或 CI），把"断言误用"挡在合入前。
