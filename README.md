# link-audit

87 个官方文档入口的月度可用性审计。跑在 GitHub Actions 上，每月 1 日 03:00 UTC 自动执行一次。

## 为什么有这个仓

对照资料失效绝大多数不是"忘了放哪"，而是**文档站改版、迁移、被墙、或静默挂掉**。人工点 87 个链接既不会按时做，也不会留下可比对的记录。这个仓把"我收藏的文档还能不能打开"变成一件由 CI 每月替你回答的事实。

## 它在测什么

`links.txt` 是 87 条**官方**文档/API 入口，覆盖：NVIDIA（CUDA / Isaac / Nsight / Omniverse / NGC）、MITRE ATT&CK、Apache Arrow、MDN、astral（uv / ruff）、Google Colab 等。只放官方一手地址，不放假冒镜像和聚合站。

## 判定不只是 200 / 非 200

`scripts/05_monthly_link_audit.ps1` 用 `curl.exe` 探针，**同主机请求间隔 ≥ 250ms**，输出七档判定：

| 判定 | 含义 |
|---|---|
| `OK` | 200，无跳转 |
| `REDIRECT_OK` | 跳转后 200（记录了 `url_effective`，能看出站点搬家到哪） |
| `NETWORK` | 连不上 / 超时 / DNS 失败 |
| `PARTIAL` | 返回非完整内容（如 206、截断、连接中途断开） |
| `RATE_LIMITED` | 429 或被限流页拦截 |
| `REJECT_403` | 最小头被拒 **且** 完整浏览器头仍被拒 —— 只有两次都失败才算真坏 |
| `REJECT_HEADERS_OK` | 最小头被拒，但带完整浏览器头（`sec-fetch-*` / `sec-ch-ua` / `Upgrade-Insecure-Requests`）后通过 |

后两档是这个脚本存在的核心理由：**403 不等于链接死了**，很多站点对没有浏览器指纹的请求直接拒。先探一次最小头，再探一次完整浏览器头，结论才可信。

## 怎么跑

```powershell
pwsh ./scripts/05_monthly_link_audit.ps1 -LinksFile links.txt -OutCsv status.csv
```

CI 里额外做一道**行数断言**：期望 87 行，不等就失败。这条断言防的是"链接悄悄少了一条却没人发现"——增删条目时必须同步更新 `links.txt` 与 workflow 里的数字。

## 边界

- 只做只读 GET，不登录、不提交表单、不抓正文、不镜像内容
- 同主机节流 250ms，避免把审计变成对别人的扫描
- 输出的 `status.csv` 是可比对的时间序列，适合直接 diff 上个月

## 许可

MIT，见 [LICENSE](LICENSE)。
