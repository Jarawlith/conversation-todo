## 简体中文
- Codex 模型改为下拉选择，优先读取本机官方模型目录，并保留自定义型号。
- Codex 推理强度可选，列表随模型支持范围变化；后台调用使用保存的选择。
- Claude 提供 Haiku、Sonnet、Opus、Fable 及具体版本下拉选项，保留自定义型号。
- 默认设置和已有任务保留。账号权限和官方客户端版本决定实际可用性；Fable 可能使用额外付费额度。
- 大陆内置服务仍锁定原有低价 DeepSeek 模型，内置服务尚未向公众开放。

## English
- Codex model dropdown uses the local official model catalog when available, with custom IDs supported.
- Select reasoning effort from the selected model's supported levels. Analysis uses the saved choice.
- Claude model dropdown includes Haiku, Sonnet, Opus, Fable and specific versions, with custom IDs supported.
- Existing tasks and settings are retained. Availability depends on account permissions and official client versions. Fable may bill additional usage credits.
- Mainland app-funded service remains pinned to the existing low-cost DeepSeek model and is not publicly available yet.

Validation: model selection and persistence UI tests; model-dependent effort test; CLI argument/default/validation tests; existing incremental/API/relay tests; Windows installer build. No paid model calls were made for these checks.
