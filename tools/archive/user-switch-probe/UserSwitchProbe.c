// READ-ONLY inventory of the fast-user-switching surface on this Mac. It never calls a switching, locking
// or logout function: private symbols are only looked up with dlsym, not invoked. User names are redacted.
#include <dlfcn.h>
#include <stdio.h>
#include <string.h>
#include <CoreFoundation/CoreFoundation.h>
#include <sys/stat.h>
extern CFDictionaryRef CGSessionCopyCurrentDictionary(void);   // public, read-only
int main(void) {
    struct stat st;
    const char *paths[] = {
        "/System/Library/CoreServices/Menu Extras/User.menu/Contents/Resources/CGSession",
        "/System/Library/CoreServices/Menu Extras/User.menu",
        "/System/Library/CoreServices/loginwindow.app", 0 };
    for (int i = 0; paths[i]; i++) printf("path %-84s %s\n", paths[i], stat(paths[i], &st) == 0 ? "exists" : "missing");
    void *h = dlopen("/System/Library/PrivateFrameworks/login.framework/login", RTLD_NOW);
    printf("login.framework dlopen %s\n", h ? "ok" : "failed");
    const char *syms[] = { "SACSwitchToUser", "SACSwitchToLoginWindow", "SACLockScreenImmediate", "SACScreenSaverStartNow",
                           "SACScreenSaverIsRunning", "SACShieldWindowShowing", "SACSwitchToUserID", 0 };
    for (int i = 0; h && syms[i]; i++) printf("login!%-26s %s\n", syms[i], dlsym(h, syms[i]) ? "present(not called)" : "absent");
    CFDictionaryRef d = CGSessionCopyCurrentDictionary();
    if (d) {
        CFIndex n = CFDictionaryGetCount(d); const void *k[64], *v[64];
        if (n > 64) n = 64; CFDictionaryGetKeysAndValues(d, k, v);
        for (CFIndex i = 0; i < n; i++) {
            char kb[128], vb[160]; CFStringGetCString(k[i], kb, sizeof kb, kCFStringEncodingUTF8);
            if (strstr(kb, "UserName") || strstr(kb, "UniqueSessionUUID")) { printf("session %-34s <redacted>\n", kb); continue; }
            CFStringRef s = CFCopyDescription(v[i]); CFStringGetCString(s, vb, sizeof vb, kCFStringEncodingUTF8); CFRelease(s);
            char *b = strstr(vb, "{"); printf("session %-34s %s\n", kb, b ? b : vb);
        }
    }
    return 0;
}
