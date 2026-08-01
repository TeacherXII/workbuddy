# Epic E04 · 掩体 / 阴影与可熄灯（cover-shadow）

- **对应 GDD**：`design/gdd/systems/cover-shadow.md`（GDD ⑤）
- **层**：L4 ↔ L2（LightState / LightmapGI，架构 §2）
- **依赖**：E01（LightState 接口/注册、SpatialHashGrid3D cell、EventBus）
- **DAG 优先级**：P1（须先于 E05，因视野「光影敏感度」依赖 get_light_level）
- **MoSCoW**：**Must** ｜ **T 恤**：M
- **上游**：概念 §3④（掩体阴影）/§6（意象⑤）；ADR-002（事件驱动重算 cell）；ADR-004；control-manifest R-02/R-03/R-04/R-05/R-06；art-bible §3.1/§3.3/§4.3

## 目标
把「阴影」变成可消耗资源——藏身于阴影池/物体后；并允许玩家主动熄灯/遮光制造阴影，改写空间可读性。为 E05 视野锥「光影敏感度」与 E08 AI 可见性判定提供统一 `LightLevel` 查询 API。

## 范围（In Scope）
- `get_light_level(pos)->[0,1]`（LightmapGI 烘焙 + 动态光叠加 + 月光底填充）；阈值 `L_DARK=0.20`/`L_BRIGHT=0.60`。
- `get_cover(pos)->bool`（降 visibility + 断 LOS，非无敌）。
- LightState 注册（LIT/EXTINGUISHED）+ `light_state_changed`/`cover_state_changed` 事件。
- 可熄灯过场（雾 ramp≤0.12/≤0.4s R-05 + vignette ease V-06）、光 LOD（ADR-004 / R-02 ≤32）。

## 关键 Story 列表

### E04-S1 · 作为（E05/E08）我要（查询任意点的光照等级）以便（判定可见性/阴影）
**Sprint 0**：是（接口 + mock 返回 [0,1]；完整实现 Sprint 1）
**验收**
- Given cover-shadow §2/§3「get_light_level(pos)=LightmapGI_baked + Σ dynamic_light_overlay + 月光底填充；0.0=死黑 #10141C，1.0=满光池 #C8862F」。
- When E05 在检测时对 target 调 `get_light_level`。
- Then 返回 [0,1]；Sprint 0 切片用 mock/程序化值驱动 E05（真实 LightmapGI 烘焙在 E04 完整 + E10 资产管线）。
- Then 断言：L≤0.20→E05 visibility≈0；L≥0.60→≈1.0（见 `tests/unit/test_vision_cone.gd`）。
**关联**：cover-shadow §2/§3；vision-cone §2（visibility 公式）；patrol-ai §2。

### E04-S2 · 作为（系统）我要（暴露 L_DARK/L_BRIGHT 阈值）以便（统一明暗边界判定）
**Sprint 0**：是
**验收**
- Given cover-shadow §2「L_dark=0.20（以下≈不可见），L_bright=0.60（以上=光池必检测）」。
- When 任意系统引用阈值。
- Then 常量 `L_DARK=0.20`/`L_BRIGHT=0.60` 由 E04 统一提供，E05/E08 不得各自硬编码。
**关联**：cover-shadow §2；vision-cone §2；patrol-ai §2。

### E04-S3 · 作为（系统）我要（查询掩体）以便（降可见度 + 断 LOS）
**Sprint 0**：否（Sprint 1，配合 E05/E08）
**验收**
- Given cover-shadow §2「get_cover(pos)：位于遮挡体邻接半影且断 LOS 候选；掩体不无敌，仅降 visibility 系数+LOS 中断」。
- When E05/E08 评估 target。
- Then `get_cover` 返回 bool；仅降低 visibility 系数并提供 LOS 中断，不保证无敌（仍可被绕射/声音出卖）。
**关联**：cover-shadow §2/§3；consistency-review C3（烟雾/掩体注入）。

### E04-S4 · 作为（E07）我要（切换光源状态并发 light_state_changed）以便（改写空间可读性）
**Sprint 0**：是（LightState 注册 + 事件契约）；完整熄灯过场 Sprint 1
**验收**
- Given system-breakdown §2「light_state_changed(light_id, state{LIT,EXTINGUISHED}) → ③ 视野重算受影响 cell」；cover-shadow §4。
- When 光源状态变更（经 E07 熄灯动作）。
- Then LightState 字典更新，`light_state_changed(light_id, state)` 发射，E05 仅重算受影响 cell（ADR-002 事件驱动）。
**关联**：system-breakdown §2；cover-shadow §4；ADR-002（事件驱动重算 cell）。

### E04-S5 · 作为（玩家）我要（熄灯制造黑暗吞没）以便（主动创造解法）
**Sprint 0**：否（Sprint 1）
**验收**
- Given cover-shadow §2「熄灭 → OmniLight3D 关 + 自发光熄暗 + 局部雾 ramp≤0.12 且 ≤0.4s 回落（R-05）+ 暗角收拢（vignette ease V-06）」。
- When 玩家熄灯。
- Then 释放 R-02 实时光预算；局部体积雾 ramp≤0.12/≤0.4s 后回落；vignette ease 非硬切；重亮反向。
- Then 断言：熄灯后受影响 cell 内 `get_light_level` 下降，E05 重算（非全图）。
**关联**：cover-shadow §2/§5；control-manifest R-05（ramp≤0.12/≤0.4s）/V-06（ease）/R-02/R-03；ADR-004；asset-manifest §3.4/§5。

### E04-S6 · 作为（性能）我要（远处提灯降为自发光近似/关实时光）以便（Tier2 16 守卫不破 32 上限）
**Sprint 0**：否（Sprint 2）
**验收**
- Given ADR-004「Tier2 远处守卫提灯降为自发光近似/关实时光（按相机距离+可见性裁剪），确保不破 32 上限」；asset-manifest §2.2（NEAR0–16/MID16–32/FAR>32）。
- When 守卫距相机 >32m。
- Then 实时 OmniLight OFF，仅保留 emissive 近似（不占 R-02）；雾选项 V-04 下世界要素仍可读。
**关联**：ADR-004（光 LOD）；control-manifest R-02（≤32）；asset-manifest §2.2；consistency-review C2。

### E04-S7 · 作为（系统）我要（事件驱动仅重算受影响 cell）以便（成本 O(cell) 非全图）
**Sprint 0**：是（最小：light_state_changed 触发 cell 重算钩子）
**验收**
- Given ADR-002「light_state_changed → 仅重算受影响 cell 内目标 LightLevel（O(cell) 非全图）」；control-manifest G-03（非逐帧）。
- When `light_state_changed`/`cover_state_changed` 到达。
- Then 仅受影响 cell 内目标重算，无全图重算；节流（非逐帧）。
**关联**：ADR-002；control-manifest G-03；架构 §4（成本随活动守卫×tick 非帧率）。

## 依赖
E01（LightState 接口/注册、Grid cell、EventBus）。发出 `light_state_changed`/`cover_state_changed` → E05；被依赖：E05（get_light_level）、E08（可见性判定）、E07（熄灯动作触发）、E09（光池/阴影绘制）。

## 整 Epic 验收标准
1. `get_light_level` 返回 [0,1]，阈值 L_DARK/L_BRIGHT 统一暴露。
2. `get_cover` 正确（降可见度+断 LOS，非无敌）。
3. `light_state_changed`/`cover_state_changed` 在状态变更时发射，E05 仅重算受影响 cell。
4. 熄灯过场雾 ramp≤0.12/≤0.4s、vignette ease（R-05/V-06）。
5. 光 LOD 在 Tier2 远处关实时光，不破 R-02 32 上限。

## 风险
- **R-影-1**：LightmapGI 需 UV2 规范 + bake 流程，否则动态物体无间接光。缓解：E01-S7 + E10 CI 校验 UV2（ADR-004 负向）。
- **R-影-2**：Tier2 16 守卫 + 动态光逼近 32 上限。缓解：E04-S6 光 LOD + R-02/CI（consistency-review C2）。
- **R-影-3**：事件驱动若漏发 dirty → 陈旧可见性。缓解：E04-S7 + E10 断言。

## 与架构 + 控制清单勾稽
- 架构 §2（L4↔L2 LightState）、§3.1（静态 LightmapGI 烘焙）、§4（动态点光/投影光/雾预算）。
- ADR-004（LightmapGI + 无投影提灯 + 光 LOD ≤32）。
- control-manifest：R-02（≤12/≤32）、R-03（投影仅月光）、R-04（雾 base≤0.05）、R-05（熄灯 ramp≤0.12/≤0.4s）、R-06（LightmapGI 烘焙）；§7（UV2/光上限断言）。
- asset-manifest §2.1/§2.2/§3.4/§5（光预算/LOD/可熄逻辑）。
