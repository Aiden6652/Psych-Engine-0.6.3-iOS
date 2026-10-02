# iOS 构建说明（hxvlc 真视频版）

## 视频怎么走（反复踩坑后的结论）

### hxvlc 必须用 1.9.3

| 版本 | 问题 |
|---|---|
| 1.7 / 1.8.x | `FlxVideoSprite` 没有 `bitmap.forceRendering = true`，也不带 1.9.x 的 GPU 纹理渲染路径 → **能播出声音、但画面出不来** |
| **1.9.3** ✅ | 有 `forceRendering` + GPU 纹理路径，且代码用的是 `if (bitmap != null)` 写法 |
| 1.9.4 / 1.9.5 / 2.x | 使用了 `bitmap?.xxx`（Haxe **4.3** 的安全导航语法）→ Haxe 4.2.4 **直接语法报错**（`Unexpected .`） |

本仓库 Haxe 固定 4.2.4（升级会连带 hxcpp/iOS 工具链风险，暂不动），
所以 **1.9.3 是唯一可用版本**。CI 里写死 `haxelib install hxvlc 1.9.3`。

### 视频精灵必须“钉在屏幕上”

`FlxVideoSprite` 默认 `scrollFactor = (1,1)`（跟随世界坐标），而且
**`FlxSpriteGroup` 的 `scrollFactor` 不会传递给子对象**。后果：

- 挂在 TitleState（相机固定不动）→ 正常，片头能看见；
- 挂在 FlxSubState（打歌时相机在跟随角色）→ 画面被相机“卷”出屏幕 → 只剩声音。

所以 `source/hxcodec/VideoHandler.hx` 与 `source/VideoSprite.hx` 里都要：

```haxe
videoSprite.scrollFactor.set(0, 0);   // 钉在屏幕上
```

### 片头（TitleState）

优先 `mods/<模组>/videos/intro.mp4` 或 `<游戏目录>/assets/videos/intro.mp4`，
用 hxvlc 直接播；没有 mp4 时回落到逐帧图 `images/vfx_frames/intro/0001.png …`
+ `sounds/vfx/intro.ogg`。

## 视口：16:9 居中（对齐无视频版）

iPad Pro 11" 屏幕是 2420x1668（比例 1.45），游戏画面是 16:9（1.78），
所以画面本来就该上下留黑，且**上下对称**：

```
画面宽 2220 → 高 1249（=2220*9/16），垂直居中
→ 上下各约 209px 黑边，左右各约 100px
```

实现要点（`source/Main.hx`）：

- 只算**画布尺寸**（16:9 = 1280x720）与缩放倍数，`IOS_TARGET_ASPECT` 置 0 即恢复铺满；
- **千万不要再手动设 `flxGame.y`** —— FlxGame 内部会按缩放比例自己居中，
  再手动移一次就是双重偏移：画面被推下去、底部被裁（表现为“打歌时像放大了”、
  hitbox 底部色带看着跑到中间、大特效铺不满）。

## 排障用的诊断文件（都在游戏目录下）

| 文件 | 内容 |
|---|---|
| `pe_ios_viewport.txt` | stage / viewHeight / canvas / zoom / FlxG / 相机 / FlxGame 的 x,y,scale |
| `pe_ios_video.txt` | 视频播放全过程：路径、load 返回值、帧尺寸、缩放结果、原始 Bitmap 状态 |
| `pe_ios_lua_errors.log` | Lua 因 `setProperty` 写不存在字段而被拦下的记录 |

出现“画面比例不对/黑边不对/视频只有声音”时，先看这几个文件，
比猜快得多。

## 模组里怎么放视频

两种都行：

- `mods/你的模组/videos/xxx.mp4`
- `assets/videos/xxx.mp4`（游戏目录下，即 Documents/assets/videos）

注意：iOS 上 mp4 会被从 IPA 里剔除（省包体），已包含在 `resources.zip` 中，
首次启动自动释放到位。模组调用照旧：

```lua
startVideo('xxx')  -- 走 Paths.video → hxvlc，真播放
```
