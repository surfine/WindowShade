#!/bin/bash
# 把 vendored 的 mediaremote-adapter（BSD-3，上游与固定提交见 UPSTREAM.md）编成
# MediaRemoteAdapter.framework，并把 perl 脚本放到旁边。不签名：由调用方用和 App 同一个身份签。
#
# 用法：build-adapter.sh OUT_DIR ARCH
#   OUT_DIR/MediaRemoteAdapter.framework   版本化框架（Versions/A），给 /usr/bin/perl 用 DynaLoader 加载
#   OUT_DIR/mediaremote-adapter.pl         上游脚本原样
#
# 和上游 CMakeLists.txt 等价的编译参数：ARC、符号默认可见（perl 要按名字找函数）、
# 链接 Foundation / AppKit / UniformTypeIdentifiers。只编一个架构（和主程序一致）。
# 不用 -Werror：这是第三方源码，警告不是我们的门槛；上游改动由固定提交挡住。
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
out="${1:?OUT_DIR}"
arch="${2:?ARCH}"
name=MediaRemoteAdapter
fw="$out/$name.framework"
rm -rf "$fw"
mkdir -p "$fw/Versions/A/Resources"

sources=()
for f in "$here"/src/adapter/*.m "$here"/src/private/*.m "$here"/src/utility/*.m; do sources+=("$f"); done

xcrun -sdk macosx clang -fobjc-arc -fvisibility=default -O2 -dynamiclib \
  -target "$arch-apple-macosx14.0" \
  -I "$here/include" -I "$here/src" \
  -install_name "@rpath/$name.framework/Versions/A/$name" \
  -framework Foundation -framework AppKit -framework UniformTypeIdentifiers \
  -o "$fw/Versions/A/$name" "${sources[@]}"

cat > "$fw/Versions/A/Resources/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleExecutable</key>
	<string>$name</string>
	<key>CFBundleIdentifier</key>
	<string>com.windowshade.prototype.mediaremote-adapter</string>
	<key>CFBundleName</key>
	<string>$name</string>
	<key>CFBundlePackageType</key>
	<string>FMWK</string>
	<key>CFBundleShortVersionString</key>
	<string>0.1</string>
	<key>CFBundleVersion</key>
	<string>0.1.0</string>
</dict>
</plist>
PLIST
ln -sfn A "$fw/Versions/Current"
ln -sfn "Versions/Current/$name" "$fw/$name"
ln -sfn Versions/Current/Resources "$fw/Resources"

cp "$here/bin/mediaremote-adapter.pl" "$out/mediaremote-adapter.pl"
