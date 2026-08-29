//
//  UIWindow+TLocationPluginTouch.m
//  TLocationPlugin
//
//  Created by TBD on 2019/9/4.
//  Copyright © 2019 TBD. All rights reserved.
//

#import <AudioToolbox/AudioToolbox.h>
#import "TSelectLocationDataViewController.h"
#import "TLocationNavigationController.h"
#import "UIWindow+TLocationPluginTouch.h"
#import "UIApplication+TLocationPlugin.h"

@implementation UIWindow (TLocationPluginTouch)

static NSInteger _t_windowTouchedTimes = 0;
- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    // 功能入口已改为悬浮窗（TLocationFloatBall），不再使用 5 连击打开界面；
    // 保留事件转发，避免影响宿主 App 的触摸行为。
    [super touchesBegan:touches withEvent:event];
}
@end
