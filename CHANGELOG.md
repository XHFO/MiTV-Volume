# 更新记录

## 0.6.0（源码已同步，安装包尚未公开发布）

当前源码对应应用 build 17，内置音频组件 0.3.6 build 10。

Build 17: stop presenting headphones/Mac styles as BuiltIn audio (0.5.0 always used Virtual). Coalesce stereo volume into one TV command revision and restore the 100ms connected poll floor so left-Control/host key glitches cannot become a rapid volumedown stream. Control Center may fall back to a generic speaker for headphones.

Build 16: limit the device-icon menu to display, speaker, headphones, TV and host Mac. Bluetooth, AirPlay and other fallback appearances are no longer offered as new choices; previously saved IDs remain readable until the user picks another style.

- 改为仅菜单栏操作，保留电视发现、输出选择、自定义名称、同步等待、信号源自动切换、登录自启和隐藏入口。
- 优化连续调节与直接设置百分比的响应：已确认生效的音量档位之间不再固定等待，延迟反馈时才补充回读。保留停止调整等待、最新目标优先及失效后丢弃旧请求的逻辑。
- 修复更新应用后遗留 ADB 服务导致信号源验证失败、音量控制暂停的问题。只在首次连接时重置应用独立的服务，并在恢复后重新采用电视实际音量。
- 加入由 Apple Icon Composer 制作的紫色声波应用图标，同时保留可编辑设计源文件。
- 设备图标菜单仅保留五种：显示器、扬声器、耳机、电视、本机 Mac。移除蓝牙、AirPlay 及其他回退项的新入口；旧保存值仍可读，不自动重置用户选择。
- 修复切换图标后控制中心显示为 Speaker / Headphones 的问题：设备名称和数据源标签均使用用户设定的名称，改名时通知观察者。
- 通过应用内原有授权流程更新内置音频组件，无需独立安装器。

验证：49 项 Swift 核心测试、真实 C++ 驱动入口与打包资源测试、菜单图标目录测试通过。
本机 macOS 27.0.1 已核对实际控制中心显示；USB、Thunderbolt、FireWire 回退为普通扬声器，
不作为新的独立外观展示。外置箱体音箱、HomePod 产品轮廓尚无可靠映射。
Intel 真机、完整信号源往返和长期稳定性验收仍未完成，详见 [验证范围](docs/VALIDATION.md)。

## 0.5.0（预发布）

首个公开版本，包含系统音量代理、电视自动发现、自定义设备名称、可配置同步等待、后台运行和登录自启。

新增读取电视主输入会话的自动输出切换：离开电脑输入后使用指定备用设备，返回后先读取电视音量再恢复代理。状态读取失败时暂停控制，避免误改游戏音量。

42 项 Swift 测试与 C++ 驱动入口测试通过；真实 Type-C 往返恢复、Intel 真机与长期运行仍待验证。应用尚未进行 Developer ID 签名和 Apple 公证。
