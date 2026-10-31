#import <Foundation/Foundation.h>
@interface NSBundle (HostNibLoading)
- (BOOL)loadNibFile:(NSString *)path externalNameTable:(NSDictionary *)table withZone:(NSZone *)zone;
@end
