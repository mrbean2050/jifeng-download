# 第三方组件

这些程序作为独立子进程随 App 分发，不是疾风自有实现。

- **yt-dlp 2026.08.19**：官方 macOS 独立发行文件。主项目为 Unlicense；独立文件还包含第三方组件，完整清单见 `yt-dlp-THIRD-PARTY.txt`。上游：https://github.com/yt-dlp/yt-dlp/tree/2026.08.19 。对应上游源码归档随本次 Release 的 ThirdPartySources 包提供。
- **Deno 2.9.7**：官方 Apple Silicon 独立文件，MIT；包括 V8、Rust 等组件，各自许可证可在对应源码归档中查看。上游：https://github.com/denoland/deno/tree/v2.9.7 。官方源码归档随 ThirdPartySources 包提供。
- **FFmpeg 8.0.1**：使用未修改的官方源码编译，仅用于本地音画合并。未启用 GPL/nonfree 和外部媒体库，按 LGPL 2.1 或更新版本使用。原始源码、配置脚本随 ThirdPartySources 包提供。可替换 App 的 `Contents/Resources/Tools/ffmpeg` 为兼容构建；替换后原代码签名会失效。未禁止为调试 FFmpeg 修改而进行的逆向工程。上游：https://ffmpeg.org/releases/ffmpeg-8.0.1.tar.xz 。

公开发行当前为未公证测试版。工具均固定版本并在准备脚本中校验 SHA-256，不会在后台自行更新。
