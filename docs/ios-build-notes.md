# iOS 构建说明（hxvlc 真视频版）

## 为什么要单独一个目录/说明

引擎和大量老模组写的是 `hxcodec.VideoHandler`，但官方 hxCodec 在 iOS 上是个空壳
（`include.xml` 的 ios 段只声明了几个 Apple 框架，完全没有链接 libvlc），拿它播视频只会黑屏。

所以本仓库的做法是：

1. 依赖里装 **hxvlc**（它自带 `libvlc_device.a`，iOS 真能播），版本固定在
   `6807fd692b8affbe6636533e56f5bbf2f52675ec`（2023-09，API 稳定、不需要 Haxe 4.3 的 nullSafety）。
2. `source/hxcodec/VideoHandler.hx` 是**兼容层**：用 hxvlc 实现同名的 `hxcodec.VideoHandler`，
   所以引擎和模组里 `import hxcodec.VideoHandler as MP4Handler` 的写法一行都不用改。
3. `Project.xml` 里的 `<haxelib name="hxCodec" />` 依然保留，但只当“名字占位”，
   真正链接进包的是 hxvlc 的 libVLC（它的 include.hxml / Build.xml 是完整可用的）。

## “没有 assets zip”黑屏

`SUtil.doTheCheck()` 原本只认 Documents 下的 `assets` 和 `mods` 文件夹，
IPA 自带的资源它不认，所以会弹窗说没解压 Assets.zip 然后退出。

现在：CI 会把仓库自己的 `assets/` 和 `example_mods/`（重命名为 `mods/`）打成一个
`resources.zip` 放进 `assets/preload/`（随编译进 App 包），游戏第一次启动时
`SUtil.ensureAssets()` 会自动解压到 Documents 并写一个 `pe_ios_assets_done.txt` 标记，
以后启动就直接跳过。手动解压依旧兼容（有标记/目录就不重复做）。

## 模组里怎么放视频

延续原逻辑，两种都行：

- `mods/你的模组/videos/xxx.mp4`
- `assets/videos/xxx.mp4`（游戏目录下，即 Documents/assets/videos）

注意：iOS 上 mp4 不在 App 包里（为了减小 IPA），要自己放到 Documents 下（或者放进模组）。
模组调用不用改：

```lua
startVideo('xxx')  -- 内部走 Paths.video → hxcodec.VideoHandler 兼容层
```
