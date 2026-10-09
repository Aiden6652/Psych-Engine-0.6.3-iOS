#!/usr/bin/env python3
# 把桌面版 Corruption 完整包打成 iOS 用的 resources.zip
# 约定（来自 source/SUtil.hx ensureAssets）：zip 顶层必须含 assets/ 和 mods/
# 全量移植：桌面包顶层 assets/ mods/ lua/ manifest/ modsList.txt 全部带进 zip
# 用法：
#   python tools/pack_resources.py --source "<桌面包>" --out assets/preload/resources.zip
#   python tools/pack_resources.py --source "<桌面包>" --dry-run   # 只统计，不打包

import os, sys, zipfile, argparse

SKIP_EXT = {'.exe'}  # 不打包可执行文件


def collect(source):
    tops = ['assets', 'mods', 'lua', 'manifest']
    wanted = []
    for t in tops:
        p = os.path.join(source, t)
        if os.path.isdir(p):
            wanted.append(p)
    mlt = os.path.join(source, 'modsList.txt')
    if os.path.isfile(mlt):
        wanted.append(mlt)
    files = []
    for root in wanted:
        for dirpath, _dirs, fnames in os.walk(root):
            for fn in fnames:
                if os.path.splitext(fn)[1].lower() in SKIP_EXT:
                    continue
                files.append(os.path.join(dirpath, fn))
    return files


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--source', required=True, help='桌面版 Corruption 包根目录')
    ap.add_argument('--out', default='assets/preload/resources.zip')
    ap.add_argument('--dry-run', action='store_true')
    args = ap.parse_args()

    if not os.path.isdir(args.source):
        print('源目录不存在:', args.source)
        sys.exit(1)

    files = collect(args.source)
    total = sum(os.path.getsize(f) for f in files)
    print('将打包文件数:', len(files))
    print('总大小: %.2f MB' % (total / 1024 / 1024))
    top = {}
    for f in files:
        rel = os.path.relpath(f, args.source)
        top[rel.split(os.sep)[0]] = top.get(rel.split(os.sep)[0], 0) + 1
    print('各顶层条目文件数:', top)

    if args.dry_run:
        print('[dry-run] 未生成 zip')
        return

    out = args.out
    os.makedirs(os.path.dirname(out), exist_ok=True)
    with zipfile.ZipFile(out, 'w', zipfile.ZIP_DEFLATED) as z:
        for f in files:
            rel = os.path.relpath(f, args.source)
            z.write(f, rel)
    print('已生成:', out, '%.2f MB' % (os.path.getsize(out) / 1024 / 1024))


if __name__ == '__main__':
    main()
