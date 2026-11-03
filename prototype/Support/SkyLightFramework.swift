// SkyLight（WindowServer 私有框架）的加载路径。历史上有带不带 `Versions/A` 两种写法，
// dyld 都解析到同一份库；统一走这里。

import Foundation

enum SkyLightFramework {
    static let path = "/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight"
}
