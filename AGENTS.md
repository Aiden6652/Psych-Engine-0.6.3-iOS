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
