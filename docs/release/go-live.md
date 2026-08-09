# Go-Live Checklist · ASHEN STEP《灰烬之步》Phase 7 — 内部封闭 alpha v0.1.0-alpha.1

**文档类型：** 上线清单（发布前最后检查）
**负责人：** 路远行（release-ops-lead）
**发布定位：** 内部封闭 alpha（vertical slice），GitHub Release 手动分发，仅 zh-CN
**权威：** 本地 Godot 4.4.1（GHA runner 宕机，无 CI）

> 高影响动作（上线 / 热修 / 回滚）须**人工审批**。本清单为可执行步骤记录，export 由主理人执行。

---

## 0. 前置阻塞清除（GO 前的硬门槛）

- [ ] ⛔ `project.godot` 已补 `version="0.1.0-alpha.1"`（当前缺失）。
- [ ] ⛔ `export_presets.cfg` 已存在且 `git ls-files` 可见（补救见 `release-checklist.md` §6）。

> 任一项未清 = **NO-GO**。不主张豁免。

---

## 1. 版本号确认
- [ ] 版本号 = `0.1.0-alpha.1`（与 `project.godot` `version` 字段、`git tag`、`GitHub Release` 三者一致）。
- [ ] 命名口径统一建议：HUD 文案"灰烬之步 · Sprint1" vs `config/name` "Sprint0" 的非阻塞差异已确认或修正。

## 2. 本地 export（主理人执行）
- [ ] 用 Godot 4.4.1 console 跑：
  ```bat
  Godot_v4.4.1-stable_win64_console.exe --headless ^
    --export-release "Windows Desktop" ^
    build\ash-step-0.1.0-alpha.1-win64\ASHEN_STEP.exe
  ```
- [ ] 导出无报错；`ASHEN_STEP.exe`（及 `.pck`/数据目录）生成于 `build/ash-step-0.1.0-alpha.1-win64/`。
- [ ] 发布包**不含** `addons/`（GUT dev-only）、`tests/`、`docs/`、源码。

## 3. GUT 质量门复跑（发布前最后一道验证）
- [ ] 重新跑真实 GUT（**看实时控制台真数，不唯 `gut_output.txt`**）：
  ```bat
  Godot_v4.4.1-stable_win64_console.exe --headless ^
    -s addons/gut/gut_cmdln.gd -gdir=res://tests/unit -gexit --verbose ^
    > gut_output_0.1.0-alpha.1.txt 2>&1
  ```
- [ ] 确认 `Scripts 22 / Tests 241 / Passing 241 / Asserts 1588 / Failing 0 / exit 0`。
- [ ] 连跑两次计数一致（确定性绿）。
- [ ] 落盘 `gut_output_0.1.0-alpha.1.txt` 作为 Release 质量附件（替换过时的 `239/1578` 旧文件）。

## 4. zip 包校验
- [ ] 将 `build/ash-step-0.1.0-alpha.1-win64/` 整体打包为 `ASHEN_STEP_0.1.0-alpha.1_win64.zip`。
- [ ] 校验 zip 可解压、exe 可启动（至少一次本地双击 / 命令行启动冒烟）。
- [ ] 确认包内不含 dev-only / 源码资产。
- [ ] （可选）记录 zip SHA-256，随 Release 公示便于内测者校验完整性。

## 5. GitHub Release 创建（手动，因 runner 宕）
- [ ] 打 tag `v0.1.0-alpha.1`（annotated，message 含区间 `24fc2ef..5cf0431`）。
- [ ] 创建 Release（建议先 Draft，复核后 Publish）：
  - Title：`ASHEN STEP 灰烬之步 · 内部封闭 alpha v0.1.0-alpha.1`
  - 上传 `ASHEN_STEP_0.1.0-alpha.1_win64.zip`
  - 上传 `gut_output_0.1.0-alpha.1.txt`（质量证据）
  - 正文 = `changelog.md` 内容（含 Known Issues 公示）
- [ ] 可见性：明确内部封闭，**不公开推广**；仅对受邀内测者可见（或私仓 + 名单制）。

## 6. Release 页文案含已知问题公示
- [ ] changelog 的 **Known Issues / 已知缺口** 5 项全部写入 Release 正文，不遗漏、不淡化：
  1. D2（A-0N 实机消费）递延
  2. path-A 真实 foley 永久 known gap
  3. `wire_audio()` 生产挂载点 gap
  4. 真机「真在播」音频待验证（非阻塞）
  5. GHA runner 宕机（手动发布）
- [ ] 另注明两个配置层阻塞已在发布前清除（version 字段 + export_presets.cfg）。

## 7. 内测名单分发
- [ ] 内测者名单确定（小范围封闭）。
- [ ] 分发 Release 链接 + 启动说明 + 已知缺口沟通稿。
- [ ] 反馈收集渠道就绪（issue 模板 / 私群 / 表单）；明确"不公开、内部反馈"。
- [ ] 收集重点提示内测者：音频为占位/程序化，世界音缺真实 foley；存读档 UI 不暴露（属设计，非 bug）。

---

## 8. 回滚 / 热修预案
- [ ] **回滚：** 若 `v0.1.0-alpha.1` 出现阻断问题，内测者回退至上一 alpha tag；或将该 Release 转为 Draft/删除。
- [ ] **热修（简化但留审计）：** 修复 → 本地 GUT 复跑绿 → 本地 export 新 zip（`0.1.0-alpha.2`）→ 新 tag + 补丁说明 + 回滚预案随附。
- [ ] **字符串冻结：** 仅 zh-CN，无字符串表；冻结后除热修不改玩家可见文案。
- [ ] 上线 / 回滚须人工审批。

---

## 9. 最终 go / no-go 签字

| 维度 | 判定 |
|---|---|
| 配置阻塞清除（version + export_presets.cfg） | ☐ 待清 |
| GUT `22/241/241/1588/0` 确定性绿 | ☐ 待确认 |
| zip 校验通过 | ☐ 待确认 |
| Release 页含已知问题公示 | ☐ 待确认 |
| 内测名单 + 反馈渠道就绪 | ☐ 待确认 |

**结论：** 上述全绿 → **GO（内部封闭 alpha）**；任一配置阻塞未清 → **NO-GO**。
