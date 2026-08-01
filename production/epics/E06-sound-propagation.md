# Epic E06 · 声音传播（sound-propagation）

- **对应 GDD**：`design/gdd/systems/sound-propagation.md`（GDD ④）
- **层**：L4 ↔ L2（SpatialHashGrid3D / EventBus，架构 §2）
- **依赖**：E01（Grid / EventBus）、E03（player_step_committed 落足噪声）、E07（decoy_landed / interactable_triggered）
- **DAG 优先级**：P2（依赖 E03 落足 + E07 诱饵）
- **MoSCoW**：**Must** ｜ **T 恤**：S
- **上游**：概念 §3③（声音）/§6；ADR-002（声环≤8、网格通知）；control-manifest G-02、C-05、X-02；art-bible §8.2

## 目标
脚步噪声 = f(地面材质, 步态)；可投掷声响诱饵制造可控噪声圈引开守卫；噪声以可视化声波环扩散，玩家可预判波及范围。与 E05 视野、E04 光影共同构成「多系统咬合」的临场张力（支柱一 步步为营 / 支柱三 自主掌控）。

## 范围（In Scope）
- `SoundPayload{origin,radius,intensity,source}` + `emit()`（网格通知半径内守卫 + 生成声环）。
- 噪声半径由 E03 公式给定（本系统不改写）；诱饵 base≈8m（E07）。
- 声波环 VFX：同心圆 Tween/shader 自毁，**同屏 ≤8**（G-02，FIFO 淘汰最旧）。
- `sound_emitted(SoundPayload)` → E08（按 `intensity×(1−dist/radius)` 提可疑度）。

## 关键 Story 列表

### E06-S1 · 作为（系统）我要（emit 声事件并通知网格内守卫）以便（E08 按距离提可疑度）
**Sprint 0**：否（Sprint 1）
**验收**
- Given ADR-002「声事件按网格查 radius 内守卫 → sound_emitted → ⑥ 按 intensity×(1−dist/radius) 提可疑度（O(半径内守卫)）」；system-breakdown §2「sound_emitted(SoundPayload) → ⑥」。
- When `emit(payload)` 调用。
- Then 经 E01 Grid 查询 radius 内守卫，逐个发 `sound_emitted`；成本 O(半径内守卫)。
**关联**：ADR-002；system-breakdown §2；sound-propagation §2/§4。

### E06-S2 · 作为（系统）我要（用 E03 的 noise_radius 发落足声）以便（噪声可权衡）
**Sprint 0**：否（Sprint 1）
**验收**
- Given stealth-step-commit §2「noise_radius=BASE(5.0)×surface×gait」；player_step_committed 携带 noise_radius。
- When E03 发 `player_step_committed`。
- Then E06 订阅并生成 `SoundPayload{origin=to, radius=noise_radius, intensity=由 gait 派生, source=FOOTFALL}`。
**关联**：stealth-step-commit §2/§4；sound-propagation §2/§4；system-breakdown §2。

### E06-S3 · 作为（玩家）我要（看见声波环且同屏≤8）以便（预判噪声波及，不破预算）
**Sprint 0**：否（Sprint 1）
**验收**
- Given control-manifest G-02「同屏声环 VFX ≤8（Tween/shader 自毁）」；sound-propagation §2「RING_CAP=8，FIFO 淘汰最旧环」；consistency-review C1（密集落足逼近上限）。
- When 生成声环（足音/诱饵/机关）。
- Then 同屏最多 8 个 RingVFX；超出按 FIFO 淘汰最旧（自毁）；CI 断言同屏>8 告警（control-manifest §7）。
- Then 断言：并发生成 10 环 → 存活 ≤8（Sprint 1 补 `tests/` 计数断言）。
**关联**：control-manifest G-02；sound-propagation §2/§6；consistency-review C1；art-bible §8.2（同心圆形状编码）。

### E06-S4 · 作为（玩家）我要（投诱饵生成可控噪声圈）以便（引开守卫）
**Sprint 0**：否（Sprint 1，配合 E07）
**验收**
- Given sound-propagation §2「⑦ decoy_landed → 生成 DECOY 声事件（可控半径≈8m）」；interactables §2「DECOY decoy_landed(pos,surface,radius≈8m) → ④」。
- When E07 发 `decoy_landed`。
- Then E06 生成 `SoundPayload{source=DECOY, radius≈8m}`，按网格通知守卫前往调查（减其对玩家路径权重，见 E08）。
**关联**：sound-propagation §2；interactables §2；system-breakdown §2（decoy_landed）。

### E06-S5 · 作为（E08）我要（按距离衰减提可疑度）以便（声音驱动警戒）
**Sprint 0**：否（Sprint 1）
**验收**
- Given patrol-ai §2「sound_in_range = intensity×(1−dist/radius) 来自 ④ sound_emitted」；GDD ⑥ KV35/KS15/DECAY8。
- When `sound_emitted` 到达 E08。
- Then E08 按 `intensity×(1−dist/radius)` 累加可疑度（suspicion += KS15×该项）。
**关联**：patrol-ai §2；sound-propagation §2；system-breakdown §2。

## 依赖
E01（Grid / EventBus）、E03（player_step_committed → 落足噪声）、E07（decoy_landed / interactable_triggered → DECOY/TRAP 声）。发出 `sound_emitted` → E08。被依赖：E08（提可疑度）、E09（绘制声环）。

## 整 Epic 验收标准
1. `SoundPayload` 经 `emit` 通知半径内守卫（O(半径内守卫)）。
2. 落足声用 E03 noise_radius；诱饵声 radius≈8m。
3. 同屏声环 ≤8（FIFO 自毁）；CI 断言同屏>8（G-02 / §7）。
4. `sound_emitted` 携带 intensity×(1−dist/radius) 供 E08。

## 风险
- **R-声-1**：密集落足（8 守卫+玩家）瞬时逼近声环 8 上限。缓解：E06-S3 FIFO + C1 已知非阻塞。
- **R-声-2**：噪声半径若被本系统膨胀 → 破玩法权衡。缓解：半径仅由 E03 公式给定，E06 不改写（sound-propagation §2）。

## 与架构 + 控制清单勾稽
- 架构 §2（L4↔L2 Grid）、§4（声环≤8、成本 O(半径内守卫)）。
- ADR-002（声环 Tween/shader 自毁、≤8、网格通知 O(半径内守卫)）。
- control-manifest：G-02（声环≤8）、C-05（形状编码非色相）、X-02（字幕说话者+音景图标）、§7（同屏>8 告警）。
- sound-propagation §8（Tier1 落足+诱饵+声环+网格通知；Tier2 循声猎犬权重）。
