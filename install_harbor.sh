#!/bin/bash

download_url=https://github.com/goharbor/harbor/releases/download/v2.1.0/harbor-offline-installer-v2.1.0.tgz
work_path=/workspace

harbor_hostname=hub.wsk8s.com
harbor_file=${work_path}"/harbor/opt/harbor/harbor.yml"
cert_file="\/workspace\/harbor\/cert\/server.crt"
key_file="\/workspace\/harbor\/cert\/server.key"


function install()
{
    wget ${download_url} -P ${work_path}
    cd ${work_path}
    
    mkdir -p ${work_path}"/harbor/opt"
    tar -zxvf ${download_url##*/} -C ${work_path}"/harbor/opt"
    rm -f ${download_url##*/}
    
    #######################################################################################
    #
    # 提前准备证书 
    #
    # mkdir -p ${work_path}/harbor/cert
    # cd ${work_path}/harbor/cert
    # 
    # openssl genrsa -des3 -out server.key 2048
    # openssl req -new -key server.key -out server.csr
    # cp server.key server.key.bak
    # openssl rsa -in server.key.bak -out server.key
    # openssl x509 -req -days 365 -in server.csr -signkey server.key -out server.crt 
    #
    #######################################################################################
    
    
    cp ${harbor_file}.tmpl ${harbor_file}
    sed -i "s/reg.mydomain.com/${harbor_hostname}/g" ${harbor_file}
    sed -i "s/\/your\/certificate\/path/${cert_file}/g" ${harbor_file}
    sed -i "s/\/your\/private\/key\/path/${key_file}/g" ${harbor_file}
    
    ${work_path}"/harbor/opt/harbor/prepare"
    ${work_path}"/harbor/opt/harbor/install.sh"
}

install
