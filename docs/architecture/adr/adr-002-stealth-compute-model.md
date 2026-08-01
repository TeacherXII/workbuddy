---
status: Accepted
date: 2026-07-31
deciders: 程基岩
tags: [stealth, vision-cone, los, spatial-partition, performance]
upstream: design/concept/game-concept.md §2 Mechanics、风险5；design/art/art-bible.md §8
---

# ADR-002 潜行系统计算模型：事件驱动 + 空间分区

## 状态
**Accepted（已采纳，Phase 2 基线）**

## 上下文
核心「读—步」循环依赖：守卫可视锥 + 真实 LOS + 光影敏感度 + 声波扩散 + 可疑度连续状态机。若每帧对全图重算（守卫 × 目标 × 射线），在守卫上限与 60fps 下成本不可控，且与风险5「事件驱动 + 空间分区」设计意图冲突。

## 决策
采用 **事件驱动重算 + 均匀空间网格（`SpatialHashGrid3D`）+ 节流 tick**：

- **空间索引**：自定义 `SpatialHashGrid3D`，cell ≈ 守卫锥最大射程（≈ 14m）。实体（玩家、守卫、诱饵、互动物）移动时更新网格条目（O(1) 哈希），cell 尺寸以最大射程定值锁死，防跨 cell 漏检。
- **锥体 / LOS 节流**：每守卫以 **10Hz（错峰）** 重算检测集——网格查询候选（通常仅玩家 + 0–2 干扰物），对角度 + 射程内候选用 `PhysicsDirectSpaceState3D.intersect_ray(PhysicsRayQueryParameters3D.create(...))` 做 LOS（仅遮挡层：墙/柱/门），并查「光影成员」：目标处于 LightmapGI 阴影区或动态光覆盖外 → 隐蔽；位于光池 → 必检测。
- **事件驱动触发**：以下事件立即置脏并重算相关 cell——守卫 transform 变化超阈值、玩家步进落足、可熄光源开关（重算受影响 cell 内目标光影成员）、诱饵落点（声波事件）。
- **状态机节流**：可疑度 FSM 决策 **5–10Hz**；A\* 寻路（`NavigationAgent3D`）**仅在状态转换**（Calm→Alert/Search）触发并缓存路径，非逐帧。
- **声波可视化**：声事件离散产生，扩张声环用 `Tween` / shader 动画后自毁，同屏 ≤ 8；声事件同时按网格通知半径内守卫提升可疑度（O(半径内守卫)）。

## 备选
- **四叉树 / 八叉树**：更优稀疏非均匀场景，但均匀网格实现成本低、本作固定机位 + 区域化密度可接受——选定网格；若后期出现大开放区再升级八叉树。
- **逐帧暴力全图重算**：拒绝——成本随 fps 与守卫数线性爆炸，违反风险5。
- **GPU 计算着色器批量射线**：过度工程，lean 范围拒绝；10Hz 网格方案 CPU 成本已可忽略（见 `architecture.md` §4 成本模型）。

## 后果
- **正向**：锥/LOS 成本只随「活动守卫数 × tick 率」而非帧率增长 → 守卫上限可上探 MVP 8 / Tier2 16；慢动作下帧率仍 60 但 tick 不变，收益更大。
- **负向**：需严格保证所有状态变更走事件总线 + dirty 标志，否则出现「陈旧可见性」bug（如熄灯后守卫仍看到玩家）。
- **风险**：网格 cell 尺寸须 ≥ 最大锥射程，否则跨 cell 漏检——以最大射程定值锁 cell。
- **联动**：预算数字见 `architecture.md` §4；事件 / 脏标志规范见后续 GDD。
