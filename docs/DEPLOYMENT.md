# Optional hosted service / 可选内置服务

The public app-funded service is **not open**. This document describes the private pilot relay for operators; ordinary users do not need to deploy a server or fill an analysis address.

## Model and cost policy

`src/hosted-policy.json` pins mainland accounts to `deepseek/deepseek-v4-flash-0731`. The server validates the selected ID before calling the provider. Editing only the client cannot enable more expensive models on the hosted service.

The relay applies `provider.sort="price"` and input/output `max_price` values from that policy, in USD per million tokens. See [OpenRouter provider routing](https://openrouter.ai/docs/guides/routing/provider-selection). Fallbacks are disabled; no qualifying route means failure. This is a per-token price ceiling, **not a total budget**.

可选推理关闭；默认每用户每天最多 60 次请求、300000 输入字符，全服务最多 2 个并发。失败不自动重试，计数在调用前预留。仍须在 OpenRouter 配置专用 Key 的美元消费上限，并在开放公众使用前实现整体预算及防滥用。

## Operator configuration

Use Node.js 22+ to run `src/server.js`. Configure environment variables on the server, never in the desktop installer or public repository:

```text
TODO_API_KEY=YOUR_SERVER_ONLY_OPENROUTER_KEY
TODO_CLIENT_TOKENS={"tester":{"token":"GENERATE_A_DISTINCT_RANDOM_TOKEN_AT_LEAST_32_CHARACTERS","edition":"mainland"}}
TODO_DATA_DIR=/var/lib/conversation-todo
TODO_CONCURRENCY=2
TODO_DAILY_REQUESTS=60
TODO_DAILY_CHARS=300000
PORT=18788
```

Token values above are placeholders. Use independent random, revocable credentials; never a shared public token. The relay listens on loopback only. Deploy it behind a properly secured HTTPS reverse proxy before public access; comply with applicable hosting and provider requirements.

The client may read a public `service.json` containing `{"analyzeUrl":"https://YOUR_HOST/analyze"}`. That file must never contain an OpenRouter key or a shared client secret. It only presets an address; it does not implement account creation or automatic authorization.

The pilot currently uses operator-issued client tokens encrypted with Windows DPAPI. Automatic anonymous identity issuance, public onboarding, a global budget, and service availability monitoring are **not implemented**. Do not distribute private SSH access, loopback pilot addresses, or operator tokens to customers.

The server persists daily counters, not conversation bodies. OpenRouter and actual model providers receive necessary prompt text. A mainland edition does not guarantee China-only processing. Official vendor terms and subscription/CLI access remain separate from this relay.

Current policy ceilings: $0.00869/M input and $0.27/M output, based on a parameter-compatible provider endpoint checked on 2026-10-10. A live empty-input synthetic inference succeeded under these caps. The displayed directory minimum alone is insufficient to establish a working JSON-compatible route.
