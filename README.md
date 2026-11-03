# 启航桌面 · Android + Godot

安卓大屏 3D 车控桌面底座。原生 Kotlin 负责桌面界面、应用启动与状态服务，Godot 负责车辆场景和部件交互。本版本使用本地模拟车辆接口；不会向真实车辆发送控制请求。

## 目前可以体验

- 全屏横向 3D 车辆与摄影棚环境；底部保留首页、应用和诊断入口；长按首页弹出车控操作面板。
- 从原厂 Kanzi 资源恢复的车辆几何模型，保留门窗、尾门、车轮等命名部件。
- 手指拖动旋转、双指缩放；鼠标滚轮也可缩放。
- 点击车身部件或车控面板按钮，体验前门、车窗、尾门和灯光变化。
- 门窗灯、三种车色和视角合并在同一个底部车控浮层；没有复位按钮。
- 旋转、缩放或切换视角后，停止操作 12 秒平滑回到默认镜头；门窗、灯光与车色状态保留。
- 公共渲染器原版车漆、车身 AO、原接地阴影、地面反射与夜间背景；隐藏前后牌照框。
- 去掉左上品牌／模拟模式和右上场景就绪标签；启动使用高斯模糊车辆背景与加载圈，首帧完成后淡出。
- 模拟指令的等待、确认、状态回传和日志。
- 日夜跟随系统配置；保持源环境能量，切换主题背景和原夜间效果。
- 跟随屏幕 VSync，不再限制为30 FPS；拖动使用现有项目的旋转速度和阻尼。
- 显示已安装应用并启动；诊断页可分享交互日志。

GLB 中的几何来自已提取的 `Launcher.apk/assets/vehicle_c236_ica2.kzb`。几何已清理退化面；材质采用 Tesla App 同源摄影棚 IBL、公共渲染器原车漆参数和本车原始 AO，交互动画在 Godot 中重新制作。尚未迁移完整原厂 Kanzi 贴图、着色器和动画曲线。`godot/assets/模型来源.json` 记录来源和几何处理范围。

## 文件结构

```text
app/src/main/java/dev/qihang/launcher/
  MainActivity.kt         Android 入口与 Godot 容器
  LauncherScreen.kt       原生桌面、应用列表和诊断界面
  VehicleBridge.kt        Kotlin 与 Godot 的双向桥接
  VehicleState.kt         状态结构与 VehicleGateway 接口
  MockVehicleGateway.kt  本地模拟实现
  IconView.kt             原生绘制图标
godot/
  project.godot
  main.tscn
  CarScene.gd             场景、部件分组、相机与交互
  SharedVehicleLighting.gd 共享摄影棚 IBL 与材质转换
  SharedStudio.gd        源地面反射、夜间背景与原车接地影
  shaders/               车漆、玻璃、金属照明及连续地面
  assets/studio-*        同源环境图、预滤波 cubemap 与来源记录
  assets/car.glb          恢复后的几何模型
```

`VehicleGateway` 是后续真实车辆适配器的接入点。渲染场景只接收状态、发出操作意图，原厂车辆属性编号和权限判断应放在 Kotlin 适配层。

## 构建

依赖：JDK 17 或兼容版本、Android SDK Platform 35、构建工具，以及可访问 Gradle/Maven 的网络。Godot 运行库固定为 `4.5.1.stable`，AGP 为 `8.7.3`。

在项目目录创建本机 `local.properties`，写入 SDK 路径，例如：

```properties
sdk.dir=/path/to/Android/sdk
```

运行：

```sh
./gradlew :app:assembleDebug
```

输出为 `app/build/outputs/apk/debug/app-debug.apk`。APK 支持 `arm64-v8a` 和 `x86_64`，最低 Android 11。首次构建需下载 Godot Android 库等依赖；没有在源码包中重复附带这些运行库。

Godot 编辑器不是构建 Android 壳的必需依赖。场景脚本与原始 GLB 直接作为 assets 打包；需要编辑、预览或做脚本检查时，使用 Godot 4.5.1 打开 `godot/project.godot`。

`android-runtime/` 中保留了导出的项目设置及空的全局脚本类缓存。修改 `project.godot` 后，用匹配版本的编辑器执行 `GODOT_BIN=/path/to/Godot scripts/prepare-scene.sh`，再构建 APK。修改普通场景脚本后直接重新构建即可。

## 安装与查看

可以将 debug APK 拖入安卓模拟器安装；也可以运行：

```sh
adb install -r app/build/outputs/apk/debug/app-debug.apk
adb shell am start -n dev.qihang.launcher/.MainActivity
```

应用名称为“启航桌面”。它声明了 HOME 入口，但安装后不会自行替换默认桌面。建议先作为普通应用查看；默认桌面切换是否可用取决于目标车机策略。

首轮体验建议使用横屏，分辨率 1920×1080、密度 240 或相近的显示配置。界面较窄时右侧面板可以滚动。

## 当前边界

- 车辆数据来自模拟器，诊断页会明确显示“未连接车辆”。
- 可以验证渲染、部件交互、原生／Godot 通信和应用切换；不能据此判断真实车辆权限已具备。
- 还没有接入原厂 CarCabinManager、CarPropertyManager、媒体会话、导航卡片或真实车况订阅。
- 门窗动画的转轴、行程和材质仍需结合实机视觉继续校准。
- 这个版本没有完整恢复原厂 UI 或实现车辆驾驶功能。

下一阶段先建立只读车辆适配器和可导出的服务诊断，再逐项接入能被验证的真实指令。

本轮已在 Android 16 / API 36 的 ARM64 模拟器中验证；渲染来源与适配范围见 `渲染与视角说明.md`。目标车机的 Android 11 环境仍需由用户后续安装验证，不能用较新模拟器的结果代替实机兼容性结论。

Godot 运行库遵循 MIT 许可证，见 [Godot 官方许可](https://godotengine.org/license/)。车模来源于用户提供镜像中提取的资源，几何来源与重建范围见模型来源记录。
