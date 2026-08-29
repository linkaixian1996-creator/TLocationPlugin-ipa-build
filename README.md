# TLocationPlugin IPA 云打包（GitHub Actions）

把注入新验证逻辑的 TLocationPlugin 打进快手 IPA，全程在 GitHub 免费 macOS 云主机完成，不需要本机 Mac、不需要证书。

## 仓库内容

- `TLocationPlugin-src/`：插件源码（LicenseManager 已填好服务器地址 + VCA_KEY）+ yololib
- `.github/workflows/build-ipa.yml`：云打包流水线

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
- VCA_KEY：`cabee0556a79e94b01c3fba1e37f63056d0b6f668e336f6e402e07f4adab82bc`（必须与 VPS 上 `/opt/tlocation-vca/.env` 一致）
