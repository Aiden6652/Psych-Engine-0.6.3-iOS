# AE ↔ PE 0.6.3 Lua API 缺失清单（移植兼容性基线）

通过比对仓库 `source/FunkinLua.hx` 暴露的 **212** 个 Lua 函数，与桌面 Corruption 发布包 **337** 个 lua 脚本调用的 **333** 个函数名，得到模组调用但引擎未注册的候选集合。

**这是「所有歌都崩」的根因：模组依赖 AE 引擎层的自定义 Lua API，stock PE 0.6.3 没有实现，调用即 `nil` crash。与打包 / 资源可见性无关。**

## 关键缺失分组（非 lua 内置、非 PE 回调钩子 onXxx）

### 着色器 / 后处理（最大崩源候选）
`createRuntimeShader` `makeShader` `setFilters` `getShaders` `ShaderFilter` `setChrome` `shaderCoordFix` `fixShaderCoordFix` `abberation` `bloom` `glitch` `setFloat`

### 双玩家 / 输入系统（P2）
`getControl` `setControl` `makeControl` `tweenControl` `holdInput` `input` `keyHoldShit` `keyPress` `keys` `getKeyFromID` `updateControllers` `goodNoteHitP2` `noteMissP2` `noteMissPressP2` `onKeyPressP2` `addBehindBF` `addBehindDad` `moveCamera` `onMoveCamera` `onNoteCam` `onNoteColor` `baseCamPos`

### 自定义视觉 / 特效
`Cam` `Cinematics` `addOverlay` `createForestClone` `createTrailFrame` `createTrailFrameBF` `createTrailFrameDad` `FlxTrail` `altFloor` `altWall` `changeBG` `normalFloor` `normalWall` `pixelThingie*` `partSicle` `trainReset` `trainStart` `updateTrainPos` `windCamPos` `windGFCam` `updateBar`

### 对话 / 剧情 / 歌词
`loadLyrics` `reloadDialogue` `startDialogueThing*` `startSenpaiCutscene*` `reloadShaders` `getLuaObject`

### 视频
`MP4Handler`（hxCodec 兼容类；iOS 底层 hxvlc，视频 lua 应直接调 hxvlc）

### HUD / 菜单
`precacheAnimatedImage` `createFilledBar` `ratingComboStuff` `scoreTxtStuff` `popUpScore` `AECover`（菜单封面，已移植成 AECover.hx 但可能不全）

### 其他 AE 工具
`encrypt` `ddHaxeLibrary` `setOnLuas` `setproperty`（小写变体）`getVar` `setVar`

## 移植含义
全量打包 assets/mods + 外置加载（SUtil.ensureAssets 已支持）只解决「资源 / UI 可见」，不解决「歌能跑」。要让歌不崩，必须在引擎 source 实现上述 AE 自定义 Lua API：
- 最大两块：着色器接 **hxShaders**、视频接 **hxvlc**（底层已是 hxvlc）；
- 其余（双键 / 对话 / 特效 / 封面）需 **AE 源码逻辑**，当前不在手。

## 已知额外不兼容
- `canon` 难度：32 首有 `-canon.json`，stock PE 通常能认难度名，但 AE 的 canon 逻辑未必。
- `BloodLust` / `Blood-Moon` 用 `FlxBackDrop`（flixel 5.0 才有，当前钉 4.11.0）→ 这几首必崩。

## 状态（2026-10-09）
- storymode 周目排序在 iOS 显示错误：**已知，用户拍板后置、不阻塞移植主线**。
- ffmpeg 本地无法安装（GitHub 大文件下载被环境限流），AECover 校准基准图改用 PC 主菜单截图（待用户提供）。
- 内容进 iOS = 走**外置 assets + mods**（SUtil 已支持，用户手动放入 App Documents）。
