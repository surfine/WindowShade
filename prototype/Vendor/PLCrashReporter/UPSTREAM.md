# PLCrashReporter（vendored，只落本地的崩溃报告，规格 R13）

- 上游：https://github.com/microsoft/plcrashreporter ，版本 1.12.0（官方发布页里最新带预编译包的一版；1.12.1／1.12.2 只有源码标签，没有发布包）
- 取的是官方发布的 `PLCrashReporter-Static-1.12.0.zip`
  （https://github.com/microsoft/plcrashreporter/releases/download/1.12.0/PLCrashReporter-Static-1.12.0.zip）
  - 压缩包 SHA-256：`36a00c3d546331fad9c13eb62d99d5c7e6e9eb4900f75853bebb1d01884f9b8a`
  - 发布页没有给校验和或签名，这个值是下载后自己算的，用来核对以后重下的包是同一个
- 许可：MIT 为主，附带 protobuf-c 等的条款，原文见同目录 `LICENSE`，发布包的 THIRD-PARTY-LICENSES.txt 里随附。
- 拿了什么：`libCrashReporter-MacOSX-Static.a`（arm64 + x86_64 静态库）、`include/` 里的头文件（原样）、`LICENSE`。
  只多加了一个 `include/module.modulemap`（让 swiftc 能 import），不改头文件。

## 怎么进构建

静态链接进主程序：不是框架，不进 Contents/Frameworks，没有额外的嵌套代码要签名；随主程序一次签完。
`prototype/build.sh` 加 `-I Vendor/PLCrashReporter/include`、链接这个 .a 以及 `-lc++ -lz`。
App 端见 `Support/CrashReporting.swift`：启动时启用（Mach 异常方式）、下次启动把上次的报告转成文本存本地。
**没有任何联网代码**：崩溃库只写本机缓存目录，我们只把文本放进 `~/Library/Logs/WindowShade/crash-reports/`。

## 升级

重新下官方发布包，核对 SHA-256，替换 .a 和 include/，改本文件的版本与校验和，以及 build.sh、
THIRD-PARTY-LICENSES.md、THIRD-PARTY-LICENSES.txt 里的版本号。
