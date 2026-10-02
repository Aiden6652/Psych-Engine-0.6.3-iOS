# iOS 构建说明（hxvlc 真视频版）

## 视频怎么走（这是已验证可用的组合）

这套配置参考了之前能跑通的提交 `036ae9f`：

1. **hxvlc 1.8.1**（haxelib 安装）——它自带 `project/vlc/lib/iOS/libvlc_device.a`，
   iOS 上能真的解码播放 MP4。
2. **lime 用专用 fork**：`https://github.com/PsychEngine-report/LIME-0.6.3-FIX`（分支 main，v8.2.2，
   专门修了移动端/iOS 的安装启动问题）。
3. **不要用 hxCodec**：它 iOS 的链接配置会去链一个从来没有发布过的 `libvlc.a`，
   装上只会黑屏 / 链接失败。`Project.xml` 里已经换成 `<haxelib name="hxvlc" />`。
4. `source/hxcodec/VideoHandler.hx` 是**兼容层**：万一引擎或模组里还写着
   `import hxcodec.VideoHandler as MP4Handler`，它会用 hxvlc 把视频真的播出来，
   所以模组一行代码都不用改。

## “没有 assets zip”黑屏（本次修复）

`SUtil.doTheCheck()` 原本只认 Documents 下的 `assets` 和 `mods` 文件夹，
IPA 自带的资源它不认，所以会弹窗说没解压 Assets.zip 然后退出（你遇到的“爆 assets zip”）。

现在：CI 会把仓库自己的 `assets/` 和 `example_mods/`（重命名为 `mods/`）打成一个
`resources.zip` 放进 `assets/preload/`（随编译进 App 包），游戏第一次启动时
`SUtil.ensureAssets()` 自动解压到 Documents 并写 `pe_ios_assets_done.txt` 标记，
以后启动直接跳过。手动解压依旧兼容。

## 模组里怎么放视频

两种都行：

- `mods/你的模组/videos/xxx.mp4`
- `assets/videos/xxx.mp4`（游戏目录下，即 Documents/assets/videos）

注意：iOS 上 mp4 会被从 IPA 里剔除（省包体），已包含在 `resources.zip` 中，
首次启动自动释放到位。模组调用照旧：

```lua
startVideo('xxx')  -- 走 Paths.video → hxvlc，真播放
```
