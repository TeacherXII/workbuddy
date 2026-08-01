# 系统 GDD · 步进提交 / 读—步循环（stealth-step-commit）
**Phase 2 · 八节 GDD · 优先级 P1**

> 上游：`design/concept/game-concept.md` §3 Mechanics①、§4 核心循环；`docs/architecture/adr/adr-003-realtime-with-pause-time-model.md`；`docs/architecture/control-manifest.md`（T-04 粒子）；`design/art/art-bible.md` §1 意象①/④、§3.3、§8.2。

---

## 1. 系统目标与支柱对齐
- **目标**：把「移动」变成「可读、可权衡、带即时反馈的落足承诺」——每一次提交在地面留下足迹残影，落足瞬间给出触觉级音效，使「一步」成为可感知实体。
- **支柱对齐**：
  - 支柱一 **步步为营**：核心载体。每步之间必有「读」的间隙；不做爽快连击式位移（概念 §3 设计红线）。
  - 支柱二 **感官愉悦**：落足微光、足音 foley、残影预演——物理/触觉质地（风险2 缓解）。
- **为何存在**：本系统是「读—步」循环的主动词；其余系统（视野/声音/阴影/AI）都是对「这一步落在哪、多响、多亮」的响应。

## 2. 核心机制与规则
- **步进行为**：玩家在 `FOCUS` 下瞄准下一落足点（ghost-trail 预演）；松开凝神键 → 提交，角色在 `step_duration` 内走到落点，落足瞬间触发足音 + 微光 + 噪声事件。
- **步态** `Gait`：`SNEAK`（慢/短/极静）| `WALK`（中）| `RUN`（快/长/极响，权衡用）。
- **参数表**（step_duration 受 `time_scale` 缩放；max_step 为真实世界距离）：
  | 步态 | max_step (m) | step_duration (s) | 噪声系数 gait_factor |
  | --- | --- | --- | --- |
  | SNEAK | 1.5 | 0.55 | 0.5 |
  | WALK | 2.5 | 0.38 | 1.0 |
  | RUN | 4.0 | 0.24 | 2.0 |
- **噪声半径公式**（输出给 ④）：`noise_radius = BASE(5.0m) × surface_factor × gait_factor`
  - `surface_factor`：`STONE 1.0` | `GRASS 0.7` | `METAL 1.2`（**Sprint 0 裁决：表面分类统一为 `STONE/GRASS/METAL`，与实现 `src/game/step_commit.gd::SURFACE_FACTOR` 对齐**；原 GDD 分类 `WOOD/MOSS` 废弃，映射 `WOOD≈STONE`、`MOSS≈GRASS`）。
  - 例：SNEAK+STONE=2.5m；WALK+STONE=5.0m；RUN+STONE=10.0m（RUN 为 Tier2，未进 Sprint 0 切片；值随 STONE 由 1.2→1.0 同步刷新）。
- **读间隙纪律**：仅当状态机为 `IDLE` 才接受下一次提交；上一步须 `RECOVERED` 完成 → 天然杜绝连击（概念红线）。最小 commit 冷却（真实时间）`≥0.12s` 兜底。
- **落点约束**：落点须在 `max_step` 内、非实心遮挡、非守卫身位；越界则预演显红（不靠纯色，见 §7）。

## 3. 数据模型与状态
```gdscript
enum Gait { SNEAK, WALK, RUN }
enum StepState { IDLE, AIMING, COMMITTING, RECOVERING }

class StepCommit:
    var state: StepState = IDLE
    var gait: Gait = SNEAK
    var aim_point: Vector3            # FOCUS 中实时更新
    var ghost_trail: Array[Vector3]   # 最近 N=6 落足残影
    const TRAIL_MAX: int = 6
    const COMMIT_COOLDOWN_RT: float = 0.12

struct StepCommitPayload:           # → player_step_committed
    var from: Vector3
    var to: Vector3
    var surface: Surface             # STONE/GRASS/METAL（Sprint 0 裁决统一分类；废弃 WOOD/MOSS，映射 WOOD≈STONE、MOSS≈GRASS）
    var gait: Gait
    var noise_radius: float
```
- `ghost_trail` 元素按时间淡出（Tween alpha，残影本身受 `time_scale` 缩放，ADR-003）。

## 4. 与其他系统的接口
- **依赖**：② RTwP（消费凝神 released→提交；step_duration 随 `time_scale`）；L2 Grid（落点有效性/位置）；L2 InputManager（步态切换、提交）。
- **发出**（L2 EventBus）：`player_step_committed(StepCommitPayload)` → ④ 声音（按 `noise_radius` 发声）。
- **被依赖**：⑧ HUD 读 `aim_point`/`ghost_trail` 做下一步预演（美术 §8.2）；③ 视野在落足瞬间由 `guard_transform_dirty`/事件驱动重算（ADR-002）。
- **联动**：落足噪声是 ④ 的主要 `SoundSource.FOOTFALL` 源。

## 5. 玩家交互与反馈
- **输入**：步态切换键（默认 `Ctrl`/`B` 循环或 `1/2/3`）；移动轴定 aim_point；松开凝神=提交。
- **Sensation 反馈**（物理/触觉，非庆祝，美术 §1 调性禁区）：
  - 落足**微光**：落地处短暂 `#C8862F` 极低强度光池（≤10% 画面纪律）。
  - **足音 foley**：触觉级「咔/嗒」按 surface 变体（石板硬、木闷、苔软）；字幕带音景图标（**X-02**）。
  - **足迹残影**：落点淡影，`ghost_trail` 最多 6 步（意象④ 地面织锦）。
  - **下一步预演**：aim_point 处 ghost footprint + 落点微光（世界内，非屏框，美术 §8.1）。
- **粒子**：落足扬起微量灰烬（additive，受 T-04 同步）。

## 6. 边界与性能约束
- **无 heavy 预算项**：本系统本身不触发射线/光；成本仅为 Tween/残影（O(步数)）。
- **联动约束**：`noise_radius` 须 ≤ ④ 声环预算；落足事件驱动视野重算（非逐帧，ADR-002）。
- **架构联动**：`architecture.md` §4（步进提交属 L4）；`time_scale` 缩放行为见 ADR-003；粒子 `T-04`。
- **相机**：固定高角 45–60°，落足残影/预演在俯视平面天然可读（概念 §2）。

## 7. 可访问性考量
- **下一步预演常驻**：aim_point ghost 始终可见（不靠玩家记忆落点）。
- **「安全步」轻提示**（可关，风险1 缓解）：当 aim_point 落在阴影且噪声不可达守卫时，给形状/图标提示（非纯色）；可关以防削弱挑战。
- **色盲安全**：落点有效/无效用**亮度+形状**（✓/⊘ 图标）编码，不依赖色相（**C-05**）；微光 `#C8862F` 属主色板（**C-06**）。
- **对比度**：预演落点亮度差 ≥3:1（**C-03**）。
- **对齐清单**：C-03/C-05/C-06、X-02、T-04；美术 §9.1/§9.2。

## 8. 范围分层归属
- **Tier1（必做）**：三步态 + 步进提交 + 足迹残影 + 落足微光/足音 + 下一步预演 + 噪声半径输出。
- **Tier2（期望）**：幽灵回放（ghost-trail 对比，概念 §5 Tier2）——复用 `ghost_trail` 数据，不新增系统。
- **Tier3（拓展）**：照片模式取残影构图；仍复用既有数据。
- **范围纪律**：本系统即概念 §3①，未新增平行机制族；Tier2/3 均为数据复用。
