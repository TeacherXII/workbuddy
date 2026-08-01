# 系统 GDD · 声音传播系统（sound-propagation）
**Phase 2 · 八节 GDD · 优先级 P2（依赖 ① 落足 + ⑦ 诱饵）**

> 上游：`design/concept/game-concept.md` §3 Mechanics③、§6；`docs/architecture/adr/adr-002-stealth-compute-model.md`（声环≤8、网格通知）；`docs/architecture/control-manifest.md` G-02、C-05、X-02；`design/art/art-bible.md` §8.2。

---

## 1. 系统目标与支柱对齐
- **目标**：脚步噪声 = f(地面材质, 步态)；可投掷**声响诱饵**制造可控噪声圈引开守卫；噪声以可视化**声波环**扩散，玩家可预判波及范围。
- **支柱对齐**：
  - 支柱一 **步步为营**：噪声是可权衡的承诺（落哪、多响）。
  - 支柱三 **自主掌控**：诱饵=主动解法，克制唯一解。
- **为何存在**：声音是与视野并列的第二感知轴；与 ⑤ 光影、③ 视野共同构成「多系统咬合」的临场张力（概念 §3 Dynamics）。

## 2. 核心机制与规则
- **离散声事件** `SoundPayload{origin, radius, intensity, source}`：由 ① 落足（`FOOTFALL`）与 ⑦ 诱饵/机关（`DECOY`/`TRAP`）发出。
- **噪声半径**（由 ① 提供 `noise_radius`，见 stealth-step-commit §2 公式）：本系统仅做传播/可视化/通知，不改写半径。
  - 参考：SNEAK+STONE=3.0m，WALK+WOOD=5.0m，RUN+STONE=12.0m；诱饵 base≈8.0m（按道具）。
- **守卫通知**（ADR-002）：声事件按网格查 `radius` 内守卫 → 发 `sound_emitted` → ⑥ 按 `intensity×(1−dist/radius)` 提可疑度（O(半径内守卫)）。
- **声波环 VFX**：离散声事件 → 扩张同心圆（Tween/shader，自毁）；**同屏 ≤8**（G-02），超出按 FIFO 淘汰最旧环。
- **诱饵**：⑦ 投掷物落点 `decoy_landed` → 本系统生成 `DECOY` 声事件（可控半径），吸引守卫前往调查（减其对玩家路径权重，见 ⑥）。

## 3. 数据模型与状态
```gdscript
enum SoundSource { FOOTFALL, DECOY, TRAP, AMBIENT }

struct SoundPayload:
    var origin: Vector3
    var radius: float
    var intensity: float          # 0..1
    var source: SoundSource

class SoundSystem:               # L4
    var active_rings: Array[RingVFX]   # 同屏 ≤ G-02(8)
    const RING_CAP: int = 8

    func emit(payload: SoundPayload): ...   # 通知网格内守卫 + 生成环
    func cull_oldest(): ...                 # FIFO 保 ≤8
```
- `RingVFX`：Tween 控制半径 0→payload.radius，alpha 淡出后 `queue_free`（自毁）。

## 4. 与其他系统的接口
- **依赖**：L2 Grid（半径内守卫查询）、L2 EventBus；① `player_step_committed`（noise_radius）、⑦ `decoy_landed`/`interactable_triggered`。
- **发出**：`sound_emitted(SoundPayload)`（→ ⑥ 可疑度）。
- **被依赖**：⑥ Patrol AI 消费提可疑度；⑧ HUD 绘制声波环（世界内）。
- **联动 ADR-002**：声环 Tween/shader 自毁、≤8、网格通知 O(半径内守卫)。

## 5. 玩家交互与反馈
- **可视化**（diegetic，美术 §8.2）：世界内同心圆扩散声环，冷调 `#3E5C76`/形状编码（不靠颜色，C-05）；诱饵落点带落点微光。
- **字幕**（X-02）：关键音景（足音类型/诱饵落点/守卫警示语）带说话者标识 + 音景图标。
- **Sensation**：环扩散是「声音可见」的 tactile 反馈，呼应意象②尘埃/光柱的「光存在证据」。

## 6. 边界与性能约束
- **G-02** 同屏声环 VFX **≤8**（Tween/shader 自毁；CI 断言同屏>8 告警）。
- **联动**：噪声半径由 ① 公式给定，非本系统膨胀；诱饵半径由 ⑦ 道具参数定。
- **架构联动**：`architecture.md` §4（声环≤8）；ADR-002（网格通知、声环自毁）。

## 7. 可访问性考量
- **三重编码**：声环靠「形状（同心圆）+ 扩散 + 标签」编码，不依赖单一色相（**C-05**）；色盲模式追加图标（美术 §9.1）。
- **字幕**：足音/诱饵/警示语字幕带说话者标识+图标（**X-02**）。
- **对比度**：声环边界亮度差 ≥3:1（**C-03**）。
- **对齐清单**：C-03/C-05、G-02、X-02；美术 §8.2/§9.1。

## 8. 范围分层归属
- **Tier1（必做）**：落足噪声（surface×gait）+ 诱饵声事件 + 声波环 VFX(≤8) + 网格通知守卫。
- **Tier2（期望）**：循声猎犬变体（听觉优先，升声音权重，见 ⑥）——参数覆盖，不新增系统。
- **Tier3（拓展）**：新诱饵/噪声源类型（复用 SoundSource 枚举）。
- **范围纪律**：本系统即概念 §3③；变体以权重覆盖（architecture §3.4），未新增平行机制族。
