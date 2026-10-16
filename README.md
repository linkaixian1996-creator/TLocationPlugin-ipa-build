# 抖音（Aweme 40.7.0）虚拟定位插件 — 云打包仓库

把 TLocationPlugin（虚拟定位 + 卡密验证）注入抖音 IPA，产出可安装的成品 IPA。
与快手那套的区别：**抖音包是干净包，没有任何插件，需要从零注入**。

## 包内结构

| 路径 | 作用 |
|---|---|
| `TLocationPlugin-src/` | 插件源码（含 `yololib` 注入器、`TLocationPluginImages.bundle` 资源） |
| `TLocationPlugin-src/TLocationPlugin/Tools/TLocationObserve.h` | **构建模式开关** `TLO_OBSERVE_MODE`（1=观测版，0=正式版） |
| `build_framework.sh` | 手工编译并完整组装 framework（clang 编 .m + ibtool 编 nib + 资源 + Info.plist + adhoc 签名） |
| `codemagic.yaml` | Codemagic 云打包工作流（推荐） |
| `.github/workflows/build-douyin-ipa.yml` | GitHub Actions 备用流水线（macos-14） |

## 关键参数

| 项 | 值 |
|---|---|
| 包内 App 目录 | `Payload/Aweme.app` |
| 主二进制（注入目标） | `Aweme`（只有 276 KB；真正代码在 `Frameworks/AwemeCore.framework/AwemeCore`，1 GB，**绝不要动**） |
| Bundle ID | `com.ss.iphone.ugc.Aweme` |
| 注入路径 | `Frameworks/TLocationPlugin.framework/TLocationPlugin`（主二进制已有 `@executable_path/Frameworks` 这条 rpath） |
| GitHub Release tag | `douyin-40.7.0`（资产名必须是 `Douyin_40.7.0.ipa`，中文名会让 curl 取不到） |

## 使用流程

1. 把抖音原始 IPA 改名为 `Douyin_40.7.0.ipa`，在仓库 **Releases** 新建 tag `douyin-40.7.0` 并上传该资产。
2. Codemagic → 选 `Build Douyin IPA` 工作流 → 选对应分支 → Start build（约 5~15 分钟）。
3. 从 Artifacts 下载 `Douyin_new.ipa`。
4. 传到手机：
   - Windows 上在 IPA 所在目录跑 `python -m http.server 8000`，手机 Safari 打开 `http://<电脑局域网IP>:8000/Douyin_new.ipa` 下载；
   - iPhone 11 / iOS 16.6.1 → 用**巨魔（TrollStore）**安装；
   - iPhone 14 Pro / iOS 27 → 用**全能签**重签安装（需开「开发者模式」）。

## 观测版 vs 正式版

开关在 `TLocationPlugin-src/TLocationPlugin/Tools/TLocationObserve.h`：

- `#define TLO_OBSERVE_MODE 1` → **观测版**：不校验卡密；冷启动 2.5 秒后自动下发假坐标
  （北京天安门 GCJ02 `39.908722, 116.397499`）、开启 toast 提示、显示悬浮球。
  用途：验证抖音的定位通道能不能被假坐标改掉（看抖音自己的「同城 / 开播城市 / 作品定位」变不变）。
- `#define TLO_OBSERVE_MODE 0` → **正式版**：走卡密门控（未激活不替换坐标、不显示悬浮球、冷启动联网校验）。

## 已知边界（抖音与快手的差异）

- 插件只拦 `CLLocationManager` 的 delegate 回调。抖音的 BDLocation 栈里有 5 个类实现该回调，机制能覆盖；
  但 `-[BDLLightLocationManager getCoreLocationLastLocationWithAccuracy:config:]`（直读 last location）、
  IP 定位（`requestIPLocationWithCompletion:`）、WiFi/BSSID 上报这三条旁路当前不拦，需要后续补。
- 注入会破坏原签名：流水线用 `codesign -f -s -`（adhoc）重新签；巨魔安装时会再 permasign，全能签会用自己的证书重签。
- 重签会丢掉部分 entitlements（推送 `aps-environment`、App Group、`increased-memory-limit` 内存上限等），
  这是重签的通病，不是插件问题；若出现被系统杀后台变频繁，优先怀疑内存上限 entitlement 被降级。
