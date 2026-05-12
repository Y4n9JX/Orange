#!/usr/bin/env python3
"""Apply custom app branding for Orange.

Usage:
  python3 scripts/brand.py --name YourApp --icon assets/brand/logo.png

The script replaces runtime display names and launcher icons for Android,
Linux, macOS, and Windows packaging resources. By default it also renames the
Windows app executable/build target to the brand name. It intentionally does not
rename package names, source classes/packages, or core binaries such as
FlClashApplication, FlClashCore, and FlClashHelperService. Use
--no-rename-executable if you only want display-name changes.
"""
from __future__ import annotations

import argparse
import re
from pathlib import Path
from typing import Iterable

try:
    from PIL import Image
except ImportError as exc:
    raise SystemExit(
        "Pillow is required. Install it with: python3 -m pip install Pillow "
        "or apt install python3-pil"
    ) from exc

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_ICON = ROOT / "assets" / "brand" / "logo.png"

TEXT_REPLACEMENTS = [
    ("lib/common/constant.dart", [
        (r'const appName = "[^"]+";', 'const appName = "{name}";'),
        (r'const appNameEn = "[^"]+";', 'const appNameEn = "{binary_name}";'),
    ]),
    ("android/app/src/main/res/values/strings.xml", [
        (r'(<string name="fl_clash">)(.*?)(</string>)', r'\1{name}\3'),
    ]),
    ("android/app/src/main/AndroidManifest.xml", [
        # Main launcher label and Quick Settings tile label are both here.
        (r'android:label="[^"]+"', 'android:label="{name}"'),
    ]),
    ("android/app/src/debug/AndroidManifest.xml", [
        (r'android:label="[^"]+"', 'android:label="{name} Debug"'),
    ]),
    ("android/app/src/main/kotlin/com/follow/clash/services/BaseServiceInterface.kt", [
        (r'setContentTitle\("[^"]+"\)', 'setContentTitle("{name}")'),
    ]),
    ("android/app/src/main/kotlin/com/follow/clash/services/FlClashVpnService.kt", [
        (r'setSession\("[^"]+"\)', 'setSession("{name}")'),
    ]),
    ("android/app/src/main/kotlin/com/follow/clash/GlobalState.kt", [
        (r'const val NOTIFICATION_CHANNEL = "[^"]+"', 'const val NOTIFICATION_CHANNEL = "{name}"'),
    ]),
    ("linux/packaging/deb/make_config.yaml", [
        (r'display_name: .*', 'display_name: {name}'),
        (r'generic_name: .*', 'generic_name: {name}'),
        (r'  - .+', '  - {name}'),
    ]),
    ("linux/packaging/rpm/make_config.yaml", [
        (r'display_name: .*', 'display_name: {name}'),
        (r'generic_name: .*', 'generic_name: {name}'),
        (r'  - .+', '  - {name}'),
    ]),
    ("linux/packaging/appimage/make_config.yaml", [
        (r'display_name: .*', 'display_name: {name}'),
        (r'generic_name: .*', 'generic_name: {name}'),
        (r'  - .+', '  - {name}'),
    ]),
    ("linux/my_application.cc", [
        (r'gtk_header_bar_set_title\(header_bar, "[^"]+"\)', 'gtk_header_bar_set_title(header_bar, "{name}")'),
        (r'gtk_window_set_title\(window, "[^"]+"\)', 'gtk_window_set_title(window, "{name}")'),
    ]),
    ("windows/packaging/exe/make_config.yaml", [
        (r'app_name: .*', 'app_name: {name}'),
        (r'display_name: .*', 'display_name: {name}'),
    ]),
    ("windows/runner/main.cpp", [
        (r'window\.Create\(L"[^"]+"', 'window.Create(L"{name}"'),
    ]),
    ("windows/runner/Runner.rc", [
        (r'VALUE "FileDescription", "[^"]+"', 'VALUE "FileDescription", "{name}"'),
        (r'VALUE "ProductName", "[^"]+"', 'VALUE "ProductName", "{name}"'),
    ]),
    ("macos/packaging/dmg/make_config.yaml", [
        (r'title: .*', 'title: {name}'),
        (r'path: .+\.app', 'path: {name}.app'),
    ]),
    ("macos/Runner/Configs/AppInfo.xcconfig", [
        (r'PRODUCT_NAME = .*', 'PRODUCT_NAME = {name}'),
    ]),
    ("distribute_options.yaml", [
        (r"app_name: '[^']+'", "app_name: '{name}'"),
    ]),
]

WINDOWS_EXECUTABLE_REPLACEMENTS = [
    ("windows/CMakeLists.txt", [
        (r'project\([^\s)]+ LANGUAGES CXX\)', 'project({binary_name} LANGUAGES CXX)'),
        (r'set\(BINARY_NAME "[^"]+"\)', 'set(BINARY_NAME "{binary_name}")'),
    ]),
    ("windows/packaging/exe/make_config.yaml", [
        (r'executable_name: .*', 'executable_name: {binary_name}.exe'),
        (r'output_base_file_name: .*', 'output_base_file_name: {binary_name}.exe'),
    ]),
    ("windows/packaging/exe/inno_setup.iss", [
        (r"Processes := \[.*?\];", "Processes := ['{binary_name}.exe', 'FlClashCore.exe', 'FlClashHelperService.exe'];"),
    ]),
    ("windows/runner/Runner.rc", [
        (r'VALUE "InternalName", "[^"]+"', 'VALUE "InternalName", "{binary_name}"'),
        (r'VALUE "OriginalFilename", "[^"]+\.exe"', 'VALUE "OriginalFilename", "{binary_name}.exe"'),
    ]),
]


def safe_package_name(name: str) -> str:
    value = re.sub(r"[^a-zA-Z0-9_.-]+", "-", name.strip()).strip("-_.").lower()
    return value or "orange"


def safe_binary_name(name: str) -> str:
    value = re.sub(r"[^a-zA-Z0-9_.-]+", "", name.strip())
    return value or "Orange"


def apply_regex(text: str, pattern: str, repl: str, values: dict[str, str]) -> str:
    """Apply a regex replacement without letting app names break backrefs.

    Some replacements intentionally use capture groups such as \1 and \3.
    Using a replacement callback avoids accidental escape processing when a
    brand name contains characters that are meaningful to re.sub.
    """
    replacement = repl.format(**values)

    def _replace(match: re.Match[str]) -> str:
        return match.expand(replacement)

    return re.sub(pattern, _replace, text, flags=re.MULTILINE)


def replace_text(name: str, *, rename_executable: bool = True) -> list[str]:
    values = {
        "name": name,
        "binary_name": safe_binary_name(name),
    }
    changed: list[str] = []
    replacement_sets = list(TEXT_REPLACEMENTS)
    if rename_executable:
        replacement_sets.extend(WINDOWS_EXECUTABLE_REPLACEMENTS)
    for rel, rules in replacement_sets:
        path = ROOT / rel
        if not path.exists():
            continue
        text = path.read_text(encoding="utf-8")
        original = text
        for pattern, repl in rules:
            text = apply_regex(text, pattern, repl, values)
        if text != original:
            path.write_text(text, encoding="utf-8")
            changed.append(rel)
    return changed


def load_icon(path: Path) -> Image.Image:
    if not path.exists():
        raise SystemExit(f"Icon file not found: {path}")
    image = Image.open(path).convert("RGBA")
    side = min(image.size)
    left = (image.width - side) // 2
    top = (image.height - side) // 2
    image = image.crop((left, top, left + side, top + side))
    return image


def fit_canvas(image: Image.Image, size: int, inset: float = 0.0) -> Image.Image:
    """Return a transparent square canvas with icon centered."""
    canvas = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    artwork_size = max(1, int(size * (1 - inset * 2)))
    artwork = image.resize((artwork_size, artwork_size), Image.LANCZOS)
    offset = ((size - artwork_size) // 2, (size - artwork_size) // 2)
    canvas.alpha_composite(artwork, offset)
    return canvas


def save_text(rel: str, content: str) -> str:
    target = ROOT / rel
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(content, encoding="utf-8")
    return rel


def save_png(image: Image.Image, rel: str, size: int, inset: float = 0.0) -> str:
    target = ROOT / rel
    target.parent.mkdir(parents=True, exist_ok=True)
    fit_canvas(image, size, inset=inset).save(target, "PNG")
    return rel


def save_webp(image: Image.Image, rel: str, size: int) -> str:
    target = ROOT / rel
    target.parent.mkdir(parents=True, exist_ok=True)
    fit_canvas(image, size).save(target, "WEBP", quality=95)
    return rel


def save_ico(image: Image.Image, rel: str) -> str:
    target = ROOT / rel
    target.parent.mkdir(parents=True, exist_ok=True)
    sizes = [(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)]
    fit_canvas(image, 256).save(target, "ICO", sizes=sizes)
    return rel


def replace_icons(icon_path: Path) -> list[str]:
    image = load_icon(icon_path)
    written: list[str] = []

    source_copy = ROOT / "assets/brand/logo.png"
    source_copy.parent.mkdir(parents=True, exist_ok=True)
    fit_canvas(image, 1024).save(source_copy, "PNG")
    written.append("assets/brand/logo.png")

    for rel in [
        "assets/images/icon.png",
        "assets/images/icon_black.png",
        "assets/images/icon_white.png",
    ]:
        written.append(save_png(image, rel, 550))

    for rel in [
        "assets/images/icon.ico",
        "assets/images/icon_black.ico",
        "assets/images/icon_white.ico",
        "windows/runner/resources/app_icon.ico",
    ]:
        written.append(save_ico(image, rel))

    for folder, size in [
        ("mipmap-mdpi", 48),
        ("mipmap-hdpi", 72),
        ("mipmap-xhdpi", 96),
        ("mipmap-xxhdpi", 144),
        ("mipmap-xxxhdpi", 192),
    ]:
        for filename in ["ic_launcher.webp", "ic_launcher_round.webp"]:
            written.append(save_webp(image, f"android/app/src/main/res/{folder}/{filename}", size))

    # Use brand-specific drawable names to avoid colliding with the upstream
    # drawable/ic_launcher_foreground.xml vector resource used by splash styles.
    written.append(save_png(image, "android/app/src/main/res/drawable/brand_ic_launcher_foreground.png", 432, inset=0.18))
    background = Image.new("RGBA", (432, 432), (250, 250, 250, 255))
    written.append(save_png(background, "android/app/src/main/res/drawable/brand_ic_launcher_background.png", 432))
    adaptive_xml = """<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@drawable/brand_ic_launcher_background"/>
    <foreground android:drawable="@drawable/brand_ic_launcher_foreground"/>
    <monochrome android:drawable="@drawable/brand_ic_launcher_foreground" />
</adaptive-icon>
"""
    written.append(save_text("android/app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml", adaptive_xml))
    written.append(save_text("android/app/src/main/res/mipmap-anydpi-v26/ic_launcher_round.xml", adaptive_xml))

    for size in [16, 32, 64, 128, 256, 512, 1024]:
        written.append(save_png(image, f"macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_{size}.png", size))

    return written


def main(argv: Iterable[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Apply Orange app name and icon branding")
    parser.add_argument("--name", required=True, help="Display name, e.g. YourApp")
    parser.add_argument("--icon", default=str(DEFAULT_ICON), help="PNG/JPG/WebP/ICO source icon. Default: assets/brand/logo.png")
    parser.add_argument("--name-only", action="store_true", help="Only replace app name")
    parser.add_argument("--icon-only", action="store_true", help="Only replace icons")
    parser.add_argument(
        "--no-rename-executable",
        action="store_true",
        help="Only replace display names; keep the Windows executable/build target as-is.",
    )
    args = parser.parse_args(argv)

    if args.name_only and args.icon_only:
        raise SystemExit("--name-only and --icon-only cannot be used together")
    if args.icon_only and args.no_rename_executable:
        raise SystemExit("--no-rename-executable cannot be used with --icon-only")

    rename_executable = not args.no_rename_executable

    changed: list[str] = []
    if not args.icon_only:
        changed.extend(replace_text(args.name.strip(), rename_executable=rename_executable))
    if not args.name_only:
        changed.extend(replace_icons(Path(args.icon)))

    print("Branding applied.")
    print(f"Name: {args.name}")
    if not args.icon_only:
        print(f"Windows executable rename: {'enabled' if rename_executable else 'disabled'}")
    if not args.name_only:
        print(f"Icon: {args.icon}")
    print("Changed files:")
    for item in changed:
        print(f" - {item}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
