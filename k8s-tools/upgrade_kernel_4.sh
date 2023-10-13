#!/bin/bash

function upgrade_kernel_4()
{
    rpm -Uvh http://www.elrepo.org/elrepo-release-7.0-3.el7.elrepo.noarch.rpm
    yum --enablerepo=elrepo-kernel install -y kernel-lt
    grub2-set-default "CentOS Linux (4.4.182-1.el7.elrepo.x86_64) 7 (Core)"
}

upgrade_kernel_4

echo "需要手动 reboot"
