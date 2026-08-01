# CI 质量门说明 · ASHEN STEP（对齐 control-manifest §7）

> 本文件说明 `tests/` 脚手架如何在 CI 中卡质量门。最小流程见 `.github/workflows/ci.yml`（Godot headless 跑 GUT 冒烟）。预算静态断言见 `tests/ci/budget_assert.gd`（当前占位，待 Phase 5 quality-lead 充实场景扫描）。

## 1. 门禁构成（lean：仅核心节点卡门）

| 门 | 触发 | 阻断？ | 依据 |
| --- | --- | --- | --- |
| **GUT 冒烟测试** | push / PR | **是**（失败阻断合并） | `tests/unit/test_step_commit.gd` + `test_vision_cone.gd`；断言编码架构 §4 预算 |
| **预算静态断言** | push / PR | 否（告警，记「漂移」交主理人裁决） | control-manifest §7 |

> lean 评审下：测试门**阻断**，预算断言**仅告警**（不阻断构建），但告警须入评审记录并由主理人裁决（control-manifest §7 末段）。

## 2. 预算静态断言清单（control-manifest §7）

`godot --headless -s res://tests/ci/budget_assert.gd -gexit` 应覆盖：

| 断言 | 上限 | 约束号 | 命中动作 |
| --- | --- | --- | --- |
| 同屏实时 `OmniLight3D`/`SpotLight3D` > 32 | 32 | R-02 | 警告 |
| `WorldEnvironment.volumetric_fog_density` > 0.05（base） | 0.05 | R-04 | 警告 |
| 熄灯雾 ramp > 0.12 或 > 0.4s | 0.12 / 0.4s | R-05 | 警告 |
| 静态网格缺 UV2 | — | ADR-004 / R-06 | 警告 |
| 同屏声环实例 > 8 | 8 | G-02 | 警告 |
| 暴露/锥缘脉动 shader 频率参数 > 2Hz | 2Hz | V-02 | 警告 |

> 当前 `budget_assert.gd` 为占位：打印 TODO 并退出 0，保证 CI 可跑通。**Phase 5 quality-lead** 需在此脚本内实现对场景/资源文件的真实扫描（遍历 `.tscn` 统计实时光、读 `WorldEnvironment` 参数、校验 `.glb` 导出 UV2 等），使上述断言真正生效。

## 3. headless 运行（无显示器）

- CI 镜像需 Godot 4.4 可执行（linux.x86_64）。本环境无法跑 godot（Bash 受限），但脚本语法按 Godot 4.4 CLI 编写，本地/CI 均可执行。
- GUT 运行器：`res://addons/gut/gut_cmdln.gd`；`-gexit` 使进程退出码 = 断言结果（CI 据此判定）。
- 首次 import：CI 先 `godot --headless --path . --editor --quit` 生成 `.godot` 导入缓存，再跑测试。

## 4. 与 Epic 勾稽
- 门禁逻辑属 **E10**（发布/CI/质量门）；断言数值来自 **architecture §4** 与 **control-manifest**。
- 测试桩覆盖 **E02/E03/E05/E08** 核心契约；其余系统用例缺口见 `tests/README.md` §5，交 quality-lead。

*CI 说明 v0.1（Phase 4）。冒烟门已接；预算断言占位待充实。*
