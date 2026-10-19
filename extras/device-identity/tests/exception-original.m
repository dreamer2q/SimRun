// MIT License; Copyright (c) 2026 Cyandev. See ../../../LICENSE.
// Based on the independent reviewer's throw-once environment-IMP reproduction.
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#include <stdatomic.h>
static _Atomic unsigned SRThrowMode;
static NSBundle *SRFixtureBundle;
static NSDictionary *(*SREnvironmentBefore)(id,SEL), *(*SRInfoBefore)(id,SEL);
static id (*SRObjectBefore)(id,SEL,id), (*SRBundleBefore)(id,SEL,id);
static void SRThrow(void) {
  @throw [NSException exceptionWithName:@"FixtureOriginalException" reason:@"deliberate preserved-IMP exception" userInfo:nil];
}
static NSDictionary *SREnvironmentOnce(id self,SEL cmd) {
  if (atomic_load(&SRThrowMode)==1) { atomic_store(&SRThrowMode,0); SRThrow(); }
  return SREnvironmentBefore(self,cmd);
}
static NSDictionary *SRInfoOnce(id self,SEL cmd) {
  if (self==SRFixtureBundle && atomic_load(&SRThrowMode)==2) { atomic_store(&SRThrowMode,0); SRThrow(); }
  return SRInfoBefore(self,cmd);
}
static id SRObjectOnce(id self,SEL cmd,id key) {
  if (self==SRFixtureBundle && atomic_load(&SRThrowMode)==3) { atomic_store(&SRThrowMode,0); SRThrow(); }
  return SRObjectBefore(self,cmd,key);
}
static id SRBundleOnce(id self,SEL cmd,NSString *path) {
  if (atomic_load(&SRThrowMode)==4 && [path containsString:@"/ThrowOnce.framework"]) { atomic_store(&SRThrowMode,0); SRThrow(); }
  return SRBundleBefore(self,cmd,path);
}
void SRThrowNextIdentityAPI(unsigned mode) { atomic_store(&SRThrowMode,mode); }
static IMP SRInstall(Class cls, SEL selector, IMP replacement) {
  Method method=class_getInstanceMethod(cls,selector); IMP previous=method_getImplementation(method);
  if (!class_addMethod(cls,selector,replacement,method_getTypeEncoding(method))) method_setImplementation(method,replacement);
  return previous;
}
__attribute__((constructor)) static void SRInstallOriginal(void) {
  SRFixtureBundle=NSBundle.mainBundle;
  SREnvironmentBefore=(void *)SRInstall(object_getClass(NSProcessInfo.processInfo),@selector(environment),(IMP)SREnvironmentOnce);
  SRInfoBefore=(void *)SRInstall(object_getClass(SRFixtureBundle),@selector(infoDictionary),(IMP)SRInfoOnce);
  SRObjectBefore=(void *)SRInstall(object_getClass(SRFixtureBundle),@selector(objectForInfoDictionaryKey:),(IMP)SRObjectOnce);
  SRBundleBefore=(void *)SRInstall(object_getClass(NSBundle.class),@selector(bundleWithPath:),(IMP)SRBundleOnce);
}
