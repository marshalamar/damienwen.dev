# 器物与回声

Damien Wen 的个人网站。网站只保留文章列表与文章阅读，不使用 CMS、数据库
或在线编辑后台。

## 本地运行

需要 Node.js `>=22.13.0`。

```bash
npm ci
npm run dev
```

打开终端打印的本地地址。

## 新增文章

运行：

```bash
npm run essay:new -- <slug> "文章标题"
```

例如：

```bash
npm run essay:new -- listening-notes "最近听到的几张专辑"
```

脚本会自动：

- 分配下一个文章编号；
- 使用北京时间填写发布日期；
- 先创建或复用配图目录 `public/essays/<slug>/`；
- 再原子创建 `content/essays/<编号>-<slug>.mdx`。

同时发起多个新增命令时，脚本会在项目内短暂排队，避免分配到相同编号。
如果创建失败，只会清理本次命令创建的文件与空目录；提前准备好的配图目录
和其中的文件会保留。

文章只要求标题和发布日期：

```mdx
export const meta = {
  title: "文章标题",
  publishedAt: "2026-07-28",
};

<Section title="第一节">

这里开始写正文。

</Section>
```

`subtitle`、`excerpt` 和 `sourceUrl` 都是可选字段。文章中的图片使用现有
`<ArticleImage />` 组件，并放在对应文章的配图目录中。

## 验证

```bash
npm run verify
```

它会执行代码检查、TypeScript 类型检查和一次生产构建，自动发现首页中的
每一篇文章逐页验证；随后从同一份 `dist/standalone` 启动随机本地端口，
实际请求文章、页面引用的本地静态资源和文章图片。新增普通文章不需要修改
页面组件或测试清单。

在 Codex 的 macOS seatbelt 环境里，如果系统禁止绑定本地端口，最后一段
HTTP 请求检查会在完成产物级验证后跳过；CI 和普通本地环境不会跳过。
需要在 Codex 中强制执行时，可运行
`STANDALONE_SMOKE_STRICT=1 npm run smoke:standalone`。

## 发布

推送 `main` 后，GitHub Actions 会构建并检查 standalone 产物，但不会读取
生产 Secret。完成一次性 VPS 配置、Environment 审批保护，并把仓库变量
`DEPLOY_ENABLED` 设为 `true` 后，再手动触发 `deploy.yml`；审批通过后，独立
的部署任务才会上传新版本、切换版本并检查 `http://127.0.0.1:3000`。失败时
会恢复上一版本；Cloudflare Tunnel 不参与普通文章发布。

一次性的 VPS 与 GitHub 环境配置见
[ops/README.md](ops/README.md)。

## Agent Skill

项目内置 `$publish-damienwen-site` Skill：

```text
.agents/skills/publish-damienwen-site/
```

可以直接告诉 Agent：

```text
使用 $publish-damienwen-site 新增一篇文章
```

或：

```text
使用 $publish-damienwen-site 校验并发布这篇文章
```
