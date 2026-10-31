#import "garde.h"
NSString * _Nullable mcp_essayer(void (NS_NOESCAPE ^ _Nonnull bloc)(void)) {
    @try { bloc(); return nil; }
    @catch (NSException *e) { return [NSString stringWithFormat:@"%@: %@", e.name, e.reason ?: @""]; }
}
