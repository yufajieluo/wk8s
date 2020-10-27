#!/bin/bash

k8s_version=v1.19.0
k8s_source_path=/workspace/source
download_url=http://45.76.247.122:9000/public/kubernetes-source-${k8s_version}.zip

k8s_pki_path=/etc/kubernetes/pki
k8s_pki_backup_path=/etc/kubernetes/pki.bak
kubeadm_conf_file=/workspace/install-k8s/core/kubeadm-config.yaml

ahead=360

check_date=
expire_date=


source ./common.sh

function get_expire_date()
{
    expire_time=`openssl x509 -in ${k8s_pki_path}"/apiserver.crt" -text -noout | grep "Not After" | awk -F ' : ' '{print $2}'`
    expire_date=`date "+%Y%m%d" -d "${expire_time}"`
    check_date=`date "-d ${ahead} days" "+%Y%m%d"`
}

function make_new_kubeadm()
{
    current_path=`pwd`

    # download
    wget ${download_url} -P ${k8s_source_path}

    mkdir -p ${k8s_source_path}
    cd ${k8s_source_path}

    # uncompress
    unzip ${download_url##*/}
    rm -f ${download_url##*/}
    
    paths=($(ls ${k8s_source_path}))
    cd ${paths[0]}
  
    # modify
    sed -i s/"time.Now().Add(kubeadmconstants.CertificateValidity).UTC()"/"time.Now().Add(kubeadmconstants.CertificateValidity * 10).UTC()"/g cmd/kubeadm/app/util/pkiutil/pki_helpers.go

    # make
    make WHAT=cmd/kubeadm GOFLAGS=-v
    cp -a _output/bin/kubeadm ${current_path}/kubeadm-${k8s_version}

    cd ${current_path}
}

function renew_cert()
{
    cp -r ${k8s_pki_path} ${k8s_pki_backup_path}
    ${current_path}"/kubeadm-"${k8s_version} alpha certs renew all --config=${kubeadm_conf_file}
}

function show_update_result()
{
    for cert_file in $(ls ${k8s_pki_path}/*.crt);
    do
        echo "===== ${cert_file} ====="
        openssl x509 -in ${cert_file} -text -noout | grep -B 1 'Not After'
    done
}

function main()
{
    get_expire_date
    if [ ${check_date} -ge ${expire_date} ];
    then
        print_color "SYSTEM" "expire date is ${expire_date}, need update cert..."
        make_new_kubeadm
        renew_cert
        get_expire_date
        show_update_result
    else
        print_color "SYSTEM" "expire date is ${expire_date}, no need update cert."
    fi
}

main
[root@ws-k8s-master-01 ~]# ^C
[root@ws-k8s-master-01 ~]# vim t.sh 
/[root@ws-k8s-master-01 ~]# cat t.sh 
#!/bin/bash

k8s_version=v1.19.0
k8s_source_path=/workspace/source
download_url=http://45.76.247.122:9000/public/kubernetes-source-${k8s_version}.zip

k8s_pki_path=/etc/kubernetes/pki
k8s_pki_backup_path=/etc/kubernetes/pki.bak
kubeadm_conf_file=/workspace/install-k8s/core/kubeadm-config.yaml

ahead=360

check_date=
expire_date=


source ./common.sh

function get_expire_date()
{
    expire_time=`openssl x509 -in ${k8s_pki_path}"/apiserver.crt" -text -noout | grep "Not After" | awk -F ' : ' '{print $2}'`
    expire_date=`date "+%Y%m%d" -d "${expire_time}"`
    check_date=`date "-d ${ahead} days" "+%Y%m%d"`
}

function make_new_kubeadm()
{
    current_path=`pwd`

    # download
    wget ${download_url} -P ${k8s_source_path}

    mkdir -p ${k8s_source_path}
    cd ${k8s_source_path}

    # uncompress
    unzip ${download_url##*/}
    rm -f ${download_url##*/}
    
    paths=($(ls ${k8s_source_path}))
    cd ${paths[0]}
  
    # modify
    sed -i s/"time.Now().Add(kubeadmconstants.CertificateValidity).UTC()"/"time.Now().Add(kubeadmconstants.CertificateValidity * 10).UTC()"/g cmd/kubeadm/app/util/pkiutil/pki_helpers.go

    # make
    make WHAT=cmd/kubeadm GOFLAGS=-v
    cp -a _output/bin/kubeadm ${current_path}/kubeadm-${k8s_version}

    cd ${current_path}
}

function renew_cert()
{
    cp -r ${k8s_pki_path} ${k8s_pki_backup_path}
    ${current_path}"/kubeadm-"${k8s_version} alpha certs renew all --config=${kubeadm_conf_file}
}

function show_update_result()
{
    for cert_file in $(ls ${k8s_pki_path}/*.crt);
    do
        echo "===== ${cert_file} ====="
        openssl x509 -in ${cert_file} -text -noout | grep -B 1 'Not After'
    done
}

function main()
{
    get_expire_date
    if [ ${check_date} -ge ${expire_date} ];
    then
        print_color "SYSTEM" "expire date is ${expire_date}, need update cert..."
        make_new_kubeadm
        renew_cert
        get_expire_date
        show_update_result
    else
        print_color "SYSTEM" "expire date is ${expire_date}, no need update cert."
    fi
}

main
