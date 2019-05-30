#!/bin/env sh
PATH="/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin"; cd "$(dirname "$0")"
exec 4>&1; ECHO(){ echo "${@}" >&4; }; exec 3<>"/dev/null"; exec 0<&3;exec 1>&3;exec 2>&3

#服务状态测试
pidof "radiusd" && {
    [ -f "./LocalSQL.Enabled" ] && { ../mariadb/PeriodicST-state-check.sh || exit; }
    exit 0; }
