#!/bin/bash

function print_color()
{
    if [ ${1} == "ERROR" ];
    then
        color="31m"
    elif [ ${1} == "SUCCESS" ];
    then
        color="32m"
    elif [ ${1} == "WARNING" ];
    then
        color="33m"
    elif [ ${1} == "SYSTEM" ];
    then
        color="34m"
    else
        color="0m"
    fi
    echo -e "\033[${color}${2}\033[0m"
}

function verify()
{
    eval ${2}
    ret=${?}
    if [ ${ret} -eq 0 ];
    then
        print_color "SUCCESS" "[${1}]环境已准备好."
    else
        print_color "SYSTEM" "[${1}]环境未准备好，请先安装[${1}]."
    fi
    return ${ret}
}

function prepare_path()
{
    if [ ! -d ${1} ];
    then
        mkdir -p ${1}
        chmod 755 ${1}
    fi
    print_color "SYSTEM" "目录[${1}]已准备好."
}

function funcs_handler()
{
    funcs=${1}

    for func in ${funcs[@]}
    do
        ${i}
        if [ $? != 0 ];
        then
            print_color "ERROR" "${func} failed, exit."
            return 1
        fi
    done
}

