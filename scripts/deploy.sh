#!/usr/bin/env bash
# Доставка статического ресурса на devops-vm.
set -euo pipefail

REMOTE="${REMOTE:-devops}"
REMOTE_DIR="${REMOTE_DIR:-/var/www/devops-site}"
SITE_URL="${SITE_URL:-https://devops.local}"
CA_CERT="${CA_CERT:-${HOME}/devops.crt}"
CURL_RESOLVE="${CURL_RESOLVE:-devops.local:443:127.0.0.1}"
REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
LOCAL_DIR="${REPO_ROOT}/site/"

if ! command -v rsync >/dev/null 2>&1; then
    portable_rsync="${REPO_ROOT}/../tools/usr/bin/rsync.exe"
    if [[ -x $portable_rsync ]]; then
        export PATH="$(dirname -- "$portable_rsync"):$PATH"
    else
        echo 'Ошибка: rsync не найден.' >&2
        exit 1
    fi
fi

if [[ $# -gt 1 || ( $# -eq 1 && $1 != --dry-run ) ]]; then
    printf 'Использование: %s [--dry-run]\n' "$0" >&2
    exit 1
fi
DRY_RUN=false
[[ $# -eq 1 ]] && DRY_RUN=true

if [[ ! -f ${LOCAL_DIR}index.html ]]; then
    echo 'Ошибка: site/index.html отсутствует; доставка отменена.' >&2
    exit 1
fi
if [[ -n $(git -C "$REPO_ROOT" status --porcelain --untracked-files=all) ]]; then
    echo 'Ошибка: в репозитории есть незафиксированные изменения.' >&2
    exit 1
fi

rsync_args=(-avz --delete --chmod=D755,F644
    -e 'ssh -o BatchMode=yes -o ConnectTimeout=5')
if $DRY_RUN; then
    rsync_args+=(--dry-run)
fi

if ! rsync "${rsync_args[@]}" "$LOCAL_DIR" "${REMOTE}:${REMOTE_DIR}/"; then
    echo 'Ошибка: синхронизация не выполнена.' >&2
    exit 1
fi
if $DRY_RUN; then
    echo 'Пробный запуск завершён; сервер не изменён.'
    exit 0
fi

if [[ ! -f $CA_CERT ]]; then
    echo "Ошибка: доверенный сертификат не найден: $CA_CERT" >&2
    exit 1
fi
curl_args=(-fsS --cacert "$CA_CERT" -o /dev/null)
if [[ -n $CURL_RESOLVE ]]; then
    curl_args+=(--resolve "$CURL_RESOLVE")
fi
if ! curl "${curl_args[@]}" "$SITE_URL"; then
    echo "Ошибка: проверка HTTPS не прошла: $SITE_URL" >&2
    exit 1
fi

printf 'Доставлен коммит %s\n' "$(git -C "$REPO_ROOT" rev-parse --short HEAD)"
