# codex-skills

我的 Codex 自定义技能仓库。

## Skills

### rk3588-closed-loop
用于 RK3588 板端程序的自动化闭环验证，支持：

- 读取仓库内配置文件
- WSL 交叉编译
- 上传板端程序
- 远端启动和停止
- 抓取短日志与完整日志
- 根据运行日志继续分析和修复

该 skill 适用于 `SkyNode` 板端程序场景，支持 `rk_ptz` 多变体和 `UpperControl`。

## 安装方式

可通过 Codex 的 skill 安装脚本从本仓库安装：

```bash
install-skill-from-github.py --repo <你的用户名>/codex-skills --path skills/rk3588-closed-loop
```

## 说明

- skill 不绑定具体机器路径
- 机器差异通过业务仓库内的配置文件处理
- 板端 IP、工具链路径、日志路径、编译宏等都应放在目标仓库自己的配置中
