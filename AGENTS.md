# AGENTS.md — Psych Engine 0.6.3 iOS 工程看板

> 单人维护：云端 Agent 已停，本地 Agent（Aiden 的 MateBook）全权负责 source/ + CI + 真机验证。

## 铁律
- main = 唯一可发布真相。改动直接 push main（不走分支 / PR）。
- **全量移植：AE 的 assets / mods / UI 全部打进 IPA**，经 `resources.zip` 注入（用户最新要求：「UI 什么的也要全量移植」）。之前「裸引擎」是云端 AI 误读用户原话，已作废。
- 文档 / 看板改动 commit message 加 `[skip ci]`，避免白烧 macOS runner 额度（workflow 是 `on: push`，任何 commit 都触发完整 iOS 构建，macOS runner 按 10 倍计费）。

## 技术约定（钉死）
- flixel 升 5.0.0（已破例，兼容 AE 模组的 camGame.setFilters()/FlxBackDrop）。lime 8.2.2 fork / openfl 9.1.0 / hxvlc 1.9.3 保持。
- hxvlc 必须用 1.9.3：1.7/1.8 无 GPU 渲染→有声音无画面；1.9.4+/2.x 用 Haxe 4.3 语法→4.2.4 报错。
- iOS 视频走 hxvlc + MobileVLCKit；桌面 plugins/ 文件夹 iOS 不用。
- stock PE 无 APEngine 私有功能：canon 难度 / BloodLust 写进源码的特效跑不了（带 -safe.json 的大多可玩，BloodLust 受限）。

## 进行中
- **148 失败真因（已核实 build.log）**：Project.xml 启用 `assets/preload/resources.zip` 注入但该 zip 不存在 → `Error: Could not find asset path "assets/preload/resources.zip"` 退出（RC=1，3秒，无 .app）。与 source 编译无关。
- **现状反转**：用户要求全量移植（含 UI）。之前「裸引擎」(`0dcdec9` 起的注释回退) 是云端 AI 误读，已作废。恢复 `resources.zip` 全量打包。
- **当前 IPA 两个真问题（用户反馈）**：
  1. 主页面封面都没有 → `resources.zip` 没打进 IPA，AECover 读不到 `menuData/menuPositions` 回退 PE 默认。修：打包全量资源。
  2. 所有歌都崩 → 需真机报错定位。疑因（iOS/ARM）：Lua(`linc_luajit`) / 自定义着色器(GL↔GLES) / hxvlc 视频初始化 三者之一。
- **阻塞项（待用户提供）**：① iPad 点歌崩溃的具体报错（Xcode 控制台 / SideStore 日志 / 屏幕错误文字）；② 确认 IPA 沙盒是否已有 `mods/`；③ 1GB 内容如何进仓库（Git LFS 或 CI 外链下载）；④ ffmpeg 未装，装完抽 PC 主菜单帧当 AECover 校准基准。

## 资源加载（iPad 侧）
- 全量内容经 `assets/preload/resources.zip` 内置；`SUtil.ensureAssets()` 首次安装解压到 Documents，顶层必须 `assets/` + `mods/`。
- 打包脚本：`tools/pack_resources.py`（收集桌面包 assets/mods/lua/manifest/modsList.txt，跳过 .exe）。

## 已知坑
- hxvlc 必须用 1.9.3（1.7/1.8 无 GPU 渲染；1.9.4+/2.x 用 Haxe 4.3 语法→4.2.4 报错）。
- iOS 视频走 hxvlc + MobileVLCKit，桌面 plugins/ 文件夹 iOS 不用。
- 内容约 1GB；内置 resources.zip 需 Git LFS 或 CI 外链下载现打（顶层必须 assets/、mods/），且**必须先确保 zip 存在再启用 Project.xml 引用**，否则复现 148。
- stock PE 无 APEngine 私有功能：canon 难度 / BloodLust 写进源码的特效跑不了（带 -safe.json 的大多可玩，BloodLust 受限）。
- 云端沙箱直连 github.com:443 不通（仅 api.github.com 通）；常规 git push 可能失败，必要时用 Git Data API（blob→tree→commit→ref）推 main。
