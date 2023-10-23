#!/bin/bash


# ===== global params
server_name=${0}
server_version=v1.1.0

response=
root_work_path=
docker_repo_aliyun=registry.cn-beijing.aliyuncs.com/wshuai

k8s_master_name=ws-k8s-master-01
k8s_master_addr=10.0.2.4

k8s_node_names=(ws-k8s-node-01 ws-k8s-node-02)
k8s_node_addrs=(10.100.101.51 10.100.101.52)

#k8s_harbor_name=hub.wsk8s.com
#k8s_harbor_addr=10.100.101.49

# =====================================
# k8s v1.19.0 images:

k8s_port=6443
k8s_version=1.28.0

docker_images=(
    kube-apiserver:v${k8s_version}
    kube-controller-manager:v${k8s_version}
    kube-scheduler:v${k8s_version}
    kube-proxy:v${k8s_version}
    pause:3.9
    etcd:3.5.9-0
    coredns:v1.10.1
)

images_calico=(
    calico-kube-controllers:v3.26.3
    typha:v3.26.3
    calico-node:v3.26.3
    pod2daemon-flexvol:v3.26.3
    cni:v3.26.3
    csi:v3.26.3
    node-driver-registrar:v3.26.3
)

# =====================================
