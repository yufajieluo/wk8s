#!/bin/bash

# local addr
HARBOR_ADDR=

# loadbalance addr
LB_ADDR=https://

# external redis
EXTERNAL_REDIS_HOST=
EXTERNAL_REDIS_PORT=6379
EXTERNAL_REDIS_PASS=

# external postgres
EXTERNAL_DB_HOST=
EXTERNAL_DB_POST=5432
EXTERNAL_DB_HARBOR_NAME=registry
EXTERNAL_DB_HARBOR_USER=registry
EXTERNAL_DB_HARBOR_PASS=registry
EXTERNAL_DB_SIGNER_NAME=notarysigner
EXTERNAL_DB_SIGNER_USER=notarysigner
EXTERNAL_DB_SIGNER_PASS=notarysigner
EXTERNAL_DB_SERVER_NAME=notaryserver
EXTERNAL_DB_SERVER_USER=notaryserver
EXTERNAL_DB_SERVER_PASS=notaryserver

# local storage
HARBOR_VOLUME=

# local work path
WORK_PATH=

# harbor version
HARBOR_VERSION=v2.3.0
DOWNLOAD_URL=https://github.com/goharbor/harbor/releases/download/${HARBOR_VERSION}/harbor-offline-installer-${HARBOR_VERSION}.tgz

function install()
{
    wget ${DOWNLOAD_URL} -P ${WORK_PATH}

    cd ${WORK_PATH}

    tar -zxf ${DOWNLOAD_URL##*/}
    rm -f ${DOWNLOAD_URL##*/}

    cp harbor/harbor.yml.tmpl harbor/harbor.yml

    sed -i "s/hostname: reg.mydomain.com/hostname: ${HARBOR_ADDR}/g" harbor/harbor.yml
    sed -i "s/^https:.*/#https:/g" harbor/harbor.yml
    sed -i "s/^  port: 443/# port: 443/g" harbor/harbor.yml
    sed -i "s/^  certificate/# certificate/g" harbor/harbor.yml
    sed -i "s/^  private_key/# private_key/g" harbor/harbor.yml

    replace_str=`echo ${LB_ADDR} | sed 's#\/#\\\/#g'`
    sed -i "s/^\# external_url.*/external_url: ${replace_str}/g" harbor/harbor.yml

    replace_str=`echo ${HARBOR_VOLUME} | sed 's#\/#\\\/#g'`
    sed -i "s/^data_volume.*/data_volume: ${replace_str}/g" harbor/harbor.yml

    cat >> harbor/harbor.yml << EOF
# external_database
external_database:
  harbor:
    host: ${EXTERNAL_DB_HOST}
    port: ${EXTERNAL_DB_PORT}
    db_name: ${EXTERNAL_DB_HARBOR_NAME}
    username: ${EXTERNAL_DB_HARBOR_USER}
    password: ${EXTERNAL_DB_HARBOR_PASS}
    ssl_mode: disable
    max_idle_conns: 2
    max_open_conns: 0
  notary_signer:
    host: ${EXTERNAL_DB_HOST}
    port: ${EXTERNAL_DB_PORT}
    db_name: ${EXTERNAL_DB_SIGNER_NAME}
    username: ${EXTERNAL_DB_SIGNER_USER}
    password: ${EXTERNAL_DB_SIGNER_PASS}
    ssl_mode: disable
  notary_server:
    host: ${EXTERNAL_DB_HOST}
    port: ${EXTERNAL_DB_PORT}
    db_name: ${EXTERNAL_DB_SERVER_NAME}
    username: ${EXTERNAL_DB_SERVER_USER}
    password: ${EXTERNAL_DB_SERVER_PASS}
    ssl_mode: disable

# external_redis
external_redis:
  host: ${EXTERNAL_REDIS_HOST}:${EXTERNAL_REDIS_PORT}
  password: ${EXTERNAL_REDIS_PASS}
  registry_db_index: 1
  jobservice_db_index: 2
  chartmuseum_db_index: 3
  trivy_db_index: 5
  idle_timeout_seconds: 30
EOF

   cd -
}

function startup()
{
    ${WORK_PATH}"/harbor/prepare"
    ${WORK_PATH}"/harbor/install.sh"
}

install
startup
