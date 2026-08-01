# 系统 GDD · 视野锥系统（vision-cone）
**Phase 2 · 八节 GDD · 优先级 P2（依赖 ⑤ 光影成员）**

> 上游：`design/concept/game-concept.md` §3 Mechanics②、§6 意象③；`docs/architecture/adr/adr-002-stealth-compute-model.md`（10Hz 错峰/LOS/网格/光影成员）；`docs/architecture/control-manifest.md` G-01/G-03、C-03/C-05/C-07、V-02；`design/art/art-bible.md` §3.1、§4.1/§4.3、§8.2。

---

## 1. 系统目标与支柱对齐
- **目标**：守卫拥有可视锥 + 真实 LOS；**光影敏感度**——亮处看得远、暗处视野收缩；玩家在阴影≈不可见，踏入光池立即纳入锥内。锥缘给「即将扫到」预警 tell。
- **支柱对齐**：
  - 支柱四 **肃穆压迫**：「被注视的恐惧」——锥缓扫如眼（意象③）。
  - 支柱一 **步步为营**：威胁一眼可读，支撑规划。
- **为何存在**：把「看见」变成可被玩家读、可被光影操纵的确定量（非黑箱），是 deliberate 手感的前提。

## 2. 核心机制与规则
- **锥几何** `VisionCone{origin, forward, half_angle, range}`：默认 `half_angle=35°`、`range=14m`（= 网格 cell 尺寸，ADR-002）。
- **检测流程**（每守卫 **10Hz 错峰** tick，G-03）：
  1. 网格查询候选（玩家 + 0–2 干扰物，O(1) 哈希）。
  2. 角度+射程过滤：`angleTo ≤ half_angle AND dist ≤ range`。
  3. `intersect_ray`（遮挡层：墙/柱/门）做 LOS（经 L2 SpatialQueryWrapper，统一 mask）。
  4. 光影成员测试：查 ⑤ `get_light_level(target)`。
- **可见性公式**：
  ```
  InCone = (angleTo ≤ half_angle) AND (dist ≤ range) AND LOS_clear
  visibility = InCone ? clamp01((L - L_DARK) / (L_BRIGHT - L_DARK)) : 0.0
  # L = get_light_level(target)；L_DARK=0.20, L_BRIGHT=0.60（见 ⑤）
  ```
  - `L ≥ 0.60` → visibility=1.0（光池必检测）；`L ≤ 0.20` → ≈0（阴影不可见）。
- **锥缘 tell（looming）**：当玩家在锥缘外 `margin=8°` 内且守卫转身将扫及 → 发 `vision_looming(guard_id)`，锥缘 shader **脉动 ≤2Hz**、幅度温和（**V-02**）；不靠色相编码（C-05）。
- **事件驱动重算**（ADR-002）：`guard_transform_dirty` / `light_state_changed` / `player_step_committed` 立即置脏相关 cell。

## 3. 数据模型与状态
```gdscript
struct VisionCone:
    var origin: Vector3
    var forward: Vector3
    var half_angle: float = 35.0   # deg
    var range: float = 14.0        # m，= grid cell

class VisionSystem:               # L4
    var cones: Dictionary[int, VisionCone]
    const TICK_HZ: float = 10.0    # 错峰（G-03）
    const EDGE_MARGIN_DEG: float = 8.0
    const PULSE_HZ_MAX: float = 2.0   # V-02

    func compute_visibility(guard_id, target) -> float: ...  # 上面公式
```
- 可视化：挂守卫的半透明 `MeshInstance3D` 地面光斑，冷白 `#9FB8C9` 低不透明（美术 §8.2）；边界脉动由 shader 实现（频率受 V-02 封顶）。

## 4. 与其他系统的接口
- **依赖**：L2 SpatialQueryWrapper（LOS 射线）、L2 Grid（候选查询）、⑤ `get_light_level`（光影成员）、②（tick 用真实时间，不随 time_scale）。
- **发出**：`vision_stimulus(guard_id, target, visibility)`（→ ⑥ 累加可疑度）、`vision_looming(guard_id)`（→ ⑧ 锥缘 tell）。
- **被依赖**：⑥ Patrol AI 消费 `vision_stimulus` 驱动 FSM；⑧ HUD 绘制锥/脉动。
- **联动 ADR-002**：10Hz 错峰 + 网格 + 事件置脏；成本随「活动守卫×tick」非帧率（architecture §4 成本模型）。

## 5. 玩家交互与反馈
- **世界内可视化**（diegetic，美术 §8.1）：地面半透明冷白光斑 + 锥缘脉动 tell；玩家落足残影/微光自身不暴露，除非进光池（由 ⑤ 判定）。
- **状态可读**：守卫姿态传达状态（非颜色，美术 §4.1）——平静垂灯 / 可疑举灯转身 / 警戒拔刃 / 搜索扫灯；视野锥随姿态转向。
- **Sensation**：锥缘脉动是「被注视」的紧张质地，非庆祝（美术 §1 调性）。

## 6. 边界与性能约束
- **G-01** 同区活动守卫 MVP ≤8 / Tier2 ≤16（锥 10Hz 错峰 + 网格）。
- **G-03** 锥体重算 ≤10Hz/守卫（错峰，事件置脏非逐帧）。
- **LOS 射线峰值**：MVP ≈160 射线/s（8×10×2），Tier2 ≈480/s（16×10×3）；BVH 单射线 ~数十 µs，帧均 <0.2ms（architecture §4）。
- **C-03** 锥缘/落点预演世界要素亮度差 ≥3:1。
- **V-02** 暴露/锥缘脉动 ≤2Hz，幅度温和。
- **架构联动**：`architecture.md` §3.1/§4；ADR-002（均匀网格 cell≥最大射程防跨 cell 漏检）。

## 7. 可访问性考量
- **三重编码**：锥缘状态靠「亮度+形状（脉动环）+位置」编码，不依赖单一色相（**C-05**）；色盲模式开启追加图标（美术 §9.1）。
- **对比度**：锥缘亮度差 ≥3:1（**C-03**）；世界可读要素不靠冷/暖色判断（**C-04**）。
- **危险提示不单色**：涉及暴露的 `#7A2E2E` 必配形状/脉动/图标（**C-07**）。
- **对齐清单**：C-03/C-04/C-05/C-07、G-01/G-03、V-02；美术 §8.2/§9.1。

## 8. 范围分层归属
- **Tier1（必做）**：单锥（half_angle 35°/range 14m）+ LOS + 光影敏感度 + 10Hz 错峰 + 锥缘 tell（≤2Hz）+ 事件驱动重算。
- **Tier2（期望）**：守卫变体——暗视哨兵（暗处仍可见，降 L 阈值）、循声猎犬（降视觉权重升听觉，见 ④/⑥）；仍复用 VisionCone + 参数覆盖，不新增系统。
- **Tier3（拓展）**：多锥/广角变种（参数扩展）。
- **范围纪律**：本系统即概念 §3②；变体以参数/权重覆盖实现（architecture §3.4），未新增平行机制族。
