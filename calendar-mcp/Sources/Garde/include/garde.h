#import <Foundation/Foundation.h>
/// Exécute le bloc ; renvoie nil s'il s'est bien passé, sinon la description de l'exception ObjC levée.
NSString * _Nullable mcp_essayer(void (NS_NOESCAPE ^ _Nonnull bloc)(void));
