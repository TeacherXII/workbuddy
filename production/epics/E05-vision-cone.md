# Epic E05 · 视野锥（vision-cone）

- **对应 GDD**：`design/gdd/systems/vision-cone.md`（GDD ③）
- **层**：L4 ↔ L2（SpatialQueryWrapper / SpatialHashGrid3D，架构 §2）
- **依赖**：E04（get_light_level / L_DARK / L_BRIGHT）、E01（SpatialQueryWrapper LOS / Grid / EventBus）
- **DAG 优先级**：P2（依赖 E04 光影成员）
- **MoSCoW**：**Must** ｜ **T 恤**：M
- **上游**：概念 §3②（视野）/§6（意象③）；ADR-002（10Hz 错峰/LOS/网格/光影成员）；control-manifest G-01/G-03、C-03/C-05/C-07、V-02；art-bible §3.1/§4.1/§8.2

## 目标
守卫拥有可视锥 + 真实 LOS；光影敏感度——亮处看得远、暗处视野收缩；玩家在阴影≈不可见，踏入光池立即纳入锥内。锥缘给「即将扫到」预警 tell。把「看见」变成可被玩家读、可被光影操纵的确定量（支柱四 肃穆压迫 / 支柱一 步步为营）。

## 范围（In Scope）
- `VisionCone{origin,forward,half_angle=35°,range=14m}` + 每守卫 10Hz 错峰 tick（G-03）。
- `compute_visibility`：InCone×LOS_clear×光影系数 `clamp01((L-L_DARK)/(L_BRIGHT-L_DARK))`。
- LOS 经 E01 SpatialQueryWrapper（遮挡层）；`vision_stimulus`/`vision_looming` 信号。
- 锥缘 tell（脉动 ≤2Hz V-02）、外部 `visibility_multiplier`（烟雾/掩体，C3）、地面光斑可视化。

## 关键 Story 列表

### E05-S1 · 作为（系统）我要（每守卫以 10Hz 错峰重算检测集）以便（成本随活动守卫×tick 非帧率）
**Sprint 0**：是（单守卫单锥切片）
**验收**
- Given ADR-002「锥体/LOS 节流：每守卫 10Hz（错峰）重算」；control-manifest G-03「≤10Hz/守卫（错峰，事件置脏非逐帧）」；architecture §4「锥 10Hz/守卫」。
- When 守卫检测 tick 触发。
- Then 每守卫决策频率 ≤10Hz，多守卫错峰（不同时刻）；事件置脏时立即重算相关 cell。
- Then 断言：单守卫在 1s 内检测 tick 次数 ≤10（见 `tests/` 节流桩，Sprint 1 补完整计数测试）。
**关联**：ADR-002；control-manifest G-03；architecture §4（锥体重算频率）；G-01（≤8/≤16 守卫）。

### E05-S2 · 作为（系统）我要（按 InCone×LOS×光影算可见性）以便（亮必检/暗不可见）
**Sprint 0**：是
**验收**
- Given vision-cone §2 公式：`visibility = InCone ? clamp01((L-L_DARK)/(L_BRIGHT-L_DARK)) : 0.0`；L_DARK0.20/L_BRIGHT0.60（来自 E04-S2）。
- When 对 (in_cone, light_level, los_clear) 求 visibility。
- Then L≥0.60→1.0（光池必检测）；L≤0.20→≈0（阴影不可见）；非锥内或 LOS 阻断→0。
- Then 断言：见 `tests/unit/test_vision_cone.gd`（test_player_in_dark_is_invisible / test_player_in_light_pool_is_detected / test_blocked_los_yields_zero）。
**关联**：vision-cone §2；cover-shadow §2（阈值）；tests/unit/test_vision_cone.gd。

### E05-S3 · 作为（系统）我要（经 SpatialQueryWrapper 做 LOS）以便（L4 不直接调射线）
**Sprint 0**：是
**验收**
- Given 架构 §2「L4 不直接调 PhysicsDirectSpaceState3D，须经 L2 空间查询封装（统一遮挡层 mask）」；ADR-002「LOS 仅对遮挡层（墙/柱/门）intersect_ray」。
- When 候选在锥内、需判定遮挡。
- Then 经 E01 SpatialQueryWrapper 查询，仅遮挡层参与，返回 blocked/clear。
**关联**：架构 §2；ADR-002；E01-S3。

### E05-S4 · 作为（E08）我要（发出 vision_stimulus）以便（累加可疑度）
**Sprint 0**：是
**验收**
- Given system-breakdown §2「vision_stimulus(guard_id, target, visibility[0..1]) → ⑥」。
- When 每 tick 算得 visibility。
- Then 发射 `vision_stimulus(guard_id, target, visibility)`（即便 Sprint 0 无 E08 消费，信号契约已存在，供 Sprint 1 E08 接入）。
**关联**：system-breakdown §2；vision-cone §4；E08（消费方）。

### E05-S5 · 作为（玩家）我要（锥缘给即将扫到的 tell）以便（预警被注视）
**Sprint 0**：否（Sprint 1）
**验收**
- Given vision-cone §2「vision_looming：玩家在锥缘外 margin=8° 内且守卫转身将扫及 → 发 vision_looming(guard_id)；锥缘 shader 脉动 ≤2Hz、幅度温和（V-02）」；不靠色相编码（C-05）。
- When 玩家进入锥缘 8° 预警带。
- Then 发 `vision_looming`（→ E09 锥缘 tell）；脉动频率 ≤2Hz、幅度温和（着色器常量上限，CI 断言 V-02）。
**关联**：vision-cone §2/§5；control-manifest V-02（≤2Hz）/C-05/C-07；E09（tell 绘制）。

### E05-S6 · 作为（E07）我要（接受外部 visibility_multiplier）以便（烟雾/掩体临时改写可见性）
**Sprint 0**：否（Sprint 1，consistency-review C3）
**验收**
- Given consistency-review C3「烟雾(⑦)如何改写③可见性：compute_visibility 应接受外部 visibility_multiplier（烟雾/掩体注入）」。
- When 目标处于烟雾区(E07 SMOKE)或掩体(E04 get_cover)。
- Then `compute_visibility` 结果 × visibility_multiplier（烟雾 ×0.3，GDD interactables §2）；不新增系统。
**关联**：consistency-review C3；interactables §2（SMOKE ×0.3）；cover-shadow §2（get_cover）。

### E05-S7 · 作为（玩家）我要（看见锥与地面光斑）以便（威胁一眼可读）
**Sprint 0**：是（最小：静态半透明锥 patch 可见）；完整脉动 Shader Sprint 1
**验收**
- Given vision-cone §3/§5「挂守卫的半透明 MeshInstance3D 地面光斑，冷白 #9FB8C9 低不透明；边界脉动由 shader（V-02 封顶）」；art-bible §8.2（世界内可读）。
- When 守卫在场。
- Then 地面半透明冷白锥 patch 可见（俯视可读）；Sprint 1 加锥缘脉动 tell（≤2Hz）。亮度差 ≥3:1（C-03）。
**关联**：vision-cone §3/§5；art-bible §8.2；control-manifest C-03（亮度差≥3:1）/V-02（脉动≤2Hz）/C-04（不靠色相）。

## 依赖
E04（get_light_level / 阈值 / light_state_changed → 触发重算）、E01（SpatialQueryWrapper / Grid / EventBus）。发出 `vision_stimulus`/`vision_looming` → E08/E09。被依赖：E08（驱动 FSM）、E09（绘制锥/脉动）。

## 整 Epic 验收标准
1. 单锥 half_angle 35°/range 14m；每守卫 ≤10Hz 错峰（G-03）；活动守卫 ≤8(MVP)/≤16(Tier2)（G-01）。
2. `compute_visibility` 正确：光池必检、阴影不可见、LOS 阻断归零。
3. LOS 经 E01 封装（遮挡层），L4 不直接调射线。
4. `vision_stimulus`/`vision_looming` 信号契约存在。
5. 锥缘脉动 ≤2Hz（V-02）；亮度差 ≥3:1（C-03）；形状/亮度编码非色相（C-04/C-05）。

## 风险
- **R-锥-1**：网格 cell < 最大锥射程 → 跨 cell 漏检。缓解：cell 锁 14m（E01-S2 / ADR-002）。
- **R-锥-2**：锥缘脉动若 >2Hz 触发光敏。缓解：V-02 着色器常量上限 + E10 CI 断言。
- **R-锥-3**：烟雾/掩体可见性未注入 → 掩体变无敌。缓解：E05-S6（C3）。

## 与架构 + 控制清单勾稽
- 架构 §2（L4↔L2）、§3.1（LOS 经封装）、§4（锥 10Hz、射线峰值 MVP≈160/s、Tier2≈480/s、守卫 8/16）。
- ADR-002（10Hz 错峰 + 网格 + 事件置脏 + 光影成员）。
- control-manifest：G-01（守卫≤8/16）、G-03（≤10Hz）、V-02（脉动≤2Hz）、C-03（亮度差≥3:1）、C-04（不靠色相）、C-05（三重编码）、C-07（危险不单色）。
- vision-cone §8（Tier1 单锥+LOS+光影+10Hz+tell；Tier2 变体参数覆盖）。
