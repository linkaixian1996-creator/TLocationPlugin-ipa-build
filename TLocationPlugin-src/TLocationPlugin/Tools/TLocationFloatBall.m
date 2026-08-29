//
//  TLocationFloatBall.m
//  TLocationPlugin
//

#import "TLocationFloatBall.h"
#import "TSelectLocationDataViewController.h"
#import "TLocationNavigationController.h"
#import "UIApplication+TLocationPlugin.h"
#import "UIImage+TLocationPlugin.h"

static UIWindow *_floatWindow;

@implementation TLocationFloatBall

+ (void)show {
    if (_floatWindow) {
        return;
    }
    CGFloat size = 56.0;
    CGFloat margin = 20.0;
    CGSize screen = [UIScreen mainScreen].bounds.size;
    CGRect frame = CGRectMake(screen.width - size - margin,
                              screen.height * 0.55,
                              size, size);

    UIWindow *window = nil;
    if (@available(iOS 13.0, *)) {
        window = [[UIWindow alloc] initWithWindowScene:[TLocationFloatBall activeScene]];
    } else {
        window = [[UIWindow alloc] initWithFrame:frame];
    }
    window.frame = frame;
    window.windowLevel = UIWindowLevelStatusBar + 100;
    window.backgroundColor = [UIColor clearColor];
    window.rootViewController = [UIViewController new];
    window.userInteractionEnabled = YES;

    UIButton *ball = [UIButton buttonWithType:UIButtonTypeCustom];
    ball.frame = window.bounds;
    ball.backgroundColor = [UIColor colorWithRed:0.13 green:0.44 blue:0.95 alpha:0.95];
    ball.layer.cornerRadius = size / 2.0;
    ball.clipsToBounds = YES;
    ball.titleLabel.font = [UIFont boldSystemFontOfSize:15];
    UIImage *icon = [UIImage t_imageNamed:@"位置"];
    if (icon) {
        [ball setImage:icon forState:UIControlStateNormal];
        [ball setTitle:@"" forState:UIControlStateNormal];
        ball.imageView.contentMode = UIViewContentModeScaleAspectFit;
        ball.imageEdgeInsets = UIEdgeInsetsMake(14, 14, 14, 14);
    } else {
        [ball setTitle:@"定位" forState:UIControlStateNormal];
        [ball setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    }
    [window.rootViewController.view addSubview:ball];

    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self
                                                                          action:@selector(panBall:)];
    [ball addGestureRecognizer:pan];
    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self
                                                                          action:@selector(tapBall)];
    [ball addGestureRecognizer:tap];

    _floatWindow = window;
    window.hidden = NO;
}

+ (void)hide {
    _floatWindow.hidden = YES;
    _floatWindow = nil;
}

+ (UIWindowScene *)activeScene {
    if (@available(iOS 13.0, *)) {
        for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
            if ([scene isKindOfClass:UIWindowScene.class] &&
                scene.activationState == UISceneActivationStateForegroundActive) {
                return (UIWindowScene *)scene;
            }
        }
        for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
            if ([scene isKindOfClass:UIWindowScene.class]) {
                return (UIWindowScene *)scene;
            }
        }
    }
    return nil;
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
