# v0.7.0 · 中国大陆预览版 / Mainland China Preview

## 简体中文

下载 `ConversationTodo-Mainland-Setup-0.7.exe` 即可安装。支持 Windows 10 / 11 x64；内置 Node.js，无需单独装运行环境或手动运行脚本。

本项目的应用代码、UI、打包配置和全部文档（包括本发布说明）均由 AI 生成并迭代，作者提出需求和反馈；第三方依赖由各自作者开发。

- 被动读取本机 Codex / Claude Code 对话，提取下一步并按优先级显示。
- Chrome 网页采集支持已打开、已加载的 ChatGPT / Claude 消息；扩展需按设置中的引导确认加载一次。
- 用户承诺自动进入待办，AI 建议待确认；支持完成、取消、忽略、暂停、排除、原文依据和托盘。
- 默认每 30 分钟检查，只有变化才分析；历史分批处理，避免反复上传全部对话。
- 当前只发布大陆版。作者付费的内置服务锁定 `deepseek/deepseek-v4-flash-0731`，客户端列表和后台权限共同限制型号，并限制供应商路由单价。

**公共内置 API 尚未开放。** 下载者请使用自己已安装并登录的 Codex / Claude Code，或自己的 API Key。必要文字会发送至选定云端服务，初次历史分析会消耗额度。

已检查增量逻辑、密钥加密、设置保存、型号限制、鉴权、配额、价格参数、私有后台拒绝高价型号、一次真实合成推理，以及安装／卸载。安装检查使用隔离模式，未替换现有 Chrome 注册和快捷方式。Chrome 真实页面和更多电脑仍待验证。安装包未签名。

详细要求、隐私及限制：[简体中文说明](https://github.com/Jarawlith/conversation-todo/blob/main/README.md)。校验文件为 `SHA256SUMS.txt`。

## English

Install `ConversationTodo-Mainland-Setup-0.7.exe` on Windows 10 / 11 x64. Node.js is bundled; no separate runtime installation or manual scripts are needed.

All project-specific application code, UI, packaging configuration, and documentation—including these release notes—were generated and iterated by AI. The author supplied requirements and feedback. Third-party dependencies retain their own authorship.

This mainland-only preview passively extracts prioritized actions from retained local Codex / Claude Code conversations, with optional Chrome capture of opened ChatGPT / Claude chats. Explicit commitments become tasks; AI suggestions require confirmation. It supports evidence, completion/cancellation, pause, exclusion, tray behavior, and incremental checks every 30 minutes by default.

The author's hosted service is pinned to `deepseek/deepseek-v4-flash-0731`, enforced by both client and server, with provider price caps. **The public hosted API is not open.** Use your own authenticated official CLI or API key. Analysis sends necessary text to the selected cloud service and consumes its quota. Chrome extension loading requires a one-time user action.

Checks covered incremental processing, settings, encryption, exact model restrictions, relay authentication/limits, price parameters, live rejection of a higher-priced model, one live synthetic inference, and isolated installation/uninstallation. Real Chrome pages and broader device compatibility need more testing. The installer is unsigned.

[English README](https://github.com/Jarawlith/conversation-todo/blob/main/README.en.md) · Verify downloads with `SHA256SUMS.txt`.
