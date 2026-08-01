# 系统 GDD · 掩体/阴影与可熄灯（cover-shadow）
**Phase 2 · 八节 GDD · 优先级 P1（先于视野锥）**

> 上游：`design/concept/game-concept.md` §3 Mechanics④、§6 视觉锚点意象⑤；`docs/architecture/adr/adr-002-stealth-compute-model.md`（事件驱动重算 cell）；`docs/architecture/adr/adr-004-lighting-and-shadow-budget.md`；`docs/architecture/control-manifest.md` R-02/R-03/R-05/R-06；`design/art/art-bible.md` §3.1/§3.3/§4.3。

---

## 1. 系统目标与支柱对齐
- **目标**：把「阴影」变成**可消耗资源**——藏身于阴影池/物体后；并允许玩家**主动熄灯/遮光**制造阴影（互动物件），改写空间可读性。
- **支柱对齐**：
  - 支柱一 **步步为营**：阴影是规划要素（落哪一步进暗处）。
  - 支柱三 **自主掌控**：可熄灯=玩家主动创造解法，克制「唯一解」。
  - 支柱二 **感官愉悦**：熄灭瞬间「黑暗吞没」的质地反馈（意象⑤）。
  - 支柱四 **肃穆压迫**：暗即安全、暖光稀缺（亮=暖且稀缺）。
- **为何存在**：为 ③ 视野锥的「光影敏感度」与 ⑥ AI 的可见性判定提供**统一 `LightLevel` 查询 API**；掩体=降可见度+断 LOS（非无敌）。

## 2. 核心机制与规则
- **LightLevel 查询**（核心 API，被 ③/⑥ 消费）：`get_light_level(pos:Vector3) -> float[0..1]`
  - 组成 = `LightmapGI_baked(pos)`（静态烘焙，ADR-004 R-06）+ `Σ dynamic_light_overlay(pos)`（提灯/烛灯/彩窗实时光，受 R-02 上限）+ 月光底填充（极弱）。
  - `0.0`=死黑（Moon Ink `#10141C`），`1.0`=满光池（Candle Amber `#C8862F`）。
- **可见性阈值（供 ③ 引用）**：`L_dark=0.20`（以下≈不可见），`L_bright=0.60`（以上=光池必检测）。
- **掩体（Cover）**：`get_cover(pos) -> bool`——位于遮挡体（墙/柱/大型物件）邻接半影且断 LOS 候选。掩体**不无敌**：仅降低 visibility 系数并提供 LOS 中断，仍可被绕射/声音出卖。
- **可熄灯（互动物触发）**：光源节点 `state ∈ {LIT, EXTINGUISHED}`；熄灭 → `OmniLight3D` 关 + 自发光材质熄暗 + 局部体积雾上扬 `≤0.12` 且 `≤0.4s` 回落（**R-05**）+ 暗角收拢（意象⑤）。重新点亮反向。
- **事件驱动重算**（ADR-002）：`light_state_changed(light_id, state)` → 仅重算受影响 cell 内目标的 `LightLevel`（O(cell) 而非全图）。

## 3. 数据模型与状态
```gdscript
enum LightState { LIT, EXTINGUISHED }
enum LightType { MOON, LANTERN, CANDLE, WINDOW_SPOT, BLOOD_EMERGENCY }

class CoverShadowSystem:        # L4，持有 ShadowGrid + LightState 表
    var shadow_grid: SpatialHashGrid3D   # cell≈锥射程 14m（ADR-002）
    var lights: Dictionary[int, LightSource]

    func get_light_level(pos: Vector3) -> float: ...   # 烘焙 + 动态叠加
    func get_cover(pos: Vector3) -> bool: ...

struct LightSource:
    var id: int
    var node: OmniLight3D
    var type: LightType
    var state: LightState
    var base_intensity: float

const L_DARK: float = 0.20
const L_BRIGHT: float = 0.60
```
- `ShadowGrid` 静态层来自 LightmapGI bake；动态层为可互光源/提灯实时覆盖，随 `light_state_changed` 增量更新。

## 4. 与其他系统的接口
- **依赖**：L2 LightState + LightmapGI 烘焙（R-06）；⑦ Interactables 发出 `light_state_changed`（熄灯动作）；L2 Grid（cell 索引）。
- **发出**：`light_state_changed(light_id, state)`（→ ③ 视野重算受影响 cell）、`cover_state_changed(cell)`。
- **被依赖**：③ 视野锥 `visibility` 计算查 `get_light_level`；⑥ AI 可见性判定同；⑧ HUD 绘制光池/阴影边界（美术 §3.1 地面织锦着色器）。
- **联动 ADR-004**：静态几何走 LightmapGI；动态光仅可互源+提灯+少量彩窗；投影仅月光（R-03）。

## 5. 玩家交互与反馈
- **交互**：对准可互光源 → 互动键熄灯/点亮（由 ⑦ 派发 `light_state_changed`）。
- **Sensation 反馈**：熄灭瞬间 `vignette` 收拢 + 局部雾 `ramp ≤0.12 / ≤0.4s`（R-05，ease 非硬切 V-06）+ 咔哒/风声 foley（美术 §3.3）；重新点亮光池缓缓铺开。
- **世界可视化**：地面着色器实时绘制光池（暖 `#C8862F`）/阴影（冷 `#10141C`/`#3E5C76`）高对比边界（意象④，美术 §3.1）。

## 6. 边界与性能约束
- **R-02** 同屏动态点光 MVP ≤12 / Tier2 ≤32（Forward+ 聚类；超 32 CI 告警）。
- **R-03** 投影光 ≤1（月光 `DirectionalLight3D`）；提灯 `OmniLight3D` 默认 `shadow=false`；高端预设 +最近 1–2 提灯。
- **R-05** 熄灯过场雾 ramp `≤0.12` 且 `≤0.4s` 后回落。
- **R-06** 静态几何 LightmapGI 烘焙（每区域一次；动态物不进烘焙）。
- **R-04** 体积雾 base `≤0.05`（熄灯上扬不破此 base 的长期值；ramp 为瞬态，受 R-05 限时）。
- **ADR-004** 光 LOD：Tier2 远处守卫提灯降为自发光近似/关实时光（保 32 上限）。
- **架构联动**：`architecture.md` §4（动态点光/投影光/雾预算）；ADR-002（事件驱动重算 cell）。

## 7. 可访问性考量
- **光池 vs 阴影靠亮度边界**（≥3:1 明度差），不靠冷/暖色判断（**C-04**）；三类色盲下 `#C8862F`/`#3E5C76` 亮度差 ≥3:1（美术 §2.3）。
- **低亮屏可读**：阴影池内互动物件须保证最低亮度屏可辨形（美术 §9.2）。
- **眩晕防护**：熄灯雾 ramp 限时 ≤0.4s + ease（**V-06**）；提供「减弱雾/关闭雾」选项（**V-04**）。
- **对齐清单**：C-04、R-02/R-03/R-04/R-05/R-06、V-04/V-06；美术 §9.1/§9.2。

## 8. 范围分层归属
- **Tier1（必做）**：`get_light_level`/`get_cover` API + 阴影池/掩体 + 可熄灯（至少 MVP 互动物含熄灯）+ 事件驱动 cell 重算 + 熄灯过场。
- **Tier2（期望）**：光 LOD 细节（16 守卫时远处提灯近似，ADR-004）；彩窗 SpotLight 光柱（美术 §3.4）。
- **Tier3（拓展）**：新可互光源类型（仍复用 LightSource 数据，不新增系统）。
- **范围纪律**：本系统即概念 §3④；互动物件（⑦）只调用其 `light_state_changed`，不另立机制族。
