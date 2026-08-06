# Sprint 3 · S3-B Follow-up — 收口记录

**日期**：2026-08-05
**主线终态**：`main` = `9009125`
**CI 真值**（run 31094744849）：Scripts 15 / Tests 196 / **Passing 196** / Asserts 1351 / 0 Failed / 0 load-failure / 0 Risky / conclusion=success

S3-B 主体（PR #10，`525cc7d`）合并时挂了两项 follow-up 与三条 CONCERNS。本文件记录它们的关闭过程与结论。

---

## 1. 关闭清单

| 项 | 内容 | 归口 | 落地 |
|----|------|------|------|
| F1 | N-7b 正则大小写死分支 | 工程 | PR #12 |
| F4 | O-3 孤儿 staging 恢复（O-3b） | 工程 | PR #12 |
| F2 | 哑弹断言 A（test_budget_assert 读错源文件） | QA | PR #11 |
| F3 | 哑弹断言 B（test_light_model GUT 签名误用） | QA | PR #11 |
| — | 哑弹断言 C（test_hud_slice 相机未入树先定向） | QA | PR #11 |
| — | 断言可信度全量审计 + 静态 linter | QA | PR #11 |

两 PR **文件零交集**，独立合入：PR #11 → `1e8cc6f`，PR #12 → `9009125`。

---

## 2. F1 — N-7b 正则死分支

**问题**：闸门写作 `SCRIPT ERROR:.*Parse error`，而 Godot 4.4 实际输出的是首字母大写的 `Parse Error`。该分支自诞生起零命中，闸门全靠 `Failed to load script` 一支独撑。

**修复**：放宽为字符类 `SCRIPT ERROR:.*[Pp]arse [Ee]rror`，两种拼写同时覆盖。

**为什么不干脆裸匹配 `SCRIPT ERROR`**：健康的绿 run 里**本来就有**运行时 SCRIPT ERROR——测试故意走负路径，引擎的抱怨正是负路径被走到的证据（上一次绿 run 有 3 条）。裸匹配不会多抓 bug，只会在下一次推送时把 main 染红，然后教会所有人忽略这个闸门。`parse` 限定词是**承重结构**，`test_n7b_ignores_runtime_engine_errors` 把这条推理钉成了镜像断言。

**回归护栏**（`tests/unit/test_ci_gates.gd`，275 行）：闸门不是被复制进测试，而是**从 ci.yml 里现读现解析再编译**，所以测的是真家伙而非副本。六条测试分两组——必须抓到的（大写体 / 小写体 / loader 失败行）、必须放过的（运行时错误 / 只读 gut_output.txt）。

---

## 3. F4 — O-3b 孤儿 staging 恢复

**背景**：O-3 让 `write_slot` 走 staging + rename，把失败态从「槽位静默损坏」降级为「槽位诚实缺失」。但 Godot 的 `DirAccess::rename()` 在 Windows 上是先删目标再重命名，留下一个瞬时窄窗——此刻断电，`.json` 没了、`.tmp` 还在。该窄窗**已裁定接受**（彻底关闭需 `ReplaceFileW`，GDScript 够不到，属 GDExtension 范畴）。

**F4 让它自愈**：`recover_orphaned_staging()` 在读档路径上懒触发（`read_slot` / `has_checkpoint` / `_flush_write` / `scan_rows`），把合格的孤儿 `.tmp` 提升为正式存档。

三条设计约束，都是刻意的：

1. **复用 `read_slot` 同一验收门槛**——能解析成 JSON、是 Dictionary、`version == SAVE_VERSION`、`slot_id` 一致。不新造一套宽松标准，否则恢复机制自己会变成损坏源。
2. **两者皆存在时 `.json` 胜出**——POSIX 原子 rename 与 Windows 先删后移，两种语义都能推出同一结论：`.tmp` 和 `.json` 同时在，说明提升从未生效，`.json` 是完好的旧值。
3. **永不删除**——恢复失败的 `.tmp` 原地留存，供事后取证。

**覆盖**：`test_save_ui.gd` +5 测试（1 正向 + 3 反向 + 1 列表路径）。

---

## 4. QA — 三颗哑弹与审计

三个断言长期打印 `[Passed]`，实际什么都没验证。**这类假绿 N-7 与 N-7b 都抓不到**——既不是 risky，也不是加载失败，它们看起来完全健康。

| # | 位置 | 真相 |
|---|------|------|
| A | `test_budget_assert.gd:36` | `BUDGET_ASSERT` 指向 `budget_assert.gd`，但 `C02_CARRIERS` 定义在 `budget_checks.gd` — split 无分隔符 → `[1]` 越界 → 断言崩溃从未执行。**Batch D 那颗 N-12 反向守卫一直是哑弹。** |
| B | `test_light_model.gd:128` | `assert_signal_emitted_with_parameters` 第 4 参是 `index(int)` 不是消息，传了字符串 → `signal_watcher.gd:159` 的 `index == -1` 拿 String 比 int 崩 → params=null → 打出 `[Passed]: ... got <null>` |
| C | `test_hud_slice.gd` | `cam.look_at()` 在 `add_child` 之前调用报 "Node not inside tree"，相机朝向从未生效，瞄准预览断言的期望值与实测值同用一台没转向的相机 |

**新增 `tests/ci/assert_lint.py`**（330 行，自带 selftest）：A 类查 GUT 签名误用，B 类拿源码断言条数与运行时条数交叉比对。植入 7 个缺陷验证 linter 自身 → 7 抓 / 0 误报。修复后全库 A 类残留 **0**。

**审计头条**：已知假绿清零；B 类扫描剩 1 个误报（`test_save_ui.gd:701` 分支发散测试，早返路径与塌缩路径断言数天然不等，非 bug），已记入报告的「linter 局限」。

**linter 尚未接入 CI**，两个前置待解：容器内 python3 可用性、B 类对分支发散的误报。见 tech debt。

---

## 5. 过程中的一次自伤（值得记住）

PR #12 首跑 conclusion=failure，但 **0 个测试失败**。

根因：`test_n7b_gate_pattern_is_extractable_and_compiles` 用 `assert_ne(line, "")` 断言闸门的 grep 行。GUT 会把收到的实参回显进 `gut_output.txt`——于是闸门自己的触发串被写进了它自己要检查的文件，N-7b 匹配到，红。**测试全过，却被自己写的门枪毙。**

这与 Batch D 的 `[Risky]` 事故是同一个形状。定则已写入项目记忆：

> 任何会被 GUT 回显进 `gut_output.txt` 的文本，都不得含 CI 闸门的触发串。
> 修法 = 断言前先归约成 bool（GUT 就只打 `true`）；必须出现的字面量拆成两个 const 跨行拼接（grep 行导向，跨行即失效）。

`test_ci_gates.gd` 底部因此有一条机械守卫 `test_unit_test_sources_cannot_trip_the_n7b_gate`：逐行扫描整个 `tests/unit/`，任何一行匹配闸门即失败，且**只报 file:line 不报文本**——打印违规内容本身就是在犯同一个错。

修复过程中还交了第二次学费：第一版替换断言用了 `line.contains("N-7b")` 和 `pattern.contains("Parse Error")`，两个都是错的（marker 在注释行上、正则用的是字符类没有字面形式）。第二版改为**先用 Python 精确复刻 GDScript 辅助函数、对真实 ci.yml 跑一遍把断言证明出来**，再推送。一次通过。

---

## 6. 遗留（转入 tech debt）

- `assert_lint.py` 未接 CI（python3 可用性 + B 类误报）
- O-3 Windows 窄窗仍在（已裁定接受，O-3b 使其自愈；彻底关闭需 GDExtension）
- 工作区脚手架待清：`_eng_hold/`、`.audit_*`、`.tmp_gut/`

## 7. 下一批

S3-B 视觉资产（`ui_saveslot_row` / `ui_focus_ring`）与音效（存 / 读 / 确认 / 禁用）→ EC-7 规格补写 → S3-C Tech Debt TD-S1~S4。
