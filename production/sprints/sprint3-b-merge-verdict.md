# S3-B 合并裁定与 CI 真值核验记录

**批次**: Sprint 3 · S3-B（SAV-S5 手动存档/读档 UI）
**PR**: #10 `feat/s3-b` → `main`
**合并后 main**: `525cc7d`（merge commit），CI run `31023581583`
**裁定人**: 主理人（游承峰）
**实现**: engineering-lead-2（程基岩）
**日期**: 2026-08-05

---

## 一、CI 真值核验（主理人亲验，非采信自报）

原则：**不看 `conclusion`，只看 `gut_output.txt` 里的数字。** 本批恰好提供了这条原则为何必要的活证据。

| run | head | conclusion | Scripts | Tests | Passing | load-failure | risky | 判定 |
|---|---|---|---|---|---|---|---|---|
| `31021353902` | `79400c9` | **success** | 13 | 149 | 149 | **3** | 0 | ❌ **假绿** |
| `31022008459` | `1931f86` | success | 14 | 184 | 184 | 0 | 0 | ✅ 真绿 |
| `31023581583` | `525cc7d` | success | 14 | 184 | 184 | 0 | 0 | ✅ 真绿（合并后 main，1297 asserts）|

### 假绿的形成机制

`test_save_ui.gd` 存在 GDScript 解析错（`const X = preload(...)` 后直接调 `X.get_script_signal_list()`——该成员访问在 X 自身类命名空间解析，属解析期错误；`X.new()` 因构造器被特判才可用）。Godot 在 GUT 收集用例**之前**就丢弃了该文件，于是：

- GUT 拿到的是**旧基线** 13 scripts / 149 tests，全部通过；
- 35 个新测**一个都没跑**；
- 所有既有门（含 N-7 risky 门）逐一放行 → `conclusion=success`。

识破方式是核对用例数（149 = 合入前基线）。这类失败的危险之处在于：**日志里没有任何红色，汇总行干净得像模范生。**

> 该假绿由 engineering-lead-2 自行发现并主动上报，未等主理人核验。此为正确行为，记录在案。

---

## 二、三项裁定

### 裁定 1 · N-7b 闸门 —— **保留在本 PR**，附 follow-up

`ci.yml` 新增闸门（本 PR 超出原 brief 范围的改动）：

```yaml
if grep -qE 'Failed to load script|SCRIPT ERROR:.*Parse error' gut_output.txt 2>/dev/null; then
```

**保留理由**：事故与守卫同批合入才构成完整证据链；拆成独立 PR 反而丢失"为什么需要这道门"的上下文。

**双向实证**（主理人下载真实 artifact 用 ci.yml 原样命令验证）：

- 对假绿 run `31021353902`：**触发 exit 1** ✅（本可拦下）
- 对真绿 run `31022008459`：**静默** ✅（无误报）

**作用域正确**：只读 `gut_output.txt`、不读 `--import` 步骤输出。这是有意为之——本地复现显示 `--import` 前有 11 scripts/136 tests（4 failing + 37 risky），扫描阶段对未导入资源的解析错会造成持续假红。此决定予以确认，不得更改。

**发现的缺陷（follow-up F1）**：`SCRIPT ERROR:.*Parse error` 是**死分支，实测 0 命中**。Godot 实际输出为大写 E 的 `Parse Error`，`grep -E` 大小写敏感。本次全靠 `Failed to load script` 一支救场。

修正约束：真绿 run 中存在 **3 条非 parse 类的运行时 `SCRIPT ERROR`**（如 `Invalid operands 'String' and 'int'`），因此**绝不可裸匹配 `SCRIPT ERROR`**，必须保留 parse 限定词，否则 main 立刻误红。大小写不敏感版经验证对真绿 run 0 误报。

### 裁定 2 · `HUD_COLOR_FOCUS` 命名 —— **采纳实现者方案，一名一槽，不合并为别名**

brief 原指令要求改 `HUD_COLOR_ALARM_CB`，**该指令基于陈旧信息、无法执行**：该常量已于 Sprint 2 Batch C 退役（`hud_colors.gd` L42–L80 留有完整墓碑注释），真实的 C-06 代偿色是 `HUD_COLOR_DANGER_CB`，其值已是 `#F0C070`。

实现者改开 `HUD_COLOR_FOCUS` 独立常量，**裁定采纳**。理由：

- 焦点环属美术圣经 §9.4「输入可访问性」独立语义槽，**不受 C-06 治理**（O-1 裁决）；
- 二者当前同值 `#F0C070` 纯属巧合，登记为 **FLAG-L** 残余风险：色盲模式下被聚焦的损坏行，其焦点环与损坏徽章同色（1.00:1）；
- 塌缩可接受，因两条通道都不依赖色相：焦点环 0Hz + 矩形描边，损坏徽章 2.0Hz + 实心三角。频率与形状是永久编码（hud-a11y-signature v1.1 §5.1），C-05 三重编码不降级；
- **保持一名一槽**，是为了让未来的裁决能单独重指焦点环，而不会拖着 C-06 代偿色一起动。

> 实现者对上级指令的这次反驳是正确的。记录在案。

### 裁定 3 · O-3 Windows `rename_absolute` 窄窗 —— **接受**，附 follow-up

**接受理由**（采纳实现者注释中的论证）：

| | 崩溃后的槽位状态 | 性质 |
|---|---|---|
| 旧行为（`FileAccess.WRITE` 直写） | 存在、可读、半个 JSON → `parse_failed` | **静默数据损坏** |
| 新行为（staging + rename） | 缺失 → `read_slot()` 报空槽 | **诚实状态** |

Windows 下 Godot 的 `DirAccess::rename()` 会先删目标再重命名，留下"槽位缺失"的窄窗；这确实弱于 POSIX 的原子 rename，但**它把失败态从"戴着有效文件面具的静默损坏"换成了"诚实的空槽"**。完全关闭窄窗需要 `ReplaceFileW`，GDScript 够不到，属 GDExtension 范畴，不在本批。

**补强要求（follow-up F4）**：注意到 `_discard_staging` 在**每一条**失败路径都清理了 `.tmp`，因此能残留在磁盘上的 `.tmp` **只可能**是"已通过反向长度校验、只差一次 rename 就崩溃"的完整文档。这让启动时扫描孤儿 `.tmp` 并自动提升成为完全安全的操作，可把窄窗从"看起来丢了"进一步降级为"下次启动自愈"。

---

## 三、核验中意外发现的两颗哑弹（历史遗留，非本批引入）

在比对 CI 日志时，从真绿 run 里捞出 3 条运行时 `SCRIPT ERROR`。追查后确认其中两条对应**标着 `[Passed]` 却什么都没验证**的断言。

这一类假绿比 PR #10 那次更隐蔽：**它既不是 risky，也不是 load failure，N-7 与 N-7b 都抓不到——它就是明明白白的 `[Passed]`。**

### 哑弹 A · `tests/unit/test_budget_assert.gd:36`（读错文件）

```gdscript
const BUDGET_ASSERT := "res://tests/ci/budget_assert.gd"   # 读的是这个
# 但 C02_CARRIERS 定义在 tests/ci/budget_checks.gd:76 —— 另一个文件
assert_false("HUD_COLOR_ALARM_FILL" in ba_src.split("const C02_CARRIERS")[1]...)
```

split 找不到分隔符 → 返回单元素数组 → 取 `[1]` 越界 → 整条断言崩溃。该测试实际只打 2 条 Passed（源码有 3 条）。

**影响**：Batch D 那颗 N-12 反向守卫（证明 ALARM_FILL 是"有意排除"而非"疏忽遗漏"）**从未真正执行过**。

### 哑弹 B · `tests/unit/test_light_model.gd:128`（GUT API 误用 → 假通过）

```gdscript
func assert_signal_emitted_with_parameters(object, signal_name, parameters, index=-1)
#                                                                          ^^^^^ int，不是 message
```

调用方把一句中文说明当第 4 参传入 → `signal_watcher.gd:159` 的 `if(index == -1)` 拿 String 比 int 崩溃 → params 变 null → `diff_tool` 再崩 → 最终输出：

```
[Passed]:  Expected object <...>(light_model.gd) to emit signal
           [light_state_changed] with parameters [1, 1], got <null>
```

**`got <null>` 却标 `[Passed]`。** 信号参数从未被验证。

另外 3 处调用点（`test_event_bus.gd:93 / :110 / :154`）只传 3 参，是干净的。

### 处置

两颗均**不阻塞** PR #10 合并（皆为历史遗留）。但已升级为独立审计任务：**184 个 Passing 里究竟有多少是真的**，需要一个可信答案。见 Task #48。

---

## 四、Follow-up 派工

| ID | 内容 | 负责 | 分支 |
|---|---|---|---|
| F1 | N-7b 正则大小写死分支修正 + 反向断言 | engineering-lead-3 | `fix/s3-b-followup` |
| F4 | O-3 孤儿 `.tmp` 启动恢复（含"两者都存在"判定） | engineering-lead-3 | 同上 |
| F2 | 哑弹 A 修复（须验证修后真的会失败） | quality-lead-1 | `fix/s3-assertion-audit` |
| F3 | 哑弹 B 修复（须验证修后真的会失败） | quality-lead-1 | 同上 |
| AUDIT | 断言可信度全量审计（A/B/C/D 四类） | quality-lead-1 | 同上 |

并行冲突规避：quality-lead-1 不得触碰 `ci.yml` 与 `src/core/save_manager.gd`（engineering-lead-3 占用）。

---

## 五、已知风险与缓解

| 风险 | 等级 | 缓解 |
|---|---|---|
| FLAG-L：焦点环与 C-06 代偿色同值 `#F0C070`，色盲模式下 1.00:1 | 中 | 频率（0Hz vs 2.0Hz）+ 形状（矩形描边 vs 实心三角）双通道兜底；一名一槽保留未来重指能力 |
| Windows `rename` 窄窗致槽位瞬时缺失 | 低 | 失败态为诚实空槽而非静默损坏；F4 补孤儿恢复后自愈 |
| **断言可信度未知**——已确认至少 2 条假 Passed，总量待查 | **高** | Task #48 全量审计；要求给出"184 个 Passing 中有多少为真"的明确数字 |
| N-7b 正则死分支（当前靠另一支救场） | 中 | F1 修正；已实证闸门整体有效，非失效状态 |

---

## 六、遗留清理项

- PR #10 工作区约 19 个 `.gd.uid` 与 3 个脚手架脚本：沙箱 safe-delete 守卫拦截自动清理，需人工处理或单开 `.gitignore` 决策。
- `.tmp_gut/` 下主理人核验脚本（`verify_pr10.py` / `dump_gut.py` / `pr_status.py` / `merge_pr10.py` / `verify_main.py` / `main_ci.py`）为一次性工具，未纳入版本控制。
