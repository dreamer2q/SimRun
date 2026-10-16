// Run against disposable SIMRUN_DATA. Keeps only its generated/imported image for picker inspection.
// Build: make core build/apps/PhotoTest.app
// Run: SIMRUN_PHOTO_LIBRARY=1 build/bin/simrun run --headless -p photo-test build/apps/PhotoTest.app
// Repeat with --authorized to check persistence. Fresh profiles: --no-request, --add-only;
// --denied expects SIMRUN_PHOTO_LIBRARY=0 or an App copy without photo usage descriptions.
#import <UIKit/UIKit.h>
#import <Photos/Photos.h>
#import <ImageIO/ImageIO.h>
#import "common.h"
#include "privacy.h"
#include <unistd.h>

static NSMutableArray *checks;
static void Check(NSString *name, BOOL pass) { [checks addObject:@{@"name": name, @"passed": @(pass)}]; }
static void Finish(void) {
  NSUInteger failures = 0;
  for (NSDictionary *c in checks) if (![c[@"passed"] boolValue]) failures++;
  NSDictionary *result = @{@"passed": @(failures == 0), @"failed_count": @(failures), @"checks": checks};
  NSData *json = [NSJSONSerialization dataWithJSONObject:result options:NSJSONWritingPrettyPrinted error:NULL];
  puts([[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding].UTF8String); fflush(stdout);
  exit(failures ? 1 : 0);
}
static BOOL HostAllows(pid_t pid, const char *service) {
  xpc_connection_t host = SRHostConnect(SRPV_SERVICE, dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), nil);
  if (!host) return NO;
  xpc_object_t m = xpc_dictionary_create(NULL, NULL, 0);
  xpc_dictionary_set_string(m, "op", "photo-status"); xpc_dictionary_set_string(m, "service", service);
  xpc_dictionary_set_int64(m, "pid", pid);
  xpc_object_t reply = xpc_connection_send_message_with_reply_sync(host, m);
  const char *status = reply && xpc_get_type(reply) == XPC_TYPE_DICTIONARY ? xpc_dictionary_get_string(reply, "status") : NULL;
  xpc_connection_cancel(host);
  return status && !strcmp(status, SRPV_AUTHORIZED);
}
static NSURL *Fixture(void) {
  UIGraphicsBeginImageContextWithOptions(CGSizeMake(256, 192), YES, 1);
  [UIColor.systemBlueColor setFill]; UIRectFill(CGRectMake(0, 0, 256, 192));
  [UIColor.systemOrangeColor setFill]; UIRectFill(CGRectMake(128, 0, 128, 192));
  UIImage *image = UIGraphicsGetImageFromCurrentImageContext(); UIGraphicsEndImageContext();
  NSURL *url = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:@"photo-fixture.png"]];
  return [UIImagePNGRepresentation(image) writeToURL:url atomically:YES] ? url : nil;
}
static NSString *Import(NSURL *url) {
  __block NSString *identifier; NSError *error = nil;
  BOOL ok = [PHPhotoLibrary.sharedPhotoLibrary performChangesAndWait:^{
    PHAssetChangeRequest *request = [PHAssetChangeRequest creationRequestForAssetFromImageAtFileURL:url];
    identifier = request.placeholderForCreatedAsset.localIdentifier;
  } error:&error];
  if (error) fprintf(stderr, "[phototest] import error %s %ld\n", error.domain.UTF8String, (long)error.code);
  return ok ? identifier : nil;
}
int main(int argc, char **argv) { @autoreleasepool {
  checks = [NSMutableArray array];
  BOOL noRequest = argc == 2 && !strcmp(argv[1], "--no-request");
  BOOL denied = argc == 2 && !strcmp(argv[1], "--denied");
  BOOL authorized = argc == 2 && !strcmp(argv[1], "--authorized");
  BOOL addOnly = argc == 2 && !strcmp(argv[1], "--add-only");
  NSString *input = argc == 3 && !strcmp(argv[1], "--import") ? @(argv[2]) : nil;
  if (argc != 1 && !noRequest && !denied && !authorized && !addOnly && !input) return 2;
  PHAuthorizationStatus initial = [PHPhotoLibrary authorizationStatusForAccessLevel:PHAccessLevelReadWrite];
  Check(@"unknown_pid_denied", !HostAllows(2147483647, "kTCCServicePhotos"));
  Check(@"unrelated_service_denied", !HostAllows(getpid(), "kTCCServiceCamera"));
  if (authorized) {
    Check(@"authorization_persisted", initial == PHAuthorizationStatusAuthorized);
    Check(@"host_authorization_persisted", HostAllows(getpid(), "kTCCServicePhotos"));
    Check(@"import_persisted", [PHAsset fetchAssetsWithMediaType:PHAssetMediaTypeImage options:nil].count > 0); Finish();
  }
  if (noRequest) {
    Check(@"fresh_status_not_determined", initial == PHAuthorizationStatusNotDetermined);
    Check(@"backend_denies_unrequested_access", !HostAllows(getpid(), "kTCCServicePhotos")); Finish();
  }
  dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 30 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{ Check(@"completed_before_timeout", NO); Finish(); });
  [PHPhotoLibrary requestAuthorizationForAccessLevel:addOnly ? PHAccessLevelAddOnly : PHAccessLevelReadWrite handler:^(PHAuthorizationStatus status) { @autoreleasepool {
    if (denied) {
      Check(@"permission_denied", status == PHAuthorizationStatusDenied);
      Check(@"backend_denies_opted_out_or_missing_usage", !HostAllows(getpid(), "kTCCServicePhotos")); Finish();
    }
    if (addOnly) {
      Check(@"add_only_authorized", status == PHAuthorizationStatusAuthorized);
      Check(@"host_allows_add_only", HostAllows(getpid(), "kTCCServicePhotosAdd"));
      Check(@"add_only_does_not_grant_read", !HostAllows(getpid(), "kTCCServicePhotos"));
      Check(@"add_only_read_status_not_authorized", [PHPhotoLibrary authorizationStatusForAccessLevel:PHAccessLevelReadWrite] != PHAuthorizationStatusAuthorized);
      Check(@"add_only_imports_image", Import(Fixture()).length > 0); Finish();
    }
    Check(@"read_write_authorized", status == PHAuthorizationStatusAuthorized);
    if (status != PHAuthorizationStatusAuthorized) Finish();
    Check(@"legacy_authorized", PHPhotoLibrary.authorizationStatus == PHAuthorizationStatusAuthorized);
    Check(@"host_allows_active_authorized_app", HostAllows(getpid(), "kTCCServicePhotos"));
    Check(@"read_write_includes_add_permission", HostAllows(getpid(), "kTCCServicePhotosAdd"));
    Check(@"read_write_includes_add_status", [PHPhotoLibrary authorizationStatusForAccessLevel:PHAccessLevelAddOnly] == PHAuthorizationStatusAuthorized);
    NSURL *url = input ? [NSURL fileURLWithPath:input] : Fixture();
    Check(@"input_available", url && [NSFileManager.defaultManager fileExistsAtPath:url.path]);
    if (!url) Finish();
    NSUInteger before = [PHAsset fetchAssetsWithMediaType:PHAssetMediaTypeImage options:nil].count;
    NSString *identifier = Import(url);
    Check(@"image_imported", identifier.length > 0);
    if (!identifier) Finish();
    PHAsset *asset = [PHAsset fetchAssetsWithLocalIdentifiers:@[identifier] options:nil].firstObject;
    fprintf(stderr,"[phototest] mediaType=%ld width=%lu height=%lu before=%lu after=%lu\n",(long)asset.mediaType,(unsigned long)asset.pixelWidth,(unsigned long)asset.pixelHeight,(unsigned long)before,(unsigned long)[PHAsset fetchAssetsWithOptions:nil].count);
    Check(@"asset_fetchable", asset && asset.mediaType == PHAssetMediaTypeImage && asset.pixelWidth && asset.pixelHeight);
    if (!asset) Finish();
    Check(@"asset_count_incremented", [PHAsset fetchAssetsWithMediaType:PHAssetMediaTypeImage options:nil].count == before + 1);
    PHAssetCollection *album = [PHAssetCollection fetchAssetCollectionsWithType:PHAssetCollectionTypeSmartAlbum subtype:PHAssetCollectionSubtypeSmartAlbumUserLibrary options:nil].firstObject;
    Check(@"user_album_available", album != nil);
    Check(@"user_album_contains_import", album && [PHAsset fetchAssetsInAssetCollection:album options:nil].count >= 1);
    PHImageRequestOptions *options = [PHImageRequestOptions new]; options.synchronous = YES;
    options.deliveryMode = PHImageRequestOptionsDeliveryModeHighQualityFormat;
    __block BOOL thumbnail = NO, original = NO;
    [PHImageManager.defaultManager requestImageForAsset:asset targetSize:CGSizeMake(80, 80) contentMode:PHImageContentModeAspectFit options:options resultHandler:^(UIImage *image, NSDictionary *info) {
      thumbnail = image.CGImage && CGImageGetWidth(image.CGImage) && !info[PHImageErrorKey];
    }];
    Check(@"thumbnail_delivered", thumbnail);
    [PHImageManager.defaultManager requestImageDataAndOrientationForAsset:asset options:options resultHandler:^(NSData *data, NSString *uti, CGImagePropertyOrientation orientation, NSDictionary *info) {
      (void)uti; (void)orientation;
      CGImageSourceRef source = data ? CGImageSourceCreateWithData((__bridge CFDataRef)data, NULL) : NULL;
      original = source && CGImageSourceGetCount(source) > 0 && !info[PHImageErrorKey];
      if (source) CFRelease(source);
    }];
    Check(@"original_data_delivered", original);
    Finish();
  }}];
  dispatch_main();
}}
