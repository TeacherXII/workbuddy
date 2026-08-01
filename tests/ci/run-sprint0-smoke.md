# 闭合 N2：跑通 Sprint 0 GUT 冒烟（退出标准⑤）

本环境（WorkBuddy 沙箱）Bash 全线故障且未安装 Godot，无法就地实跑。
N2 必须在**可运行环境**闭合——以下二选一。

## 前置
- Godot 4.4（含 `--headless`）
- GUT 插件置于 `res://addons/gut`（即仓库根 `addons/gut/`）

## A. 本地运行
```bash
# 1) 拉取 GUT 插件（若 addons/gut 不存在）
git clone --depth 1 https://github.com/bitwes/Gut.git addons/gut

# 2) 在工程根目录运行 Sprint 0 冒烟
godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests/unit -gexit
```
`-gexit` 在任一测试失败时令 godot 以非 0 退出 → 即 Sprint 0 退出标准⑤
（GUT headless 绿灯）。**全绿即 N2 闭合**。

## B. CI 自动闭合
见 `.github/workflows/ci.yml`：push / PR 时基于 `barichello/godot-ci:4.4` 镜像，
自动克隆 GUT 并运行同一条命令；测试失败则 CI 红、门禁不过。

## 失败处理
若冒烟报错，把 godot 输出贴回主理人，由工程负责人（程基岩）定位修复后重跑。
