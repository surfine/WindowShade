# mediaremote-adapter（vendored）

- 上游：https://github.com/ungive/mediaremote-adapter
- 固定提交：`29718252613a5b0e210bdc64de0bd944ab379706`（2026-09-30）
- 许可：BSD 3-Clause，原文见同目录 `LICENSE`。发布包里随框架一起附带。

## 拿了什么

只拿源码，没有拿任何预编译二进制：`bin/mediaremote-adapter.pl`、`include/`、`src/adapter`、
`src/private`、`src/utility`、`src/test`（只为 `test.m` 引用的头文件；测试客户端本身不编）、
`CMakeLists.txt`（只作参照，构建不用 CMake）。文件内容与固定提交逐字一致，没有改动。

## 怎么进构建

`build-adapter.sh OUT_DIR ARCH` 用 clang 按上游 CMakeLists 的参数编出 `MediaRemoteAdapter.framework`
（ARC、符号默认可见、链接 Foundation / AppKit / UniformTypeIdentifiers），只编主程序的那一个架构。

`prototype/build.sh` 在放好 Sparkle 之后调用它：

- 框架放到 `WindowShade.app/Contents/Frameworks/MediaRemoteAdapter.framework`，和 App 同一个身份签名；
- 脚本放到 `WindowShade.app/Contents/Resources/mediaremote-adapter.pl`；
- 编不出来只打警告、不挡构建。`--check` 不编它。

App 端（`prototype/App/NowPlayingStream.swift`）两样都在才用；任何一样缺了，音乐照旧问 Music / Spotify。

## 运行方式

```
/usr/bin/perl <Resources>/mediaremote-adapter.pl <Frameworks>/MediaRemoteAdapter.framework \
  stream --no-diff --no-artwork --micros --debounce=150
```

每次变化一行 JSON。macOS 15.4 起第三方进程直接调私有 MediaRemote 会被拒，系统自带的 perl 不会；
系统更新可能让它再次失效，所以 osascript 退路一直保留。

默认关：`defaults write com.windowshade.prototype Notch.activities.nowPlayingStream -bool true`
（还要实时活动和音乐控制都开着）。

## 升级

换提交时：重新拉源码、对照 diff、改上面的固定提交，跑 `tests/run-notch-activity-tests.sh`，
再在真机上放一首歌，看刘海卡片是否跟着换曲、暂停。
