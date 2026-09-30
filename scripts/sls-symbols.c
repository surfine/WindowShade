/* 只查导出是否存在，不创建空间、不挪窗口、不锁屏。
 *
 * 编译与运行（在目标 Mac 上）：
 *     xcrun clang -Wall -Wextra -O2 scripts/sls-symbols.c -o /tmp/sls-symbols && /tmp/sls-symbols
 *
 * 退出码：0 = 六个基础符号都在；1 = 少了基础符号；2 = 框架没加载起来。
 *
 * **符号在，不等于 ABI 对、不等于能显示在锁屏上。**这份探针只做第一阶段（导出存在性）；
 * 后面的 ABI、真锁屏可见、完整生命周期各要另外验，见 docs/glance-integration.md。
 * 来源：ChatGPT Pro 的审查里附带的探针（2026-09-30），原样入库便于每台机器、每个系统版本复跑。
 */
#include <dlfcn.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>

struct symbol { const char *name; bool baseline; };

int main(void) {
    const char *paths[] = {
        "/System/Library/PrivateFrameworks/SkyLight.framework/Versions/A/SkyLight",
        "/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight"
    };
    const struct symbol symbols[] = {
        {"SLSMainConnectionID", true},
        {"SLSSpaceCreate", true},
        {"SLSSpaceSetAbsoluteLevel", true},
        {"SLSShowSpaces", true},
        {"SLSSpaceAddWindowsAndRemoveFromSpaces", true},
        {"SLSRemoveWindowsFromSpaces", true},
        {"SLSHideSpaces", false},
        {"SLSSpaceDestroy", false},
        {"SLSCopySpacesForWindows", false},
        {"SLSSpaceGetType", false}
    };
    void *handle = NULL;
    for (size_t i = 0; i < sizeof(paths) / sizeof(paths[0]); ++i) {
        handle = dlopen(paths[i], RTLD_NOW | RTLD_LOCAL);
        if (handle) {
            fprintf(stderr, "loaded: %s\n", paths[i]);
            break;
        }
        const char *error = dlerror();
        fprintf(stderr, "load failed: %s: %s\n", paths[i], error ? error : "unknown error");
    }
    if (!handle) return 2;

    int missing = 0;
    puts("symbol,present,baseline");
    for (size_t i = 0; i < sizeof(symbols) / sizeof(symbols[0]); ++i) {
        (void)dlerror();
        void *address = dlsym(handle, symbols[i].name);
        const char *error = dlerror();
        bool present = address != NULL && error == NULL;
        printf("%s,%s,%s\n", symbols[i].name,
               present ? "YES" : "NO", symbols[i].baseline ? "YES" : "NO");
        if (!present && symbols[i].baseline) ++missing;
    }
    dlclose(handle);
    return missing ? 1 : 0;
}
