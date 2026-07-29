#!/usr/bin/env python3
"""把 App Store 截图压平成不带 alpha 的 PNG，并校验尺寸。

App Store Connect 拒收带 alpha 通道的图片 —— 哪怕整张图完全不透明，
只要 PNG 里有那条通道就报 "Images can't contain alpha channels or transparencies"。
macOS 截屏默认带 alpha，所以直接传必被退。

用法:
    python3 Tools/fix_screenshots.py <文件夹或文件> [...]

原图会改名成 .orig.png 留在原地，不会丢。
"""

import sys
import os
from PIL import Image

# App Store Connect 各机型槽位接受的像素尺寸（竖屏；横屏为宽高互换）。
# 一个槽位往往接受多种尺寸，任选其一即可，但同一槽位里所有图必须一致。
ACCEPTED = {
    (1320, 2868): '6.9" (iPhone 16/17 Pro Max)',
    (1290, 2796): '6.9" (iPhone 15/16 Pro Max)',
    (1284, 2778): '6.5" (iPhone 12/13 Pro Max)',
    (1242, 2688): '6.5" (iPhone 11 Pro Max / XS Max)',
    (1242, 2208): '5.5" (iPhone 8 Plus)',
    (2048, 2732): '12.9" iPad Pro',
    (2064, 2752): '13" iPad Pro (M4)',
}


def collect(paths):
    files = []
    for p in paths:
        if os.path.isdir(p):
            for name in sorted(os.listdir(p)):
                if name.lower().endswith((".png", ".jpg", ".jpeg")) \
                        and not name.endswith(".orig.png"):
                    files.append(os.path.join(p, name))
        elif os.path.isfile(p):
            files.append(p)
    return files


def describe(size):
    if size in ACCEPTED:
        return f"✓ {ACCEPTED[size]}"
    # 横屏也认
    flipped = (size[1], size[0])
    if flipped in ACCEPTED:
        return f"✓ {ACCEPTED[flipped]}（横屏）"
    return "✗ 尺寸不在受理列表里"


def main(paths):
    files = collect(paths)
    if not files:
        print("没找到图片。")
        return 1

    fixed = skipped = 0
    print(f"{'文件':<44} {'尺寸':<12} {'alpha':<7} 结果")
    print("-" * 96)

    for path in files:
        im = Image.open(path)
        size = im.size
        has_alpha = "A" in im.getbands() or im.mode == "P" and "transparency" in im.info

        if not has_alpha and im.mode == "RGB":
            print(f"{os.path.basename(path):<44} {str(size):<12} {'无':<7} 无需处理 · {describe(size)}")
            skipped += 1
            continue

        # 压平到白底。截图本来就不透明，白底只是给那条通道一个归宿；
        # 真有半透明像素的话，白底也是 App Store 预览的实际背景。
        src = im.convert("RGBA")
        out = Image.new("RGB", size, (255, 255, 255))
        out.paste(src, mask=src.getchannel("A"))

        backup = os.path.splitext(path)[0] + ".orig.png"
        os.rename(path, backup)
        out.save(os.path.splitext(path)[0] + ".png", "PNG", optimize=True)

        print(f"{os.path.basename(path):<44} {str(size):<12} {'有':<7} 已压平 · {describe(size)}")
        fixed += 1

    print("-" * 96)
    print(f"压平 {fixed} 张，跳过 {skipped} 张。原图存为 *.orig.png。")

    bad = [f for f in files
           if Image.open(os.path.splitext(f)[0] + ".png"
                         if os.path.exists(os.path.splitext(f)[0] + ".png") else f).size not in ACCEPTED]
    if bad:
        print(f"\n⚠️  有 {len(bad)} 张尺寸不在受理列表里，压平了也会被拒。")
        print("   同一个槽位里所有截图的尺寸必须完全一致。")
    return 0


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(1)
    sys.exit(main(sys.argv[1:]))
