//
//  TLocationFloatBall.h
//  TLocationPlugin
//
//  激活后显示的悬浮球：点击打开功能界面（替代 5 连击入口）
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface TLocationFloatBall : NSObject

+ (void)show;
+ (void)hide;
+ (void)toggle;

@end

NS_ASSUME_NONNULL_END
