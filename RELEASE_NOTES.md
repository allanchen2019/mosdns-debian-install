# Release v5.1.3

## 版本更新要点 (Release Highlights)

- **系统更新机制重构 (System Update Refactoring)**:
  - 增加对 Release 稳定版 (基于 GitHub Tag) 和 Dev 开发版 (基于分支最新 Commit) 切换与更新通道的支持。
  - 在 Web 控制面板的“系统维护”卡片中新增了更新通道选择下拉框，并实现自重连与平滑升级体验。
  - 重构 `update-all.sh` 脚本，在执行更新和 git 检出前，自动备份并在完成后恢复用户配置文件 (`config-v5.yaml`)、SQLite 数据库 (`panel.db*`) 以及自定义域名规则列表 (`direct-domain.txt`, `local-domain.txt`)，避免数据丢失。
  - 解决由于本地配置/规则修改导致 Git 检出冲突的 Bug，采用 `git checkout -f` 强制切换以保证自更新逻辑的健壮性。

- **自定义域名直连与局域网自治默认配置 (Default Custom Rules Initialization)**:
  - 优化 `install-mosdns.sh` 和 `update-all.sh`，在初次安装及日常更新时，自动检测并初始化 `direct-domain.txt`（默认包含 Taobao、AliCDN 和 `.cn` 的直连路由规则）和 `local-domain.txt`（包含局域网自治路由规则），确保最佳开箱体验。

- **开发版版本号动态显示 (Dynamic Dev Version Display)**:
  - 实现 local 本地编译与 GitHub Actions 远程编译时的 checkout 状态检测。如果是 Dev 开发版，版本号自动编译为 `dev-COMMIT_ID`；如果是 Release 稳定版，则显示对应的 GitHub Tag 名字。

- **布局溢出与移动端自适应优化 (Layout & Overflow Fixes)**:
  - 修复了系统运维面板因内容增加导致最下方操作按钮被遮挡的问题。通过引入滚动容器包裹卡片，使页面高度完美贴合视口，并在移动端自适应适配网格高度。

## 一键更新与升级命令 (One-Key Update Commands)

### 1. 已经是 v5.x 的用户（本地更新命令）：
```bash
# 升级至最新 Release 稳定版
bash /opt/mosdns/update-all.sh release

# 升级至最新 Dev 开发版
bash /opt/mosdns/update-all.sh dev
```

### 2. 远程/全新安装一键升级命令：
```bash
# 使用一键菜单进行安装或升级
bash <(curl -Ls https://raw.githubusercontent.com/allanchen2019/mosdns-debian-install/main/AutoSetup.sh)
```
