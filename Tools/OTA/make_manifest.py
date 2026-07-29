#!/usr/bin/env python3
"""生成 OTA 安装用的 manifest.plist 和落地页。

OTA（Over-the-Air）靠 `itms-services://` 协议让 iPhone 直接装 ipa，不经 App Store。
三个硬要求，缺一不可：
  1. ipa 必须是 **Ad Hoc**（或企业）签名 —— App Store 签名的装不了
  2. ipa 和 manifest.plist 都必须走 **HTTPS**（http 会被静默拒绝）
  3. 目标设备的 UDID 要在描述文件里

用法: python3 Tools/OTA/make_manifest.py <ipa路径> <https基址> <输出目录>
  例: python3 Tools/OTA/make_manifest.py /tmp/export/JLPTPrep.ipa https://jlpt.example.com /tmp/ota
"""
import plistlib
import subprocess
import sys
import zipfile
from pathlib import Path

IPA, BASE_URL, OUT = Path(sys.argv[1]), sys.argv[2].rstrip("/"), Path(sys.argv[3])
OUT.mkdir(parents=True, exist_ok=True)

# 从 ipa 里读出真实的 bundle id / 版本，不靠手填 —— 填错了装上去是另一个 App
with zipfile.ZipFile(IPA) as z:
    plist_name = next(
        n for n in z.namelist()
        if n.count("/") == 2 and n.startswith("Payload/") and n.endswith(".app/Info.plist")
    )
    info = plistlib.loads(z.read(plist_name))

bundle_id = info["CFBundleIdentifier"]
version = info.get("CFBundleShortVersionString", "0")
build = info.get("CFBundleVersion", "0")
title = info.get("CFBundleDisplayName") or info.get("CFBundleName") or bundle_id

manifest = {
    "items": [{
        "assets": [{
            "kind": "software-package",
            "url": f"{BASE_URL}/{IPA.name}",
        }],
        "metadata": {
            "bundle-identifier": bundle_id,
            "bundle-version": version,
            "kind": "software",
            "title": title,
        },
    }]
}
(OUT / "manifest.plist").write_bytes(plistlib.dumps(manifest))

# 落地页。itms-services 的 URL 里 manifest 地址必须整体转义。
install_url = f"itms-services://?action=download-manifest&url={BASE_URL}/manifest.plist"
(OUT / "index.html").write_text(f"""<!doctype html>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>{title}</title>
<style>
  body {{ margin:0; background:#f3f2f2; color:#201f1d;
         font-family:-apple-system,"PingFang SC",sans-serif;
         display:flex; min-height:100vh; align-items:center; justify-content:center; }}
  .card {{ padding:36px 28px; border:1px solid rgba(32,31,29,.16); border-radius:4px;
           max-width:340px; text-align:center; }}
  h1 {{ font-family:"Songti SC",serif; font-weight:600; font-size:26px; margin:0 0 6px; }}
  .meta {{ font-size:12px; color:#7d7979; font-variant-numeric:tabular-nums; margin-bottom:24px; }}
  a.install {{ display:block; padding:13px; border:1px solid #b68235; border-radius:4px;
               color:#7d5411; text-decoration:none; font-size:15px; }}
  .note {{ margin-top:20px; font-size:11px; line-height:1.8; color:#9b9797; }}
</style>
<div class="card">
  <h1>{title}</h1>
  <div class="meta">{version} ({build}) · {bundle_id}</div>
  <a class="install" href="{install_url}">安装到这台 iPhone</a>
  <div class="note">
    用 iPhone 上的 Safari 打开这个页面。<br>
    装完若提示「不受信任的开发者」，去<br>
    设置 › 通用 › VPN 与设备管理 里信任。
  </div>
</div>
""", encoding="utf-8")

print(f"App        {title}")
print(f"Bundle ID  {bundle_id}")
print(f"版本       {version} ({build})")
print(f"输出       {OUT}/manifest.plist, {OUT}/index.html")
print(f"安装页     {BASE_URL}/index.html")
