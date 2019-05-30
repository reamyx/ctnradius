#官方centos7镜像初始化,镜像TAG: ctnradius

FROM        imginit
LABEL       function="ctnradius"

#添加本地资源
ADD     freeradius     /srv/freeradius/
ADD     mariadb        /srv/mariadb/

WORKDIR /srv/freeradius

#功能软件包
RUN     set -x \
        && cd ../imginit \
        \
        && yum -y install freeradius freeradius-utils freeradius-mysql \
                  freeradius-sqlite mariadb mariadb-server \
        \
        && yum clean all \
        && rm -rf /tmp/* \
        && cat ../mariadb/my-clt.cnf > /etc/my.cnf \
        && find ../ -name "*.sh" -exec chmod +x {} \;

ENV       ZXDK_THIS_IMG_NAME    "ctnradius"
ENV       SRVNAME               "freeradius"

# ENTRYPOINT CMD
CMD [ "../imginit/initstart.sh" ]
