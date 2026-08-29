# TLocationPlugin 新验证接入记录

已加入 `TLocation/License/LicenseManager.h/.m`，目标 Bundle ID 已改为 `com_kwai_gif`。

## 当前状态

- 客户端验证模块已放入源码树；
- 尚未填写新服务器地址和 HMAC 密钥；
- 尚未接入原有悬浮窗入口；
- 尚未修改 Xcode 工程文件，因此下一步需要把两个源文件加入 target Compile Sources。

## 接入原则

验证成功后才允许定位 Hook 生效；网络失败按离线容错策略放行，服务器明确禁用/过期才清除激活状态。
