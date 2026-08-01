# 实体资产清单 · Entity Inventory
## 《灰烬之步》ASHEN STEP — Phase 4 预制作（资产规格附表）

| 字段 | 值 |
| --- | --- |
| **项目** | ASHEN STEP《灰烬之步》 |
| **引擎 / 平台** | Godot 4.4（Forward+ / Vulkan）· PC·Steam |
| **文档版本** | v0.1 |
| **作者** | 林绘澄（Art Director） |
| **上游依据** | `design/assets/asset-manifest.md`（主表 §4）· `design/art/art-bible.md`（§2 色板 / §4 剪影 / §5 材质 / §8 UI）· `design/gdd/systems/*.md` · `docs/architecture/control-manifest.md` |
| **下游衔接** | 技术美术（布光/着色器/VFX）· 资产生产 · CI 断言 |

> **本文用途**：把 `asset-manifest.md` §4 动态实体与 §3/§5 静态/反馈资产展开为**逐实体清单表**，供资产生产与 CI 校验直接引用。列：实体名 | 资产类型 | 复杂度档 | 关键视觉特征（对齐美术§色板/剪影）| LOD/光照规则 | 可访问性备注。
> **复杂度档**：MVP = Tier1 必做；Tier2 = 期望层。静态 kit 标 MVP（Tier2 复用 + 材质换色）。
> **光照规则**严格对齐 control-manifest **R-02/R-03**（动态光≤12/≤32、投影仅月光）+ ADR-004 光 LOD。

---

## 实体清单表

| # | 实体名 | 资产类型 | 复杂度档 | 关键视觉特征（对齐 art-bible §色板/剪影） | LOD / 光照规则 | 可访问性备注 |
| --- | --- | --- | --- | --- | --- | --- |
| 1 | **玩家潜行者** Player Stalker | `chr`（角色网格 + 骨骼） | MVP | 瘦高、兜帽、微弓背、单肩披风（§4.1）；**冷调 rim 边光**（隐蔽）；无外显武器光；落足中途可冻结 Pose（意象①） | LOD0/1/2（0–15/15–30/>30m）；**不携实时光**（潜行） | 下一步预演常驻（C-05）；落点亮度差 ≥3:1（C-03）；微光主色板内（C-06） |
| 2 | **守卫·标准** Guard Standard | `chr` + 挂骨 OmniLight | MVP | 壮硕、肩甲、提灯前举、头盔（§4.1）；提灯侧**暖边 rim**（威胁）；提灯暖 `#C8862F` 光弧（意象③） | LOD0/1/2；挂骨 OmniLight `shadow=false`（R-03）+ flicker；光 LOD 见 §2.2（FAR>32m 关实时光） | 状态靠姿态+道具非颜色（C-05）；可疑度条图标+数字+亮度（C-02） |
| 3 | **守卫·循声猎犬** Hound | `chr` | Tier2 | 低矮四足、长耳、贴地（§4.1）；与守卫「高」明暗对比；听觉优先 | LOD0/1/2；无携光；光 LOD 同 §2.2 | 三重编码（C-05）；复用 FSM 参数（不新增系统） |
| 4 | **守卫·暗视哨兵** Sentinel | `chr` | Tier2 | 极高瘦、无灯、眼有极弱 micro-emissive（§4.1）；「无灯却可见」反直觉 | LOD0/1/2；无实时光；眼部 emissive 极弱（不占 R-02） | 三重编码（C-05）；降 L 阈值逼迫换解法 |
| 5 | **视野锥·地面光斑** Vision Cone Patch | `vfx`（半透 MeshInstance3D） | MVP | 地面半透明冷白 `#9FB8C9` 低不透明（§8.2）；**锥缘脉动 tell**（≤2Hz，V-02）预报「即将扫到」 | 随守卫位置/朝向；光 LOD 跟随守卫（FAR 提灯关光时锥仍由 emissive 近似可见） | 亮度+形状+位置三重（C-05）；边界 ≥3:1（C-03）；不靠色相（C-04） |
| 6 | **足迹残影** Footstep Ghost Trail | `vfx`（decal quad 链） | MVP | 落地淡影，冷调；≤6 步 Tween 淡出（意象④ 地面织锦） | 平面 quad，无 LOD；超出相机远裁剪自毁 | 位置+亮度非色相（C-05）；俯视可读 |
| 7 | **下一步预演落点** Next-Step Preview | `vfx`（ghost footprint + 微光） | MVP | aim_point 处 ghost footprint + `#C8862F` 极低微光（世界内非屏框，§8.2） | 平面 quad，无 LOD；随 aim 实时更新 | 亮度+形状（✓/⊘ 图标）非色相（C-05/C-03）；无效落点图标非纯色 |
| 8 | **落足微光** Landing Glow | `vfx`（emissive quad，非实时光） | MVP | 落地短暂 `#C8862F` 极低强度光池（≤10% 画面纪律，§2.1） | 平面 quad，无 LOD；极短存活 | 主色板内（C-06）；省 R-02（非实时光） |
| 9 | **声波环** Sound Ring | `vfx`（Tween/shader 同心圆） | MVP | 冷 `#3E5C76` 扩张同心圆，形状编码（§8.2） | 平面 quad，自毁；**同屏 ≤8**（G-02，FIFO） | 形状+扩散+标签非色相（C-05/C-03）；字幕带音景图标（X-02） |
| 10 | **声响诱饵** Decoy (碎石/骨片) | `itm`（投掷物） | MVP | 小石/骨片；落点 micro 光 + 声环（GDD `sound-propagation`） | LOD 单档；charges 限量 | 图标+标签非颜色（C-05）；字幕说话者+音景图标（X-02） |
| 11 | **障目烟雾** Smoke Screen | `vfx`（additive particles） | MVP | 落点 puff，临时 visibility×0.3（GDD `interactables`） | additive 粒子；`time_scale` 同步（T-04） | 形状化非纯色（C-05）；不破肃穆 |
| 12 | **可熄光源·烛台** Candle Stand | `itm` + OmniLight（toggle） | MVP | 烛台比环境多握柄高光（§4.2）；自发光焰 + flicker | OmniLight `shadow=false`（R-03）；光 LOD §2.2；熄灭释放 R-02 + 雾 ramp≤0.12/≤0.4s（R-05） | 互动物图标非色（C-05）；低亮屏可辨（C-03） |
| 13 | **壁灯 / 吊灯** Sconce / Chandelier | `itm` + OmniLight | MVP | 暗锈金属 + 微反光（§5.1）；吊灯多焰合并 1 光 | OmniLight `shadow=false`（R-03）；光 LOD §2.2；计入 R-02（吊灯计 1） | 同上（C-05/C-03） |
| 14 | **彩窗 + 光柱** Stained Glass + Spot | `env` + SpotLight | Tier2 | 碎裂微暖透光冷蓝玻璃（§5.1/意象②）；SpotLight + 体积雾 + 尘埃三联 | SpotLight 少量（≤4 @Tier2），无投影；光 LOD §2.2；计入 R-02/R-07 | 关雾时靠边界补可读（行 7）；尘埃 additive≤2000（R-08） |
| 15 | **门 / 闸门 / 吊闸** Door / Gate | `itm`（互动物） | MVP | 木门握柄磨光高光（§5.1）；形状干净硬朗（§4.2） | LOD 单档（小物）；距>25m 剔除 | 握柄高光暗示可操作（C-05） |
| 16 | **机关·拉杆/符文/绞盘** Lever / Rune / Winch | `itm`（TRAP） | MVP | 握柄高光 + 符文 micro-emissive（§4.2） | LOD 单档 | 图标+标签非颜色（C-05）；触发字幕音景图标（X-02） |
| 17 | **遮蔽体·阴影块** Cover Crate / Pew | `env`（cover） | MVP | 可移箱/长椅/棺；边缘铺苔强化「藏身处」（§5.1 苔） | LOD 单档；阻断 LOS + 半影 | 靠亮度边界编码（C-04）；掩体不无敌（GDD `cover-shadow`） |
| 18 | **遮蔽体·帷幕** Curtain | `env`（cover） | MVP | 悬挂织物，朽烂边缘，微透光 | LOD 单档；轻风动 shader | 视觉阻断 + 亮度边界（C-04） |
| 19 | **环境模块 Kit**（墙/地/柱/拱/阶） | `env`（模块化拼接） | MVP | 哥特尖拱/滴水兽/长椅，形状干净硬朗（§4.2）；painterly 石/木/苔（§5） | LOD0/1/2（0–20/20–40/>40m）；~30–40 唯一件复用 ~150–300 实例/区域 | 光池 vs 阴影靠亮度边界（C-04）；地面带 surface_factor 元数据（噪声） |
| 20 | **体积雾密度盒** Fog Density Box | 逻辑节点（非网格） | MVP | 每区域 1× WorldEnvironment（base≤0.05 冷调，R-04）+ ~2–4 覆盖盒 | 事件驱动（仅可见区）；V-04 FULL/REDUCED/OFF | 关雾时世界要素靠边界/图标补可读（行 7） |
| 21 | **尘埃 / 灰烬粒子** Dust / Ash Motes | `vfx`（additive GPUParticles） | MVP | 光柱内微暖 `#C8862F` 极低加法粒子（意象②）；落足扬起微量灰烬 | additive，仅光柱/点光内可见；全局 ≤2000（R-08）；`time_scale` 同步（T-04） | 不破肃穆（§1）；眩晕防护靠 R-08 封顶 |
| 22 | **暴露 ALERT 指示** Exposure Alert | `vfx` + `ui` 图标 | MVP | `#7A2E2E` + 脉动（≤2Hz，V-02）+ 图标 + 可关屏震（V-03） | shader 常量上限；HUD 角标 | **绝不单色**（C-07）；色盲模式→`#C8862F`高亮+图标（C-06） |
| 23 | **可疑度条** Suspicion Bar | `ui` | MVP | 细条 + 图标（眼/问号/叹号）+ 亮度递增 | HUD 角标，近 guard 或固定 | 图标+数字+亮度，颜色仅辅助（C-02 ≥7:1） |
| 24 | **凝神态压暗遮罩** Focus Vignette | `shd`（后处理/世界空间） | MVP | WorldEnvironment 曝光降 + 自定义 vignette，世界空间无霓虹（§8.4） | ease 非硬切（V-06）；`time_scale` 联动 | 压暗四周提亮可读要素（概念 §2）；不破肃穆（§1 红线） |

---

## 汇总（量级与约束速查）

- **动态角色实体**：1 玩家 + 1 标准守卫 + 2 Tier2 变体 = **4 类角色资产**（变体复用 FSM/骨骼，不新增系统族）。
- **同区活动守卫峰值**：MVP ≤8 / Tier2 ≤16（G-01）→ 角色实时光峰值 ≤16 提灯（R-02 余量留给烛/窗 ≤16）。
- **视觉反馈实体（near-diegetic）**：残影 / 预演 / 落足微光 / 声环 / 暴露 / 可疑度 / 凝神压暗 = **7 类 VFX/UI 资产**，全部世界内、不破坏肃穆（§1/§8.1）。
- **静态环境实体**：~30–40 唯一 kit 件（墙/地/柱/拱/阶/装饰）+ 遮蔽体 2 + 光源 fixture 4 + 彩窗（Tier2）+ 雾盒 → **模块化拼接复用**支撑 3–5 子区域（Tier1）/ 2–3 主题关（Tier2）。
- **互动物件实体**：门/闸门、拉杆/符文/绞盘、可熄烛台、诱饵、烟雾 = **5 类**（`interactables` §2 四类 + 门），charges 限量、事件派发既有动词。

## 引用闭合
- 色板 §2 / 剪影 §4 / 材质 §5 / UI §8：见 `design/art/art-bible.md`。
- 动态光 ≤12/≤32、投影仅月光、雾 ≤0.05 / ramp≤0.12·≤0.4s、声环 ≤8：见 `docs/architecture/control-manifest.md`（R-02/R-03/R-04/R-05/G-02）与 `architecture.md` §4。
- 光 LOD / 无阴影提灯 / LightmapGI：见 `docs/architecture/adr/adr-004-lighting-and-shadow-budget.md`。
- 可访问性行 1/2/3/14/15/16/17：见 `design/art/accessibility-matrix.md`。

---

*实体资产清单 v0.1 完成（Phase 4 预制作）。与 asset-manifest.md 一一对应；数值对齐 architecture §4、ADR-004、control-manifest 与 GDD。*
