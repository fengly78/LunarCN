# 月光与原版 Lunar 功能对照

盘点日期：2026-11-12。原版源码基准为 `06950e25747159c81f501a5e4477374abb1d779a`（6.11.3），本次远程 master 查询与该提交一致。月光当前代码版本为 0.6.1。

目标是逐项支持原版的显示器控制能力。用户已确认先支持当前 Apple Silicon Mac；Intel 不纳入当前阶段验收。下表的“待实现”是开发范围，不代表已有对应按钮或控制能力。

本独立仓库不包含原版工程；表中的 `Lunar/...` 路径指[原版基准源码](https://github.com/alin23/Lunar/tree/06950e25747159c81f501a5e4477374abb1d779a)。

## 功能清单与验收条件

| 编号 | 原版能力 | 月光状态 | 原版源码证据 | 验收重点 |
| --- | --- | --- | --- | --- |
| M01 | 内建屏亮度 | 本机已实测；0.6.0 改为拖动即调节 | `Lunar/Control/AppleNativeControl.swift` | 实际读写、回读、恢复原值；0.2.1 已修正 Apple Silicon 接口 |
| M02 | 外接屏硬件亮度、对比度 | 已实现；0.6.0 亮度拖动即调节，按 UUID 合并目标；Dell 亮度读写及恢复已实测，对比度写入待验收 | `Lunar/Control/DDCControl.swift` | 实际范围、写入确认、原值恢复、不支持处理 |
| M03 | 显示器音量、静音 | 0.3.0 已接入；Dell 音量可读、写入未通过，静音无有效返回 | `Lunar/Control/DDCControl.swift` | VCP 0x62 与 0x8D；区分连续值范围与静音枚举，兼容枚举最大值为零；定位硬件写入限制 |
| M04 | HDMI／DP／USB-C 输入源切换、自定义输入值 | 待实现 | `Lunar/DDC/DDC.swift`、`LunarShortcuts/LunarShortcuts.swift` | 切换前有可见恢复入口；发送成功与目标输入生效分别反馈 |
| M05 | 每屏最小／最大值、锁定、亮度对比度联动 | 0.4.0 实现每屏亮度范围保存；锁定和联动待实现 | `Lunar/Data/Display.swift` | 用户限制与硬件范围共同生效，按 UUID 保存 |
| M06 | 平滑过渡、多屏联动、鼠标所在屏幕控制 | 待实现 | `Lunar/Control/DDCControl.swift`、`Lunar/Data/Hotkeys.swift` | 限流、取消旧任务、热插拔时禁止串屏 |
| M07 | Apple 外接屏原生控制 | 待实现，需对应设备 | `Lunar/Control/AppleNativeControl.swift` | Studio Display、Pro Display XDR、LG UltraFine 等分别探测及验证 |
| M08 | RGB 硬件增益、颜色重置 | 待实现，需显示器支持 | `Lunar/Control/DDCControl.swift` | 各通道范围、原值保存与恢复 |
| U01 | 原生菜单、滚轮调节、菜单密度、OSD | 部分实现 | `Lunar/SwiftUIViews`、`Lunar/Views/OSDWindow.swift` | 当前菜单栏按钮只打开控制窗口，完整交互及 OSD 尚未实现 |
| K01 | 自定义快捷键、系统亮度／音量键及触控栏 | 待实现 | `Lunar/Data/Hotkeys.swift`、`Lunar/AppDelegate.swift` | 注册冲突、所需权限、跨应用调用、目标屏选择；此前未触发的恢复快捷键已移除 |
| A01 | Sync：跟随内建屏或指定源屏 | 0.5.0 实现外接屏跟随内建屏百分比；指定其他源屏与校准曲线待实现 | `Lunar/Modes/AdaptiveMode.swift`、官方 Pro 说明 | 每屏开关、范围、分步与防抖；内建屏关闭时暂停，源恢复后继续；写入失败暂停，手动重试；校准曲线和其他源屏待补 |
| A02 | Sensor：内置／外置环境光传感器 | 待实现，需可读传感器 | `Lunar/Modes/SensorMode.swift.secret`、`Lunar/ALS` | 内外传感器分别适配，断连、过期读数、异常值处理 |
| A03 | Location：根据太阳位置调节 | 待实现 | `Lunar/Data/Geolocation.swift`、`Lunar/Utils/Solar.swift` | 定位或手填坐标，时区、极昼极夜、平滑过渡 |
| A04 | Clock：时间、日出、中午、日落计划 | 待实现 | `Lunar/Views/Schedule.swift`、官方 Pro 说明 | 跨午夜、时区变化、错过计划、唤醒恢复和手动覆盖 |
| A05 | 自动选模式、自适应暂停、学习曲线 | 待实现 | `Lunar/Modes/AdaptiveMode.swift`、`Lunar/Data/Display.swift` | 规则优先级与手动调整不互相覆盖，算法独立设计并测试 |
| P01 | 多屏预设、快捷键预设 | 0.4.0 实现每屏一份预设；多屏场景与快捷键待实现 | `Lunar/Data/Presets.swift` | UUID 匹配、离线屏跳过、部分失败、保存与删除 |
| P02 | 前台应用／窗口触发预设或偏移 | 待实现 | `Lunar/Data/AppException.swift`、`Lunar/Modes/ManualMode.swift` | 应用切换、窗口迁移、退出恢复、多屏规则冲突 |
| B01 | 不合盖关闭内建屏及恢复 | 本机已实测 | 原版 BlackOut／断开入口、`Lunar/Data/CLI.swift` | 关闭后 active/online 为 0；限时确认、按钮／CLI／异常退出恢复已测 |
| B02 | Auto BlackOut：连接外接屏后自动关闭内建屏 | 待实现 | `Lunar/Utils/DisplayController.swift`、官方主页 | 首次确认、用户退出、拔线恢复、唤醒后避免反复开关 |
| B03 | 外接屏 BlackOut、断开／重连、只保留一屏 | 待实现 | `Lunar/Data/CLI.swift`、`LunarShortcuts/LunarShortcuts.swift` | 至少保留可见屏，退出恢复；区分断开、黑屏和电源关闭 |
| B04 | DDC 待机／关机 | 待实现，需显示器支持 | `Lunar/Control/DDCControl.swift`、官方 Pro 说明 | 部分设备关机后不能经 DDC 唤醒，必须明确恢复方式 |
| L01 | DDC 失败后的 Gamma／遮罩软件调光 | 待实现 | `Lunar/Control/GammaControl.swift`、官方 FAQ | 硬件亮度与软件调光分别说明，多应用兼容、退出及异常恢复 |
| L02 | Sub-zero：低于硬件最小亮度继续变暗 | 待实现 | `Lunar/Data/Display.swift`、官方主页 | 硬件／软件衔接、避免不可恢复全黑、热插拔与睡眠恢复 |
| L03 | XDR／HDR 增亮、Full Range、Auto XDR | 待实现，需硬件与系统支持 | `Lunar/Data/Display.swift`、`Lunar/SwiftUIViews/HDRSettingsView.swift` | EDR/HDR 能力、面板限制、热与电源约束、恢复 SDR；EDR 头部空间不能直接等同于 1600 nits |
| L04 | FaceLight 暖白补光 | 待实现 | `Lunar/Data/CLI.swift`、官方 Pro 说明 | 覆盖窗口、亮度／对比度协同、退出和原值恢复 |
| L05 | Night Mode：低白点、暖色、对比度优化 | 待实现 | `ReleaseNotes/6.5.0.md`、`Lunar/Data/CLI.swift` | 颜色配置保存恢复，与 HDR、Night Shift、True Tone、Gamma 软件兼容 |
| L06 | Cleaning Mode：屏幕与键盘清洁 | 待实现 | `ReleaseNotes/6.1.5.md`、`Lunar/Data/CLI.swift` | 输入拦截权限、独立超时恢复、可靠紧急退出，禁止无恢复途径的输入锁定 |
| D01 | 分辨率、刷新率、HiDPI、旋转 | 待实现，需设备支持 | `LunarShortcuts/LunarShortcuts.swift` | 枚举能力、倒计时确认、失败回滚；不假定所有面板可旋转 |
| D02 | 主屏、镜像、位置排列、交换及布局恢复 | 待实现 | `LunarShortcuts/LunarShortcuts.swift` | 不同缩放、离线屏、多屏回滚，保存及至少一屏可见 |
| D03 | Apple 参考模式、HDR 开关、Sidecar 操作 | 待实现，需对应系统／设备 | `LunarShortcuts/LunarShortcuts.swift` | API 探测与真机验收；HDR 开关和 XDR 增亮分别验收 |
| I01 | CLI：查询、读写、原始 DDC、事件及预设 | 部分实现 | `Lunar/Data/CLI.swift` | 当前只有自检和内建屏恢复；后续补目标选择、JSON、错误码与事件 |
| I02 | macOS 快捷指令／App Intents | 待实现 | `LunarShortcuts/LunarShortcuts.swift` | 使用共享控制层，验证安装后系统发现和真实调用 |
| I03 | 局域网 DDC／Raspberry Pi 控制 | 待实现，需网络控制设备 | `Lunar/Control/NetworkControl.swift` | 显式配置目标、认证、超时、断连及实际服务端验收 |
| I04 | 外置传感器协议、固件安装 | 待实现，需传感器 | `Lunar/ALS`、`Lunar/Controllers/ALSInstallViewController.swift` | 协议、用户提供的设备与网络参数、刷写失败恢复 |
| S01 | 设置保存、开机启动、诊断、版本更新 | 部分实现 | `Lunar/Data/DataStore.swift`、`Lunar/Utils/LoginServiceKit.swift`、`Lunar/AppDelegate.swift` | 已提供 UUID 设置保存、单实例、本机 DMG／ZIP、自检及临时签名；登录启动和自动更新待补 |
| S02 | Intel、不同接口、扩展坞与其他显示器兼容 | 当前验收目标为 Apple Silicon；Intel 留待后续 | `Lunar/DDC/DDC.c`、`Lunar/DDC/DDC.swift`、官方 FAQ | 实际硬件矩阵，本机通过不能推广为全设备通过 |

## 实现顺序

1. 基础手动控制：音量、静音、输入源、每屏范围与设置保存、颜色、快捷键和媒体键。
2. 多屏自动化：Sync、Clock、预设、应用规则、Auto BlackOut；共用队列、能力检查和手动接管策略。
3. 调光与场景：软件调光、Sub-zero、外接屏关闭、FaceLight、Night Mode、Cleaning Mode；先具备恢复保护再验收。
4. 显示配置与系统入口：分辨率、布局、镜像、完整 CLI、App Intents、登录启动及独立发布。
5. 硬件相关能力：传感器、Location、网络 DDC、XDR/HDR；可与前面交叉推进，设备与权限验收分别记录。Intel 兼容另列后续阶段，不扩大本轮已确认的 Apple Silicon 范围。

每项同时具备控制实现、中文入口、错误处理、匹配测试和必要的硬件验收后，才能标为“本机已实测”。请求提交、API 返回成功或界面有按钮，均不能单独当作功能完成。当前不声明与原版完整等价。

## 公开资料与源码边界

- [官方主页](https://lunar.fyi/)：功能分类、硬件控制及系统入口。
- [官方 Pro 说明](https://lunar.fyi/pro)：四种自动调光模式、补光、XDR、BlackOut 变体。
- [官方 FAQ](https://lunar.fyi/faq)：DDC、Gamma、端口与显示器限制。
- [官方快捷指令](https://lunar.fyi/shortcuts)：布局、HDR、输入源和清洁场景。
- [官方传感器说明](https://lunar.fyi/sensor)：协议、硬件与固件安装。

原版部分模式及必要文件只有 `.secret` 加密副本。源码核对包含公开入口、协议、数据结构和界面绑定，不代表已读取加密算法。月光使用公开接口独立实现对应行为。

## 已知验收缺口

本机已验证内建亮度、内建屏停用与恢复、外接屏亮度／对比度读取；0.4.0 当前 Dell 连接亮度 65 → 64 → 65 已读回确认并恢复。真实拔线、合盖、睡眠唤醒、其他显示器、外置传感器、网络 DDC 设备以及各项新增能力的硬件测试仍需逐项补齐。将来扩展 Intel 时需单独验收。

0.3.0 音频测试：DELL U3225QE 返回音量 `current=50, maximum=100`；经应用请求 51% 和 55% 后，读回仍为 50%，应用正确报告未确认目标值。静音读取没有返回有效的 1/2 枚举，因此界面未提供静音开关。不能据此认定所有该型号、所有连接方式或全部 DDC 音频均不支持；原因尚需进一步定位。测试结束时音量读回为原始的 50%，未声称该设备音量写入已通过。

0.4.0 将写入未确认与传输失败分别处理；未确认的项目在本次运行内暂停写入，手动允许重试后才恢复操作。UUID 变化后视为新设备，不自动沿用旧连接设置。亮度范围和每屏单份预设具备持久化、边界及损坏记录保护自检，不自动执行启动预设。

0.5.0 跟随亮度本机验收：Dell 从 3% 分步到约 42%；重启开关保留；未应用的对比度草稿未被轮询覆盖。关闭内建屏前先取消任务，关闭后 active/online 为 0，连续三次外接屏亮度读回保持 13%，自动跟随显示暂停。测试结束关闭跟随并恢复 Dell 原始 3%，保持内建屏关闭。默认关闭；旧版设置缺少此字段时按关闭处理。未测试真实环境光变化、睡眠唤醒和多台外接屏。

0.6.0 实时亮度验收：Dell 滑块 3% → 8%，实际拖动至 12% 再回到 3%，无需应用按钮；对比度草稿未写入。内建屏直接设置 43% 后由独立系统接口读回确认，并精确恢复原始 0.41598325967788696。显示值回跳问题已修正为直接读取最新目标／设备状态。目标合并、取消、最终值和失败保护自检通过；多台实机同时拖动和真实睡眠唤醒仍未验收。
