# TLocationPlugin IPA 云打包（GitHub Actions）

把注入新验证逻辑的 TLocationPlugin 打进快手 IPA：**移除旧 3DES 卡密验证 → 保留虚拟定位功能 → 装入新 LicenseManager 验证**。全程在 GitHub 免费 macOS 云主机完成，不需要本机 Mac、不需要证书。

## 仓库内容

- `TLocationPlugin-src/`：插件源码（LicenseManager 已填好服务器地址 + VCA_KEY）+ yololib
- `.github/workflows/build-ipa.yml`：云打包流水线

## 打包逻辑说明

- 原始 IPA 里插件是 `Frameworks/TLocationPlugin.framework`（旧版，含旧 3DES 验证）。
- 流水线用**干净开源源码 + 新 LicenseManager** 重新编译 framework，**整包替换**旧的 → 旧验证代码彻底移除，虚拟定位功能保留，新验证装入。
- 主二进制原本已加载该 framework，无需重复注入；若检测到未加载则用 yololib 补注入。
- 激活入口：连点 5 次快手窗口打开设置界面后，未激活会自动弹出卡密输入框。

## 使用方法

1. **GitHub Desktop** → File → Add Local Repository → 选择本目录 → Publish repository（**务必选 Private 私有仓库**，因为源码里含 VCA_KEY）。
2. 网页打开仓库 → **Releases** → Create a new release：
   - Tag 填 `kwai-14.7.20`
   - 上传 `Kwai_14.7.20.ipa`（272MB）
   - Publish release
3. 仓库 **Actions** 页 → 左侧选 `Build Kwai IPA` → Run workflow（release_tag 默认 `kwai-14.7.20`）→ 等几分钟。
4. 跑完 Actions 页面下方出现 **Artifacts** → 下载 `Kwai_new_ipa`，解压得到 `Kwai_new.ipa`。
5. 把 `Kwai_new.ipa` 传到 iPhone，用**全能签**（个人证书）重签安装。

> 仓库必须是 Private：LicenseManager.m 里的 VCA_KEY 不能进公开仓库。

## 客户端配置（已填好）

- 服务器：`https://ks.etgstudio.live`
- VCA_KEY：**不放仓库**。构建时从 GitHub **Secrets** 读取（见第 2 步）；必须与 VPS 上 `/opt/tlocation-vca/.env` 的 `VCA_KEY` 完全一致（`sudo cat /opt/tlocation-vca/.env | grep VCA_KEY` 查看）。

## 为什么仓库必须是 Public

- GitHub 免费版对**私有仓库**不提供 macOS 云主机，任务会一直排队；
- 改为 **Public** 后免费额度即可用；
- 真实密钥已从源码移除，通过 **Settings → Secrets and variables → Actions → New repository secret** 配置 `VCA_KEY`，构建时自动注入，仓库公开也不会泄露。
