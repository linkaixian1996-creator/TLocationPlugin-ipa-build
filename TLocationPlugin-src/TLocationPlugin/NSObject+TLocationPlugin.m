//
//  NSObject+TLocationPlugin.m
//  TLocationPlugin
//
//  Created by TBD on 2019/9/4.
//  Copyright © 2019 TBD. All rights reserved.
//

#import <CoreLocation/CoreLocation.h>
#import "NSObject+TLocationPlugin.h"
#import "TSafeRuntimeCFunc.h"
#import "TLocationManager.h"
#import "UIWindow+TLocationPluginToast.h"
#import "LicenseManager.h"
#import <objc/runtime.h>
#import <dlfcn.h>

@implementation NSObject (TLocationPlugin)

+ (void)load {
    // 启动后检查授权：未激活则弹卡密输入框（与原版激活体验一致）
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [NSObject promptLicenseIfNeededWithRetry:3];
    });

    // Selector Name
    const char *old_location_sel_name = sel_getName(@selector(locationManager:didUpdateToLocation:fromLocation:));
    const char *new_location_sel_name = sel_getName(@selector(locationManager:didUpdateLocations:));
    
    /// 替换所有方法
    int all_classes_count;
    Class *all_classes = NULL;
    all_classes_count = objc_getClassList(NULL, 0);
    if (all_classes_count > 0 ) {
        all_classes = (__unsafe_unretained Class *)malloc(sizeof(Class) * all_classes_count);
        objc_getClassList(all_classes, all_classes_count);
        for (int i = 0; i < all_classes_count; i++) {
            Class cls = all_classes[i];
            unsigned int methods_count;
            Method *methods = class_copyMethodList(cls, &methods_count);
            for (int i = 0; i < methods_count; i++) {
                const char *selName = sel_getName(method_getName(methods[i]));
                // 是定位函数
                if (strcmp(selName, old_location_sel_name) == 0 ||
                    strcmp(selName, new_location_sel_name) == 0) {
                    [self replaceCLLocationsFunctionToClass:cls];
                    break;
                }
            }
            free(methods);
        }
        free(all_classes);
    }
}

#pragma mark - 启动激活（强制验证，与原版一致）

+ (void)promptLicenseIfNeededWithRetry:(NSInteger)retry {
    if ([LicenseManager isActivated]) {
        return; // 已激活，正常进入
    }
    UIViewController *top = [NSObject topViewController];
    if (!top) {
        if (retry > 0) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                [NSObject promptLicenseIfNeededWithRetry:retry - 1];
            });
        }
        return;
    }
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"某手控制台 · 激活"
                                                                  message:@"请输入卡密激活后使用虚拟定位"
                                                           preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *tf) {
        tf.placeholder = @"卡密";
        tf.keyboardType = UIKeyboardTypeASCIICapable;
        tf.autocapitalizationType = UITextAutocapitalizationTypeNone;
        tf.clearButtonMode = UITextFieldViewModeWhileEditing;
    }];
    [alert addAction:[UIAlertAction actionWithTitle:@"激活"
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction *action) {
        NSString *card = alert.textFields.firstObject.text;
        [LicenseManager activateWithCard:card completion:^(BOOL ok, NSString *message) {
            if (ok) {
                // 激活成功：强制退出，重启后生效（与原版一致）
                exit(0);
            } else {
                [NSObject promptLicenseIfNeededWithRetry:2];
            }
        }];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"退出"
                                              style:UIAlertActionStyleDestructive
                                            handler:^(UIAlertAction *action) {
        exit(0);
    }]];
    [top presentViewController:alert animated:YES completion:nil];
}

+ (UIViewController *)topViewController {
    UIWindow *window = [NSObject mainWindow];
    UIViewController *top = window.rootViewController;
    while (top.presentedViewController) {
        top = top.presentedViewController;
    }
    return top;
}

+ (UIWindow *)mainWindow {
    if (@available(iOS 13.0, *)) {
        for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
            if ([scene isKindOfClass:UIWindowScene.class] &&
                scene.activationState == UISceneActivationStateForegroundActive) {
                for (UIWindow *w in ((UIWindowScene *)scene).windows) {
                    if (w.isKeyWindow) {
                        return w;
                    }
                }
            }
        }
    }
    return UIApplication.sharedApplication.keyWindow;
}

+ (void)replaceCLLocationsFunctionToClass:(Class)cls {
    if ([cls instancesRespondToSelector:@selector(locationManager:didUpdateToLocation:fromLocation:)]) {
        t_exchange_instance_method(cls,
                                   @selector(locationManager:didUpdateToLocation:fromLocation:),
                                   @selector(__t_locationManager:didUpdateToLocation:fromLocation:));
    }
    
    if ([cls instancesRespondToSelector:@selector(locationManager:didUpdateLocations:)]) {
        t_exchange_instance_method(cls,
                                   @selector(locationManager:didUpdateLocations:),
                                   @selector(__t_locationManager:didUpdateLocations:));
    }
}

- (void)__t_locationManager:(CLLocationManager *)manager
        didUpdateToLocation:(CLLocation *)newLocation
               fromLocation:(CLLocation *)oldLocation API_AVAILABLE(macos(10.6)) {
    // 授权门控：未激活/已过期时不替换宿主定位数据，只走原始回调。
    BOOL licensed = [LicenseManager isActivated];
    BOOL useHook = licensed && TLocationManager.shared.usingHookLocation && TLocationManager.shared.hasCachedLocation;
    // 不使用或者暂时暂停使用，调用原方法
    if (!useHook || TLocationManager.shared.isSuspend) {
        [self t_showTostForCLLocation:newLocation];
        [self __t_locationManager:manager didUpdateToLocation:newLocation fromLocation:oldLocation];
        return;
    }
    
    /// CLLocation 使用WGS84坐标
    CLLocation *t_newLocation = [[CLLocation alloc] initWithCoordinate:TLocationManager.shared.randomWGS84Coordinate
                                                              altitude:newLocation.altitude
                                                    horizontalAccuracy:newLocation.horizontalAccuracy
                                                      verticalAccuracy:newLocation.verticalAccuracy
                                                                course:newLocation.course
                                                                 speed:newLocation.speed
                                                             timestamp:newLocation.timestamp];
    
    [self t_showTostForCLLocation:t_newLocation];
    [self __t_locationManager:manager didUpdateToLocation:t_newLocation fromLocation:oldLocation];
}

- (void)__t_locationManager:(CLLocationManager *)manager
         didUpdateLocations:(NSArray<CLLocation *> *)locations {
    // 授权门控：未激活/已过期时不替换宿主定位数据，只走原始回调。
    BOOL licensed = [LicenseManager isActivated];
    BOOL useHook = licensed && TLocationManager.shared.usingHookLocation && TLocationManager.shared.hasCachedLocation;
    // 不使用或者暂时暂停使用，调用原方法
    if (!useHook || TLocationManager.shared.isSuspend) {
        [self t_showTostForCLLocations:locations];
        [self __t_locationManager:manager didUpdateLocations:locations];
        return;
    }
    
    NSMutableArray<CLLocation *> *t_locations = [NSMutableArray<CLLocation *> array];
    for (CLLocation *location in locations) {
        /// CLLocation 使用WGS84坐标
        CLLocation *t_location = [[CLLocation alloc] initWithCoordinate:TLocationManager.shared.randomWGS84Coordinate
                                                               altitude:location.altitude
                                                     horizontalAccuracy:location.horizontalAccuracy
                                                       verticalAccuracy:location.verticalAccuracy
                                                                 course:location.course
                                                                  speed:location.speed
                                                              timestamp:location.timestamp];
        [t_locations addObject:t_location];
    }
    
    [self t_showTostForCLLocations:t_locations];
    [self __t_locationManager:manager didUpdateLocations:t_locations];
}

- (void)t_showTostForCLLocations:(NSArray<CLLocation *> *)locations {
    if (TLocationManager.shared.usingToast) {
        [UIWindow t_showTostForCLLocations:locations];
    }
}

- (void)t_showTostForCLLocation:(CLLocation *)location {
    if (TLocationManager.shared.usingToast) {
        [UIWindow t_showTostForCLLocation:location];
    }
}

@end

