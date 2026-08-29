//
//  TLocationFloatBall.m
//  TLocationPlugin
//

#import "TLocationFloatBall.h"
#import "TSelectLocationDataViewController.h"
#import "TLocationNavigationController.h"
#import "UIApplication+TLocationPlugin.h"
#import "UIImage+TLocationPlugin.h"
#import <objc/runtime.h>

static UIButton *_ballButton;
static NSTimeInterval _lastShakeTime;

static IMP __originalSendEvent;
static void __tlSendEvent(id self, SEL _cmd, UIEvent *event) {
    ((void (*)(id, SEL, UIEvent *))__originalSendEvent)(self, _cmd, event);
    if (event.type == UIEventTypeMotion && event.subtype == UIEventSubtypeMotionShake) {
        // 去抖：1 秒内只响应一次摇一摇，避免一次摇动触发多次 toggle
        NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
        if (now - _lastShakeTime < 1.0) {
            return;
        }
        _lastShakeTime = now;
        dispatch_async(dispatch_get_main_queue(), ^{
            [TLocationFloatBall toggle];
        });
    }
}

@implementation TLocationFloatBall

+ (void)load {
    // 摇一摇隐藏/唤出悬浮球
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        Method m = class_getInstanceMethod([UIApplication class], @selector(sendEvent:));
        if (m) {
            __originalSendEvent = method_getImplementation(m);
            method_setImplementation(m, (IMP)__tlSendEvent);
        }
    });
    // 系统权限弹窗（如本地网络）导致悬浮球消失后，回到前台自动重新出现
    [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidBecomeActiveNotification
                                                      object:nil
                                                       queue:nil
                                                  usingBlock:^(NSNotification *note) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.6 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [TLocationFloatBall show];
        });
    }];
    // 系统窗口（权限弹窗等）切换 key window 后，把悬浮球挂回当前主窗口
    [[NSNotificationCenter defaultCenter] addObserverForName:UIWindowDidBecomeKeyNotification
                                                      object:nil
                                                       queue:nil
                                                  usingBlock:^(NSNotification *note) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [TLocationFloatBall show];
        });
    }];
}

+ (void)show {
    UIWindow *host = [TLocationFloatBall hostWindow];
    if (!host) {
        return;
    }
    if (_ballButton && _ballButton.superview == host) {
        return;
    }
    if (_ballButton && _ballButton.superview) {
        [_ballButton removeFromSuperview];
        _ballButton = nil;
    }
    CGFloat size = 56.0;
    CGFloat margin = 20.0;
    // 首次出现在左上方（避开状态栏）
    CGRect frame = CGRectMake(margin, 120.0, size, size);

    UIButton *ball = [UIButton buttonWithType:UIButtonTypeCustom];
    ball.frame = frame;
    // 高透明度：几乎不挡视野但能看到
    ball.backgroundColor = [UIColor colorWithRed:0.13 green:0.44 blue:0.95 alpha:0.35];
    ball.layer.cornerRadius = size / 2.0;
    ball.clipsToBounds = YES;
    ball.titleLabel.font = [UIFont boldSystemFontOfSize:15];
    UIImage *icon = [UIImage t_imageNamed:@"float_ball"];
    if (!icon) {
        icon = [UIImage t_imageNamed:@"位置"];
    }
    if (icon) {
        [ball setImage:icon forState:UIControlStateNormal];
        [ball setTitle:@"" forState:UIControlStateNormal];
        ball.imageView.contentMode = UIViewContentModeScaleAspectFit;
        ball.imageEdgeInsets = UIEdgeInsetsMake(14, 14, 14, 14);
    } else {
        [ball setTitle:@"定位" forState:UIControlStateNormal];
        [ball setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    }
    [host addSubview:ball];

    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self
                                                                          action:@selector(panBall:)];
    [ball addGestureRecognizer:pan];
    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self
                                                                          action:@selector(tapBall)];
    [ball addGestureRecognizer:tap];

    _ballButton = ball;
}

+ (void)hide {
    [_ballButton removeFromSuperview];
    _ballButton = nil;
}

+ (void)toggle {
    if (_ballButton && _ballButton.superview) {
        [TLocationFloatBall hide];
    } else {
        [TLocationFloatBall show];
    }
}

+ (UIWindow *)hostWindow {
    if (@available(iOS 13.0, *)) {
        for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
            if ([scene isKindOfClass:UIWindowScene.class] &&
                scene.activationState == UISceneActivationStateForegroundActive) {
                UIWindowScene *ws = (UIWindowScene *)scene;
                for (UIWindow *w in ws.windows) {
                    if (w.isKeyWindow) {
                        return w;
                    }
                }
                if (ws.windows.count > 0) {
                    return ws.windows.firstObject;
                }
            }
        }
    }
    return UIApplication.sharedApplication.keyWindow;
}

+ (void)panBall:(UIPanGestureRecognizer *)pan {
    UIView *ball = pan.view;
    UIView *superview = ball.superview;
    if (!superview) {
        return;
    }
    if (pan.state == UIGestureRecognizerStateChanged) {
        CGPoint translation = [pan translationInView:superview];
        CGPoint center = ball.center;
        center.x += translation.x;
        center.y += translation.y;
        CGFloat half = ball.bounds.size.width / 2.0;
        center.x = MAX(half, MIN(superview.bounds.size.width - half, center.x));
        center.y = MAX(half, MIN(superview.bounds.size.height - half, center.y));
        ball.center = center;
        [pan setTranslation:CGPointZero inView:superview];
    } else if (pan.state == UIGestureRecognizerStateEnded) {
        CGFloat half = ball.bounds.size.width / 2.0;
        CGFloat targetX = ball.center.x < superview.bounds.size.width / 2.0 ? half + 6 : superview.bounds.size.width - half - 6;
        [UIView animateWithDuration:0.2 animations:^{
            CGPoint center = ball.center;
            center.x = targetX;
            ball.center = center;
        }];
    }
}

+ (void)tapBall {
    if (TLocationNavigationController.isShowing) {
        return;
    }
    UIViewController *rootVC = [UIApplication sharedApplication].t_topViewController;
    if (!rootVC) {
        return;
    }
    TSelectLocationDataViewController *vc = [[TSelectLocationDataViewController alloc] init];
    TLocationNavigationController *nav = [[TLocationNavigationController alloc] initWithRootViewController:vc];
    [rootVC presentViewController:nav animated:YES completion:nil];
}

@end
