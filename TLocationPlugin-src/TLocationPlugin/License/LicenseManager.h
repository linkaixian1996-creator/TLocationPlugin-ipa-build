#import <Foundation/Foundation.h>

// 幻位服务器验证（HMAC-SHA256 + 紧凑JSON + response_sign）
// 协议：
//   激活  POST {base}/vca//activate.php   action=activate
//   心跳  POST {base}/vca//verify.php     action=heartbeat
//   签名  除 sign 外参数按字母序，值 URL 编码，& 连接，HMAC-SHA256(密钥)
//   验签  响应 JSON 原文（去掉末尾 response_sign）→ HMAC-SHA256 比对
@interface LicenseManager : NSObject

// ---- 服务器配置（部署时修改 ServerConfig 常量）----
+ (NSString *)serverBaseURL;
+ (void)setServerBaseURL:(NSString *)url;
+ (NSData *)signKey;

// ---- 设备标识 ----
// 本机 UDID（Keychain 持久化，UUID 格式大写）
+ (NSString *)udid;

// ---- 激活（服务器验证，异步）----
+ (void)activateWithCard:(NSString *)card
              completion:(void (^)(BOOL ok, NSString *message))completion;

// ---- 本地状态（离线判断，基于已存 token/到期时间）----
+ (BOOL)isActivated;
+ (BOOL)isExpired;
+ (NSDate *)expiryDate;
+ (NSString *)token;
+ (NSString *)storedCardKey;
+ (NSString *)activatedModel;

// ---- 心跳（服务器校验，异步）----
// valid=YES 正常；valid=NO 且 message 非空表示服务器明确拒绝（禁用/未激活/换设备）
+ (void)heartbeatWithCompletion:(void (^)(BOOL valid, NSString *message))completion;

// ---- 清除本地激活状态 ----
+ (void)clearActivation;

// ---- 重装检测（覆盖安装/卸载重装 → 清激活状态）----
+ (void)checkReinstallAndReset;

// ---- 签名工具（供其它模块复用）----
+ (NSString *)hmacSignForParams:(NSDictionary *)params;
+ (BOOL)verifyResponseSign:(NSString *)bodyHex sign:(NSString *)signHex;

@end
