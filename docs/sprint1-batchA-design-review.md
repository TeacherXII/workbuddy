# Sprint 1 · Batch A 设计评审（词汇冲突收口）
**阶段**：Phase 5 · Sprint 1 · Batch A（词汇 + 光影地基）
**作者**：文策渊（design-strategist）
**上游依据**：`docs/sprint1-batchA-impl.md` §5（程基岩标记的两项 GDD 缺口）、`production/sprints/sprint1-stories.md` §1.1/§4、`design/gdd/system-breakdown.md` §2.3、`design/gdd/systems/stealth-step-commit.md` §2、`design/assets/asset-manifest.md` §3.1
**下游衔接**：Batch B（E05/E06 声音）、Batch C（E08 FSM / E09 HUD）、`docs/sprint1-batchA-impl.md` §5（待裁决项现收口）
**文档版本**：v0.1

> **本评审目的**：Batch A 暴露的 2 项 GDD 词汇冲突会阻断 Batch B 声音系统（吃 `noise_radius`/surface 系数）与 Batch C 巡逻 AI FSM（吃 `SusTier` tier），必须先收口为**单一事实来源（single source of truth）**，让代码有唯一权威。本文件给出范围纪律判定、四支柱贴合核对、2 项冲突的最终裁决值与理由、代码常量一致性声明、残余风险与缓解。

---

## 0. 摘要（一屏结论）

| 项 | 裁决 | 代码是否需改 |
| --- | --- | --- |
| 冲突 1 · Surface 词汇/数值 | 权威玩法集 `{STONE, GRASS, METAL, MOSS}`；`SURFACE_FACTOR = {STONE 1.0, GRASS 0.7, METAL 1.2, MOSS 0.5}`；`WOOD` 仅资产材质→映射 STONE | **无需改**（常量已一致） |
| 冲突 2 · SusTier 枚举 | `CALM \| SUSPICIOUS \| ALERT \| SEARCH`（`CALM` = 可疑度 < 25） | **无需改**（常量已一致） |
| 范围纪律 | **PASS**（无新增平行系统大类；无支柱漂移） | — |

**回写 GDD 文件（6 处）**：`stealth-step-commit.md` §2 + §3、`system-breakdown.md` §2.3、`asset-manifest.md` §3.1、`patrol-ai.md` §3、`ux-spec.md` §世界锚表。历史 `design/reviews/*.md` 为决策记录，保持不动。
**代码常量**：`src/game/step_commit.gd::SURFACE_FACTOR` 与 `src/core/event_bus.gd::SusTier` 均与裁决一致 → **无需程基岩改动**（仅 2 处过时 GAP 注释建议清理，非功能，不阻断）。

---

## 1. 范围纪律判定（PASS / CONCERNS）

**判定：PASS（范围纪律达成；CONCERNS 仅限历史注释清理，不阻断）。**

Batch A 共 7 Story（E01-S9 / E04-S3·S4·S7 / E03-S5·S6·S7），严格落在既有 8 系统框架内：
- **未新增平行系统大类**：全部为概念 §3 六子系统 + RTwP + HUD 的展开（E03 步进提交、E04 掩体/阴影），无「新机制族」引入。
- **E03-S7 落足 VFX**（微光/足音/残影）属 `stealth-step-commit` §5/§7 既定范围（Tier1 必做），非新增系统。
- **E01-S9 事件词汇收口**为基础设施收口（system-breakdown §2 契约落地），不扩展玩法面。
- **Tier 纪律**：所有变更均为既有系统参数/变体扩展（噪声全 surface、三步态），符合概念 §5「单核心做极致」。

**CONCERNS（非阻断，交程基岩清理）**：
1. `step_commit.gd` 第 13–18 行 GAP 注释（标记 STONE 1.0 vs asset 1.2 为开放冲突）现已过时——裁决已落 GDD，该注释应删/改写，避免误导后续读者。属注释清理，**不改常量、不破测试**。
2. `event_bus.gd` 第 15–16 行 NOTE（「§2.3 lists NONE… discrepancy flagged」）现已过时——`system-breakdown` §2.3 已改为 `CALM`。同属注释清理，非功能改动。
3. 历史 `design/reviews/sprint1-design-scope.md` §G6 曾标记「§2 示例仍用旧分类」，但当前 `stealth-step-commit.md` §2 示例已为 `SNEAK+STONE=2.5m / WALK+STONE=5.0m / RUN+STONE=10.0m`（新值），G6 实质已满足；该评审为历史记录，不动。

### 1.1 四支柱贴合核对（Batch A 如何服务「步步为营 / 肃穆压迫」）

| Batch A Story | 支柱一 步步为营 | 支柱二 感官愉悦 | 支柱三 自主掌控 | 支柱四 肃穆压迫 | 说明 |
| --- | --- | --- | --- | --- | --- |
| E03-S5 噪声全 surface | ● | ○ | ○ | ● | MOSS 0.5 最静，强化「落足可权衡」；苔地肃穆寂静 |
| E03-S6 三步态 RUN | ● | ○ | ○ | ○ | RUN = 高成本 deliberate 选项（用户裁决 D1），杜绝无脑冲刺，落实「一步一读」 |
| E03-S7 落足微光/足音/残影 | ● | ● | ○ | ○ | 「一步」成为可感知实体（概念 §3①）；落足微光/足音/残影=物理触觉质地（美术 §1 非庆祝） |
| E04-S3 get_cover | ● | ○ | ● | ● | 掩体=可消耗资源（支柱一）；主动造影（支柱三）；暗即安全（支柱四） |
| E04-S4 light_state_changed | ○ | ● | ● | ● | 可熄灯事件地基 → 熄灯质地（支柱二）、主动造影（支柱三）、暗即安全（支柱四） |
| E04-S7 dirty cell 重算 | ○ | ○ | ○ | ● | 光影成员精确到 cell → 肃穆压迫的「光/影语言」 |
| E01-S9 词汇收口 | — | — | — | — | 基础设施；为全部支柱提供零漂移事件接口 |

> ● = 直接服务；○ = 间接/次要；— = 基础设施不直接服务。每个 Batch A Story 至少命中 1 条支柱，**无支柱漂移**。其中「步步为营」（支柱一）由 E03 三 Story 直接承载——这是 Batch A 的主轴；「肃穆压迫」（支柱四）由 E04 光影/掩体三 Story 承载。两项冲突的收口（surface 系数 / SusTier）正是让上述承载落到**可被 Batch B/C 无歧义消费**的数值与枚举上。

---

## 2. 冲突 1 · Surface 词汇与数值（四源矛盾）—— 最终裁决

### 2.1 裁决值

| 维度 | 最终权威值 |
| --- | --- |
| **权威玩法集**（= `commit.payload.surface` 取值域） | **`{STONE, GRASS, METAL, MOSS}`** |
| **SURFACE_FACTOR**（噪声半径直接乘子） | **STONE 1.0 / GRASS 0.7 / METAL 1.2 / MOSS 0.5** |
| **资产材质 → 玩法 Surface 映射** | `WOOD → STONE`（1.0）、`MOSS 资产 = MOSS 玩法`（0.5）、`STONE/GRASS/METAL 资产 = 同玩法 Surface` |

噪声半径公式（不变）：`noise_radius = BASE(5.0m) × surface_factor × gait_factor`，由 E03 输出 `player_step_committed` payload，被 E06 直接消费（不改写 radius）。

### 2.2 裁决理由

1. **词汇集采用 `{STONE, GRASS, METAL, MOSS}`（以玩法噪声模型为准）**：
   - E06 声音半径**直接吃**这套系数（`noise_radius` 公式 + `commit.payload.surface`），且 `stealth-step-commit.md` §2 已定义 STONE/GRASS/METAL；E03-S5 将 MOSS 升为**独立玩法 surface**（系数 0.5），而非旧 Sprint 0「MOSS≈GRASS」的近似映射。
   - `WOOD` 不再进入玩法集，仅保留为**资产材质 taxonomy**（木地板在灰烬之步为硬木/石基，按 STONE 级计），避免「taxonomy 词汇」与「acoustic 词汇」两套并行导致 Batch B 声音算错。
2. **SURFACE_FACTOR 取值采用 STONE 1.0 而非资产 1.2**：
   - `asset-manifest.md` §3.1 原 `STONE 1.2 / WOOD 1.0 / MOSS 0.5` 是**材质命名/美术侧权重**，不是玩法乘子。声环直接吃玩法系数，必须以玩法 GDD `1.0` 为准（sprint0-design-review §3 已确认 STONE 1.2→1.0 的落版决策）。
   - `MOSS 0.5`：苔藓吸音，应比 GRASS 0.7 更安静，与 `asset-manifest` 旧值巧合一致且声学合理，定为独立最静面。
3. **显式声明资产→玩法映射**（消除混用）：在 `stealth-step-commit.md` §2、`system-breakdown.md` §2.3、`asset-manifest.md` §3.1 三处登记同一映射表，任一读者都不会再把 `STONE 1.2` 误当作噪声乘子。

### 2.3 四源冲突对照（已收口）

| 来源 | 原内容 | 收口后状态 |
| --- | --- | --- |
| sprint1-stories E03-S5 | `{STONE 1.0, GRASS 0.7, METAL 1.2, MOSS ?}` | ✅ MOSS=0.5 落定，全集一致 |
| stealth-step-commit §2 | STONE 1.0/GRASS 0.7/METAL 1.2，废弃 WOOD/MOSS | ✅ 改为 `{STONE,GRASS,METAL,MOSS}` + MOSS 0.5 独立 + WOOD→STONE 映射 |
| system-breakdown §2.3 | `Surface = STONE\|WOOD\|MOSS` | ✅ 改为 `STONE\|GRASS\|METAL\|MOSS` + 映射注 |
| asset-manifest §3.1 | `STONE 1.2 / WOOD 1.0 / MOSS 0.5` | ✅ 标注为「材质命名权重，≠ 玩法 SURFACE_FACTOR」，附映射表 |

---

## 3. 冲突 2 · SusTier 枚举成员 —— 最终裁决

### 3.1 裁决值

| 维度 | 最终权威值 |
| --- | --- |
| **SusTier 枚举** | **`CALM \| SUSPICIOUS \| ALERT \| SEARCH`** |
| **CALM 语义** | **可疑度 < 25**（最低带，非「无可疑度」） |
| 与阈值带关系 | `CALM`=[0,25) / `SUSPICIOUS`=[25,60) / `ALERT`=[60,100)（E08-S2 25/60/10）；`SEARCH` 由 E08 FSM 在丢失目标后进入，非连续阈值带成员 |

### 3.2 裁决理由

1. **`CALM` 取代 `NONE`**：`suspicion_changed(guard_id, value, tier)` 的 `tier` 由 E08-S2 连续可疑度阈值带派生（<25 CALM / <60 SUSPICIOUS / 否则 ALERT）。`NONE` 是占位符，语义应为「最低可疑带」而非「无可疑度」——`CALM` 准确表达「平静巡逻/已回落」状态。
2. **与 E08-S2 阈值 25/60/10 对齐**：`THR_SUSP=25` 起为 SUSPICIOUS，`THR_ALERT=60` 起为 ALERT，`THR_RETURN=10` 以下守卫回 RETURN（但 tier 仍报 CALM）。枚举 `CALM|SUSPICIOUS|ALERT|SEARCH` 与这套连续带一一对应，Batch C FSM 可无歧义映射。
3. **`SEARCH` 保留为枚举成员**：守卫在 ALERT 后丢失目标进入 SEARCH（搜素），`suspicion_changed` 的 `tier` 可携带 SEARCH，故枚举须含之（非阈值带但为合法 tier 值）。

### 3.3 冲突对照（已收口）

| 来源 | 原内容 | 收口后状态 |
| --- | --- | --- |
| system-breakdown §2.3 | `SusTier = NONE\|SUSPICIOUS\|ALERT\|SEARCH` | ✅ 改为 `CALM\|SUSPICIOUS\|ALERT\|SEARCH` + CALM<25 注 |
| patrol-ai §3 | `enum SusTier { NONE, SUSPICIOUS, ALERT, SEARCH }` | ✅ 改为 `CALM…`（Batch C 实现将引用此定义） |
| ux-spec 世界锚表 | `SusTier>NONE` 时出现 | ✅ 改为 `SusTier > CALM`（= SUSPICIOUS/ALERT/SEARCH 才显示，克制） |
| event_bus.gd（代码） | `enum SusTier { CALM, SUSPICIOUS, ALERT, SEARCH }` | ✅ 已为 CALM，与裁决一致 |

---

## 4. 代码常量一致性声明（SURFACE_FACTOR / SusTier）

> 依据 `docs/sprint1-batchA-impl.md` §5 要求：明确声明当前代码常量是否与裁决一致。

### 4.1 `SURFACE_FACTOR`（`src/game/step_commit.gd` 第 19–24 行）
```gdscript
const SURFACE_FACTOR := {
	"STONE": 1.0,
	"GRASS": 0.7,
	"METAL": 1.2,
	"MOSS": 0.5,
}
```
**判定：与裁决完全一致 → 代码无需改动。**
- 集合 `{STONE, GRASS, METAL, MOSS}` 与权威玩法集一致；四值 `1.0/0.7/1.2/0.5` 与 `SURFACE_FACTOR` 裁决一致。
- ⚠️ 仅该常量**上方注释**（第 13–18 行 GAP NOTE）已过时，建议程基岩清理（删除/改写为「已收口，见 system-breakdown §2.3」），**非功能改动，不破测试、不阻断 Batch B/C**。

### 4.2 `SusTier`（`src/core/event_bus.gd` 第 17 行）
```gdscript
enum SusTier { CALM, SUSPICIOUS, ALERT, SEARCH }
```
**判定：与裁决完全一致 → 代码无需改动。**
- 枚举成员 `CALM|SUSPICIOUS|ALERT|SEARCH` 与裁决一致（E01-S9 已按 sprint1-stories §4 契约落地）。
- ⚠️ 仅该枚举**上方注释**（第 15–16 行 NOTE「§2.3 lists NONE… discrepancy flagged」）已过时，建议程基岩清理，**非功能改动**。

### 4.3 结论
**两项代码常量均无需程基岩改动。** Batch B（E06 声音）可直接消费 `noise_radius`（已含 surface 系数），Batch C（E08 FSM）可直接引用 `SusTier.CALM/SUSPICIOUS/ALERT/SEARCH`。唯一待办为 2 处过时注释清理（可选，建议随 Batch B/C 开工前顺手处理）。

---

## 5. 残余风险与缓解

| # | 残余风险 | 概率/影响 | 缓解 |
| --- | --- | --- | --- |
| R1 | 资产团队误将旧 `STONE 1.2` 写入噪声逻辑（历史权重残留） | 中/高（直接错算声环） | ① 本评审 + `asset-manifest` §3.1 已显式声明「资产权重 ≠ 玩法系数」；② 建议 CI 静态断言（control-manifest §7）`grep` 禁止 `1.2` 作为 STONE 乘子出现在玩法/噪声消费处；③ E06-S2 实现时校验 `noise_radius` 来源仅为 `SURFACE_FACTOR`，不经资产 metadata 透传 |
| R2 | `WOOD` 资产按 STONE 计，玩家感知「木地板与石板一样响」 | 低/低（有意设计取舍） | GDD 已显式记录（硬木/石基底，归 STONE 级）；足音 foley 仍按资产材质变体（木闷）区分听感（stealth-step-commit §5），噪声半径按 STONE 计——听感/响度有意解耦 |
| R3 | GDD 注释/历史文档引用旧映射引发歧义 | 低/中 | 本次已回写 6 处 GDD（含 patrol-ai/ux-spec 两处 Batch C 阻断点）；历史 `design/reviews/*.md` 为决策记录保留；一致性评审 `consistency-review.md` 建议登记「G2/G6 冲突已闭合」（非阻断） |
| R4 | 代码 2 处过时 GAP 注释误导后续实现者 | 低/中 | 见 §4.1/§4.2，建议程基岩清理；不阻断 Batch B/C（常量已对） |
| R5 | 其他文档/实现仍引用 `SusTier.NONE` | 低/高 | Grep 已确认 GDD 层 NONE 清零（仅历史 reviews 保留记录）；Batch C 实现 `patrol-ai.md` §3 已为 `CALM`，E08-S6 信号发射 tier 直接引用之 |

### 5.1 Batch B / Batch C 开工前置（收口后已具备）
- **Batch B（声音 E06）**：`player_step_committed` 携带 `surface` + `noise_radius`（含 STONE/GRASS/METAL/MOSS 系数）→ E06-S2 直接用，无需再查 surface 表。✅
- **Batch C（AI FSM E08 / HUD E09）**：`suspicion_changed(.., tier:SusTier)` 的 `tier` 枚举已统一为 `CALM|SUSPICIOUS|ALERT|SEARCH`；`patrol-ai.md` §3 定义与 `event_bus.gd` 一致 → E08-S2/S6 无歧义映射。✅
- **UX（E09-S2 可疑度条）**：`ux-spec.md` 显示条件已改为 `SusTier > CALM`，与枚举对齐。✅

---

## 6. 收口清单（供主理人汇编 Batch A 闭合）

- [x] 冲突 1 裁决值落 GDD：`stealth-step-commit.md` §2（玩法集+系数+映射）、`system-breakdown.md` §2.3（Surface 行）、`asset-manifest.md` §3.1（映射表）
- [x] 冲突 1 内部一致性：`stealth-step-commit.md` §3 payload 注释同步
- [x] 冲突 2 裁决值落 GDD：`system-breakdown.md` §2.3（SusTier 行）、`patrol-ai.md` §3（枚举）、`ux-spec.md`（显示条件）
- [x] 代码常量一致性声明：`SURFACE_FACTOR` / `SusTier` 均与裁决一致 → 无需改
- [x] 范围纪律 PASS、四支柱贴合核对完成
- [ ] （建议，非阻断）程基岩清理 `step_commit.gd` / `event_bus.gd` 2 处过时 GAP 注释
- [ ] （建议，非阻断）`consistency-review.md` 登记「G2/G6 词汇冲突已闭合」

*Batch A 设计评审 v0.1 完成。两项 GDD 词汇冲突已收口为单一事实来源，Batch B/C 可无歧义开工。*
