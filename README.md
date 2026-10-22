# 轮廓投影 / Contour Shadows

[English](#english) · [简体中文](#简体中文)

## English

Contour Shadows is a GDScript mod for Dungeondraft. It creates editable, contour-based shadows for Props and Pathways. The source texture and pathway stay intact; the mod adds and manages its own shadow nodes.

### Features

- Create a short offset shadow or a continuous extruded shadow, with adjustable direction, distance, softness, opacity, and color.
- Work on the current floor, recorded selections, Props, and Pathways. Pathway fade and taper settings are included in the sampled silhouette.
- Choose global defaults or adjust recorded objects individually. Per-object overrides can be reset to the global values.
- Erase parts of a generated shadow with a brush. Brush diameter is 2–512 map pixels and hardness is 0–100%. Strokes are stored in source-local coordinates and saved with the map.
- Preview shadows in the editor, optionally follow source shape changes, undo the latest eraser stroke during the current editing session, and restore erased areas for selected sources.
- Use the same map-space shadow direction even when a source is rotated, scaled, or mirrored.
- Switch between English and Simplified Chinese without changing map data or restarting the mod.

### Quick start

1. Open **Effects → Contour Shadows / 轮廓投影**. Select **English** under **Language / 语言** at the top of the panel.
2. Choose **Select Objects**, select Props or Pathways on the current floor, then choose **Generate Selected**. Use **Generate Floor** to process the current floor.
3. Choose **Global** or **Per-Object** below **Shadow Parameters**. Per-Object mode applies changed fields to the recorded targets and leaves their other effective values alone.
4. To erase, generate the target shadows first, enable the eraser, set its size and hardness, then drag on the canvas. Press Esc or change tools to leave eraser mode.
5. Save the map with Dungeondraft’s **Ctrl+S** or Save button. Shadow settings and eraser strokes are stored in the map data.

Props show Dungeondraft’s native selection outline while the mod tool is active. Pathways do not have that outline; use the recorded target count in the panel to confirm them.

### Install

On first use, the interface follows Dungeondraft's active locale. Choose **English** or **简体中文** from **Language / 语言** at the top of the panel to override it. The choice is saved locally and does not change map data.

Download [contour-shadows-0.4.0.zip](dist/contour-shadows-0.4.0.zip), extract it, and copy the `contour_shadows` folder into Dungeondraft’s `mods` folder. The `.ddmod` file should be at `mods/contour_shadows/contour_shadows.ddmod`. Restart Dungeondraft after installation.

The repository also includes a PowerShell installer that preserves an existing installation in a timestamped backup:

```powershell
.\tools\Install-ContourShadows.ps1 -Destination 'D:\Dungeondraft\mods'
```

Close Dungeondraft before using the installer. See [TESTING.md](TESTING.md) for compatibility and validation notes. The mod targets Dungeondraft 1.2.0.0.

### Parameters

| Setting | Default | Range / behavior |
| --- | ---: | --- |
| Direction | 45° | 0–359° in map coordinates; 0° points right and 90° points down |
| Distance | 32 | 0–256 map pixels |
| Softness | 8 | 0–64 approximate map pixels; non-uniform source scaling uses the average scale |
| Opacity | 0.30 | 0–1 |
| Color | `#141519` | Default shadow color |
| Projection | Continuous | Short offset or continuous extrusion |
| Follow sources | Off | Periodically checks enabled targets within a limited per-frame budget |
| Preview | On | Hides or shows generated shadow nodes |
| Eraser diameter | 24 | 2–512 map pixels; saved in local settings |
| Eraser hardness | 70% | 0–100%; lower values give a softer brush edge |

### Limits and implementation

The mod handles Props with readable Sprite textures and Pathways sampled from their visible editor result. It does not infer shadows for walls, terrain, water, or ground decals, and it does not calculate sunlight or 3D occlusion. Large blur and extrusion work is GPU accelerated where available; bounded CPU paths handle smaller brush strokes and unsupported renderers. Performance varies with the GPU, source texture, and render backend; measurements are documented in [TESTING.md](TESTING.md).

Map settings, enabled targets, per-object overrides, and eraser strokes are stored in `Global.ModMapData` under `contour_shadows` (recipe version 2). Global UI defaults are stored in `user://contour_shadows/settings.json`. Use Dungeondraft’s own save command; the bridge `save_map` command does not serialize the active session’s `Global.ModMapData`.

To build the install archive from source, run:

```powershell
.\tools\Package-ContourShadows.ps1 -OutputPath 'C:\Temp\contour_shadows.zip'
```

The package script requires an absolute output path outside `mod/` and will not overwrite an existing file. See [DESIGN.md](DESIGN.md) for architecture and [TESTING.md](TESTING.md) for recorded validation.

## 简体中文

轮廓投影是面向 Dungeondraft 的 GDScript mod。它根据 Prop 的 Sprite 或 Pathway 的可见轮廓生成可编辑阴影。插件会创建并管理自己的阴影节点，不修改原始纹理或路径。

### 功能

- 支持短投影与连续延展，可调整方向、距离、柔化、不透明度和颜色。
- 支持当前楼层、已记录选择、Prop 与 Pathway；路径渐入、渐出和收尖过渡会纳入轮廓采样。
- 可切换全局默认值和对象单独调整；对象覆盖值可恢复为全局参数。
- 可用橡皮擦局部擦除生成的阴影，笔刷直径为 2–512 地图像素，硬度为 0–100%。笔画保存在源对象局部坐标，并随地图保存。
- 支持编辑器预览、可选的来源形状跟随更新、当前编辑会话中的上一步擦除撤销，以及恢复所选来源的擦除区域。
- 对象旋转、缩放或镜像时，阴影方向仍按地图坐标计算。
- 可即时切换简体中文与 English，语言偏好只保存在本机。

### 快速开始

1. 打开 **Effects → 轮廓投影**。
2. 点击 **选择对象**，在当前楼层选择 Prop 或 Pathway，再点击 **生成选中对象**。要处理整层时，点击 **生成当前层**。
3. 在“投影参数”标题下选择 **全局调整** 或 **单独调整**。单独模式只把改动字段应用到已记录目标，其他字段保留各对象当前的有效值。
4. 先生成阴影，再启用橡皮擦并设置大小与硬度，然后在画布上拖动。按 Esc 或切换工具可退出橡皮擦模式。
5. 使用 Dungeondraft 的 **Ctrl+S** 或保存按钮保存地图。阴影参数和擦除笔画保存在地图数据中。

轮廓投影工具活动时，Prop 会显示 Dungeondraft 原生选中边框。Pathway 没有这个边框，可通过面板中的目标数量确认选择记录。

### 安装

可在面板顶部切换简体中文或 English。语言偏好保存在本机，不会写入地图数据。

下载 [contour-shadows-0.4.0.zip](dist/contour-shadows-0.4.0.zip)，解压后将 `contour_shadows` 文件夹复制到 Dungeondraft 的 `mods` 文件夹。确认 `.ddmod` 位于 `mods/contour_shadows/contour_shadows.ddmod`，然后重启 Dungeondraft。

仓库提供 PowerShell 安装脚本；若目标位置已有插件，脚本会先将旧目录移到带时间戳的备份目录：

```powershell
.\tools\Install-ContourShadows.ps1 -Destination 'D:\Dungeondraft\mods'
```

运行安装脚本前请关闭 Dungeondraft。兼容性和验证记录见 [TESTING.md](TESTING.md)。插件面向 Dungeondraft 1.2.0.0。

### 参数

| 参数 | 默认值 | 范围与说明 |
| --- | ---: | --- |
| 方向 | 45° | 0–359°；按地图坐标计算，0°向右，90°向下 |
| 距离 | 32 | 0–256 地图像素 |
| 柔化半径 | 8 | 0–64 地图像素近似值；非均匀缩放时取两个方向的平均比例 |
| 不透明度 | 0.30 | 0–1 |
| 颜色 | `#141519` | 默认阴影颜色 |
| 投影模式 | 连续延展 | 可选短投影或连续延展 |
| 跟随来源对象 | 关闭 | 在有限的每帧预算内定期检查已启用目标 |
| 预览 | 开启 | 显示或隐藏生成的阴影节点 |
| 橡皮擦直径 | 24 | 2–512 地图像素；保存在本机设置中 |
| 橡皮擦硬度 | 70% | 0–100%；数值越低，笔刷边缘越柔和 |

### 限制与实现

插件处理可读取 Sprite 纹理的 Prop，以及按编辑器可见结果采样的 Pathway。墙、地形、水面和贴地装饰不会自动推断阴影；插件也不计算太阳位置或三维遮挡。较大的模糊与延展在可用时使用 GPU；小笔刷和不支持的渲染器由有预算限制的 CPU 路径处理。性能会随显卡、贴图和渲染后端变化，实测数据见 [TESTING.md](TESTING.md)。

地图参数、已启用目标、单对象覆盖值和擦除笔画保存在 `Global.ModMapData` 的 `contour_shadows` 键中（配方版本 2）。全局界面默认值保存在 `user://contour_shadows/settings.json`。请使用 Dungeondraft 自带的保存命令；桥接工具的 `save_map` 不会序列化当前会话的 `Global.ModMapData`。

从源码构建安装包：

```powershell
.\tools\Package-ContourShadows.ps1 -OutputPath 'C:\Temp\contour_shadows.zip'
```

输出路径必须是 `mod/` 外的绝对路径，已有同名文件不会被覆盖。架构说明见 [DESIGN.md](DESIGN.md)，验证记录见 [TESTING.md](TESTING.md)。
