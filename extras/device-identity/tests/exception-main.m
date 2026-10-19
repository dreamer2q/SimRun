// MIT License; Copyright (c) 2026 Cyandev. See ../../../LICENSE.
#import <Foundation/Foundation.h>
#include <dlfcn.h>
extern void SRThrowNextIdentityAPI(unsigned mode);
typedef NSDictionary *(*Snapshot)(void);
int main(int argc,const char **argv) {
  @autoreleasepool {
    if (argc!=2) return 2;
    unsigned mode=(unsigned)atoi(argv[1]);
    NSString *path=[NSBundle.mainBundle.bundlePath stringByAppendingPathComponent:@"Frameworks/ThrowOnce.framework/ThrowOnce"];
    Snapshot caller=NULL;
    if (mode==4) {
      void *handle=dlopen(path.fileSystemRepresentation,RTLD_NOW|RTLD_LOCAL);
      caller=handle ? (Snapshot)dlsym(handle,"SRThrowSnapshot") : NULL;
      if (!caller) return 3;
    }
    BOOL hiddenBefore=getenv("SIMULATOR_IDENTITY_FIXTURE")==NULL;
    SRThrowNextIdentityAPI(mode); BOOL caught=NO;
    @try {
      if (mode==1) (void)NSProcessInfo.processInfo.environment;
      else if (mode==2) (void)NSBundle.mainBundle.infoDictionary;
      else if (mode==3) (void)[NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleVersion"];
      else if (mode==4) (void)caller();
      else return 4;
    } @catch(NSException *exception) { caught=[exception.name isEqual:@"FixtureOriginalException"]; }
    BOOL hiddenAfter=getenv("SIMULATOR_IDENTITY_FIXTURE")==NULL;
    BOOL bundleAfter=[NSBundle.mainBundle.infoDictionary[@"DTPlatformName"] isEqual:@"iphoneos"];
    BOOL frameworkAfter=mode!=4 || [caller()[@"machine"] isEqual:@"iPhone18,1"];
    BOOL passed=hiddenBefore && caught && hiddenAfter && bundleAfter && frameworkAfter;
    NSDictionary *result=@{@"passed":@(passed),@"mode":@(mode),@"hiddenBefore":@(hiddenBefore),
      @"caughtOriginal":@(caught),@"hiddenAfter":@(hiddenAfter),@"bundleAfter":@(bundleAfter),@"frameworkAfter":@(frameworkAfter)};
    NSData *data=[NSJSONSerialization dataWithJSONObject:result options:NSJSONWritingPrettyPrinted error:NULL];
    fwrite(data.bytes,1,data.length,stdout); putchar('\n'); return passed ? 0 : 1;
  }
}
