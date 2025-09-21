# README.md

<marquee style="color:red; font-weight:bold;">
本开源项目由点动云独家提供技术支持，仅供交流学习使用，禁止用于违法用途，请各位自行遵守。
</marquee>

---

## 项目简介

本仓库收集并整理了常见**落地机 ↔ 中转机**的节点中转脚本与使用说明，覆盖 `hysteria2`、`TUIC`、`VLESS`、`SOCKS5` 等协议组合，目标是方便用户快速搭建中转链路并在客户端（如 v2rayN）中导入自定义配置文件进行使用。
**注意**：请仅用于合规与学习场景，使用前务必遵守所在地法律法规。

---

## 一键安装

在安装前请确保你的系统支持 `bash` 环境，且系统网络正常。

> 落地机 / 中转机 均采用一键脚本方式调用（`curl | bash`）。脚本路径已在本 README 中列出，若需要自定义路径或做二次开发，请手动下载脚本、审查代码后再执行。

---

## 配置要求

### 内存

* 最低：128MB
* 推荐：256MB 及以上

### 操作系统

* Ubuntu 22 / 23 / 24（建议使用最新稳定内核与常规安全更新）

### 推荐工具

* FinalShell（便于远程管理）
  下载地址（示例）：[FinalShell](https://dl.hostbuf.com/finalshell3/finalshell_windows_x64.exe)

---

## 支持的中转方案与使用方法（示例）

### hysteria2 中转 hysteria2（hysteria2 -> hysteria2）

落地机执行：

```bash
bash <(curl -Ls https://raw.githubusercontent.com/diandongyun/Transfer/blob/main/hysteria2-hysteria2/destination-node.sh)
```

落地机会在系统中生成 `/opt/hysteria2_client.yaml`，将该文件下载并上传到中转机的 `/opt/` 下。
中转机执行：

```bash
bash <(curl -Ls https://raw.githubusercontent.com/diandongyun/Transfer/blob/main/hysteria2-hysteria2/relay-node.sh)
```

中转机会生成 `/opt/hysteria2_relay_client.yaml`，在 v2rayN 中可使用“导入自定义配置”功能导入该 YAML 文件。

---

### socks5 中转 TUIC（socks5 -> TUIC）

落地机执行：

```bash
bash <(curl -Ls https://raw.githubusercontent.com/Transfer/blob/main/socks5-TUIC/socks5.sh)
```

落地机会生成 `socks5_config.json`，将该文件下载并上传到中转机 `/opt/`。
中转机执行：

```bash
bash <(curl -Ls https://raw.githubusercontent.com/diandongyun/Transfer/blob/main/socks5-TUIC/TUIC.sh)
```

完成后根据生成的节点信息在客户端导入或手动配置 TUIC 节点。

---

### socks5 中转 VLESS（socks5 -> VLESS）

落地机执行：

```bash
bash <(curl -Ls https://raw.githubusercontent.com/diandongyun/Transfer/blob/main/socks5-vless/socks5.sh)
```

落地机会产出 `socks5_config.json`，将其上传到中转机 `/opt/`。
中转机执行：

```bash
bash <(curl -Ls https://raw.githubusercontent.com/Transfer/blob/main/socks5-vless/vless.sh)
```

导出后在 v2rayN 或其他支持 VLESS 的客户端导入使用。

---

### VLESS 中转 SOCKS5（VLESS -> SOCKS5）

落地机执行：

```bash
bash <(curl -Ls https://raw.githubusercontent.com/Transfer/blob/main/vless-socks5/vless.sh)
```

在落地机 `/opt/` 下找到 VLESS 的 JSON 配置文件，下载并上传到中转机 `/opt/`。
中转机执行：

```bash
bash <(curl -Ls https://raw.githubusercontent.com/Transfer/blob/main/vless-socks5/socks5.sh)
```

导出后在客户端导入或手动配置 SOCKS5 节点。

---

## 协议组合对比（简要建议）

| 协议组合                            |   抗封锁 |    延迟 |   稳定性 | 部署复杂度 | 适用场景       |
| ------------------------------- | ----: | ----: | ----: | ----: | ---------- |
| hysteria2 ↔ hysteria2           | ★★★☆☆ | ★★★★★ | ★★★☆☆ | ★★★★☆ | 直播/低延迟稳定场景 |
| Hysteria2 + UDP + TLS + Obfs    | ★★★☆☆ | ★★★★★ | ★★★☆☆ | ★★☆☆☆ | 大流量影视/流媒体  |
| TUIC + UDP + QUIC + TLS         | ★★★★☆ | ★★★★★ | ★★★★☆ | ★★★★★ | 游戏/低延迟场景   |
| VLESS + Reality + uTLS + Vision | ★★★★★ | ★★★☆☆ | ★★★★☆ | ★☆☆☆☆ | 长期稳定/高隐蔽场景 |

---

## 部署建议与注意事项

1. **安全性**：一切面向公网的服务请使用 TLS（证书）或其他加密手段保护控制与传输通道。
2. **防火墙/端口**：确保防火墙（如 `ufw`、`firewalld`、iptables）允许所需端口的入站/出站流量；若使用端口跳动或 SNI 伪装，请在防火墙规则上留意策略与日志。
3. **资源限制**：落地机建议限制单连接带宽，避免单用户跑满出口带宽导致其他服务不可用。
4. **日志**：脚本通常会产生日志文件，便于排错。生产环境建议启用轮转（logrotate）并限制日志大小。
5. **证书与域名**：若使用 SNI/TLS 伪装，请确保证书合法且定期续签（自动化：certbot 等工具）。
6. **升级与审查**：一键脚本仅为便捷入口，执行前建议审查脚本内容并在受控环境中测试再投入生产。

---

## 常见问题（FAQ）

**Q1：导入到 v2rayN 后无法连接，如何排查？**
A：检查（1）中转机与落地机的配置文件路径是否正确，（2）端口在防火墙与云厂商安全组中是否放通，（3）查看中转机/落地机日志确认是否有握手或鉴权错误。

**Q2：脚本运行报错“curl: command not found”或 `bash` 未找到？**
A：请先安装 `curl` 与 `bash`：`apt update && apt install -y curl bash`。

**Q3：如何验证节点延迟与带宽？**
A：可使用 `ping`、`mtr` 测试连通性与路径，`iperf3` 测试吞吐性能（需双方支持），或使用 `curl -I`、`wget` 下载样本测试实际吞吐。

**Q4：我想自定义端口和证书，该如何修改？**
A：下载脚本后在本地打开并编辑相关变量（通常脚本顶部或 `config` 文件段），修改端口/证书路径后再手动执行脚本中对应的服务启动命令。

---

## 日志与调试

* 常用日志路径：`/var/log/` 下对应服务子目录或 `/opt/` 下生成的 `.log` 文件。
* 常用排错命令：

  * `systemctl status <service>`（如果脚本将服务注册为 systemd）
  * `journalctl -u <service> -n 200`（查看最近 200 行日志）
  * `tail -f /path/to/log`（实时查看日志）

---

## 性能 & 优化建议

* 使用 `aio`/多线程/epoll 等高效 I/O 实现的二进制更适合高并发场景。
* 若带宽为瓶颈，优先优化链路（更换更好线路／更高规格 VPS），或在中转机做流量整形。
* 对于低配落地机（128MB），尽量禁用非必要模块（如冗余混淆层、复杂统计）以降低内存占用。

---

## 示例导入流程（以 v2rayN 为例）

1. 在落地机运行对应的落地脚本并下载生成的配置文件（如 `/opt/hysteria2_client.yaml` 或 `socks5_config.json`）。
2. 将文件上传到中转机的 `/opt/`（若需要在中转机运行相关脚本以生成中转端配置，执行中转脚本）。
3. 打开 v2rayN → 服务器 → 导入自定义配置 → 选择生成的 YAML/JSON 文件 → 应用并启动。

---

## 贡献指南

欢迎以合规用途贡献代码或改进文档：

1. Fork 本仓库 → 新建分支 → 提交修改 → 发起 PR。
2. 请在 PR 中说明修改目的、改动点与测试方法（若涉及脚本变更请附上在测试环境执行的命令与结果截图/日志摘录）。

---

## 许可证

本项目 README 与示例脚本遵循开源协议（请在仓库根目录查看 LICENSE 文件以确认具体许可类型）。
使用者在使用本项目代码时须遵守相关法律法规并对自己的行为承担全部责任。

---

## 联系方式

若需技术支持或反馈问题，请在仓库 Issues 中提问，或联系维护人（点动云）QQ：1531116771

---

*最后再次提醒：本开源项目由点动云独家提供技术支持，仅供交流学习使用，禁止用于违法用途，请各位自行遵守。*
