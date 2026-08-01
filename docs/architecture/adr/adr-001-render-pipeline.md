---
status: Accepted
date: 2026-07-31
deciders: 程基岩
tags: [rendering, godot4, forward-plus, performance]
upstream: design/art/art-bible.md §3；design/concept/game-concept.md 风险5
---

# ADR-001 渲染管线选型：Forward+（聚类前向）

## 状态
**Accepted（已采纳，Phase 2 基线）**

## 上下文
《灰烬之步》为 PC/Steam 黑暗奇幻 3D 潜行，固定高角度机位。视觉靠大量点状暖光（守卫提灯、可熄烛灯、彩窗光柱）+ 体积雾 + 烘焙 GI 营造「肃穆压迫」。目标在中端 PC（GTX 1060 / RX 580 档）稳定 60fps@1080p。

候选管线：
- **Forward+**（Vulkan 聚类前向，Godot 4 桌面默认）
- **Forward Mobile**（移动 GPU 路径，实时光数受限、部分特性裁剪）
- **Compatibility**（GL 回退，特性最少）

## 决策
采用 **Forward+** 作为主渲染器。依据：
1. 聚类前向原生支持**同屏数十个实时点光**而无需手动合并——直接满足「提灯 + 烛灯 + 彩窗光柱」多光源潜行语言。
2. 完整支持 **Volumetric Fog、`LightmapGI`/`SDFGI`/`VoxelGI`、Decals**——覆盖美术 §3 全部需求。
3. PC/Steam 目标承诺 Vulkan，Forward+ 为零配置最优路径。

提供 **Compatibility（GL）作为低配回退预设**：检测到无 Vulkan 1.0+ 时自动降级，关闭体积雾 / 动态 GI，仅保留 LightmapGI 与有限动态光。

**Forward Mobile 不采用**（非移动目标，且特性子集不如 Forward+ 完整，与美术 §3 冲突）。

## 备选
- **Forward Mobile**：拒绝——目标非移动，且牺牲体雾 / 动态 GI，与美术 §3 冲突。
- **Compatibility 作主渲染**：拒绝——GL 后端实时光数与特性受限，无法支撑多提灯潜行语言。
- **自研延迟渲染**：拒绝——lean 范围，Godot 已有 Forward+，自研成本高回报低。

## 后果
- **正向**：多光源、体雾、烘焙 GI 开箱即用；动态光预算宽松（见 ADR-004）。
- **负向**：要求桌面 GPU 支持 Vulkan；极老显卡需走 Compatibility 回退（功能降级但可玩）。
- **风险**：Forward+ 在个别 AMD 旧驱动 / 集成显卡上偶有排序异常——QA 矩阵须覆盖。
- **联动**：渲染预算数字见 `architecture.md` §4 与 `control-manifest.md` R-01~R-09。
