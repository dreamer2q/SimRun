// MIT License; Copyright (c) 2026 Cyandev. See ../../../LICENSE.
#import <Foundation/Foundation.h>
#include <errno.h>
#include <sys/utsname.h>
#include <sys/sysctl.h>
#ifndef SR_SNAPSHOT
#define SR_SNAPSHOT SRMainSnapshot
#endif
__attribute__((visibility("default"), noinline)) NSDictionary *SR_SNAPSHOT(void) {
  struct utsname value = {0}; uname(&value);
  char machine[256] = {0}; size_t length = sizeof machine;
  sysctlbyname("hw.machine", machine, &length, NULL, 0);
  NSDictionary *environment = NSProcessInfo.processInfo.environment;
  NSBundle *bundle = NSBundle.mainBundle;
  const char *simulator = getenv("SIMULATOR_IDENTITY_FIXTURE");
  const char *simrun = getenv("SIMRUN_IDENTITY_FIXTURE");
  const char *ordinary = getenv("ORDINARY_IDENTITY_FIXTURE");
  const char *simrund = getenv("SIMRUND_SOCKET"), *simns = getenv("SIMNS_IDENTITY_FIXTURE"), *simapp = getenv("SIMAPP_IDENTITY_FIXTURE");
  return @{@"getenvSimulator":simulator ? @(simulator) : NSNull.null,
    @"getenvSimrun":simrun ? @(simrun) : NSNull.null,
    @"getenvSimrund":simrund ? @(simrund) : NSNull.null,
    @"getenvSimns":simns ? @(simns) : NSNull.null,
    @"getenvSimapp":simapp ? @(simapp) : NSNull.null,
    @"environmentSimrund":environment[@"SIMRUND_SOCKET"] ?: NSNull.null,
    @"environmentSimns":environment[@"SIMNS_IDENTITY_FIXTURE"] ?: NSNull.null,
    @"environmentSimapp":environment[@"SIMAPP_IDENTITY_FIXTURE"] ?: NSNull.null,
    @"ordinary":ordinary ? @(ordinary) : NSNull.null,
    @"environmentSimulator":environment[@"SIMULATOR_IDENTITY_FIXTURE"] ?: NSNull.null,
    @"environmentSimrun":environment[@"SIMRUN_IDENTITY_FIXTURE"] ?: NSNull.null,
    @"home":environment[@"HOME"] ?: NSNull.null, @"path":environment[@"PATH"] ?: NSNull.null,
    @"platform":bundle.infoDictionary[@"DTPlatformName"] ?: NSNull.null,
    @"sdk":[bundle objectForInfoDictionaryKey:@"DTSDKName"] ?: NSNull.null,
    @"platforms":[bundle objectForInfoDictionaryKey:@"CFBundleSupportedPlatforms"] ?: NSNull.null,
    @"version":bundle.infoDictionary[@"CFBundleVersion"] ?: NSNull.null,
    @"machine":@(machine), @"unameMachine":@(value.machine)};
}
