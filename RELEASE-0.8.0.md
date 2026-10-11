# v0.8.0 · 本地语音记录 / Local voice capture

按住 F2 说出想法，松开后使用本机 SenseVoiceSmall 识别，确认或修改文字后保存为待办。支持普通话、粤语、英语及自动识别；语音设置允许更换快捷键。麦克风只在主动按键时录音。首次使用自动下载约 160 MB 模型，之后可离线使用，不产生转写 API 费用。下载需要访问 GitHub。

语音待办独立保存，扫描对话不会覆盖。录音只临时用于识别，取消不保存任务。每次录音最长 2 分钟。模型、录音、确认和持久化通过独立接口连接，后续可替换语音模型；请保存前核对识别文字。

下载 `ConversationTodo-Mainland-Setup-0.8.0.exe` 安装或升级；个人待办和设置保留。模型 gzip 是应用自动下载的资源，用户无需手动解压，不是第二个安装程序。当前仍为中国大陆预览版，软件提供的公共分析 API 尚未开放。

Hold F2 to record an idea, release to transcribe locally with SenseVoiceSmall, then edit and confirm before saving a task. Supports Mandarin, Cantonese, English and automatic detection; the shortcut is configurable. First use downloads a ~160 MB model from GitHub. Later recognition works offline without transcription API charges. Audio is transient; captured tasks survive conversation analysis. Maximum recording: two minutes. A model adapter interface keeps recognition replaceable.

Install or upgrade with the EXE; existing tasks and settings remain. The gzip asset is downloaded by the app automatically and is not a separate installer. Mainland preview only; the public hosted analysis service remains unavailable.

Validation: verified model downloads, corrupt-cache recovery, offline reuse, PCM conversion, silence handling and bounded inference; WPF capture confirmation/cancellation, full-text persistence, hotkey/language settings, native key conflicts, task priority/completion after analysis replacement; existing subscription/API settings regression; public Mandarin/Cantonese/English audio inference. Sample tests are not a general accuracy benchmark. Live microphone input still requires testing with the user's own device.

Built and documented by AI from the author's requirements. Third-party speech models and libraries were created by their respective authors; license notices are bundled.
