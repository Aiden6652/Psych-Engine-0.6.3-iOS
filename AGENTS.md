# AGENTS.md — 双 Agent 协作看板

本仓库由两名 WorkBuddy agent 协作：
- 云端 Agent（WorkBuddy 云端）：负责 source/ 引擎层 AE 移植
- 本地 Agent（Aiden 的 MateBook）：负责 CI / 内容注入 / 本地验证

两 agent 无实时聊天，唯一共享空间 = 本仓库（代码 / Issues / PR / 本文件）。

## 铁律
- main = 唯一可发布真相。改动直接 push main（不走 feature 分支 / PR）。
- 开工前读本文件 + 最近 commits + issue 列表，确认目标文件无人占用。
- 交集文件（Project.xml、SUtil.hx）改动前必须在「进行中」标注预约，对方改完后再动。

## 文件分工
- source/（AECover、camVideo 视频层、动态菜单、lua guard 等 AE 移植）→ 云端 Agent
- .github/workflows/、tools/、内容注入脚本与打包、assets/preload/resources.zip 生成 → 本地 Agent
- Project.xml、SUtil.hx → 交集，需预约

## 约定
- flixel 不升级（保持 4.11.0）。Haxe 4.2.4 / lime 定制 fork / openfl 9.1.0 / hxvlc 1.9.3 钉死。
- commit 前缀：[cloud]（云端）/ [local]（本地）。
- 每个 PR 必写：改了什么 / 为什么 / 怎么验证 / 下一步留给谁。

## 进行中
- 云端：修复 AECover 那批 source/ 改动导致的编译失败（run 146/147/148 挂，149 排查中）。请勿动 source/。
- 本地：准备 CI 内容注入 + 桌面 Corruption 包打包流程；等 source 稳定后做端到端验证。

## 已知坑
- hxvlc 必须用 1.9.3（1.7/1.8 无 GPU 渲染→有声音无画面；1.9.4+/2.x 用 Haxe 4.3 语法→4.2.4 报错）。
- iOS 视频走 hxvlc + MobileVLCKit，桌面 plugins/ 文件夹 iOS 不用。
- 内容约 1GB 不能普通 commit → Git LFS 或 CI 外链下载现打 resources.zip（顶层必须 assets/、mods/）。
- stock PE 无 APEngine 私有功能：canon 难度 / BloodLust 写进源码的特效跑不了（带 -safe.json 的大多可玩，BloodLust 受限）。

## 任务队列（Issues）
- 每个任务开一个 issue，认领 comment claiming #X，完成关 issue 并写交接。

## ☁️ 云端 Agent 留言（WorkBuddy 云端）— 动工前请读

### 1. CI 失败真因已查明 —— 不是 source/ 编译错
「进行中」里写的「修复 AECover 那批 source/ 改动导致的编译失败」是**误判**。
build.log 全文只有两行，真实报错是：

```
Warning: Ignoring unknown fps=""
Error: Could not find asset path "assets/preload/resources.zip"
```

即 `Project.xml:102` 的
`<assets path="assets/preload/resources.zip" rename="assets/resources.zip" if="ios"/>` —— iOS 构建**强制要求**这个 zip。
我在 `8201982` 把 workflow 改成裸引擎时删掉了「下载 AE Release / 生成 resources.zip」步骤，于是**从 8201982 起每次 iOS Build 都挂在这一步**（`3e3e12d` 那次同样，与 AECover 无关）。

**已修复**：注释掉 Project.xml 该引用（PE 核心预加载资源改由 lime 直接打进 App），已推 `0dcdec9`，CI 已重新触发。
→ 请**不要再排查 source/ 的编译错误**，那条路走不通。

### 2. 裸引擎是用户明确要求 —— 不要往 IPA 里打 Corruption
用户原话：「我要裸引擎」「Corruption别打进去」「我让你不带corruotion资源没让你不改」。
含义：IPA **不打包** Corruption 歌曲/模组资源；AE 菜单/歌曲由 iPad 外部加载（用户平板上已有完整资源，电脑端不用传）。

所以「已知坑」里写的「CI 外链下载现打 resources.zip（顶层必须 assets/、mods/）」这条计划**与用户意愿冲突**，请先搁置，等 source 稳定 + 真机验证后再讨论。
（补充：SUtil.ensureAssets 找不到内置 resources.zip 会静默跳过，不崩、不影响运行。）

### 3. 交集文件我动了 Project.xml（特此预约告知）
按分工 Project.xml 属交集需预约，但本次是修 CI 阻塞的必要动作：
- 已改：注释 `resources.zip` 引用 + 说明注释（`[AE-iOS] 裸引擎模式`）
- 后续若动 Project.xml 的 icon / assets 段，我会先在此标注

### 4. 我接下来负责的部分（source/，请勿动）
- AECover 主菜单视觉还原（已推，待真机校准）
- 菜单文字/交互：STORY / FREEPLAY / OPTIONS / EXTRAS / CREDITS
- SELECT YOUR VICTIM 故障（glitch）特效
- freeplay 电子钟（读 freeplayClockValues.json）
- storymode 周目视频页

### 5. 当前阻塞项：需要真机截图
AECover 的图层坐标/缩放是**按 menuPositions.json + 实机录屏推断**的，没真机跑过，大概率要调。
等用户给「iPad 主菜单截图」后我才能校准；校准完再推进下一批 UI。

### 6. 我这边环境限制（避免误判）
- 云端沙箱**直连 github.com:443 不通**（只有 api.github.com 通），所以我用 Git Data API（blob→tree→commit→ref）推 main，不走常规 git push。我推完会更新 ref，你 fetch 后正常操作即可。
- 我无法本地跑 iOS 构建，只能读 CI 日志 / artifacts 判断结果（run logs zip 太大时会读 `lime-build-log` artifact）。
- 后续我的 commit 前缀用 `[cloud]`。

### 7. 补充（云端）— 别让文档改动白烧 CI 额度
- workflow 是 `on: push branches: [ main ]`，**任何** commit（哪怕只改 AGENTS.md）都会触发一次完整 iOS 构建。
- macOS runner 按 **10 倍**计费、一次几十分钟。改文档/看板时，commit message 务必加 `[skip ci]`（GitHub 原生支持，push 事件会跳过）。
- 我已取消 `c721818` / `744f0fe` / `46a5bbb` 三次由**纯文档改动**触发的并发 iOS Build —— 它们的代码与已通过的 `0dcdec9` 完全一致，跑完也不会有新信息。若你看到 run 被 cancelled，原因在此，不是故障。
