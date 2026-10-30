#!/usr/bin/env bash
set -euo pipefail
umask 077

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
RELEASE='v2026.10.30'
IMAGE='dnf86-runtime-261030-timeout-linux-amd64.tar.gz'
repository=''
public_ip=''

fail() { printf '%s\n' "$*" >&2; exit 1; }
usage() {
  printf '%s\n' '用法：bash install.sh --public-ip 服务器公网IPv4 [--repo 用户名/仓库名]'
}

while (($#)); do
  case "$1" in
    --public-ip|--repo)
      (($# >= 2)) || fail "$1 后面需要填写参数。"
      if [[ $1 == --public-ip ]]; then public_ip=$2; else repository=$2; fi
      shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) usage >&2; fail "不支持的参数：$1" ;;
  esac
done
[[ -n $public_ip ]] || { usage >&2; exit 1; }

for command in python3 docker curl flock; do
  command -v "$command" >/dev/null || fail "缺少 ${command}，请先安装 Docker、Compose 插件、Python 3、curl 和 util-linux。"
done
python3 - "$public_ip" <<'PY'
import ipaddress
import sys
try:
    ipaddress.IPv4Address(sys.argv[1])
except ipaddress.AddressValueError:
    sys.exit('请填写正确的公网 IPv4。')
PY
[[ $(uname -s) == Linux && $(uname -m) == x86_64 ]] || fail '请在 Debian x86_64 服务器上执行。'
[[ $(id -u) == 0 ]] || fail '请以 root 执行。'

# A first installation must not inherit paths or credentials from another stack.
for variable in COMPOSE_FILE COMPOSE_PROJECT_NAME COMPOSE_ENV_FILES DNF_IMAGE \
  DNF_SOURCE_DIR DNF_DATA_DIR DNF_PUBLIC_IP DNF_LISTEN_IP MYSQL_ROOT_PASSWORD \
  DNF_DB_PASSWORD MYSQL_EXTERNAL_LISTEN_IP MYSQL_EXTERNAL_PORT MYSQL_MAX_CONNECTIONS \
  MYSQL_CHARACTER_SET_SERVER MYSQL_COLLATION_SERVER MYSQL_MAX_ALLOWED_PACKET; do
  [[ -z ${!variable:-} ]] || fail "请先取消终端中的 $variable 环境变量，再重新安装。"
done

cd "$ROOT"
[[ ! -L .dnf86-install.lock ]] || fail '安装锁不能是符号链接。'
exec 9>>.dnf86-install.lock
flock -n 9 || fail '另一个安装进程正在运行，请等待它结束。'
for path in .env data; do
  [[ ! -e $path && ! -L $path ]] || fail "已存在 ${path}，安装已停止。保留现有数据，启动请使用 docker compose up -d --no-build --pull never。"
done
[[ -f compose.yaml && -f scripts/configure.py ]] || fail '缺少 compose.yaml 或 scripts/configure.py，请完整下载部署仓库。'
docker compose version >/dev/null
docker info >/dev/null

if [[ -z $repository ]]; then
  origin=$(git remote get-url origin 2>/dev/null || true)
  case "$origin" in
    https://github.com/*) repository=${origin#https://github.com/} ;;
    git@github.com:*) repository=${origin#git@github.com:} ;;
    *) fail '无法识别 GitHub 仓库，请补充 --repo 用户名/仓库名。' ;;
  esac
  repository=${repository%/}
  repository=${repository%.git}
fi
[[ $repository =~ ^[A-Za-z0-9][A-Za-z0-9_.-]*/[A-Za-z0-9][A-Za-z0-9_.-]*$ ]] || fail '仓库格式应为 用户名/仓库名。'

for path in private private/source private/delivery; do
  [[ ! -L $path ]] || fail "$path 不能是符号链接。"
  mkdir -p "$path"
done
release_record="$repository/$RELEASE"
record_file=private/.download-release
[[ ! -L $record_file ]] || fail '下载版本记录不能是符号链接。'
if [[ -e $record_file ]]; then
  [[ $(cat "$record_file") == "$release_record" ]] || fail '此目录已下载过其他版本，请在新的目录安装。'
else
  printf '%s\n' "$release_record" > "$record_file"
fi

download() {
  local asset=$1 destination=$2
  [[ ! -L $destination && ! -L $destination.part ]] || fail "$destination 不能是符号链接。"
  if [[ -f $destination ]]; then
    printf '使用已下载文件：%s\n' "$asset"
    return
  fi
  [[ ! -e $destination && ! -d $destination.part ]] || fail "$destination 下载路径被占用。"
  printf '下载：%s\n' "$asset"
  curl --fail --location --proto '=https' --proto-redir '=https' \
    --retry 3 --connect-timeout 20 --continue-at - \
    --output "$destination.part" \
    "https://github.com/$repository/releases/download/$RELEASE/$asset"
  mv -n -- "$destination.part" "$destination"
}

download compat.json private/source/compat.json
download manifest.json private/source/manifest.json
download game.tar private/source/game.tar
download database.tar private/source/database.tar
download "$IMAGE" "private/delivery/$IMAGE"

printf '导入镜像……\n'
docker load -i "private/delivery/$IMAGE"
python3 scripts/configure.py --public-ip "$public_ip"
docker compose --env-file .env -f compose.yaml config --quiet
docker compose --env-file .env -f compose.yaml up -d --no-build --pull never

printf '\n服务已启动，请等待几分钟后连接。\n客户端地址：%s\n数据库账号：game，端口：3306\n' "$public_ip"
printf '查看数据库密码：sed -n '\''s/^DNF_DB_PASSWORD=//p'\'' "%s/.env"\n' "$ROOT"
printf '需要放行 TCP：7001、10011、7200、3306；UDP：7001、11011、7200、2311–2313。\n'
