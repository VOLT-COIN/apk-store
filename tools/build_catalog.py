#!/usr/bin/env python3
"""Build catalog.json for Makhzan Store from the F-Droid public index.

Every app listed is free/open-source software published by F-Droid, so the APKs
are redistributable. We do not host third-party APKs: download links point at
f-droid.org and each entry credits its license and source repository.

Usage: python3 tools/build_catalog.py [--out catalog.json] [--prev catalog.json]
"""
import argparse
import datetime
import html
import json
import re
import urllib.request

INDEX_URL = "https://f-droid.org/repo/index-v1.json"
REPO = "https://f-droid.org/repo/"

CATEGORIES = [
    ("comms", "تواصل", ["Internet", "Connectivity", "Phone & SMS", "Messaging"]),
    ("media", "وسائط", ["Multimedia", "Online Media Player", "Local Media Player", "Cast"]),
    ("games", "ألعاب", ["Puzzle Game", "Game Helper"]),
    ("tools", "أدوات", ["System", "Development", "Keyboard & IME", "Timer", "Launcher",
                        "Wallpaper", "Remote Controller", "Graphics", "File Manager"]),
    ("security", "أمان وخصوصية", ["Security", "Password & 2FA", "VPN & Proxy"]),
    ("productivity", "إنتاجية", ["Note", "Task", "Calendar & Agenda"]),
    ("education", "تعليم", ["Science & Education", "Reading", "Writing"]),
    ("health", "صحة ورياضة", ["Sports & Health", "Health Manager"]),
    ("money", "مالية", ["Finance Manager"]),
    ("maps", "خرائط وتنقل", ["Navigation"]),
]

FEATURED = [
    "org.fdroid.fdroid", "org.videolan.vlc", "org.schabi.newpipe", "org.wikipedia",
    "com.termux", "app.organicmaps", "net.osmand.plus", "org.mozilla.fennec_fdroid",
    "com.fsck.k9", "net.thunderbird.android", "de.danoeh.antennapod", "com.aurora.store",
    "com.wireguard.android", "org.telegram.messenger", "com.b44t.messenger",
    "org.briarproject.briar.android", "im.vector.app", "org.nextcloud", "com.nextcloud.client",
    "com.kunzisoft.keepass.libre", "com.beemdevelopment.aegis", "io.github.muntashirakon.AppManager",
    "com.github.libretube", "net.minetest.minetest", "com.shatteredpixel.shatteredpixeldungeon",
    "org.kde.kdeconnect", "me.zhanghai.android.files", "org.fossify.gallery", "org.fossify.calendar",
    "org.fossify.phone", "org.fossify.messages", "com.github.axet.audiorecorder",
    "org.amnezia.vpn", "eu.kanade.tachiyomi", "com.machiav3lli.fdroid", "org.mozilla.focus",
]

CJK = re.compile(r"[\u3040-\u30ff\u3400-\u4dbf\u4e00-\u9fff\uac00-\ud7af]")
TAG = re.compile(r"<[^>]+>")


def clean(text, limit=1200):
    if not text:
        return ""
    text = text.replace("<br>", "\n").replace("<br/>", "\n").replace("<br />", "\n")
    text = re.sub(r"</p>", "\n\n", text, flags=re.I)
    text = re.sub(r"<li[^>]*>", "\u2022 ", text, flags=re.I)
    text = TAG.sub("", text)
    text = html.unescape(text)
    text = re.sub(r"[ \t]+", " ", text)
    text = re.sub(r"\n{3,}", "\n\n", text).strip()
    return text[:limit].strip()


def load_index(url):
    with urllib.request.urlopen(url, timeout=300) as r:
        return r.read().decode("utf-8", "replace")


def parse_index(s):
    dec = json.JSONDecoder()
    apps = []
    i = s.index('"apps": [') + len('"apps": [')
    while True:
        while i < len(s) and s[i] in " \n\r\t,":
            i += 1
        if s[i] == "]":
            break
        obj, i = dec.raw_decode(s, i)
        apps.append(obj)
    pkgs = {}
    j = s.index('"packages": {') + len('"packages": {')
    while True:
        while j < len(s) and s[j] in " \n\r\t,":
            j += 1
        if s[j] == "}":
            break
        key, j = dec.raw_decode(s, j)
        while s[j] in " \n\r\t:":
            j += 1
        val, j = dec.raw_decode(s, j)
        pkgs[key] = val
    return apps, pkgs


def category_of(cats):
    for cid, _, names in CATEGORIES:
        for c in cats or []:
            if c in names:
                return cid
    for c in cats or []:
        if c.lower().endswith("game"):
            return "games"
    return "tools"


def build(index_text, prev_entries):
    apps, pkgs = parse_index(index_text)
    out = []
    for a in apps:
        pkg = a.get("packageName") or ""
        versions = pkgs.get(pkg) or []
        if not versions:
            continue
        apk = max(versions, key=lambda v: v.get("versionCode") or 0)
        if not apk.get("apkName") or not apk.get("hash"):
            continue
        loc = a.get("localized") or {}
        ar = loc.get("ar") or {}
        en = loc.get("en-US") or {}
        base = en if (en.get("description") or en.get("summary")) else ar
        name = ar.get("name") or base.get("name") or en.get("name") or pkg
        summary = clean(ar.get("summary") or base.get("summary") or en.get("summary") or "", 200)
        desc = clean(ar.get("description") or base.get("description") or en.get("description") or "", 700)
        if not desc:
            desc = summary
        if len(desc) < 40:
            continue
        if CJK.search(name) or CJK.search(summary):
            continue
        if not a.get("icon"):
            continue
        shots = []
        shot_loc = None
        for lname in ("ar", "en-US"):
            if loc.get(lname, {}).get("phoneScreenshots"):
                shot_loc = lname
                shots = loc[lname]["phoneScreenshots"]
                break
        icon = a.get("icon")
        out.append({
            "id": pkg,
            "package_name": pkg,
            "name": name,
            "name_ar": ar.get("name") or "",
            "summary": summary,
            "desc_ar": desc if (ar.get("description") or ar.get("summary")) else "",
            "desc": desc,
            "developer": a.get("authorName") or "",
            "category": category_of(a.get("categories")),
            "version": apk.get("versionName") or "",
            "version_code": apk.get("versionCode"),
            "size_mb": round((apk.get("size") or 0) / 1048576, 2) if apk.get("size") else None,
            "icon_url": (REPO + "icons-640/" + icon) if icon else "",
            "screenshots": [(REPO + pkg + "/" + shot_loc + "/phoneScreenshots/" + s) for s in shots[:6]],
            "apk_url": REPO + apk["apkName"],
            "sha256": apk.get("hash") or "",
            "license": a.get("license") or "",
            "source_url": a.get("sourceCode") or "",
            "website": a.get("authorWebSite") or "",
            "min_sdk": apk.get("minSdkVersion"),
            "updated": datetime.datetime.utcfromtimestamp((a.get("lastUpdated") or 0) / 1000).strftime("%Y-%m-%d") if a.get("lastUpdated") else "",
            "featured": pkg in FEATURED,
            "has_ar": bool(ar.get("summary") or ar.get("name")),
        })
    seen = set()
    picked = []
    by_id = {e["id"]: e for e in out}
    for pkg in FEATURED:
        e = by_id.get(pkg)
        if e and e["id"] not in seen:
            picked.append(e)
            seen.add(e["id"])

    def score(e):
        return (3 if e["screenshots"] else 0) + (2 if e["has_ar"] else 0) + min(len(e["desc"]) / 400.0, 3) + (1 if e["icon_url"] else 0)

    per_cat = {}
    for e in sorted(out, key=lambda x: (-score(x), x["updated"])):
        if e["id"] in seen:
            continue
        c = e["category"]
        if per_cat.get(c, 0) >= 45:
            continue
        per_cat[c] = per_cat.get(c, 0) + 1
        picked.append(e)
        seen.add(e["id"])
    for e in picked:
        e.pop("has_ar", None)
    ours = []
    for p in prev_entries:
        if not str(p.get("package_name", "")).startswith("com.eslam"):
            continue
        p = dict(p)
        p.setdefault("summary", (p.get("desc_ar") or "")[:140])
        p.setdefault("screenshots", [])
        p.setdefault("featured", False)
        p["featured"] = True
        p.setdefault("category", "apps")
        p.setdefault("version_code", None)
        p.setdefault("min_sdk", 21)
        p.setdefault("license", "")
        p.setdefault("source_url", "")
        p.setdefault("website", "")
        p.setdefault("updated", "")
        ours.append(p)
    return ours + picked


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default="catalog.json")
    ap.add_argument("--prev", default="catalog.json")
    ap.add_argument("--index", default=INDEX_URL)
    args = ap.parse_args()

    prev_entries = []
    try:
        with open(args.prev, encoding="utf-8") as f:
            prev_entries = json.load(f).get("apps") or []
    except Exception:
        pass

    text = load_index(args.index)
    apps = build(text, prev_entries)
    doc = {
        "store": "مخزن التطبيقات",
        "tagline": "تحميل تطبيقات وألعاب أندرويد — مجانية ومفتوحة المصدر",
        "updated": datetime.date.today().isoformat(),
        "schema_version": 2,
        "source": "F-Droid (https://f-droid.org) — تطبيقات حرة مفتوحة المصدر",
        "categories": [{"id": c, "name": n} for c, n, _ in CATEGORIES],
        "apps": apps,
    }
    with open(args.out, "w", encoding="utf-8") as f:
        json.dump(doc, f, ensure_ascii=False, separators=(",", ":"))
        f.write("\n")
    print("wrote %s: %d apps, %d KB" % (args.out, len(apps), len(json.dumps(doc, ensure_ascii=False).encode()) // 1024))


if __name__ == "__main__":
    main()
