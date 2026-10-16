// Native simulator photo library backend. Loaded only into SimRun's assetsd.
// The daemon owns <SIMULATOR_SHARED_RESOURCES_DIRECTORY>/Media, never the Mac's Photos library.
#import <Foundation/Foundation.h>
#import <mach/message.h>
#include <xpc/xpc.h>
#import "common.h"
#include "privacy.h"
#include <unistd.h>

extern uint64_t tcc_authorization_preflight(id service);
extern void tcc_authorization_request(id service, const void *options, void (^reply)(uint64_t));
extern uint64_t tcc_authorization_check_audit_token(id service, audit_token_t token, const void *options);

static BOOL backend(void) {
  const char *data = getenv("SIMULATOR_SHARED_RESOURCES_DIRECTORY");
  return !strcmp(getprogname(), "assetsd") && data && data[0] == '/';
}
static BOOL photo_service(id service) {
  return backend() && [service isKindOfClass:NSString.class] &&
    ([@"kTCCServicePhotos" isEqual:service] || [@"kTCCServicePhotosAdd" isEqual:service]);
}

static uint64_t preflight(id service) {
  // The daemon's own access is to the isolated simulator library. App rights are checked below.
  return photo_service(service) ? 2 : tcc_authorization_preflight(service);
}
static void request(id service, const void *options, void (^reply)(uint64_t)) {
  if (photo_service(service) && reply) { reply(2); return; }
  tcc_authorization_request(service, options, reply);
}
static uint64_t photo_audit(id service, audit_token_t token, const void *options) {
  if (!photo_service(service)) return tcc_authorization_check_audit_token(service, token, options);
  if (token.val[1] != geteuid()) return 0;
  pid_t pid = (pid_t)token.val[5];
  if (pid == getpid()) return 2;
  static xpc_connection_t host; static dispatch_once_t once;
  dispatch_once(&once, ^{ host = SRHostConnect(SRPV_SERVICE, dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), nil); });
  if (!host || pid <= 0) return 0;
  xpc_object_t message = xpc_dictionary_create(NULL, NULL, 0);
  xpc_dictionary_set_string(message, "op", "photo-status");
  xpc_dictionary_set_string(message, "service", [service UTF8String]);
  xpc_dictionary_set_int64(message, "pid", pid);
  xpc_object_t reply = xpc_connection_send_message_with_reply_sync(host, message);
  const char *status = reply && xpc_get_type(reply) == XPC_TYPE_DICTIONARY ? xpc_dictionary_get_string(reply, "status") : NULL;
  return status && !strcmp(status, SRPV_AUTHORIZED) ? 2 : 0;
}

__attribute__((used, section("__DATA,__interpose"))) static struct { const void *n, *o; } interposers[] = {
  { (const void *)preflight, (const void *)tcc_authorization_preflight },
  { (const void *)request, (const void *)tcc_authorization_request },
  { (const void *)photo_audit, (const void *)tcc_authorization_check_audit_token },
};
