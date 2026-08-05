# Epic E01 · 工程基座与管线（L2 基础设施 + 资产管线 + CI 基座）

- **对应模块**：L2 核心服务层（`docs/architecture/architecture.md` §2）+ 资产导入管线（`design/assets/asset-manifest.md` §1.3/§1.5）+ CI 基座（control-manifest §7）
- **层**：L2 / L1（平台）
- **依赖**：无（地基，所有 Epic 的前置）
- **DAG 优先级**：P0 地基
- **MoSCoW**：**Must** ｜ **T 恤**：L
- **上游**：架构 §2 层契约、ADR-001~004、control-manifest R/T/V/C/X/G、asset-manifest §1.3/§1.5、system-breakdown §2 词汇表

## 目标
把「架构 §2 定义的 L2 基础设施」与「资产导入/CI 管线」落成可复用、可测的服务基座，使上层玩法（E02–E09）只经契约通信、不直接触引擎底层。本 Epic 是风险5「事件驱动 + 空间分区」与 ADR-002「事件驱动重算 + 网格」的物理载体。

## 范围（In Scope）
- L2 单例/服务：EventBus、SpatialHashGrid3D、SpatialQueryWrapper(LOS)、LightState 注册、NavServer 封装、**SaveManager 接口**（仅契约/seam；真实持久化实现见 **E11**）、InputManager、A11ySettings（偏好经 E11 SAV-S4 委托落盘）。
- 项目脚手架：`project.godot` 分层目录、`res://` 资源布局、addon 放置（GUT 见 `tests/README.md`）。
- 资产管线：导入预设（BC7 / sRGB 线性 / mipmap / aniso 8–16，asset-manifest §1.4）、命名规范 CI 校验（`<category>_<name>[_<variant>][_<lodN>][_<map>]`，§1.3）、UV2 缺失校验（ADR-004 / R-06）、LightmapGI bake 配置槽。

## 关键 Story 列表

### E01-S1 · 作为（程序员）我要（实现类型化 L2 EventBus）以便（各系统经声明信号通信，杜绝事件名漂移）
**Sprint 0**：是
**验收（Given/When/Then）**
- Given `system-breakdown.md` §2 共享事件词汇表（L2 上游 4 信号 + L4/L3 玩法 9 信号 + 8 个共享类型）。
- When 我实现 EventBus 单例并声明全部 13 个信号与 8 个共享类型（`Gait`/`Surface`/`SoundSource`/`LightState`/`GuardState`/`SusTier`/`TimeMode`/`LightLevel`）。
- Then 任一系统 `emit`/`connect` 上述信号均通过类型校验；CI lint 断言「无未声明信号 / 无拼写漂移」（对齐 consistency-review §1.3 闭合性）。
**关联**：system-breakdown §2；consistency-review §1.3；架构 §2（L2 事件总线 + dirty 标志）。

### E01-S2 · 作为（程序员）我要（实现 SpatialHashGrid3D，cell≈14m）以便（潜行查询 O(1) 且防跨 cell 漏检）
**Sprint 0**：是
**验收**
- Given ADR-002 规定「cell ≈ 守卫锥最大射程 ≈14m，cell 尺寸以最大射程定值锁死，防跨 cell 漏检」。
- When 我插入玩家/守卫/诱饵/互动物并做半径查询（默认 radius=14m，覆盖锥射程）。
- Then 半径内实体被 1 次哈希查询命中；跨越 cell 边界的实体仍被返回（cell ≥ 最大锥射程，无漏检）；插入/查询为 O(1)。
**关联**：ADR-002（均匀网格 cell≥最大射程）；架构 §4（成本模型）；asset-manifest §3.6（沿 cell≈14m 拼接）。

### E01-S3 · 作为（程序员）我要（实现 SpatialQueryWrapper 统一 LOS 射线）以便（L4 不直接调 PhysicsDirectSpaceState3D，LOS 可测/可节流）
**Sprint 0**：是
**验收**
- Given 架构 §2「L4 玩法层不直接调用 PhysicsDirectSpaceState3D，须经 L2 空间查询封装（统一遮挡层 mask、射线参数、批处理）」。
- When 上层请求 `query_los(from, to)`。
- Then 仅对遮挡层（墙/柱/门）做 `intersect_ray`，返回 `blocked:bool`；所有射线走统一 mask；批量接口供 E05 节流 tick 复用。
**关联**：架构 §2（层间契约）；ADR-002（LOS 仅遮挡层）；control-manifest G-03（10Hz 错峰）。

### E01-S4 · 作为（程序员）我要（建立 LightState 注册 + get_light_level 契约）以便（E04/E05/E08 有统一光照查询 API）
**Sprint 0**：是（接口/契约）；完整实现见 E04
**验收**
- Given cover-shadow GDD §2 定义 `get_light_level(pos)->[0,1]` 与 `get_cover(pos)->bool`，阈值 `L_DARK=0.20`/`L_BRIGHT=0.60`。
- When E01 建立 LightState 字典（id↔{LIT,EXTINGUISHED}）与 LightLevel 查询接口契约（静态烘焙 + 动态叠加 + 月光底填充）。
- Then E04 注入实现、E05/E08 消费时签名一致；Sprint 0 切片用 mock 返回 [0,1] 即可驱动 E05 检测。
**关联**：cover-shadow §2/§3；vision-cone §2（visibility 公式）；patrol-ai §2。

### ~~E01-S5 · SaveManager 检查点语义~~ —— ⛔ **已退役 · 已移至 E11**
> **状态**：**RETIRED（不在 E01 排期，不计入 E01 验收）**。依主理人**裁决 2**（`production/sprints/sprint2-stories.md` §0.1 / §6），SaveManager 自 E01 剥离为独立 epic **E11 · 存档与设置持久化**。
> **接续位置**：本 Story 的全部职责整体迁入 **`production/epics/E11-save-manager.md`** 的 **SAV-S1~S6**（Sprint 2 交数据层 SAV-S1/S2/S3/S4/S6；Sprint 3 交 UI SAV-S5）。
> **E01 的剩余责任**：仅保留 **SaveManager 接口 / D9 seam**（`GuardBrain._checkpoint_sink` 的**零参** `Callable` 契约，`src/game/patrol_ai.gd`）；真实持久化实现不在本 Epic。
> **原验收去向**：consistency-review **C4**（暴露软失败在最近安全检查点重生：守卫回 `RETURN`/巡逻、可疑度清零、动态光/物体状态复位）现由 **E11 SAV-S3 `restore_checkpoint()`** 承担并验收；`patrol-ai` §2 的 `GRACE_RT=1.2s` 宽限仍归 E08-S4（Sprint 1 已锁）。
> **编号保留理由**：维持 Sprint 1 历史文档（`production/sprints/sprint1-stories.md`，已锁）的可追溯性——故不删除编号，且 `E01-S5` **不得复用**于其它 Story。

### E01-S6 · 作为（程序员）我要（实现 InputManager + A11ySettings 持久化）以便（凝神/步态/互动输入统一，可访问性设置落地）
**Sprint 0**：是（最小：凝神键 + 步态键 + A11ySettings 接口）
**验收**
- Given rtwp-time-model §5（凝神键 hold=进入/release=退出，默认右键/Shift/手柄 LT）、stealth-step-commit §5（步态切换键）；core-hud-a11y §3（A11ySettings 持久化字段）。
- When 玩家按下/松开凝神键、切换步态、修改设置。
- Then `InputEvent` 实时（不受 time_scale，ADR-003）；设置写入 `A11ySettings`（色盲/时间缩放/屏震/雾/动模糊/文本/字幕），**持久化经 E11 SAV-S4 偏好委托**（`SaveManager.save_prefs("a11y", dict)` / `load_prefs("a11y")` → `user://prefs.json`）；E01 侧只负责 `A11ySettings` 接口与字段，不自持落盘实现。
**关联**：ADR-003（输入实时）；T-01/T-02（时间缩放）；C-/V-/X- 约束（core-hud-a11y §7）。

### E01-S7 · 作为（程序员）我要（搭工程脚手架 + 资产导入预设 + 命名/UV2/Lightmap CI）以便（资产可批量产出且漂移可断言）
**Sprint 0**：是（脚手架 + 命名/UV2 基础校验）；完整预算断言见 E10
**验收**
- Given asset-manifest §1.3（命名规范 `<category>_<name>[_<variant>][_<lodN>][_<map>]`）、§1.4（颜色空间/压缩/UV2）、ADR-004（UV2 前置）。
- When 资产导入或 CI 运行。
- Then 命名不符前缀/缺 `_lodN`/静态网格缺 UV2 时产出告警（lean 不阻断，记「漂移」）；`project.godot` 含分层目录与 addon 启用片段（见 `tests/README.md`）。
**关联**：asset-manifest §1.3/§1.4/§6；ADR-004（UV2）；control-manifest §7。

### E01-S8 · 作为（程序员）我要（封装 NavServer / NavigationAgent3D）以便（E08 仅状态转换触发 A* 并缓存路径）
**Sprint 0**：否（Sprint 1，配合 E08）
**验收**
- Given ADR-002「A* 仅在状态转换触发并缓存，非逐帧」；control-manifest G-05。
- When E08 在 CALM→ALERT/SEARCH 转换时请求路径。
- Then 经 NavServer 封装发起 `NavigationAgent3D` 寻路并缓存；非逐帧调用。
**关联**：ADR-002；control-manifest G-05；架构 §1（导航）。

## 依赖
无（地基）。下游：E02（TimeController）、E03（EventBus/Grid/Input）、E04（LightState）、E05（SpatialQueryWrapper/Grid）、E06（Grid/EventBus）、E07（EventBus）、E08（NavServer/Grid/EventBus）、E09（只读聚合）、E10（CI 基座）、**E11（EventBus 事件词汇 + `A11ySettings` 接口；承接原 E01-S5 的 SaveManager 实现）**。

## 整 Epic 验收标准
1. L2 服务全部以单例/资源形式可实例化为节点/RefCounted，且不依赖任何玩法 Epic。
2. EventBus 信号集 == system-breakdown §2 词汇表（CI 断言）。
3. SpatialHashGrid3D cell=14m，半径查询无跨 cell 漏检。
4. 资产命名/UV2 CI 告警可用（control-manifest §7）。
5. `tests/` 可 `godot --headless` 加载（E10-S1）。

## 风险
- **R-基-1**：L2 服务若未严格经事件 + dirty 标志，会出现「陈旧可见性」bug（如熄灯后守卫仍看到玩家）——ADR-002 负向。缓解：E01-S1/S4 以契约 + E10 断言兜底。
- **R-基-2**：grid cell 若 < 最大锥射程则跨 cell 漏检——ADR-002 风险。缓解：cell 定值锁 14m（E01-S2）。
- **R-基-3**：资产规范（UV2/mipmap/aniso）若不在管线层卡，LightmapGI 烘焙失败（ADR-004）。缓解：E01-S7 + E10 断言。

## 与架构 + 控制清单勾稽
- 架构 §2（L2 分层契约）、§4（成本模型，网格/射线预算）。
- ADR-001（Forward+ 不涉本 Epic 逻辑，仅资源格式）、ADR-002（网格/事件驱动/L2 封装）、ADR-003（输入实时/冷却真实时间）、ADR-004（UV2/LightmapGI 前置）。
- control-manifest：G-03（10Hz 经 E01 节流封装）、G-05（A* 经 NavServer 封装）、§7（命名/UV2/光上限/声环/脉动 CI）；R-06（LightmapGI 需 UV2）；asset-manifest §1.3/§1.4/§1.5（管线数值）。
