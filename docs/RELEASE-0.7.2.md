## 简体中文
首次历史分析不再每次只处理六个对话。现在会自动连续分批处理全部可读取、未排除的历史对话及长对话的后续片段，显示进度，支持暂停与断点续接。已有分析结果保留；成功处理的消息不重复分析。首次完成后仍按设置的频率检查变化，网页采集仍只读取已加载内容。

## English
The initial history scan now automatically drains all readable, non-excluded conversation batches, including subsequent chunks of long conversations, without waiting for another scheduled check. Progress, pause and resumable checkpoints are supported. Existing results are retained and completed messages are not analyzed again. Subsequent checks follow the configured interval; web capture remains limited to loaded messages.

Validation: initial queue beyond six conversations, long-conversation chunks, unchanged-history no-call, failure checkpoint resume, pause; existing incremental/API/relay and subscription argument tests. Tests use mocked analysis and incur no model charges.
