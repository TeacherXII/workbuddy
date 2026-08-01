# Epic E03 · 步进提交 / 读—步循环（stealth-step-commit）

- **对应 GDD**：`design/gdd/systems/stealth-step-commit.md`（GDD ①）
- **层**：L4 玩法/模拟层（架构 §2）
- **依赖**：E02（focus-release 提交 + step_duration 缩放）、E01（EventBus / SpatialHashGrid3D / InputManager）
- **DAG 优先级**：P1
- **MoSCoW**：**Must** ｜ **T 恤**：M
- **上游**：概念 §3①（步进提交）/§4（核心循环）；ADR-003；control-manifest T-04；art-bible §1/§3.3/§8.2

## 目标
把「移动」变成「可读、可权衡、带即时反馈的落足承诺」——每次提交在地面留足迹残影，落足瞬间给触觉级音效，使「一步」成为可感知实体。本系统是「读—步」循环的主动词（支柱一 步步为营 核心载体）。

## 范围（In Scope）
- Step 状态机（`IDLE/AIMING/COMMITTING/RECOVERING`）+ 读间隙纪律（仅 IDLE 接受提交，冷却 ≥0.12s 真实时间）。
- 三步态 `SNEAK/WALK/RUN` + 参数（max_step/step_duration/gait_factor）+ 噪声半径公式 `BASE(5.0)×surface_factor×gait_factor`。
- aim_point 预演 + ghost_trail(≤6) + 落足微光/足音 + `player_step_committed(StepCommitPayload)`。
- 落点约束（max_step 内 / 非实心 / 非守卫身位）+ 无效落点形状化提示（C-05）。

## 关键 Story 列表

### E03-S1 · 作为（玩家）我要（提交一步且步间有读间隙）以便（避免连击式位移，保 deliberate 手感）
**Sprint 0**：是
**验收**
- Given 概念 §3 设计红线「不做爽快连击式位移，每步间必有读间隙」；stealth-step-commit §2「仅 IDLE 接受提交，COMMIT_COOLDOWN_RT=0.12s」。
- When 状态机为 `COMMITTING`/`RECOVERING` 时再次请求提交。
- Then 拒绝提交（仅 `IDLE` 接受）；上一步 `RECOVERED` 且冷却 ≥0.12s 真实时间（E02-S3）后才接受下一次。
**关联**：概念 §3①（红线）；stealth-step-commit §2；ADR-003 风险4（真实时间冷却）。

### E03-S2 · 作为（玩家）我要（切换 SNEAK/WALK/RUN 步态）以便（权衡步幅/速度/噪声）
**Sprint 0**：是（SNEAK + WALK；RUN Sprint 1 或 Tier2，见 consistency-review 取舍1）
**验收**
- Given 参数表：SNEAK max_step1.5/step_duration0.55/gait_factor0.5；WALK 2.5/0.38/1.0；RUN 4.0/0.24/2.0。
- When 玩家经 E01 InputManager 切换步态并提交。
- Then 落足距离/step_duration/噪声系数按所选步态应用；step_duration 受 `time_scale` 缩放（ADR-003）。
**关联**：stealth-step-commit §2；ADR-003（step_duration 缩放）；consistency-review 取舍1（RUN 高成本 deliberate 选项）。

### E03-S3 · 作为（玩家）我要（FOCUS 中看下一步落点预演）以便（提交前已知落哪）
**Sprint 0**：是
**验收**
- Given stealth-step-commit §5/§7「aim_point 处 ghost footprint + #C8862F 微光，世界内非屏框；亮度+形状（✓/⊘）编码非色相（C-05/C-03）」。
- When 玩家在 FOCUS 中移动瞄准轴。
- Then 预演 ghost footprint 与落点微光实时跟随 aim_point；无效落点（越界/实心/守卫身位）显 ⊘ 图标（非纯色）。
**关联**：stealth-step-commit §5/§7；core-hud-a11y §2（世界内预演）；control-manifest C-03/C-05。

### E03-S4 · 作为（系统）我要（提交落足时发 player_step_committed）以便（驱动声音/视野重算）
**Sprint 0**：是
**验收**
- Given system-breakdown §2「player_step_committed(StepCommitPayload{from,to,surface,gait,noise_radius}) → ④」。
- When 一步提交完成、角色落足。
- Then 发射 `player_step_committed`（含 from/to/surface/gait/noise_radius），触发 E04/E05 事件驱动重算（ADR-002 非逐帧）。
- Then 断言：commit 后 `last_to`==落点且信号已发射（见 `tests/unit/test_step_commit.gd::test_commit_moves_player_to_landing_point`）。
**关联**：system-breakdown §2；ADR-002（事件驱动重算）；stealth-step-commit §4。

### E03-S5 · 作为（系统）我要（按地面材质×步态算噪声半径）以便（声音系统按 noise_radius 发声）
**Sprint 0**：是（公式 + SNEAK/WALK；MOSS 在 Sprint 1 配 surface 元数据）
**验收**
- Given `noise_radius = BASE(5.0)×surface_factor×gait_factor`；surface_factor STONE1.2/WOOD1.0/MOSS0.5。
- When 提交一步（surface 取自地面元数据，asset-manifest §3.1）。
- Then `noise_radius` = SNEAK+STONE 3.0 / WALK+WOOD 5.0 / RUN+STONE 12.0（示例）；写入 payload 供 E06。
**关联**：stealth-step-commit §2；sound-propagation §2；asset-manifest §3.1（surface_factor 元数据）。

### E03-S6 · 作为（玩家）我要（落足有微光+足音+残影）以便（一步有质感反馈）
**Sprint 0**：是（微光 + 足音 + ghost_trail≤6 最小版）
**验收**
- Given art-bible §1 调性禁区「反馈走物理/触觉，非庆祝」；stealth-step-commit §5（落足微光 ≤10% 画面纪律 / 足音 foley / ghost_trail≤6）。
- When 角色落足。
- Then 落点 `#C8862F` 极低微光（emissive quad 非实时光，省 R-02）；surface 变体足音 foley（石板硬/木闷/苔软，字幕带音景图标 X-02）；ghost_trail 最多 6 步 Tween 淡出（受 time_scale，ADR-003）。
**关联**：stealth-step-commit §5/§7；art-bible §1/§8.2；control-manifest C-06（主色板）/X-02（字幕）/T-04（粒子同步）/R-02（微光省预算）。

### E03-S7 · 作为（可访问性玩家）我要（安全步轻提示可关）以便（降低挫败但不削弱挑战）
**Sprint 0**：否（Sprint 2，a11y）
**验收**
- Given stealth-step-commit §7「安全步轻提示（可关，风险1 缓解）：aim_point 落阴影且噪声不可达守卫时给形状/图标提示（非纯色）」。
- When aim_point 落在安全处。
- Then 给出形状/图标提示（非纯色，C-05）；设置可关（经 E01 A11ySettings）。
**关联**：stealth-step-commit §7；consistency-review 风险1；control-manifest C-05。

## 依赖
E02（focus-release 提交；step_duration 缩放；冷却真实时间）、E01（EventBus/Grid/InputManager/A11ySettings）。发出 `player_step_committed` → E06；触发 E04/E05 重算。被依赖：E09（aim_point/ghost_trail 预演）。

## 整 Epic 验收标准
1. 仅 `IDLE` + 冷却 ≥0.12s 真实时间接受提交（无连击）。
2. 三步态参数与噪声半径公式正确；noise_radius 写入 payload。
3. `player_step_committed` 在落足时发射（驱动 E06/E04/E05）。
4. 预演（ghost footprint + 微光）常驻且亮度+形状编码（C-03/C-05）；无效落点显 ⊘ 图标。
5. 落足微光 ≤10% 画面、足音 foley、ghost_trail≤6 均落地。

## 风险
- **R-步-1**：连击破坏 deliberate 手感。缓解：E03-S1 状态机 + 真实时间冷却。
- **R-步-2**：微光/残影若用实时光会破 R-02。缓解：emissive quad 非实时光（asset-manifest §5）。
- **R-步-3**：慢放下动画/残影需随 time_scale，否则不同速。缓解：ADR-003 自动缩放 + T-04 粒子同步。

## 与架构 + 控制清单勾稽
- 架构 §2（L4 玩法层，不直接触引擎底层）、§4（步进提交属 L4，无 heavy 预算项）。
- ADR-003（time_scale 缩放 step_duration/残影；输入实时；冷却真实时间）。
- control-manifest：T-04（粒子同步）、C-03（预演亮度差≥3:1）、C-05（形状/亮度编码）、C-06（微光主色板）、R-02（微光非实时光省预算）、X-02（足音字幕）。
- stealth-step-commit §8（Tier1 三步态+提交+残影+微光+预演+噪声；Tier2 幽灵回放复用数据）。
