# 测试与验证

## 运行测试

从仓库根目录运行宿主/库 GDScript harness：

```powershell
.\tools\Test-ContourShadows.ps1 -GodotExecutable 'D:\Dungeondraft\Dungeondraft.exe'
```

该脚本使用 Dungeondraft 自带的 Godot 3.4.2 Mono 引擎，在 `tests/.staged/` 创建隔离测试目录并使用 `--no-window` 运行，不打开地图。测试报告和日志也保存在该目录中。`-PrepareOnly` 只准备文件、不启动引擎；`-DirectEngine` 可跳过引擎副本。

打包与安装脚本的隔离模拟检查：

```powershell
.\tests\test_distribution_tools.ps1
```

它只在 `tests/.staged/` 中创建临时 ZIP 和模拟 mods 目录，不访问真实 Dungeondraft 安装。

GPU、Pathway 和增量橡皮擦的专用检查入口在 `tests/v3/Run-*.ps1`。这些检查需要 Dungeondraft 自带引擎；具体脚本参数和结果格式见相应 `.ps1` 与 `.gd` 源码。

## 覆盖范围

- 遮罩渲染：透明边缘、轮廓孔洞、渐变 Alpha、短投影、连续延展、模糊、尺寸上限和输入纹理不变性。
- 几何变换：地图坐标方向、旋转、平移、缩放、非均匀缩放与镜像。
- 来源轮廓：Sprite 帧、纹理区域和 AtlasTexture；Pathway 渐入、渐出、收尖以及原生点宽度。
- 擦除：笔刷线段和圆端、软硬度、局部坐标映射、源纹理不变、分帧 CPU 工作预算、GPU 合成、撤销及异步任务取消。
- 宿主生命周期：对象选择、路径选择、地图/楼层变化、节点清理、配方保存与恢复、单独参数和全局参数。
- 分发工具：安装包目录、可重复打包、已有安装备份与 `-WhatIf`。

## 已记录结果

2026-10-14 的 v0.3.0 功能版本验证记录：

| 验证项 | 结果 |
| --- | --- |
| 宿主与库 GDScript harness | 239/239 通过 |
| Pathway 捕获 | GLES2 20/20；GLES3 23/23 |
| CPU 增量擦除验收 | 31/31 通过，输出与完整回放逐像素一致 |
| GPU 擦除控制器 | 22/22 通过 |
| 分发工具模拟 | 14/14 通过；安装包含 8 个插件文件 |
| 隔离 Dungeondraft 原生输入 | Prop、Pathway、小笔刷与大笔刷 3/3；仅注入 Godot GUI 事件，未做物理鼠标验收 |
| GPU 阴影渲染中位数 | 128²/512²：GLES3 102/253 ms，GLES2 111/251 ms；相较旧 CPU 路径约快 2.2–5.7 倍 |
| 512² 大笔刷擦除 | 32 个采样点：GLES3 约 32 ms，GLES2 约 111 ms；与 CPU 参考的最大 Alpha 差 1 byte，RGB 差不超过 1 byte |

v0.3.1 只替换插件图标并改写文档，没有运行时代码变化；上表沿用 v0.3.0 功能版本的验收结果。测试用地图、原生截图、机器相关日志和生成报告未纳入仓库；可用上述脚本在本机重跑并生成新的报告。隔离验收使用专用 APPDATA 和地图副本，没有保存用户地图。

真实地图保存请使用 Dungeondraft 自带的 Ctrl+S 或保存按钮。bridge 的 `save_map` 只复制输入文件，不会序列化当前会话中的 `Global.ModMapData`。
