# Sprint 2 · Batch C — 实施记录（E09 无障碍完整包 Tier2）

- **Task ID**：S2-BATCH-C
- **分支**：`plan/sprint-2`
- **实施者**：程基岩（engineering-lead）
- **引擎**：Godot 4.4（Forward+ / GDScript 4）
- **口径权威**：`docs/architecture/control-manifest.md` v0.2 · `design/art/hud-a11y-signature.md` v1.0
- **验证状态**：本地无引擎，全部为**静态代码审查 + API 签名核对**。首轮 CI 为唯一真实验证点。

---

## 1. Story 覆盖与落点

| Story | 控制项 | 模型侧（产出） | 消费侧（应用） | 出口测试 |
|---|---|---|---|---|
| E09-S5a | C-05 / C-06 / C-07 | `a11y_settings.gd` 四态枚举 `ColorBlindMode` | `hud_colors.gd::danger_color/danger_icon`；`hud_slice.gd` ALERT 边框、暴露边框与图标 | `test_colorblind_enum_maps_danger_color` |
| E09-S5b | T-01 / T-02 / V-06 | `time_scale_user ∈ [0.1, 1.0]`，默认 0.25 | `time_controller.gd::set_user_scale / apply_a11y`，经 `_ramp_to` 缓动 | `test_time_slider_bounds_default_0_25`、`test_step_commit.gd::test_focus_honours_user_time_scale` |
| E09-S5c | V-01 / V-03 / V-04 / V-05 | `screen_shake=false`、`fog_option` 三态、`motion_blur=false` | `hud_slice.gd::dim_alpha_for / shake_amplitude / motion_blur_strength / world_boost_allowed` | `test_fog_option_tri_state_and_motion_blur_off` |
| E09-S5d | X-01 / X-02 | `text_scale ∈ [1.0, 1.5]`、`subtitles=true` | `hud_slice.gd::_apply_text_scale / subtitle_text / show_subtitle` | `test_text_scale_range_and_subtitles` |
| E09-S7 | 全模型 + 持久化 | `to_dict / from_dict / default_values`，经 `save_prefs("a11y", …)` | — | `test_a11y_settings_full_model_roundtrip` |
| CI | `@ci:a11y-values-in-range` | `budget_checks.gd::_check_a11y_values` + `scan_a11y_values` | — | `test_ci_a11y_values_scan_reverse` |

---

## 2. 关键工程决策

### D-C1 · 模型与消费严格分层
`A11ySettings` 只拥有**字段模型**（命名、默认值、枚举、钳制），不画像素、不驱动 VFX、不发信号。`TimeController`（E02）与 `HudSlice`（E09）**读**它。
理由：这条单向依赖是 FLAG-J 解环的结构性前提，也让每一个 a11y 不变量都能在无渲染的 headless 单测里断言。

### D-C2 · PULL 而非新增信号
设置变更由调用方主动 `hud.apply_a11y()` / `tc.apply_a11y(settings)` 拉取。
理由：`event-vocab-zero-drift` 冻结总线词汇表。新增一个 `a11y_changed` 信号是最"自然"的写法，也正是本批次禁止的漂移。代价是 bootstrap 需显式接线一次，已在两处 `apply_a11y` 的文档注释中写明。

### D-C3 · 写入即钳制（而非保存时钳制）
`time_scale_user` / `text_scale` / 两个枚举都是**校验属性**，越界值**无法被存储**。
理由：这让 `@ci:a11y-values-in-range` 从"但愿如此"变成真不变量——运行期数据不可能越界，因此该扫描防守的是**源码**：有人把 `TIME_SCALE_DEFAULT` 调成 0.05"找找手感"，或把 `screen_shake` 初值翻成 `true`，运行期的钳制会忠实地把这个无障碍回归一路保留下去。扫描读的是出厂常量。

### D-C4 · 向后兼容外观（facade）
`color_blind_mode: String` 与 `fog_enabled: bool` 保留为 Tier2 字段的**计算视图**，双向可写；`from_dict` 采用 **Tier2 优先**优先级。
理由：Sprint 0/1 全部调用方 + `test_save_manager.gd::test_prefs_delegation_roundtrip`（round-trip 字符串 `"DEUTERANO"`）依赖它。Tier2 优先保证 Batch C 存档同时带两代键时不会自我降级。

### D-C5 · V-01 频率从**源码枚举**，而非手工清单
`test_a11y_settings.gd::_declared_hz_constants()` 扫描 `hud_slice.gd` 中所有 `const *_HZ`，逐个断言 ≤ `FLICKER_HZ_MAX`。
理由：手工清单只能守住"已经知道的频率"。下个 Sprint 有人加一条新的周期性调制而忘记更新测试时，这个扫描仍然会抓到。`hud_slice.gd:97` 的注释承诺了这一点，此处兑现。

### D-C6 · 三档雾必须**严格递减**
`dim_alpha_for()`：FULL 0.35 > REDUCED 0.15 > OFF 0.0，并有对应断言。
理由："减弱"档如果不是真的比 FULL 弱，就是一个**会撒谎的无障碍设置**——比没有更糟。

### D-C7 · 反向断言与正向断言等量
每条"设置生效"都配一条"设置仍然承重"。
理由：无障碍功能极易 rot-while-green：关掉替换色、废掉钳制、丢掉字幕，都不崩溃、不动帧预算、其他测试毫无察觉，游戏只是对它服务的那批玩家变得不可玩。典型如 `shake_amplitude()` / `motion_blur_strength()`——若被硬写成 `0.0`，"默认关闭"的正向断言依然全绿，因此必须有"开启后确实拿到非零值"的反向断言。

---

## 3. 地雷防护对照

| 地雷 | 要求 | 落实方式 | 验证点 |
|---|---|---|---|
| **1（FLAG-J）** | `save_manager.gd` 不得出现 a11y 字段名；新字段须登记黑名单；`color_blind_mode` 保留 facade | 4 个新字段名已加入 `test_save_manager.gd::A11Y_FIELD_NAMES`（共 10 条）；facade 保留 | 新增**模型驱动**扫描：遍历 `to_dict()` 全部键，断言①已登记②不出现在 `save_manager.gd` |
| **2** | `a11y_settings.gd` 不得含字面量 `ConfigFile` | 文档改述为"legacy Sprint 0 .cfg config-file API"；迁移归 SaveManager | `assert_false(a11y_src.contains("ConfigFile"))` |
| **3（N-7）** | 不得出现裸的风险令牌 | 全部改写为"the N-7 risky token" | 见 §6 自查 |
| **4** | `event_bus.gd` 与 `system-breakdown.md §2` 逐字节一致；零新增信号 | 两文件**未触碰**；跨层通信一律 PULL | `time_scale_changed` 为既有信号，复用不新增 |
| **5** | GDScript 4 陷阱 | 无 `\` 续行；无 `var x := autofree(...)`；无单参 `JSON.stringify`；`Color("#hex")` 而非 `Color.from_string` | 见 §6 自查 |

---

## 4. CONCERNS（需主理人/QA 裁决）

### CONCERN 1 · `HUD_COLOR_ALARM_CB` 是一个被冻结的死值 —— ✅ **已裁决并执行（主理人 2026-08-05：退休）**
- **事实**：原任务书写"危险色映射到 `#C8862F`"。control-manifest v0.2 C-06 明文作废该口径：「旧口径「→#C8862F」作废：警戒本就是 #C8862F，映射后两档亮度比塌缩至 1.00:1」。
- **冲突（历史）**：`tests/unit/test_hud_slice.gd:409` 曾钉死 `HUD_COLOR_ALARM_CB == HUD_COLOR_CAUTION`——即测试在断言一个已被签字作废的值是正确的。
- **处置**：新增 `HUD_COLOR_DANGER_CB := Color("#F0C070")` 作为权威替换色（面板 10.55:1，兼过 C-02/C-03；vs 警报 2.60:1，vs 警戒 1.81:1）；`danger_color()` 返回它。`HUD_COLOR_ALARM_CB` 当时**仅为满足上述测试行而保留**，已无任何生产调用方——故退休为纯删除，零行为变更。
- **裁决（主理人 2026-08-05）：退休 `HUD_COLOR_ALARM_CB`。** 该动作是"一行常量 + 一行测试"的改动。裁决依据三条：
  1. **责任已写死在本批**：`design/art/accessibility-matrix.md:199` 的待跟进清单明列「`src/ui/hud_colors.gd` | L36 | `HUD_COLOR_ALARM_CB := HUD_COLOR_CAUTION`（=`#C8862F`，塌缩 1.00:1） | 程基岩（Batch C）」，责任人与批次均已指定，不滚 Sprint 3。
  2. **留着它等于让测试锁死错误**：常量若保留，`test_hud_slice.gd:409` 就持续断言一个已被 art-bible v0.3 §9.1 FLAG-2 与 control-manifest v0.2 共同作废的值是正确的。测试由"守护正确性"退化为"守护错误"，正是 `test_a11y_settings.gd` 文件头所批判的 rotting-green 失效模式。
  3. **退休无风险**：该常量零生产调用方，删除不改变任何运行时行为。
- **执行记录（本次收尾）**：
  - `src/ui/hud_colors.gd`：删除常量（原 L42），删除点留一行面包屑；原"SUPERSEDED / 仅因测试保留"注释改写为**墓碑说明**——曾存在的理由 / 作废的理由 / 现行权威三段式，并保留 `#F0C070` 的亮度比取证。另记入一条**命名分歧提示**：signature §4 用旧名承载新值，工程侧改用 `HUD_COLOR_DANGER_CB`，**值一致、仅名不同**。
  - `tests/unit/test_hud_slice.gd:407-410`：占位读点升级为真断言 + **反向锁**——`danger_color(DEUTAN) == HUD_COLOR_DANGER_CB` 且 `HUD_COLOR_DANGER_CB != HUD_COLOR_CAUTION`。注释显式说明失败方向已反转：本行不再"认证替换色"，而是"禁止回归"。
  - **该文件其余断言一律未动**，含 landmine 3 的 `ALARM_FILL_ALPHA_MAX <= 0.35`（L394）与 `HUD_COLOR_ALARM_FILL` 不得升格为边框（L390）两组。
  - 全库扫描 `src/` / `tests/` / `tools/`：除上述两处外**零引用**，无悬空符号，不存在编译期断链。
- **遗留（文档域，非工程批次范围）**：`design/art/hud-a11y-signature.md:134/164/221`、`design/assets/sprint2-asset-spec.md:602/668`、`production/sprints/batchc-impl-spec.md:146/182/835/936/1138`、GDD `patrol-ai.md:71` 仍以旧名 `HUD_COLOR_ALARM_CB` 行文。**取值口径已无分歧（均为 `#F0C070`），仅命名待收口**，归美术／文策域处理。

### CONCERN 2 · `MOTION_BLUR_STRENGTH` 是策略缝，不是已实现特性
- **事实**：本 Sprint HUD 层没有后处理栈（渲染工作在 Sprint 3），因此 `motion_blur_strength()` 在任何已出货路径上都只会返回 `0.0`。
- **为何不删**：它守的不变量是"**不存在绕过该设置而存在的模糊**"。删掉这个缝，Sprint 3 加模糊时就没有任何结构性障碍阻止它直接落到屏幕上。
- **待裁决**：请在 Sprint 3 渲染故事里显式引用本缝作为唯一入口；若届时决定改走 Environment/后处理资源，需同步把 V-05 的断言迁到那一层，否则本测试会退化为恒真。

### CONCERN 3 · `_dim` 与 `world_boost` 的默认行为由既有测试反向锁定
- **事实**：`test_hud_slice.gd` 三处钉死：L79 `_dim.visible == true`（凝神中）、L301 `boost_calls == [true]`、L388 暴露边框 `== HUD_COLOR_ALARM`。
- **影响**：这决定了 V-04 只能实现为"默认 FULL 保持 Sprint 1 观感、仅在 OFF 档移除面纱"，而不能实现为"默认就减弱"。
- **处置**：`world_boost_allowed()` 仅在 `fog_option() == OFF` 时返回 false；`danger_color(OFF)` 恒等于 `HUD_COLOR_ALARM`。三条既有断言均不需修改。
- **待确认**：这是**正确**的产品语义（无障碍设置不应改变未开启玩家的观感），此处仅记录该语义同时被测试锁定，非巧合。

### CONCERN 4 · X-01 的"不破版"是有限证明
- **事实**：`_apply_text_scale()` 让每个控件的**位置与尺寸**同乘 scale，测试断言 150% 下纵向次序不塌陷（悬疑条仍在状态行下方）且布局确实移动了。
- **局限**：这证明的是"布局随字号一起移动"，**不等于**"任意视口宽度下文本都不溢出"。真正的溢出需要字体度量与真实视口，属于截图/人工验收范畴。
- **待裁决**：建议在 QA 计划中补一条 150% 的人工目视项，不要把它算进单测覆盖。

### CONCERN 5 · 三类色盲共用同一替换色
- **事实**：PROTAN / DEUTAN / TRITAN 映射到同一个 `HUD_COLOR_DANGER_CB`。
- **依据**：manifest 注记明确三型靠**常驻形状通道与脉冲通道**区分，而非三种不同色相；`#F0C070` 的区分度由**亮度**承载，故对三型同时有效。
- **待确认**：若后续无障碍顾问要求分型配色，需先在 signature 文档补签，工程侧只需改 `danger_color()` 一处（该函数是"危险长什么样"的唯一决策点）。

### CONCERN 6 · 遗留探针 `tools/tmp/probe.gd` 按设计编译不过（本批扫描顺带发现，非本批引入）
- **事实**：该文件第 2 行为 `const A := Color.from_string("#16181D", Color.BLACK)`——正是 `hud_colors.gd:24-30` 记录的、在 GDScript 4.4 中**无法作为常量表达式编译**的写法。它是当初验证该结论的一次性探针，结论已固化进 `hud_colors.gd` 的注释。
- **当前风险**：**零**（本次收尾复核，比原判"低"更强）。四层隔离，任一层单独成立即可：
  1. **`.gitignore:19` 整目录忽略 `tools/`** ——决定性一条。CI 的 `actions/checkout@v4` 检出的是 git 仓库内容，`tools/tmp/probe.gd` **根本不存在于 CI 容器的工作区**，谈不上被解析。
  2. GUT 以 `-gdir=res://tests/unit` 收集用例，扫描根不含 `tools/`。
  3. 该文件**无 `class_name`**，故不进全局类缓存（已比对 `.godot/global_script_class_cache.cfg` 全部 21 条注册项，无 probe）；全库 `.gd` 扫描亦无任何 `preload`/`load` 指向它，无隐式加载路径。
  4. 即便前三层同时失效：`ci.yml` 步骤 2 `godot --headless --import --quit 2>&1 || true` 显式吞掉退出码，而门禁（步骤 3）只读独立进程产出的 `gut_output.txt`，导入期脚本报错不进入判定面。
- **引信条件（何时需重新裁决）**：以下任一发生，上述隔离即被击穿，须立刻重议——① `.gitignore` 放开 `tools/`；② `-gdir` 放宽到 `res://` 或新增全量 lint/parse 门；③ 步骤 2 去掉 `|| true` 并改为读取导入期 stderr。
- **潜在风险**：任何"全工程脚本解析"步骤（打开编辑器、未来新增的全量 lint/parse 门）都会在它上面报错，且报的正是一个**已经解决过的**问题，极易误导排查方向。
- **裁决（主理人 2026-08-05）：本批不删，记为 tech debt。** 依据：删文件属高影响动作，且经上方复核该文件不触达 CI（`tools/` 已被 `.gitignore` 排除），当前不影响任何门禁。**本批次未执行删除。**
- **债务登记**：仅剩本地开发机影响——用 Godot 编辑器打开工程时会对它报一次常量表达式错误，且报的正是一个**已经解决并固化进 `hud_colors.gd:24-30` 注释**的问题，易误导排查方向。清理时机不限，风险不随时间增长。

---

## 5. 变更文件清单

**新增**
- `tests/unit/test_a11y_settings.gd` — 5 个出口钩子 + `@ci:a11y-values-in-range` 反向断言
- `production/sprints/sprint2-batchc-impl-notes.md` — 本文件

**修改**
- `src/core/a11y_settings.gd` — Tier2 全模型（枚举 / 范围 / 校验属性 / facade / to_dict / from_dict）
- `src/core/time_controller.gd` — `user_scale`、`set_user_scale`、`apply_a11y`、`focus_target`、`get_ramp_target`
- `src/ui/hud_colors.gd` — `HUD_COLOR_DANGER_CB`、`HUD_COLOR_BOUNDARY`、`danger_color/danger_icon/danger_read_is_multi_channel`
- `src/ui/hud_slice.gd` — S5a/S5c/S5d 消费侧（危险色路由、三档雾、屏震/模糊闸门、文本缩放、字幕）
- `tests/ci/budget_checks.gd` — `_check_a11y_values()` + `scan_a11y_values()` 反向面
- `tests/unit/test_save_manager.gd` — `A11Y_FIELD_NAMES` 增补 4 个 Tier2 字段名
- `tests/unit/test_step_commit.gd` — 新增 `test_focus_honours_user_time_scale`
- `tests/unit/test_hud_slice.gd` — **仅 L407-410 一处**：C-06 占位读点 → 真断言 + 反向锁（CONCERN 1 收尾）。其余断言含 landmine 3 两组均未触碰

**未触碰（硬约束）**
- `src/core/event_bus.gd`
- `src/core/save_manager.gd`

---

## 6. 自查（地雷 3 / 4 / 5）

**地雷 3（N-7）**：本批次所有新增文件与新增注释中，不存在裸的 N-7 风险令牌，亦不存在会被 ci.yml 门禁正则 `\[Risky\]:|\[Pending\]:|\[Risky\] Script was skipped` 命中的字符串。相关表述一律写作"the N-7 risky token"。

**地雷 4（event-vocab-zero-drift）**：`event_bus.gd` 与 `docs/architecture/system-breakdown.md §2` 均未修改，逐字节一致。零新增信号——`TimeController.apply_a11y()`、`HudSlice.apply_a11y()` / `set_a11y_settings()` 全部为直接方法调用（PULL）。`time_scale_changed` 为既有信号，仅复用未改签名。

**地雷 5（GDScript 4 陷阱）**：
- 无 `\` 续行；跨行表达式一律置于括号内隐式续行。
- 无 `var x := autofree(...)`——`autofree` 返回 Variant，全部改为显式标注：`var s: A11ySettings = autofree(...)`。
- 无单参 `JSON.stringify`。
- 所有颜色常量使用 `Color("#hex")`；`Color.from_string()` 不是常量表达式，在 `const` 中无法编译。
- headless 生命周期：`_ready()` 不自动执行，故 `_ramp_to()` 以 `is_inside_tree()` 守卫 `create_tween()`；`hud_slice.gd` 每个 a11y resolver 均对 widget 做空值守卫，使策略可在无树环境断言。
- 额外规避：测试脚本 `extends GutTest -> Node`，局部变量避免命名为 `name`（会遮蔽 `Node.name`），改用 `const_name` / `hz_name`。

**hermetic 性自查**：`SaveManager` 是真实自动加载（`project.godot:18`）。因此"空存储保留默认值"的反向断言**必须**注入空的 `PrefsStub`，而不能靠"不注入"来触发 null 分支——后者会解析到线上服务并读取开发机真实的 `user://prefs.json`，在干净 CI 上通过、在跑过游戏的机器上失败。已按注入式改写。
