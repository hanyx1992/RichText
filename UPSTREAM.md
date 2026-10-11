# RichText — Limenia 定制

上游：[LiYanan2004/RichText](https://github.com/LiYanan2004/RichText)。维护 fork：[hanyx1992/RichText](https://github.com/hanyx1992/RichText)，在 `main` 维护定制，以 `upstream` remote 跟踪原库。起点 `a2fb191988f6f2ce60574962c96a0e1846c36dae`，保留完整上游历史、示例与 LICENSE。

本轮定制和来源说明合为一个完整提交：最低行高环境入口与段落合并；属性一次遍历、重复提交与有效测高复用；可选 iOS 原生滚动视口、独立头部、可见附件定位、页内位置恢复和明确版本／配置未变时的早停；本次转换内属性复用。已见附件离屏隐藏并保留宿主，实际移除才销毁；嵌套正文不继承根视口，附件 run 不复用属性，不增加跨调用缓存。

Limenia 在 `Vendor/RichText` 以 Git submodule 固定已验证 commit；本地同 identity 根依赖覆盖 MarkdownView 3.0.0 的间接 RichText。正常检出执行 `git submodule update --init --recursive`，不自动追踪分支更新。应用侧解析与离线资源改写留在 Limenia。

升级先 fetch upstream，在 main 合入明确上游版本，核对定制是否仍需要，完成库回归及 Limenia 两端构建、阅读验证，再发布 fork commit 并更新应用 gitlink。同一任务的修补和整理在交付前合并为一个提交，不压缩原上游历史。
