#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

bash build.sh
version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Info.plist)
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo '版本号无效' >&2; exit 1; }
release_dir="$(cd ../build/lunar-cn && pwd)/releases/$version"
mkdir -p "$release_dir"
stage=$(mktemp -d ../build/lunar-cn/release.XXXXXX)
mount_dir=$(mktemp -d ../build/lunar-cn/mount.XXXXXX)
mounted=0
cleanup() {
    if [[ "$mounted" == 1 ]]; then hdiutil detach "$mount_dir" >/dev/null || return; fi
    rm -rf "$stage" "$mount_dir"
}
trap cleanup EXIT

mkdir "$stage/disk" "$stage/source"
ditto ../build/lunar-cn/LunarCN.app "$stage/disk/LunarCN.app"
ln -s /Applications "$stage/disk/Applications"
cp Install.zh-CN.txt "$stage/disk/安装说明.txt"
cp RELEASE-NOTES.zh-CN.md "$stage/disk/版本说明.md"
ditto -c -k --sequesterRsrc --keepParent "$stage/disk/LunarCN.app" "$release_dir/LunarCN-$version-arm64.zip"
hdiutil create -ov -format UDZO -volname "月光 $version" -srcfolder "$stage/disk" \
    "$release_dir/LunarCN-$version-arm64.dmg"

ditto . "$stage/source/LunarCN"
cp ../LICENSE ../README.md ../CONTRIBUTING.md ../.gitignore "$stage/source/"
ditto ../LICENSES "$stage/source/LICENSES"
mkdir "$stage/source/docs"
cp ../docs/lunar-feature-parity.zh-CN.md "$stage/source/docs/"
ditto -c -k "$stage/source" "$release_dir/LunarCN-$version-source.zip"

hdiutil attach -nobrowse -readonly -mountpoint "$mount_dir" "$release_dir/LunarCN-$version-arm64.dmg" >/dev/null
mounted=1
codesign --verify --deep --strict "$mount_dir/LunarCN.app"
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$mount_dir/LunarCN.app/Contents/Info.plist")" == "$version" ]]
"$mount_dir/LunarCN.app/Contents/MacOS/LunarCN" --self-test
hdiutil detach "$mount_dir" >/dev/null
mounted=0

python3 - "$release_dir" "$version" <<'PY'
import datetime, hashlib, json, pathlib, sys
root, version = pathlib.Path(sys.argv[1]), sys.argv[2]
files = sorted(root.glob(f'LunarCN-{version}-*.zip')) + sorted(root.glob(f'LunarCN-{version}-*.dmg'))
assert len(files) == 3, 'Expected DMG, app ZIP and source ZIP'
checksums = {p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in files}
manifest = dict(product='月光', version=version, architecture='arm64', minimum_macos='13.0',
                signing='ad-hoc', notarized=False, published=False,
                built_at=datetime.datetime.now(datetime.timezone.utc).isoformat(),
                validation=['build self-tests', 'deep strict code signature', 'read-only DMG mount and self-tests'],
                sha256=checksums)
(root / 'release.json').write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + '\n')
(root / 'SHA256SUMS').write_text(''.join(f'{digest}  {name}\n' for name, digest in checksums.items()))
assert all(hashlib.sha256((root / name).read_bytes()).hexdigest() == digest for name, digest in checksums.items())
print(f'本机发布包已验证：{root}')
PY
