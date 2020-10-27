#!/bin/bash

source ./common.sh

# ===== global params
server_name=${0}
server_version=v1.1.0

response=
root_work_path=
docker_repo_aliyun=registry.cn-beijing.aliyuncs.com/wshuai
package_repo_custom=http://45.76.247.122:9000/public

k8s_master_name=ws-k8s-master-01
k8s_master_addr=10.100.101.50

k8s_node_names=(ws-k8s-node-01 ws-k8s-node-02)
k8s_node_addrs=(10.100.101.51 10.100.101.52)

k8s_harbor_name=hub.wsk8s.com
k8s_harbor_addr=10.100.101.49

# =====================================
# k8s v1.19.0 images:

k8s_port=6443
k8s_version=1.19.0

docker_images=(
    kube-apiserver:v1.19.0
    kube-controller-manager:v1.19.0
    kube-scheduler:v1.19.0
    kube-proxy:v1.19.0
    pause:3.2
    etcd:3.4.9-1
    coredns:1.7.0
)
# =====================================

function check_system()
{
    system=`cat /etc/redhat-release | awk '{print $1}'`
    if [ "${system}" == "CentOS" ];
    then
        version=`cat /etc/redhat-release | awk '{print $4}'`
        if [ "${version:0:1}" == "7" ];
        then
            print_color "SYSTEM" "该系统为 [${system}], 版本为 [${version}]"
            print_color "SYSTEM" "系统匹配, 版本匹配, 适用此脚本"
            return 0
        else
            print_color "ERROR" "该系统为 [${system}] : [${version}]"
            print_color "ERROR" "系统匹配, 版本不匹配, 不适用此脚本"
            return 1
        fi

    else
        print_color "ERROR" "该系统不是CentOS，不适用此脚本"
        return 1
    fi
}

function configure_hostname()
{
    host_file=/etc/hosts

    echo ${k8s_master_addr} ${k8s_master_name} >> ${host_file}
    for i in ${!k8s_node_names[@]};
    do
        echo ${k8s_node_addrs[${i}]} ${k8s_node_names[${i}]} >> ${host_file}
    done
    echo ${k8s_harbor_addr} ${k8s_harbor_name} >> ${host_file}
}

function prepare_dependent()
{
    yum install -y conntrack ntpdate ntp ipvsadm ipset iptables curl sysstat libseccomp wget vim net-tools git
}

function set_timezone()
{
    timedatectl set-timezone Asia/Shanghai
    timedatectl set-local-rtc 0
    systemctl restart rsyslog
    systemctl restart crond
}

function stop_swap()
{
    swapoff -a
    sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab
}

function stop_selinux()
{
    setenforce 0
    sed -i 's/^SELINUX=.*/SELINUX=disabled/g' /etc/selinux/config
}

function stop_firewall()
{
    systemctl stop firewalld.service
    systemctl disable firewalld.service

    yum install -y iptables-services
    systemctl start iptables
    systemctl enable iptables
    iptables -F
    service iptables save
}

function configure_k8s()
{
    k8s_conf_file=/etc/sysctl.d/kubernetes.conf

    cat > ${k8s_conf_file} <<EOF
net.bridge.bridge-nf-call-iptables=1
net.bridge.bridge-nf-call-ip6tables=1
net.ipv4.ip_forward=1
net.ipv4.tcp_tw_recycle=0
vm.swappiness=0 # 禁用swap空间
vm.overcommit_memory=1 # 不检查物理内存是否够用
vm.panic_on_oom=0 # 开启oom
fs.inotify.max_user_instances=8192
fs.inotify.max_user_watches=1048576
fs.file-max=52706963
fs.nr_open=52706963
net.ipv6.conf.all.disable_ipv6=1
net.netfilter.nf_conntrack_max=2310720
EOF

    modprobe br_netfilter
    sysctl -p ${k8s_conf_file}
}

function configure_journal()
{   
    mkdir -p /var/log/journal
    mkdir -p /etc/systemd/journal.conf.d
    cat > /etc/systemd/journal.conf.d/99-prophet.conf <<EOF
[Journal]
# 持久化保存到磁盘
Storage=persistent

# 压缩历史日志
Compress=yes

SyncIntervalSec=5m
RateLimitInterval=30s
RateLimitBurst=1000

# 最大占用空间
SystemMaxUse=10G

# 单日志文件最大
SystemMaxFileSize=200M

# 日志保存时间
MaxRetentionSec=2week

# 不将日志转发到 syslog
ForwardToSyslog=no
EOF
    
    systemctl restart systemd-journald
}

function configure_ipvs()
{
    ipvs_file=/etc/sysconfig/modules/ipvs.modules

    modprobe br_netfilter

cat > ${ipvs_file} <<EOF
#!/bin/bash
modprobe -- ip_vs
modprobe -- ip_vs_rr
modprobe -- ip_vs_wrr
modprobe -- ip_vs_sh
modprobe -- nf_conntrack_ipv4
EOF

    chmod 755 ${ipvs_file}
    bash ${ipvs_file}
    #lsmod | grep -e ip_vs -e nf_conntrack_ipv4
}

function install_docker()
{
    docker_lib_path=${root_work_path}/lib/docker

    yum install -y yum-utils device-mapper-persistent-data lvm2
    yum-config-manager --add-repo https://mirrors.aliyun.com/docker-ce/linux/centos/docker-ce.repo
    yum update -y
    yum install -y docker-ce

    mkdir /etc/docker

    cat > /etc/docker/daemon.json <<EOF
{
    "exec-opts": ["native.cgroupdriver=systemd"],
    "log-driver": "json-file",
    "log-opts": {
        "max-size": "100m"
    },
    "insecure-registries": ["https://${k8s_harbor_name}"]
}
EOF

    mkdir -p /etc/systemd/system/docker.service.d

    mkdir -p ${docker_lib_path}
    sed -i "/^ExecStart/s/$/& --graph ${docker_lib_path//\//\\/}/g" /usr/lib/systemd/system/docker.service

    systemctl daemon-reload
    systemctl restart docker
    systemctl enable docker
}

function install_kubeadm()
{
    cat > /etc/yum.repos.d/kubernetes.repo <<EOF
[kubernetes]
name=Kubernetes
baseurl=http://mirrors.aliyun.com/kubernetes/yum/repos/kubernetes-el7-x86_64
enabled=1
gpgcheck=0
repo_gpgcheck=0
gpgkey=http://mirrors.aliyun.com/kubernetes/yum/doc/yum-key.gpg
       http://mirrors.aliyun.com/kubernetes/yum/doc/rpm-package-key.gpg
EOF

    yum install -y kubeadm-${k8s_version} kubectl-${k8s_version} kubelet-${k8s_version}
    systemctl enable kubelet.service
}

function pull_kubeadm_images()
{
    docker_repo_k8s=k8s.gcr.io

    for image in ${docker_images[@]}
    do
        docker pull ${docker_repo_aliyun}/${image}
        docker tag ${docker_repo_aliyun}/${image} ${docker_repo_k8s}/${image}
        docker rmi ${docker_repo_aliyun}/${image}
    done
}

function init_k8s_master()
{
    mkdir -p ${root_work_path}/install-k8s/core
    
    kubeadm_conf_file=${root_work_path}/install-k8s/core/kubeadm-config.yaml
    kubeadm_log_file=${root_work_path}/install-k8s/core/kubeadm-init.log

    kubeadm config print init-defaults > ${kubeadm_conf_file}
    sed -i "s/1.2.3.4/${k8s_master_addr}/g" ${kubeadm_conf_file}
    sed -i "/dnsDomain/a\  podSubnet: \"10.244.0.0\/16\"" ${kubeadm_conf_file}
    cat >> ${kubeadm_conf_file} <<EOF
---
apiVersion: kubeproxy.config.k8s.io/v1alpha1
kind: KubeProxyConfiguration
featureGates:
  SupportIPVSProxyMode: true
mode: ipvs
EOF

    kubeadm init --config=${kubeadm_conf_file} --upload-certs | tee ${kubeadm_log_file}
    response=`tail -2 ${kubeadm_log_file}`
    response=${response/\\/}

    mkdir -p $HOME/.kube
    cp -f /etc/kubernetes/admin.conf $HOME/.kube/config
    chown $(id -u):$(id -g) $HOME/.kube/config
}

function install_flannel()
{
    
    flannel_yaml_path=${root_work_path}/install-k8s/plugin/flannel
    flannel_yaml_file=${package_repo_custom}/kube-flannel.yml
    
    mkdir -p ${flannel_yaml_path}
    wget ${flannel_yaml_file} -P ${flannel_yaml_path}

    kubectl create -f ${flannel_yaml_path}/${flannel_yaml_file##*/}
}

function join_k8s()
{
    kubeadm join ${k8s_master_addr}:${k8s_port} --token ${token} --discovery-token-ca-cert-hash ${hash}
    ret=$?
    if [ ${ret} == 0 ];
    then
        response="join ${k8s_master_addr}:${k8s_port} success."
    fi
    return ${ret}
}

function print_rsponse()
{
    print_color "SUCCESS" "${response}"
}

function common_install()
{
    func_list=(
        configure_hostname
        prepare_dependent
        set_timezone
        stop_swap
        stop_selinux
        stop_firewall
        configure_k8s
        configure_journal
        configure_ipvs
        install_docker
        install_kubeadm
        pull_kubeadm_images
    )
    funcs_handler "${func_list[*]}"
    return $?
}

function master_install()
{
    func_list=(
        init_k8s_master
        install_flannel
        # install dashboard
    )
    funcs_handler "${func_list[*]}"
    return $?
}

function node_install()
{
    func_list=(
        join_k8s
    )
    funcs_handler "${func_list[*]}"
    return $?
}


#===================================================

function help()
{
    print_color "SYSTEM"  "Usage:"
    print_color "SYSTEM"  "  ${server_name} [OPTION]"
    print_color "SYSTEM"  ""
    print_color "SYSTEM"  "Available OPTION:"
    print_color "SYSTEM"  "  --type         必选，master; node"
    print_color "SYSTEM"  "  --path         必选，执行安装操作的工作目录，用于存放一些重要的安装临时文件"
    print_color "SYSTEM"  "  --token        可选，type为node时使用"
    print_color "SYSTEM"  "  --hash         可选，type为node时使用"
    print_color "SYSTEM"  "  --join         可选，type为node时使用"
    print_color "SYSTEM"  "  --dashboard    可选，安装dashboard"
    print_color "SYSTEM"  ""
    print_color "SYSTEM"  "  --help         display this help and exit"
    print_color "SYSTEM"  "  --version      output version information and exit"
    print_color "SYSTEM"  ""
    print_color "SYSTEM"  "Example:"
    print_color "SYSTEM"  "  master 节点安装使用如下命令:"
    print_color "SYSTEM"  "    ${server_name} --type master --path YOUR_WORK_PATH"
    print_color "SYSTEM"  "  node 节点安装使用如下命令:"
    print_color "SYSTEM"  "    ${server_name} --type node --path YOUR_WORK_PATH --token JOIN_MASTER_TOKEN --hash JOIN_MASTER_HASH"
    print_color "SYSTEM"  "  node 节点只Join (此情况用于Node节点安装成功，但由于超过24小时token和hash失效时，重新只做Join动作):"
    print_color "SYSTEM"  "    ${server_name} --type node --join --token JOIN_MASTER_TOKEN --hash JOIN_MASTER_HASH"
    print_color "SYSTEM"  ""
    print_color "WARNING" "Warning:"
    print_color "WARNING" "  1. 建议安装 Kubernetes 之前，先把系统内核升级到4.4以上，内核3.x会引发不稳定"
    print_color "WARNING" "     可使用 upgrade_kernel_4.sh 脚本进行升级内核"
    print_color "WARNING" "  2. 此脚本目前只适用于 Centos7 系统"
    print_color "WARNING" "  3. 此脚本安装的 Kubernetes 版本为 v1.19.0"
}

function version()
{
    print_color "SYSTEM" "${server_name} ${server_version}"
}

function funcs_handler()
{
    funcs=${1}

    for func in ${funcs[@]}
    do
        ${func}
        if [ $? != 0 ];
        then
            print_color "ERROR" "${func} failed, exit."
            return 1
        fi
    done
}

#===================================================


ARGS=`getopt -o t:,b: --long help,version,dashboard,join,type:,path:,token:,hash: -- "$@"`
if [ $# == 0 ];
then
    help
    print_color "SYSTEM" ""
    print_color "SYSTEM" "Terminating..." >&2
    exit 1
fi

if [ $? != 0 ];
then
    print_color "SYSTEM" "Terminating..." >&2
    exit 1
fi

eval set -- "$ARGS"

type=
join=false
token=
hash=

while true
do
    case "$1" in
        --help)
            help
            break
            ;;
        --version)
            version
            break
            ;;
        --type)
            type=$2
            shift 2
            ;;
        --path)
            root_work_path=$2
            if [ ${root_work_path: -1} == '/' ];
            then
                root_work_path=${root_work_path%?}
            fi
            shift 2
            ;;
        --join)
            join=true
            shift 1
            ;;
        --token)
            token=$2
            shift 2
            ;;
        --hash)
            hash=$2
            shift 2
            ;;
        --dashboard)
            dashboard=1
            shift 1
            ;;
        --)
            shift
            break
            ;;
    esac
done

case ${type} in
    master)
        if [ -z ${root_work_path} ];
        then
            print_color "ERROR" "path must be not empty."
        else
            func_list=(
                check_system
                common_install
                master_install
                print_rsponse
            )
            funcs_handler "${func_list[*]}"
        fi
        break
        ;;
    node)
        if [ ${join} == true ];
        then
            if [ -z ${token} ] || [ -z ${hash} ];
            then
                print_color "ERROR" "token and hash must be not empty."
            else
                func_list=(
                    node_install
                )
                funcs_handler "${func_list[*]}"
            fi
        else
            if [ -z ${root_work_path} ] || [ -z ${token} ] || [ -z ${hash} ];
            then
                print_color "ERROR" "path、token and hash must be not empty."
            else
                func_list=(
                    check_system
                    common_install
                    node_install
                    print_rsponse
                )
                funcs_handler "${func_list[*]}"
            fi
        fi
        break
        ;;
    *)
        print_color "ERROR" "type must by master or node."
        break
        ;;
esac
