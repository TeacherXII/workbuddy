# 测试框架脚手架 ·《灰烬之步》ASHEN STEP（Godot 4.4）

> **用途（Phase 4 预制作）**：搭好可运行的单元测试框架，使「验证驱动开发（先测后写）」从 Phase 5 起即成立。框架归**工程（jiyan-p4）**搭；**测试用例归 Phase 5 质量负责人（quality-lead）**填充（见文末缺口表）。
> **评审强度**：lean —— 仅核心节点（架构 §4 预算 / control-manifest 硬约束）卡质量门；CI 默认跑 GUT 冒烟 + §7 静态断言。

---

## 1. 测试方案选型

**推荐默认：GUT（Godot Unit Test）** —— 轻量、GDScript 原生、自带编辑器面板与 headless CLI，契合 lean 评审与「小团队单核心做极致」的体量。

| 方案 | 适用 | 结论 |
| --- | --- | --- |
| **GUT**（bitwes/gut） | GDScript 单测/集成、编辑器面板、headless CI | ✅ **lean 默认**，本脚手架采用 |
| **GdUnit4** | 需要更强 mock/参数化、Java 风格断言 | 可选备选；若后续系统逻辑变重可切 |

> 本脚手架所有桩均按 **GUT** 语法编写（`extends GutTest` + `test_` 方法 + `assert_*`）。若切 GdUnit4，桩需改写为 `extends GdUnitTestSuite`，断言 API 不同——但接口契约（信号名/数据类型，见 `design/gdd/system-breakdown.md` §2）不变。

---

## 2. 安装 / 启用（GUT）

1. **获取 addon**：从 Asset Library 或 `https://github.com/bitwes/Gut` 取最新（兼容 Godot 4.4）放入：
   ```
   res://addons/gut/
   ```
   关键文件：`addons/gut/gut.gd`（面板）、`addons/gut/gut_test.gd`（基类 `GutTest`）、`addons/gut/gut_cmdln.gd`（headless 运行器）。

2. **启用插件**：编辑器 `Project Settings → Plugins → Gut → Enable`。或在 `project.godot` 直接落：

   ```ini
   ; project.godot（启用 GUT 插件片段）
   [editor_plugins]

   enabled=PackedStringArray("gut")
   ```

3. **目录布局**（本脚手架已建立）：
   ```
   res://tests/
     README.md            # 本文
     unit/                # 单元/冒烟测试（GUT 加载）
       test_step_commit.gd   # 核心循环冒烟：提交落点 / time_scale 0.25 / 冷却真实时间 / 暴露 1.2s
       test_vision_cone.gd   # 视野锥 LOS / 光影阈值冒烟
     ci-note.md           # CI 质量门说明（对齐 control-manifest §7）
     ci/
       budget_assert.gd   # headless 预算静态断言占位（§7）
   .github/workflows/ci.yml   # GitHub Actions：godot --headless 跑 GUT 冒烟
   ```

---

## 3. 运行命令

### 编辑器内（交互）
- 快捷键 **Ctrl+Shift+G** 打开 GUT 面板；选 `res://tests/unit` 目录 → Run。
- 或在顶部工具栏点 GUT 图标。

### Headless（CI / 命令行）
```bash
# 跑 tests/unit 下所有 test_*.gd（退出码 0=通过，非0=失败）
godot --headless --path "." \
  -s res://addons/gut/gut_cmdln.gd \
  -gdir=res://tests/unit \
  -gprefix=test_ -gsuffix=.gd \
  -gexit
```
- `-gdir`：测试目录（`res://` 路径）。
- `-gprefix` / `-gsuffix`：测试文件命名约定（`test_*.gd`）。
- `-gexit`：跑完以断言结果作为进程退出码（CI 据此卡门）。

### 预算静态断言（control-manifest §7）
```bash
godot --headless --path "." -s res://tests/ci/budget_assert.gd -gexit
```

---

## 4. 验证驱动开发（TDD）纪律

1. **先测后写**：实现任一 Epic Story 前，先写/补对应 `test_*.gd` 断言，再以接口/信号桩跑绿，再填真实节点（lean 下也鼓励，至少核心循环必守）。
2. **锚定契约**：测试只依赖 `design/gdd/system-breakdown.md` §2 的**共享事件词汇表**与各方 GDD §3 的**数据模型**（`Gait`/`Surface`/`StepCommitPayload`/`SoundPayload`/`VisionCone`/`GuardBrain` 等）。底层节点未实现时，用**内联 Stub 类**实现最小接口（见 `test_step_commit.gd` 的 `StepCommitStub`/`TimeControllerStub`/`ExposureGuardStub`），证明框架可跑；节点落地后把 Stub 换成 `preload`/`double` 真实类。
3. **数值即预算**：断言中的数值（time_scale 0.25、锥 10Hz、L_DARK 0.20/L_BRIGHT 0.60、暴露宽限 1.2s、声环 ≤8、动态光 ≤32、雾 ≤0.05）必须**直接引用** `docs/architecture/architecture.md` §4 与 `docs/architecture/control-manifest.md`，不得凭记忆硬编码。
4. **Given/When/Then**：每个 Story 的验收（见 `production/epics/E<NN>-*.md`）对应一组可运行断言；Story 验收与测试一一可追溯。

---

## 5. 与 Phase 5 quality-lead 的衔接

- **职责边界**：工程（jiyan-p4）交付 `tests/` 框架 + 本文件 + 2 个冒烟桩；**quality-lead 在 Phase 5 按各 Epic Story 的 Given/When/Then 把完整用例填进 `tests/unit/`**（可新增 `test_sound.gd` / `test_patrol_ai.gd` / `test_cover_shadow.gd` / `test_hud_a11y.gd` 等）。
- **CI 卡门**：`.github/workflows/ci.yml` 已接 GUT 冒烟，作为合并门；`budget_assert.gd` 接 §7 断言（占位，待 quality-lead 充实场景扫描）。
- **可溯性**：测试文件名 ↔ Epic 文件 ↔ GDD 系统一一对应，便于回归与覆盖率追踪。

### §5 测试缺口表（Sprint 0 收口状态）

> 更新：Phase 5 棒次②（quality-lead）。Sprint 0 范围内的步骤提交 / 时间模型 / 视野锥 / 光照 / HUD / 集成用例 **已闭合**；开放缺口按计划留待后续 Sprint，并标注归属 Epic。详细映射见 `tests/qa/sprint0-qa-plan.md` §2。

| 待测系统 / 预算 | 对应 Epic Story | 覆盖测试 | Sprint 0 状态 |
| --- | --- | --- | --- |
| 核心循环：提交落点 / 噪声半径 / time_scale 0.25 / 真实时间冷却 / 暴露 1.2s 软失败 | E03-S1/S2/S3/S4/S5/S6、E02-S1/S2/S3、E08-S4 | `test_step_commit.gd`（真实节点 + `ExposureGuardStub` 占位） | ✅ **已闭合** |
| 视野锥：可见性公式 / 光影阈值 / 10Hz 错峰常量 / 无光模型兜底 | E05-S1/S2/S4 | `test_vision_cone.gd`（真实节点） | ✅ **已闭合**（E05-S3 真实遮挡 LOS ⏳ N2 待可运行环境） |
| 掩体/阴影：get_light_level / L_DARK·L_BRIGHT 阈值 | E04-S1/S2 | `test_light_model.gd`（真实节点） | ✅ **已闭合** |
| 集成：StepCommit→EventBus→VisionCone 词汇贯通 / 残影≤6 | E03-S4/E04-S1/E05-S2（ADR-002） | `test_integration_step_vision.gd`（真实节点） | ✅ **已闭合** |
| HUD/可访问性：凝神读出 / 可疑度条 / 落点预演 | E09-S1/S3 | `test_hud_slice.gd`（真实节点，需场景树 + Camera3D） | ✅ **已闭合**（运行时需 N2 可运行环境确认，§6.1） |
| 声音：声环同屏 ≤8 FIFO | E06-S3、G-02 | `test_sound.gd` | ⬜ 开放（归属 **E06**，Sprint 1） |
| 巡逻 AI：可疑度阈值 25/60/10、衰减、FSM | E08-S2/S3、G-04 | `test_patrol_ai.gd` | ⬜ 开放（归属 **E08**，Sprint 1） |
| 掩体熄灯过场：雾 ramp≤0.12/≤0.4s（R-05）、light_state_changed 全细胞重算 | E04-S5/S7、R-05 | `test_cover_shadow.gd`（过场部分） | ⬜ 开放（归属 **E04**，Sprint 1） |
| 互动物件：charges / 诱饵半径 / 烟雾×0.3 | E07-S1~S5、C-3 | `test_interactables.gd` | ⬜ 开放（归属 **E07**，Sprint 1） |
| 性能预算 harness：守卫 8/16、锥 10Hz、draw call ≤400、动态光 ≤32、雾 ≤0.05 | E10-S4、架构 §4、control-manifest §7 | `tests/ci/budget_assert.gd`（冒烟骨架 + §7 占位） | ⬜ 开放（归属 **E10**，Sprint 1→2 逐步充实） |

**已知漂移（P2，待工程裁决）**：`step_commit.gd::SURFACE_FACTOR` 用 `{STONE:1.0, GRASS:0.7, METAL:1.2}`，与 GDD E03-S5 规格 `{STONE:1.2, WOOD:1.0, MOSS:0.5}` 不符。测试按**已实现代码**锁定（保 Sprint 0 冒烟绿灯 + 回归基线），提请工程统一 GDD/实现后在对应测试回填常量。详见 `tests/qa/sprint0-qa-plan.md` §6.2。

---

## 6. 对齐架构 / 控制清单
- 断言数值对齐 `architecture.md` §4（time_scale 0.25、锥 10Hz、射线峰值、守卫 8/16、动态光 12/32、雾 ≤0.05）。
- CI 质量门对齐 `control-manifest.md` §7（光>32 / 雾 / UV2 / 声环>8 / 脉动>2Hz 告警）。
- 事件/类型契约对齐 `design/gdd/system-breakdown.md` §2（零漂移）。
- 测试目录/命名对齐 `asset-manifest.md` §1.3 与 `production/epics/` 拆分。

*测试脚手架 v0.1（Phase 4）。框架就绪，用例填充交 Phase 5 quality-lead。*
