#import "LicenseManager.h"
#import <UIKit/UIKit.h>
#import <CommonCrypto/CommonHMAC.h>
#import <Security/Security.h>
#import <sys/utsname.h>

// ================= 服务器配置（部署时修改） =================
// 默认服务器地址。部署后改成你的 HTTPS 地址，例如 https://vca.example.com（不带末尾斜杠）。
// 生产环境走 Nginx/Caddy 反代，不要直连 127.0.0.1:5675。
static NSString *const kDefaultServerBaseURL = @"https://ks.etgstudio.live";
// 与服务端 VCA_KEY 必须一致。仓库公开，真实密钥不写死：CI 构建时用 GitHub Secrets 的 VCA_KEY 替换。
static NSString *const kSignKeyHex = @"CHANGE_ME"; // 构建时被 secrets.VCA_KEY 替换
static NSString *const kActivatePath = @"/vca//activate.php";
static NSString *const kVerifyPath = @"/vca//verify.php";

// 本地持久化 key
static NSString *const kUDToken = @"vca_token";
static NSString *const kUDExpireAt = @"vca_expire_at";
static NSString *const kUDActivatedAt = @"vca_activated_at";
static NSString *const kUDCardKey = @"vca_card_key";
static NSString *const kUDModel = @"vca_model";

@implementation LicenseManager

#pragma mark - 服务器配置

+ (NSString *)serverBaseURL {
    NSString *saved = [[NSUserDefaults standardUserDefaults] stringForKey:@"vca_server_base"];
    return saved.length ? saved : kDefaultServerBaseURL;
}

+ (void)setServerBaseURL:(NSString *)url {
    [[NSUserDefaults standardUserDefaults] setObject:url forKey:@"vca_server_base"];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

+ (NSData *)signKey {
    static NSData *key;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        // 服务器 KEY = 密钥字符串的 UTF-8 字节（不是 hex 解码！）
        // 例如 "6b31..." 直接取 ASCII 字节，与服务端 .encode("utf-8") 一致
        key = [kSignKeyHex dataUsingEncoding:NSUTF8StringEncoding];
    });
    return key;
}

#pragma mark - 工具

+ (NSData *)dataFromHex:(NSString *)hex {
    if (hex.length == 0 || hex.length % 2) return nil;
    NSMutableData *data = [NSMutableData data];
    for (NSUInteger i = 0; i + 1 < hex.length; i += 2) {
        unsigned int byte;
        [[NSScanner scannerWithString:[hex substringWithRange:NSMakeRange(i, 2)]] scanHexInt:&byte];
        uint8_t b = (uint8_t)byte;
        [data appendBytes:&b length:1];
    }
    return data;
}

+ (NSString *)urlEncode:(NSString *)s {
    // 与 Python urllib.parse.quote 默认行为一致：安全字符 = 字母数字 + _ . - ~ /
    static NSCharacterSet *allowed;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        allowed = [NSCharacterSet characterSetWithCharactersInString:
                   @"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_.-~/"];
    });
    return [s stringByAddingPercentEncodingWithAllowedCharacters:allowed];
}

+ (NSString *)hmacSHA256Hex:(NSString *)data {
    NSData *key = [self signKey];
    const char *cKey = key.bytes;
    const char *cData = data.UTF8String;
    unsigned char hmac[CC_SHA256_DIGEST_LENGTH];
    CCHmac(kCCHmacAlgSHA256, cKey, key.length, cData, strlen(cData), hmac);
    NSMutableString *hex = [NSMutableString string];
    for (int i = 0; i < CC_SHA256_DIGEST_LENGTH; i++) {
        [hex appendFormat:@"%02x", hmac[i]];
    }
    return hex;
}

+ (NSString *)hmacSignForParams:(NSDictionary *)params {
    NSArray *keys = [params.allKeys sortedArrayUsingSelector:@selector(compare:)];
    NSMutableString *data = [NSMutableString string];
    for (NSString *k in keys) {
        NSString *v = [params[k] description];
        if (data.length > 0) [data appendString:@"&"];
        [data appendFormat:@"%@=%@", k, [self urlEncode:v]];
    }
    return [self hmacSHA256Hex:data];
}

+ (NSString *)nonce {
    uint8_t bytes[16];
    arc4random_buf(bytes, 16);
    NSMutableString *hex = [NSMutableString string];
    for (int i = 0; i < 16; i++) [hex appendFormat:@"%02x", bytes[i]];
    return hex;
}

+ (NSString *)timestamp {
    return [NSString stringWithFormat:@"%.0f", [NSDate date].timeIntervalSince1970];
}

+ (NSString *)deviceModel {
    struct utsname info;
    uname(&info);
    return [NSString stringWithCString:info.machine encoding:NSUTF8StringEncoding];
}

#pragma mark - 响应验签

+ (BOOL)verifyResponseSign:(NSString *)bodyHex sign:(NSString *)signHex {
    // 服务器 response_sign = HMAC(KEY, JSON原文)，原文 = 最终 JSON 去掉末尾的 ,"response_sign":"..."}
    if (!bodyHex.length || !signHex.length) return NO;
    NSRange range = [bodyHex rangeOfString:@",\"response_sign\":\""];
    if (range.location == NSNotFound) return NO;
    // bodyHex 形如 {...,"token":"x"},"response_sign":"hex"}
    // 截到逗号前是 {...} 去掉最后的 }，需补回 } 得到服务器签名的原始 JSON 对象
    NSString *originalBody = [bodyHex substringToIndex:range.location];
    originalBody = [originalBody stringByAppendingString:@"}"];
    return [[self hmacSHA256Hex:originalBody] isEqualToString:signHex.lowercaseString];
}

+ (NSDictionary *)parseResponseBody:(NSData *)bodyData signOut:(NSString **)signOut {
    NSString *body = [[NSString alloc] initWithData:bodyData encoding:NSUTF8StringEncoding];
    if (!body.length) return nil;
    NSRange r = [body rangeOfString:@",\"response_sign\":\""];
    if (r.location != NSNotFound) {
        NSString *tail = [body substringFromIndex:r.location + r.length];
        // tail 形如 "<hex>"}
        tail = [tail stringByReplacingOccurrencesOfString:@"\"}" withString:@""];
        if (signOut) *signOut = tail;
    }
    NSData *jsonData = [body dataUsingEncoding:NSUTF8StringEncoding];
    return [NSJSONSerialization JSONObjectWithData:jsonData options:0 error:nil];
}

#pragma mark - 网络

+ (void)postToPath:(NSString *)path
            params:(NSDictionary *)params
        completion:(void (^)(NSDictionary *json, NSString *rawBody, NSString *sign, NSError *error))completion {
    NSString *url = [[self serverBaseURL] stringByAppendingString:path];
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:url]];
    req.HTTPMethod = @"POST";
    [req setValue:@"application/x-www-form-urlencoded" forHTTPHeaderField:@"Content-Type"];

    NSMutableDictionary *all = [params mutableCopy];
    all[@"nonce"] = [self nonce];
    all[@"timestamp"] = [self timestamp];
    all[@"sign"] = [self hmacSignForParams:all];

    NSMutableString *bodyStr = [NSMutableString string];
    for (NSString *k in [all.allKeys sortedArrayUsingSelector:@selector(compare:)]) {
        if (bodyStr.length) [bodyStr appendString:@"&"];
        [bodyStr appendFormat:@"%@=%@", k, [self urlEncode:all[k]]];
    }
    req.HTTPBody = [bodyStr dataUsingEncoding:NSUTF8StringEncoding];
    req.timeoutInterval = 15;

    [[[NSURLSession sharedSession] dataTaskWithRequest:req
                                     completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (error) {
                completion(nil, nil, nil, error);
                return;
            }
            NSString *sign = nil;
            NSDictionary *json = [self parseResponseBody:data signOut:&sign];
            NSString *raw = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
            completion(json, raw, sign, nil);
        });
    }] resume];
}

#pragma mark - 设备标识

+ (NSString *)udid {
    NSData *stored = [self keychainDataForAccount:@"device-udid"];
    if (stored) {
        return [[NSString alloc] initWithData:stored encoding:NSUTF8StringEncoding];
    }
    NSString *uuid = [[NSUUID UUID] UUIDString].uppercaseString;
    [self saveKeychainData:[uuid dataUsingEncoding:NSUTF8StringEncoding] forAccount:@"device-udid"];
    return uuid;
}

#pragma mark - 激活（服务器）

+ (void)activateWithCard:(NSString *)card
              completion:(void (^)(BOOL ok, NSString *message))completion {
    NSString *cleanCard = [card stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (!cleanCard.length) {
        if (completion) completion(NO, @"请输入卡密");
        return;
    }
    NSDictionary *params = @{
        @"action": @"activate",
        @"app_bundle": @"com_kwai_gif", // 改成目标 App 的 bundle id
        @"card_key": cleanCard,
        @"ios_version": [[UIDevice currentDevice] systemVersion],
        @"model": [self deviceModel],
        @"udid": [self udid],
    };
    [self postToPath:kActivatePath params:params completion:^(NSDictionary *json, NSString *rawBody, NSString *sign, NSError *error) {
        if (error) {
            if (completion) completion(NO, [NSString stringWithFormat:@"网络错误：%@", error.localizedDescription]);
            return;
        }
        if (!json) {
            if (completion) completion(NO, @"服务器响应异常");
            return;
        }
        // 验签
        if (![self verifyResponseSign:rawBody sign:sign]) {
            if (completion) completion(NO, @"响应验签失败");
            return;
        }
        NSNumber *code = json[@"code"];
        if (code.integerValue != 0) {
            if (completion) completion(NO, json[@"message"] ?: @"激活失败");
            return;
        }
        NSString *token = json[@"token"];
        NSString *expireAt = json[@"expire_at"];
        if (!token.length) {
            if (completion) completion(NO, @"服务器未返回 token");
            return;
        }
        NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
        [ud setObject:token forKey:kUDToken];
        [ud setObject:expireAt ?: @"" forKey:kUDExpireAt];
        [ud setObject:[self timestamp] forKey:kUDActivatedAt];
        [ud setObject:cleanCard forKey:kUDCardKey];
        [ud setObject:[self deviceModel] forKey:kUDModel];
        [ud synchronize];
        if (completion) completion(YES, @"激活成功");
    }];
}

#pragma mark - 本地状态

+ (NSDate *)parseServerDate:(NSString *)s {
    if (!s.length) return nil;
    NSDateFormatter *fmt = [[NSDateFormatter alloc] init];
    fmt.dateFormat = @"yyyy-MM-dd HH:mm:ss";
    fmt.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
    // 服务端统一返回 UTC 时间，这里必须按 UTC 解析，避免 VPS/手机时区差导致提前到期
    fmt.timeZone = [NSTimeZone timeZoneForSecondsFromGMT:0];
    return [fmt dateFromString:s];
}

+ (NSString *)token {
    return [[NSUserDefaults standardUserDefaults] stringForKey:kUDToken];
}

+ (NSString *)storedCardKey {
    return [[NSUserDefaults standardUserDefaults] stringForKey:kUDCardKey];
}

+ (NSString *)activatedModel {
    return [[NSUserDefaults standardUserDefaults] stringForKey:kUDModel];
}

+ (NSDate *)expiryDate {
    return [self parseServerDate:[[NSUserDefaults standardUserDefaults] stringForKey:kUDExpireAt]];
}

+ (BOOL)isExpired {
    NSDate *expiry = [self expiryDate];
    if (!expiry) return NO;
    return [expiry timeIntervalSinceNow] < 0;
}

+ (BOOL)isActivated {
    NSString *token = [self token];
    if (!token.length) return NO;
    return ![self isExpired];
}

+ (void)clearActivation {
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    [ud removeObjectForKey:kUDToken];
    [ud removeObjectForKey:kUDExpireAt];
    [ud removeObjectForKey:kUDActivatedAt];
    [ud removeObjectForKey:kUDCardKey];
    [ud removeObjectForKey:kUDModel];
    [ud synchronize];
}

#pragma mark - 心跳（服务器）

+ (void)heartbeatWithCompletion:(void (^)(BOOL valid, NSString *message))completion {
    NSString *token = [self token];
    if (!token.length) {
        if (completion) completion(NO, @"未激活");
        return;
    }
    NSDictionary *params = @{
        @"action": @"heartbeat",
        @"token": token,
        @"udid": [self udid],
    };
    [self postToPath:kVerifyPath params:params completion:^(NSDictionary *json, NSString *rawBody, NSString *sign, NSError *error) {
        if (error) {
            // 网络失败：容错，不踢（离线可用）
            if (completion) completion(YES, nil);
            return;
        }
        if (!json) {
            if (completion) completion(YES, nil);
            return;
        }
        NSNumber *code = json[@"code"];
        if (code.integerValue != 0) {
            // 服务器明确拒绝：禁用(-9)/未激活(-5)/过期(-6)/换设备(-3)等
            // 先验签，只有响应签名有效才相信“服务器拒绝”，防止伪造响应把用户踢下线
            BOOL signedOk = [self verifyResponseSign:rawBody sign:sign];
            if (signedOk) {
                [self clearActivation];
                if (completion) completion(NO, json[@"message"] ?: @"验证失败");
            } else {
                // 无法验签：按网络异常容错，不踢（离线可用）
                if (completion) completion(YES, nil);
            }
            return;
        }
        // 验签通过才认为 valid
        BOOL ok = [self verifyResponseSign:rawBody sign:sign];
        if (completion) completion(ok, nil);
    }];
}

#pragma mark - 重装检测

+ (void)checkReinstallAndReset {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *docPath = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory,
                                                           NSUserDomainMask, YES).firstObject;
    NSString *markerPath = [docPath stringByAppendingPathComponent:@"install_marker"];
    NSString *execPath = [NSBundle mainBundle].executablePath;
    NSDictionary *attrs = [fm attributesOfItemAtPath:execPath error:nil];
    NSDate *mtime = attrs[NSFileModificationDate];
    if (!mtime) return;
    double cur = [mtime timeIntervalSince1970];

    NSString *saved = [NSString stringWithContentsOfFile:markerPath
                                                encoding:NSUTF8StringEncoding
                                                   error:nil];
    if (saved.length == 0) {
        if ([self keychainDataForAccount:@"device-udid"]) {
            [self resetForReinstall];
        }
        [self saveMarker:mtime toPath:markerPath];
        return;
    }
    if (fabs(saved.doubleValue - cur) > 1.0) {
        [self resetForReinstall];
        [self saveMarker:mtime toPath:markerPath];
    }
}

+ (void)saveMarker:(NSDate *)mtime toPath:(NSString *)path {
    NSString *s = [NSString stringWithFormat:@"%.0f", [mtime timeIntervalSince1970]];
    [s writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil];
}

+ (void)resetForReinstall {
    [self clearActivation];
    [self deleteKeychainDataForAccount:@"device-udid"];
}

#pragma mark - Keychain

+ (NSData *)keychainDataForAccount:(NSString *)account {
    NSDictionary *query = @{
        (id)kSecClass: (id)kSecClassGenericPassword,
        (id)kSecAttrService: @"cn.virtualloc.app",
        (id)kSecAttrAccount: account,
        (id)kSecReturnData: @YES,
        (id)kSecMatchLimit: (id)kSecMatchLimitOne,
    };
    CFTypeRef result = NULL;
    OSStatus st = SecItemCopyMatching((__bridge CFDictionaryRef)query, &result);
    if (st != errSecSuccess) return nil;
    return (__bridge_transfer NSData *)result;
}

+ (void)saveKeychainData:(NSData *)data forAccount:(NSString *)account {
    NSDictionary *query = @{
        (id)kSecClass: (id)kSecClassGenericPassword,
        (id)kSecAttrService: @"cn.virtualloc.app",
        (id)kSecAttrAccount: account,
    };
    NSDictionary *update = @{(id)kSecValueData: data};
    OSStatus st = SecItemUpdate((__bridge CFDictionaryRef)query, (__bridge CFDictionaryRef)update);
    if (st == errSecItemNotFound) {
        NSMutableDictionary *add = [query mutableCopy];
        add[(id)kSecValueData] = data;
        SecItemAdd((__bridge CFDictionaryRef)add, NULL);
    }
}

+ (void)deleteKeychainDataForAccount:(NSString *)account {
    NSDictionary *query = @{
        (id)kSecClass: (id)kSecClassGenericPassword,
        (id)kSecAttrService: @"cn.virtualloc.app",
        (id)kSecAttrAccount: account,
    };
    SecItemDelete((__bridge CFDictionaryRef)query);
}

@end
