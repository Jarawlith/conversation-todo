## 简体中文
修复会话 ID 不匹配导致历史分析中断的问题。模型输入采用本批临时短编号，输出 schema 限制编号取值，再通过明确映射恢复真实会话 ID。遗漏或重复的会话只修正一次，仍失败保留断点；有效会话继续处理，不按结果位置猜测来源。

## English
Fixes conversation ID mismatches interrupting history analysis. Requests use batch-local short IDs constrained by the output schema, with explicit mapping back to real conversation IDs. Missing or duplicate conversations receive one targeted correction attempt; persistent failures retain their checkpoint while valid conversations continue. Results are never assigned by position.

Validation: constrained IDs, out-of-order reverse mapping, existing-task context preservation, wrong-ID repair, duplicate-ID isolation, failed checkpoint preservation, evidence validation, initial history/pause/resume and API/relay tests.
