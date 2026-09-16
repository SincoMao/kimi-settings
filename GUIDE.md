# Kimi K3 × Claude Code（Windows）配置与作业手册

> **定位**：本手册面向两个生产场景——**① BMC 级超大复杂代码体系开发**（从嵌入式底层到上层 Web 的全栈工程）与 **② A 股市场持续深度行情分析**（数据值绝对可靠、考虑问题全面、可长期稳定复跑）。
>
> **总原则**：成本与速度不纳入决策考量。所有决策仅对三项指标负责：**正确性、完备性、可靠性**。凡"节省 token / 节省配额 / 提升速度"与"更准确 / 更完整 / 更稳定"相冲突之处，一律选择后者。全链路仅允许一个模型：**Kimi K3**——包括后台辅助任务在内，不存在任何降级路径。
>
> **适用环境**：Windows 原生 Claude Code CLI（2026-09 时点 v2.1.x）+ Kimi 会员订阅的 Kimi Code 权益（Moderato 及以上可调用 K3，1M 上下文需 Allegretto 及以上）。
> **文档快照日期**：2026-09-15；**2026-09-16 按当日官方文档全面复核修订**（子代理模型解析顺序 v2.1.251 起 frontmatter 优先、字节级看门狗网关默认开启 v2.1.222、workflow 子代理权限模式继承主会话、Kimi 配额触顶为 403 而非 429、`minimumVersion` 真实语义仅约束更新通道；vision 专线由 `k3-256k` 改裸 `k3` 以修正窗口核算）。全部机制性结论以三个官方文档源为准：[Claude Code Docs](https://code.claude.com/docs/en/overview)、[Kimi Code 文档站](https://www.kimi.com/code/docs/)、[MoonshotAI/Kimi-K3 官方仓库](https://github.com/MoonshotAI/Kimi-K3)；本手册另含 13 项对 `https://api.kimi.com/coding/` 端点的**第一手实测结论**（5.0 实测记录表），它们与官方文档互补，共同构成本配置的依据基线；长上下文质量结论以第 7.4.0 节所引权威研究（Anthropic 工程博客、Chroma、ICML/COLM 论文）为准；两大领域的作业规程（第 9、10 章）为专家经验层，独立于上述文档。

---

## 目录

- **第一部分：需求定调**
  - 1. 场景需求规格（由两大场景反推的硬性需求）
  - 2. 对"高缓存命中"的定调
  - 3. 模型策略：主线单旗舰（原生多模态）+ 视觉证据转录专线
  - 4. 需求 → 配置追溯矩阵
- **第二部分：配置**
  - 5. 工作原理速览（含端点实测记录）
  - 6. 配置文件位置、生效时机与验证
  - 7. 参数逐项详解（附权威来源）
  - 8. 有意不设置的参数及原因
- **第三部分：作业手册**
  - 9. 场景 ①：BMC 级超大代码体系开发（含 CLAUDE.md 模板）
  - 10. 场景 ②：A 股深度行情分析（含数据铁律与 CLAUDE.md 模板）
- **第四部分：运维**
  - 11. 多模态证据作业手册（双通道架构：主线直读 + vision 批量转录）
  - 12. 额度、限流与可用性运维
  - 13. 升级 SOP
  - 14. 一致性管理：任务中途的行为漂移源清单
  - 15. 部署后验证清单
  - 16. 故障排查速查表
- **第五部分：附录**
  - 17. Kimi K3 规格、Model ID 矩阵与会员档位
  - 18. 参考链接汇总

---

# 第一部分：需求定调

## 1. 场景需求规格

最深思考、最完整上下文、最少截断、最高缓存命中是方向性目标，并非可直接执行的需求。本章将两个场景加一条两场景共用的多模态证据链分解为**可验证、可映射到配置项**的需求条目（编号 A1–A6 / B1–B6 / C1–C3，第 4 章给出每条需求到具体参数的追溯）。

### 1.1 场景 ①：超大复杂代码体系（以 BMC 为例）

BMC（基板管理控制器）开发是"单任务跨越整个技术栈"的典型代表：Yocto/bitbake 构建体系、u-boot、内核驱动（I2C/IPMB/KCS/MCTP）、设备树、D-Bus 服务群（OpenBMC 的 phosphor-* 仓库族）、IPMI / Redfish（DMTF DSP0266）协议服务、直至 WebUI 前端。由此反推的硬需求：

| 编号 | 需求 | 判定标准 |
| --- | --- | --- |
| **A1 跨栈上下文** | 单个任务的推理必须同时容纳多仓库、多语言（C / C++ / DTS / Python / JS）的真实代码与工程约定 | 1M 窗口全程可用**且会话永不因触顶进入不可恢复状态**（压缩水位受控，见 7.4）；多目录挂载时各仓库的 CLAUDE.md 全部载入；巨型源码树的检索不超时 |
| **A2 长周期执行不中断** | 小时级构建、跨多轮的多阶段迁移中，任何一环的超时/断流/限流都不得终结任务 | 请求超时、流式看门狗、命令超时、子代理失速阈值、限流重试全部按最坏情况配置 |
| **A3 证据先行** | 协议字段、寄存器位、D-Bus 接口签名等**必须来自读到的真实代码/规范**，不允许凭模型记忆书写 | 工具输出（文件读取、命令输出、子代理回传、MCP 结果）在文档允许的上限内不截断；上游开源仓库可被直接检索与全文读取 |
| **A4 规范硬约束** | 编码规范、内存约束、安全启动链、许可证边界、"禁改区"必须被强制执行而非口头遵守 | CLAUDE.md 硬规则 + 构建/静态检查/测试的验证闭环，必要时以 deny 规则或 hooks 兜底 |
| **A5 大规模并行不互踩** | 代码审计、批量迁移需要几十上百个子代理并行，且互不污染工作区 | 子代理数量上限、后台任务能力、worktree 隔离、agent teams 全部启用且上限提高 |
| **A6 行为一致性** | 同一任务内模型行为不得漂移（换模型、换推理档、换系统提示都会改变行为） | 模型/effort 固定为单一配置；升级只发生在任务间隙（见第 13、14 章） |

### 1.2 场景 ②：A 股深度行情分析

A 股的特殊性在于：交易规则密集（T+1、分板块涨跌停、ST 制度、停复牌）、口径陷阱密集（复权、单位、报告期 vs 公告日）、信息面变化迅速（政策、公告、资金）。"绝对可靠的数据值"在 LLM 语境下只有一种实现方式：**模型的每一个数字都来自当轮工具调用的返回值，并可溯源**。硬需求：

| 编号 | 需求 | 判定标准 |
| --- | --- | --- |
| **B1 数据值绝对可靠** | 禁止模型凭参数记忆给出任何行情/财务数字；关键数字须双源交叉验证 | 每个数值可追溯到具体工具调用（接口名/URL + 获取时间）；检索与全文读取链路全程可用且结果不被截断 |
| **B2 口径先于计算** | 任何计算前先锁定：复权方式、单位（元/万元/亿元）、币种、时区、报告期与公告日、交易日历 | CLAUDE.md 中的口径声明规程强制执行（见 10.3 模板） |
| **B3 时点正确性** | 回看历史必须用时点数据（point-in-time），防幸存者偏差、防以"当前已知信息"解释历史 | 作业规程强制声明数据截止时间；停牌/退市/新股按规程单独处理 |
| **B4 考虑问题全面** | 多空两面、宏观—行业—个股—资金—情绪—估值多维检查，必须主动搜索反驳证据 | 深思考锁定 reasoning_effort=max（xhigh 档经 Kimi 官方映射）；并行子代理/fork/workflow 分头核查；检查清单进 CLAUDE.md（见 10.4） |
| **B5 持续稳定复跑** | 盘后例行分析可无人值守运行，结论产物落盘存档、可审计 | bypassPermissions 全自动；无人值守重试；结论文件化；会话记录长期保留 |
| **B6 推理可审** | 深度结论的中间推理必须可见、可复查 | 思考过程全程开启且界面可展开审阅 |

### 1.3 多模态证据链（两场景共用）

BMC 侧的报错/崩溃截图、原理图与时序图、面板照片、复现录屏、PDF 规范文档（DSP0266 等），A 股侧的 K 线图、研报 PDF/扫描件、数据平台图表——大量一手证据天然是**非文本**形态。与 DeepSeek/GLM 配置的根本差异在于：**Kimi K3 旗舰原生具备视觉能力**（MoonViT-V2 视觉编码器，401M 参数，官方明示"understands text, images, and video within the same model"），主线收到图片不会报错。多模态需求的形态因此从"绕开主线的结构性限制"转变为"管理视觉证据进入主链路的方式"。由此反推的硬需求：

| 编号 | 需求 | 判定标准 |
| --- | --- | --- |
| **C1 多模态可读** | 图片、视频、文档三类证据都必须能被读取并转化为可靠文字 | 双通道架构：少量图片主线直读（原生视觉，已实测 OCR 走通）；批量帧序列、密集小字、多页文档经 vision 子代理（frontmatter 裸 `k3`，与主线同一旗舰）转录为文本证据回传——视觉洪流不挤占主线上下文与请求体积预算 |
| **C2 主线不妥协** | 为获得视觉能力，不得把主线或任何别名位换成次级模型 | 次级模型（`kimi-for-coding` 高速版、K2.8 等候选）不进入任何 `ANTHROPIC_DEFAULT_*_MODEL` 别名位；`/model` 选单无备选原则保持；vision 专线仅存在于子代理 frontmatter |
| **C3 视觉可靠性** | 视觉转文字的过程本身可审计：转录先行、细节保全、不确定性明示 | vision 子代理系统提示内置作业规程（先转录后判读、抽帧/裁剪保全、看不清就明说），见第 11 章 |

## 2. 对"高缓存命中"的定调

本手册对该机制的定调如下：

1. **缓存是无损机制，与准确性零冲突**。提示缓存的本质是"逐字节精确匹配的前缀复用"——命中时服务端复用的是与重算**完全相同**的计算结果，不存在"命中缓存导致回答质量下降"的情形。因此它不需要被刻意追求，也不需要被防范：保持默认开启即可（关闭它不会换取任何精度，只会让每轮重算同样的内容）。Kimi 网关为隐式自动缓存——**实测确认**首次请求后 `usage.cache_read_input_tokens` 即时回报命中（见 5.0 实测表第 3 条），无需任何客户端配置。
2. **本配置没有任何为缓存牺牲能力的设定**。唯一与缓存相关的参数 `CLAUDE_CODE_ATTRIBUTION_HEADER=0` 的作用是"从系统提示词开头移除客户端版本指纹块"——这是减少与任务无关的提示噪音，缓存收益属于附带效果。
3. **第 14 章"行为漂移源清单"的真正价值是一致性，而非费用**。中途切换模型、切换 effort、MCP 服务器断连、升级版本——这些操作的要害是**改变了模型的行为条件**（不同模型/档位/系统提示 = 不同的回答者），缓存重建只是其可观测的影子。Kimi 官方对两处缓存失效有明示，本手册将其纳入漂移清单固化：**切换模型 ID 会使已建立的上下文缓存全部失效**（"切换模型后，之前建立的上下文缓存不再命中……刚切换时消耗会偏高"）；**切换思考档位（effort）同样使缓存失效**（"切换思考程度会让已建立的上下文缓存失效……确需改用不同思考程度时，新建会话再切换"）。
4. **Kimi 侧与缓存相关且关乎精度的机制是 Preserved Thinking History**（保留历史轮推理内容）。K3 以"保留思考历史"模式训练，官方要求多轮对话把完整 assistant 消息（含推理内容与工具调用）原样传回——该机制**已由网关在 Anthropic 协议层自动处理**（实测确认：thinking block 连同 signature 回传后模型正确延续上轮推理，见 5.0 实测表第 13 条），无需客户端配置。它是精度特性（官方明示"提升模型表现"），缓存命中率提升是副产品。

- 来源：[Claude Code – Prompt caching（前缀精确匹配机制）](https://code.claude.com/docs/en/prompt-caching)、[Kimi Code – 模型配置（切换模型/思考程度使缓存失效、新会话建议）](https://www.kimi.com/code/docs/kimi-code/models.html)、[MoonshotAI/Kimi-K3（Preserved thinking history）](https://github.com/MoonshotAI/Kimi-K3)、[Claude Code – env-vars（`CLAUDE_CODE_ATTRIBUTION_HEADER`）](https://code.claude.com/docs/en/env-vars)

## 3. 模型策略：主线单旗舰（原生多模态）+ 视觉证据转录专线

Kimi Code 端点提供 4 个模型 ID，分属三类模型（官方模型总览）：

| Model ID | 模型版本 | 说明 | 速度 | 上下文窗口 | 思考程度 | 调用限制 | 多模态输入 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `k3` | **K3** | 最强旗舰编程模型，2.8T 参数规模 | 常规 | `1048576`（Allegretto 及以上） | low/high/max（默认 high） | Moderato 及以上 | **图片、视频** |
| `k3-256k` | K3 | K3 的 256K 上下文版本，256k 内效果与 K3 相同 | 常规 | `262144` | low/high/max（默认 high） | Moderato 及以上 | 仅图片 |
| `kimi-for-coding` | K2.8 Preview | 综合性能接近 K3，思考效率更高 | 常规 | `1048576` | low/high/max（默认 max） | 所有会员 | 图片、视频 |
| `kimi-for-coding-highspeed` | K2.7 Code HighSpeed | K2.7 Code 的高速版，输出速度约普通版 5–6 倍（3 倍消耗） | 高速 | `262144` | Thinking:ON | Allegretto 及以上 | 图片、视频 |

**主线：全部文本推理（含一切常规子代理与后台辅助任务）仅用 K3。** 选择依据是官方基准的硬数据（MoonshotAI 官方仓库发布口径，K3 以 `reasoning_effort=max` 评测；注意以下均为厂商自报）：

| Code Agent 基准 | Kimi K3 (max) | Opus 4.8 (max) | GPT-5.5 (xhigh) |
| --- | --- | --- | --- |
| Terminal-Bench 2.1 | **88.3** | 84.6 | 83.4 |
| DeepSWE v1.1 | **67.5** | 59.0 | 67.0 |
| FrontierSWE | **81.2** | 66.7 | 64.9 |
| SWE-Marathon | **42.0** | 40.0 | 14.0 |
| ProgramBench | **77.8** | 71.9 | 70.8 |
| Agents' Last Exam | **28.3** | 27.0 | 26.6 |
| MCPMark-Verified | **94.5** | 76.4 | 92.9 |

K3 在全部已公布的长时程/工具链基准上领先（SWE-Marathon 42.0 对 14.0 的差距正是"极少人工监督下持续完成长时间工程任务"这一官方定位的量化体现，直接对应 BMC 场景的多阶段迁移）；官方同时明示其"稳定超过 Opus 4.8、GPT 5.5 等主流模型，在 Kernel 优化等高难度编程任务中接近当前最强闭源模型"。因此：**四个别名位全部 K3，`/model` 选单不设任何备选**；后台辅助功能（Haiku 位：会话标题、WebFetch 内容抽取）同样采用旗舰——辅助环节不使用次级模型；`fallbackModel` 保持不设置，过载时按第 7.6 节看门狗重试同一模型，不允许静默降级出活。K2.8 Preview 的综合性能虽"接近 K3"，但极限长时程任务的旗舰定位无可替代，且其与 K3 之间存在模型切换缓存失效的行为漂移（第 2 章）——不进入主线任何路径。

**视觉证据转录专线：裸 `k3` 只存在于 vision 子代理。** 专线与主线是**同一个模型**（裸 `k3` 在服务端即 1M 窗口，实测 5.0 第 9 条），不存在任何"次级模型承担视觉"的精度折损——这是与 GLM 配置（flash 为独立小模型）的本质区别。之所以用裸 `k3` 而非 `k3-256k`：客户端对无法解析的裸名自定义 ID 按 `CLAUDE_CODE_MAX_CONTEXT_TOKENS` 直接设定假设窗口（官方三分支语义，7.4.1）——若用 `k3-256k`，客户端会按 1M 假设管理其窗口，超出 256K 真实上限后将硬失败而非压缩；裸 `k3` 的假设窗口（1M）与端点真实上限一致，800K 压缩安全网对专线同样完整生效。专线的存在理由不是"旗舰不能看图"（旗舰能看），而是**工程经济性**：

1. **上下文经济**：批量帧序列（一次录屏取证动辄数十张图）、多页扫描件逐页读、密集小字分块读——这些任务的原始图片若直入主线，将占用大量主线上下文 token（图片进入模型按视觉 token 计价，与服务端压缩规则相关），而其**结论形态是文本**（转录、时间点、结构描述）。子代理在独立窗口中消化图片洪流，回传的文本结论只占主线数千 token——这正是官方"上下文是最需要管理的资源"定调（7.4.0）在多模态侧的对称应用。
2. **请求体积安全**：图片以 base64 进入请求体（编码膨胀约 33%）。数十张高分辨率帧单批发送存在服务端请求体拒绝风险（官方错误参考将 `total message size ... exceeds limit` 列为最高频 400 错误；本配置实测 Anthropic 端点 4.2MB 仍在 token 层拦截而非消息体层——见 5.0 第 11 条——但 OpenAI 协议路径与大基数场景仍受该限制约束）。批量读取天然属于子代理的分批职责。
3. **证据规范化**：先转录后判读、估读精度标注、不可辨认明示——这些规程（C3）在子代理系统提示中固化，不依赖每次任务的下达质量。

隔离手段——**结构性分离**：

- 裸 `k3` 写法**仅出现在 vision 子代理定义**（`agents/vision.md`）的 `model` frontmatter 中——批量视觉任务在子代理的独立上下文中完成，文本结论回传主线；主线四位别名全部使用 env 专用的 `k3[1m]` 写法，两条通道在配置文本层面即可区分审计；
- **`CLAUDE_CODE_SUBAGENT_MODEL` 保持不设置**（第 8 章）：v2.1.251 起该变量仅是"未另行指定模型的子代理"的默认值——子代理定义的 `model` frontmatter 与调用时指定的模型都**优先于**它（v2.1.251 之前相反：它会覆盖 frontmatter）；强制所有子代理同模型另有专用开关 `CLAUDE_CODE_SUBAGENT_MODEL_FORCE`（v2.1.257+），本配置不使用。不设置该变量时：常规子代理按默认 `inherit` 继承主会话的 K3 (1M)，vision 子代理按 frontmatter 命中裸 `k3`——两条线各得其所，且与 Kimi 官方接入示例（该示例设置此变量）保持最小差异。

模型矩阵——**主线四位全旗舰 + 视觉转录专线同旗舰裸名直连，无任何备选、无任何回退**：

| Claude Code 模型位 | 值 | 承担的工作 |
| --- | --- | --- |
| Opus 位 | `k3[1m]` | 主会话（默认 `model: "opus"`）；少量图片（≤3 张、目标明确）可直读 |
| Sonnet 位 | `k3[1m]` | 任何解析到 sonnet 别名的路径（含 `opusplan` 执行阶段等） |
| Fable 位 | `k3[1m]` | 误触 `/model fable` / `best` 时的兜底 |
| Haiku 位 | `k3[1m]` | 后台辅助功能（标题、WebFetch 抽取等）。官方 Claude Code 接入示例对 Haiku 位同样使用 `$ANTHROPIC_MODEL`（即 `k3[1m]`），四个位保持一致以杜绝任何路径的模型偏离 |
| 常规子代理 | （不设 `CLAUDE_CODE_SUBAGENT_MODEL`，默认 `inherit`） | Explore、fork、workflow 代理、agent teams 队友全部继承主会话 = K3 (1M) |
| vision 子代理 | frontmatter `model: k3`（裸名） | 批量视觉证据（帧序列/密集小字/多页文档）的转录专线（第 7.13、11 章） |

**`k3[1m]` 写法的场景边界（实测证实的硬约束）**：`[1m]` 后缀**仅在 Claude Code 环境变量场景合法**（`ANTHROPIC_DEFAULT_*_MODEL` 等 env 写法，Claude Code 解析后缀声明 1M 窗口并在发送前剥除）；在 API 请求体、子代理 frontmatter、其它工具的 Model ID 字段直接使用 `k3[1m]` 会被服务端以 401 拒绝（`Your model id does not exist, recognized as other: k3[1m]`——官方错误参考明示 + 本配置实测复现，见 5.0 第 8 条）。因此 vision 子代理 frontmatter 必须写裸名（本配置为 `k3`）。

- 来源：[Kimi Code – 模型配置（模型总览表、effort 映射、`k3[1m]` 边界、切换注意事项）](https://www.kimi.com/code/docs/kimi-code/models.html)、[Kimi Code – Claude Code 接入（官方环境变量示例、`k3[1m]` 说明）](https://www.kimi.com/code/docs/third-party-tools/claude-code.html)、[Kimi Code – 概览（Base URL 与模型 ID 表）](https://www.kimi.com/code/docs/)、[MoonshotAI/Kimi-K3（模型规格、基准全表、原生多模态）](https://github.com/MoonshotAI/Kimi-K3)、[Claude Code – Sub-agents（`model` frontmatter 与解析优先级（v2.1.251 起）：调用参数 > frontmatter > SUBAGENT_MODEL 默认 > 继承）](https://code.claude.com/docs/en/sub-agents)、[Claude Code – Model configuration（别名机制、Fallback model chains）](https://code.claude.com/docs/en/model-config)

## 4. 需求 → 配置追溯矩阵

| 需求 | 对应配置/机制 | 详解章节 |
| --- | --- | --- |
| A1 跨栈上下文 | `k3[1m]` 全别名位、`CLAUDE_CODE_AUTO_COMPACT_WINDOW=800000`（1M 窗口 + 800K 压缩水位）、`CLAUDE_CODE_MAX_CONTEXT_TOKENS=1048576`、`CLAUDE_CODE_ADDITIONAL_DIRECTORIES_CLAUDE_MD=1`、`CLAUDE_CODE_GLOB_TIMEOUT_SECONDS=60`、上下文生命周期规程 | 7.2 / 7.4 / 9.4 |
| A2 长周期执行 | `API_TIMEOUT_MS=3000000`、`API_FORCE_IDLE_TIMEOUT=0`、`CLAUDE_STREAM_IDLE_TIMEOUT_MS=1800000`、`CLAUDE_CODE_RETRY_WATCHDOG=1`、`BASH_MAX_TIMEOUT_MS=3600000`、`CLAUDE_ASYNC_AGENT_STALL_TIMEOUT_MS=3600000` | 7.6 |
| A3 证据先行 | `BASH_MAX_OUTPUT_LENGTH=150000`、`TASK_MAX_OUTPUT_LENGTH=160000`、`MAX_MCP_OUTPUT_TOKENS=50000`、`CLAUDE_CODE_FILE_READ_MAX_OUTPUT_TOKENS=65536` | 7.5 |
| A4 规范硬约束 | CLAUDE.md 模板、验证闭环规程、（可选）项目级 deny/hooks | 9.2–9.4 |
| A5 大规模并行 | `workflowSizeGuideline=unrestricted`（解锁默认 medium 的规模引导）、`CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1`、`CLAUDE_CODE_FORK_SUBAGENT=1`、worktree、ultracode workflow 通道（effort 锁定 `xhigh`） | 7.10 / 9.5 |
| A6 / B5 行为一致性 | 全 K3 单模型、effort 环境变量锁定（xhigh→max）、thinking 红线（关 thinking 即降级 K2.8 无思考版）、不设 fallback、升级 SOP、漂移源清单 | 3 / 7.3 / 13 / 14 |
| B1 数据可靠 | 双源交叉规程、`skipWebFetchPreflight`、数据铁律、取证级读取走 Bash `curl`/本地接口 | 10.2 |
| B2/B3 口径与时点 | A 股 CLAUDE.md 模板（口径声明块、时点规程） | 10.3 |
| B4 全面性 | `reasoning_effort=max` 锁定、fork/子代理并行核查、检查清单 | 7.3 / 10.4 |
| B5 持续复跑 | bypassPermissions、无人值守重试、headless 例行任务、`preferredNotifChannel=terminal_bell`（完成/待输入铃声）、`minimumVersion=2.1.246`（门槛硬执行） | 7.9 / 7.11 / 7.12 / 10.5 |
| B6 推理可审 | `alwaysThinkingEnabled`（红线：关闭即模型降级）、`showThinkingSummaries`、thinking 恒开（实测确认）、fullscreen 渲染（压缩后全量回滚 + `Ctrl+O` 全文检索） | 7.3 / 7.12 |
| C1 多模态可读 | 主线 `k3[1m]` 原生视觉直读（实测 OCR 走通）+ vision 子代理（`model: k3` 裸名）批量转录 + ffmpeg 视频抽帧 + PDF 转图分页 | 7.13 / 11 |
| C2 主线不妥协 | 次级模型（K2.8/高速版）零别名位；vision 专线与主线同源同窗口；不设 `CLAUDE_CODE_SUBAGENT_MODEL` | 3 / 7.13 / 8 |
| C3 视觉可靠性 | vision 子代理系统提示（转录先行/裁剪保全/不确定性标注） | 11 |

---

# 第二部分：配置

## 5. 工作原理速览

### 5.0 端点实测记录（第一手依据，2026-09-15）

本配置编制过程中对 `https://api.kimi.com/coding/v1/messages`（Anthropic 协议端点）进行了直接实测。以下 13 项结论与官方文档共同构成配置依据；凡引用"实测"处均指本表：

| # | 实测项 | 结果与结论 |
| --- | --- | --- |
| 1 | 认证方式：`x-api-key` 头（对应 Claude Code 的 `ANTHROPIC_API_KEY` 变量） | **通过**。官方接入文档即用 `ANTHROPIC_API_KEY` |
| 2 | K3 thinking 行为：未传 thinking 参数的裸请求 | 响应自动含 `thinking` 内容块（带 `signature`）——**thinking 恒开**，与官方 "Kimi K3 always has thinking enabled" 一致 |
| 3 | 隐式缓存 | 首次请求后 `usage.cache_read_input_tokens` 即时回报命中（91）——隐式自动缓存生效，无需配置 |
| 4 | `max_tokens=131072` | **接受**（128K 输出上限设计成立） |
| 5 | `k3-256k` / `kimi-for-coding` 模型可用性 | 均正常响应 |
| 6 | `thinking: {type:"enabled", budget_tokens:1024}` 参数 | 接受，不冲突 |
| 7 | 图片输入：Anthropic `image` 内容块（base64 `image/png`） | **走通**；绘制文字 "HELLO-K3-7391" 的 PNG 被逐字精确转录——视觉链路在 Anthropic 协议下完整可用 |
| 8 | `k3[1m]` 作为裸 API model id | **401 拒绝**——`[1m]` 后缀仅在 Claude Code 环境变量场景合法（官方口径 + 实测双重证实）；frontmatter/请求体必须用裸名 |
| 9 | 裸 `k3` 的 token 上限 | 报错文案 `Your request exceeded model token limit: 1048576`——**裸 k3 即 1M 窗口**（该密钥档位已解锁），`k3[1m]` 的 env 写法只影响 Claude Code 侧的窗口管理 |
| 10 | 1.15MB 请求体（≈308K token） | 通过 |
| 11 | 2.4MB 请求体（≈335K token） / 4.2MB 请求体（≈1.13M token） | 2.4MB **通过**；4.2MB 被拒，但错误是 **token 超限**（1,125,107 > 1,048,576）而非消息体超限——Anthropic 端点在 4.2MB 量级仍未见 `2097152` 消息体限制触发（该限制列于官方错误参考、主要约束 OpenAI 协议路径与大基数场景；8MB 级未测，留有余量假设） |
| 12 | 编码密度 | 4,200,115 字节 ÷ 1,125,107 token ≈ **3.73 bytes/token**（英文散文；代码/JSON 通常更高）——800K 水位对应请求体 ≈ 3.0MB，处于实测安全区内 |
| 13 | 多轮 thinking block 回传（preserved thinking history） | assistant 消息含 thinking block（含 signature）+ text block 原样回传后再追问 → 正确延续上轮记忆（记住数字 4271）——Claude Code 工具调用循环的核心链路兼容 |

### 5.1 网关模式

Claude Code 通过 `ANTHROPIC_BASE_URL` 将全部模型请求改发至兼容 Anthropic Messages 协议的端点；该变量仅改变"请求发往何处"，不改变"哪个模型回答"。Kimi Code 的双协议端点为：

| 协议 | Base URL | Endpoint 示例 |
| --- | --- | --- |
| OpenAI 兼容 | `https://api.kimi.com/coding/v1` | `https://api.kimi.com/coding/v1/chat/completions` |
| **Anthropic 兼容（本配置使用）** | `https://api.kimi.com/coding/`（官方写法含尾斜杠） | `https://api.kimi.com/coding/v1/messages` |

**两套体系不可混用**（官方错误参考将 `Invalid Authentication` 的最常见原因归结于此）：Kimi Code（会员订阅，Key 从 [Kimi Code 控制台](https://www.kimi.com/code/console) 获取）与 Kimi 开放平台（按量付费，`https://api.moonshot.cn/v1`，Key 从 platform.kimi.com 获取）是独立系统，**Key 与 Base URL 均不通用**。

**官方接入流程的三步骤**（`deploy.ps1` 已全量自动化，见第 6 章）：① 安装 Claude Code；② 向 `%USERPROFILE%\.claude.json` 写入 `penguinModeOrgEnabled: true` 与 `hasCompletedOnboarding: true`（启用第三方模型支持并跳过 Anthropic 登录引导——官方以 node 脚本形式提供，本配置的部署脚本内置等价实现）；③ 设置环境变量后启动。启动后 `/status` 中 Base URL 显示 `https://api.kimi.com/coding/` 即接入成功——此时即使模型名称仍显示为 Claude 模型，实际调用的已是 Kimi 模型（官方明示）。

**User-Agent 红线**：官方明示"使用时请保持工具的真实身份标识，篡改客户端标识（User-Agent）将被视为违规，可能导致会员权益暂停"。本配置不设置任何 UA 相关环境变量；使用者亦不得以任何手段伪装客户端身份。

- 来源：[Kimi Code – 概览（双协议端点表、平台对比、UA 条款）](https://www.kimi.com/code/docs/)、[Kimi Code – Claude Code 接入（三步骤、.claude.json 引导脚本、/status 验证）](https://www.kimi.com/code/docs/third-party-tools/claude-code.html)、[Kimi Code – 错误参考（Invalid Authentication / 两体系不通用）](https://www.kimi.com/code/docs/kimi-code/error-reference.html)、[Claude Code – Model configuration](https://code.claude.com/docs/en/model-config)

### 5.2 别名映射与 effort 映射

模型别名（opus/sonnet/haiku/fable）由 `ANTHROPIC_DEFAULT_*_MODEL` 解析（见第 3 章矩阵）。Claude Code 的 effort 档位经 Kimi 端点映射为 K3 的 `reasoning_effort`（官方映射表）：

| Claude Code effort | K3 reasoning_effort |
| --- | --- |
| `low` | `low` |
| `medium` / `high` | `high`（官方推荐档） |
| `xhigh` / `max` | **`max`**（K3 的最深推理档。Kimi 文档该档原文写作 `ultra / max / xhigh`；注意 Claude Code 的 ultracode 是客户端编排设置而非模型档位——开启时实际向模型发送 `xhigh`，经本行映射到 max） |
| 未设置（默认） | `high`（K3 网关侧默认；注意开放平台 API 的 K3 默认为 `max`——以 Kimi Code 文档为准） |
| 未知取值 | **HTTP 400**（端点对无法识别的 effort 值直接报错，不静默回退） |
| `none` | thinking disabled——**降级陷阱，见下** |

**两条硬性警告**（写入第 14 章漂移清单）：

1. **关闭 thinking = 静默换模型**。官方明示："关闭 thinking 后 K3 系列与 K2.8 Preview 的请求均路由到 K2.8 Preview（无思考）"。本配置以 `alwaysThinkingEnabled: true` 从客户端封死该路径（7.3）；Claude Code 侧关闭 thinking 的快捷键（Windows/Linux 为 `Alt+T`）不得使用。
2. **effort 切换使上下文缓存失效**。官方明示切换思考程度会让已建立的缓存失效、需重新预填充；确需改档时新建会话再切，不在长会话中反复切换（A6）。

- 来源：[Kimi Code – Claude Code 接入（effort 映射表、thinking 警告、Alt+T）](https://www.kimi.com/code/docs/third-party-tools/claude-code.html)、[Kimi Code – 模型配置（第三方工具 effort 映射、未知值 400）](https://www.kimi.com/code/docs/kimi-code/models.html)、[MoonshotAI/Kimi-K3（API 默认 effort=max）](https://github.com/MoonshotAI/Kimi-K3)

### 5.3 两层缓存（背景知识，非优化目标）

Claude Code 侧为前缀精确匹配的提示缓存；Kimi 侧为隐式自动缓存（实测 `usage.cache_read_input_tokens` 即时回报命中）+ Preserved Thinking History（推理内容跨轮保留，网关自动处理，实测走通）。定调见第 2 章，漂移源清单见第 14 章。

- 来源：[Claude Code – Prompt caching](https://code.claude.com/docs/en/prompt-caching)、[MoonshotAI/Kimi-K3（Preserved thinking history）](https://github.com/MoonshotAI/Kimi-K3)

## 6. 配置文件位置、生效时机与验证

| 作用域 | Windows 路径 | 影响范围 |
| --- | --- | --- |
| **用户级（本配置使用）** | `%USERPROFILE%\.claude\settings.json` | 当前用户、所有项目 |
| 项目级（共享） | `<项目>\.claude\settings.json` | 该仓库所有协作者 |
| 项目级（本地） | `<项目>\.claude\settings.local.json` | 当前用户、仅该仓库 |
| 托管策略 | `C:\Program Files\ClaudeCode\managed-settings.json` 等 | 全机器，最高优先级 |
| 客户端状态 | `%USERPROFILE%\.claude.json` | onboarding/第三方模型支持开关、MCP 注册（非 settings.json 职责） |

要点：

- 优先级：托管 > 命令行 > 项目本地 > 项目共享 > 用户级；**数组类设置（如 `permissions.allow`）跨作用域合并**而非覆盖。
- 环境变量与设置字段并存时**环境变量优先**；同一变量在 shell 与 settings 的 `env` 块并存时 **`env` 块优先**（启动时写入进程环境覆盖 shell 值）——因此一切变量集中配置于 `env` 块。
- settings 文件被监视并**热加载**大部分键；`model`、`outputStyle` 等在下次启动/`/model` 时生效。**`.claude.json` 的引导字段不热加载**——部署后必须新开会话。
- 验证：`/status`（Setting sources、Model、**Base URL 应显示 `https://api.kimi.com/coding/`**）、`/context`（窗口占用）、`/mcp`（MCP 状态）、`claude doctor`（健康检查）。

部署步骤（`d-kimi` 一键完成，亦可手动执行）：

1. 将仓库根目录 [`settings.json`](./settings.json) 部署至 `%USERPROFILE%\.claude\settings.json`，并将 `ANTHROPIC_API_KEY` 的占位值替换为实际的 Kimi Code API Key（[Kimi Code 控制台](https://www.kimi.com/code/console) 创建；最多 5 个，仅创建时显示一次）。
2. 引导 `%USERPROFILE%\.claude.json`：写入 `penguinModeOrgEnabled: true` 与 `hasCompletedOnboarding: true`（官方接入流程步骤②的等价实现）。
3. 将 [`agents/vision.md`](./agents/vision.md) 部署至 `%USERPROFILE%\.claude\agents\vision.md`（视觉转录专线，全项目可用；与 ds-settings/glm-settings 等其它供应商配置共用同一部署位时，切换供应商须同步替换此文件——各配置库的 vision 子代理指向各自端点的模型，混用必然路由失败）。
4. 关闭全部既有会话窗口后重新启动 `claude`，首次提示 "Do you want to use this API key?" 时确认使用。

**环境变量残留排查**：Kimi 官方错误参考指出 `KIMI_API_KEY` / `OPENAI_API_KEY` 等环境变量可能覆盖配置文件中的密钥（Kimi Code CLI 自身读取 `KIMI_API_KEY`）。本配置的 `env` 块优先级高于 shell 环境变量，但为杜绝歧义：`ANTHROPIC_AUTH_TOKEN`（Z.AI 配置的认证变量）与 `ANTHROPIC_BASE_URL` 的 shell 残留在切换供应商时必须清除（`[Environment]::GetEnvironmentVariable('ANTHROPIC_AUTH_TOKEN','User')` 检查）。

**官方脚本不可重入警告**：Kimi 官方接入文档步骤②的 node 脚本除写入 `.claude.json` 引导字段外，还会**删除** settings.json `env` 中的接入变量（`ANTHROPIC_BASE_URL`/`ANTHROPIC_API_KEY`/四个别名位/`CLAUDE_CODE_EFFORT_LEVEL`/`CLAUDE_CODE_AUTO_COMPACT_WINDOW` 等，作为切换到 Kimi 前的历史清理）。`deploy.ps1` 只实现了引导字段写入、未复制该删除逻辑（它整体覆盖 settings.json，无残留可清）。因此：**部署本配置后不要再手动执行官方步骤②脚本**——误执行后重跑 `d-kimi` 即可完整恢复。

安全提示：settings.json 中包含明文 API Key。将该文件提供给任何第三方、进行截图分享或提交至公开仓库之前，必须先移除 Key；已暴露的 Key 应立即在 Kimi Code 控制台撤销重建。

- 来源：[Claude Code – Settings（scopes / precedence / 热加载 / 验证）](https://code.claude.com/docs/en/settings)、[Claude Code – env-vars（Precedence）](https://code.claude.com/docs/en/env-vars)、[Kimi Code – Claude Code 接入](https://www.kimi.com/code/docs/third-party-tools/claude-code.html)、[Kimi Code – 错误参考（环境变量覆盖密钥条目）](https://www.kimi.com/code/docs/kimi-code/error-reference.html)

## 7. 参数逐项详解

除特别说明外，`env` 值一律为**字符串**。每项给出：名称、值、含义与理由、来源。

### 7.1 接入与认证

| 参数 | 值 | 含义与理由 |
| --- | --- | --- |
| `env.ANTHROPIC_BASE_URL` | `https://api.kimi.com/coding/` | Kimi Code 的 Anthropic 协议端点。官方写法含尾斜杠（"部分工具（如 Claude Code）只需填写 Base URL，工具会自动拼接后续路径"）。 |
| `env.ANTHROPIC_API_KEY` | 使用者的 Kimi Code API Key | 以 `x-api-key` 头发送（实测通过，5.0 第 1 条）——官方接入文档的指定变量。**系统中不得残留 `ANTHROPIC_AUTH_TOKEN`**（Z.AI 配置的 Bearer 认证变量），切换供应商时须清除，避免双认证冲突。 |

`.claude.json` 引导（由 `deploy.ps1` 自动完成，非 settings.json 参数）：`penguinModeOrgEnabled: true`（第三方模型支持）+ `hasCompletedOnboarding: true`（跳过 Anthropic 登录引导）。这是官方接入流程的必要步骤——缺失时 Claude Code 启动将要求登录 Anthropic 账号。

- 来源：[Kimi Code – Claude Code 接入](https://www.kimi.com/code/docs/third-party-tools/claude-code.html)、[Kimi Code – 概览（端点表）](https://www.kimi.com/code/docs/)、[Claude Code – env-vars（两认证变量条目）](https://code.claude.com/docs/en/env-vars)

### 7.2 模型矩阵（全 K3）

| 参数 | 值 | 含义与理由 |
| --- | --- | --- |
| `env.ANTHROPIC_DEFAULT_OPUS_MODEL` | `k3[1m]` | 主力位。`[1m]` 使 Claude Code 按 1M 窗口管理会话，发送前自动剥除后缀（裸 `k3` 在服务端即为 1M 上限，实测 5.0 第 9 条）。 |
| `env.ANTHROPIC_DEFAULT_SONNET_MODEL` | `k3[1m]` | 覆盖一切解析到 sonnet 的路径。 |
| `env.ANTHROPIC_DEFAULT_FABLE_MODEL` | `k3[1m]` | 覆盖 `fable`/`best` 别名路径。 |
| `env.ANTHROPIC_DEFAULT_HAIKU_MODEL` | `k3[1m]` | **后台辅助功能同样采用旗舰**（第 3 章）。官方 Claude Code 接入示例对 Haiku 位同样使用 `$ANTHROPIC_MODEL`（即 `k3[1m]`），四位一致与官方配置完全对齐，杜绝任何路径的模型偏离。 |
| `model`（顶层） | `opus` | 会话启动模型显式声明，杜绝默认值漂移。 |
| 子代理模型 | （不设 `CLAUDE_CODE_SUBAGENT_MODEL`） | 常规子代理默认 `inherit` 继承主会话的 k3[1m]；vision 子代理按 frontmatter 命中裸 `k3`（第 3 章、7.13）。v2.1.251 起该变量仅充当"未另行指定模型的子代理"的默认值——frontmatter 与 per-spawn 指定均优先于它；本配置保持不设，与官方示例维持最小差异（取舍详见第 8 章）。 |
| `env.ANTHROPIC_DEFAULT_*_MODEL_NAME` / `_DESCRIPTION` | `Kimi K3 (1M)` 等 | `/model` 选择器显示名（官方说明 `_NAME`/`_DESCRIPTION` 在网关模式生效）。 |
| `env.ANTHROPIC_DEFAULT_*_MODEL_SUPPORTED_CAPABILITIES` | `effort,xhigh_effort,max_effort,thinking`（四个位一致） | 向 Claude Code 声明自定义模型 ID 支持的能力，解锁 effort 滑杆与 xhigh/max 档、思考渲染。**有意不声明 `adaptive_thinking` / `interleaved_thinking`**：K3 的思考机制为恒开 thinking + `reasoning_effort` 三档（官方与实测均无 adaptive/interleaved 的能力证据），Kimi 端点对无法识别的参数取值存在直接 400 的先例（effort 未知值即 400）——按"实测确认的才声明"原则保守声明，未声明的能力仅损失客户端侧开关、不引入请求失败风险（第 8 章取舍表）。 |

**不设 `ANTHROPIC_MODEL`**：官方示例虽设置该变量，但其作用是强制锁定主模型、屏蔽 `/model` 切换；本配置以四位别名全覆盖达到同样效果且保留会话内模型查询能力。`CLAUDE_CODE_SUBAGENT_MODEL` 的取舍见第 8 章。

- 来源：[Kimi Code – Claude Code 接入（官方环境变量示例）](https://www.kimi.com/code/docs/third-party-tools/claude-code.html)、[Claude Code – Model configuration（Environment variables / `[1m]` / Customize pinned model display and capabilities）](https://code.claude.com/docs/en/model-config)

### 7.3 思考深度：锁定 reasoning_effort=max（A6 / B4 / B6）

| 参数 | 值 | 含义与理由 |
| --- | --- | --- |
| `env.CLAUDE_CODE_EFFORT_LEVEL` | `xhigh` | **锁定档**。环境变量是 effort 的最高优先级来源（高于 `/effort` 与 `effortLevel` 设置）。之所以锁定 `xhigh` 而非 `max`：① 经 Kimi 官方映射，`xhigh` 与 `max` 均落到 K3 的 `reasoning_effort=max`，**推理深度无差别**；② 官方明确"当 `CLAUDE_CODE_EFFORT_LEVEL` 被设为 xhigh 以外的档位时，请求按该档执行且 **ultracode 的 workflow 编排保持关闭**"——即锁定 `max` 会随之关闭 ultracode 的动态工作流编排（A5 大规模并行审计、B4 多角度交叉核查的主力通道），而 ultracode 本身发送给模型的本就是 `xhigh`。锁定 `xhigh` 即以相同的最深推理保留自动编排通道，为严格占优的选择。 |
| `effortLevel`（顶层） | `xhigh` | 冗余保障层：若上述环境变量被移除，会话仍持久落在 xhigh——经 Kimi 映射仍是 `reasoning_effort=max`，双重保障。 |
| `env.CLAUDE_CODE_ALWAYS_ENABLE_EFFORT` | `1` | Claude Code 默认仅对其识别的 Claude 模型 ID 发送 effort 参数；`k3[1m]` 是自定义 ID，不设此项 effort 可能根本不随请求发出。官方原文："Use this when routing through an LLM gateway or third-party provider that serves models under custom identifiers." |
| `alwaysThinkingEnabled`（顶层） | `true` | **红线级参数**：K3 thinking 恒开（实测 5.0 第 2 条），且官方明示**关闭 thinking 会被路由到 K2.8 Preview（无思考）**——那是静默换模型，直接违反 A6 与"单旗舰无降级"总原则。本参数保证客户端不发出关闭思考的请求形态；`Alt+T` 快捷键（Windows）不得使用。 |
| `showThinkingSummaries`（顶层） | `true` | 思考内容在界面可见（`Ctrl+O` 展开）——B6"推理可审"的界面开关。A 股结论必须回看推理链；BMC 大改动前亦应审查其方案推演。 |

配额视角提示（可用性，非费用）：`k3`（1M）的消耗约为 `k3-256k` 的两倍（官方口径）；vision 专线改用裸 `k3` 后不再享有该差价，按"成本不纳入决策"的总原则属可接受代价。这不改变任何决策——触及 5 小时窗口或周额度上限时按第 12 章处置（切换账号或等待窗口滚动），不降模型、不降档位。

- 来源：[Kimi Code – Claude Code 接入（effort 映射表、xhigh→max）](https://www.kimi.com/code/docs/third-party-tools/claude-code.html)、[Kimi Code – 模型配置（thinking 关闭路由警告、缓存失效警告）](https://www.kimi.com/code/docs/kimi-code/models.html)、[Claude Code – Model configuration（Adjust effort level：max 持久化例外条款、优先级顺序）](https://code.claude.com/docs/en/model-config)、[Claude Code – env-vars（`CLAUDE_CODE_EFFORT_LEVEL`、`CLAUDE_CODE_ALWAYS_ENABLE_EFFORT`）](https://code.claude.com/docs/en/env-vars)、[Claude Code – Settings（`alwaysThinkingEnabled`、`showThinkingSummaries`、`effortLevel`）](https://code.claude.com/docs/en/settings)

### 7.4 上下文：1M 窗口 + 800K 压缩水位（A1）

#### 7.4.0 定调：为什么不是"1M 用到尽头"

窗口大小与压缩水位是**两个独立旋钮**：`[1m]` 后缀声明容量（模型能装多少），`CLAUDE_CODE_AUTO_COMPACT_WINDOW` 声明水位（装到多满时把对话史压缩成摘要）。Kimi 官方 Claude Code 接入示例将水位设为满格 1048576（该示例值只演示"解除默认提前压缩"，未考虑压缩请求自身的可行性），GLM 配置的实践已证明其后果：**会话逼近上限时手动/自动压缩双双失败、整个会话不可恢复**，只能导出重开。本配置将水位定为 800000，定调依据分三层，各自独立、各自充分：

**第一层（机制层）：满格水位使压缩在结构上必然失败。**

1. **压缩本身是一次模型请求**：官方明确自动压缩与 `/compact` 是同一操作——把**全部对话史 + 摘要指令**发给模型生成摘要。请求发出时还要叠加 `max_tokens` 输出预留（本配置 131072）与思考开销（v2.1.198 起压缩请求继承会话的扩展思考配置，本配置恒为 `reasoning_effort=max`）。水位=1M 意味着压缩恰好在"历史已占满窗口"时才启动——此时 `历史(~1M) + 摘要指令 + 131K 输出预留 > 1048576`，压缩请求本身被服务端拒绝（Kimi 端点的拒绝形态实测为 `Your request exceeded model token limit: 1048576`，5.0 第 11 条）。**手动 `/compact` 同理失败**（同一请求形态），且自动压缩连续失败 3 次后官方熔断器停止重试——会话就此死锁。
2. **网关场景没有"错误触发式"最后防线**：官方明确，靠"prompt is too long"报错触发的兜底压缩**要求报错文案是 Claude Code 可识别的**——"Claude Code doesn't run that recovery when a gateway rewrites the error to wording Claude Code doesn't recognize"。Kimi 网关的报错文案（`Invalid request: Your request exceeded model token limit: 1048576 (requested: N)`）不在识别列表内，撞墙后没有任何自动恢复路径。
3. **Anthropic 对自家 1M 模型同样不用满格**：官方默认下 Sonnet 5 的 1M 会话在 **约 967K** 即自动压缩（v2.1.247 changelog 原文），即 Anthropic 直连、自家分词、32K 输出预留的最优条件下也保留 3%+ 余量。经网关 + 128K 输出预留 + 第三方分词计数的条件下，余量必须显著更大。
4. **800000 的算术**：压缩请求规模 ≈ 800K 历史 + 摘要指令 + 131072 输出预留 ≈ 935K < 1048576，留 ~113K 结构余量吸收系统提示、思考与计数偏差；触发前的每一轮常规请求同样满足 `输入 + 131K ≤ 1M`。水位可按任务在 700K–850K 间调节（`/autocompact` 会报告被环境变量接管；改动属行为漂移，仅在任务边界执行）；**850K 以上余量不足以稳定容纳压缩请求自身，禁入**。

**第二层（传输层，Kimi 特有）：请求体规模受隐性约束。** 官方错误参考将 `total message size N exceeds limit 2097152`（2MB）列为**出现频率最高的 400 错误**。本配置实测：Anthropic 端点在 2.4MB（≈335K token）通过、4.2MB 被拒但错误为 token 超限而非消息体超限（5.0 第 10/11 条）——即 Anthropic 路径的即时约束在 4MB 级以上，2MB 文案主要约束 OpenAI 协议路径或已放宽。以实测编码密度 3.73 bytes/token 折算：**800K 水位对应请求体 ≈ 3.0MB**，处于实测安全区内且保留约 1.2MB 余量；而满格 1M 水位对应 ≈ 3.9MB，已逼近实测拦截边界（4.2MB 拒绝），叠加 base64 图片（膨胀 33%）时随时越界。水位 800K 同时满足 token 层与传输层双重要求——这是"两层独立依据收敛于同一取值"的定调。

**第三层（质量层）：即便压缩不失败，"用尽 1M"也违背"正确性压倒一切"。** 权威证据一致表明模型质量随上下文填充度上升而下降，且远在名义上限之前：

| 来源 | 性质 | 结论 |
| --- | --- | --- |
| [Claude Code – Best practices](https://code.claude.com/docs/en/best-practices) | 官方文档 | "绝大多数最佳实践基于一个约束：上下文窗口填充得很快，**且性能随填充而下降**……窗口接近满时，Claude 可能开始'忘记'先前的指令或犯更多错误。上下文是最需要管理的资源。" |
| [Anthropic – Effective context engineering for AI agents](https://www.anthropic.com/engineering/effective-context-engineering-for-ai-agents) | 官方工程博客 | 提出 **context rot**：随 token 数增加，模型从上下文中准确召回信息的能力下降，"该特性在**所有模型**上出现"；上下文必须被视为**边际收益递减的有限资源**（注意力预算）；并明确"**等待更大的窗口**看似显然，但可预见的未来内，任何尺寸的窗口都受上下文污染与信息相关性问题制约"。长程任务的官方三板斧：压缩、结构化笔记（落盘）、子代理架构——与本手册 9.4/7.10/7.13 完全同构。 |
| [Chroma – Context Rot 技术报告](https://research.trychroma.com/context-rot)（2025-07） | 独立实验室受控实验 | 18 个 SOTA 模型（含闭源旗舰与开源权重），**保持任务复杂度恒定、仅变输入长度**："所有实验中，模型性能随输入长度增加而一致性下降"，且退化非均匀；报告明确指出真实任务复杂度更高，实际退化只会比该受控下限更显著。 |
| [NoLiMa（ICML 2025）](https://arxiv.org/abs/2502.05167) | 同行评审论文 | 13 个声称 ≥128K 窗口的模型，剔除字面匹配捷径后：**仅 32K 处就有 11 个模型跌破其短上下文基线的 50%**；GPT-4o 从 99.3% 降至 69.7%。 |
| [RULER（COLM 2024）](https://arxiv.org/abs/2404.06654) | 同行评审论文 | 17 个长上下文模型：NIAH 近满分的模型在稍复杂任务上"几乎全部随长度大幅退化"，**声称窗口 ≥32K 的模型只有一半在 32K 处维持合格表现**——"名义窗口 ≠ 有效窗口"。 |
| [MoonshotAI – Kimi K3 技术口径](https://github.com/MoonshotAI/Kimi-K3) | 厂商官方 | K3 的长程能力定位是"大规模代码库与长程连贯推理"（KDA 混合线性注意力的架构收益），厂商基准评测中 BrowseComp 采用 **300K token 触发的上下文压缩策略**——官方自身的长程评测方案就是压缩分段，而非填满窗口。 |

由此定调：**1M 窗口的价值是"单阶段容量"（一次装下跨栈证据链），不是"会话寿命"（把整个多日任务塞进一个窗口）**。会话寿命由第 9.4 节的上下文生命周期规程承担：证据落盘 → 阶段边界主动压缩/清空 → 从磁盘再引导。旧做法（用尽 1M → 报错 → 导出重开）在三层上都是劣势：末端 20% 的推理恰是全会话质量最低的部分，而崩溃式重开丢失的工作状态远多于一次受控压缩。

#### 7.4.1 参数

| 参数 | 值 | 含义与理由 |
| --- | --- | --- |
| `env.CLAUDE_CODE_AUTO_COMPACT_WINDOW` | `800000` | **压缩水位**（定调依据见 7.4.0 三层论证）。取值区间 100000–1000000（官方语义按窗口上限折算）、仅接受纯数字；环境变量优先于 `/autocompact` 命令、`--autocompact` 旗标与 `autoCompactWindow` 设置键，对主会话与子代理一并生效。仍远高于 200K 默认边界，Kimi"启用 1M 需配套设置压缩窗口"的要求继续满足。注意：设置本变量后，状态栏 `used_percentage` 仍按模型全窗口计量，不再指示压缩触发点。 |
| `env.CLAUDE_CODE_MAX_CONTEXT_TOKENS` | `1048576` | 显式声明窗口大小。按官方三分支语义：主会话的 `k3[1m]`（含 `[1m]` 的未解析自定义 ID）由后缀直接推定 1M，本变量**不单独生效**；它对**不含 `[1m]` 的未解析裸名 ID 直接生效**——这正是 vision 子代理 frontmatter 选用裸 `k3` 的决定性理由：裸 `k3` 的假设窗口由此被正确设为 1M（与端点真实上限一致，800K 压缩安全网在专线同样成立）；若改用 `k3-256k`，客户端将按本变量把它误当 1M 窗口管理，超出 256K 真实上限后会以 token 超限硬失败而非触发压缩。 |
| `env.CLAUDE_CODE_MAX_OUTPUT_TOKENS` | `131072` | 单请求输出上限。实测 `max_tokens=131072` 被端点接受（5.0 第 4 条）；Kimi 官方口径中 128k 是压缩输出与未知模型的输出上限基准（"默认将压缩输出限制在 128k token，避免触发供应商的 max_tokens 错误"、"未知模型回退到 128k 输出上限"），128K 为有官方与实测双重支撑的安全值。整文件重写、长分析报告单轮完成，不因输出配额被截断。**知情权衡**（官方明示"提高该值会减少触发 auto-compaction 前的可用上下文"）：该预留已计入 7.4.0 的水位算术——800K 水位 + 131K 预留 + 结构余量恰好安全装入 1M，两参数是配套设计，调整任一须重算另一。 |
| `env.CLAUDE_CODE_ADDITIONAL_DIRECTORIES_CLAUDE_MD` | `1` | **多仓库工作区关键项**：默认情况下 `--add-dir`/`/add-dir` 挂载的目录**不加载**其 CLAUDE.md/规则文件；置 1 后各仓库的 `CLAUDE.md`、`.claude/rules/*.md`、`CLAUDE.local.md` 全部载入。BMC 场景将 u-boot、kernel、openbmc、webui 各自的工程约定同时载入上下文（A1/A4）。 |
| `env.CLAUDE_CODE_GLOB_TIMEOUT_SECONDS` | `60` | Glob 文件发现超时从默认 20 秒提高到 60 秒（官方在 WSL 上的默认值）。Yocto 全量源码树等超大目录的检索不因超时遗漏文件（A1/A3）。 |

**不设** `CLAUDE_CODE_DISABLE_1M_CONTEXT`（按 200K 处理）与 `DISABLE_AUTO_COMPACT`/`DISABLE_COMPACT`（800K 水位的自动压缩是避免请求直接失败的最后防线；配合第 9/10 章"关键证据落盘"规程，压缩造成的损失可控）。

**K3（1M）与 K3-256k 之间的切换纪律**（官方明示 + 第 14 章固化）：`k3`→`k3-256k` 切换前若上下文已超 256K，工具侧会直接执行 compact——应先手动压缩再切换；历史上下文包含视频内容时（K3-256k 不支持视频输入）直接切换会报错；`k3-256k`→`k3` 无损（当前版本不影响缓存）。本配置主线恒为 `k3[1m]`、vision 专线为裸 `k3`，部署后的任何链路都不经过 `k3-256k`，不发生此切换；该纪律仅供手动实验 `/model` 时参考。

- 来源：[Claude Code – Model configuration（Context window and auto-compaction：默认阈值、`/autocompact`/旗标/设置键/环境变量的优先级与取值、网关自定义 ID 的三分支窗口语义、网关改写报错文案时不执行恢复）](https://code.claude.com/docs/en/model-config)、[Claude Code – Explore the context window（自动压缩与 `/compact` 同机制、压缩请求继承扩展思考配置）](https://code.claude.com/docs/en/context-window)、[Claude Code – env-vars（`CLAUDE_CODE_AUTO_COMPACT_WINDOW`、`CLAUDE_CODE_MAX_OUTPUT_TOKENS`、`CLAUDE_CODE_MAX_CONTEXT_TOKENS`）](https://code.claude.com/docs/en/env-vars)、[Claude Code – CHANGELOG（v2.1.247：Sonnet 5 默认 ~967K 压缩；压缩失败 3 次熔断）](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)、[Kimi Code – 模型配置（K3/K3-256k 切换纪律、消耗倍率）](https://www.kimi.com/code/docs/kimi-code/models.html)、[Kimi Code – Claude Code 接入（`CLAUDE_CODE_AUTO_COMPACT_WINDOW`/`CLAUDE_CODE_MAX_CONTEXT_TOKENS` 示例）](https://www.kimi.com/code/docs/third-party-tools/claude-code.html)、[Kimi Code – 最新动态（128k 压缩输出上限、BrowseComp 300K 压缩策略）](https://www.kimi.com/code/docs/kimi-code/whats-new.html)、5.0 实测表、7.4.0 表内所列权威研究

### 7.5 证据不截断（A3 / B1）

| 参数 | 值 | 默认 | 含义与理由 |
| --- | --- | --- | --- |
| `env.CLAUDE_CODE_FILE_READ_MAX_OUTPUT_TOKENS` | `65536` | 内置较小值 | 单次文件读取 token 上限。长驱动源文件、长财报文本尽量整读入上下文而非分页。（可继续上调，但单文件占用 1M 窗口比例过大反而挤压推理空间，65536≈250KB 文本是证据完整性与推理余量的平衡点。） |
| `env.BASH_MAX_OUTPUT_LENGTH` | `150000` | 30000 | 命令输出直接进入上下文的字符上限，**150000 为官方硬上限**。构建日志、回测输出超限时转存文件并提供路径，模型可继续检索。 |
| `env.MAX_MCP_OUTPUT_TOKENS` | `50000` | 25000 | MCP 响应 token 上限，长网页/长源码文件不被截断。 |
| `env.TASK_MAX_OUTPUT_LENGTH` | `160000` | 32000 | 后台任务输出经 `TaskOutput` 回读时保留的**字符数**上限，**160000 为官方最大值**。后台子代理（workflow 代理、vision 转录专线）的输出文件是证据链核心载体，设置为最大值。（注意计量单位是字符而非 token；若另设顶层键 `taskOutputMaxChars`，本变量被忽略。） |
| `env.BASH_DEFAULT_TIMEOUT_MS` | `600000` | 120000 | 命令默认超时 10 分钟。 |
| `env.BASH_MAX_TIMEOUT_MS` | `3600000` | 600000 | 模型可请求的命令超时上限 1 小时（bitbake 单包构建、长回测）。超时不等于被终止：到时命令转入后台继续执行。 |

- 来源：[Claude Code – env-vars（各变量条目）](https://code.claude.com/docs/en/env-vars)、[Claude Code – Tools reference（Bash 输出/超时/自动转后台行为）](https://code.claude.com/docs/en/tools-reference)

### 7.6 传输可靠性（A2 / B5）

| 参数 | 值 | 含义与理由 |
| --- | --- | --- |
| `env.API_TIMEOUT_MS` | `3000000` | 单请求总超时 50 分钟（默认仅 10 分钟）。max 档深思考 + 1M 预填充的最坏情况兜底。 |
| `env.API_FORCE_IDLE_TIMEOUT` | `0` | 关闭"流式 5 分钟无字节即中止"的定时器（非 Anthropic 直连时默认开启）。官方明确 `0` 用于块间停顿超过 5 分钟的网关/模型场景——K3 的 `reasoning_effort=max` 深思考停顿被误中断正是"中途截断"的典型来源。 |
| `env.CLAUDE_STREAM_IDLE_TIMEOUT_MS` | `1800000` | 流式空闲看门狗放宽到 30 分钟（显式设置的官方下限为 5 分钟）。保留最终兜底：确认失效的连接在 30 分钟后仍会被切断并进入重试，不会无限挂起。 |
| `env.CLAUDE_ENABLE_BYTE_WATCHDOG` | `1` | **字节级**流式看门狗。它与事件级看门狗互补：事件级监测"是否解析出 SSE 事件"，字节级监测"线路上是否存在任何字节"（含 SSE keep-alive）。v2.1.222 起网关连接（含自定义 `ANTHROPIC_BASE_URL`）已**默认开启**字节级看门狗，本设置是面向旧版的显式保险（旧版网关上它默认关闭）。超时复用 `CLAUDE_STREAM_IDLE_TIMEOUT_MS`（字节级钳制上限恰为 30 分钟，与本配置取值一致）；v2.1.210 起另有专用旋钮 `CLAUDE_BYTE_STREAM_IDLE_TIMEOUT_MS`（10 秒–30 分钟，设置后优先于前者）——本配置不设它，两层看门狗同取 30 分钟，不会误中断 max 档深思考停顿。 |
| `env.CLAUDE_CODE_RETRY_WATCHDOG` | `1` | 无人值守级重试：429/529 容量类错误无限重试（按限额重置时间或最长 5 分钟退避等待），其余瞬时错误默认重试提高到 300 次（约 3 小时退避）。**v2.1.239 起语义细化**：报"支出上限/额度耗尽"的 429（含网关侧定时重置的限额）改为**立即失败**而非无限等待——对无人值守恰是正确行为：额度耗尽时快速失败退出，触发第 12 章处置（切换账号或等待窗口滚动），而非整夜空转。与 Kimi 错误码的对应关系：Kimi 的容量过载/并发超限是 429（看门狗无限重试），而**配额触顶（5 小时窗口/周/月）在 Kimi 侧是 403**——403 不进入看门狗的无限重试路径，按普通错误快速失败，同样收敛到"配额耗尽不空转"的语义（分类表见 12.2）。官方推荐用于 unattended sessions——B5 盘后无人值守的基石。 |
| `env.CLAUDE_CODE_DISABLE_NONSTREAMING_FALLBACK` | `1` | 流式中断时禁止回退为非流式重发——官方指出该回退经代理/网关时可能**重复执行工具**。对金融数据写入、git 操作，重复执行属于正确性事故；禁用后错误统一进入上述重试层。 |
| `env.MCP_TIMEOUT` | `120000` | MCP 服务器**启动连接**超时 2 分钟（默认 30 秒）；本地 stdio 型 MCP（如视觉兜底服务器）首次启动需 npx 现场拉取包。 |
| `env.MCP_TOOL_TIMEOUT` | `1800000` | MCP 工具**执行**超时。关键在第二重语义：HTTP 型 MCP 单请求默认 60 秒超时，将本变量提高到 60000 以上才能提升单请求上限——长公告全文、大仓库结构不再被 60 秒截断（B1/A3）。**知情取舍**：本变量同时是单个 MCP 工具调用的总时长上限（默认约 28 小时），1800000 即总长封顶 30 分钟——对本配置的检索/读页类 MCP 属合理上限；若未来接入分钟级以上的长时 MCP 工具，需同步上调本值与 `CLAUDE_CODE_MCP_TOOL_IDLE_TIMEOUT`（后者不得超过前者）。 |
| `env.CLAUDE_CODE_MCP_TOOL_IDLE_TIMEOUT` | `600000` | MCP 工具执行的**空闲**判定：网络型服务器默认 5 分钟无响应即中止，提高到 10 分钟，容纳慢页面、大仓库的长停顿（官方要求该值不超过 `MCP_TOOL_TIMEOUT`，600000 < 1800000 合规；需 v2.1.187+）。 |
| `env.CLAUDE_CODE_MCP_AUTO_BACKGROUND_MS` | `0` | 关闭"MCP 调用超过 2 分钟自动转后台"（默认 120000；需 v2.1.212+）。理由是**证据顺序**而非仅可见性：取数调用被静默转入后台后，模型可能在数据到达前继续推进论证，事后再补挂结果——这违背 B1"先有证据、后有结论"的时序。关闭后取数调用同步完成、结果按序进入推理链。BMC 的长构建走 Bash 后台任务，不受此项影响。 |

- 来源：[Claude Code – env-vars（各变量条目，含 `CLAUDE_ENABLE_BYTE_WATCHDOG` 复用 `CLAUDE_STREAM_IDLE_TIMEOUT_MS`、`MCP_TOOL_TIMEOUT` 60 秒单请求条款、idle 上限条款）](https://code.claude.com/docs/en/env-vars)

### 7.7 提示词纯净（附带缓存收益）

| 参数 | 值 | 含义与理由 |
| --- | --- | --- |
| `env.CLAUDE_CODE_ATTRIBUTION_HEADER` | `0` | 移除系统提示词开头的客户端版本/指纹归因块：减少与任务无关的提示噪音。缓存收益的官方依据有版本边界：v2.1.181 之前该块在自定义 base URL 连接上含逐请求 token（会破坏网关缓存前缀），之后已移除——在现行版本上本项的主要收益是提示词纯净，缓存仅为旧版本上的附带效果（第 2 章定调不变）。 |

- 来源：[Claude Code – env-vars（`CLAUDE_CODE_ATTRIBUTION_HEADER`）](https://code.claude.com/docs/en/env-vars)

### 7.8 网络适配与检索链路

| 参数 | 值 | 含义与理由 |
| --- | --- | --- |
| `env.CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC` | `1` | 关闭全部非必要外联：后台自动更新、遥测、错误上报、`/feedback`、发行说明、模型发现刷新、可用性检查。在无法访问 Anthropic 的日常环境中，这些请求仅产生超时报错并拖慢会话。手动 `claude update` 不受影响。 |
| `env.DISABLE_ERROR_REPORTING` / `env.DISABLE_TELEMETRY` | `1` / `1` | 显式双重保障；`DISABLE_TELEMETRY` 使特性开关采用代码默认值，行为更确定。 |
| `skipWebFetchPreflight`（顶层） | `true` | **关键项**：WebFetch 默认对每个 URL 先向 `api.anthropic.com` 发起域名安全预检；本环境无法访问 Anthropic，不跳过则 WebFetch 整体不可用（直接破坏 B1 数据链路）。官方明确此项用于 "environments that block traffic to Anthropic"。 |
| `autoUpdatesChannel`（顶层） | `latest` | 手动升级时跟随最新通道，配合主动持续跟踪升级的策略。 |

**检索链路的已知边界**：内置 `WebSearch` 是 Anthropic 服务端工具，第三方网关下大概率不可用（官方明示"需要其他搜索来源时应接入提供搜索工具的 MCP"）。Kimi 官方文档未声明网关透传 `web_search` 服务端工具——本配置将 `WebSearch`/`WebFetch` 保留在 allow 清单（不可用时无副作用），检索需求的正式承载按优先级：① 已部署的搜索/读页类 MCP（如 web-search-prime、web-reader，allow 规则按 7.9 加入）；② Bash `curl`/`python requests` 直接取证（B1 的最强形态，零依赖）；③ WebFetch 泛读（有损抽取，仅用于定位线索）。claude.ai 登录态功能（Artifacts、Remote Control、Routines 等）在纯 API Key 模式下不可用，属预期行为。

- 来源：[Claude Code – env-vars（`CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC` 等）](https://code.claude.com/docs/en/env-vars)、[Claude Code – Settings（`skipWebFetchPreflight`、`autoUpdatesChannel`）](https://code.claude.com/docs/en/settings)、[Claude Code – Tools reference（WebSearch tool behavior）](https://code.claude.com/docs/en/tools-reference)

### 7.9 Windows 专项与自动化权限

| 参数 | 值 | 含义与理由 |
| --- | --- | --- |
| `env.CLAUDE_CODE_USE_POWERSHELL_TOOL` | `1` | 启用原生 PowerShell 工具。官方现行默认：无 Git Bash 的 Windows 自动启用；装有 Git Bash 时对 claude.ai/Console 账户默认开启，对 Bedrock/Agent Platform/Foundry 会话需显式置 1——第三方网关（自定义 base URL + API Key）场景未被官方文档明示覆盖，显式置 1 消除歧义。启用后自动优先选择 `pwsh.exe`，回退 `powershell.exe`，进程级 `-ExecutionPolicy Bypass` 保证 `.ps1` 可执行。Bash 工具保留用于 POSIX 脚本。 |
| `defaultShell`（顶层） | `powershell` | 输入框 `!` 手动执行的命令走 PowerShell。 |
| `permissions.defaultMode` | `bypassPermissions` | 默认全自动。残留提示仅包括：显式 ask 规则（未设置）、标记 `requiresUserInteraction` 的 MCP 工具、`rm -rf /`/`rm -rf ~` 断路器（v2.1.208 起含 `$(...)` 变体）。 |
| `skipDangerousModePermissionPrompt`（顶层） | `true` | 跳过进入 bypass 模式的确认弹窗（用户级设置有效，项目级会被忽略）。 |
| `permissions.allow` | 16 条 | Shift+Tab 切换到 manual/acceptEdits/plan 模式时的免批清单，见下文。 |
| `permissions.deny` | `[]` | deny 在**一切模式（含 bypass）**下生效，与全自动目标冲突，故保持为空。涉及真实资金的实盘接口防线见 10.6（项目级窄 deny 是官方提供的唯一硬闸）。 |

允许列表设计（工具名以 [tools reference](https://code.claude.com/docs/en/tools-reference) 的权威名为准）：

- `Bash`、`PowerShell`：任意命令；`Read`、`Glob`、`Grep`、`LSP`：读取与搜索（放行后**工作目录之外**的读取同样免批——跨盘符数据目录、下载目录等 Windows 常见场景）；`Edit`、`Write`、`NotebookEdit`：全部文件修改；`WebFetch`、`WebSearch`：网页抓取/搜索；`Agent`、`Skill`、`Monitor`：子代理、技能、后台监视；`EnterWorktree`、`Workflow`：worktree 进入与动态工作流编排。
- **allow 清单的适用边界（版本敏感，已按现行官方文档改写）**：workflow/子代理的权限模式按通用子代理规则确定——主会话处于 `bypassPermissions`/`acceptEdits`/auto 时，子代理**继承同一模式**（早期官方文档中"workflow 子代理强制 acceptEdits、不继承主会话 bypass"的表述已被移除，现行 workflows 文档明确子代理权限模式按通用规则选取）。因此在 bypass 常驻的本配置下，workflow 代理同样在 bypass 中运行，allow 清单对它们不构成约束；清单的真实价值在于：Shift+Tab 切到 manual/acceptEdits/plan 模式时的免批，以及 headless `-p` 以非 bypass 模式启动（如 `--permission-mode dontAsk`）时的规则供给。**安全含义需知悉**：无人值守 workflow 的代理权限与主会话同级——控制面应放在 deny 规则（一切模式生效）与工作目录隔离上，而不是 allowlist。新部署的 MCP 若需在非 bypass 模式下可用，仍应将 `mcp__<server>` 加入本清单（如 `"mcp__web-search-prime"`、`"mcp__web-reader"`）。
- **有意不放行** `ExitPlanMode`：计划审批保留人工闸门——BMC 级大改动先出计划、经确认后执行，是 A4 的低成本高收益环节。
- Shift+Tab 循环为 `manual → acceptEdits → plan → bypassPermissions`（bypass 因 defaultMode 声明而进入循环）；auto 模式依赖 Anthropic 侧分类器与特定 Claude 模型，Kimi 网关下不可用、不会出现在循环中。

- 来源：[Claude Code – Tools reference（PowerShell tool、权威工具名）](https://code.claude.com/docs/en/tools-reference)、[Claude Code – Permissions（规则语法、deny 全模式生效、断路器）](https://code.claude.com/docs/en/permissions)、[Claude Code – Permission modes（模式循环与 bypass 进入循环条件、auto 可用性要求）](https://code.claude.com/docs/en/permission-modes)、[Claude Code – Settings（Permission settings）](https://code.claude.com/docs/en/settings)

### 7.10 大规模并行与长任务编排（A5）

| 参数 | 值 | 含义与理由 |
| --- | --- | --- |
| `workflowSizeGuideline`（顶层） | `unrestricted` | 动态 workflow 的规模引导（特性需 v2.1.202+，设置键需 v2.1.219+）。**默认 `medium` 的官方语义是引导 Claude 把 workflow 写在 10 个代理以内**——直接压制 A5 全仓审计、B4 多角度核查所需的规模；`unrestricted` 即"无引导、按任务定规模"，与 workflow 单 run 1000 代理的硬上限对齐。官方明确 guideline 只是发给 Claude 的建议而非强制上限。设置文件提供值时优先于 `/config` 行（该行随之隐藏），防止会话内被误改。 |
| `env.CLAUDE_CODE_ENABLE_TODO_TOOLS` | `1` | 任务清单工具（TaskCreate/TaskGet/TaskUpdate/TaskList）显式锁定。v2.1.233 起较新模型默认**不再提供**这些工具（官方以模型判定为准）；BMC 级长任务、批量迁移依赖任务清单做进度跟踪与断点续查，显式置 1 保证任何版本判定变化下工具都在。 |
| `env.CLAUDE_ASYNC_AGENT_STALL_TIMEOUT_MS` | `3600000` | 后台子代理"失速"判定从默认 10 分钟放宽到 1 小时——子代理内部单条长构建/长回测命令期间可能没有流式进度事件，默认值会将其误判为失败（A2）。超过 1 小时的构建应改用 `run_in_background` 的后台命令而非阻塞式子代理。 |
| `env.CLAUDE_CODE_FORK_SUBAGENT` | `1` | 启用 fork 型子代理：**继承完整对话上下文**开分支，而非空白起步。金融场景用它并行核查对立假设（多/空论证各 fork 一支，证据不丢失）；工程场景用它在不污染主线的情况下试探激进方案。**v2.1.232 起 fork 在交互会话默认启用，但 `claude -p`/SDK 仍默认关闭**——本配置的无人值守轨道（10.5）全部经 `-p` 启动，置 1 是 headless 下 fork 可用的必要开关。 |
| `env.CLAUDE_CODE_PRINT_BG_WAIT_CEILING_MS` | `0` | headless（`claude -p`）模式默认仅等待后台子代理与 workflow **10 分钟**，超时后"remaining background tasks are terminated and the process exits"——即无人值守的深度 workflow 会在 10 分钟被终止，这正是 B5 场景最隐蔽的截断源。官方明确 `0` = 无限等待。交互式会话不受此变量影响。（需 v2.1.182+） |
| `env.CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS` | `1` | 启用实验性 agent teams（主管+队友多实例协作）。队友模型无论按别名解析还是继承主会话，均落在 K3（全部别名位已对齐）；**v2.1.234 起官方移除 `/config` 的 Default teammate model 选项，队友恒用 leader 的模型**——主线单旗舰的保障进一步坐实，连可选的偏离入口都已关闭。实验性特性，异常时删除此行即可。 |

子代理规模的官方语义（v2.1.224 起）：单会话**总量**上限（原默认 200）已被官方移除；现行约束为**并发**运行数（`CLAUDE_CODE_MAX_CONCURRENT_SUBAGENTS`，默认 20，v2.1.217+；**ultracode 激活的会话豁免于该上限**）、**嵌套深度**（默认 3）与 workflow 单 run 1000 代理/16 并发。对 BMC 全仓审计这意味着"超出并发的 spawn 排队等待，而非被拒绝"。两个现行约束保持默认的理由见第 8 章——**对 Kimi 侧有额外的实锤**：官方错误参考明确存在"短时间内发出的请求太多，超出账户限制"的 429（每 5 小时滚动频率窗口，见第 12 章），超发并发只会把 429 打向网关并触发退避循环；Kimi Code 自身也提供 `KIMI_CODE_AGENT_SWARM_MAX_CONCURRENCY` 一类的初始并发限制以规避供应商限流——大规模并行的正确形态是"总量排队"而非"并发堆高"。

- 来源：[Claude Code – Workflows（size guideline 表、单 run 上限）](https://code.claude.com/docs/en/workflows)、[Claude Code – env-vars（`CLAUDE_CODE_MAX_CONCURRENT_SUBAGENTS`、`CLAUDE_ASYNC_AGENT_STALL_TIMEOUT_MS`、`CLAUDE_CODE_FORK_SUBAGENT`、`CLAUDE_CODE_ENABLE_TODO_TOOLS`、`CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS`）](https://code.claude.com/docs/en/env-vars)、[Claude Code – Settings（`workflowSizeGuideline`）](https://code.claude.com/docs/en/settings)、[Kimi Code – 错误参考（并发请求过多 429）](https://www.kimi.com/code/docs/kimi-code/error-reference.html)、[Kimi Code – 会员权益（5 小时滚动频率窗口）](https://www.kimi.com/code/docs/kimi-code/membership.html)、[Kimi Code – 最新动态（AGENT_SWARM_MAX_CONCURRENCY）](https://www.kimi.com/code/docs/kimi-code/whats-new.html)

### 7.11 留痕与其他

| 参数 | 值 | 含义与理由 |
| --- | --- | --- |
| `cleanupPeriodDays` | `365` | 会话转录保留一年（默认 30 天清理）。分析会话 = 审计底稿（B5）；配合 `/resume` 回溯。可按需继续加大。 |
| `attribution.commit`/`attribution.pr` | `""`/`""` | 关闭提交/PR 中的 Claude 署名（新版 `attribution` 键取代已废弃的 `includeCoAuthoredBy`）。 |
| `language` | `chinese-simplified` | 默认中文回复（亦影响自动会话标题语言）。 |
| `$schema` | schemastore 地址 | 编辑器内自动补全与校验。 |
| `minimumVersion`（顶层） | `2.1.246` | **真实语义：仅约束更新通道**——后台自动更新与 `claude update` 不得安装低于此值的版本，配合 `autoUpdatesChannel: "latest"` 防止切换发布通道时降级到凭证隔离安全修复（v2.1.246：遥测/指标请求不再向第三方网关泄露已配置的 API key）之前的旧版。注意它**不是启动门槛**：官方明确"该键只约束更新"；能让低版本拒绝启动的 `requiredMinimumVersion` 仅 managed 作用域生效（写在用户级/项目级会被静默忽略）。因此 17.4 版本门槛表的执行层面仍是"备查 + 升级 SOP（第 13 章）"，运行期核对靠第 15 章第 1 条的 `claude --version`。 |

- 来源：[Claude Code – Settings（`cleanupPeriodDays`、Attribution settings、`language`、`$schema`、`minimumVersion`）](https://code.claude.com/docs/en/settings)

### 7.12 终端渲染（fullscreen）与完成通知

| 参数 | 值 | 含义与理由 |
| --- | --- | --- |
| `tui`（顶层） | `fullscreen` | 全屏 alt-screen 渲染器（research preview；`/tui fullscreen` / `/tui default` 随时切换，会话完整保留）。对本配置三项实质收益：① **内存恒定**——只渲染可见消息，1M 窗口超长会话不随转录增长吃内存；② **压缩后全量回滚**——auto-compact 之后 `Ctrl+Home` 仍可滚回会话开头查看原始证据（官方明确 fullscreen scrollback 跨多次压缩保留全部早期消息），直接缓解 9.4 落盘规程要对冲的"压缩丢证据"压力；③ **大输出可交互**——折叠的工具输出点击展开（`BASH_MAX_OUTPUT_LENGTH=150000` 的大段结果可优雅回看）、菜单/权限对话框可鼠标点选、`Ctrl+O` 进入 transcript 模式后 `/` 全文检索、`{`/`}` 逐 prompt 跳转、`[` 写回终端原生 scrollback、`v` 甩进外部编辑器。 |
| `env.CLAUDE_CODE_ALT_SCREEN_FULL_REPAINT` | `1` | Windows 专属配套：Windows Terminal 等 ConPTY 主机在增量重绘下会残留错位碎片（官方排障条目"Stale or misplaced text on screen"），修法即全帧重绘。官方已对后台会话与 agent view 在 Windows 上自动启用，**交互式全屏会话需显式设置**。若全屏滚动出现整块空白，可再叠加 `CLAUDE_CODE_DISABLE_VIRTUAL_SCROLL=1`。 |
| `preferredNotifChannel`（顶层） | `terminal_bell` | 完成通知闭环。官方默认仅 iTerm2/Ghostty/Kitty 发桌面通知，**Windows Terminal 默认零通知**——无人值守长任务（10.5 双轨）完成后终端静默无声。设为 `terminal_bell` 后，任务完成或等待输入时终端响铃；配合 Windows Terminal 设置 `bellStyle`（声音/任务栏闪烁/窗口注意）形成完整提醒链。B5"持续复跑"的人机协议：听到铃声 = 产物已落盘待验收。 |

长会话操作速记（fullscreen 模式）：`Ctrl+O` 进 transcript 检索，`/focus` 切安静视图（只显示最后 prompt + 工具调用一行摘要 + 最终响应），滚轮速度 `/scroll-speed` 可调（写入 `CLAUDE_CODE_SCROLL_SPEED`），离开数分钟后回终端自动显示一行会话回顾（`awaySummaryEnabled`，默认开）。agent view 中 attach 的后台会话恒以 fullscreen 渲染，不受本键影响。

- 来源：[Claude Code – Fullscreen rendering（收益、ConPTY 全帧重绘、transcript 检索、压缩后回滚）](https://code.claude.com/docs/en/fullscreen)、[Claude Code – Terminal configuration（terminal bell / `preferredNotifChannel`）](https://code.claude.com/docs/en/terminal-config)、[Claude Code – env-vars（`CLAUDE_CODE_ALT_SCREEN_FULL_REPAINT`、`CLAUDE_CODE_SCROLL_SPEED`、`CLAUDE_CODE_DISABLE_VIRTUAL_SCROLL`）](https://code.claude.com/docs/en/env-vars)、[Claude Code – Settings（`tui`、`awaySummaryEnabled`）](https://code.claude.com/docs/en/settings)

### 7.13 多模态双通道：主线原生直读 + vision 转录专线（C1 / C2）

多模态不是一个参数，而是一条**分流规则**。K3 旗舰原生具备视觉（MoonViT-V2，支持图片与视频输入）——这是与"旗舰纯文本"配置（DeepSeek/GLM 主线）的根本差异：**主线收到图片不会报错**。多模态链路因此设计为双通道（部署物为 [`agents/vision.md`](./agents/vision.md)，用法与作业规程见第 11 章）：

| 通道 | 承载 | 适用 | 依据 |
| --- | --- | --- | --- |
| **主线直读** | `k3[1m]` 原生视觉 | 单张或少量（≤3 张）目标明确的图片：一张报错截图、一张 K 线图、一份 UI 对照图。零路由开销、旗舰推理直接作用于像素、图片进入主线上下文后可被后续多轮持续引用 | [MoonshotAI/Kimi-K3（原生视觉）](https://github.com/MoonshotAI/Kimi-K3)、实测 5.0 第 7 条（Anthropic image block + 精确 OCR） |
| **vision 转录专线** | 子代理 frontmatter `model: k3`（裸名，与主线同旗舰同 1M 窗口） | 批量帧序列（视频抽帧取证）、密集小字（日志/表格/扫描件）、多页文档逐页读、任何"图片数量多但结论是文本"的任务。子代理在独立窗口消化图片洪流，回传规范化文本证据 | [Kimi Code – 模型配置（k3 支持图片/视频）](https://www.kimi.com/code/docs/kimi-code/models.html)、[Sub-agents – Choose a model](https://code.claude.com/docs/en/sub-agents) |

| 环节 | 机制 | 依据 |
| --- | --- | --- |
| 模型指定 | frontmatter `model: k3`（**必须裸名**：`k3[1m]` 在 frontmatter/API 场景被服务端 401 拒绝——官方错误参考 + 实测 5.0 第 8 条）。选裸 `k3` 而非 `k3-256k` 的决定性理由见 7.4.1（客户端对未解析裸名 ID 按 `CLAUDE_CODE_MAX_CONTEXT_TOKENS` 设定假设窗口：裸 `k3` 假设值 1M = 真实上限，压缩安全网完整生效；`k3-256k` 会被误按 1M 管理、超 256K 硬失败）。裸 `k3` 支持图片输入，与主线同模型同效果（官方口径） | [Kimi Code – 错误参考（model id does not exist）](https://www.kimi.com/code/docs/kimi-code/error-reference.html)、[Kimi Code – 模型配置](https://www.kimi.com/code/docs/kimi-code/models.html)、[Model configuration – Correct the window for a gateway or custom model ID](https://code.claude.com/docs/en/model-config) |
| 路由优先级 | 子代理模型解析顺序（v2.1.251 起）：调用时指定的模型 > 子代理定义的 `model` frontmatter > `CLAUDE_CODE_SUBAGENT_MODEL`（仅作"未另行指定"时的默认值）> 继承主会话。本配置不设该变量，vision 的 frontmatter 稳定命中裸 `k3`；v2.1.257+ 另有 `CLAUDE_CODE_SUBAGENT_MODEL_FORCE=1` 可压过 frontmatter——**不得设置**（第 8 章） | [Sub-agents – Choose a model / Run every subagent on one model](https://code.claude.com/docs/en/sub-agents)、[CHANGELOG v2.1.251](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md) |
| 多模态进入 | 全部视觉证据收敛为 **image 内容块**这一条通道（实测走通）：图片——Read 直读；视频——ffmpeg 抽帧为图片再读（fps 按需：通览 1fps、抓闪现报错 2fps/关键帧）；PDF/扫描件——先转图片（`pdftoppm`）再逐页读。PDF 的 Anthropic document 块在 Kimi 端点的支持未见官方声明，本配置统一走"转图"路径规避不确定性 | 实测 5.0 第 7 条、[Tools reference – Read](https://code.claude.com/docs/en/tools-reference) |
| 客户端压缩 | Claude Code 发送前对大图缩放重编码；服务端还会按自身规则换算 token（官方未公布 Kimi 侧换算细则）。官方建议错过像素级细节时先裁剪感兴趣区域再读——vision 子代理系统提示已内置裁剪规程 | [Tools reference – Read（Images）](https://code.claude.com/docs/en/tools-reference) |
| 深度与窗口 | 子代理 effort 默认继承会话（xhigh 经映射即 `reasoning_effort=max`）；thinking 配置继承（v2.1.198+）；窗口按 `CLAUDE_CODE_MAX_CONTEXT_TOKENS=1048576` 正确核算（裸 `k3` 真实上限即 1M）；回传上限 `TASK_MAX_OUTPUT_LENGTH=160000` | [Sub-agents（effort/thinking 继承）](https://code.claude.com/docs/en/sub-agents)、7.4.1、7.5 |
| 观测 | `/tasks` 与代理详情对话框显示每个子代理实际运行的模型与 effort（v2.1.243+）——验证 vision 走的是裸 `k3` 的直接手段 | [CHANGELOG v2.1.243](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md) |

**为什么不是别的方案**（设计决策记录）：

- ~~一切图片都走子代理~~（GLM/DS 形态）：那是"旗舰不能看图"逼出来的架构。K3 能看且看得准（实测逐字 OCR），少量图片绕道子代理徒增延迟与转录损耗——单图直读是旗舰原生能力的正当使用。但**批量**场景直读主线会同时挤占上下文（图片 token 计入 1M 窗口）与请求体预算（base64 膨胀），且结论形态本就是文本——专线转录严格占优。分界线"≤3 张、目标明确"即两条通道成本曲线的交点附近，写入各项目 CLAUDE.md 模板。
- ~~图片粘贴进主会话输入框~~：技术上可行（K3 接受图片，不报错），但粘贴图不走 Read 工具的规范化通道、无法被 vision 规程约束、且永久占据主线上下文。规程统一为**文件落盘**（`docs/evidence/`）后按分界线选择通道——文件路径同时是证据的可引用坐标（B1 溯源）。
- ~~`kimi-for-coding`（K2.8，同样多模态）挂子代理~~：引入第二家模型违反 C2 与 A6（模型切换即行为漂移）；裸 `k3` 与主线是同一模型，转录质量与主线同源。
- ~~`k3-256k` 挂 vision（初版方案，已废止）~~：`k3-256k` 与 K3 同模型、消耗减半（官方口径），但客户端无法解析该裸名 ID 的真实窗口——`CLAUDE_CODE_MAX_CONTEXT_TOKENS=1048576` 会直接把它按 1M 假设（7.4.1 三分支语义），超出 256K 真实上限后以 token 超限硬失败而非压缩；且 `max_tokens=131072` 仅在裸 `k3` 上实测过（5.0 第 4 条）。按"成本不纳入决策、可靠性优先"的总原则，专线改用裸 `k3`（2026-09-16 修订）。
- ~~`/model` 手动切换读图~~：主线本就能读图，无需切换；任何模型切换都是最高级别行为漂移（第 14 章）。

**主会话纪律（必须写入各项目 CLAUDE.md，模板见 9.2/10.3）**：视觉证据一律以文件落盘；少量目标明确的图片可让主线直接 Read，批量/取证/密集转录任务点名 vision 子代理（`@vision`）；图片不粘贴进对话。

- 来源：见表内逐行标注

## 8. 有意不设置的参数及原因

| 参数 | 决定 | 原因 |
| --- | --- | --- |
| `fallbackModel` | **绝不设置** | 过载时自动切换模型 = 静默降级出活，违反 A6/B1。策略：`CLAUDE_CODE_RETRY_WATCHDOG` 持续重试同一模型，无法等待时按第 12 章处置。来源：[Model configuration – Fallback model chains](https://code.claude.com/docs/en/model-config) |
| `CLAUDE_CODE_SUBAGENT_MODEL` | 不设置 | v2.1.251 起该变量仅充当"未另行指定模型的子代理/队友/workflow 代理"的**默认值**——子代理定义的 `model` frontmatter 与调用时指定的模型均优先于它（v2.1.251 之前相反：它覆盖两者；v2.1.257+ 需强制时用专用开关 `CLAUDE_CODE_SUBAGENT_MODEL_FORCE=1`，本配置不使用）。不设时常规子代理默认 `inherit` 继承主会话的 K3 (1M)，vision 子代理按 frontmatter 命中裸 `k3`——"子代理全旗舰"已达成，且与 Kimi 官方接入示例（该示例设置此变量为 `k3[1m]`）保持最小差异；本配置锚定的最低版本区间（2.1.246–2.1.250）内旧语义仍存，不设它同时消除该窗口期的 frontmatter 被覆盖风险。来源：[Sub-agents – Choose a model / Run every subagent on one model](https://code.claude.com/docs/en/sub-agents)、[CHANGELOG v2.1.251](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)、[Kimi Code – Claude Code 接入](https://www.kimi.com/code/docs/third-party-tools/claude-code.html) |
| `ANTHROPIC_MODEL` | 不设置 | 官方示例用它锁定主模型，但会屏蔽 `/model` 查询与切换；四位别名全覆盖已达到"任何路径都是 K3"的同等效果且保留交互能力。来源：[Kimi Code – Claude Code 接入](https://www.kimi.com/code/docs/third-party-tools/claude-code.html) |
| `CLAUDE_CODE_EXTRA_BODY`（如注入 `temperature`/`top_p`） | 不设置 | 不注入：① 网关对自定义组合的处理无官方保证，Kimi 端点对未知参数取值存在直接 400 的先例（effort 未知值即 400），注入即引入未定义行为；② K3 官方基准的标定工况为 `temperature=1.0`（单步任务 top_p=0.95、agentic 任务 top_p=1.0，厂商脚注明示）——偏离标定工况无任何收益证据；③ **数值的确定性由"工具算数"保证**（10.2 铁律：所有计算落到代码执行），不依赖采样温度。来源：[MoonshotAI/Kimi-K3（Footnotes 标定工况）](https://github.com/MoonshotAI/Kimi-K3)、[Claude Code – env-vars（`CLAUDE_CODE_EXTRA_BODY`）](https://code.claude.com/docs/en/env-vars) |
| `MAX_THINKING_TOKENS` | 不设置 | 设 0 会关闭思考——对 K3 即触发"路由到 K2.8 无思考版"的降级陷阱（7.3 红线）；非零值属"固定思考预算"模型的机制，K3 思考深度由 `reasoning_effort` 控制且已锁定。来源：[Claude Code – env-vars](https://code.claude.com/docs/en/env-vars) |
| `_SUPPORTED_CAPABILITIES` 中的 `adaptive_thinking` / `interleaved_thinking` | 有意不声明 | K3 的思考机制为恒开 thinking + effort 三档，无 adaptive/interleaved 的能力证据；Kimi 端点对无法识别的取值直接 400（effort 先例），按"实测确认的才声明"原则保守声明（7.2）。未声明仅损失客户端侧开关，不引入请求失败风险。来源：5.0 实测表、[Kimi Code – 模型配置](https://www.kimi.com/code/docs/kimi-code/models.html) |
| `DISABLE_PROMPT_CACHING`（及分模型变体） | 绝不设置 | 缓存是无损机制（第 2 章），关闭无任何收益。来源：[Prompt caching](https://code.claude.com/docs/en/prompt-caching) |
| `ENABLE_PROMPT_CACHING_1H` / `FORCE_PROMPT_CACHING_5M` | 不设置 | Anthropic 官方缓存 TTL 计费选项，Kimi 隐式缓存不适用。来源：[Prompt caching – Cache lifetime](https://code.claude.com/docs/en/prompt-caching) |
| `ENABLE_TOOL_SEARCH` | 保持默认 | 非第一方 host 默认预载全部 MCP 工具（tool search 需网关支持 `tool_reference`，Kimi 未声明支持，强制开启会导致请求失败）。来源：[env-vars（`ENABLE_TOOL_SEARCH`）](https://code.claude.com/docs/en/env-vars) |
| `CLAUDE_CODE_DISABLE_EXPERIMENTAL_BETAS` | 默认不设 | 仅当端点对 `anthropic-beta` 头报错时临时置 1。来源：[env-vars](https://code.claude.com/docs/en/env-vars) |
| `DISABLE_AUTO_COMPACT` / `DISABLE_COMPACT` | 不设置 | 800K 水位的自动压缩是避免请求直接失败的最后防线；损失由"关键证据落盘"规程（9.4/10.5）对冲。来源：[env-vars](https://code.claude.com/docs/en/env-vars) |
| `CLAUDE_AUTOCOMPACT_PCT_OVERRIDE` | 不设置 | 按百分比提前触发压缩（只能降低不能提高）。压缩触发点已由 `CLAUDE_CODE_AUTO_COMPACT_WINDOW=800000` 以绝对 token 数直接表达（7.4），再叠加百分比旋钮会使实际触发点变成两数乘积、难以推算与验证——单旋钮原则。来源：[env-vars（`CLAUDE_AUTOCOMPACT_PCT_OVERRIDE`）](https://code.claude.com/docs/en/env-vars) |
| `CLAUDE_CODE_DISABLE_1M_CONTEXT` | 绝不设置 | 会按 200K 窗口处理。来源：[env-vars](https://code.claude.com/docs/en/env-vars) |
| `ANTHROPIC_AUTH_TOKEN` | **必须清除** | Kimi 使用 `ANTHROPIC_API_KEY`（x-api-key，实测通过）；从 Z.AI 配置切换而来的机器上残留的 `ANTHROPIC_AUTH_TOKEN`（Bearer 认证）会造成双认证冲突。来源：[Claude Code – env-vars](https://code.claude.com/docs/en/env-vars)、7.1 |
| `CLAUDE_CODE_ENABLE_FINE_GRAINED_TOOL_STREAMING=1` | 可选未启用 | 网关下细粒度工具流默认关闭，仅影响"大段写入的实时观感"，不影响结果；启用属观感优化，若遇工具参数解析错误须移除。来源：[env-vars](https://code.claude.com/docs/en/env-vars) |
| `CLAUDE_CODE_MAX_TOOL_USE_CONCURRENCY` | 保持默认 10 | 可提高并行度，但 Kimi 侧存在每 5 小时滚动频率窗口的并发限制（第 12 章；官方错误参考"并发请求过多"429 条目），超发只会产生 429-重试循环。需要更高吞吐时应使用多会话/多账号（第 12 章）。来源：[env-vars（`CLAUDE_CODE_MAX_TOOL_USE_CONCURRENCY`）](https://code.claude.com/docs/en/env-vars)、[Kimi Code – 错误参考](https://www.kimi.com/code/docs/kimi-code/error-reference.html) |
| `sandbox.*` | 不设置 | 沙箱仅支持 macOS/Linux/WSL2；Windows 原生 PowerShell 工具不支持沙箱。来源：[Settings – Sandbox settings](https://code.claude.com/docs/en/settings)、[Tools reference – PowerShell preview limitations](https://code.claude.com/docs/en/tools-reference) |
| `fastMode` / `fastModePerSessionOptIn` | 不设置 | Fast mode 是 Anthropic 原生 Opus 的加速计费特性，走 Kimi 网关无对应通道；且本配置定调"速度不纳入决策考量"（Kimi 侧的对应物 `kimi-for-coding-highspeed` 同因不采用——3 倍消耗换 5–6 倍输出速度是速度取向的产物，且属另一模型位），双不沾。来源：[Fast mode](https://code.claude.com/docs/en/fast-mode)、[Kimi Code – 模型配置](https://www.kimi.com/code/docs/kimi-code/models.html) |
| `verbose` | 不设置 | 显示层完整工具输出。"证据不截断"由 7.5 的传输层上限保证；显示层 fullscreen 已提供折叠 + 点击展开，开 verbose 只会把超长输出整段刷进视口，反而降低可读性。来源：[Settings – `verbose`](https://code.claude.com/docs/en/settings) |
| `askUserQuestionTimeout`（及 `CLAUDE_AFK_TIMEOUT_MS`） | 不设置 | AskUserQuestion 对话框空闲超时"自动继续"（默认 `never` 等待作答）。自动继续与 10.6"人工闸门"哲学冲突；headless（`-p`）下问题本就走非交互路径，不存在挂等场景。来源：[Settings – `askUserQuestionTimeout`](https://code.claude.com/docs/en/settings) |
| `crossSessionInbound` | 保持默认 `hold` | 跨会话入站消息策略（`accept`/`hold`/`refuse` 阶梯，v2.1.224+）。默认 hold 使 bypass 会话收到的入站消息被扣住待批准——这是防提示注入的安全设计；单人多会话确需互通时再显式设 `accept`，属未来决策点。来源：[Settings – 跨会话消息入站策略](https://code.claude.com/docs/en/settings) |
| `keybindingFlavor` | 不设置 | readline 风格键位。纯个人键位偏好，与场景需求无关。来源：[CHANGELOG v2.1.238](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md) |
| `voice` / channels（`channelsEnabled` 等） | 不设置 | 语音听写需 claude.ai 账号；channels 属 claude.ai Team/Enterprise 管控体系——网关 + API Key 认证下均不可用。来源：[Voice dictation](https://code.claude.com/docs/en/voice-dictation)、[Channels](https://code.claude.com/docs/en/channels) |
| `CLAUDE_CODE_MAX_CONCURRENT_SUBAGENTS` / `CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH` | 保持默认 20 / 3 | v2.1.217+ 起现行的子代理约束（见 7.10 语义说明）。调高并发与 `CLAUDE_CODE_MAX_TOOL_USE_CONCURRENCY`（保持 10）同源：Kimi 侧 5 小时滚动频率窗口（第 12 章）约束总吞吐，超发只产生 429-重试循环；workflow runtime 自身并发上限 16，默认 20 已非瓶颈——大规模审计的正确形态是"总量排队"而非"并发堆高"。来源：[env-vars – 两变量条目](https://code.claude.com/docs/en/env-vars) |
| `CLAUDE_CODE_GOAL_CHECKIN_MINUTES` | 不设置 | `/goal` 长任务的自动 check-in 间隔（默认 30 分钟起逐步退避；v2.1.234+）。当前作业手册未采用 `/goal` 工作流；若日后启用且不欲 check-in 消息注入上下文，设 `0` 关闭。来源：[env-vars – `CLAUDE_CODE_GOAL_CHECKIN_MINUTES`](https://code.claude.com/docs/en/env-vars) |
| `ANTHROPIC_DEFAULT_MODEL` | 不设置 | v2.1.236+ 的"新会话默认模型"变量。与既有顶层 `model: "opus"` 等效，无迁移收益。来源：[env-vars – `ANTHROPIC_DEFAULT_MODEL`](https://code.claude.com/docs/en/env-vars) |
| `CLAUDE_CODE_WORKFLOW_PREFIX_STAGGER_MS` | 保持默认 5000 | workflow fan-out 的缓存前缀错峰：同前缀的兄弟代理等待首代理响应开始后一起放行，读共享缓存前缀而非各自冷处理（v2.1.229+）。对 Kimi 隐式缓存同样适用，保留默认即免费收益。来源：[Workflows – Prompt caching in a fan-out](https://code.claude.com/docs/en/workflows) |
| User-Agent 相关任何变量 | **绝不设置** | Kimi 官方明示"篡改客户端标识（User-Agent）将被视为违规，可能导致会员权益暂停"。来源：[Kimi Code – 概览](https://www.kimi.com/code/docs/) |
| `CLAUDE_CODE_RESTRICTED=1`（`--restricted` 启动旗标） | **绝不使用** | v2.1.248 新增的受限模式：移除命令/代码执行类内置工具与 WebFetch、文件工具禁出工作目录、**拒绝 bypassPermissions、忽略用户级/项目级/本地 settings 文件**——与"无人值守全自动 + 用户级配置"的整套架构正相反。属给受限环境管理员提供的锁定开关，非本场景工具。来源：[CHANGELOG v2.1.248](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md) |

---

# 第三部分：作业手册

## 9. 场景 ①：BMC 级超大代码体系开发

### 9.1 工作区形态

推荐"主仓启动 + 多目录挂载"：在主工作仓（如 openbmc 或自定义元层仓库）启动 `claude`，用 `/add-dir` 挂载 u-boot、kernel、webui 等兄弟仓库。本配置已开启 `CLAUDE_CODE_ADDITIONAL_DIRECTORIES_CLAUDE_MD=1`，各仓库自身的 CLAUDE.md/规则会一并载入（A1/A4）。超大单树（monorepo）参见官方专文：[Set up Claude Code in a monorepo or large codebase](https://code.claude.com/docs/en/large-codebases)（嵌套 CLAUDE.md、稀疏 worktree、按包技能）。

### 9.2 根 CLAUDE.md 模板（置于主仓根目录，按实际项目改写）

模板遵循官方写法要求：单文件控制在 200 行内、规则具体到可验证（"执行 `<测试命令>`"而非"做好测试"）、按主题拆分时使用 `.claude/rules/*.md` 或 `@path` 导入。规则是"上下文"而非强制执行——需硬拦截的动作应使用 deny 规则或 PreToolUse hook（见 10.6）。

- 来源：[Claude Code – Memory（<200 行、具体可验证、rules 目录、context not enforced configuration）](https://code.claude.com/docs/en/memory)

```markdown
# 工程语境
- 本工作区为 BMC 固件全栈：Yocto/bitbake 元层、u-boot、Linux 内核（I2C/IPMB/KCS/MCTP 驱动）、
  phosphor-* D-Bus 服务、bmcweb（Redfish）、webui-vue 前端。
- 目标机型/SoC：<填写>；交叉工具链：<填写>；构建入口：<bitbake 命令/脚本>。

# 硬性约束（违反即返工）
1. 协议字段、寄存器位、D-Bus 接口签名：必须先读到对应规范文本或现有代码定义再落笔，
   禁止凭记忆书写。Redfish 资源以 DSP0266 及 bmcweb 现有 schema 为准；IPMI 命令以规范文档
   和现有 handler 为准。引用时注明文件路径与行号。
2. 内存与实时性：守护进程禁止在热路径引入动态分配与阻塞 I/O；新增依赖必须评估镜像体积。
3. 禁改区：vendor blob、签名/安全启动密钥与流程、许可证头。涉及许可证边界的复制必须停下说明。
4. 每次代码改动后必须依次执行：<格式化命令>、<静态检查命令>、<单元测试命令>；
   跨组件改动必须完成 <QEMU/仿真运行命令> 冒烟。任何一步失败不得宣布完成。
5. commit 边界：一个逻辑变更一个 commit；禁止顺手重构无关代码。

# 视觉证据规程（双通道分流）
- 一切视觉证据（报错/崩溃截图、原理图、时序图、面板照片、录屏、PDF 规范）先落盘到
  docs/evidence/，对话中只出现文件路径；图片不粘贴进输入框。
- 分流规则：单张或少量（≤3 张）目标明确的图片（一张报错截图、一张图纸）——直接用 Read
  读取，主线模型（K3）原生具备视觉能力；批量与取证任务（视频抽帧序列、多页 PDF/扫描件、
  密集小字表格、需要逐图精确转录的对比）——点名 vision 子代理：
  "用 vision 分析 <路径或目录>：<要回答的问题>"（视频自动抽帧、PDF 自动转图分页）。
- vision 回传的逐字转录进入结论时注明「文件路径 + vision 转录 + 获取时间」，按长任务规程落盘。
- 视觉估读只用于形态判断；进入计算与结论的数值必须回到代码/数据接口取证。

# 长任务规程
- 阶段性结论（架构判断、影响面清单、风险点）写入 docs/worklog/<日期>-<主题>.md 后再继续，
  确保上下文压缩后证据仍在磁盘上。
- 小时级构建用后台方式运行，期间继续推进可并行的工作。
- 上下文压缩（compact）时必须完整保留：硬性约束全文、当前阶段目标与未完成事项清单、
  已修改文件清单及各自的验证命令、尚未验证通过的失败项与报错原文。

# 检索优先级
上游/开源参考：优先用已部署的仓库理解 MCP 读 GitHub 仓库结构与源码；网页文档用读页 MCP
或 Bash curl 取全文；两者均未部署时直接 git clone 到临时目录读源码。
```

### 9.3 任务下达范式

每个任务的下达遵循四要素结构——**Goal（要做成什么）/ Context（涉及哪些文件、报错、文档）/ Constraints（工程约束）/ Done when（怎样算完成）**。长期性规则进 CLAUDE.md，临时性指令进提示词，二者不混放。K3 的官方定位（"在极少人工监督下持续完成长时间工程任务……Kernel 优化、GPU 编译器、芯片设计"）意味着长程任务可直接下达完整边界，无需拆碎 spoon-feed；但仍应保留 9.5 的计划先行闸门。

### 9.4 证据落盘与上下文生命周期规程（两场景通用）

多日任务终会触顶。总原则（与 7.4.0 定调对应）：**证据的持久层在文件系统，不在对话窗口**——压缩摘要会替换对话史，但磁盘文件永久保留，模型可随时重读。在此之上，上下文按生命周期主动管理，而非被动等 800K 水位：

1. **阶段结论必须先落盘**（worklog、影响面清单、决策记录、报告）：这是一切压缩/清空操作无损的前提。CLAUDE.md 模板中的"压缩保留项"指令（9.2/10.3）是官方支持的定制通道（"Customize compaction behavior in CLAUDE.md"），作为落盘的第二重保险。
2. **阶段边界查看 `/context`**：占用 ≥60% 时收尾当前阶段——结论落盘，然后主动 `/compact <聚焦指令>`（如 `/compact 保留驱动接口改动清单与未通过的测试`）。带指令的手动压缩保留"你指定的重点"而非"自动流程猜测的重点"，且在 60–70% 处执行的压缩请求远离一切失败条件。
3. **任务切换一律 `/clear`**：官方明确"无关上下文会降低性能"、"kitchen sink 会话"是第一反模式。切换后用 worklog 文件再引导（"先读 docs/worklog/xxx.md 然后继续 YY"）——干净窗口 + 磁盘证据优于被无关历史稀释的长会话。同一问题纠正超过两次同样适用：`/clear` 后带着教训重写提示词，官方明示这几乎总是优于继续拉扯。
4. **大规模检索交给子代理**：官方定调"上下文是根本约束，子代理是最有力的工具"——全仓探索、长日志分析、批量视觉转录放入子代理的独立窗口，主会话只收结论（7.10 的 fork/workflow、7.13 的 vision 即此模式的形态）。快问快答用 `/btw`（答案不进入对话史）。
5. **部分压缩**：需要保留近期推理全文、只压缩早期探索时，用 `Esc+Esc`/`/rewind` 选中检查点 → **Summarize up to here**（压早留新）或 **Summarize from here**（压新留早）。
6. **兜底路径**（水位调整后理论上不再触达）：若历史会话已在压缩死区卡死——先试 `/rewind` 部分摘要（请求规模小于全量压缩，可能仍可行）；仍失败则导出 + 新会话 + worklog 再引导。此为最后手段而非常规操作。

- 来源：[Claude Code – Best practices（Manage context aggressively：/clear、/compact 指令、/rewind 部分摘要、/btw、CLAUDE.md 定制压缩、两次纠正后重开、子代理与反模式清单）](https://code.claude.com/docs/en/best-practices)、[Claude Code – Explore the context window（When your context fills up、/context）](https://code.claude.com/docs/en/context-window)、[Anthropic – Effective context engineering（compaction / structured note-taking / sub-agent architectures）](https://www.anthropic.com/engineering/effective-context-engineering-for-ai-agents)

### 9.5 并行编排

- **计划先行**：大改动先 Shift+Tab 进入 plan 模式出计划，`ExitPlanMode` 未放行，计划必经人工审批（A4 人工闸门）。
- **worktree 隔离**：并行修改多分支时让 Claude 使用 worktree（默认 `.claude/worktrees/` 路径下创建/进入不弹窗），互不污染。
- **批量审计/迁移使用动态工作流**：workflow 是"计划写入脚本"的重型编排——阶段化、可并行、可对抗互验、可保存复跑，官方定位即"codebase audits、large migrations、cross-checked research"，单次可并行调度几十上百个子代理（本配置规模引导已解除）。触发方式三种：提示词包含 `ultracode` 关键词（单次）、直接指示"用 workflow 并行审计全部 phosphor-* 服务的 XX 用法"、或 `/effort ultracode` 使本会话对每个有分量的任务自动编排（锁定档为 `xhigh`，该通道处于可用状态）。fork 型子代理用于"带完整上下文的方案对比"。
- **workflow 的两条边界**：① `ultracode` 关键词与"用 workflow"的自然语言请求**仅在人工输入**（交互输入框、IDE 面板、Remote Control、标记 human 的 SDK 输入）时触发；经 `-p` 传入的提示词、计划任务提示词、webhook 一律**不触发**——无人值守需要 workflow 时，使用启动参数 `claude --effort ultracode -p "..."`（见 10.5）。② 权限语义：`-p`/SDK 下 workflow 的启动调用走标准权限评估——本配置的 allow 清单已含 `Workflow`（批准一切 workflow 启动），bypass 模式下亦直接放行；workflow 代理的权限模式按通用子代理规则继承主会话（主会话 bypass 则代理同为 bypass，7.9 已按现行官方文档改写）。
- **多实例协作**：agent teams 已启用，适合"一人主控 + 多队友分模块"的大迁移。
- **深度代码审查用 `/code-review`**：`/review` 已成为 `/code-review <level> <pr#>` 的别名（v2.1.223+），`high`/`xhigh`/`max` 档在后台 agent 运行、不阻塞主线（v2.1.232+）；不带级别时复用上次级别。`/code-review ultra` 为云端深度审查，需 claude.ai 通道，网关下不可用——本地档位不受影响。
- **长任务托管的第三形态——后台会话（agent view）**：`claude --bg "..."`、会话内 `/bg`、或总控台 `claude agents` 直接派发。会话由 per-user supervisor 进程托管，关闭终端、关闭 shell 甚至睡眠唤醒后仍在运行；`claude attach <id>` 随时进入查看（attach 恒为 fullscreen 渲染），`Space` 免 attach 预览。后台会话默认 worktree 隔离（`worktree.bgIsolation`）。可脚本化管理：`claude agents --json`、`claude logs/stop/respawn <id>`。与 `-p` headless 的分工：`-p` 是"射后不管 + 产物落盘"，`--bg` 是"长任务托管 + 中途可介入"——重大改造期间持续跟进的正确形态。Windows 兼容官方已覆盖（supervisor 无响应时 `claude daemon stop` 会打印 PID，用 `taskkill /PID <pid>` 结束）。
- **并发的 Kimi 侧上限意识**：每 5 小时滚动频率窗口约束请求密度（第 12 章）；workflow 的 16 并发 + 子代理并发 20 的默认组合在窗口内属安全量级，触顶 429 时重试看门狗自动退避，无需人工干预。

- 来源：[Claude Code – Workflows（定位、规模、adversarial review、ultracode 触发）](https://code.claude.com/docs/en/workflows)、[Claude Code – Agent view（`--bg`/`claude agents`/attach/worktree 隔离/Windows 说明）](https://code.claude.com/docs/en/agent-view)、[Claude Code – Tools reference（EnterWorktree/Agent/Workflow 行为）](https://code.claude.com/docs/en/tools-reference)、[Kimi Code – 会员权益（5 小时滚动窗口）](https://www.kimi.com/code/docs/kimi-code/membership.html)

## 10. 场景 ②：A 股深度行情分析

### 10.1 总原则

LLM 在金融数据上的唯一可靠形态是**编排器**而非数据库：它负责取数、编写代码计算、交叉验证、组织论证；数字本身必须全部来自工具调用。以下规程将这一点制度化。

### 10.2 数据铁律（写入 CLAUDE.md，同时也是验收结论的标准）

1. **零记忆数字**：任何行情/财务/宏观数字，禁止直接引用模型记忆；必须来自当轮工具调用（本地数据接口或检索），并标注「来源（接口名或 URL）+ 获取时间」。
2. **计算全部落代码**：均线、波动率、估值分位、组合归因等一律由 Python 代码算出（Bash/PowerShell 工具执行），模型不做心算——采样随机性不影响 `pandas` 的输出，这才是"数值绝对可靠"的机制保证（也是第 8 章不调整 temperature 的底气）。
3. **双源交叉**：进入结论的关键数字（收盘价、涨跌幅、成交额、财务科目）至少两个独立来源核对；不一致时必须报告差异与取舍理由。
4. **来源分级**：交易所与法定披露渠道（上交所/深交所官网、巨潮资讯网、中国结算、央行/统计局/证监会）> 结构化数据接口（如 akshare/tushare/baostock 等本地库）> 财经媒体/聚合站。级别低的来源只能佐证，不能独立支撑结论。
5. **有损工具不入账**：WebFetch 是"小模型抽取"的有损设计（官方明示 lossy by design）——关键数字取证使用**读页 MCP 全文**或 Bash 中 `curl`/`python requests` 获取原始页面，WebFetch 仅用于泛读。
6. **检索链路明确指定**：时效信息（政策、公告、突发）优先走已部署的搜索/读页 MCP；未部署时用 Bash `curl` 直接取证——向模型下达任务时**指名工具**（"用 web-search-prime 检索、web-reader 取全文"或"用 curl 拉取该页"），不依赖内置 WebSearch（网关下大概率不可用，7.8）。
7. **图表与文档证据走双通道**：单张 K 线图/仪表盘截图可主线直读（K3 原生视觉）；研报 PDF/扫描件、批量图表对比、录屏取证经 vision 子代理（裸 `k3`）逐字转录（11 章作业规程），避免人工转录误差。

- 来源：[Claude Code – Tools reference（WebFetch lossy by design、WebSearch 后端说明）](https://code.claude.com/docs/en/tools-reference)

### 10.3 A 股 CLAUDE.md 模板（置于分析工作区根目录）

```markdown
# 角色与目标
你是 A 股市场分析工程师：负责取数、验证、计算、组织多空论证，产出可审计的分析报告。

# 数据铁律（不可违反）
1. 任何数字必须来自本轮工具调用，标注来源与获取时间；禁止凭记忆给数。
2. 一切计算写 Python 执行（pandas），禁止心算；脚本与中间数据落盘到 data/ 与 scripts/。
3. 关键数字双源交叉验证；不一致必须披露差异及取舍理由。
4. 数据不可得就明说"取不到"，禁止估计值冒充实际值。

# 口径声明（每份报告开头必须给出）
- 数据截止时间（Asia/Shanghai）；行情快照 vs 收盘数据。
- 复权方式：前复权/后复权/不复权（涉及跨期比较必须声明）。
- 单位统一声明：元/万元/亿元；成交额与市值单位分开写清。
- 财务数据：报告期（如 2026Q1）与公告日期分开标注；同比/环比基期写明。
- 指数/板块口径：指数代码与编制方（中证/国证/申万行业版本）。

# 交易规则常识（计算与回测必须内建）
- T+1；交易日历以交易所公布为准（节假日、临时休市）。
- 涨跌停：主板 ±10%，ST/*ST ±5%，创业板/科创板 ±20%，北交所 ±30%；
  新股/次新与退市整理期规则特殊，单独核对后再用。
- 停复牌、退市、ST 变更影响可交易性与连续性：回看历史用时点数据（point-in-time），
  防幸存者偏差；禁止用后来发生的事解释之前的价格。

# 视觉证据规程（双通道）
- K 线图、仪表盘截图、研报 PDF 一律落盘 charts/ 与 docs/evidence/，对话中只出现路径。
- 单张图表可主线直读（K3 原生视觉）；研报/扫描件多页阅读、批量图表对比、
  录屏取证点名 vision："用 vision 读 charts/601398-daily.png：先锁定口径再读数"。
- 视觉读数一律带估读精度，且只用于形态判断；精确数值必须回数据接口取证。

# 全面性检查清单（深度分析必须逐项过）
宏观与政策 / 行业景气与产业链上下游 / 公司基本面（财报三表+关键科目异动）/
资金面（成交、换手、大宗、股东户数、北向及融资融券如可得）/ 估值（绝对+相对+历史分位）/
情绪与预期差 / 风险与反方论证（必须主动检索做空/看空观点并回应）/ 结论的可证伪条件。

# 输出规范
- 报告落盘 reports/<日期>-<主题>.md；附数据来源清单表（数值|来源|获取时间|校验源）。
- 明确区分「事实（带来源）」「推断（带逻辑链）」「观点（带置信度与前提）」。
- 本工作区只做研究分析，不接实盘下单接口。

# 上下文压缩保留项（compact 时不可丢弃）
- 口径声明块全文；数据来源清单表（数值|来源|获取时间|校验源）；
  未完成核查项清单；已形成结论的可证伪条件。
```

### 10.4 深度与全面性的执行手段

- `reasoning_effort=max` 已锁定（7.3 的 xhigh 经 Kimi 映射即 max），无需在提示词中要求"深度思考"。
- 全面性依靠**结构**而非"多想想"：要求模型按 10.3 检查清单逐项核对，并使用 fork/子代理并行核查——例如"fork 两支分别构建多头与空头最强论证，主线汇总裁决"（fork 继承完整上下文，证据不丢失，见 7.10）。
- **重大专题使用对抗互验工作流**：workflow 的官方设计即包含 "independent agents adversarially review each other's findings before they're reported"（独立代理互相对抗审查后才汇报）——对"某行业景气拐点是否成立"这类命题，指示"用 workflow：多角度分头取证 → 交叉互验 → 汇总裁决"，较单线程结论具有显著更高的可信度。
- 每份报告强制设"反方论证"章节：主动检索看空/风险观点并逐条回应，纠正单边倾向。
- **上下文生命周期同样执行 9.4 规程**：盘后长会话在专题之间 `/clear` + 报告文件再引导；单专题内多轮取数后 `/context` ≥60% 即落盘报告再 `/compact`。行情数字属"当轮工具调用"证据（10.2 铁律），被摘要替换后**不得**凭摘要复述数字——重新取数或从落盘报告读取。
- **自备金融数据 MCP 置于项目级**：若另行接入行情/资讯类 MCP（如 akshare、wind、ifind 等本地封装），其 allow 规则应放入**分析工作区的** `.claude/settings.json`（如 `"mcp__akshare"`），不进入全局用户级——部署后才放行、重装不残留。

- 来源：[Claude Code – Workflows（adversarial review 模式）](https://code.claude.com/docs/en/workflows)、[Claude Code – Permissions（作用域合并）](https://code.claude.com/docs/en/permissions)

### 10.5 持续稳定复跑（盘后例行）——双轨制

无人值守采用 **Windows 任务计划程序 + headless 模式**，按任务性质分两轨：

```powershell
# 轨道一：每日例行（结构稳定、可比对、可复跑——B5 主力）
claude -p "执行每日例行分析：按 CLAUDE.md 铁律更新自选池数据、运行 scripts/daily.py、生成 reports/$(Get-Date -Format yyyy-MM-dd)-daily.md，全部数字附来源清单"

# 轨道二：重大专题（季度策略复盘、行业景气拐点判定——大规模并行深挖 + 对抗互验）
claude --effort ultracode -p "对 <标的/行业> 做深度多空核查：多角度分头取证、交叉互验后汇总裁决；产出 reports/$(Get-Date -Format yyyy-MM-dd)-deep.md，全部数字附来源清单"
```

双轨的划分依据是**产物性质**，而非节省配额：每日例行的价值在于结构稳定、日间可比、异常可归因——固定脚本 + 单线程 xhigh 是其正确形态；workflow 的编排自由度（每次并行结构均由脚本现场生成）用于例行任务反而引入日间不可比性，它属于重大专题。配额仅为可用性约束：触及上限时按第 12 章处置。

三个 headless 关键机制（均已在本配置内置或说明）：

1. **`ultracode` 关键词在 `-p` 提示词中不生效**（官方：关键词仅对人工输入的 prompt 生效），因此轨道二必须使用 `--effort ultracode` 启动参数（需 v2.1.203+），使整个会话对每个有分量的任务自动编排 workflow。
2. **`CLAUDE_CODE_PRINT_BG_WAIT_CEILING_MS=0`（settings 已内置）**：headless 默认仅等待后台子代理/workflow 10 分钟，超时直接终止剩余任务并退出——轨道二的深度 workflow 极易超过 10 分钟，不设 `0` 即为最隐蔽的"无人值守被截断"。
3. headless 下权限弹窗无人可答：本配置的 `-p` 会话继承用户级 `bypassPermissions`，workflow 代理随之同为 bypass（7.9）；若以非 bypass 模式启动（如 `--permission-mode dontAsk` 的 CI 形态），未在 allowlist 的调用将被直接拒绝——16 条 allow（含 `Workflow` 启动规则）即为该形态的规则供给。

其余要点不变：`-p` 沿用同一份用户级 settings（bypass、重试看门狗、MCP 全部生效）；产物落盘 = 审计底稿；`cleanupPeriodDays=365` 保留转录一年；会话内轻量轮询另有 `/loop`。无人值守会话无人执行手动压缩，800K 水位的自动压缩（7.4）即其上下文安全网——这正是水位必须落在"压缩必然可行"区间的原因之一。

- 来源：[Claude Code – Workflows（关键词仅限人工输入、`--effort ultracode`、acceptEdits 语义、headless 无交互确认）](https://code.claude.com/docs/en/workflows)、[Claude Code – env-vars（`CLAUDE_CODE_PRINT_BG_WAIT_CEILING_MS`、`CLAUDE_CODE_RETRY_WATCHDOG`）](https://code.claude.com/docs/en/env-vars)、[Claude Code – Agent view（`claude --bg` 派发旗标、supervisor 托管）](https://code.claude.com/docs/en/agent-view)、[Claude Code – Overview（headless/`-p`、`/loop`）](https://code.claude.com/docs/en/overview)

需要中途跟进的重大专题可改用**后台会话形态**：`claude --bg --effort ultracode "..."`（派发支持 `--effort` 等旗标，语义同 `claude agents` 派发；注意 `--bg` 传入的提示词同 `-p` 一样**不触发** ultracode 关键词，必须用旗标）——supervisor 托管下关闭终端不中断，`claude agents` 总控台随时 attach 查看进度，完成/待输入时终端铃声提醒（7.12）。产物仍按数据铁律落盘，无人值守语义与 `-p` 一致；`claude agents --json` 可纳入任务计划程序做编排。

### 10.6 实盘边界（唯一建议保留的硬闸）

分析与执行必须物理分离：实盘下单脚本置于独立仓库，在**该仓库**的 `.claude/settings.local.json` 中添加窄 deny（如 `"Bash(python live_trade.py*)"`、`"Edit(//C/trading/keys/**)"`）。deny 规则在包括 bypass 在内的一切模式下生效，是官方提供的唯一硬闸；分析工作区保持零 deny 全自动。

- 来源：[Claude Code – Permissions（deny 全模式生效、路径规则语法）](https://code.claude.com/docs/en/permissions)

---

# 第四部分：运维

## 11. 多模态证据作业手册（双通道架构）

### 11.1 部署与触发

- 部署：[`agents/vision.md`](./agents/vision.md) → `%USERPROFILE%\.claude\agents\vision.md`（用户级，全项目可用；亦可放入 `<项目>\.claude\agents\` 做项目级覆写）。`d-kimi` 一键完成；与 ds-settings/glm-settings 共用部署位时，切换供应商须同步替换（第 6 章部署步骤 3）。
- 触发：主线依据子代理 `description` **自动委派**（其中已声明批量视觉任务的委派条件），亦可 `@vision` 显式点名。可靠的下达格式：**文件路径（或目录）+ 要回答的问题**。
- 观测：`/tasks` 或代理详情应显示该子代理运行于裸 `k3`（部署后按第 15 章第 11 条验证一次）。

**双通道分流规则**（写入各项目 CLAUDE.md，模板 9.2/10.3 已含）：

| 场景 | 通道 | 理由 |
| --- | --- | --- |
| 一张报错截图、一张 K 线图、一张 UI 对照图 | **主线直读**（Read 图片） | 零路由开销；旗舰推理直接作用于像素；图片入主线上下文后可被后续多轮持续引用 |
| 视频取证（抽帧后数十张图）、多页 PDF/扫描件、密集小字表格、批量截图对比 | **vision 子代理** | 图片洪流不占主线上下文与请求体预算；转录规程（先转录后判读）制度化；回传文本可落盘审计 |

### 11.2 多模态规程（防细节丢失与防请求体超限）

1. **视觉内容永远是文件，不是粘贴物**：粘贴进输入框的图片技术上可行（K3 不报错），但绕过 Read 工具的规范化通道、无法被 vision 规程约束、且永久占据主线上下文。规程：截图/录屏/PDF 落盘到工作区（建议 `docs/evidence/`、`charts/`），对话中只出现路径。
2. **图片直读**：JPEG/PNG/GIF/WebP，Read 工具路径。大图先裁剪——两级压缩会吃掉细节（客户端对大图缩放重编码后才发送；服务端再按自身规则换算，Kimi 未公布换算细则）。vision 子代理的系统提示已内置裁剪规程（高分屏截图的局部报错、密集小字、需精确读数的图表，先用 Python Pillow/ImageMagick 裁出感兴趣区域再读，必要时分块）；下达任务时主动指出关注区域（"右下角的报错弹窗"）能显著提高转录质量。
3. **视频走抽帧**：子代理用 ffmpeg 抽帧后逐帧读——通览用 `fps=1`、抓闪现报错/弹窗用 `fps=2` 或全关键帧；长视频先低密度通览、再对可疑片段高密度重抽；产出要求带时间点（"t=00:14 处出现红色弹窗，文字为……"）。ffmpeg 缺失时 `winget install Gyan.FFmpeg`。（K3 主线虽支持视频输入，但 Claude Code 客户端无视频读取工具——抽帧是一切客户端工况下的通用路径，子代理本就只吃帧图，无能力损失。）
4. **批量分批读**：图片以 base64 进入请求体（膨胀约 33%），几十张高分辨率帧单批发送存在服务端请求体拒绝风险（7.4.0 第二层）。子代理规程：每批 ≤10 张、批间累积已确认事实、只为目标证据读图。
5. **PDF/扫描件转图读**：数字原生 PDF（有文字层）优先主线文本提取（`pdftotext`/PyPDF）——文字证据走文本通道更准；扫描版/图片型 PDF 先转图片（`pdftoppm -png -r 150`）再逐页读，页数多时先读目录页定位。Anthropic document 块在 Kimi 端点的支持未获官方声明，统一走转图路径规避不确定性。
6. **转录即证据**：vision 回传的文本是批量证据的规范载体。关键转录按 9.4 落盘；报告中引用时注明「文件路径 + vision 转录 + 获取时间」。
7. **视觉读数不进计算**：图表估读只用于形态判断与线索定位；进入计算与结论的数值必须回到数据接口/原文取证（10.2 第 7 条）。

### 11.3 典型任务模板

```text
# debug 截图（BMC/CI 报错，单张——主线直读）
读取 docs/evidence/ci-fail-0827.png：逐字提取报错消息、错误码、栈帧与文件行号；
记录截图中可见的环境线索（终端标题/路径/版本号/时间戳）；报错被截断处明确标注。

# UI 走查（前端还原度，两张对照——主线直读）
读取 docs/evidence/design.png 与 docs/evidence/actual.png：按区块列出布局/配色/字号/间距差异，
标注各差异在截图中的位置；不确定处标注"不可辨认"。

# 架构图/时序图理解（单张大图——主线直读或裁剪后直读）
读取 docs/evidence/ipmb-timing.png：转录全部节点/信号名与连线关系，输出时序步骤清单；
图中文字不可辨认处逐项列出，不得脑补。

# K 线/图表读数（A 股，单张——主线直读）
读取 charts/601398-daily.png：先锁定口径（坐标轴含义、时间范围、复权标注、成交量单位），
再描述形态（趋势、跳空、放量位置），读数一律带估读精度区间；精确数值回数据接口取。

# 复现录屏/视频取证（批量帧——vision 子代理）
用 vision 分析 docs/evidence/repro-0827.mp4：抽帧找出报错弹窗/崩溃画面出现的全部时刻，
逐字转录弹窗文字与可见的终端输出；描述触发前的操作序列；分批读取、批间汇总。

# PDF 规范/研报阅读（多页——vision 子代理）
用 vision 读 docs/spec-redfish.pdf 第 12–14 页：先转图再逐页逐字转录 Chassis 集合属性表的
属性名/类型/读写权限/描述列；表格截断或跨页处明确标注。

# 密集小字/扫描件（批量裁剪——vision 子代理）
用 vision 读 docs/evidence/ledger-scan/：密集表格逐块裁剪转录，输出结构化表格；
不可辨认单元格标注置信范围，禁止按常理补全。
```

### 11.4 已知边界

- 视频没有客户端读取工具——任何模型（含主线）都无法在 Claude Code 内直读视频文件，一律先抽帧，无能力损失。
- 主线直读图片会消耗主线上下文（图片按视觉 token 计入 1M 窗口）——单会话累计直读大量图片时应转用 vision 子代理，且按 9.4 规程及时落盘与压缩。
- vision 子代理的任何非视觉任务不得委派——专线为批量视觉证据而设，独立上下文不适合长程文本任务；子代理 description 与本手册规程双重约束。
- PDF 的 Anthropic document 块路径未启用（11.2 第 5 条）；如后续官方声明支持，可评估直读路径并更新本节。

- 来源：[Kimi Code – 模型配置（多模态输入支持矩阵）](https://www.kimi.com/code/docs/kimi-code/models.html)、[Claude Code – Tools reference（Read 图片压缩行为）](https://code.claude.com/docs/en/tools-reference)、[Claude Code – Sub-agents（自动委派依据 description）](https://code.claude.com/docs/en/sub-agents)、实测 5.0 第 7 条

## 12. 额度、限流与可用性运维

本章为 Kimi 体系特有的运维章节（替代 GLM 配置的"多账号轮换"单节，机制更完整）。

### 12.1 额度体系三层结构

Kimi Code 与 Kimi 会员共享同一套额度，三层结构同时生效（官方会员权益页）：

| 层 | 周期 | 语义 |
| --- | --- | --- |
| 5 小时滚动频率窗口 | 每 5 小时滚动 | **请求密度限制**——即使总量充足，短时间请求过多也会触发限流，窗口滚动后自动恢复 |
| 周额度 | 以订阅日为起点每 7 天刷新 | 周期总量，未用完不累积 |
| 月度总额度 | 自然月 | 与网页端 Kimi 全家（PPT、Agent 集群等）共享；月度触顶后 Kimi Code 额度冻结，等待月度重置或升级 |

所有登录设备与 API Key 共享同一套配额；超过 30 天未活跃的设备自动解绑（重新 `/login` 恢复）。[Kimi Code 控制台](https://www.kimi.com/code/console) 可随时查看剩余额度、频限状态、管理 API Key 与登录设备。

### 12.2 429/403 分类处置（对照官方错误参考）

| 报错关键词 | HTTP | 性质 | 处置 |
| --- | --- | --- | --- |
| `The engine is currently overloaded` | 429 | 服务端容量问题，与个人配额无关 | **直接重试**——`CLAUDE_CODE_RETRY_WATCHDOG=1` 自动无限重试；工作日高峰期（官方错误参考提示 14:00–17:00）可能触发，可避开 |
| `We're receiving too many requests` | 429 | 账户请求频率/并发超限 | 稍候重试（看门狗自动）；持续出现时降低并行度（减少同时运行的会话/workflow 并发） |
| `You've reached your usage limit for this period` | 403 | 5 小时滚动窗口触顶 | 等待窗口滚动（控制台查看重置时间）或切换账号/加油包；**重试无意义** |
| `You've reached your usage limit for this billing cycle` | 403 | 周额度耗尽 | 等待下个 7 天周期或切换账号/加油包 |
| `You've reached kimi monthly usage limit` | 403 | 月度总额度（全家共享）耗尽 | 等待月度重置或升级订阅；加油包可覆盖（见 12.4） |
| `You've reached your concurrent request limit` | 403 | 触发风控并发限制（官方口径：需申诉解除） | 先降并发并核查账号状态；与 429 的瞬时频率超限性质不同，勿仅靠重试 |

与重试看门狗的对应：429 容量/频率类（overloaded、too many requests）由看门狗无限重试；**配额类在 Kimi 侧是 403**（非 429），不进入看门狗的无限重试路径，按普通错误快速失败——无人值守任务快速退出，正是触发本章处置（换账号/等窗口）的信号，而非缺陷。

### 12.3 高峰时段

官方错误参考明示工作日 14:00–17:00 为推理引擎高峰期、可能触发 overloaded 429。B5 盘后例行（收盘后至晚间）与该时段部分重叠——若例行任务频繁遭遇 overloaded 重试，可将其排程后移至 17:00 之后（重试看门狗本身已保证任务不中断，排程调整只是减少空转等待）。

### 12.4 加油包（Extra Usage）

订阅额度用尽后的无缝续跑机制（官方会员权益页）：

- **无视一切限额**：月/周/小时任意额度触顶时自动切到加油包余额，任务不中断、不报错；只扣加油包、不影响会员额度刷新。
- 计价近似开放平台 API 官方价格（按实际用量扣费）；先扣订阅限时额度、加油包最后扣。
- 余额不过期、可叠加（上限 10,000 RMB）；单次充值最低 25 RMB、每日最多 10 次。
- 开启入口：Kimi 订阅页底部「额度加油包」模块，或控制台进度条卡片（周/5 小时额度任一消耗超 80% 时出现购买按钮）；可设每月消费上限。
- 用量查询：网页端设置 → 订阅和发票 → 我的额度；控制台（开启加油包后）；CLI 内 `/usage`（Kimi Code CLI 的命令，非 Claude Code）。

对无人值守轨道（10.5）的意义：开启加油包后，"额度触顶导致 headless 任务失败"的最后一块短板被消除——任意额度触顶都无缝续跑。是否开启属使用者决策（涉及真实支出），本配置不代为决定。

### 12.5 多账号轮换（可用性机制）

多个 Kimi 会员账号在本方案中的定位：**可用性冗余**。触顶 5 小时窗口/周额度/月度额度时切换账号续跑是唯一不降级的路径（不换模型、不降 effort、不关 thinking）。

1. **直接更换 Key**：修改 settings.json 的 `ANTHROPIC_API_KEY`（或更新 `KIMI_API_KEY` 环境变量后重跑 `d-kimi`）。`env` 块热加载，通常无需重启。
2. **每账号一个配置目录（推荐）**：`CLAUDE_CONFIG_DIR` 整体切换配置根（官方明示用于 "running multiple accounts side by side"）：`$env:CLAUDE_CONFIG_DIR="$env:USERPROFILE\.claude-acc2"; claude`。每个目录放置同一份 settings.json（仅 Key 不同）；`.claude.json` 的引导字段与 MCP 注册存储于各目录，新目录需重新执行引导（对应用户目录时 `d-kimi` 自动完成；自定义 `CLAUDE_CONFIG_DIR` 场景手动执行 deploy.ps1 的等价步骤）。
3. **apiKeyHelper 自动轮换**：`apiKeyHelper` 指向返回当前可用 Key 的脚本（`CLAUDE_CODE_API_KEY_HELPER_TTL_MS` 控制刷新间隔），实现触顶自动切换账号；采用此方式时应将 `ANTHROPIC_API_KEY` 从 `env` 移除，避免两套认证机制冲突。

注意：切换账号 = 切换 Kimi 侧缓存主体，新账号首轮全量冷启动（无损，仅慢一轮），应尽量在任务边界切换。

- 来源：[Kimi Code – 会员权益（额度三层结构、加油包、共享配额）](https://www.kimi.com/code/docs/kimi-code/membership.html)、[Kimi Code – 错误参考（429 全表、401/402/403 权限类）](https://www.kimi.com/code/docs/kimi-code/error-reference.html)、[Claude Code – env-vars（`CLAUDE_CONFIG_DIR`、`CLAUDE_CODE_API_KEY_HELPER_TTL_MS`）](https://code.claude.com/docs/en/env-vars)、[Claude Code – Settings（`apiKeyHelper`）](https://code.claude.com/docs/en/settings)

## 13. 升级 SOP

自动更新已被 `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1` 关闭，升级完全由使用者主动执行：

1. **确认无任务运行**（升级 = 系统提示词变化 = 行为漂移 + 缓存冷启动，只能发生在任务间隙——A6）。
2. 连接 VPN → `claude --version` 记录当前版本。
3. 升级（按安装方式）：原生安装 `claude update`；WinGet `winget upgrade Anthropic.ClaudeCode`；npm `npm install -g @anthropic-ai/claude-code@latest`。
4. `claude --version` + `claude doctor` 验证。
5. 断开 VPN，正常使用（模型流量仅走 `api.kimi.com`）。
6. 升级后**从新会话开始新任务**；避免立即 `--resume` 长会话（官方明示：升级后恢复会话将无缓存重放全部历史，且新系统提示下的行为与原任务存在漂移）。

- 来源：[Claude Code – Overview（各安装方式更新行为）](https://code.claude.com/docs/en/overview)、[Claude Code – Prompt caching（Upgrading Claude Code）](https://code.claude.com/docs/en/prompt-caching)

## 14. 一致性管理：任务中途的行为漂移源清单

以下操作会在任务中途改变"回答者的条件"（缓存重建只是其可观测的影子），**任务进行中一律避免**，统一移至任务边界执行。前三行为 Kimi 官方明示的缓存失效源，权重最高：

| 漂移源 | 后果 | 对策 |
| --- | --- | --- |
| 关闭 thinking（`Alt+T` 快捷键或任何途径） | **请求被路由到 K2.8 Preview（无思考）——静默换模型**，官方明示 | `alwaysThinkingEnabled: true` 封死客户端路径；不使用 `Alt+T`；`/effort` 不设 `none` |
| `/model` 切换模型 | 不同模型 = 不同回答者 + 缓存全部失效（官方明示"切换模型后缓存不再命中"） | 全 K3 单模型，选单中已无备选；不得手动指定其它模型 |
| `/effort` 切换档位 | 推理深度改变 + 缓存失效（官方明示"切换思考程度会让已建立的缓存失效"） | 已用环境变量锁定 xhigh（经映射即 max），`/effort` 实际失效 |
| 升级 Claude Code | 系统提示词/工具定义变化 | 第 13 章 SOP：仅在任务间隙升级 |
| MCP 服务器中途连接/断开 | 工具定义集合变化 | MCP 一次配置完成不再变动；服务器抖动由 `MCP_TIMEOUT` 与重连机制吸收 |
| 以裸工具名 deny 工具 | 工具集合变化 | deny 保持为空（第 7.9） |
| `/compact` 压缩 | 对话史被摘要替换 | 安排在任务之间或阶段边界（9.4 规程：先落盘、再带聚焦指令压缩），不在论证中途执行 |
| `/autocompact`/`--autocompact` 中途改水位 | 压缩触发点改变 | 水位由环境变量锁定 800K（7.4），`/autocompact` 仅报告接管状态；调整水位属任务边界操作 |
| 中途修改 CLAUDE.md | 本会话不生效（下次 `/clear`/重启才生效），易产生"以为已修改"的错觉 | 修改规则后重启会话再开工 |
| 中途修改 `agents/vision.md` | 同上（子代理定义会话启动时装载） | 同上 |

无漂移风险、可随时执行：编辑仓库文件、Shift+Tab 切换权限模式、调用技能/命令、`/recap`、`/rewind`、派生子代理。

观测手段（按需使用、无常驻组件）：`/status` 查看模型与设置来源（**并核对 Base URL 为 `https://api.kimi.com/coding/`**）、`/context` 查看窗口占用与压缩水位、`/effort` 确认档位被环境变量接管；缓存读写可在响应的 `usage.cache_read_input_tokens` 观察。本配置无常驻状态栏组件——漂移的结构性来源已在配置层消除（见上表对策），如需临时观测，可使用官方 `/statusline` 命令按需生成。

- 来源：[Kimi Code – 模型配置（切换模型/effort 使缓存失效、thinking 关闭路由）](https://www.kimi.com/code/docs/kimi-code/models.html)、[Claude Code – Prompt caching（cache 字段含义）](https://code.claude.com/docs/en/prompt-caching)、[Claude Code – Statusline（`/statusline` 命令）](https://code.claude.com/docs/en/statusline)

## 15. 部署后验证清单

| # | 动作 | 期望结果 |
| --- | --- | --- |
| 1 | `claude --version` | ≥ v2.1.246（全部版本门槛见 17.4；注意 `minimumVersion` 约束的是更新通道而非启动——旧版不会拒绝启动，版本核对以本命令为准） |
| 2 | 启动 `claude` | 无认证报错、未被要求登录 Anthropic（`.claude.json` 引导生效）；`⏵⏵ bypass permissions on` 徽标；首次提示 "Do you want to use this API key?" 时确认 |
| 3 | `/status` | Setting sources 含 User settings；Model 为 `k3[1m]`（显示名 Kimi K3 (1M)）；**Base URL 显示 `https://api.kimi.com/coding/`**（官方指定的接入成功判据——即使模型名仍显示为 Claude 系名称，实际调用的已是 K3） |
| 4 | `/model` | 各别名位均显示 Kimi K3；**无**任何 K2.8/高速版备选项 |
| 5 | `/effort` | 提示档位被环境变量接管（xhigh） |
| 6 | `/context` | 窗口按 1M 计（注意：状态栏 `used_percentage` 按全窗口计量，不指示 800K 触发点） |
| 6a | `/autocompact`（不带参数） | 报告水位 800000 且由环境变量 `CLAUDE_CODE_AUTO_COMPACT_WINDOW` 接管，命令不可修改 |
| 7 | 复杂提问 | **思考过程可见**（`Ctrl+O`）——K3 thinking 恒开，无 thinking 块即异常（对照第 14 章红线：可能被路由到无思考版）；流式稳定 |
| 8 | 提示词包含 `ultracode` 下达审计任务 | 触发 workflow 编排，`/workflows` 可见并行子代理 |
| 9 | "用 curl 取今日沪深两市成交额并给来源"（或已部署的搜索 MCP） | Bash/MCP 取证正常，无权限弹窗，数字带来源与时间 |
| 10 | 项目放置一张含清晰文字的图片，"读取 error.png，提取完整文字" | **主线直读成功**（K3 原生视觉）——逐字转录正确即视觉链路健康（对照实测 5.0 第 7 条） |
| 11 | 同一目录放置多张截图或一段录屏，"用 vision 分析 <目录/视频>：<问题>" | 主线委派 vision 子代理；`/tasks`/代理详情显示其模型为裸 `k3`；回传逐字转录与时间点 |
| 12 | Shift+Tab | manual → acceptEdits → plan → bypass 循环 |
| 13 | 日常断开 Anthropic 访问 | 无升级/遥测报错刷屏；WebFetch 可用（预检已跳过） |
| 14 | `/tui`（不带参数） | Current renderer: fullscreen（输入框固定底部不随输出移动即已生效） |
| 15 | 长任务运行期间切换到其他窗口 | 完成或等待输入时终端铃声（Windows Terminal 需在设置中为 bellStyle 启用声音/任务栏闪烁至少一项） |
| 16 | 下达含多步清单的任务 | 任务清单工具可用（TaskCreate/TaskUpdate 正常被调用，未被新版默认移除） |
| 17 | 提示词包含 `ultracode` 下达大型审计 | workflow 编排的代理数量按任务规模展开（不被 medium 引导压在 15 以内，见 7.10） |
| 18 | 会话运行约 1 小时后观察 `/context` 与响应头缓存字段 | 长会话无中途截断；缓存持续命中（隐式缓存自动生效，实测 5.0 第 3 条） |

## 16. 故障排查速查表

以报错信息中的**文字关键词**为主匹配（官方提示：客户端可能转换/包装错误码）。逐条对应官方错误参考：

| 症状 | 原因 | 处置 |
| --- | --- | --- |
| `The API Key appears to be invalid or may have expired`（401） | Key 填写有误/已撤销/被环境变量覆盖 | 核对多余空格；[控制台](https://www.kimi.com/code/console) 确认 Key 状态；检查 `KIMI_API_KEY`/`OPENAI_API_KEY`/`ANTHROPIC_AUTH_TOKEN` 等环境变量残留（6 章、12.5） |
| `Invalid Authentication`（401） | **误用开放平台的 Key 或 URL**（两体系不通用） | 核对 Base URL 为 `https://api.kimi.com/coding/`、Key 来自 Kimi Code 控制台而非 platform.kimi.com；[错误参考](https://www.kimi.com/code/docs/kimi-code/error-reference.html) |
| `Your current subscription does not have access to k3`（401） | 套餐低于 Moderato | 升级订阅；或暂用 `kimi-for-coding`（所有会员可用）——将四别名位整体改值并在任务边界执行 |
| `Your current plan supports only kimi-k3 up to 256K context`（401） | Moderato 档调用 `k3` 的 1M 超出权限 | 升级 Allegretto 及以上；或将 `k3[1m]` 改为 `k3-256k`（同时 `CLAUDE_CODE_AUTO_COMPACT_WINDOW`/`CLAUDE_CODE_MAX_CONTEXT_TOKENS` 降至 262144，官方示例口径） |
| `Your model id does not exist, recognized as other: k3[1m]`（401） | `[1m]` 写法进入了非 env 场景（frontmatter/API/其它工具字段） | 该写法仅限 Claude Code 环境变量；vision 子代理 frontmatter 与 API 直调均用裸 `k3`（实测 5.0 第 8 条） |
| `unable to verify your membership benefits`（402） | 订阅状态临时无法确认 | 确认订阅有效；稍候重试；持续出现走官方客服 |
| `You've reached your usage limit ...` / `kimi monthly usage limit`（403） | 周/月/5 小时额度触顶（Kimi 侧配额触顶为 403 而非 429） | 按第 12 章分类处置（等待重置/切换账号/加油包） |
| `The engine is currently overloaded` / `too many requests`（429） | 容量过载/账户并发超限 | 看门狗自动重试；持续出现按 12.2/12.3 处置 |
| `total message size N exceeds limit 2097152`（400） | 消息体超 2MB（官方最高频 400） | 精简历史/分段；本配置 800K 水位 + vision 批量转录已结构性规避（7.4.0 第二层、11.2 第 4 条）；仍触发时手动 `/compact` 减小请求 |
| `Your request exceeded model token limit: 1048576`（400） | 单请求 token 超上限（实测即此文案，5.0 第 11 条） | 本配置水位设计下不应出现；存量会话按 9.4 兜底路径（/rewind 部分摘要或导出重开） |
| `thinking is enabled but reasoning_content is missing`（400） | 工具调用消息缺失推理字段（非 Claude Code 常规路径） | Claude Code 工况下由网关自动处理（实测 5.0 第 13 条）；出现于自定义脚本时按官方规范补 reasoning_content |
| `unsupported image url`（400） | 图片传了本地路径/非标准 base64 前缀 | 走 Read 工具读图（标准 image 块，实测走通）；不手工拼 image source |
| 响应中途中断 | 链路抖动 | 已含三层看门狗与重试；频发时检查本地代理是否拦截 `api.kimi.com` |
| `anthropic-beta` 头报错 | 端点不识别某 beta | 临时添加 `"CLAUDE_CODE_DISABLE_EXPERIMENTAL_BETAS": "1"`；[env-vars](https://code.claude.com/docs/en/env-vars) |
| 修改 settings 不生效 | JSON 语法错误/文件位置错误/旧窗口 | 全部关闭重开；`/status` 查看 sources；`claude doctor` |
| 启动要求登录 Anthropic 账号 | `.claude.json` 引导字段缺失 | 重跑 `d-kimi`（自动写入 penguinModeOrgEnabled/hasCompletedOnboarding）；或按官方文档手动执行步骤②脚本 |
| 响应无 thinking 块、且深度明显变浅 | **被路由到 K2.8 Preview 无思考版**（thinking 被关闭：`Alt+T` 误触或请求形态异常） | 第 14 章红线：确认 `alwaysThinkingEnabled: true`；不用 `Alt+T`；重启会话；此状态产出的结论应复核 |
| vision 子代理未被自动委派 | 主线未识别任务的批量/取证属性 | `@vision` 显式点名；任务描述给出图片目录；核对 `agents/vision.md` 部署路径与 frontmatter |
| vision 读图报 401（model id 类） | frontmatter 被改成了 `k3[1m]` 或残留其它供应商的 vision.md | 恢复 `model: k3`；确认部署的是本仓库 agents/vision.md |
| vision 转录细节缺失/读数模糊 | 两级压缩（客户端缩放重编码 + 服务端换算） | 按 11.2 先裁剪感兴趣区域再读；下达任务时指明关注区域 |
| "忘记前文" | 窗口按 200K 误判，或已发生压缩而关键信息未落盘 | `/context` 核对窗口与占用；确认 `[1m]`/水位 800K 生效；已压缩则重读 worklog/报告文件（9.4），fullscreen 下 `Ctrl+Home` 回滚原文（7.12） |
| 会话逼近上限后卡死：手动/自动压缩均失败 | 水位曾被改为满格或未生效 | 本配置 800000 水位下不应出现；存量卡死会话按 9.4 兜底路径（/rewind → Summarize up to here → 导出重开） |
| 压缩后关键结论/数字丢失 | 压缩摘要未保留该信息且未落盘 | 按 9.4 规程：阶段结论先落盘再压缩；CLAUDE.md 写入"压缩保留项"（9.2/10.3 模板已含）；金融数字不得凭摘要复述，重新取数（10.4） |
| WebFetch 全部失败 | 未跳过 Anthropic 预检 | `skipWebFetchPreflight: true`（已内置）；[Settings](https://code.claude.com/docs/en/settings) |
| 内置 WebSearch 报错 | Anthropic 服务端工具，网关下不可用 | 用已部署的搜索 MCP 或 Bash curl（7.8/10.2 第 6 条） |
| 非 bypass 模式弹出权限窗 | 工具不在 allow / 拼写非权威名 | 对照 7.9 清单；`/permissions` 查看规则来源 |
| 后台子代理异常标记 "failed" | 长命令期间无进度事件被判失速 | 已放宽到 1h；超过 1h 的构建改用后台命令执行；[env-vars（`CLAUDE_ASYNC_AGENT_STALL_TIMEOUT_MS`）](https://code.claude.com/docs/en/env-vars) |
| `/effort` 未提示被环境变量接管 / 疑似 effort 未生效 | 能力声明或 `CLAUDE_CODE_ALWAYS_ENABLE_EFFORT` 未生效 | 核对 `_SUPPORTED_CAPABILITIES` 与 `CLAUDE_CODE_ALWAYS_ENABLE_EFFORT=1`；重启会话；`/status` 查看设置来源 |
| 无人值守的深度分析 10 分钟被终止 | headless 后台等待上限默认 10 分钟 | 本配置已设 `CLAUDE_CODE_PRINT_BG_WAIT_CEILING_MS=0`（无限等待）；核对 `/status` 设置来源 |
| `-p` 提示词中写了 ultracode 却没有 workflow | 关键词仅对人工输入生效 | 使用 `claude --effort ultracode -p`（10.5 轨道二） |
| workflow 编排的代理数总在十个以内封顶 | `workflowSizeGuideline` 处于默认 `medium`（<10 引导） | 确认已设 `unrestricted` 且未被项目级设置覆盖 |
| 全屏渲染出现残影/错位碎片 | Windows Terminal（ConPTY）增量重绘合并缺陷 | 确认 `CLAUDE_CODE_ALT_SCREEN_FULL_REPAINT=1` 生效（7.12）；滚动出空白块再叠加 `CLAUDE_CODE_DISABLE_VIRTUAL_SCROLL=1`；临时回退 `/tui default` |
| 任务清单工具（TaskCreate 等）不可用 | CLI ≥ v2.1.233 且模型被判为"较新"，默认移除 | 确认 `CLAUDE_CODE_ENABLE_TODO_TOOLS=1` 生效（7.10） |
| K3 与 K3-256k 手动互切后报错 | 上下文已超 256K 或历史含视频内容（256K 版不支持视频） | 官方纪律：切换前先 compact（7.4 末尾）；本配置部署链路不含 `k3-256k`（主线 `k3[1m]`、vision 裸 `k3`），正常工况不发生此切换 |

---

# 第五部分：附录

## 17. Kimi K3 规格、Model ID 矩阵与会员档位

### 17.1 K3 架构规格（MoonshotAI 官方仓库口径）

| 项 | 值 |
| --- | --- |
| 架构 | Mixture-of-Experts（MoE），Kimi Delta Attention（KDA）+ Attention Residuals（AttnRes），Stable LatentMoE |
| 总参数 / 激活参数 | 2.8T / 104B（896 专家选 16 + 2 共享；93 层，其中 69 KDA + 24 Gated MLA） |
| 上下文长度 | 1,048,576 token（实测确认，5.0 第 9 条） |
| 视觉编码器 | MoonViT-V2（401M 参数）——原生理解文本、图片、视频 |
| 量化 | MXFP4 权重 / MXFP8 激活（量化感知训练，SFT 阶段起） |
| 词表 | 160K |
| thinking | 恒开（API 层默认 `reasoning_effort=max`；Kimi Code 网关默认 `high`），preserved thinking history 模式 |
| 训练标定 | `temperature=1.0`；单步任务 top_p=0.95、agentic 任务 top_p=1.0 |
| 定位 | 长程编程（GPU kernel 优化、编译器、芯片设计）、知识工作、Agentic 任务；全球首个开源 3T 级模型（Kimi K3 License） |

### 17.2 Model ID 备查表（Kimi Code 端点）

| Model ID | 版本 | 上下文 | effort | 多模态 | 会员门槛 |
| --- | --- | --- | --- | --- | --- |
| `k3` / `k3[1m]`（env 专用写法） | K3 | 1048576（1M 需 Allegretto+；Moderato 为 256K） | low/high/max（默认 high） | 图片、视频 | Moderato+ |
| `k3-256k` | K3 | 262144 | low/high/max（默认 high） | 仅图片 | Moderato+ |
| `kimi-for-coding` | K2.8 Preview | 1048576（全档位开放） | low/high/max（默认 max） | 图片、视频 | 所有会员 |
| `kimi-for-coding-highspeed` | K2.7 Code HighSpeed | 262144 | Thinking:ON | 图片、视频 | Allegretto+ |

### 17.3 会员档位与权限矩阵（401 三情形对照）

| 档位 | k3 调用权 | k3 上下文上限 | kimi-for-coding | 高速版 |
| --- | --- | --- | --- | --- |
| Andante | ✗ | — | ✓（262144） | ✗ |
| Moderato | ✓ | 262144 | ✓（262144） | ✗ |
| **Allegretto 及以上（本配置目标档位）** | ✓ | **1048576** | ✓（1048576） | ✓ |

低于权限的调用返回 401（非 403），报错文案直接指明所需档位与升级链接——排查时以文案为准（16 章速查表前三行）。

### 17.4 版本门槛备查表（Claude Code 侧）

| 变量（本配置值） | 最低版本 | 旧版行为 |
| --- | --- | --- |
| `CLAUDE_CODE_ENABLE_TODO_TOOLS=1` | v2.1.233 | 无此变量；较新模型判定下任务清单工具缺失 |
| `workflowSizeGuideline=unrestricted`（设置键） | v2.1.219 | 旧版忽略该键；v2.1.219 起内置默认改为 `medium`（<15 引导）——本配置显式设值即对冲该默认 |
| `CLAUDE_CODE_FORK_SUBAGENT=1` 在 `-p` 下生效 | v2.1.232 | 旧版 `-p` 下 fork 同样需显式置 1；v2.1.232 起交互会话默认启用 |
| `CLAUDE_CODE_MCP_AUTO_BACKGROUND_MS=0` | v2.1.212 | 静默回退 2 分钟自动转后台 |
| `CLAUDE_CODE_MCP_TOOL_IDLE_TIMEOUT=600000` | v2.1.187 | 走传输层默认（网络 5 分钟/stdio 30 分钟） |
| `CLAUDE_CODE_MAX_CONTEXT_TOKENS` 对自定义模型名直接生效 | v2.1.193 | 需配合其他条件 |
| `CLAUDE_CODE_RETRY_WATCHDOG=1`（含 v2.1.239 计费类 429 立即失败语义） | v2.1.186 | 无看门狗语义，按默认重试 |
| 子代理 frontmatter `model` 指定完整模型 ID + 解析优先级现行语义（vision 路由的机制基础） | v2.1.196+ | 更旧版本 inherit 语义不同 |
| `--effort ultracode` 启动参数 | v2.1.203 | 报 Unknown value（会话内 `/effort ultracode` 不受此限） |
| 字节级流式看门狗在网关连接默认开启 | v2.1.222 | 网关连接仅有事件级看门狗（字节级需 `CLAUDE_ENABLE_BYTE_WATCHDOG=1`，本配置已显式设置） |
| `CLAUDE_CODE_SUBAGENT_MODEL` 语义：仅作默认，frontmatter/per-spawn 优先 | v2.1.251 | 旧版该变量覆盖 frontmatter（彼时设置它会破坏 vision 路由；本配置不设置，无影响） |
| 凭证隔离安全修复（遥测/指标请求不再向第三方网关泄露 API key） | v2.1.246 | `minimumVersion` 锚定值 |

第 13 章的升级纪律（保持最新 CLI）本身即是对这张表的最佳防御。`claude --version` ≥ v2.1.246 即全部满足；`minimumVersion: "2.1.246"`（7.11）的职责是**阻止自动更新/`claude update` 安装更低版本**（官方语义：该键只约束更新、不是启动门槛；`requiredMinimumVersion` 才是启动门槛且仅 managed 作用域可用），运行期核对以第 15 章第 1 条为准。

## 18. 参考链接汇总

**Claude Code 官方文档**

- 总览与安装：<https://code.claude.com/docs/en/overview>
- 设置全参考：<https://code.claude.com/docs/en/settings>
- 环境变量全参考：<https://code.claude.com/docs/en/env-vars>
- 模型配置（别名/[1m]/effort/能力声明/回退链）：<https://code.claude.com/docs/en/model-config>
- 权限系统：<https://code.claude.com/docs/en/permissions>
- 权限模式（Shift+Tab）：<https://code.claude.com/docs/en/permission-modes>
- 工具参考（权威工具名/行为/上限）：<https://code.claude.com/docs/en/tools-reference>
- 提示缓存机制：<https://code.claude.com/docs/en/prompt-caching>
- MCP 接入与作用域：<https://code.claude.com/docs/en/mcp>
- 动态工作流（workflow/ultracode）：<https://code.claude.com/docs/en/workflows>
- Agent view / 后台会话（`--bg`/`claude agents`/attach）：<https://code.claude.com/docs/en/agent-view>
- 全屏渲染（fullscreen/滚动/检索/ConPTY 修复）：<https://code.claude.com/docs/en/fullscreen>
- 终端配置（铃声通知/Shift+Enter/主题/键位）：<https://code.claude.com/docs/en/terminal-config>
- Fast mode（网关下不适用，备查）：<https://code.claude.com/docs/en/fast-mode>
- 状态栏（statusline 字段与 Windows 配置）：<https://code.claude.com/docs/en/statusline>
- 记忆机制（CLAUDE.md/规则/auto memory）：<https://code.claude.com/docs/en/memory>
- 超大代码库/monorepo 专文：<https://code.claude.com/docs/en/large-codebases>
- 上下文窗口机制（压缩存活表/水位/`/context`）：<https://code.claude.com/docs/en/context-window>
- 官方最佳实践（上下文为首要约束/`/clear`/`/btw`/反模式清单）：<https://code.claude.com/docs/en/best-practices>

**长上下文质量权威研究（7.4.0 定调依据）**

- Anthropic 工程博客 – Effective context engineering for AI agents（context rot/注意力预算/长程三板斧）：<https://www.anthropic.com/engineering/effective-context-engineering-for-ai-agents>
- Chroma – Context Rot 技术报告（18 模型受控实验）：<https://research.trychroma.com/context-rot>
- NoLiMa: Long-Context Evaluation Beyond Literal Matching（ICML 2025）：<https://arxiv.org/abs/2502.05167>
- RULER: What's the Real Context Size of Your Long-Context Language Models?（COLM 2024）：<https://arxiv.org/abs/2404.06654>

**Kimi 官方文档与资源**

- Kimi Code 文档站首页（双协议端点、模型总览、平台对比、UA 条款）：<https://www.kimi.com/code/docs/>
- Kimi Code – Claude Code 接入（官方环境变量示例、`.claude.json` 引导脚本、effort 映射、/status 验证）：<https://www.kimi.com/code/docs/third-party-tools/claude-code.html>
- Kimi Code – 模型配置（Model ID 规格、多模态矩阵、effort 映射、K3/K3-256k 切换纪律）：<https://www.kimi.com/code/docs/kimi-code/models.html>
- Kimi Code – 会员权益（额度三层结构、5 小时窗口、加油包）：<https://www.kimi.com/code/docs/kimi-code/membership.html>
- Kimi Code – 错误参考（401/402/403/429/400/500 全表、两体系不通用）：<https://www.kimi.com/code/docs/kimi-code/error-reference.html>
- Kimi Code – 最新动态（K3/K2.8 发布记录、128k 压缩输出上限、Anthropic 协议支持）：<https://www.kimi.com/code/docs/kimi-code/whats-new.html>
- Kimi Code 控制台（API Key 与额度管理）：<https://www.kimi.com/code/console>
- MoonshotAI/Kimi-K3 官方仓库（架构规格、基准全表、preserved thinking、quickstart）：<https://github.com/MoonshotAI/Kimi-K3>
- Kimi 开放平台（按量付费体系，`kimi-k3` 模型，与 Kimi Code 不通用）：<https://platform.kimi.ai>
- Kimi K3 技术博客：<https://www.kimi.com/blog/kimi-k3>

> 领域作业规程说明：第 9、10 章中 BMC 工程实践与 A 股交易规则/口径清单（T+1、分板块涨跌停幅度、复权、报告期 vs 公告日、point-in-time 等）为领域专家经验层，不出自上述文档站；使用前请按实际标的与最新交易所规则校验（新股、退市整理期等特殊证券的规则随监管调整）。第 5.0 节实测记录为编制时点（2026-09-15）对 `https://api.kimi.com/coding/` 端点的直接验证结论，服务端行为可能演进，以官方文档最新口径为准。
