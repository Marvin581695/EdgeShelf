# 拾边 EdgeShelf

原生 macOS 侧边栏临时数据收纳工具。参考 [EdgeMark](https://github.com/Ender-Wang/EdgeMark) 的边缘停靠交互，为文本、图片和文件提供连续复制收藏、分类、Todo 与 Pin。

## 功能

- 连续按 `⌘C`（默认 2 次，可调整 2–5 次）收藏当前选中的文本、图片或文件
- 左右屏幕边缘触碰展开，支持自动收起、再次触边切换、Pin 保持展开、动画、宽度、显示器与角落排除配置
- 文本保存为独立 `.md` 文件，图片保存为 `.png`，文件保存原格式；索引与状态保存为可读 `index.json`
- 搜索、分类、Todo、完成状态、置顶、回收站、拖放收藏、手动剪贴板收藏
- 全局快捷键 `⌃⇧Space` 展开/收起
- 输入监控为 listen-only，不拦截或合成键盘事件；只有达到连续次数后才读取剪贴板

## 开发

需要 macOS 14+ 与 Swift 6。运行：

```bash
./script/build_and_run.sh
```

测试：

```bash
swift test --disable-sandbox
```

首次使用连续复制时，在设置或面板提示中授权「系统设置 → 隐私与安全性 → 输入监控」。资料库默认位于 `~/Library/Application Support/EdgeShelf`，可在设置中切换。
