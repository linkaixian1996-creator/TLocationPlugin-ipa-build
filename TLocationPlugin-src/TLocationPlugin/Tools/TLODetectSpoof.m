//
//  TLODetectSpoof.m
//  安装方式伪装：让抖音读到「App Store 官方描述文件」而不是重签证书的描述文件
//
//  依据（对 AwemeCore 全量检索）：
//    - 字符串 "SignInfo" 的取值只有 "AppStore" / "SelfSign"
//    - 两条正则：
//        <key>TeamIdentifier</key>\s*<array>\s*<string>(\w+)</string>\s*</array>
//        <key>TeamName</key>\s*<string>([^<]*)</string>
//      → 说明它是把 embedded.mobileprovision 当**文本**正则抠字段，不做 CMS 验签
//    - 全包无 SecStaticCodeCheckValidity / SecCodeCopySigningInformation 调用
//
//  做法：全局拦截「读 embedded.mobileprovision」的几条常见路径，返回伪造内容
//  （TeamIdentifier = 官方 3JTPEA4UU7），其余调用一律原样透传。
//

#import <Foundation/Foundation.h>
#import <objc/runtime.h>

static NSString *const kTLOProfileFileName = @"embedded.mobileprovision";

static NSData   *gTLOFakeProfile     = nil;
static NSString *gTLOFakeProfilePath = nil;

static NSString *const kTLOFakeProfileXML =
    @"<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
    "<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">\n"
    "<plist version=\"1.0\">\n"
    "<dict>\n"
    "\t<key>AppIDName</key>\n"
    "\t<string>Aweme</string>\n"
    "\t<key>ApplicationIdentifierPrefix</key>\n"
    "\t<array>\n"
    "\t\t<string>3JTPEA4UU7</string>\n"
    "\t</array>\n"
    "\t<key>CreationDate</key>\n"
    "\t<date>2024-01-01T00:00:00Z</date>\n"
    "\t<key>ExpirationDate</key>\n"
    "\t<date>2099-12-31T00:00:00Z</date>\n"
    "\t<key>Platform</key>\n"
    "\t<array>\n"
    "\t\t<string>iOS</string>\n"
    "\t</array>\n"
    "\t<key>TeamIdentifier</key>\n"
    "\t<array>\n"
    "\t\t<string>3JTPEA4UU7</string>\n"
    "\t</array>\n"
    "\t<key>TeamName</key>\n"
    "\t<string>Beijing ByteDance Technology Co., Ltd.</string>\n"
    "\t<key>UUID</key>\n"
    "\t<string>11111111-2222-3333-4444-555555555555</string>\n"
    "</dict>\n"
    "</plist>\n";

#pragma mark - helpers

static BOOL TLOIsProfilePath(id path) {
    if (![path isKindOfClass:[NSString class]]) {
        return NO;
    }
    return [(NSString *)path hasSuffix:kTLOProfileFileName];
}

static void TLOPrepareFakeProfile(void) {
    if (gTLOFakeProfile) {
        return;
    }
    gTLOFakeProfile = [kTLOFakeProfileXML dataUsingEncoding:NSUTF8StringEncoding];
    // 同时落一份到 tmp，供走 fopen/open 路径的读取命中
    NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:kTLOProfileFileName];
    [gTLOFakeProfile writeToFile:path atomically:YES];
    gTLOFakeProfilePath = [path copy];
    NSLog(@"[TLO] fake provisioning profile ready: %@", path);
}

#pragma mark - NSData

static NSData *(*tlo_orig_data_file)(id, SEL, NSString *);
static NSData *tlo_data_file(id self, SEL _cmd, NSString *path) {
    if (TLOIsProfilePath(path)) {
        TLOPrepareFakeProfile();
        NSLog(@"[TLO] spoofed profile read (dataWithContentsOfFile): %@", path);
        return gTLOFakeProfile;
    }
    return tlo_orig_data_file(self, _cmd, path);
}

static NSData *(*tlo_orig_data_file_opts)(id, SEL, NSString *, NSDataReadingOptions, NSError **);
static NSData *tlo_data_file_opts(id self, SEL _cmd, NSString *path, NSDataReadingOptions opts, NSError **err) {
    if (TLOIsProfilePath(path)) {
        TLOPrepareFakeProfile();
        NSLog(@"[TLO] spoofed profile read (dataWithContentsOfFile:options:)");
        return gTLOFakeProfile;
    }
    return tlo_orig_data_file_opts(self, _cmd, path, opts, err);
}

static NSData *(*tlo_orig_data_url)(id, SEL, NSURL *);
static NSData *tlo_data_url(id self, SEL _cmd, NSURL *url) {
    if (TLOIsProfilePath(url.path)) {
        TLOPrepareFakeProfile();
        NSLog(@"[TLO] spoofed profile read (dataWithContentsOfURL)");
        return gTLOFakeProfile;
    }
    return tlo_orig_data_url(self, _cmd, url);
}

#pragma mark - NSFileManager

static NSData *(*tlo_orig_contents_at_path)(id, SEL, NSString *);
static NSData *tlo_contents_at_path(id self, SEL _cmd, NSString *path) {
    if (TLOIsProfilePath(path)) {
        TLOPrepareFakeProfile();
        NSLog(@"[TLO] spoofed profile read (contentsAtPath)");
        return gTLOFakeProfile;
    }
    return tlo_orig_contents_at_path(self, _cmd, path);
}

#pragma mark - NSBundle

static NSString *(*tlo_orig_path_for_resource)(id, SEL, NSString *, NSString *);
static NSString *tlo_path_for_resource(id self, SEL _cmd, NSString *name, NSString *ext) {
    if ([name isEqualToString:@"embedded"] && [ext isEqualToString:@"mobileprovision"]) {
        TLOPrepareFakeProfile();
        NSLog(@"[TLO] spoofed pathForResource:embedded.mobileprovision");
        return gTLOFakeProfilePath;
    }
    return tlo_orig_path_for_resource(self, _cmd, name, ext);
}

static NSURL *(*tlo_orig_url_for_resource)(id, SEL, NSString *, NSString *);
static NSURL *tlo_url_for_resource(id self, SEL _cmd, NSString *name, NSString *ext) {
    if ([name isEqualToString:@"embedded"] && [ext isEqualToString:@"mobileprovision"]) {
        TLOPrepareFakeProfile();
        NSLog(@"[TLO] spoofed URLForResource:embedded.mobileprovision");
        return [NSURL fileURLWithPath:gTLOFakeProfilePath];
    }
    return tlo_orig_url_for_resource(self, _cmd, name, ext);
}

#pragma mark - install

static void TLOSwizzleClassMethod(Class cls, SEL sel, IMP *orig, IMP replacement) {
    Method m = class_getClassMethod(cls, sel);
    if (!m) {
        NSLog(@"[TLO] class method not found: %@ %@", cls, NSStringFromSelector(sel));
        return;
    }
    *orig = method_setImplementation(m, replacement);
}

static void TLOSwizzleInstanceMethod(Class cls, SEL sel, IMP *orig, IMP replacement) {
    Method m = class_getInstanceMethod(cls, sel);
    if (!m) {
        NSLog(@"[TLO] instance method not found: %@ %@", cls, NSStringFromSelector(sel));
        return;
    }
    *orig = method_setImplementation(m, replacement);
}

__attribute__((constructor))
static void TLODetectSpoofInstall(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        TLOPrepareFakeProfile();

        TLOSwizzleClassMethod([NSData class], @selector(dataWithContentsOfFile:),
                              (IMP *)&tlo_orig_data_file, (IMP)tlo_data_file);
        TLOSwizzleClassMethod([NSData class], @selector(dataWithContentsOfFile:options:error:),
                              (IMP *)&tlo_orig_data_file_opts, (IMP)tlo_data_file_opts);
        TLOSwizzleClassMethod([NSData class], @selector(dataWithContentsOfURL:),
                              (IMP *)&tlo_orig_data_url, (IMP)tlo_data_url);
        TLOSwizzleInstanceMethod([NSFileManager class], @selector(contentsAtPath:),
                                 (IMP *)&tlo_orig_contents_at_path, (IMP)tlo_contents_at_path);
        TLOSwizzleInstanceMethod([NSBundle class], @selector(pathForResource:ofType:),
                                 (IMP *)&tlo_orig_path_for_resource, (IMP)tlo_path_for_resource);
        TLOSwizzleInstanceMethod([NSBundle class], @selector(URLForResource:withExtension:),
                                 (IMP *)&tlo_orig_url_for_resource, (IMP)tlo_url_for_resource);

        NSLog(@"[TLO] detection spoof installed");
    });
}
