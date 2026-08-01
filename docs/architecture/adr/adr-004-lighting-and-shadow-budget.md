---
status: Accepted
date: 2026-07-31
deciders: 程基岩
tags: [lighting, lightmapgi, shadows, performance]
upstream: design/art/art-bible.md §3 光照与体积；design/concept/game-concept.md 风险5
---

# ADR-004 光照与阴影预算：烘焙 GI + 无投影动态提灯 + 光 LOD

## 状态
**Accepted（已采纳，Phase 2 基线）**

## 上下文
美术 §3 要求：静态几何 `LightmapGI` 烘焙、动态光压到最低（可互光源 + 提灯）、体积雾冷调低密度、彩窗光柱。Forward+ 支持多实时光，但实时光 + 投影在中端 PC 仍有成本，须给守卫上限（风险5）留余量。

## 决策
- **静态几何**：全部静态网格走 `LightmapGI` 烘焙（每区域一次 bake；需规范 UV2）。动态物体（玩家、守卫、移动道具）不进烘焙，仅受实时光。
- **实时光构成**：月光 `DirectionalLight3D`（冷 `#3E5C76`，弱填充，长影）+ 守卫提灯 `OmniLight3D`（暖 `#C8862F`，半径受限，flicker shader）+ 可熄烛 / 灯 `OmniLight3D` + 彩窗 `SpotLight3D` 光柱（少量）。
- **投影策略（关键省钱项）**：**仅月光 `DirectionalLight3D` 投阴影**（1 张阴影图）。守卫提灯 `OmniLight3D` **默认无投影**（`shadow = false`）——其威胁由「地面光池 + 锥体」传达，而非投射阴影。高端画质预设可额外让「最近 1–2 盏提灯」投影。
- **动态光 LOD**：同屏实时点光上限 **≤ 32**（MVP ≤ 12）。Tier2 守卫上限 16 时，远处守卫提灯降为**自发光近似 / 关闭实时光**（按相机距离 + 可见性裁剪），确保不破 32 上限。
- **体积雾**：`WorldEnvironment.volumetric_fog_enabled`，密度 base ≤ 0.05 冷调；熄灯过场 ramp ≤ 0.12 且 ≤ 0.4s 回落（见 control-manifest R-04/R-05）。
- **尘埃**：加法粒子仅在光柱 / 点光内可见，每光柱上限 + 全局 additive 上限（CI 断言，control-manifest R-08）。

## 备选
- **每盏提灯都投影**：拒绝——16 盏投影 OmniLight 在中端 PC 不可持续，且视觉收益低（威胁已由光池 / 锥传达）。
- **全动态 GI（SDFGI / VoxelGI）**：拒绝——实时 GI 成本高于烘焙，且本作静态为主，LightmapGI 足够；SDFGI 可作高端预设增强。
- **无烘焙全实时**：拒绝——静态大场景实时 GI 不可行。

## 后果
- **正向**：动态光预算宽松，守卫上限不受光照拖累；烘焙一次，运行时零 GI 成本。
- **负向**：LightmapGI 需 UV2 规范与 bake 流程（CI 检查 UV2 缺失）。
- **风险**：Tier2 16 守卫需严格光 LOD 纪律，否则破 32 上限——由 control-manifest 硬约束 + 编辑器断言保障。
- **联动**：见 `architecture.md` §4 预算表、ADR-001、control-manifest R-01~R-09。
