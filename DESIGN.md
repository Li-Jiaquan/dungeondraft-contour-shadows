# 轮廓投影 / Contour Shadows — 开发设计与接口约定

## 0.4 双语界面（2026-10-22）

界面文案集中保存在 `scripts/library/localization.gd`，控件以消息键和参数描述状态，显示时按当前语言格式化。用户可即时在简体中文与 English 间切换；偏好只存入本机 `user://contour_shadows/settings.json`，不进入地图 recipe。控件重译不重建作业队列，也不改动对象选择、覆盖参数和擦除笔画。

## 0.3 改进方案（2026-10-14）

本轮由主代理设计与整合，三个 GPT-6 Luna max 子代理分别负责渲染算法、宿主交互与界面、路径采样与整体原生验收。保留 recipe version=2，与已有地图中的独立参数、排除项和擦除笔画兼容。

性能与质量一起解决。原算法在 CPU 上逐步扫描全源 Alpha，工作量与投影长度相乘；250,000 的工作上限会迫使大幅缩小来源，低柔和度下明显暴露栅格。先实现方向滑动最大值并测量，发现2倍覆盖采样及 CPU 像素循环在512上限下比旧版更慢：同一128输入2019ms对606ms，512输入14894ms对693ms。因此生产方案调整为 GPU 多阶段最大值传播与分离模糊，生成队列统一异步等待，不在交互线程同步运行高精度 CPU 版本。GLES2/GLES3 原型已确认链式 Viewport 可正确传递坐标及0.4/0.8的Alpha；必须设置 render_target_v_flip=true，等待至少两帧，再读取最终图像供擦除和缓存使用。保持最大 Alpha 合成，避免重叠加深。CPU同步接口保留作为兼容回退和独立验证路径，生产后端及耗时在诊断中标明。

抗锯齿与柔化分开；低柔化不应突然失去覆盖采样，柔化参数也不应因整数半径出现突变。使用同一输入、位移、尺寸和柔化条件比较旧版与新版的耗时和输出，保存实际图像证据。宿主输出边长暂定512，最终由基准决定。异步结果经过token/world/map/楼层/节点身份检查后才安装；清理、排除或地图变更时过期结果不得写入新配方。

路径来源必须包含进入和退出过渡的实际视觉状态。真实 Pathway 的渐入、渐出由 Gradient 表达；收尖由自定义 Line2D 的逐点绝对像素宽度表达，普通 points 属性复制不会带入这些宽度。只读复制视觉并通过 set_point_width 构造采样节点，不修改原路径。原生 get_point_width 在宽度数组未初始化时会导致进程崩溃，不能仅凭 super 标记调用；读取条件需通过隔离宿主验证。跟随签名使用 Pathway.Save(false) 的过渡、编辑点和平滑参数，以及 Gradient、Curve 的内容，避免不安全的逐点读取。导出 visual_signature(source) 供宿主调用。过渡验收使用专用地图比较收尖、淡入淡出前后的来源和阴影 Alpha，并核验源节点与地图文件不变。

本机读取真实CSharpScript Pathway且Save(false)的grow/shrink已启用时，Smooth后的48个点具有初始化的绝对宽度数组；隔离实例已验证进入端0→69与退出端69→0的复制、Alpha变化和只读恢复。普通Line2D及GDScript模拟节点不读取这个无边界检查的原生数组。路径与GPU离屏采样保留Viewport默认usage；显式USAGE_2D在本机将0.4量化成0.333333，默认模式读回0.396078，误差符合RGBA8精度。

界面按目标与生成、投影参数、局部擦除、折叠维护排列。投影参数标题下保留全局与单独两个互斥按钮，紧邻说明作用范围；目标数、工作状态直接可见。参数标明名称、值和单位，维护操作收纳，使用当前 Dungeondraft 皮肤并留出合理间距。昂贵形状调整按180ms合并；颜色和不透明度直接更新现有阴影的 modulate，避免重新采样和计算。

启用橡皮擦必须先保存选择快照，再明确切换到 contour_shadows 并验证活动工具，准备好目标阴影后才能接收画布输入。本机Image仅暴露is_empty()，不能使用empty()判空；后者在自定义引擎动态调用中产生错误类型而未报脚本异常，使缓存就绪检查始终失败。统一使用is_empty()，数组、字典和字符串仍使用empty()。失焦结束笔画而保留模式，切换工具、地图或楼层仍安全结束。验收从原生 SelectTool 启用控件开始，通过 Editor/ModBaseTool 的实际画布事件路由拖动，核验源对象/路径几何不变、目标阴影 Alpha 减少、其他阴影不变；直接调用擦除算法不能代替该验证。

本轮文件所有权：render_v3 负责 renderer 与独立渲染测试；ui_v3 负责宿主和 README；path_accept_v3 负责 path_source、集成驱动和 TESTING；主代理负责 runner 整合、DESIGN、manifest、审查和安装发行。隔离 QA profile 与专用地图，不改用户编辑会话。

橡皮擦大小以地图像素直径显示，范围2–512，默认24；内部保留半径字段以兼容旧用户设置。硬度0–100%，默认70%，控制中心完整擦除区域与边缘平滑过渡。单笔覆盖的线段取最大擦除影响，避免接头重复累乘形成深斑；不同笔画可以叠加。旧v2笔画未保存硬度时按100%读取，新笔画保存自己的硬度。调整大小或硬度时先结束当前笔画。

GPU生产后端使用2倍覆盖采样、倍增最大值传播和分离高斯模糊。输出上限512，核心硬上限1024；CPU回退上限384/250,000采样预算。GLES3三次测量中位数：128输入102.098ms（旧版581.779ms），512输入253.106ms（旧版613.485ms）；GLES2分别111.477ms/251.331ms。数据来自本机Radeon780M与固定测试输入，不能当作所有地图的速度保证。颜色与不透明度直接更新显示节点，形状参数180ms合并刷新。GPU工作与擦除CPU工作分别记录，未实现CPU多线程。

用户追加橡皮擦卡顿问题后，检查确认旧拖动分支每个鼠标事件都重放所有笔画、重建ImageTexture并计算完整签名。原生固定遮罩测试：512输入，2点笔画28.9ms、32点113.3ms、8笔各8点362.1ms。改为每笔维护开始时的Alpha与最大擦除影响，只扫描新增线段的裁切区域；像素游标跨帧保留，单帧共享4096候选像素与约6ms计算预算。鼠标事件只追加轨迹，每对象FIFO队列保证连续多笔按顺序作用。每帧复用ImageTexture更新显示，不重算历史；结束手势记录撤销和配方，剩余显示工作继续分帧完成。撤销、恢复、重生成取消相关旧任务，再由配方恢复一次；地图或楼层变化不能提交旧缓存。全量apply保留用于加载配方和恢复，拖动使用增量接口。预算限制响应阻塞，不保证极大笔刷在单帧完成。

增量基准进一步发现大笔刷积压问题：512输入、半径256、32点，在4096像素/帧下松开后仍有1709帧，不能作为完成方案。增加大笔刷GPU分流：单次裁切覆盖大于16,384像素时，从该笔固定开始图计算整个当前轨迹的最大擦除影响，16段一批在GPU合并，最多64个覆盖pass，最后合成并一次读回；计算期间的新点合并为下一次完整快照，不截断曲线。全局最多一个GPU擦除任务，结果经过job ID、地图、来源实例、基图及显示缓存身份校验；同一笔预览始终使用固定开始图，防止柔边重复累乘。取消任务后须等实际资源释放再启动下一任务。GPU有效失败时回退到同一开始图的CPU增量队列；小笔刷保留CPU增量路径。

CPU增量几何使用与全量apply相同的Vector2原生float32中间计算，避免脚本double标量计算在量化边界产生1级Alpha误差；31项独立宿主验收保持逐字节一致。GPU Alpha允许1级RGBA8误差。GLES3独立颜色纹理由原始Image在原生C++中转换为RGB8，避免纹理上传预乘；512、半径256、32点测试25.943ms，70点6个pass测试61.159ms。GLES2读回还存在目标颜色预乘，颜色恢复改为6ms限时分帧，避免整张逐像素循环阻塞画布。两种后端分别记录实际耗时与CPU修正帧数，不能把分帧CPU修正描述成纯GPU。

最终GPU笔刷双后端报告：同一512、32点、半径256输入，GLES3为32.2ms；GLES2为111.0ms，9个CPU修正切片，累计52.7ms，最长6.06ms。GLES3 RGB与Alpha最大误差各1级；GLES2 RGB逐字节一致、Alpha最大误差1级。独立控制器22项验收包括计算中合并新增点、固定笔画开始图、GPU处理中撤销与同源FIFO。主回归239项、分发工具14项通过；这些是固定本机测试结果。

以下0.2与首版接口、预算及记录为历史设计；0.3生产流程与上限以上述方案和当前代码为准。

## 0.2 扩展约定（2026-10-14）

本轮增加 Pathway 路径来源、局部擦除和每对象参数。路径和 Prop 共用稳定 node_id、选择快照、生成队列、启用/排除列表；不会将路径拆成真实 Prop。Pathway 继承 Line2D，读取其已经平滑的 points、width/width_curve、gradient、texture 和纹理/接头/端帽设置，在透明 Viewport 中复制渲染得到 Alpha 来源。只复制视觉节点，不移动或改变原路径，不把路径中心线简单代替真实透明轮廓。异步采样由队列管理并清理 Viewport，缓存有尺寸和数量上限。

来源图返回 image、源局部 rect 和 source pixel_scale。若采样缩小，世界位移转换为源局部后还需除以来源 pixel_scale，渲染输出 offset 和 pixel_scale 显示时乘回来源比例。Prop 的来源局部空间为 Sprite，Pathway 为 Line2D；投影仍绘制在各自原画面之后。

“投影参数”标题紧接“单独调整 / 全局调整”两个互斥按钮。全局参数为地图默认，只影响未设置独立参数的已生成对象；单独模式使用已记录选择，编辑字段只改变这些对象对应字段，不污染默认。切换模式或选择更新控件，并显示当前作用范围；提供回归全局默认的操作。

擦除在投影生成完成后的 Alpha 上应用。每笔记录来源局部坐标点列与刷子半径，支持局部半径基以还原缩放下的世界圆。连续拖动按线段扫掠，避免快速移动留下空隙。擦除只作用于目标投影，原物件/路径像素保持只读。参数调整、刷新与保存重开复用已存笔画，移动/旋转时随来源变换。提供恢复擦除；工具切换、地图/楼层变化和失焦结束笔画，面板点击不产生擦除。

地图 recipe version=2，保留 settings、enabled_node_ids、excluded_node_ids，增加按 node_id 索引的 overrides 与 erasures。v1 无损迁移为空扩展字段；未来未知版本保持原数据并拒绝改写。独立参数不写全局 user:// 默认配置。验收包括实际路径纹理投影、独立/全局互不污染、擦除保留/恢复，以及原地图来源不变。

本轮文件分工：sources_v2 只编辑 library；ui_v2 只编辑宿主；checks_v2 编辑 tests/、QA 驱动及 README/TESTING；root 负责 DESIGN、版本、集成与安装发行。

## 产品范围

独立的 Dungeondraft 原生 GDScript mod，使用 Godot 3.x API。读取每个 Prop 的 Sprite 透明轮廓，在编辑器内生成可见且可正常导出的附加阴影。纯美术控制，绝不计算太阳位置、物理高度或三维遮挡。

界面为 Effects 分类下的“轮廓投影”。控制：方向（0°向右、90°向下）、距离（地图像素/woxel）、柔化半径、不透明度、色彩、短投影/连续延展模式。支持当前层生成/刷新、仅选中对象、选中对象排除/恢复、预览开关、移除投影。全局默认角度45、距离32、柔化8、不透明度0.30、深灰黑；默认关闭自动生成，用户按生成后可开启轻量跟随。范围以 Prop 为主；墙、地形、水面、贴地装饰不自动推断。

原始 Sprite 只读，新增节点归插件所有。首版按对象逐一附加阴影，保留各 Prop 本身 z 与树顺序。阴影节点挂在 Prop 下，位于原 Sprite 后面，拷贝 Sprite 的局部变换；局部采样对应中心/offset/region/frames/flip。地图统一方向必须换算到 Sprite 局部坐标，不能随对象旋转或镜像改变。重复刷新复用或替换原插件节点，不累积节点。删除插件节点不删除原对象。内置 HasShadow 如有替换选项必须记录、清理时恢复原值；默认保留且提示可关闭。

## 目录及分工

- `mod/contour_shadows.ddmod`, `mod/scripts/contour_shadows.gd`, `mod/icons/contour_shadows.png`: 主工具入口与 UI、对象发现、生命周期、设置持久化。由 ui_host 子代理负责。
- `mod/scripts/library/shadow_renderer.gd`, `mod/scripts/library/shadow_geometry.gd`: 纯 Godot 栅格算法与变换辅助，由 shadow_core 子代理负责。
- `tests/`, `tools/`, `README.md`, `TESTING.md`: 独立验证、原生 Godot smoke、安装/打包脚本，由 validation 子代理负责。
- 根代理负责 DESIGN、集成、审查、实际 DD 运行验证、打包发行。各代理不覆盖别人的文件；接口改动先协商。

## Core 对外接口（必须一致）

两个 library 脚本以 `extends Reference` 开头。宿主用 `ResourceLoader.load(Global.Root + "scripts/library/…", "", true).new()` 加载核心库，禁用资源缓存以支持重新加载插件；这条路径已在本机实际宿主验证。core 不引用 Global/Script，便于独立 Godot 运行。

renderer:

`func render(source: Image, displacement: Vector2, blur_radius: float = 8.0, mode: String = "sweep", alpha_cutoff: float = 0.02, max_size: int = 384) -> Dictionary`

- source 为已经按 Sprite 的实际帧/region 裁切的图像（若已含 flip，宿主不可再 flip）；不修改输入。
- displacement 与 blur_radius 单位为 source 图像原始像素。`offset` 表示输出图像左上角相对输入图像左上角的位置，可为负。`pixel_scale` 表示输出一个像素对应多少原始像素，宿主按此缩放生成的 Sprite。
- mode=`offset` 只平移轮廓，mode=`sweep` 沿(0,0)至displacement连续取最大 Alpha，以免同一阴影的内部重叠越叠越黑。
- 输出 `{"ok":true,"image":Image,"offset":Vector2,"pixel_scale":float,"source_size":Vector2}`；失败 `{"ok":false,"error":String}`。
- 图像 RGBA8、RGB 为白色，Alpha 为柔化后的遮罩；宿主通过 modulate 控制阴影颜色和总不透明度，缓存不受色彩影响。
- 先裁掉完全透明的外边缘，保留原尺寸和裁切原点，再扩边避免模糊裁切。连续延展的像素×采样步数预算为 250,000，按需降低采样分辨率；宿主最大边长为 384。缩小后的细孔可能合并。纹理提取缓存由宿主负责，最多 32 项/64 MiB。

geometry:

`func world_to_local_vector(transform: Transform2D, world_vector: Vector2) -> Vector2`

只逆变换基向量，不引入平移，处理旋转、非均匀缩放、镜像；退化变换返回安全值或记录错误。

`func angle_vector(degrees: float, distance: float) -> Vector2`

`func extract_sprite_image(sprite) -> Dictionary`

返回 `{"ok":true,"image":Image,"rect":Rect2}`，rect 为 Sprite 原本的本地绘制矩形。需要考虑 texture/AtlasTexture、region_enabled、hframes/vframes/frame、centered、offset、flip_h/flip_v。flip 可直接应用于提取图像；如这样处理，则宿主只拷贝 Sprite.transform 而不额外镜像。

## 宿主布局约定

影子 Sprite 设置 `centered=false`，position=`rect.position + result.offset`，scale=`Vector2.ONE * result.pixel_scale`，外层 Node2D 拷贝原 Sprite.transform。该外层作为 Prop 子节点绘制在原 Sprite 之前；不要给原 Prop 换纹理或添加真实 Prop 数据。方向向量由原 Sprite.global_transform 逆基变换得到，保持地图方向一致。跟随检测包括 texture/frame/region/flip、global_transform 的基向量、z 层级和设置版本；平移由父节点自动带动，不重算像素。每帧最多生成一个对象，每轮跟随检查两个对象。

地图设置采用 `Global.ModMapData["contour_shadows"]`，保存设置、启用与排除的稳定 `node_id`（包含 0），不保存临时 instance_id。全局配置保存在 `user://contour_shadows/settings.json`。已通过原生保存与重开验证 recipe 恢复；桥接的 save_map 不序列化当前 ModMapData，用户需按 Ctrl+S 或保存按钮。

本机 C# Prop 和 SelectTool 的属性优先通过 `get_Sprite`、`get_Selected` 读取。选择工具关闭会清空实时选择，因此宿主每帧记录当前地图和楼层的稳定 ID 快照，返回轮廓投影工具后用于选中生成/排除/恢复。颜色控件通过官方命名回调 `on_color_change` 更新，而非连接 HBoxContainer 上不存在的信号。

## 验收

1. 原生 Godot3 编译/运行 core，而非仅 Python 重写模拟；覆盖透明孔洞、负方向、零位移、渐变 Alpha、扩边、连续延展最大值合并、大图限制、旋转/非均匀缩放/镜像向量、Sprite frame/region/offset。
2. 宿主脚本加载和模组格式核验；刷新不重复、移除恢复原状态、排除项、不同楼层切换无残留。
3. 尽可能在实际 Dungeondraft 打开测试副本，生成、导出、清理，并检查控制台错误；若应用/桥接不可连接必须如实记录尚未完成的实测，不能声称已验证。
4. 发行 ZIP 只含安装所需 mod 文件；附中文安装、参数说明、性能限制、兼容版本和实测状态；提供安全的显式安装脚本，安装不覆盖同名内容。

## 核实的官方依据

- https://megasploot.github.io/DungeondraftModdingAPI/ ：mod .ddmod 与脚本加载结构。
- https://megasploot.github.io/DungeondraftModdingAPI/Globals/ ：CreateModTool、Global.World、Script.InstanceReference/InstanceExtension（实现前进一步核实）。
- https://megasploot.github.io/DungeondraftModdingAPI/reference/Prop/ ：Sprite 只读，HasShadow、Mirror、occluders。
- https://megasploot.github.io/DungeondraftModdingAPI/reference/Objects/ ：Prop 容器。
- https://megasploot.github.io/DungeondraftModdingAPI/tutorials/SerializingModData/ ：user:// JSON、持久 node_id。

2026-10-13 已在本机 Dungeondraft 1.2.0.1、Godot 3.4.2 Mono custom build 实测核心加载、选择快照、原生保存、重开恢复及 PNG 导出。详细断言和验收记录见 TESTING.md。
