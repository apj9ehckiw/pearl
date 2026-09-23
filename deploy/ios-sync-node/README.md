# 自建 iOS 钱包同步节点

iOS 钱包的 SPV 同步除了区块头，还需要紧凑过滤器、相关区块和交易广播。这里运行仓库自带的 `pearld` 全节点；它持续从 Pearl 网络同步，把链数据保存在 Docker 卷中，并通过原生 P2P 协议提供给手机。手机仍按原有 SPV 流程校验区块头。此地址不是 HTTP API，也不是 RPC 地址。

在有公网 IP 或可从手机访问的服务器上，安装 Docker Compose，从仓库根目录运行：

```sh
docker compose -f deploy/ios-sync-node/compose.yaml up -d --build
docker compose -f deploy/ios-sync-node/compose.yaml logs -f pearl-mainnet
```

主网开放 TCP `44108`；iOS 钱包的“设置 → 同步节点”填写 `你的域名:44108` 或 `公网IP:44108`，保存并重新解锁。端口不填时会自动使用主网的 `44108`。测试网 2 需要单独启动：

```sh
docker compose -f deploy/ios-sync-node/compose.yaml --profile testnet2 up -d --build
```

测试网 2 开放 TCP `44112`，并在手机选择测试网 2 后填写对应地址。两个网络使用不同的数据卷，地址设置也分别保存。服务器需要持续运行并留有区块链增长所需的磁盘空间；首次同步完成前，手机端同步可能停滞。卷保留时，容器重启会复用已缓存的链数据。无需对外开放 RPC 端口，本配置已禁用 RPC。只允许可信设备连接时可通过防火墙限制 P2P 端口的来源 IP；不要把钱包助记词或私钥放到服务器上。

手机端留空地址可恢复公共节点自动发现。填写自建地址后，手机只连接该节点；若节点不可达，钱包不会自动回退到公共节点。需要更改时，在钱包解锁状态进入设置修改地址。该节点能观察到手机的连接和 SPV 查询，因此应由用户自己运营或充分信任。
