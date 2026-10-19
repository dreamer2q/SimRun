// MIT License; Copyright (c) 2026 Cyandev. See ../../LICENSE.
// An opt-in business-facing identity view. Runtime state and Apple callers remain unchanged.
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#include <dlfcn.h>
#include <ctype.h>
#include <errno.h>
#include <limits.h>
#include <mach/mach.h>
#include <mach-o/dyld.h>
#include <pthread.h>
#include <stdatomic.h>
#include <sys/sysctl.h>
#include <sys/utsname.h>

static _Atomic bool SRReady;
static char SRRoot[PATH_MAX], SRExecutable[PATH_MAX], SRFrameworkRoot[PATH_MAX];
static char SRModel[sizeof(((struct utsname *)0)->machine)];
static const void *SROwnImage;
static char **SRInserted;
static size_t SRInsertedCount;
static NSBundle *SRMainBundle;
static NSDictionary *SRPlatformInfo;
static _Thread_local unsigned SRDepth;
static _Atomic unsigned long SRCalls[6];
static pthread_mutex_t SRImageLock = PTHREAD_MUTEX_INITIALIZER;
typedef struct SRImageEntry { const void *base; BOOL allowed; struct SRImageEntry *next; } SRImageEntry;
static SRImageEntry *SRImages;
static NSDictionary *(*SROriginalEnvironment)(id, SEL);
static NSDictionary *(*SROriginalInfo)(id, SEL);
static id (*SROriginalObject)(id, SEL, NSString *);

static BOOL SRHiddenName(const char *name) {
  return name && (!strncmp(name, "SIMULATOR_", 10) || !strncmp(name, "SIMRUN_", 7) ||
    !strncmp(name, "SIMRUND_", 8) || !strncmp(name, "SIMNS_", 6) || !strncmp(name, "SIMAPP_", 7) ||
    !strncmp(name, "DYLD_", 5) || !strncmp(name, "XPC_SIMULATOR_", 14) ||
    !strcmp(name, "IPHONE_SIMULATOR_ROOT"));
}

static BOOL SRClassifyImage(const Dl_info *image) {
  if (!image->dli_fname || image->dli_fbase == SROwnImage) return NO;
  char path[PATH_MAX];
  if (!realpath(image->dli_fname, path)) return NO;
  for (size_t i = 0; i < SRInsertedCount; i++) if (!strcmp(path, SRInserted[i])) return NO;
  if (!strcmp(path, SRExecutable)) return YES;
  size_t prefix = strlen(SRFrameworkRoot);
  if (strncmp(path, SRFrameworkRoot, prefix)) return NO; // prefix ends in '/'
  const char *base = strrchr(path, '/'); base = base ? base + 1 : path;
  if (!strncmp(base, "libswift", 8) || !strncmp(base, "SimRun", 6)) return NO;
  // Apple frameworks copied inside an App are infrastructure, not business code.
  const char *framework = strstr(path + prefix, ".framework/");
  if (framework) {
    size_t length = (size_t)(framework - path) + strlen(".framework");
    NSString *bundlePath = [[NSString alloc] initWithBytes:path length:length encoding:NSUTF8StringEncoding];
    NSString *identifier = [NSBundle bundleWithPath:bundlePath].bundleIdentifier;
    if ([identifier hasPrefix:@"com.apple."]) return NO;
  }
  return YES;
}

// Capture the return address in each replacement itself; a helper's address identifies this module.
__attribute__((noinline)) static BOOL SRBusinessCallerReady(const void *returnAddress) {
  int saved = errno;
  if (SRDepth) return NO;
  SRDepth++;
  BOOL allowed = NO;
  @try {
    Dl_info image = {0};
    if (dladdr(returnAddress, &image) && image.dli_fbase) {
      pthread_mutex_lock(&SRImageLock);
      SRImageEntry *entry = SRImages;
      while (entry && entry->base != image.dli_fbase) entry = entry->next;
      if (entry) allowed = entry->allowed;
      pthread_mutex_unlock(&SRImageLock);
      if (!entry) {
        allowed = SRClassifyImage(&image);
        SRImageEntry *fresh = calloc(1, sizeof *fresh);
        if (fresh) {
          fresh->base = image.dli_fbase; fresh->allowed = allowed;
          pthread_mutex_lock(&SRImageLock); fresh->next = SRImages; SRImages = fresh; pthread_mutex_unlock(&SRImageLock);
        }
      }
    }
  } @finally {
    SRDepth--; errno = saved;
  }
  return allowed;
}

// Interposition is active during libSystem initialization, before TLS exists. Keep all TLS access behind
// a non-inlined ready-only function; otherwise the optimizer can hoist the TLV resolver above the flag test.
__attribute__((noinline)) static BOOL SRBusinessCaller(const void *returnAddress) {
  if (!atomic_load_explicit(&SRReady, memory_order_acquire)) return NO;
  return SRBusinessCallerReady(returnAddress);
}

__attribute__((noinline)) static char *SRGetenv(const char *name) {
  if (SRBusinessCaller(__builtin_return_address(0)) && SRHiddenName(name)) {
    atomic_fetch_add(&SRCalls[0], 1); return NULL;
  }
  return getenv(name); // dyld does not interpose an image's references to its own replacements' originals
}

__attribute__((noinline)) static NSDictionary *SREnvironment(id self, SEL selector) {
  BOOL business = SRBusinessCaller(__builtin_return_address(0));
  NSDictionary *original;
  SRDepth++;
  @try { original = SROriginalEnvironment(self, selector); } @finally { SRDepth--; }
  if (!business || !original) return original;
  NSMutableDictionary *view = [original mutableCopy];
  for (id key in original) if ([key isKindOfClass:NSString.class] && SRHiddenName([key UTF8String])) [view removeObjectForKey:key];
  atomic_fetch_add(&SRCalls[1], 1);
  return [view copy];
}

__attribute__((noinline)) static NSDictionary *SRInfo(id self, SEL selector) {
  BOOL business = SRBusinessCaller(__builtin_return_address(0)) && self == SRMainBundle;
  NSDictionary *original;
  SRDepth++;
  @try { original = SROriginalInfo(self, selector); } @finally { SRDepth--; }
  if (!business || !original) return original;
  NSMutableDictionary *view = [original mutableCopy]; [view addEntriesFromDictionary:SRPlatformInfo];
  atomic_fetch_add(&SRCalls[2], 1);
  return [view copy];
}

__attribute__((noinline)) static id SRObject(id self, SEL selector, NSString *key) {
  if (SRBusinessCaller(__builtin_return_address(0)) && self == SRMainBundle && [key isKindOfClass:NSString.class]) {
    id value = SRPlatformInfo[key];
    if (value) { atomic_fetch_add(&SRCalls[2], 1); return value; }
  }
  id result;
  SRDepth++;
  @try { result = SROriginalObject(self, selector, key); } @finally { SRDepth--; }
  return result;
}

__attribute__((noinline)) static int SRUname(struct utsname *value) {
  BOOL business = SRBusinessCaller(__builtin_return_address(0));
  int result = uname(value), saved = errno;
  if (!result && business) { strlcpy(value->machine, SRModel, sizeof value->machine); atomic_fetch_add(&SRCalls[3], 1); }
  errno = saved; return result;
}

// Safe copy-in/out preserves EFAULT for invalid user pointers instead of crashing in memcpy.
// vm_address_t is pointer sized on the supported arm64 targets.
static BOOL SRReadSize(const size_t *address, size_t *value) {
  vm_size_t copied = 0;
  return vm_read_overwrite(mach_task_self(), (vm_address_t)address, sizeof *value,
    (vm_address_t)value, &copied) == KERN_SUCCESS && copied == sizeof *value;
}
static BOOL SRWrite(void *destination, const void *source, size_t length) {
  return vm_write(mach_task_self(), (vm_address_t)destination, (vm_offset_t)source,
    (mach_msg_type_number_t)length) == KERN_SUCCESS;
}
static int SRMachine(void *oldp, size_t *oldlenp) {
  int saved = errno; size_t length = strlen(SRModel) + 1;
  if (!oldp) {
    if (!SRWrite(oldlenp, &length, sizeof length)) { errno = EFAULT; return -1; }
    errno = saved; return 0;
  }
  size_t capacity;
  if (!SRReadSize(oldlenp, &capacity)) { errno = EFAULT; return -1; }
  if (capacity < length) {
    size_t zero = 0;
    if (!SRWrite(oldlenp, &zero, sizeof zero)) { errno = EFAULT; return -1; }
    errno = ENOMEM; return -1;
  }
  if (!SRWrite(oldp, SRModel, length) || !SRWrite(oldlenp, &length, sizeof length)) { errno = EFAULT; return -1; }
  errno = saved; return 0;
}
__attribute__((noinline)) static int SRSysctlbyname(const char *name, void *oldp, size_t *oldlenp, void *newp, size_t newlen) {
  if (SRBusinessCaller(__builtin_return_address(0)) && name && !strcmp(name, "hw.machine") && oldlenp && !newp && !newlen) {
    atomic_fetch_add(&SRCalls[4], 1); return SRMachine(oldp, oldlenp);
  }
  return sysctlbyname(name, oldp, oldlenp, newp, newlen);
}
__attribute__((noinline)) static int SRSysctl(int *name, u_int namelen, void *oldp, size_t *oldlenp, void *newp, size_t newlen) {
  if (SRBusinessCaller(__builtin_return_address(0)) && name && namelen == 2 && oldlenp && !newp && !newlen) {
    int saved = errno, mib[2]; vm_size_t copied = 0;
    BOOL readable = vm_read_overwrite(mach_task_self(), (vm_address_t)name, sizeof mib,
      (vm_address_t)mib, &copied) == KERN_SUCCESS && copied == sizeof mib;
    errno = saved;
    if (readable && mib[0] == CTL_HW && mib[1] == HW_MACHINE) {
      atomic_fetch_add(&SRCalls[5], 1); return SRMachine(oldp, oldlenp);
    }
  }
  return sysctl(name, namelen, oldp, oldlenp, newp, newlen);
}
__attribute__((used, section("__DATA,__interpose"))) static struct { const void *replacement, *original; } SRInterposers[] = {
  {(void *)SRGetenv, (void *)getenv}, {(void *)SRUname, (void *)uname},
  {(void *)SRSysctlbyname, (void *)sysctlbyname}, {(void *)SRSysctl, (void *)sysctl}
};

static void SRReplace(Class target, SEL selector, IMP replacement) {
  Method method = class_getInstanceMethod(target, selector);
  if (!class_addMethod(target, selector, replacement, method_getTypeEncoding(method))) method_setImplementation(method, replacement);
}

static void SRImageRemoved(const struct mach_header *header, intptr_t slide) {
  (void)slide;
  pthread_mutex_lock(&SRImageLock);
  SRImageEntry **slot = &SRImages;
  while (*slot) {
    SRImageEntry *entry = *slot;
    if (entry->base == header) { *slot = entry->next; free(entry); }
    else slot = &entry->next;
  }
  pthread_mutex_unlock(&SRImageLock);
}

@interface SRDeviceIdentity : NSObject
+ (NSDictionary *)status;
@end
@implementation SRDeviceIdentity
+ (NSDictionary *)status {
  NSMutableArray *calls = [NSMutableArray array];
  for (unsigned i = 0; i < 6; i++) [calls addObject:@(atomic_load(&SRCalls[i]))];
  return @{@"enabled":@(atomic_load_explicit(&SRReady, memory_order_acquire)), @"model":@(SRModel), @"calls":calls,
    @"scope":@"main executable and embedded business Frameworks; direct caller only"};
}
@end

__attribute__((constructor)) static void SRInstallIdentity(void) {
  @autoreleasepool {
    const char *enabled = getenv("SIMRUN_DEVICE_IDENTITY");
    if (!enabled || strcmp(enabled, "1")) return;
    const char *root = getenv("SIMRUN_DEVICE_IDENTITY_APP_ROOT");
    const char *model = getenv("SIMRUN_DEVICE_IDENTITY_MODEL");
    const char *infoPath = getenv("SIMRUN_DEVICE_IDENTITY_ORIGINAL_INFO");
    if (!root || root[0] != '/' || !realpath(root, SRRoot) || !model || !infoPath || infoPath[0] != '/') return;
    size_t length = strlen(model);
    if (!length || length >= sizeof SRModel || (strncmp(model, "iPhone", 6) && strncmp(model, "iPad", 4) && strncmp(model, "iPod", 4))) return;
    for (const char *c = model; *c; c++) if (!isalnum((unsigned char)*c) && *c != ',') return;
    SRMainBundle = NSBundle.mainBundle;
    char actualRoot[PATH_MAX];
    if (!realpath(SRMainBundle.bundlePath.fileSystemRepresentation, actualRoot) || strcmp(actualRoot, SRRoot) ||
        !realpath(SRMainBundle.executablePath.fileSystemRepresentation, SRExecutable)) return;
    int frameworkLength = snprintf(SRFrameworkRoot, sizeof SRFrameworkRoot, "%s/Frameworks/", SRRoot);
    if (frameworkLength < 0 || (size_t)frameworkLength >= sizeof SRFrameworkRoot) return;
    NSDictionary *source = [NSDictionary dictionaryWithContentsOfFile:@(infoPath)];
    if (![source[@"DTPlatformName"] isEqual:@"iphoneos"] || ![source[@"DTSDKName"] isKindOfClass:NSString.class] ||
        ![source[@"DTSDKName"] hasPrefix:@"iphoneos"] || ![source[@"CFBundleSupportedPlatforms"] isKindOfClass:NSArray.class] ||
        ![source[@"CFBundleSupportedPlatforms"] containsObject:@"iPhoneOS"]) return;
    SRPlatformInfo = @{ @"DTPlatformName":source[@"DTPlatformName"], @"DTSDKName":source[@"DTSDKName"],
                       @"CFBundleSupportedPlatforms":[source[@"CFBundleSupportedPlatforms"] copy] };
    strlcpy(SRModel, model, sizeof SRModel);
    Dl_info own = {0}; if (dladdr((void *)SRInstallIdentity, &own)) SROwnImage = own.dli_fbase;
    const char *inserted = getenv("DYLD_INSERT_LIBRARIES");
    if (inserted) {
      for (NSString *path in [@(inserted) componentsSeparatedByString:@":"]) {
        char canonical[PATH_MAX]; if (!realpath(path.fileSystemRepresentation, canonical)) continue;
        char **next = realloc(SRInserted, (SRInsertedCount + 1) * sizeof *next);
        if (!next) return;
        SRInserted = next; SRInserted[SRInsertedCount] = strdup(canonical);
        if (!SRInserted[SRInsertedCount]) return;
        SRInsertedCount++;
      }
    }
    Class processClass = object_getClass(NSProcessInfo.processInfo), bundleClass = object_getClass(SRMainBundle);
    Method environmentMethod = class_getInstanceMethod(processClass, @selector(environment));
    Method infoMethod = class_getInstanceMethod(bundleClass, @selector(infoDictionary));
    Method objectMethod = class_getInstanceMethod(bundleClass, @selector(objectForInfoDictionaryKey:));
    if (!environmentMethod || !infoMethod || !objectMethod) return;
    // Publish all originals before installing any replacement: a thread may enter immediately after exchange.
    SROriginalEnvironment = (void *)method_getImplementation(environmentMethod);
    SROriginalInfo = (void *)method_getImplementation(infoMethod);
    SROriginalObject = (void *)method_getImplementation(objectMethod);
    SRReplace(processClass, @selector(environment), (IMP)SREnvironment);
    SRReplace(bundleClass, @selector(infoDictionary), (IMP)SRInfo);
    SRReplace(bundleClass, @selector(objectForInfoDictionaryKey:), (IMP)SRObject);
    _dyld_register_func_for_remove_image(SRImageRemoved);
    atomic_store_explicit(&SRReady, true, memory_order_release);
  }
}
