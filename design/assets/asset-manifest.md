# 资产规格 · Asset Manifest
## 《灰烬之步》ASHEN STEP — Phase 4 预制作资产交付

| 字段 | 值 |
| --- | --- |
| **项目** | ASHEN STEP《灰烬之步》 |
| **引擎 / 平台** | Godot 4.4（Forward+ / Vulkan）· PC·Steam（键鼠 + 手柄） |
| **文档版本** | v0.1（Phase 4 预制作交付） |
| **作者** | 林绘澄（Art Director / 美术与视觉表现指导） |
| **评审强度** | lean（仅核心节点卡质量门） |
| **上游依据** | `design/art/art-bible.md`（视觉身份九节）· `docs/architecture/architecture.md` §4 性能预算 · `docs/architecture/adr/adr-004-lighting-and-shadow-budget.md` · `docs/architecture/control-manifest.md`（R/T/V/C/X/G 约束）· `design/art/accessibility-matrix.md`（三档矩阵 18 行）· `design/gdd/systems/*.md`（8 份八节 GDD）· `design/concept/game-concept.md` §2/§5/§6 |
| **下游衔接** | `design/assets/entity-inventory.md`（实体清单表）· 着色器/VFX 列表 · `docs/architecture/control-manifest.md`（CI 静态断言）· 技术美术（布光/体积雾/地面光照遮罩着色器）· UI 团队（§8 规范落地） |

> **本文用途**：把美术圣经（视觉身份九节）、架构 §4 预算、ADR-004 决策、control-manifest 硬约束与 GDD 实体需求翻译成**可直接执行**的资产规格。资产团队据此产出模型/贴图/动画；技术美术据此布光、写地面光照遮罩着色器与 VFX；CI 据此跑静态断言（control-manifest §7）。任何偏离本规范的资产须在评审标注「视觉漂移 / 性能漂移」并由主理人裁决。
>
> **章节引用约定**：本文「§2 色板 / §3 光照体积 / §4 剪影 / §5 材质 / §6 母题 / §8 UI / §9 可访问性」均指 `art-bible.md` 的实际章节号（art-bible 正文为 §1 视觉基调…§9 可访问性，无 §0；任务简报中的「§0 色调」即 art-bible §2 色彩系统）。凡数值必与 `architecture.md` §4、`adr-004`、`control-manifest` 一致。

---

## 1. 资产总览与管线约束

### 1.1 目标平台与渲染管线锚点
- **渲染器**：Forward+（聚类前向，Vulkan）。依据 `architecture.md` §1 / ADR-001 / control-manifest **R-01**。低配回退 `Compatibility`（GL）：关体雾/动态 GI，保留 LightmapGI（ADR-004）。
- **目标帧率**：**60fps @ 1080p，GTX1060 档**（control-manifest **R-09** / `architecture.md` §4）。
- **相机**：固定高角度俯视 / 等距，约 **45–60° 俯角**（概念 §2，已锁）。所有 LOD 距离、地面光斑、俯视可读要素均按此机位参数化（art-bible §0 / 概念 §2）。

### 1.2 Godot 4.4 资源格式
| 资产类别 | 格式 | 说明 |
| --- | --- | --- |
| 角色 / 环境 / 道具 网格 | **`.glb`**（Blender 导出）→ Godot 导入为 `.tscn` 场景封装 | 推荐 Blender→glTF 2.0/`.glb` 无损导出；Godot 4 原生导入，保留节点/骨骼/UV。最终以 `.tscn` 包裹网格+碰撞+材质。 |
| 场景 / 预制体 | **`.tscn`** | 关卡模块、互动物件、VFX 实例均为 `.tscn`；支持继承与 `.tres` 资源引用。 |
| 材质 / 资源 | **`.tres`** | `StandardMaterial3D` / `ShaderMaterial` / `Texture2D` 引用、LightmapGI 配置等以 `.tres` 存档，便于批量调参与 CI 校验。 |
| 着色器 | **`.gdshader`** | 地面光照遮罩、锥缘脉动、熄灯过场、落足微光等确定性着色器。 |
| 纹理 | **`.png`**（sRGB 贴图）/ **`.exr`**（HDR 自发光/光照遮罩） | 游戏贴图压缩为 `.png`（BC7）；LightmapGI 烘焙产物与 HDR 自发光源用 `.exr`。 |
| 动画 | **`.tres` / 内嵌 `.tscn`**（Animation / AnimationTree / AnimationNodeStateMachine） | 角色步态、FSM 姿态靠 AnimationTree 混合；`time_scale` 自动缩放（ADR-003）。 |

### 1.3 命名规范（强制）
格式：`<category>_<name>[_<variant>][_<lodN>][_<map>].<ext>`

| 前缀 `category` | 含义 | 示例 |
| --- | --- | --- |
| `env` | 静态环境 / 关卡模块 / 遮蔽体 / 光源 fixture | `env_wall_straight_4m_lod0.tscn`、`env_floor_flagstone_stone_lod0.tscn` |
| `chr` | 角色（玩家/守卫/变体） | `chr_player_lod0.tscn`、`chr_guard_hound_lod1.tscn` |
| `itm` | 互动物件 / 道具 / 可熄光源 | `itm_door_wood.tscn`、`itm_candle_stand.tscn`、`itm_decoy.tscn` |
| `vfx` | 视觉反馈（残影/微光/声环/粒子） | `vfx_footstep_trail.tscn`、`vfx_sound_ring.tscn`、`vfx_dust_motes.tscn` |
| `shd` | 着色器 | `shd_ground_lightmask.gdshader`、`shd_cone_edge_pulse.gdshader` |
| `mat` | 共享材质库 | `mat_stone_wall.tres`、`mat_ash_ground.tres` |
| `ui` | HUD/菜单纹理（暗面板） | `ui_panel_dark_70.tres`、`ui_focus_ring.tres` |
| `tex` | 纹理贴图（作为 `mat` 引用源） | `tex_env_wall_albedo.png`、`tex_env_wall_normal.png`、`tex_env_wall_orm.png` |

- **LOD 后缀**：`_lod0`（近，全细节）/ `_lod1`（中，简化）/ `_lod2`（远，剪影/impostor）。无 LOD 后缀者默认 `_lod0`（如互动物件多用单 LOD）。
- **地图后缀（纹理）**：`_albedo` / `_normal` / `_orm`（Occlusion+Roughness+Metalness 合图）/ `_emissive`。
- **目录约定（`res://arts/…`）**：
```
res://arts/
  characters/        player/   guard/   guard/variants/   (hound, sentinel)
  environment/       kit/  cover/  light_fixtures/  windows/
  interactables/     doors/  mechanisms/  decoys/  smoke/
  vfx/               decals/  particles/  rings/
  shaders/
  materials/
  lighting/          (lightmap bake 配置 / WorldEnvironment 预设 / 密度盒)
  ui/                (暗面板纹理 / 焦点环 / 图标图集)
```
- **CI 校验（control-manifest §7）**：命名不符前缀/缺 `_lodN`/静态网格缺 UV2 → 断言告警（lean 不阻断构建，记「漂移」）。

### 1.4 导入预设 / 压缩 / 颜色空间
- **颜色空间**：Albedo / Emissive / Lightmap = **sRGB 线性**；Normal / ORM / Roughness / Metalness = **线性（non-color）**。Godot 导入预设按通道锁定，禁止反向。
- **纹理尺寸上限**（小而精 + GTX1060 约束）：
  | 资产档 | Albedo/Normal 上限 | ORM 上限 | 备注 |
  | --- | --- | --- | --- |
  | Hero / 主角 / 守卫 | 2048² | 2048² | 单角色独占，少量 |
  | 标准静态 / 道具 | 1024² | 1024² | 主体量 |
  | 小道具 / 远LOD | 512² | 512² | 复用 |
  | LightmapGI 烘焙 | 每区域 ≤ 4096²（或 2×2048² 图集） | — | 静态几何每区域一次 bake（R-06） |
- **压缩 / Vulkan 就绪**：桌面压缩 **BC7**（VRAM_COMPRESSED）；`filter=Linear`、`generate_mipmaps=ON`、`repeat=OFF`（除非 tiling 地面）。**强制 mipmap**（LOD + 俯视各距离一致可读性，art-bible §5.3）。**各向异性 8–16**：地面/光池为俯视主舞台，需 aniso 防远景闪烁（art-bible §3.1 意象④）。
- **Texel Density**：统一 **1px ≈ 1–2cm**（art-bible §5.3，待与程基岩 final 定，对齐 §6 开放依赖）。2m 墙在 1024² ≈ 2cm/px，达标。

### 1.5 计量预算（Meter Budget，对齐「小而精」）
| 指标 | MVP（单要塞主关，3–5 子区域） | Tier2（2–3 主题关 + 变体） | 依据 |
| --- | --- | --- | --- |
| 纹理 VRAM（压缩后） | **≤ 200 MB**（含 LightmapGI 烘焙图） | **≤ 384 MB** | GTX1060 3–6GB 余量；LightmapGI 烘焙图计入（R-06） |
| 可见三角面（静态环境/区域） | **≤ 1.5M tris** | **≤ 2.0M tris**（跨区域流式） | 模块化拼接 + LOD（§2） |
| 单角色三角面 | **≤ 15k tris**（玩家/守卫） | 变体同档（猎犬/哨兵） | 骨骼动画 + 实时光余量 |
| 同屏角色总三角面 | **≤ 150k**（含 16 守卫 + 玩家） | 同 | G-01（≤16 同区） |
| Draw call 目标 | **≤ 400/frame** | **≤ 500/frame** | Forward+ 聚类 + 实例化 + 材质图集 + LOD |
| 唯一静态网格（kit） | **~30–40 件**（全关复用） | 同 kit + 材质换色 | 小而精 → 重用以模块化拼接（§3） |
| 每区域实例数 | **~150–300 实例**（来自 ~30–40 唯一网格） | 同 | 模块化拼接 |

> 动态光、声环、雾等「运行时」预算见 §2；其上限由 **R-02 / G-02 / R-04 / R-05** 硬锁，本文资产层不得突破。

---

## 2. 资产分档（Tier）与 LOD

> 所有分档数值严格对齐 `architecture.md` §4 预算表与 ADR-004。MVP = Tier1，Tier2 = 期望层。

### 2.1 动态光预算（control-manifest **R-02** / ADR-004 / `architecture.md` §4）
| 光源类别 | MVP 同屏 | Tier2 同屏 | 投影规则（**R-03**） |
| --- | --- | --- | --- |
| 动态点光总计（Omni/Spot） | **≤ 12** | **≤ 32** | 超 32 → CI 告警（§7） |
| 其中：守卫提灯（Omni） | ≤ 8（MVP 同区上限 G-01） | ≤ 16（Tier2 同区上限 G-01） | **默认 `shadow=false`**（ADR-004） |
| 其中：可互光源（烛/灯/吊灯） | 余量（≤ 4 @MVP） | ≤ 16 余量 @Tier2 | **默认 `shadow=false`** |
| 其中：彩窗 SpotLight 光柱 | ≤ 2 @MVP | ≤ 4 @Tier2 | 默认无投影；计入 32 上限（R-07） |
| 投影光（唯一） | **1（月光 DirectionalLight3D）** | **1 + 高端预设最近 1–2 提灯**（可选） | R-03 硬锁 1；高端预设增 1–2 |

### 2.2 光 LOD 切换（对齐 ADR-004「动态光 LOD」）
固定高角俯视下按**相机距离** + **可见性裁剪**分级；确保 Tier2 16 守卫 + 烛/窗不破 32 上限。

| 距离档（相机相对） | 实时光状态 | Flicker 着色器 | 投影（默认档） | 近似回退 |
| --- | --- | --- | --- | --- |
| **NEAR 0–16m** | OmniLight **ON**，全强度 | ON（art-bible §3.2） | OFF（R-03） | — |
| **MID 16–32m** | OmniLight **ON**，强度略降 | 简化/关 | OFF | — |
| **FAR > 32m** | **实时光 OFF** | — | — | 保留**自发光近似**（烛焰 emissive quad / 提灯 glow 仅视觉），不占 R-02 预算 |

- **彩窗 SpotLight** 同样走 FAR>32m 关实时光、仅留光柱 emissive + 尘埃近似。
- **高端预设**（`Compatibility` 反向：高画质）：NEAR 档可让「最近 1–2 提灯」`shadow=true`（R-03 增项），仍不破 32。
- **静态大光池**走 LightmapGI 烘焙（R-06/R-07），**不占**实时光预算。

### 2.3 模型 LOD（环境 / 角色 / 道具 / 特效）
| 类别 | LOD0（近） | LOD1（中） | LOD2（远） | 切换距离（俯视） |
| --- | --- | --- | --- | --- |
| 环境模块 | 全细节 + 法线 + 磨损 | ~40% 三角面 + 简化材质 | 剪影级低模 + 单色 | 0–20m / 20–40m / >40m |
| 角色 | 全骨骼 + 磨损 + rim | ~50% 三角面（骨骼混合） | impostor（billboard） | 0–15m / 15–30m / >30m |
| 道具 / 互动物 | 单 LOD（多为小物，近看也少） | — | — | 距 >25m 直接剔除 |
| 特效（decal/ring） | 平面 quad，无 LOD（俯视可读） | — | — | 超出相机远裁剪即自毁 |

- LOD 切换须**无 popping**：靠 mipmap + 材质过渡；fade 距离留 2m 缓冲。
- **无阴影纪律**（R-03）：所有 OmniLight3D（提灯/烛/窗）`shadow=false`；仅月光 DirectionalLight3D 投 1 张阴影图。资产层**不产出**任何提灯的 shadow-casting 配置。

### 2.4 体积雾 / 尘埃（control-manifest **R-04 / R-05 / R-08**）
- **WorldEnvironment.volumetric_fog_enabled**：base 密度 **≤ 0.05**（R-04），冷调染色 `#10141C`/`#3E5C76`（art-bible §3.4）；禁暖雾主导（R-04）。
- **熄灯过场**：局部雾 `ramp ≤ 0.12` 且 `≤ 0.4s` 后回落（R-05），ease 非硬切（V-06）。
- **尘埃**（加法粒子，art-bible §3.4 意象②）：仅在点光/月光光柱内可见；**每光柱上限 + 全局 additive ≤ 2000**（R-08）。`GPUParticles3D.time_scale` 凝神同步（**T-04**/ADR-003）。
- **雾选项**（V-04）：提供 FULL / REDUCED / OFF；关雾时世界要素靠边界/图标保可读（accessibility-matrix 行 7）。

---

## 3. 静态环境资产

### 3.1 关卡模块（Kit，模块化拼接，art-bible §4.2 / §5）
~30–40 件唯一网格，全关复用；材质换色产出主题变体（Tier2 地穴/钟楼/王座厅）。

| 模块 | 唯一件数 | 命名示例 | 材质归属（art-bible §5） | LOD |
| --- | --- | --- | --- | --- |
| 墙（直/角/带拱/柱基） | 6 | `env_wall_straight_4m_lod0.tscn` | 石 `#2A2A30`+冷补 `#3E5C76` | 0/1/2 |
| 地（石板/木/苔 → 玩法 STONE/STONE/MOSS，按 §2.3 资产材质→玩法 Surface 映射） | 3+变体 | `env_floor_flagstone_stone_lod0.tscn` | 石/木/苔（art-bible §5.1） | 0/1/2 |
| 柱（瘦/壮/残） | 3 | `env_column_slim_lod0.tscn` | 石 | 0/1/2 |
| 拱（素/饰/毁） | 3 | `env_arch_ornate_lod0.tscn` | 石 | 0/1/2 |
| 台阶/平台 | 2 | `env_stair_flight_lod0.tscn` | 石 | 0/1/2 |
| 长椅/祭坛/滴水兽装饰 | 4 | `env_pew_lod0.tscn` | 木/石 | 0/1/2 |

- **地面光照遮罩着色器**（`shd_ground_lightmask.gdshader`，art-bible §3.1 意象④）：接收 `LightLevel` 遮罩实时绘制光池（暖 `#C8862F`）/ 阴影（冷 `#10141C`/`#3E5C76`）高对比边界——潜行语言主舞台。由 ⑤ cover-shadow 系统驱动（GDD 引用）。
- **surface 元数据对接（资产材质 → 玩法 Surface 映射）**：地面/踏面资产材质须带 `surface` 元数据标签（供落足噪声判定），但**资产 metadata 数值 ≠ 玩法 SURFACE_FACTOR**。权威玩法系数见 `stealth-step-commit` §2 / `system-breakdown` §2.3（单一事实来源）：`SURFACE_FACTOR = {STONE 1.0, GRASS 0.7, METAL 1.2, MOSS 0.5}`。资产侧材质 taxonomy 与玩法集映射如下（本表仅供资产打标签，**禁止把下列「权重」当作玩法乘子写入噪声逻辑**）：
  | 资产材质（taxonomy） | 玩法 Surface | 玩法系数 | 说明 |
  | --- | --- | --- | --- |
  | `STONE` | STONE | 1.0 | 石板/石地 |
  | `WOOD` | STONE | 1.0 | **木地板按 STONE 计**（旧 Sprint 0「WOOD≈STONE」降格为资产→玩法映射；资产侧原 `WOOD 1.0` 权重仅美术命名，非玩法乘子） |
  | `MOSS` | MOSS | 0.5 | 苔地/地毯，最静 |
  | `GRASS` | GRASS | 0.7 | 草径/泥地 |
  | `METAL` | METAL | 1.2 | 铁栅/金属台 |
  - **资产 metadata 旧值 `STONE 1.2 / WOOD 1.0 / MOSS 0.5` 作废为「材质命名权重」**：其中 MOSS 0.5 与玩法巧合一致；`STONE 1.2` 与玩法 `1.0` **不一致**，以玩法 GDD `1.0` 为准（声环直接吃玩法系数）；资产层切勿将 `1.2` 写入噪声逻辑。

### 3.2 可交互物（Interactables，GDD `interactables` §2）
| 物件 | 类型 | 命名 | 视觉暗示（art-bible §4.2） | 事件派发（GDD） |
| --- | --- | --- | --- | --- |
| 门 / 闸门 / 吊闸 | `LIGHT_TOGGLE`? 否，独立 | `itm_door_wood.tscn` | 多一道握柄磨光高光 | —（路径） |
| 拉杆 / 符文面板 / 绞盘 | `TRAP` | `itm_lever.tscn` / `itm_rune_panel.tscn` | 握柄高光 + 符文微 emissive | `interactable_triggered(TRAP)` |
| 可熄光源（烛台/灯/吊灯） | `LIGHT_TOGGLE` | `itm_candle_stand.tscn` / `itm_chandelier.tscn` | 握柄高光 + 自发光焰 | `light_state_changed`（→ ⑤） |
| 声响诱饵（碎石/骨片） | `DECOY` | `itm_decoy.tscn` | 投掷物，落点微光 | `decoy_landed`（→ ④） |
| 障目烟雾 | `SMOKE` | `itm_smoke.tscn` | puff（additive，T-04 同步） | `interactable_triggered(SMOKE)` |

- 互动物件剪影须有「可操作暗示」：比环境同类多一道握柄高光（art-bible §4.2），**不靠颜色**（C-05）。

### 3.3 遮蔽体（Cover / Shadow，art-bible §4.2 / GDD `cover-shadow`）
| 遮蔽体 | 命名 | 视觉 | LOD/光照 |
| --- | --- | --- | --- |
| 阴影块（可移箱/长椅/棺） | `env_cover_crate_lod0.tscn` | 阻断 LOS + 落半影；边缘铺苔强化「藏身处」（art-bible §5.1 苔） | 单 LOD；靠亮度边界编码（C-04） |
| 帷幕（悬挂织物） | `env_cover_curtain_lod0.tscn` | 视觉阻断 + 微透光；朽烂边缘 | 单 LOD；风动轻 shader |

> 掩体**不无敌**：仅降 visibility + 断 LOS（GDD `cover-shadow` §2 `get_cover`）。资产仅提供几何与材质，逻辑交玩法层。

### 3.4 光源 Fixture（无阴影，R-03 / ADR-004）
| Fixture | 命名 | 实时光 | Flicker | 计入 R-02 |
| --- | --- | --- | --- | --- |
| 壁灯 / 烛台（可互） | `itm_candle_stand.tscn` / `itm_sconce.tscn` | OmniLight（`shadow=false`） | ON | 是 |
| 吊灯 | `itm_chandelier.tscn` | OmniLight（多焰合并 1 光） | ON | 是（计 1） |
| 守卫提灯（挂骨骼） | 随 `chr_guard`（见 §4） | OmniLight（`shadow=false`） | ON | 是 |
| 彩窗 + SpotLight 光柱 | `env_window_stained.tscn` | SpotLight（少量） | — | 是（≤4 @Tier2） |

- **可熄灭逻辑**（art-bible §3.3 意象⑤）：每 fixture = 场景节点 + `LightState{LIT,EXTINGUISHED}` + 自发光材质 toggle + flicker shader。熄灭触发 ① OmniLight OFF（R-02 释放）② 自发光熄暗 ③ 局部雾 ramp ≤0.12/≤0.4s（R-05）+ 暗角收拢（vignette，ease，V-06）。
- **光 LOD**（§2.2）：FAR>32m 实时光 OFF，仅留自发光近似。

### 3.5 体积雾密度盒（per-region 调参）
- 每区域 1× `WorldEnvironment` 预设（base ≤0.05，冷调）+ **~2–4 个密度覆盖盒**（`env_fog_density_box` 逻辑节点，非网格）按厅堂/地穴微调「空气密度」。
- 提供 V-04 FULL/REDUCED/OFF 切换；关雾时靠边界/图标补可读（accessibility-matrix 行 7）。

### 3.6 复用策略（小而精 → 模块化拼接）
- **唯一网格少（~30–40），实例多（~150–300/区域）**：靠墙/地/柱/拱模块沿网格（cell≈14m，ADR-002）拼接出递进子区域。
- **材质换色产主题**：Tier2 三主题关复用同 kit，仅 `mat_*` 调冷暖/磨损强度（不破 art-bible §2 色板）。
- **LightmapGI 一次烘焙/区域**（R-06）：静态几何烘焙后运行时零 GI 成本，动态物不进烘焙（art-bible §3.2 / ADR-004）。

---

## 4. 动态实体资产（实体清单）

> 完整表格见 `design/assets/entity-inventory.md`（同仓库）。本节给每实体的**网格复杂度 / 骨骼动画 / 材质数 / 特效钩子**，对齐 GDD 需求与性能预算。

### 4.1 玩家潜行者（MVP 核心，GDD `stealth-step-commit`）
- **网格**：~8–12k tris，瘦高、兜帽、微弓背、单肩披风（art-bible §4.1 剪影）。
- **骨骼**：~40 骨 `CharacterBody3D` + `AnimationTree`（idle / aim / commit-step / recover / **focus-freeze pose**——落足中途可冻结，意象①）。
- **材质**：2（布料/身 + 饰边）；**冷调边缘光**（rim，隐蔽，art-bible §4.1）。
- **特效钩子**：落足微光（`vfx_landing_glow`，emissive quad 非实时光，省 R-02）、足迹残影（`vfx_footstep_trail`，≤6 步淡出）、灰烬扬起（`vfx_ash_puff`，additive，R-08/T-04）、下一步预演（`vfx_nextstep_preview`，ghost footprint + `#C8862F` 微光，世界内非屏框，art-bible §8.2）。
- **无挂光**：玩家不携实时光（潜行），剪影靠冷 rim 浮出暗背景。

### 4.2 守卫·标准（MVP，GDD `vision-cone` / `patrol-ai`）
- **网格**：~12–15k tris，壮硕、肩甲、提灯前举、头盔（art-bible §4.1）。
- **骨骼**：~45 骨；**提灯挂骨节点**带 OmniLight（`shadow=false`，R-03）+ flicker。
- **材质**：3（甲金属暗锈 `#7A2E2E` 点染 / 身 / 提灯）；提灯侧**暖边 rim**（威胁），其余冷边。
- **视野锥**：挂守卫的半透明 `MeshInstance3D` 地面光斑，冷白 `#9FB8C9` 低不透明（art-bible §8.2）；**锥缘脉动 tell**（`shd_cone_edge_pulse`，≤2Hz，V-02）预报「即将扫到」。
- **FSM 姿态可读**（非颜色，art-bible §4.1 / accessibility-matrix）：CALM 垂灯 / SUSPICIOUS 举灯转身 / ALERT 拔刃灯高举 / SEARCH 灯左右扫 / RETURN 归位。
- **特效钩子**：暴露脉动（`#7A2E2E` + 图标 + 可关屏震，C-07/V-03）、可疑度条（HUD，图标+数字+亮度，C-02）。

### 4.3 守卫变体（Tier2，GDD `patrol-ai` §8 / `vision-cone` §8）
| 变体 | 剪影（art-bible §4.1） | 配光 | 备注 |
| --- | --- | --- | --- |
| 循声猎犬 Hound | 低矮四足、长耳、贴地 | 无携光（听觉优先，升声音权重） | 与守卫「高」形成明暗对比；光 LOD 同 §2.2 |
| 暗视哨兵 Sentinel | 极高瘦、无灯、眼有微光 | 无实时光；眼部 micro-emissive（极弱） | 「无灯却可见」反直觉，降 L 阈值逼迫换解法 |

- 二者**复用 FSM + 参数覆盖**（architecture §3.4），不新增系统/不新增资产族；仅网格 + 权重差异。

### 4.4 潜行关键物（视觉反馈，详见 §5）
- 足音残影、落足微光、下一步预演、声波环、凝神压暗、暴露 ALERT —— 均为 near-diegetic（世界内），不破坏肃穆压迫（art-bible §1 红线 / §8.1）。

### 4.5 噪声源 / 交互道具
- **诱饵**（`itm_decoy`）：投掷落点 micro 光 + 声环（GDD `sound-propagation`）；charges 限量，HUD 显示（art-bible §8.1）。
- **烟雾**（`itm_smoke`）：additive puff，`time_scale` 同步（T-04），临时 visibility×0.3（GDD `interactables`）。
- **机关**（拉杆/符文/绞盘）：触发声/光/阻事件（GDD `interactables` §2）。

---

## 5. 视觉反馈资产（near-diegetic，art-bible §8.1 / §8.2）

| 反馈 | 美术实现 | 资产 | 编码 / 约束 |
| --- | --- | --- | --- |
| **足迹残影** | 落地淡影 quad 链，冷调，≤6 步 Tween 淡出（意象④） | `vfx_footstep_trail.tscn` | 位置+亮度，非色相（C-05）；俯视可读 |
| **下一步预演** | aim_point 处 ghost footprint + `#C8862F` 极低微光（世界内） | `vfx_nextstep_preview.tscn` | 亮度+形状（✓/⊘ 图标）非色相（C-05/C-03）；无效落点用图标非纯色（stealth-step-commit §7） |
| **落足微光** | 落地短暂 `#C8862F` 极低强度光池（emissive quad，**非实时光**以省 R-02） | `vfx_landing_glow.tscn` | 主色板内（C-06）；≤10% 画面纪律（art-bible §2.1） |
| **声波环** | 同心圆扩散（Tween/shader 自毁），冷 `#3E5C76`，形状编码 | `vfx_sound_ring.tscn` | 形状+扩散+标签非色相（C-05/C-03）；同屏 ≤8（G-02） |
| **凝神态压暗遮罩** | WorldEnvironment 曝光降 + 自定义 vignette（`shd_focus_vignette`），**世界空间、无霓虹** | `shd_focus_vignette.gdshader` | 压暗四周提亮可读要素（概念 §2）；ease 非硬切（V-06）；不破肃穆（art-bible §8.4） |
| **暴露 ALERT** | `#7A2E2E` + 脉动（≤2Hz，V-02）+ 图标 + 可关屏震（V-03） | `vfx_exposure_alert.tscn` + `ui_icon_alert` | **绝不单色**（C-07）；色盲模式→`#C8862F` 高亮+图标（C-06） |
| **可疑度指示** | 细条 + 图标（眼/问号/叹号）+ 亮度递增 | `ui_suspicion_bar` | 图标+数字+亮度，颜色仅辅助（C-02 ≥7:1） |
| **灰烬/尘埃** | additive 粒子，微暖 `#C8862F` 极低（光柱内） | `vfx_dust_motes.tscn` / `vfx_ash_puff.tscn` | 全局 additive ≤2000（R-08）；`time_scale` 同步（T-04） |

> **四支柱一致性**：所有反馈走「质地」非「烟花」（art-bible §1 调性禁区）；熄灯/暴露靠物理触觉反馈，成功感受是「在黑暗里活下来」。

---

## 6. 可访问性合规（资产层覆盖 accessibility-matrix 相关行）

> 依据 `accessibility-matrix.md` 18 行矩阵与 `control-manifest` C-/X-/V- 约束。**资产层达成合规不引入新工艺约束**——仅靠：① 色板纪律（art-bible §2.3）+ ② 着色器参数（脉动频率/亮度边界）+ ③ 图标精灵图集预留槽位。无新增工具链步骤（仅 art-bible §2.3 既有 Protan/Deutan/Tritan 自检）。

| 矩阵行 | 特性（约束号） | 资产层落地 | 引入新工艺？ |
| --- | --- | --- | --- |
| **行 1** | 对比度达标（C-01/C-02/C-03） | 色板纪律 + UI 暗面板 `#1B1B1F`@70–85% + `#3E5C76` 描边（art-bible §8.1）；世界要素亮度差 ≥3:1（锥缘/落点，C-03） | 否（CI 断言既存） |
| **行 2** | 亮度/边界编码（C-04/C-03） | 地面光照遮罩着色器（`shd_ground_lightmask`）使光池 vs 阴影靠**亮度边界**非冷/暖色；emissive decal 承载边界 | 否（着色器参数） |
| **行 3** | 色盲三重编码（C-05/C-07） | 锥缘脉动（亮度+形状+位置）、声环（形状+扩散）、暴露（色彩+图标+脉动）；危险 `#7A2E2E` 必配图标（C-07）；**图标精灵图集预留槽** | 否（既存精灵+着色器） |
| **行 14** | 输入可达焦点环（§9.4） | `ui_focus_ring` 用 `#C8862F` 细描边不靠颜色；键盘/手柄可达 | 否（UI 资产） |
| **行 15** | 音频可视化素材预留（X-02/§8.2） | 声环已是世界内可视化；预留**音景类型图标精灵集**（说/足音/诱饵/警示）供 Comprehensive 增强 | 否（预留槽，不新增约束） |
| **行 16** | 辅助落足/路径提示（§8.2） | 复用 §5 下一步预演资产（`vfx_nextstep_preview`）——Comprehensive 安全落点高亮即同资产调亮，不新资产 | 否（复用核心资产） |
| **行 17** | 自定义配色主题（C-01/C-02/C-06） | 资产全在主色板内；主题系统仅调明度/强调色明度，每次切换过 C-01/C-02 自检（不引入新色相，对齐 §2.4） | 否（UI/引擎侧） |

**未列入资产层（交 UI/引擎/程基岩）**：行 4 色盲模式开关逻辑、行 5/6/8/9 频闪/转场/屏震/动模糊开关、行 7 雾选项、行 10/11/12 时间缩放/文本/字幕、行 13/14 输入重映射逻辑、行 18 认知负荷——资产层仅提供**可被这些开关驱动的素材**（如 emissive 强度、脉动幅度、雾 density 接口），不自行实现开关。

**眩护参数（资产着色器须内置上限）**：暴露/锥缘脉动 **≤2Hz**（V-02）、幅度温和；禁止 >3Hz 频闪（V-01）；转场 ease 非硬切（V-06）；熄灯雾 ramp ≤0.12/≤0.4s（R-05）。这些为着色器常量上限，CI 断言核对（control-manifest §7）。

---

## 附录 A · 待回填 / 开放依赖
- **Texel Density 精确值**：art-bible §5.3 待与程基岩按预算 final（本文暂定 1px≈1–2cm）。
- **LightmapGI bake 流程 / UV2 规范**：CI 检查缺 UV2（ADR-004 / control-manifest §7）；资产导出须带 UV2。
- **高端预设阴影增项**：最近 1–2 提灯 `shadow=true` 的选取策略（R-03 增项）交技术美术/程基岩。
- **图标精灵图集**：行 3/15 所需图标（眼/问号/叹号/✓/⊘/音景类型）由 UI 资产产出，本文预留命名 `ui_icon_*`。

## 附录 B · 文档接口
- **实体清单表**：`design/assets/entity-inventory.md`（§4 详细表，含 实体名/资产类型/复杂度档/关键视觉特征/LOD光照规则/可访问性备注）。
- **下游**：技术美术据 §2.2/§2.4/§3.4/§5 写着色器与布光；UI 据 §5/§6 落地 HUD；CI 据命名/UV2/光上限/声环/脉动跑断言（control-manifest §7）。

---

*资产规格 v0.1 完成（Phase 4 预制作）。所有数值对齐 architecture §4、ADR-004、control-manifest 与 GDD；视觉对齐 art-bible 九节。任何后续资产若偏离，须在评审标注「视觉漂移 / 性能漂移」并由主理人裁决。*
