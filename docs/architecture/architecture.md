# 架构基线文档 ·《灰烬之步》ASHEN STEP

| 字段 | 值 |
| --- | --- |
| **项目** | ASHEN STEP《灰烬之步》 |
| **引擎 / 平台** | Godot 4（Forward+ / Vulkan）· PC·Steam（键鼠 + 手柄） |
| **评审强度** | lean（仅核心节点卡质量门） |
| **文档版本** | v0.3（Sprint 3 · S3-B：§4 预算表补音频四行，收口 OOS 冲突 F-4）｜前版 v0.2（Phase 2 系统设计前置·锁版基线） |
| **作者** | 程基岩（工程负责人） |
| **上游依据** | `design/concept/game-concept.md`（§2 Mechanics、风险5）、`design/art/art-bible.md`（§3 光照/体积、§9 可访问性）、**`design/audio/asset-categories.md` §7.3（音频预算建议上限）** |
| **下游衔接** | `docs/architecture/adr/*.md`（决策）、`docs/architecture/control-manifest.md`（硬约束）、Phase 2 `design/gdd/systems/*.md`（逐系统 GDD） |

> **本文用途**：在概念文档与美术圣经锁定后，对齐风险5（RTwP + 可视锥 + 声波 + 状态机在 Godot 4 的预算），产出**架构基线**。本文定义技术栈、整体分层、核心系统技术选型与边界、性能预算表，供后续逐系统 GDD 拆分直接引用。本文为**前置基线**，不含逐系统实现细节（留待 GDD）。
>
> **引擎一致性**：本文 Godot API 引用基于 **Godot 4.4 锁定线**（Forward+、LightmapGI、Volumetric Fog、`PhysicsDirectSpaceState3D`、`Engine.time_scale` 自 4.0 起稳定）。最终锁定 4.4，API 签名已按 4.4 复核。

---

## 0. 风险5 一句话结论

概念与美术建议的「事件驱动 + 空间分区 / 时间缩放 / 烘焙 GI / 动态光压最低 / 雾事件驱动」在 Godot 4 Forward+ 下**全部可行且可量化**。基于下述预算，风险5 判定为 **PASS（含 4 项可缓解的非阻塞 Concerns，详见 §5）**，守卫上限建议 **MVP 同区活动 8 / Tier2 16**。无硬阻塞项。

---

## 1. 技术栈

| 维度 | 选型 | 说明 |
| --- | --- | --- |
| 引擎 | **Godot 4.4（锁定）** | 桌面目标，Vulkan 后端 |
| 渲染器 | **Forward+（聚类前向）** | 多实时光 + 体雾 + LightmapGI + Decals；详见 ADR-001 |
| 回退预设 | **Compatibility（GL）** | 无 Vulkan 1.0+ 时降级（关体雾/动态GI，保留 LightmapGI） |
| 语言 | **GDScript 为主，热点用 C#/GDExtension** | 玩法/系统 GDScript；空间索引/射线批处理可 C# |
| 维度 | 3D 固定高角度机位（已锁定 45–60° 俯角，见概念 §2） | 见 §6 开放依赖 |
| 物理 | Godot Physics（3D） | 固定步 1/60；守卫/玩家用 `CharacterBody3D` |
| 导航 | `NavigationRegion3D` + `NavigationAgent3D` | A* 由导航服务器提供，仅状态转换触发 |
| 音频 | `AudioStreamPlayer(3D)` + `AudioServer` | 凝神期不变调，仅 lowpass + ducking（ADR-003） |
| 输入 | `InputEvent`（实时，不受 time_scale） | 键鼠 + 手柄，重映射由后续 GDD 定 |
| 构建/CI | Godot `--headless` 导出 + 编辑器断言脚本 | 校验 UV2 / 动态光上限 / 声环上限（control-manifest 硬约束） |
| 平台 | PC / Steam | 最低目标 GTX 1060 / RX 580 档，60fps@1080p |

---

## 2. 整体架构分层

自顶向下五层；依赖单向向下，上层不直接触引擎底层，须经核心服务层。

```
┌──────────────────────────────────────────────────────────────┐
│ L5 表现 / 渲染层  场景树 · 固定高角度相机 · 着色器 · VFX ·     │
│                 near-diegetic HUD（世界内锥/光池/声环/残影）     │
├──────────────────────────────────────────────────────────────┤
│ L4 玩法 / 模拟层  「读—步」循环 · 步进提交 · 视野锥 · 声波 ·    │
│                 掩体/阴影 · 可疑度状态机 · 互动物件             │
├──────────────────────────────────────────────────────────────┤
│ L3 AI 层        守卫 FSM（Calm→Suspicious→Alert→Search→Return）│
│                 变体（循声猎犬/暗视哨兵 Tier2）· A* 路径（缓存） │
├──────────────────────────────────────────────────────────────┤
│ L2 核心服务层    时间控制器(time_scale) · 事件总线 ·            │
│                 SpatialHashGrid3D（空间分区）· 空间查询封装 ·    │
│                 存档 · 输入管理 · 可访问性设置 · 光/雾预算守卫   │
├──────────────────────────────────────────────────────────────┤
│ L1 基础 / 平台层  Godot 4 引擎（Forward+ · 物理 · 音频 ·       │
│                 资源流式加载）· OS / Steam 输入 · 文件系统       │
└──────────────────────────────────────────────────────────────┘
```

**层间契约要点**
- L4 玩法层**不直接**调用 `PhysicsDirectSpaceState3D`，须经 L2 的「空间查询封装」（统一遮挡层 mask、射线参数、批处理），保证 LOS 逻辑可测、可节流。
- 所有「状态变更」（熄灯、落足、诱饵落点、守卫转身超阈值）走 **L2 事件总线 + dirty 标志**，触发 L4/L3 局部重算（ADR-002），杜绝逐帧全图重算。
- 时间统一由 **L2 时间控制器**经 `Engine.time_scale` 管理；玩法代码冷却计时须用真实时间，不得落入受缩放的 process（ADR-003）。

---

## 3. 核心系统技术选型与边界

### 3.1 潜行系统（视野锥 / 声波 / 掩体阴影 / 可疑度）
- **计算模型**：事件驱动 + 均匀空间网格 + 节流 tick（**ADR-002**）。
- **视野锥几何**：每守卫 `VisionCone` 组件（origin / forward / half-angle / range）。可视化用挂守卫的半透明 `MeshInstance3D`（锥/地面光斑），边界脉动 tell 由 shader 实现（频率受 control-manifest 封顶）。
- **LOS**：仅对遮挡层（墙/柱/门）`intersect_ray`；光影成员查 LightmapGI 阴影区 + 动态光覆盖——阴影=隐蔽，光池=必检测。
- **声波**：离散声事件 → 扩张声环（Tween/shader，自毁，同屏 ≤8）+ 网格通知半径内守卫提可疑度。
- **可疑度**：连续条，FSM 决策 5–10Hz；暴露为可见升级（梯度），非瞬死。
- **边界**：锥/LOS 成本只随「活动守卫数 × 10Hz」增长，与帧率解耦（慢放下帧率仍 60，收益更大）。

### 3.2 RTwP 时间模型（凝神慢放）
- **实现**：单一 `Engine.time_scale`（常态 1.0，凝神 0.1–0.3 默认 0.25）（**ADR-003**）。
- **自动减速**：`_process`/`_physics_process` delta、`AnimationPlayer`/`Tween`/`AnimationTree` 随之减速 → 步进动画、足迹残影预演、落足 Pose 冻结天然实现。
- **玩家实时**：`InputEvent` 不受 time_scale，慢放中仍可规划/提交。
- **音频单独**：不变调，仅 lowpass + ducking；粒子需手动同步 `.time_scale`（ADR-003 风险）。

### 3.3 渲染管线（Forward+ / 光照 / 体积）
- **渲染器**：Forward+（**ADR-001**）。
- **光照**：静态 LightmapGI 烘焙；动态光仅可互光源 + 提灯 + 少量彩窗 SpotLight（**ADR-004**）。
- **投影**：仅月光 `DirectionalLight3D` 投阴影；提灯 OmniLight **无投影**（威胁由光池/锥传达）。
- **体积雾/尘埃**：冷调低密度，事件驱动（仅相机可见区 + 光柱内），密度/粒子封顶（control-manifest）。

### 3.4 AI（守卫 FSM / 变体 / 寻路）
- **FSM**：Calm→Suspicious→Alert→Search→Return，决策 5–10Hz，状态靠姿态+道具（非颜色）传达。
- **变体（Tier2）**：循声猎犬（听觉优先，降视觉权重）、暗视哨兵（暗处仍可见，逼迫换解法）。
- **寻路**：`NavigationAgent3D`，A* **仅状态转换**触发并缓存路径；不逐帧。

---

## 4. 性能预算表（风险5 核心交付）

> 所有数字为 **PC / 60fps@1080p（GTX1060 档）** 目标上限；超出即触发 control-manifest 硬约束告警。MVP=Tier1，Tier2=期望层。

| 资源 / 指标 | MVP (Tier1) | Tier2 | 实现路径 / 依据 |
| --- | --- | --- | --- |
| **同区活动守卫** | **≤ 8** | **≤ 16** | 锥 10Hz 错峰 + 网格；渲染不受光照拖累（ADR-004 光LOD） |
| **关卡守卫总数** | ≤ 12 | ≤ 32 | 按区域流式激活，仅可见区 tick |
| **动态点光同屏** | ≤ 12 | ≤ 32 | Forward+ 聚类；提灯+烛灯+彩窗 |
| **投影光** | 1（月光） | 1（月光）+ 可选最近 1–2 提灯 | 提灯默认 shadow=false |
| **锥体重算频率** | 10 Hz/守卫（错峰） | 同 | 事件置脏 + 节流 tick，非逐帧 |
| **LOS 射线峰值** | ~160 射线/s | ~480 射线/s | G×10Hz×(1–3 射线)；BVH 射线 ~0.02ms，帧均 <0.2ms |
| **可疑度 FSM 决策** | 5–10 Hz | 同 | 状态机节流 |
| **A\* 寻路** | 仅状态转换 | 同 | 缓存路径，非逐帧 |
| **同屏声环 VFX** | ≤ 8 | ≤ 8 | Tween/shader 自毁 |
| **体积雾密度** | base ≤0.05 | 同 | 冷调；熄灯 ramp ≤0.12 且 ≤0.4s 回落 |
| **尘埃加法粒子** | 每光柱上限 + 全局 additive 上限 | 同 | CI 断言 |
| **目标帧率** | 60 @ 1080p | 60 @ 1080p | 画质预设（低/中/高） |
| **凝神时间缩放** | 0.1–0.3（默认 0.25） | 同 | 用户 0.1–1.0 可调，下限 0.1 |
| **UI 音效常驻 PCM** | **≤ 512 KB** | 同 | 全部常驻、不流式（48 kHz/16-bit/单声道）。S3-B 实占 ≈ **31 KB**（上限的 6%） |
| **流式音频解码缓冲** | **≤ 4 MB** | 同 | 环境床 / 音乐走流式 `.ogg`。S3-B 实占 **0**（本批无床、无乐） |
| **UI 同发语音数** | **3** | 3 | `SFX_UI` 播放器池固定 3；满池即**偷最旧声**（20 ms 淡出后接续），**不排队** |
| **音频总线数** | 7 | 7 | `Master / World[Music,Ambience,SFX_World,Voice] / SFX_UI`（ADR-005 D-1）；索引顺序即契约 |

### 音频预算说明（S3-B 新增）
> 前三行取自 `design/audio/asset-categories.md` §7.3（音频指导给出的建议上限），经工程侧采纳为架构级预算（收口 OOS 冲突 F-4）。
- **为什么现在就写下来** —— S3-B 的实际占用是 31 KB，量级上零风险。预算行不是为了约束今天的两个 `.wav`，而是为了让「加一条 3 分钟无损环境床」这种决定在**评审时**撞上一个数字，而不是在某台 8 GB 机器上撞上一次卡顿。
- **512 KB 与 4 MB 的分界是「常驻 vs 流式」，不是大小** —— UI 音必须常驻，因为它要在读盘（正在存档/读档）时立即出声；环境床可以流式，因为它永远有前摇。把一条床误设为常驻，超的不是 4 MB 那条线，是 512 KB 这条。
- **同发 3 是硬上限，不是软目标** —— 见 `src/core/audio_director.gd` `UI_POOL_SIZE`。第 4 声不会排队等待（那会让「嗒」迟到几百毫秒，比丢掉它更糟），而是让最旧的一声在 20 ms 内淡出让位；20 ms 是为了避开硬停造成的直流阶跃咔嗒声。
- **总线数写进预算表**是因为它是 A-05（分路音量）的前置条件，且被 `tests/unit/test_audio_bus_layout.gd` 硬断言 —— 改这一行会红 CI。

### 锥体/LOS 成本模型（估算依据）
- 每守卫每 tick：网格哈希查询 O(1) + 候选（玩家 + 0–2 干扰物）→ 角度/射程过滤 → 每候选 1×`intersect_ray`（遮挡层）+ 1×光影成员测试 ≈ **1–3 射线**。
- MVP：8 × 10Hz × 2 ≈ **160 射线/s**；Tier2：16 × 10Hz × 3 ≈ **480 射线/s**。
- Godot `intersect_ray` 走 BVH，单射线 ~数十 µs；峰值 480/s ≈ 10ms/s 摊到 60 帧 → **帧均 <0.2ms**，可忽略。
- 对比朴素逐帧全图：成本随 60fps 线性膨胀，且在慢放下仍 60fps → 本方案收益随慢放放大。

---

## 5. 风险5 判定与 Concerns

**判定：PASS**（设计意图在 Godot 4 Forward+ 下可行且可量化，守卫上限 MVP 8 / Tier2 16 成立）。附 **4 项非阻塞 Concerns**，均可在 lean 范围内缓解：

1. **相机角度已锁定**（高角/等距固定机位 45–60° 俯角，见概念 §2）：锥体地面投影、LOS 与布光均按此机位参数化。→ 缓解：架构按固定高角设计；机位已由概念 §2 拍板，美术圣经 §0 与本基线 §6 已回填，锥/HUD 投影代码参数化适配。
2. **Tier2 守卫 16 逼近动态光 32 上限**：需严格「提灯光 LOD」（远处关实时光）+ 无投影纪律。→ 缓解：control-manifest 硬约束 + 编辑器断言实时光 >32 告警。
3. **`Engine.time_scale` 不自动变调音频 / 不自动同步粒子**：→ 缓解：显式 lowpass+ducking 接线；凝神时同步 `GPUParticles3D/CPUParticles3D.time_scale`（ADR-003）。
4. **LightmapGI 需 UV2 规范 + bake 流程**：动态物体无间接光（暗调基调下可接受）。→ 缓解：资产规范加 UV2 字段，CI 检查缺失。

无硬阻塞项（FAIL 条件不成立）。

---

## 6. 开放依赖 / 待确认

| 项 | 状态 | 影响 |
| --- | --- | --- |
| 相机 45–60° 高角（已锁定，见概念 §2） | 已定 | 锥地面投影、LOS、布光参数化适配 |
| 确切 Texel Density / LOD 档 | 待与美术按预算定 | 资产规范 §5.3 |
| Godot 4.4（已锁定） | 已定 | API 签名已按 4.4 复核 |
| Tier2 守卫 16 时光 LOD 策略细节 | 架构已定方向 | 由 GDD + control-manifest 落地 |

---

## 7. 关联文档索引

- **ADR-001** 渲染管线选型（Forward+） → `docs/architecture/adr/adr-001-render-pipeline.md`
- **ADR-002** 潜行计算模型（事件驱动 + 空间分区） → `docs/architecture/adr/adr-002-stealth-compute-model.md`
- **ADR-003** 时间模型（time_scale 实现 RTwP） → `docs/architecture/adr/adr-003-realtime-with-pause-time-model.md`
- **ADR-004** 光照与阴影预算（烘焙 GI + 无投影提灯 + 光 LOD） → `docs/architecture/adr/adr-004-lighting-and-shadow-budget.md`
- **ADR-005**（Draft）音频总线架构与世界模式预设（澄清 ADR-003 的「全局 lowpass」= 挂 `World` 而非 `Master`） → `docs/architecture/adr/adr-005-audio-bus-architecture-and-world-mode-presets.md`
- **控制清单** 性能与可访问性硬约束（**§8 音频硬约束 A-01~A-05**） → `docs/architecture/control-manifest.md`
- **下游** 逐系统 GDD（Phase 2）：潜行/RTwP/渲染/AI 各自八节 GDD，须引用本基线预算与 ADR。
