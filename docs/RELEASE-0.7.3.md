## 简体中文
修复原文依据校验失败导致整批历史分析停止的问题。空白、换行和全角字符差异会匹配回真实原文。引用不匹配时，仅对出问题的对话修正一次；仍失败则保留断点，并继续其他对话。不会接收凭空生成或拼接的依据。引用修正调用会消耗当前分析服务的额度。

## English
Fixes source-quote validation failures stopping the entire history batch. Whitespace, line breaks and full-width character differences map back to the original text. Invalid quotes receive at most one targeted correction call. Persistent failures keep their checkpoint while other conversations continue. Fabricated and cross-message quotations remain rejected. Correction calls consume the selected service's quota.

Validation: normalized original excerpts including Unicode; fabricated/cross-message quote rejection; single targeted repair; persistent failure isolation and checkpoint resume; initial history/pause/resume, incremental/API/relay, subscription arguments tests. Tests use mocked analysis.
