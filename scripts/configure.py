#!/usr/bin/env python3
"""Create a local .env with random passwords; never overwrite an existing file."""
import argparse
import ipaddress
import os
from pathlib import Path
import secrets


def prepare_data_directory(path):
    """Protect host data while letting source MySQL uid 27 traverse its mount."""
    root = Path(path)
    if root.exists() or root.is_symlink():
        raise FileExistsError('Data directory already exists; preserve it and its matching .env: %s' % root)
    root.mkdir(mode=0o700, parents=True)
    (root / 'database').mkdir(mode=0o755)
    (root / 'database').chmod(0o755)
    (root / 'game').mkdir(mode=0o700)


parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--public-ip', required=True, type=ipaddress.IPv4Address)
parser.add_argument('--listen-ip', default='0.0.0.0', type=ipaddress.IPv4Address)
parser.add_argument('--project-name', default='dnf86')
parser.add_argument('--output', type=Path, default=Path('.env'))
parser.add_argument('--data-dir', type=Path, default=Path('data'))
args = parser.parse_args()
os.umask(0o077)
if args.output.exists() or args.output.is_symlink():
    raise FileExistsError('Configuration already exists; preserve the existing data and passwords: %s' % args.output)
prepare_data_directory(args.data_dir)
with args.output.open('x') as f:
    f.write('COMPOSE_PROJECT_NAME=%s\nDNF_IMAGE=dnf86-runtime:261030-timeout\n' % args.project_name)
    data_setting = str(args.data_dir) if args.data_dir.is_absolute() else './' + str(args.data_dir)
    f.write('DNF_DATA_DIR=%s\n' % data_setting)
    f.write('DNF_PUBLIC_IP=%s\nDNF_LISTEN_IP=%s\n' % (args.public_ip, args.listen_ip))
    f.write('MYSQL_EXTERNAL_LISTEN_IP=%s\nMYSQL_EXTERNAL_PORT=3306\n' % args.listen_ip)
    f.write('MYSQL_ROOT_PASSWORD=%s\nDNF_DB_PASSWORD=%s\n' % (secrets.token_hex(20), secrets.token_hex(10)))
print('Created %s (mode 0600); secrets were not printed.' % args.output)
print('Persistent directories: %s/database and %s/game' % (args.data_dir.resolve(), args.data_dir.resolve()))
