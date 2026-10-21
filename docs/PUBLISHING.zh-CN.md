# 维护者发布流程

仓库的 main 分支保存源码、图片、音效与说明。EXE 和给使用者的 ZIP 发布到 Releases，不提交进 Git 历史。

## 准备发布

在 Windows 上执行：

```powershell
.\tools\build.ps1
.\tools\test.ps1 -SkipBuild
.\tools\package.ps1 -SkipBuild
```

检查 `dist/LokiThrogPets-v0.10.0-windows-x64.zip` 的内容：一个 EXE、操作说明、更新说明、权利说明和 EXE 的 SHA-256。

## GitHub 认证

使用 GitHub 官方 CLI `gh`。账户持有人在浏览器里完成官方授权，不在终端命令中粘贴密码或访问令牌。

```powershell
gh auth login --hostname github.com --git-protocol https --web
```

Git 提交身份可使用 GitHub 设置中给出的 noreply 邮箱，避免公开私人邮箱。

## 上传版本

确认发布说明和版本后，将源码提交并推送到自己的仓库，再创建标签和 Release。后续版本需要更新版本号、AssemblyInfo.cs、更新说明及发布说明。

```powershell
git push origin main
git tag v0.10.0
git push origin v0.10.0
gh release create v0.10.0 dist/LokiThrogPets-v0.10.0-windows-x64.zip dist/SHA256SUMS.txt --verify-tag --title "洛基与雷神 · v0.10.0" --notes-file release/v0.10.0.md
```

维护者可在发布前检查 Release 附件中的 ZIP 与仓库中源码编译出的版本一致。不要将个人配置、凭据、完整桌面截图、聊天记录或原始第三方参考截图加入仓库。
