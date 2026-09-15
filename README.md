# kimi-settings

Kimi K3 × Claude Code（Windows CLI）——面向**正确性、完备性、可靠性**的极致化配置。成本与速度不纳入决策考量；模型策略为**主线单旗舰 + 视觉证据转录专线**：一切文本推理（含后台辅助任务与全部常规子代理）仅运行 **K3**（2.8 万亿参数原生多模态旗舰，`k3[1m]` 承载 1M 上下文），无备选、无回退。与 DeepSeek/GLM 配置的本质差异在于：K3 旗舰**原生接受图片输入**（MoonViT-V2 视觉编码器），主线直读图片不会报错——多模态不再是"绕开主线 400"的补救通道，而是"主线直读少量图片 + vision 子代理专线消化批量视觉证据（视频抽帧序列、密集小字、多页文档）"的双通道架构，转录回传的文本证据同时保护主线上下文与请求体积预算。

| 文件 | 说明 |
| --- | --- |
| [`settings.json`](./settings.json) | 部署至 `%USERPROFILE%\.claude\settings.json`，仅需将 `ANTHROPIC_API_KEY` 替换为实际的 Kimi Code API Key（已通过官方 JSON Schema 严格校验） |
| [`agents/vision.md`](./agents/vision.md) | 部署至 `%USERPROFILE%\.claude\agents\vision.md`——vision 子代理，批量视觉证据转录专线（视频抽帧取证、扫描件/多页文档逐页读、密集小字转录、图表精确读数），frontmatter 直指 `k3-256k`（256K 内与 K3 同效果、支持图片；`[1m]` 写法仅限 Claude Code 环境变量场景，frontmatter 直写会被服务端 401 拒绝——已实测证实） |
| [`GUIDE.md`](./GUIDE.md) | 配置与作业手册：三类需求（BMC 级超大代码体系开发、A 股持续深度行情分析、多模态证据链）的需求规格与追溯矩阵；参数逐项详解（附权威来源链接与 13 项端点实测结论）；双通道多模态架构与作业手册（主线直读/vision 批量转录分流）；1M 窗口与 800K 压缩水位机制定调；上下文生命周期规程；额度三层结构与 429 分类处置；升级 SOP；漂移源清单；两份 CLAUDE.md 模板 |
| [`d-kimi.bat`](./d-kimi.bat) | **一键部署入口**：终端输入 `d-kimi`（需本目录在 PATH）或到本目录双击运行，自动从 `KIMI_API_KEY` 环境变量回填密钥并部署整套配置，详见下文「一键部署」 |
| [`deploy.ps1`](./deploy.ps1) | 部署逻辑本体（`d-kimi.bat` 仅是薄封装；也可带参数直接运行，支持 `-KeyEnvName` / `-ProfileLabel` / `-AgentAction deploy|remove|none`）；除部署 settings.json 与 vision 子代理外，还执行官方接入流程的 `.claude.json` 引导（写入 `penguinModeOrgEnabled` 与 `hasCompletedOnboarding`，跳过 Anthropic 登录） |

核心设定：effort 锁定 `xhigh`（经 Kimi 官方映射即 K3 的 `reasoning_effort=max` 最深档，且保留 Claude Code 侧 ultracode 动态工作流编排通道，`workflowSizeGuideline=unrestricted` 对冲默认 `medium` 的规模引导）、thinking 全程开启（**关闭 thinking 会被服务端路由到 K2.8 Preview 无思考版——官方明示的降级陷阱，`alwaysThinkingEnabled` 为硬性红线**）、1M 窗口 + 800K 压缩水位（压缩请求自身永不超窗：800K 历史 + 131072 输出预留 ≈ 931K < 1048576；裸 `k3` 的 1M 上限与 `max_tokens=131072` 均经端点实测确认）、多模态双通道（主线 `k3[1m]` 直读少量图片 + vision 子代理 `k3-256k` 批量转录；不设 `CLAUDE_CODE_SUBAGENT_MODEL` 以保 frontmatter 路由生效；图片经 Anthropic image block 输入与精确 OCR 均已实测走通）、隐式缓存自动生效（实测 `cache_read_input_tokens` 即时命中）、工具输出与子代理回传按官方上限放宽不截断、三层流式看门狗 + 无人值守重试 + headless 后台无限等待、默认 `bypassPermissions` 全自动（16 条 allow 清单同时是 workflow 子代理的免批通行证）、fullscreen 渲染 + 终端铃声完成通知（无人值守闭环）、`minimumVersion=2.1.246` 将版本门槛固化为启动检查（凭证隔离安全修复）。

## 一键部署（d-kimi）

终端输入 `d-kimi`（需本目录在 PATH）或双击 `d-kimi.bat`，一条命令完成"回填密钥 + 引导 .claude.json + 部署 settings.json + 部署 vision 子代理 + 备份原配置"，无需手改文件、无需粘贴密钥。

一次性准备（设完永久生效；也可在「编辑账户的环境变量」界面手动添加）：

```powershell
setx KIMI_API_KEY "sk-kimi-你的 Kimi Code API Key"   # www.kimi.com/code/console 控制台创建

# 将本仓库目录加入用户 PATH（按实际 clone 位置调整，不加 PATH 双击 .bat 亦可）
[Environment]::SetEnvironmentVariable('Path',
  [Environment]::GetEnvironmentVariable('Path','User') + ';D:\Source\kimi-settings',
  'User')
```

日常部署：任意终端输入 `d-kimi` 回车即可（PATH 变更需新开终端生效）。`deploy.ps1` 自动完成：

1. 读取 `KIMI_API_KEY`（当前进程 → 用户级注册表，`setx` 设完无需重开终端）；
2. 引导 `%USERPROFILE%\.claude.json`：写入 `penguinModeOrgEnabled=true` 与 `hasCompletedOnboarding=true`（Kimi 官方 Claude Code 接入流程步骤②的等价实现，启用第三方模型支持并跳过 Anthropic 登录引导；优先经 node 执行，回退 PowerShell JSON 处理，写前自动备份）；
3. 回填 `ANTHROPIC_API_KEY` 占位符，JSON 校验后以 UTF-8 无 BOM 写出，覆盖前自动将现有配置备份为 `.bak-<时间戳>`；
4. 部署 vision 子代理 `agents\vision.md` → `%USERPROFILE%\.claude\agents\vision.md`；
5. 打印端点 / 模型 / 密钥掩码摘要。

部署目标为 `%USERPROFILE%\.claude\settings.json`。已运行的会话不热加载 settings.json 与 .claude.json，部署后请新开 Claude Code 会话；启动后输入 `/status`，Base URL 显示 `https://api.kimi.com/coding/` 即接入成功——此时即使模型名称仍显示为 Claude 模型，实际调用的已是 Kimi K3。
