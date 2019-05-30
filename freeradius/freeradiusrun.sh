#!/bin/env sh
PATH="/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin"; cd "$(dirname "$0")"
exec 4>&1; ECHO(){ echo "${@}" >&4; }; exec 3<>"/dev/null"; exec 0<&3;exec 1>&3;exec 2>&3

SQLEN="./LocalSQL.Enabled"

#先行服务停止
for ID in {1..20}; do pkill "^radiusd$" || break; sleep 0.5; done
[ -f "$SQLEN" ] && { rm -f "$SQLEN"; ../mariadb/mariadbstart.sh "stop"; }
[ "$1" == "stop" ] && exit 0

#DDNS注册
DDNSREG="./PeriodicRT-ddns-update"
[ -f "$DDNSREG" ] && ( chmod +x "$DDNSREG"; setsid "$DDNSREG" & )

#Radius服务库表创建过程($1服务器名称,$2端口,$3账号,$4密码,$5库名称)
#操作过程仅尝试建立必要的数据库和表,不代表数据库连接或账号的有效性
RADIUS_DBTB_CREATE() {
    local TB=""; local TBS=(
        "CREATE TABLE radacct (
            radacctid bigint(21) NOT NULL auto_increment,
            acctsessionid varchar(64) NOT NULL default '',
            acctuniqueid varchar(32) NOT NULL default '',
            username varchar(64) NOT NULL default '',
            groupname varchar(64) NOT NULL default '',
            realm varchar(64) default '',
            nasipaddress varchar(15) NOT NULL default '',
            nasportid varchar(15) default NULL,
            nasporttype varchar(32) default NULL,
            acctstarttime datetime NULL default NULL,
            acctupdatetime datetime NULL default NULL,
            acctstoptime datetime NULL default NULL,
            acctinterval int(12) default NULL,
            acctsessiontime int(12) unsigned default NULL,
            acctauthentic varchar(32) default NULL,
            connectinfo_start varchar(50) default NULL,
            connectinfo_stop varchar(50) default NULL,
            acctinputoctets bigint(20) default NULL,
            acctoutputoctets bigint(20) default NULL,
            calledstationid varchar(50) NOT NULL default '',
            callingstationid varchar(50) NOT NULL default '',
            acctterminatecause varchar(32) NOT NULL default '',
            servicetype varchar(32) default NULL,
            framedprotocol varchar(32) default NULL,
            framedipaddress varchar(15) NOT NULL default '',
            PRIMARY KEY (radacctid),
            UNIQUE KEY acctuniqueid (acctuniqueid),
            KEY username (username),
            KEY framedipaddress (framedipaddress),
            KEY acctsessionid (acctsessionid),
            KEY acctsessiontime (acctsessiontime),
            KEY acctstarttime (acctstarttime),
            KEY acctinterval (acctinterval),
            KEY acctstoptime (acctstoptime),
            KEY nasipaddress (nasipaddress)
            ) ENGINE = INNODB;"
 
        "CREATE TABLE radcheck (
            id int(11) unsigned NOT NULL auto_increment,
            username varchar(64) NOT NULL default '',
            attribute varchar(64)  NOT NULL default '',
            op char(2) NOT NULL DEFAULT '==',
            value varchar(253) NOT NULL default '',
            PRIMARY KEY  (id),
            KEY username (username(32)));"

        "CREATE TABLE radgroupcheck (
            id int(11) unsigned NOT NULL auto_increment,
            groupname varchar(64) NOT NULL default '',
            attribute varchar(64)  NOT NULL default '',
            op char(2) NOT NULL DEFAULT '==',
            value varchar(253)  NOT NULL default '',
            PRIMARY KEY  (id),
            KEY groupname (groupname(32)));"

        "CREATE TABLE radgroupreply (
            id int(11) unsigned NOT NULL auto_increment,
            groupname varchar(64) NOT NULL default '',
            attribute varchar(64)  NOT NULL default '',
            op char(2) NOT NULL DEFAULT '=',
            value varchar(253)  NOT NULL default '',
            PRIMARY KEY  (id),
            KEY groupname (groupname(32)));"

        "CREATE TABLE radreply (
            id int(11) unsigned NOT NULL auto_increment,
            username varchar(64) NOT NULL default '',
            attribute varchar(64) NOT NULL default '',
            op char(2) NOT NULL DEFAULT '=',
            value varchar(253) NOT NULL default '',
            PRIMARY KEY  (id),
            KEY username (username(32)));"

        "CREATE TABLE radusergroup (
            username varchar(64) NOT NULL default '',
            groupname varchar(64) NOT NULL default '',
            priority int(11) NOT NULL default '1',
            KEY username (username(32)));"

        "CREATE TABLE radpostauth (
            id int(11) NOT NULL auto_increment,
            username varchar(64) NOT NULL default '',
            pass varchar(64) NOT NULL default '',
            reply varchar(32) NOT NULL default '',
            authdate timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
            PRIMARY KEY  (id)
            ) ENGINE = INNODB;"

        "CREATE TABLE nas (
            id int(10) NOT NULL auto_increment,
            nasname varchar(128) NOT NULL,
            shortname varchar(32),
            type varchar(30) DEFAULT 'other',
            ports int(5),
            secret varchar(60) DEFAULT 'secret' NOT NULL,
            server varchar(64),
            community varchar(50),
            description varchar(200) DEFAULT 'RADIUS Client',
            PRIMARY KEY (id),
            KEY nasname (nasname));"

        "CREATE TABLE radippool (
            id int(11) unsigned NOT NULL auto_increment,
            pool_name varchar(30) NOT NULL,
            framedipaddress varchar(15) NOT NULL default '',
            nasipaddress varchar(15) NOT NULL default '',
            calledstationid VARCHAR(30) NOT NULL,
            callingstationid VARCHAR(30) NOT NULL,
            expiry_time DATETIME NULL default NULL,
            username varchar(64) NOT NULL default '',
            pool_key varchar(30) NOT NULL,
            PRIMARY KEY (id),
            KEY radippool_poolname_expire (pool_name, expiry_time),
            KEY framedipaddress (framedipaddress),
            KEY radippool_nasip_poolkey_ipaddress (nasipaddress, pool_key, framedipaddress)
            ) ENGINE=InnoDB;" )
    mysql -h"$1" -P"$2" -u"$3" -p"$4" -e "CREATE DATABASE $5;"
    for TB in "${TBS[@]}"; do mysql -h"$1" -P"$2" -u"$3" -p"$4" -D"$5" -e "$TB"; done; }

#环境变量未能提供配置数据时从配置文件读取
[ -z "$SRVCFG" ] && SRVCFG="$( jq -scM ".[0]|objects" "./workcfg.json" )"

#提取SQL配置参数(服务器,账号,密码,库名称),可以指示启用一个本地mysql服务
LCSQL="$( echo "$SRVCFG" | jq -r ".radius.sqlsrv|strings"   )"
DBSER="$( echo "$SRVCFG" | jq -r ".radius.sqlser|strings"   )"
DBSPT="$( echo "$SRVCFG" | jq -r ".radius.sqlport|numbers"  )"
DBUNM="$( echo "$SRVCFG" | jq -r ".radius.sqluser|strings"  )"
DBPWD="$( echo "$SRVCFG" | jq -r ".radius.sqlpwd|strings"   )"
DBSNM="$( echo "$SRVCFG" | jq -r ".radius.dbname|strings"   )"
LCNET="$( echo "$SRVCFG" | jq -r ".radius.lcnetpmt|strings" )"
LCNPW="$( echo "$SRVCFG" | jq -r ".radius.lcnetpwd|strings" )"

#参数缺省时使用默认值,使用默认sql账号时会配置默认关联密码
DBSER="${DBSER:-localhost}"
DBSPT="${DBSPT:-1811}"
DBSNM="${DBSNM:-radius}"
[ -z "$DBUNM" ] && { DBUNM="radadmin"; DBPWD="radpw000"; }

FWRLPM=( -p tcp -m tcp --dport "$DBSPT" -m conntrack --ctstate NEW -j ACCEPT )
RADDB="./raddb"

#服务环境初始化
iptables -t filter -D SRVLCH "${FWRLPM[@]}"
mkdir -p "$RADDB"
chown -R radiusd:radiusd "$RADDB"
chmod -R 644 "$RADDB"; find "$RADDB" -type d -exec chmod 744 {} \;

#启用本地sql服务时强制更改SQL服务目标到本地
[[ "$LCSQL" =~ ^"YES"|"yes"$ ]] && DBSER="localhost" && (
    iptables -t filter -A SRVLCH "${FWRLPM[@]}"
    SRVCFG="[{ \"usernm\": \"$DBUNM\", \"passwd\": \"$DBPWD\", \"dbname\": \"$DBSNM\" }]"
    SRVCFG="{ \"mariadb\": { \"srvport\": $DBSPT, \"dbauthz\": $SRVCFG }}"
    touch "$SQLEN"; SRVCFG="$SRVCFG" setsid ../mariadb/mariadbstart.sh & )

#测试SQL服务至可用时配置目标库表和MYSQL支持,无效参数最终可能导致数据库服务不可用
for ID in {1..20}; do sleep 0.5
    mysqladmin ping -h"$DBSER" -P"$DBSPT" -u"$DBUNM" -p"$DBPWD" && break
    done; RADIUS_DBTB_CREATE "$DBSER" "$DBSPT" "$DBUNM" "$DBPWD" "$DBSNM"
echo "\
server     =    \"$DBSER\"
port       =    $DBSPT
login      =    \"$DBUNM\"
password   =    \"$DBPWD\"
radius_db  =    \"$DBSNM\"" > "$RADDB/dbserinfo";

#条件配置本地网络radius授权
echo -e "#服务器本地网络(广播网络)中其它主机准入配置.\n" > "$RADDB/clients.lcnet"
[[ "$LCNET" =~ ^"YES"|"yes"$ ]] && {
    BCIFS=( $( ip link | awk '$3~/^<.*BROADCAST.*>$/{sub("[:@].*$","",$2);print $2}' ) )
    for IF in "${BCIFS[@]}"; do
    IFIP="$( ip addr show "$IF" | awk '$1=="inet"{print $2;exit}' )"
    [ -z "$IFIP" -o -z "$LCNPW" ] && continue
    echo "client localnet-$IF {
          ipaddr = $IFIP
          secret = $LCNPW
          nas_type = other
          }" >> "$RADDB/clients.lcnet"; done; }

#启动freeradius服务
exec radiusd -f -d "$RADDB" -l ./radiusd.log

#Haha, May be unnecessary.
exit 127

######################################################################################
# SQL认证检查流程
#
#   1. 从radcheck表中查找指定用户的所有属性.
#   2. 如果找到检查属性并且匹配(NAS提交的属性),从radreply表中提取回复项到用户回复属性.
#   3. 如果满足如下条件之一则执行组处理过程:
#       a. 用户未能在radcheck表中找到.
#       b. 用户在radcheck表中找到但查检属性不匹配.
#       c. 用户在radcheck表中找到且查检属性匹配,但"read_groups"指令被设置为"yes".
#   4. 如果为用户执行组处理,先从radusergroup表中提取用户所有属组并依照优先级进行排序,
#      radusergroup表中的优先级字段允许检查过程可以控制组处理顺序,因此可以模拟使用文
#      件时的顺序检查,这在有些时候是很重要的.
#   5. 对于该用户所属的每个组,将从radgroupCheck表中提取相应的检查项,并与请求进行比较,
#      如果匹配,则从radgrouppreply表中提取该组的应答项并应用到用户回复属性.
#   6. 如果组检查不匹配则进入下一组检查否则结束
#      (以上过程同使用文件认证相同)
#   7. 最后,如果用户具有"User-Profile"属性或者默认Profile选项在sql.conf中被设置,则对
#      用户Profile所属的组重复执行4-6步骤的组检查.

#属性赋值操作符
# =   仅在目标属性不存在于对应列表中时添加到属性列表,否则放弃
# :=  仅在目标属性不存在于对应列表中时添加到属性列表,否则替换原属性值
# +=  添加属性到列表尾部,若右侧表达式解析为多个值时则添加多个同名属性
#
#属性过滤操作符,仅过滤已存在的属性,不存在的属性不会被添加
# -=  删除列表中属性值等于指定值的该属性
# ==  仅保留列表中属性值等于指定值的该属性
# !=  仅保留列表中属性值不等于指定值的该属性
# <   仅保留列表中属性值小于指定值的该属性
# <=  仅保留列表中属性值小于等于指定值的该属性
# >   仅保留列表中属性值大于指定值的该属性
# >=  仅保留列表中属性值大于等于指定值的该属性
# !*  删除列表中所有该属性,例如 MS-MPPE-Send-Key !* ANY
#
#属性值说明
#     属性值可以是属性引用,引用属性必需和目标属性值类型相同
#     &Attribute 属性值引用, %{Attribute} 属性引用并转换为字符串
#     从模块输出的内容(字符串)作为赋值内容时会被解析到对应的数据类型,整形或地址类型等
#     由于协议等限制,分配到属性字符串最大长度为253,但内部处理过程中可以达到8K
#
#配置文件中定义的其它关键字
#     fail    指示: 操作失败
#     noop    指示: 未进行任何处理
#     ok      指示: 已正确处理
#     reject  指令: 请求立即被拒绝
#
#模块返回值,可参与条件运算
#     notfound  信息未找到
#     noop      未进行任何处理
#     ok        模块执行成功
#     updated   模块已更新的请求
#     fail      模块执行失败
#     reject    模块拒绝了请求
#     userlock  用户被锁定
#     invalid   配置无效
#     handled   模块已处理请求本身

