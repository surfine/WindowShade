# Security

## Reporting a vulnerability

Please don't open a public issue. Use GitHub's [private vulnerability reporting](https://github.com/surfine/WindowShade/security/advisories/new) instead. You'll get a reply within a week. Once a fix ships, the advisory is published with credit to you unless you'd rather stay anonymous.

**中文：** 发现安全问题请不要公开提 issue，用上面的私密报告入口；一周内回复。

## Supported versions

Only the latest release gets security fixes. The app updates itself from the menu (Sparkle, signed with an EdDSA key; every release is Developer ID signed and notarized by Apple).

## What WindowShade touches

- It asks for Accessibility (to move, roll up and read windows) and Screen Recording (for window pictures). Both stay on your Mac.
- Diagnostics and crash reports are kept only on your Mac. Nothing is uploaded; Export diagnostics saves a folder for you to look through, and you decide whether to attach it to a report.
- The only network traffic is the update check (the project website first, GitHub if that fails). Turn off “Check for updates automatically” and it never goes online on its own.

Settings → Privacy lists every kind of data the app reads and where it goes.
