# codex-skills

这个仓库提供面向不同开发场景的 Codex skills，重点解决“自动化闭环”本身，包括：

- 自动构建
- 自动运行或部署
- 日志抓取
- 基于日志继续修复

## 当前包含的 Skill

### rk3588-closed-loop

适用于 RK3588 或类似嵌入式 Linux 板端程序的交叉编译、部署、远端启停和拉日志闭环。

详细文档见：

- [rk3588-closed-loop.md](D:\Video\150\codex-skills\docs\rk3588-closed-loop.md)

### vs-qt-build-loop

适用于 Windows 10/11 下 VS2017 + Qt 5.11.0 项目的“修改代码 -> 编译 -> 运行 -> 抓日志 -> 分析 -> 继续修复”闭环。

详细文档见：

- [vs-qt-build-loop.md](D:\Video\150\codex-skills\docs\vs-qt-build-loop.md)

## Skill 目录

```text
codex-skills/
├─ docs/
│  ├─ rk3588-closed-loop.md
│  └─ vs-qt-build-loop.md
└─ skills/
   ├─ rk3588-closed-loop/
   └─ vs-qt-build-loop/
```

## 安装示例

安装 `rk3588-closed-loop`：

```bash
$skill-installer --repo zc202106/codex-skills --path skills/rk3588-closed-loop
```

安装 `vs-qt-build-loop`：

```bash
$skill-installer --repo zc202106/codex-skills --path skills/vs-qt-build-loop
```
