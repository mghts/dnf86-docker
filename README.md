# DNF86 服务器部署

使用 Debian 12/13 x86_64，以 `root` 登录。游戏客户端和登录器需要另外准备。

先装好 [Docker 和 Compose 插件](https://docs.docker.com/engine/install/debian/)，再安装这几个工具：

```sh
apt update && apt install -y git curl python3 util-linux
```

首次部署，把 `203.0.113.10` 换成你的服务器公网 IP：

```sh
mkdir -p /docker && \
git clone https://github.com/mghts/dnf86-docker.git /docker/DNF86 && \
cd /docker/DNF86 && \
bash install.sh --public-ip 203.0.113.10
```

脚本会下载资源、导入镜像、生成密码并启动服务。下载中断可以重试；已有 `.env` 或 `data/` 时会停止。保留好 `.env` 和 `data/`。

在服务器安全组或路由器端口转发中放行：

| 协议 | 端口 |
| --- | --- |
| TCP | `7001`、`10011`、`7200`、`3306` |
| UDP | `7001`、`11011`、`7200`、`2311–2313` |

等几分钟，客户端和登录器填写你的公网 IP。数据库账号是 `game`，端口默认 `3306`，密码这样查看：

```sh
sed -n 's/^DNF_DB_PASSWORD=//p' /docker/DNF86/.env
```

以后启动服务：

```sh
cd /docker/DNF86
docker compose up -d --no-build --pull never
```

停服：

```sh
docker compose stop game database
```

启动出错时，在 `/docker/DNF86` 查看日志：

```sh
docker compose logs --tail 100 init database game
```
