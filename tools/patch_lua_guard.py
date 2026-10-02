#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
[PE-iOS] 编译前加固：让 Lua 的 setProperty / setPropertyFromClass 在
「字段不存在 / 不可写」时只记日志，而不是把异常抛出去崩掉整个游戏。

为什么需要：
iOS（hxcpp）上 Haxe 异常一旦从 Lua 的 C 回调里逃出去，C++ 会直接
std::terminate() -> abort()，表现是「瞬间闪退回桌面，连 crash 文件都不留」。
实测崩溃栈（PsychEngine-2026-10-02-205308.ips）：
  PlayState.create -> FunkinLua 构造 -> Lua 脚本 setProperty ->
  Reflect.setProperty -> PlayState.__SetField -> hx::Throw -> abort()

做法：把下面这些调用各自包一层 try/catch（异常就地捕获并写入日志文件）。
匹配不到预期代码时会直接报错退出，避免「静默失效」。
"""

import sys

PATH = "source/FunkinLua.hx"

# 下面每一条都是从仓库当前代码里原样摘出来的整行
TARGETS = [
    "setVarInArray(getPropertyLoopThingWhatever(killMe), killMe[killMe.length-1], value);",
    "setVarInArray(getInstance(), variable, value);",
    "setVarInArray(coverMeInPiss, killMe[killMe.length-1], value);",
    "setVarInArray(Type.resolveClass(classVar), variable, value);",
]


def guard(call):
    return ("try { " + call + " } catch (e:Dynamic) { "
            "trace('[PE-iOS][LuaGuard] 已忽略一次非法 setProperty: ' + Std.string(e)); "
            "try { sys.io.File.saveContent(SUtil.getPath() + 'pe_ios_lua_errors.log', "
            "Std.string(e) + '\\n'); } catch (e2:Dynamic) {} }")


def main():
    src = open(PATH, encoding="utf-8").read()

    if "[LuaGuard]" in src:
        print("[LuaGuard] FunkinLua.hx 已经加固过，跳过")
        return 0

    total = 0
    for t in TARGETS:
        n = src.count(t)
        if n > 0:
            src = src.replace(t, guard(t))
            total += n
            print("[LuaGuard] 加固 %d 处: %s" % (n, t))

    if total == 0:
        print("[LuaGuard] 未匹配到任何目标行，FunkinLua.hx 结构可能已变化", file=sys.stderr)
        return 1

    open(PATH, "w", encoding="utf-8").write(src)
    print("[LuaGuard] 完成，共加固 %d 处" % total)
    return 0


if __name__ == "__main__":
    sys.exit(main())
