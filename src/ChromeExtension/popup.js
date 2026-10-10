chrome.runtime.sendNativeMessage('com.codextodo.capture', { type: 'status' }, async result => {
  const error = chrome.runtime.lastError?.message;
  const saved = await chrome.storage.local.get('lastStatus');
  document.getElementById('status').textContent = error ? '未连接本机组件：' + error : result?.paused ? '已暂停采集和分析' :
    '本机连接正常；打开聊天页面后自动采集。' + (saved.lastStatus?.at ? ' 最近采集：' + new Date(saved.lastStatus.at).toLocaleTimeString() : '');
});
