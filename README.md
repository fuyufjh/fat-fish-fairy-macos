# 小肥鱼 · FatFishFairy for macOS

受 [vczh/FatFishFairy](https://github.com/vczh/FatFishFairy) 启发的原生 macOS 桌面版。SwiftUI + AppKit，无第三方运行时、无命令行产品。需要 macOS 14 或更新版本。

## 启动

构建好的应用在 `dist/FatFishFairy.app`，可以直接双击。关闭聊天窗口后，桌面小鱼与菜单栏仍继续运行；通过菜单栏或 `⌘Q` 完全退出。

一键编译并生成 DMG（只需 Apple Command Line Tools；未安装时先执行 `xcode-select --install`）：

```sh
./build.sh
```

输出为 `dist/FatFishFairy.app` 和 `dist/FatFishFairy-1.0.0-arm64.dmg`（Intel Mac 上后缀为 `x86_64`）。打开 DMG，将应用拖到 Applications，然后推出磁盘映像，从「应用程序」启动。安装包不包含 `.secret`、本地对话、记忆或导入的主题。

```sh
./build.sh --app-only                 # 只生成 .app，兼容旧入口 ./scripts/build.sh
APP_VERSION=1.0.1 ./build.sh           # 自定义版本号
./build.sh --help
```

脚本可从任何工作目录调用，先在临时目录构建并验证签名、DMG 完整性，全部成功后替换输出；失败时保留旧产物。`dist/` 已被 Git 忽略。

默认使用本机 ad-hoc 签名，尚未 Apple 公证；当前构建针对本机架构。若有 Developer ID，可设置 `CODE_SIGN_IDENTITY='Developer ID Application: 你的名称 (TEAMID)'` 指定签名身份，公证仍需自行完成。

## 配置模型连接

打开「设置 → 模型连接」，填写 API Key 后点击「保存连接配置」。

| 选项 | 默认值 |
| --- | --- |
| Base URL | `https://api.deepseek.com` |
| Model | `deepseek-flash` |
| API Key | 空 |
| thinking（高级选项） | `disabled` |
| reasoning_effort（高级选项） | `none` |

Base URL 支持官方地址、带 `/v1` 的兼容服务地址或完整 `/chat/completions` 端点。服务及模型需要支持图片输入、JSON 回复和所选思考参数。`none` 关闭思考；`low/high/max` 开启思考并指定强度。开启思考时默认选择 `high`。

配置点击保存后才生效，会取消当前请求。API Key 使用普通密码输入框，随其他配置保存到本机 `state.json`（文件权限 `0600`），重启后可直接编辑；清空输入框并保存即删除密钥。不使用钥匙串，配置文件中的密钥为明文。

应用不读取 `.secret`、环境变量或旧版钥匙串中的密钥。升级后请在 UI 中填写一次。旧的聊天、记忆、形象和观察设置继续保留。

## 桌面使用

- 拖动小鱼改变位置，双击打开聊天，右键打开菜单；位置跨重启保存，并在显示器改变时回到可见范围。
- 默认暂停自动观察。在「设置」授权屏幕录制后，可「看一眼屏幕」或开启自动观察，间隔可选 30 秒、1 / 2 / 5 分钟。
- 默认观察所有显示器，也可关闭该选项，只观察主显示器。截图排除本应用窗口，缩放至最长边 1440 像素后发往所配置的 API 服务，多张截图合并为一条回应。
- 锁屏、休眠和会话切换时取消当前请求并暂停；恢复后继续。请求串行执行，可取消；自动观察失败时退避重试，最长 5 分钟。
- 点击图片按钮附图聊天；支持 PNG、JPEG、WebP、GIF（首帧）及 HEIC，最大文件 32 MB，发送前转换为 JPEG。
- 小鱼的气泡 25 秒后收起；完整回复保留在聊天中。屏幕无新鲜事情时，模型可以选择安静。
- 用户主动分享的偏好可成为长期记忆；屏幕观察不会写入长期记忆。「小鱼的记忆」中可单条移除。删除记忆不会删除原聊天文本。

## 桌面形象与图标

只保留「蓝色小肥鱼」（原「萝莉小妹抖」），包含 10 组动作、34 张动画帧和角色性格文件。升级后旧形象选择统一切换为此角色，聊天与记忆保留。不再提供其他形象和导入入口，仍可调整桌面大小。

动画位于 `Sources/FatFishFairy/Resources/Themes/loli_maid/`。App 图标源文件为 `Assets/AppIcon.png`，构建脚本自动生成各尺寸 ICNS；无需依赖下载目录。

## 本地数据与隐私

数据在 `~/Library/Application Support/FatFishFairy/`：

- `state.json`：设置、位置、最近 200 条消息和最多 60 条记忆；文件权限为 `0600`。
- `Themes/`：导入的角色素材。
- `last-request.json`：最近一次模型请求的图片数量、结束原因、回复字节数与解析结果；不含截图、回复正文或密钥。格式异常最多自动重试一次，沿用同一批截图。

截图和附图只用于当前请求，不写入聊天文件。观察时截图会传给所配置的 API 服务，聊天时会发送最近 16 条上下文和记忆；使用其 API 会产生账户费用。关闭自动观察仍可主动发起聊天或一次观察。截图内容作为不可信上下文传入，不作为系统指令。

若本地状态文件损坏，应用会提示并保留原文件，禁止覆盖；备份并修复或移走该文件后重启即可。

## 验证

```sh
./scripts/test.sh
# 可选：真实 API 测试，仅发送测试文字和纯色合成图，不截屏
FATFISH_TEST_API_KEY=你的测试密钥 FATFISH_LIVE_TEST=1 ./scripts/test.sh
```

测试覆盖 UI 配置默认值及旧数据迁移、API Key 本地保存、重启恢复和清空、自定义请求地址与思考参数、模型 JSON / 安静回复、本地数据重启恢复、损坏数据保护、权限和主题索引校验。独立测试程序无需完整 Xcode / XCTest；它不是命令行版小肥鱼。

屏幕录制需要 macOS 系统授权。首次授权后如系统提示重启应用，请退出重开；重新签名构建有时也需要重新授权。

## 与原版的区别

原版是 Windows / GacUI；这里用 macOS 原生窗口、菜单栏和 ScreenCaptureKit 重写。识图与性格回应合并为一次多模态请求，减少延迟；记忆采用本地结构化偏好列表，不包含原版通用记忆文件工具。没有实现 FatFishCli。
