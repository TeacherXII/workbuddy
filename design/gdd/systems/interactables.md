# 系统 GDD · 环境互动道具（interactables）
**Phase 2 · 八节 GDD · 优先级 P2–P3（组合既有动词）**

> 上游：`design/concept/game-concept.md` §3 Mechanics⑥、§5（MVP 3–4 种）；`docs/architecture/control-manifest.md` G-02/R-02；`design/art/art-bible.md` §4.2/§5。

---

## 1. 系统目标与支柱对齐
- **目标**：提供小工具集，用「已存在的动词（熄灯/发声/触发）」组合出多种解法——同一扇门可用钥匙、阴影绕行、或声响调虎。
- **支柱对齐**：
  - 支柱三 **自主掌控**：道具克制「唯一解」，多解自由（概念 §3⑥）。
  - 支柱一 **步步为营**：道具是规划工具，非自动通关。
- **为何存在**：道具不引入新机制族，只**派发事件**给 ④/⑤/⑥，是 Autonomy 的物化。

## 2. 核心机制与规则
- **MVP 道具（3–4 种）**，均映射到既有系统动词：
  | 道具 | 类型 `InteractableType` | 派发事件 | 目标系统 |
  | --- | --- | --- | --- |
  | 声响诱饵（碎石/骨片） | `DECOY` | `decoy_landed(pos, surface, radius≈8m)` | ④ 声音 |
  | 可熄光源（烛/灯/吊灯） | `LIGHT_TOGGLE` | `light_state_changed(id, EXTINGUISHED/LIT)` | ⑤ 光影 |
  | 可触发机关（钟/落石/松动地板） | `TRAP` | `interactable_triggered(id, TRAP)` → 声/光/阻 | ④/⑤/⑥ |
  | 短程障目烟雾 | `SMOKE` | `interactable_triggered(id, SMOKE)` → 临时降 visibility | ③/⑥ |
- **交互规则**：对准 + 互动键触发；诱饵需投掷落点（半径由道具定）；`charges` 限量（MVP 每类 2–3 发，关卡补给）。
- **烟雾**：在落点生成临时 `visibility ×0.3` 区域（限时 `≈4s`，受 ③ 读取），不从属新系统——仅临时改写 ⑤ `get_light_level` 局部 or 直接令 ③ 在该区 visibility 衰减。
- **不新增平行系统**：道具只产生既有事件；「机关谜题/环境处决」(Tier3) 仍由这些道具组合实现（概念 §5 Tier3）。

## 3. 数据模型与状态
```gdscript
enum InteractableType { DECOY, LIGHT_TOGGLE, TRAP, SMOKE }

struct Interactable:
    var id: int
    var type: InteractableType
    var charges: int
    var state: Dictionary          # 如 LIGHT_TOGGLE 的 lit 状态
    var radius: float              # DECOY/SMOKE/TRAP 影响半径
```
- 关卡以 `entity-inventory` 配置每处互动物件类型与 charges；运行时查 `charges>0` 方可触发。

## 4. 与其他系统的接口
- **依赖**：L2 EventBus；⑤（熄灯）、④（发声）、⑥（触发机关）。
- **发出**：`decoy_landed`（→④）、`light_state_changed`（→⑤，复用其定义）、`interactable_triggered(obj_id, type, payload)`（→④/⑤/⑥）。
- **被依赖**：① 步进提交不依赖；⑧ HUD 显示当前道具/charges。
- **联动**：所有事件名见 `system-breakdown.md` §2 词汇表，无自造事件。

## 5. 玩家交互与反馈
- **输入**：对准互动物 → 互动键；诱饵另需落点选择（复用 ① aim 逻辑）。
- **Sensation 反馈**：诱饵落点微光+声环（④）；熄灯咔哒+暗角（⑤）；烟雾 puff（additive 粒子，受 T-04 同步）；机关咔哒/轰鸣 foley。
- **剪影暗示**（美术 §4.2）：可互动物件比环境多一道握柄高光，提示可操作。

## 6. 边界与性能约束
- **G-02** 诱饵/机关声环仍计入同屏声环 ≤8（由 ④ 统一 FIFO 管控）。
- **R-02** 可熄光源计入同屏动态点光 ≤12/32（由 ⑤ 管控）。
- **无射线/AI 预算**：道具本身不触锥/LOS；烟雾仅临时改写 visibility 系数。
- **架构联动**：`architecture.md` §4（声环/光预算）；事件驱动（ADR-002）。

## 7. 可访问性考量
- **图标+标签**：每个道具/交互有图标+文字标签，不靠颜色（**C-05**）；瞄准有形状化预览（非纯色）。
- **字幕**（X-02）：机关/诱饵触发带音景图标+说话者（环境）标识。
- **对比度**：交互提示亮度差 ≥3:1（**C-03**）。
- **对齐清单**：C-03/C-05、G-02、R-02、X-02；美术 §4.2/§9.1。

## 8. 范围分层归属
- **Tier1（必做）**：DECOY + LIGHT_TOGGLE + TRAP + SMOKE 四类（MVP 3–4 种），charges 限量，事件派发。
- **Tier2（期望）**：更多道具变体（仍复用四类 + 参数，不新增类型）。
- **Tier3（拓展）**：机关谜题/环境处决（组合既有道具）；照片模式取景；均复用，不新增系统。
- **范围纪律**：本系统即概念 §3⑥；严格只用既有动词组合，未新增平行机制族（概念 §5 范围纪律）。

---

## 9. Sprint 2 实体级扩展（E07 完整系统）
> 本 § 将 ⑦ 从「MVP 类型表 + 关卡配置」升级为**实体级运行系统**：区分*世界互动物件*与*玩家携带物件*，二者均带 `charges` 与运行态；并补 TRAP 内部 FSM 与烟雾对 ③ 的可见性接口（解决一致性评审 C3）。信号契约（D11 冻结 `decoy_landed` / `interactable_triggered` 签名）**不变**，实体化不改契约。

### 9.1 两类实体
| 类别 | 说明 | 代表类型 | charges 归属 |
| --- | --- | --- | --- |
| **世界互动物件（Placed Entity）** | 关卡静态布置、可被玩家就近触发 | `LIGHT_TOGGLE`（灯）、`TRAP`（机关） | 物件自身 `charges`（可多次触发） |
| **玩家携带物件（Carried Item / entity-inventory）** | 玩家背包内、投掷/使用 | `DECOY`（诱饵）、`SMOKE`（烟雾弹） | 背包按类型计 `charges` |

- **`entity-inventory`**（玩家背包，L3 运行态）：
  ```gdscript
  struct InteractableItem { var type: InteractableType; var charges: int }
  class EntityInventory:                    # 玩家持有
      var slots: Array[InteractableItem]    # 当前携带的 DECOY/SMOKE 等
      var active_index: int = 0
      func use_active() -> InteractableItem:   # 使用并 charges-1
  ```
- 世界物件沿用 §3 `Interactable`（`id/type/charges/state/radius`），`charges>0` 方可触发；`charges` 归零 → 进入 `SPENT`（视觉降饱和、剪影高光消失，§5）。

### 9.2 四类型实体化细节
- **DECOY（携带→投掷）**：`EntityInventory.use_active()` → 落点选择（复用 ① aim）→ 发 `decoy_landed(pos, surface, radius≈8m)`（→④）。`surface` 仅驱动 foley/字幕（D11-A，无 GDScript 对应，用 `String`）。`charges` 在落点生成时扣减。
- **LIGHT_TOGGLE（世界）**：对准 + 互动键 → 翻转 `state.lit` → 发 `light_state_changed(id, EXTINGUISHED/LIT)`（→⑤，复用其定义，R-02 仍计）。`charges` 限制可重复开关次数（多数场景 `charges=∞` 即无限，关卡可设限）。
- **TRAP（世界，见 9.3 FSM）**：对准 + 互动键（或踩踏触发）→ 内部 FSM 推进 → 发 `interactable_triggered(id, TRAP, payload)`（payload 含声/光/阻类型，→④/⑤/⑥）。
- **SMOKE（携带→投掷）**：`EntityInventory.use_active()` → 落点 → 在半径内生成临时 `visibility ×0.3` 区（限时 `≈4s`，受 ③ 读取）→ 发 `interactable_triggered(id, SMOKE, {radius, duration≈4s})`（→③/⑥）。`charges` 落点扣减。

### 9.3 TRAP 内部 FSM
```
TRAP_FSM: IDLE → ARMED(布设/就绪, 等待触发)
              → TRIGGERED(发 interactable_triggered, 声/光/阻脉冲)
              → RECOVER(charges>0 ? ARMED : SPENT)
SPENT: charges==0，不可再触发（视觉 SPENT 标记）
```
- 触发条件：玩家互动键 OR（若关卡配置）踩踏/视锥进入。触发脉冲参数（声强/光闪/阻挡）由关卡 `payload` 定义，类型不变。
- FSM 节流同 ⑥（`≤10Hz`，G-04 精神），TRAP 自身无逐帧 AI 预算。

### 9.4 烟雾 × ③ 可见性接口（解决 C3）
- ③ `compute_visibility(target, observer)` 公式追加外部乘子：`vis = base_vis × cover_factor × smoke_factor`。
- **`smoke_factor`** 由 ⑦ 落点区在有效期内提供（默认 `0.3`，半径内线性衰减至边界 `1.0`）；`interactable_triggered(id, SMOKE, payload)` 携带 `radius`/`duration`，③ 订阅并在有效期内注入乘子。
- 不新增独立系统：烟雾仅为 ③ 公式的临时乘子源，符合「道具只派发既有事件/改写既有系数」纪律。

### 9.5 边界（实体级新增）
- **G-02**：DECOY/TRAP 声环仍计入同屏声环 ≤8（④ FIFO 管控），实体化不豁免。
- **R-02**：LIGHT_TOGGLE 计入同屏动态点光 ≤12/32（⑤ 管控）。
- **零新事件**：实体级扩展复用 §4 全部既有信号；`decoy_landed`/`interactable_triggered`/`light_state_changed` 签名冻结（D11），**本 § 不改任何契约**。
- **存档接口**：运行时 `charges`/`state`/`lit` 由 `save-system.md` §3 `interactable_charges`/`light_states` 快照，读档还原（无新词汇）。
