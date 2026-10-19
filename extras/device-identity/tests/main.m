// MIT License; Copyright (c) 2026 Cyandev. See ../../../LICENSE.
#import <Foundation/Foundation.h>
#import <objc/message.h>
#include <dlfcn.h>
#include <errno.h>
#include <sys/sysctl.h>
#include <stdatomic.h>
extern NSDictionary *SRMainSnapshot(void);
typedef NSDictionary *(*Snapshot)(void);
static NSMutableArray *Checks;
static void Check(BOOL condition, NSString *name) { [Checks addObject:@{@"name":name,@"passed":@(condition)}]; }
static NSDictionary *LoadSnapshot(NSString *path, const char *symbol) {
  void *handle = dlopen(path.fileSystemRepresentation, RTLD_NOW | RTLD_GLOBAL);
  Snapshot function = handle ? (Snapshot)dlsym(handle, symbol) : NULL;
  Check(function != NULL, [NSString stringWithFormat:@"load %s",symbol]);
  return function ? function() : @{};
}
int main(int argc, const char **argv) {
  @autoreleasepool {
    if (argc != 3) return 2;
    Checks = [NSMutableArray array];
    BOOL enabled = !strcmp(argv[2], "enabled");
    NSString *base = @(argv[1]), *root = NSBundle.mainBundle.bundlePath;
    NSDictionary *main = SRMainSnapshot();
    NSDictionary *framework = LoadSnapshot([root stringByAppendingPathComponent:@"Frameworks/Business.framework/Business"], "SRFrameworkSnapshot");
    NSDictionary *external = LoadSnapshot([base stringByAppendingPathComponent:@"External.dylib"], "SRExternalSnapshot");
    NSDictionary *apple = LoadSnapshot([root stringByAppendingPathComponent:@"Frameworks/AppleFixture.framework/AppleFixture"], "SRAppleSnapshot");
    NSDictionary *injected = LoadSnapshot([root stringByAppendingPathComponent:@"Frameworks/Injected.dylib"], "SRInjectedSnapshot");
    NSString *model = @"iPhone18,1";
    for (NSDictionary *view in @[main, framework]) {
      Check(enabled ? view[@"getenvSimulator"] == NSNull.null : [view[@"getenvSimulator"] isEqual:@"simulator-marker"], @"business getenv scope");
      Check(enabled ? view[@"getenvSimrun"] == NSNull.null : [view[@"getenvSimrun"] isEqual:@"simrun-marker"], @"business SimRun scope");
      Check(enabled ? view[@"environmentSimulator"] == NSNull.null : [view[@"environmentSimulator"] isEqual:@"simulator-marker"], @"business environment scope");
      BOOL getenvControls=YES, environmentControls=YES;
      for (NSString *key in @[@"getenvSimrund",@"getenvSimns",@"getenvSimapp"])
        getenvControls &= enabled ? view[key]==NSNull.null : [view[key] isEqual:@"control-marker"];
      for (NSString *key in @[@"environmentSimrund",@"environmentSimns",@"environmentSimapp"])
        environmentControls &= enabled ? view[key]==NSNull.null : [view[key] isEqual:@"control-marker"];
      Check(getenvControls,@"business getenv internal control domains scoped");
      Check(environmentControls,@"business environment internal control domains scoped");
      Check([view[@"platform"] isEqual:enabled ? @"iphoneos" : @"iphonesimulator"], @"business bundle platform");
      Check([view[@"sdk"] isEqual:enabled ? @"iphoneos27.1" : @"iphonesimulator27.1"], @"business bundle SDK");
      Check([view[@"machine"] isEqual:enabled ? model : external[@"machine"]], @"business sysctl machine");
      Check([view[@"unameMachine"] isEqual:enabled ? model : external[@"unameMachine"]], @"business uname machine");
      Check([view[@"version"] isEqual:@"123"], @"business version preserved");
      Check([view[@"ordinary"] isEqual:@"ordinary-value"] && [view[@"home"] isEqual:external[@"home"]] && [view[@"path"] isEqual:external[@"path"]], @"ordinary environment HOME PATH preserved");
    }
    for (NSDictionary *view in @[external, apple, injected]) {
      Check([view[@"getenvSimulator"] isEqual:@"simulator-marker"] && [view[@"environmentSimulator"] isEqual:@"simulator-marker"], @"infrastructure environment preserved");
      BOOL controlsPreserved=YES;
      for (NSString *key in @[@"getenvSimrund",@"getenvSimns",@"getenvSimapp",@"environmentSimrund",@"environmentSimns",@"environmentSimapp"])
        controlsPreserved &= [view[key] isEqual:@"control-marker"];
      Check(controlsPreserved,@"infrastructure internal control domains preserved");
      Check([view[@"platform"] isEqual:@"iphonesimulator"] && [view[@"sdk"] isEqual:@"iphonesimulator27.1"], @"infrastructure bundle preserved");
      Check([view[@"machine"] isEqual:external[@"machine"]] && [view[@"unameMachine"] isEqual:external[@"unameMachine"]], @"infrastructure machine preserved");
    }
    NSBundle *other = [NSBundle bundleWithPath:[base stringByAppendingPathComponent:@"Other.bundle"]];
    Check([other.infoDictionary[@"DTPlatformName"] isEqual:@"iphonesimulator"] && [[other objectForInfoDictionaryKey:@"DTSDKName"] isEqual:@"iphonesimulator27.1"], @"other bundle unmodified");
    if (enabled) {
      size_t length = 0; errno = 123;
      int status = sysctlbyname("hw.machine",NULL,&length,NULL,0);
      Check(!status && length == model.length + 1 && errno == 123, @"sysctl size query includes NUL and preserves errno");
      const size_t capacities[] = {0,1,9,10,11,64};
      for (unsigned i=0; i<sizeof capacities/sizeof capacities[0]; i++) {
        char buffer[64]; memset(buffer,0x5a,sizeof buffer); length=capacities[i]; errno=123;
        status=sysctlbyname("hw.machine",buffer,&length,NULL,0);
        if (capacities[i] < model.length+1) Check(status==-1 && errno==ENOMEM && !length && buffer[0]==0x5a, @"sysctl short buffer leaves bytes unchanged and reports zero length");
        else Check(!status && errno==123 && length==model.length+1 && !strcmp(buffer,model.UTF8String) && buffer[length]==0x5a, @"sysctl adequate buffer writes only string and NUL");
      }
      int mib[]={CTL_HW,HW_MACHINE}; char buffer[64]={0}; length=sizeof buffer; errno=123;
      status=sysctl(mib,2,buffer,&length,NULL,0);
      Check(!status && !strcmp(buffer,model.UTF8String) && length==model.length+1 && errno==123,@"sysctl MIB agrees");
      length=sizeof buffer; errno=0; status=sysctlbyname("hw.machine",(void *)1,&length,NULL,0);
      Check(status==-1 && errno==EFAULT,@"invalid output pointer returns EFAULT");
      errno=0; status=sysctlbyname("hw.machine",NULL,(size_t *)1,NULL,0);
      Check(status==-1 && errno==EFAULT,@"invalid length pointer returns EFAULT");
      char operatingSystem[128]={0}; length=sizeof operatingSystem;
      status=sysctlbyname("kern.ostype",operatingSystem,&length,NULL,0);
      Check(!status && !strcmp(operatingSystem,"Darwin"),@"unknown sysctl keys pass through");
      _Atomic unsigned failures=0; _Atomic unsigned *failureCounter=&failures;
      dispatch_apply(300,dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^(size_t index) {
        (void)index;
        @autoreleasepool {
          NSDictionary *business=SRMainSnapshot();
          Snapshot original=(Snapshot)dlsym(RTLD_DEFAULT,"SRExternalSnapshot");
          if (![business[@"machine"] isEqual:model] || business[@"getenvSimulator"] != NSNull.null || (original && ![original()[@"getenvSimulator"] isEqual:@"simulator-marker"])) atomic_fetch_add(failureCounter,1);
        }
      });
      Check(atomic_load(&failures)==0,@"300 concurrent scoped snapshots");
      Class identity=NSClassFromString(@"SRDeviceIdentity");
      NSDictionary *state=((id (*)(id,SEL))objc_msgSend)(identity,@selector(status));
      Check([state[@"enabled"] boolValue],@"status enabled");
    }
    BOOL passed=YES; for (NSDictionary *check in Checks) if (![check[@"passed"] boolValue]) passed=NO;
    NSDictionary *report=@{@"passed":@(passed),@"enabled":@(enabled),@"checks":Checks,@"main":main,@"framework":framework,@"external":external,@"apple":apple,@"injected":injected};
    NSData *data=[NSJSONSerialization dataWithJSONObject:report options:NSJSONWritingPrettyPrinted error:NULL];
    fwrite(data.bytes,1,data.length,stdout); putchar('\n');
    return passed ? 0 : 1;
  }
}
