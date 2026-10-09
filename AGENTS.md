# AGENTS.md — Psych Engine 0.6.3 iOS 工程看板

> 单人维护：云端 Agent 已停，本地 Agent（Aiden 的 MateBook）全权负责 source/ + CI + 真机验证。

## 铁律
- main = 唯一可发布真相。改动直接 push main（不走分支 / PR）。
- **IPA 保持裸引擎：绝不打包 Corruption 歌曲 / 模组资源。** 用户明确要求「我要裸引擎」「Corruption别打进去」「我让你不带corruption资源没让你不改」。AE 引擎级改动（AECover / hxvlc / lua guard 等）保留；Corruption 内容由用户 iPad 外部加载（平板上已有完整资源）。
- 文档 / 看板改动 commit message 加 `[skip ci]`，避免白烧 macOS runner 额度（workflow 是 `on: push`，任何 commit 都触发完整 iOS 构建，macOS runner 按 10 倍计费）。

## 技术约定（钉死）
- flixel 不升级（保持 4.11.0）。Haxe 4.2.4 / lime 定制 fork / openfl 9.1.0 / hxvlc 1.9.3。
- hxvlc 必须用 1.9.3：1.7/1.8 无 GPU 渲染→有声音无画面；1.9.4+/2.x 用 Haxe 4.3 语法→4.2.4 报错。
- iOS 视频走 hxvlc + MobileVLCKit；桌面 plugins/ 文件夹 iOS 不用。
- stock PE 无 APEngine 私有功能：canon 难度 / BloodLust 写进源码的特效跑不了（带 -safe.json 的大多可玩，BloodLust 受限）。

## 进行中
- **148 失败真因（已核实 build.log，非 source 编译错）**：Project.xml 启用了 `assets/preload/resources.zip` 注入，但该 zip 不存在 → lime 报 `Error: Could not find asset path "assets/preload/resources.zip"` 退出（RC=1，3秒，无 .app 产物）。与 AECover 无关。
- 修复：注释掉 Project.xml 该引用，回到裸引擎（`0dcdec9`）→ 149 起 CI 成功。当前 main = 裸引擎，CI 正常出 IPA。
- **当前任务（单人全权）**：接手 source/ 的 AE 收尾 —— AECover 主菜单视觉还原的图层坐标 / 缩放校准（按 menuPositions.json + 实机录屏推断，未真机跑过，大概率要调）。**阻塞：需用户提供 iPad 主菜单截图**。校准完再推进下一批 UI（STORY / FREEPLAY / OPTIONS 文字、SELECT YOUR VICTIM glitch、freeplay 电子钟、storymode 视频页）。

## 资源加载（iPad 侧）
- IPA 不含 Corruption 内容；用户 iPad 上已有完整资源，从外部加载（文档目录 / LiveContainer 文件共享 / Filza）。
- SUtil.ensureAssets 找不到内置 resources.zip 会静默跳过，不崩、不影响运行。

## 已知坑
- hxvlc 必须用 1.9.3（1.7/1.8 无 GPU 渲染→有声音无画面；1.9.4+/2.x 用 Haxe 4.3 语法→4.2.4 报错）。
- iOS 视频走 hxvlc + MobileVLCKit，桌面 plugins/ 文件夹 iOS 不用。
- 内容约 1GB；**若将来要内置** resources.zip，需 Git LFS 或 CI 外链下载现打（顶层必须 assets/、mods/），且**必须先确保 zip 存在再启用 Project.xml 引用**，否则复现 148。当前用户选择不打进 IPA，故搁置。
- stock PE 无 APEngine 私有功能：canon 难度 / BloodLust 写进源码的特效跑不了（带 -safe.json 的大多可玩，BloodLust 受限）。
- 云端沙箱直连 github.com:443 不通（仅 api.github.com 通）；常规 git push 可能失败，必要时用 Git Data API（blob→tree→commit→ref）推 main。
