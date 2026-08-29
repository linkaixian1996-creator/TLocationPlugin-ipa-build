//
//  TLocationSettingViewController.m
//  TLocationPlugin
//
//  Created by TBD on 2019/9/4.
//  Copyright © 2019 TBD. All rights reserved.
//

#import "TLocationSettingViewController.h"
#import "TSelectLocationDataViewController.h"
#import "TLocationManager.h"
#import "UIImage+TLocationPlugin.h"
#import "TAlertController.h"
#import "UIWindow+TLocationPluginToast.h"
#import "TLocationChangeAppICONViewController.h"
#import "LicenseManager.h"

@interface TLocationSettingViewController () <UITextFieldDelegate>

@property (nonatomic, strong) IBOutlet UIScrollView *contentScrollView;
@property (nonatomic, strong) IBOutlet UILabel *locationNameLabel;
@property (nonatomic, strong) IBOutlet UITextField *latitudeTextField;
@property (nonatomic, strong) IBOutlet UITextField *longitudeTextField;
@property (nonatomic, strong) IBOutlet UITextField *rangeTextField;
@property (nonatomic, strong) IBOutlet UISwitch *usingHookSwitch;
@property (strong, nonatomic) IBOutlet UISwitch *usingToastSwitch;

@end

@implementation TLocationSettingViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"设置";
    UITapGestureRecognizer *sigleTap = [[UITapGestureRecognizer alloc] initWithTarget:self
                                                                               action:@selector(tapScrollView)];
    [self.contentScrollView addGestureRecognizer:sigleTap];
    NSString *locationName = TLocationManager.shared.locationName;
    CLLocationDegrees latitude = TLocationManager.shared.latitude;
    CLLocationDegrees longitude = TLocationManager.shared.longitude;
    NSInteger range = TLocationManager.shared.range;
    BOOL isUsingHook = TLocationManager.shared.usingHookLocation;
    BOOL isUsingToast = TLocationManager.shared.usingToast;
    self.locationNameLabel.text = locationName;
    self.latitudeTextField.text = @(latitude).stringValue;
    self.longitudeTextField.text = @(longitude).stringValue;
    self.rangeTextField.text = @(range).stringValue;
    self.usingHookSwitch.on = isUsingHook;
    self.usingToastSwitch.on = isUsingToast;
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    if ([LicenseManager isActivated]) {
        NSDate *exp = [LicenseManager expiryDate];
        NSString *expStr = @"";
        if (exp) {
            NSDateFormatter *fmt = [[NSDateFormatter alloc] init];
            fmt.dateFormat = @"yyyy-MM-dd HH:mm:ss";
            expStr = [fmt stringFromDate:exp];
        }
        [UIWindow t_showTostForMessage:[NSString stringWithFormat:@"已激活，到期 %@", expStr]];
        return;
    }
    [self promptActivate];
}

- (void)promptActivate {
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
            [UIWindow t_showTostForMessage:(message.length ? message : (ok ? @"激活成功" : @"激活失败"))];
        }];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)tapScrollView {
    [self.view endEditing:YES];
}

/// 开关
- (IBAction)usingHookLocationValueChanged:(UISwitch *)sender {
    [self.view endEditing:YES];
    TLocationManager.shared.usingHookLocation = sender.isOn;
    [UIWindow t_showTostForMessage:sender.isOn ? @"已开启位置拦截" : @"已关闭位置拦截"];
}

- (IBAction)usingToastValueChanged:(UISwitch *)sender {
    [self.view endEditing:YES];
    TLocationManager.shared.usingToast = sender.isOn;
    [UIWindow t_showTostForMessage:sender.isOn ? @"已开启定位提示" : @"已关闭定位提示"];
}

- (IBAction)changeAppICON:(UIButton *)sender {
    TLocationChangeAppICONViewController *vc = [[TLocationChangeAppICONViewController alloc] init];
    [self.navigationController pushViewController:vc animated:YES];
}

- (IBAction)cleanCacheData:(UIButton *)sender {
    TAlertController *alert = [TAlertController destructiveAlertWithTitle:@"确定清空保存的位置列表数据?"
                                                                  message:nil
                                                              cancelTitle:@"取消"
                                                              cancelBlock:nil
                                                         destructiveTitle:@"确定"
                                                         destructiveBlock:^(TAlertController * _Nonnull alert, UIAlertAction * _Nonnull action) {
        TLocationManager.shared.cacheDataArray = nil;
        [TLocationManager.shared saveCacheDataArray];
        [UIWindow t_showTostForMessage:@"已清空保存的位置列表数据"];
    }];
    [self presentViewController:alert animated:YES completion:nil];
}

#pragma mark - UITextFieldDelegate
- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    [self.view endEditing:YES];
    return YES;
}

- (BOOL)textFieldShouldEndEditing:(UITextField *)textField {
    if (textField == self.rangeTextField) {
        NSInteger range = [self.rangeTextField.text integerValue];
        if (TLocationManager.shared.range != range) {
            TLocationManager.shared.range = range;
            NSString *tostText = [NSString stringWithFormat:@"已保存范围: %ld", (long)TLocationManager.shared.range];
            // 重设值, TLocationManager.shared.range 赋值包含判断
            textField.text = @(TLocationManager.shared.range).stringValue;
            [UIWindow t_showTostForMessage:tostText];
        }
    }
    return YES;
}

- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    [self.view endEditing:YES];
}

@end
