#!/bin/bash
# 1、先做免密登录
# 2、自动关闭firewall防火墙
# 3、自动关闭selinux
# 4、自动禁用swap分区
# 5、服务器需能ping通baidu.com

#当前安装目录
install_dir=`pwd`

#安装用户，建议使用root用户
user=root
#ssh的端口，默认22端口
ssh_port=22
#master节点主机名
master="master"
#node1节点主机名
node1="node1"
#node2节点主机名
node2="node2"

#master节点IP
masterIP="192.168.134.130"
#node1节点IP
node1IP="192.168.134.131"
#node2节点IP
node2IP="192.168.134.132"

function usage() {
    local name
    name="$(basename $0)"
    cat << EOF
Usage: bash ${name} [command]
Commands:
    deploy  部署k8s
    remove  卸载k8s,永久删除k8s组件和数据，请谨慎使用！
    status  查看k8s部署状态
Options:
    -h    Display help message
EOF
}

#检查是否做了免密登录
function environment-check() {
if [ -f ~/.ssh/id_rsa.pub ]
then
  grep "${node1IP}" ~/.ssh/known_hosts &>/dev/null
  if [ $? = 1 ]
  then
    echo "ssh ${user}@${node1IP}失败，没有做免密登录，请做免密登录，然后ssh ${user}@${node1IP}"
    exit 1
  fi
  grep "${node2IP}" ~/.ssh/known_hosts &>/dev/null
  if [ $? = 1 ]
  then
    echo "ssh ${user}@${node2IP}失败，没有做免密登录，请做免密登录，然后ssh ${user}@${node2IP}"
    exit 1
  fi
fi
}

function kernel-check() {
echo "${master}节点内核检查"
if [ $(uname -r| awk -F . '{print $1}') -le "4"  ];then echo "当前内核是$(uname -r),符合先决条件，安装继续" ;
else echo "当前${master}节点内核是$(uname -r),不符合先决条件，安装退出"; exit 1;
fi
}
function environment-init() {
echo "" 
echo "更改默认的centos官网yun源为阿里云yum源"
mkdir -p ${install_dir}/packages/{tools,docker}
yum install -y wget deltarpm --downloadonly --downloaddir=${install_dir}/packages/tools/
yum install -y ${install_dir}/packages/tools/wget*.rpm  ${install_dir}/packages/tools/deltarpm*.rpm 

cd /etc/yum.repos.d/ 
mkdir bak 
mv *.repo bak/
touch CentOS-Base.repo
cat > CentOS-Base.repo <<'EOF'
[base]
name=CentOS-$releasever - Base - mirrors.aliyun.com
failovermethod=priority
baseurl=http://mirrors.aliyun.com/centos/$releasever/os/$basearch/
gpgcheck=1
gpgkey=http://mirrors.aliyun.com/centos/RPM-GPG-KEY-CentOS-7
 
#released updates 
[updates]
name=CentOS-$releasever - Updates - mirrors.aliyun.com
failovermethod=priority
baseurl=http://mirrors.aliyun.com/centos/$releasever/updates/$basearch/
gpgcheck=1
gpgkey=http://mirrors.aliyun.com/centos/RPM-GPG-KEY-CentOS-7
 
#additional packages that may be useful
[extras]
name=CentOS-$releasever - Extras - mirrors.aliyun.com
failovermethod=priority
baseurl=http://mirrors.aliyun.com/centos/$releasever/extras/$basearch/
gpgcheck=1
gpgkey=http://mirrors.aliyun.com/centos/RPM-GPG-KEY-CentOS-7
EOF

wget -O /etc/yum.repos.d/epel.repo http://mirrors.aliyun.com/repo/epel-7.repo
yum clean all && yum makecache
echo ""
echo "传输yum源到其它节点"
ssh -p ${ssh_port} ${user}@${node1} "mkdir /etc/yum.repos.d/bak;mv /etc/yum.repos.d/*.repo /etc/yum.repos.d/bak/"
scp -P ${ssh_port} /etc/yum.repos.d/*.repo ${user}@${node1}:/etc/yum.repos.d/
ssh -p ${ssh_port} ${user}@${node2} "mkdir /etc/yum.repos.d/bak;mv /etc/yum.repos.d/*.repo /etc/yum.repos.d/bak/"
scp -P ${ssh_port} /etc/yum.repos.d/*.repo ${user}@${node2}:/etc/yum.repos.d/
ssh -p ${ssh_port} ${user}@${node1} 'yum clean all && yum makecache'
ssh -p ${ssh_port} ${user}@${node2} 'yum clean all && yum makecache'
echo ""
echo "${master}节点安装一些常用的软件"
yum install -y lsof net-tools tree gcc make zip unzip vim bash-completion curl pciutils --downloadonly --downloaddir=${install_dir}/packages/tools/
yum install -y ${install_dir}/packages/tools/*.rpm
echo ""
echo "${node1}节点安装一些常用的软件"
#传输包到node1节点
scp -P ${ssh_port} ${install_dir}/packages/tools/* ${user}@${node1}:~
ssh -p ${ssh_port} ${user}@${node1} 'yum install -y ~/*.rpm'
ssh -p ${ssh_port} ${user}@${node1} 'rm -rf ~/*.rpm'
echo ""
echo "${node2}节点安装一些常用的软件"
#传输包到node2节点
scp -P ${ssh_port} ${install_dir}/packages/tools/* ${user}@${node2}:~
ssh -p ${ssh_port} ${user}@${node2} 'yum install -y ~/*.rpm'
ssh -p ${ssh_port} ${user}@${node2} 'rm -rf ~/*.rpm'

echo ""
echo "关闭和禁用master节点防火墙"
systemctl stop firewalld.service; systemctl disable firewalld.service
echo "关闭和禁用${node1}节点防火墙"
ssh -p ${ssh_port} ${user}@${node1} "systemctl stop firewalld.service ; systemctl disable firewalld.service"
echo "关闭和禁用${node2}节点防火墙"
ssh -p ${ssh_port} ${user}@${node2} "systemctl stop firewalld.service ; systemctl disable firewalld.service"
echo ""
echo "关闭和禁用${master}节点NetworkManager服务"
systemctl stop NetworkManager.service; systemctl disable NetworkManager.service
echo "关闭和禁用${node1}节点NetworkManager服务"
ssh -p ${ssh_port} ${user}@${node1} "systemctl stop NetworkManager.service ; systemctl disable NetworkManager.service"
echo "关闭和禁用${node2}节点NetworkManager服务"
ssh -p ${ssh_port} ${user}@${node2} "systemctl stop NetworkManager.service ; systemctl disable NetworkManager.service"
echo ""
echo "关闭和永久禁用${master}节点selinux"
setenforce 0 ; sed -ri 's/SELINUX=enforcing/SELINUX=disabled/g' /etc/selinux/config 
echo "关闭和永久禁用${node1}节点selinux"
ssh -p ${ssh_port} ${user}@${node1} "setenforce 0 ; sed -ri 's/SELINUX=enforcing/SELINUX=disabled/g' /etc/selinux/config;"
echo "关闭和永久禁用${node2}节点selinux"
ssh -p ${ssh_port} ${user}@${node2} "setenforce 0 ; sed -ri 's/SELINUX=enforcing/SELINUX=disabled/g' /etc/selinux/config;"
echo ""
echo "关闭和禁用${master}节点swap分区"
swapoff -a ; sed -ri 's/.*swap.*/#&/' /etc/fstab
echo "关闭和禁用${node1}节点swap分区"
ssh -p ${ssh_port} ${user}@${node1} "swapoff -a ; sed -ri 's/.*swap.*/#&/' /etc/fstab;"
echo "关闭和禁用${node2}节点swap分区"
ssh -p ${ssh_port} ${user}@${node2} "swapoff -a ; sed -ri 's/.*swap.*/#&/' /etc/fstab;"
echo ""
echo "${master}节点安装ntpd服务"
yum -y install ntp; systemctl  start ntpd; systemctl enable ntpd
echo "${node1}节点安装ntpd服务"
ssh -p ${ssh_port} ${user}@${node1} "yum -y install ntp; systemctl  start ntpd ; systemctl enable ntpd"
echo "${node2}节点安装ntpd服务"
ssh -p ${ssh_port} ${user}@${node2} "yum -y install ntp; systemctl  start ntpd ; systemctl enable ntpd"
echo ""
echo "创建/etc/sysctl.d/kubernetes.conf文件"
touch /etc/sysctl.d/kubernetes.conf
cat > /etc/sysctl.d/kubernetes.conf <<'EOF'
net.bridge.bridge-nf-call-ip6tables=1
net.bridge.bridge-nf-call-iptables=1
net.ipv4.ip_forward=1
vm.swappiness=0
EOF
echo ""
echo "${master}节点执行sysctl --system使/etc/sysctl.d/kubernetes.conf配置文件生效"
sysctl --system
echo ""
echo "将${master}节点的/etc/sysctl.d/kubernetes.conf文件分发到${node1}节点"
scp -P ${ssh_port} /etc/sysctl.d/kubernetes.conf ${user}@${node1}:/etc/sysctl.d/
echo "${node1}节点执行sysctl --system使/etc/sysctl.d/kubernetes.conf配置文件生效"
ssh -p ${ssh_port} ${user}@${node1}  "sysctl --system"
echo ""
echo "将${master}节点的/etc/sysctl.d/kubernetes.conf文件分发到${node2}节点"
scp -P ${ssh_port} /etc/sysctl.d/kubernetes.conf ${user}@${node2}:/etc/sysctl.d/
echo "${node2}节点执行sysctl --system使/etc/sysctl.d/kubernetes.conf配置文件生效"
ssh -p ${ssh_port} ${user}@${node2}  "sysctl --system"
}

function deploy-docker() {
echo
echo "${master}节点开始安装docker-ce-20.10.9"
yum remove -y docker \
	docker-ce \
	docker-ce-cli \
	docker-ce-rootless-extras \
	docker-scan-plugin \
	docker-client \
	docker-client-latest \
	docker-common \
	docker-latest \
	docker-latest-logrotate \
	docker-logrotate \
	docker-engine \
	containerd.io
yum install -y yum-utils
yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo

yum install -y docker-ce-20.10.9 docker-ce-cli-20.10.9 containerd.io-1.6.20 --downloadonly --downloaddir=${install_dir}/packages/docker/
yum install -y ${install_dir}/packages/docker/*.rpm

systemctl enable docker
systemctl start docker
mkdir /etc/docker/
echo ""
echo "${master}节点创建/etc/docker/daemon.json文件"
touch /etc/docker/daemon.json 
cat > /etc/docker/daemon.json <<EOF
{
    "registry-mirrors": ["https://b9pmyelo.mirror.aliyuncs.com"],
    "exec-opts": ["native.cgroupdriver=systemd"]
}
EOF
systemctl restart docker
echo ""
echo "查看${master}节点的docker状态"
systemctl status docker
echo ""
echo "等待6秒后判断docker状态是否处于running"
sleep 6
status=$(systemctl  status docker | grep -i running| awk '{print $3}' | awk -F'(' '{print $2}' | awk -F')' '{print $1}')
if [ $status != 'running' ]
then
echo "docker状态未处于running状态，尝试重启docker"
systemctl restart docker
fi
echo ""
echo "${node1}安装docker-ce-20.10.9"
ssh -p ${ssh_port} ${user}@${node1} "yum remove -y docker docker-ce docker-ce-cli docker-ce-rootless-extras docker-scan-plugin docker-client docker-client-latest docker-common docker-latest docker-latest-logrotate docker-logrotate docker-engine"
ssh -p ${ssh_port} ${user}@${node1} "yum install -y yum-utils"
ssh -p ${ssh_port} ${user}@${node1} "yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo"
#复制master节点上下载的docker包到node1节点 
scp -P ${ssh_port} ${install_dir}/packages/docker/* ${user}@${node1}:~
ssh -p ${ssh_port} ${user}@${node1} 'yum -y install ~/*.rpm'
ssh -p ${ssh_port} ${user}@${node1} "systemctl enable docker;systemctl start docker"
ssh -p ${ssh_port} ${user}@${node1} "mkdir /etc/docker/"
scp -P ${ssh_port} /etc/docker/daemon.json ${user}@${node1}:/etc/docker/
ssh -p ${ssh_port} ${user}@${node1} "systemctl restart docker"
ssh -p ${ssh_port} ${user}@${node1} 'rm -rf ~/*.rpm'
echo ""
echo "查看${node1}节点的docker状态"
ssh -p ${ssh_port} ${user}@${node1} "systemctl status docker"

echo ""
echo "${node2}安装docker-ce-20.10.9"
ssh -p ${ssh_port} ${user}@${node2} "yum remove -y docker docker-ce docker-ce-cli docker-ce-rootless-extras docker-scan-plugin docker-client docker-client-latest docker-common docker-latest docker-latest-logrotate docker-logrotate docker-engine"
ssh -p ${ssh_port} ${user}@${node2} "yum install -y yum-utils"
ssh -p ${ssh_port} ${user}@${node2} "yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo"
#传输master节点上下载的docker包到node2节点 
scp -P ${ssh_port} ${install_dir}/packages/docker/* ${user}@${node2}:~
ssh -p ${ssh_port} ${user}@${node2} 'yum -y install ~/*.rpm'
ssh -p ${ssh_port} ${user}@${node2} "systemctl enable docker;systemctl start docker"
ssh -p ${ssh_port} ${user}@${node2} "mkdir /etc/docker/"
scp -P ${ssh_port} /etc/docker/daemon.json ${user}@${node2}:/etc/docker/
ssh -p ${ssh_port} ${user}@${node2} "systemctl restart docker"
ssh -p ${ssh_port} ${user}@${node2} 'rm -rf ~/*.rpm'
echo ""
echo "查看${node2}节点的docker状态"
ssh -p ${ssh_port} ${user}@${node2} "systemctl status docker"
}

function  deploy-cfssl() {
echo ""
echo "安装cfssl证书生成工具"
cd ${install_dir}/cfssl
chmod +x cfssl_linux-amd64 cfssljson_linux-amd64 cfssl-certinfo_linux-amd64
cp cfssl_linux-amd64 /usr/local/bin/cfssl
cp cfssljson_linux-amd64 /usr/local/bin/cfssljson
cp cfssl-certinfo_linux-amd64 /usr/bin/cfssl-certinfo
}
function deploy-etcd() {
echo ""
echo "生成Etcd证书,存放于/opt/TLS/etcd目录"
mkdir -p /opt/TLS/etcd		#创建etcd证书存放目录

echo "自签CA"
cd /opt/TLS/etcd
cat > ca-config.json << EOF
{
  "signing": {
    "default": {
      "expiry": "87600h"
    },
    "profiles": {
      "www": {
         "expiry": "87600h",
         "usages": [
            "signing",
            "key encipherment",
            "server auth",
            "client auth"
        ]
      }
    }
  }
}
EOF

cat > ca-csr.json << EOF
{
    "CN": "etcd CA",
    "key": {
        "algo": "rsa",
        "size": 2048
    },
    "names": [
        {
            "C": "CN",
            "L": "Shenzhen",
            "ST": "Shenzhen"
        }
    ]
}
EOF
echo ""
echo "生成证书，/opt/TLS/etcd目录下会生成ca.pem和ca-key.pem文件"
cd /opt/TLS/etcd
cfssl gencert -initca ca-csr.json | cfssljson -bare ca - 
echo ""
echo "使用自签CA签发Etcd HTTPS证书"
#注：下面文件hosts字段中IP为所有etcd节点的集群内部通信IP，一个都不能少，为了方便后期扩容可以多写几个预留的IP
cd /opt/TLS/etcd
cat > server-csr.json << EOF
{
    "CN": "etcd",
    "hosts": [
    "${masterIP}",
    "${node1IP}",
    "${node2IP}"
    ],
    "key": {
        "algo": "rsa",
        "size": 2048
    },
    "names": [
        {
            "C": "CN",
            "L": "Shenzhen",
            "ST": "Shenzhen"
        }
    ]
}
EOF
cd /opt/TLS/etcd
echo ""
echo "在/opt/TLS/etcd目录下生成server.pem和server-key.pem文件"
cfssl gencert -ca=ca.pem -ca-key=ca-key.pem -config=ca-config.json -profile=www server-csr.json | cfssljson -bare server
echo ""
echo "开始部署etcd集群"
#创建etcd的目录，bin目录存放可执行文件，config存放配置文件，ssl存放证书文件，data存放数据文件
mkdir  -p /opt/etcd/{bin,config,ssl,data}
echo "解压etcd源码包"
cd ${install_dir}
if [ -d etcd-v3.4.21-linux-amd64 ]
then 
 rm -rf etcd-v3.4.21-linux-amd64
fi
tar -zxvf etcd-v3.4.21-linux-amd64.tar.gz 
#复制可执行文件到etcd的目录
cp etcd-v3.4.21-linux-amd64/etcd /opt/etcd/bin/etcd 
cp etcd-v3.4.21-linux-amd64/etcdctl /opt/etcd/bin/etcdctl 
echo ""
echo "编写master节点的etcd配置文件"
touch  /opt/etcd/config/etcd.conf 
cat > /opt/etcd/config/etcd.conf << EOF
#[Member]
#1.节点名称，必须唯一
ETCD_NAME="etcd-1"
#2.设置数据保存的目录
ETCD_DATA_DIR="/opt/etcd/data"
#3.用于监听其他etcd member的url（集群通信监听地址）
ETCD_LISTEN_PEER_URLS="https://${masterIP}:2380"
#4.该节点对外提供服务的地址（客户端访问的监听地址）
ETCD_LISTEN_CLIENT_URLS="https://${masterIP}:2379"

#[Clustering]
#5.客户端访问的监听地址
ETCD_ADVERTISE_CLIENT_URLS="https://${masterIP}:2379"
#6.该节点成员对等URL地址，且会通告集群的其余成员节点（集群通告的监听地址）
ETCD_INITIAL_ADVERTISE_PEER_URLS="https://${masterIP}:2380"
#7.集群中所有节点的信息
ETCD_INITIAL_CLUSTER="etcd-1=https://${masterIP}:2380,etcd-2=https://${node1IP}:2380,etcd-3=https://${node2IP}:2380"
#8.创建集群的token，这个值每个集群保持唯一
ETCD_INITIAL_CLUSTER_TOKEN="etcd-cluster"
#9.初始集群状态，新建集群的时候，这个值为new；
ETCD_INITIAL_CLUSTER_STATE="new"
EOF
echo ""
echo "编写node1节点的etcd配置文件"
touch  /opt/etcd/config/etcd-node1.conf
cat > /opt/etcd/config/etcd-node1.conf << EOF
#[Member]
#1.节点名称，必须唯一
ETCD_NAME="etcd-2"
#2.设置数据保存的目录
ETCD_DATA_DIR="/opt/etcd/data"
#3.用于监听其他etcd member的url（集群通信监听地址）
ETCD_LISTEN_PEER_URLS="https://${node1IP}:2380"
#4.该节点对外提供服务的地址（客户端访问的监听地址）
ETCD_LISTEN_CLIENT_URLS="https://${node1IP}:2379"

#[Clustering]
#5.客户端访问的监听地址
ETCD_ADVERTISE_CLIENT_URLS="https://${node1IP}:2379"
#6.该节点成员对等URL地址，且会通告集群的其余成员节点（集群通告的监听地址）
ETCD_INITIAL_ADVERTISE_PEER_URLS="https://${node1IP}:2380"
#7.集群中所有节点的信息
ETCD_INITIAL_CLUSTER="etcd-1=https://${masterIP}:2380,etcd-2=https://${node1IP}:2380,etcd-3=https://${node2IP}:2380"
#8.创建集群的token，这个值每个集群保持唯一
ETCD_INITIAL_CLUSTER_TOKEN="etcd-cluster"
#9.初始集群状态，新建集群的时候，这个值为new；
ETCD_INITIAL_CLUSTER_STATE="new"
EOF
echo ""
echo "编写node2节点的etcd配置文件"
touch  /opt/etcd/config/etcd-node2.conf
cat > /opt/etcd/config/etcd-node2.conf << EOF
#[Member]
#1.节点名称，必须唯一
ETCD_NAME="etcd-3"
#2.设置数据保存的目录
ETCD_DATA_DIR="/opt/etcd/data"
#3.用于监听其他etcd member的url（集群通信监听地址）
ETCD_LISTEN_PEER_URLS="https://${node2IP}:2380"
#4.该节点对外提供服务的地址（客户端访问的监听地址）
ETCD_LISTEN_CLIENT_URLS="https://${node2IP}:2379"

#[Clustering]
#5.客户端访问的监听地址
ETCD_ADVERTISE_CLIENT_URLS="https://${node2IP}:2379"
#6.该节点成员对等URL地址，且会通告集群的其余成员节点（集群通告的监听地址）
ETCD_INITIAL_ADVERTISE_PEER_URLS="https://${node2IP}:2380"
#7.集群中所有节点的信息
ETCD_INITIAL_CLUSTER="etcd-1=https://${masterIP}:2380,etcd-2=https://${node1IP}:2380,etcd-3=https://${node2IP}:2380"
#8.创建集群的token，这个值每个集群保持唯一
ETCD_INITIAL_CLUSTER_TOKEN="etcd-cluster"
#9.初始集群状态，新建集群的时候，这个值为new；
ETCD_INITIAL_CLUSTER_STATE="new"
EOF


echo ""
echo "拷贝证书到etcd证书目录下"
cp /opt/TLS/etcd/ca*pem /opt/etcd/ssl/ 
cp /opt/TLS/etcd/server*pem /opt/etcd/ssl/ 

echo "使用systemd管理etcd服务"
cat > /usr/lib/systemd/system/etcd.service << EOF
[Unit]
Description=Etcd Server
After=network.target
After=network-online.target
Wants=network-online.target

[Service]
Type=notify
EnvironmentFile=/opt/etcd/config/etcd.conf
ExecStart=/opt/etcd/bin/etcd \
--cert-file=/opt/etcd/ssl/server.pem \
--key-file=/opt/etcd/ssl/server-key.pem \
--peer-cert-file=/opt/etcd/ssl/server.pem \
--peer-key-file=/opt/etcd/ssl/server-key.pem \
--trusted-ca-file=/opt/etcd/ssl/ca.pem \
--peer-trusted-ca-file=/opt/etcd/ssl/ca.pem \
--logger=zap
Restart=on-failure
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF

echo "将etcd服务文件分发到node1、node2上"
scp -P ${ssh_port} /usr/lib/systemd/system/etcd.service  ${user}@${node1}:/usr/lib/systemd/system/
scp -P ${ssh_port} /usr/lib/systemd/system/etcd.service  ${user}@${node2}:/usr/lib/systemd/system/
echo ""
echo "将etcd目录复制到其它节点上"
scp -P ${ssh_port} -r /opt/etcd ${user}@${node1}:/opt/
scp -P ${ssh_port} -r /opt/etcd ${user}@${node2}:/opt/
echo ""
echo "删除master节点etcd的配置文件以及修改node节点的etcd文件"
rm -rf /opt/etcd/config/etcd-node1.conf /opt/etcd/config/etcd-node2.conf
ssh -p ${ssh_port}  ${user}@${node1} "mv /opt/etcd/config/etcd-node1.conf /opt/etcd/config/etcd.conf"
ssh -p ${ssh_port}  ${user}@${node2} "mv /opt/etcd/config/etcd-node2.conf /opt/etcd/config/etcd.conf"
echo ""
echo "启动etcd服务"
systemctl daemon-reload
systemctl start etcd.service
systemctl status etcd.service
systemctl enable etcd.service
ssh -p ${ssh_port}  ${user}@${node1} "systemctl daemon-reload;systemctl start etcd.service;systemctl status etcd.service;systemctl enable etcd.service"
ssh -p ${ssh_port}  ${user}@${node2} "systemctl daemon-reload;systemctl start etcd.service;systemctl status etcd.service;systemctl enable etcd.service"
echo ""
echo '等待安装完成，需要耐心等待全部etcd集群启动完成，此处等待30s'
for i in $(seq 1 30);do echo -n "." ; sleep 1; done

echo ""
echo "验证etcd是否正常:"
ETCDCTL_API=3 /opt/etcd/bin/etcdctl \
--cacert=/opt/etcd/ssl/ca.pem \
--cert=/opt/etcd/ssl/server.pem \
--key=/opt/etcd/ssl/server-key.pem \
--endpoints="https://${masterIP}:2379,https://${node1IP}:2379,https://${node2IP}:2379" endpoint health \
--write-out=table

ETCDCTL_API=3 /opt/etcd/bin/etcdctl \
--cacert=/opt/etcd/ssl/ca.pem \
--cert=/opt/etcd/ssl/server.pem \
--key=/opt/etcd/ssl/server-key.pem \
--endpoints="https://${masterIP}:2379,https://${node1IP}:2379,https://${node2IP}:2379" \
endpoint status  -w table

echo ""
}

function deploy-apiserver() {
echo ""
echo "开始部署master节点的组件"
#生成kube-apiserver证书
#1、自签证书颁发机构（CA）
mkdir -p /opt/TLS/k8s/		#创建k8s证书存放目录
cd /opt/TLS/k8s/
echo "自签证书颁发机构（CA）在/opt/TLS/k8s/目录生成ca-config.json，ca-csr.json文件"
cat > ca-config.json << EOF
{
  "signing": {
    "default": {
      "expiry": "87600h"
    },
    "profiles": {
      "kubernetes": {
         "expiry": "87600h",
         "usages": [
            "signing",
            "key encipherment",
            "server auth",
            "client auth"
        ]
      }
    }
  }
}
EOF
cat > ca-csr.json << EOF
{
    "CN": "kubernetes",
    "key": {
        "algo": "rsa",
        "size": 2048
    },
    "names": [
        {
            "C": "CN",
            "L": "Shenzhen",
            "ST": "Shenzhen",
            "O": "k8s",
            "OU": "System"
        }
    ]
}
EOF

echo "在/opt/TLS/k8s/目录生成证书（会生成ca.pem和ca-key.pem文件）"
cfssl gencert -initca ca-csr.json | cfssljson -bare ca -
cat > server-csr.json << EOF
{
    "CN": "kubernetes",
    "hosts": [
      "${masterIP}",
      "10.0.0.1",
      "10.11.0.1"
    ],
    "key": {
        "algo": "rsa",
        "size": 2048
    },
    "names": [
        {
            "C": "CN",
            "L": "Shenzhen",
            "ST": "Shenzhen",
            "O": "k8s",
            "OU": "System"
        }
    ]
}
EOF
echo "在/opt/TLS/k8s/目录生成证书（会生成server.pem和server-key.pem文件）"
cfssl gencert -ca=ca.pem -ca-key=ca-key.pem -config=ca-config.json -profile=kubernetes server-csr.json | cfssljson -bare server


echo "创建k8s的目录"
mkdir -p /opt/kubernetes/{bin,config,ssl,logs}
echo '解压kubernetes-server-linux-amd64.tar.gz源码包'
cd ${install_dir}
if [ -d kubernetes ]
then 
rm -rf kubernetes
fi
#先合并包，因为单文件超过100M传不上gitee
cat kubernetes-server-linux-amd64.tar.gz.a* > kubernetes-server-linux-amd64.tar.gz
tar  -zxvf kubernetes-server-linux-amd64.tar.gz
echo ""
echo "复制可执行文件到k8s的/opt/kubernetes/bin目录" 
cd kubernetes/server/bin/
cp kube-apiserver  /opt/kubernetes/bin/
cp kube-controller-manager /opt/kubernetes/bin/
cp kube-scheduler /opt/kubernetes/bin/
echo "复制客户端命令工具到PATH能识别的路径下"
cp kubectl /usr/bin/

echo ""
echo "开始部署kube-apiserver"

echo "1、先拷贝过程给api-server生成的证书到k8s的证书目录"
cp /opt/TLS/k8s/ca*.pem /opt/kubernetes/ssl/
cp /opt/TLS/k8s/server*.pem /opt/kubernetes/ssl/

echo "2、创建kube-apiserver配置文件"
cat > /opt/kubernetes/config/kube-apiserver.conf << EOF
KUBE_APISERVER_OPTS="--logtostderr=false \\
--v=2 \\
--log-dir=/opt/kubernetes/logs \\
--etcd-servers=https://${masterIP}:2379,https://${node1IP}:2379,https://${node2IP}:2379 \\
--bind-address=${masterIP} \\
--secure-port=6443 \\
--advertise-address=${masterIP} \\
--allow-privileged=true \\
--service-cluster-ip-range=10.0.0.0/24 \\
--enable-admission-plugins=NodeRestriction \\
--authorization-mode=RBAC,Node \\
--enable-bootstrap-token-auth=true \\
--token-auth-file=/opt/kubernetes/config/token.csv \\
--service-node-port-range=30000-32767 \\
--kubelet-client-certificate=/opt/kubernetes/ssl/server.pem \\
--kubelet-client-key=/opt/kubernetes/ssl/server-key.pem \\
--tls-cert-file=/opt/kubernetes/ssl/server.pem  \\
--tls-private-key-file=/opt/kubernetes/ssl/server-key.pem \\
--client-ca-file=/opt/kubernetes/ssl/ca.pem \\
--service-account-key-file=/opt/kubernetes/ssl/ca-key.pem \\
--service-account-issuer=api \\
--service-account-signing-key-file=/opt/kubernetes/ssl/ca-key.pem \\
--etcd-cafile=/opt/etcd/ssl/ca.pem \\
--etcd-certfile=/opt/etcd/ssl/server.pem \\
--etcd-keyfile=/opt/etcd/ssl/server-key.pem \\
--requestheader-client-ca-file=/opt/kubernetes/ssl/ca.pem \\
--proxy-client-cert-file=/opt/kubernetes/ssl/server.pem \\
--proxy-client-key-file=/opt/kubernetes/ssl/server-key.pem \\
--requestheader-allowed-names=kubernetes \\
--requestheader-extra-headers-prefix=X-Remote-Extra- \\
--requestheader-group-headers=X-Remote-Group \\
--requestheader-username-headers=X-Remote-User \\
--enable-aggregator-routing=true \\
--audit-log-maxage=30 \\
--audit-log-maxbackup=3 \\
--audit-log-maxsize=100 \\
--audit-log-path=/opt/kubernetes/logs/k8s-audit.log"
EOF

echo " 3、启用 TLS Bootstrapping 机制"
echo "先生成token"
token=$(head -c 16 /dev/urandom | od -An -t x | tr -d ' ')
echo "token的值：${token}"
echo "将该token值保存在安装目录下得token.txt文件备用"
touch ${install_dir}/token.txt
echo "${token}" > ${install_dir}/token.txt
echo "token.txt文件的值：" 
cat  ${install_dir}/token.txt 
echo ""


echo " 创建token文件"
echo "格式：token，用户名，UID，用户组"
cat > /opt/kubernetes/config/token.csv << EOF
${token},kubelet-bootstrap,10001,"system:node-bootstrapper"
EOF

echo "4、使用systemd管理api-server"
cat > /usr/lib/systemd/system/kube-apiserver.service << EOF
[Unit]
Description=Kubernetes API Server
Documentation=https://github.com/kubernetes/kubernetes

[Service]
EnvironmentFile=/opt/kubernetes/config/kube-apiserver.conf
ExecStart=/opt/kubernetes/bin/kube-apiserver \$KUBE_APISERVER_OPTS
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

echo "5、启动api-server并设置开机启动"
systemctl daemon-reload;
systemctl start kube-apiserver;
systemctl status kube-apiserver;
systemctl enable kube-apiserver;
}

function deploy-controller-manager() {
echo ""    
echo "部署kube-controller-manager"
echo "1、生成kubeconfig文件"
echo "要先去生成kube-controller-manager证书"
cd /opt/TLS/k8s/
echo "创建证书请求文件"
cat > kube-controller-manager-csr.json << EOF
{
  "CN": "system:kube-controller-manager",
  "hosts": [],
  "key": {
    "algo": "rsa",
    "size": 2048
  },
  "names": [
    {
      "C": "CN",
      "L": "Shenzhen", 
      "ST": " Shenzhen",
      "O": "system:masters",
      "OU": "System"
    }
  ]
}
EOF
echo "生成证书"
cfssl gencert -ca=ca.pem -ca-key=ca-key.pem -config=ca-config.json -profile=kubernetes kube-controller-manager-csr.json | cfssljson -bare kube-controller-manager


echo "生成kubeconfig文件（直接在shell命令行执行）"
KUBE_CONFIG="/opt/kubernetes/config/kube-controller-manager.kubeconfig"
KUBE_APISERVER="https://${masterIP}:6443"

kubectl config set-cluster kubernetes \
  --certificate-authority=/opt/kubernetes/ssl/ca.pem \
  --embed-certs=true \
  --server=${KUBE_APISERVER} \
  --kubeconfig=${KUBE_CONFIG}
kubectl config set-credentials kube-controller-manager \
  --client-certificate=/opt/TLS/k8s/kube-controller-manager.pem \
  --client-key=/opt/TLS/k8s/kube-controller-manager-key.pem \
  --embed-certs=true \
  --kubeconfig=${KUBE_CONFIG}
kubectl config set-context default \
  --cluster=kubernetes \
  --user=kube-controller-manager \
  --kubeconfig=${KUBE_CONFIG}
kubectl config use-context default --kubeconfig=${KUBE_CONFIG}

echo "这时就生成了/opt/kubernetes/config/kube-controller-manager.kubeconfig文件了"

echo "2、创建controller-manager配置文件"
cat > /opt/kubernetes/config/kube-controller-manager.conf << EOF
KUBE_CONTROLLER_MANAGER_OPTS="--logtostderr=false \\
--v=2 \\
--log-dir=/opt/kubernetes/logs \\
--leader-elect=true \\
--kubeconfig=/opt/kubernetes/config/kube-controller-manager.kubeconfig \\
--bind-address=0.0.0.0 \\
--allocate-node-cidrs=true \\
--cluster-cidr=10.244.0.0/16 \\
--service-cluster-ip-range=10.0.0.0/24 \\
--cluster-signing-cert-file=/opt/kubernetes/ssl/ca.pem \\
--cluster-signing-key-file=/opt/kubernetes/ssl/ca-key.pem  \\
--root-ca-file=/opt/kubernetes/ssl/ca.pem \\
--service-account-private-key-file=/opt/kubernetes/ssl/ca-key.pem \\
--cluster-signing-duration=87600h0m0s"
EOF

echo "3、systemd管理controller-manager"
cat > /usr/lib/systemd/system/kube-controller-manager.service << EOF
[Unit]
Description=Kubernetes Controller Manager
Documentation=https://github.com/kubernetes/kubernetes

[Service]
EnvironmentFile=/opt/kubernetes/config/kube-controller-manager.conf
ExecStart=/opt/kubernetes/bin/kube-controller-manager \$KUBE_CONTROLLER_MANAGER_OPTS
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

echo "4、启动controller-manager并设置开机自启"
systemctl daemon-reload;
systemctl start kube-controller-manager;
systemctl status  kube-controller-manager;
systemctl enable kube-controller-manager;
}

function deploy-scheduler() {
echo ""    
echo "部署kube-scheduler"
echo "1、先生成kubeconfig文件"
cd /opt/TLS/k8s/
cat > kube-scheduler-csr.json << EOF
{
  "CN": "system:kube-scheduler",
  "hosts": [],
  "key": {
    "algo": "rsa",
    "size": 2048
  },
  "names": [
    {
      "C": "CN",
      "L": "Shenzhen",
      "ST": "Shenzhen",
      "O": "system:masters",
      "OU": "System"
    }
  ]
}
EOF
echo "生成证书"
cfssl gencert -ca=ca.pem -ca-key=ca-key.pem -config=ca-config.json -profile=kubernetes kube-scheduler-csr.json | cfssljson -bare kube-scheduler

echo "生成kubeconfig文件（在shell命令终端执行）"&>>${logs}
KUBE_CONFIG="/opt/kubernetes/config/kube-scheduler.kubeconfig"
KUBE_APISERVER="https://${masterIP}:6443"

kubectl config set-cluster kubernetes \
  --certificate-authority=/opt/kubernetes/ssl/ca.pem \
  --embed-certs=true \
  --server=${KUBE_APISERVER} \
  --kubeconfig=${KUBE_CONFIG}
kubectl config set-credentials kube-scheduler \
  --client-certificate=./kube-scheduler.pem \
  --client-key=./kube-scheduler-key.pem \
  --embed-certs=true \
  --kubeconfig=${KUBE_CONFIG}
kubectl config set-context default \
  --cluster=kubernetes \
  --user=kube-scheduler \
  --kubeconfig=${KUBE_CONFIG}
kubectl config use-context default --kubeconfig=${KUBE_CONFIG}

echo "kubeconfig文件就生成好了，位于/opt/kubernetes/config/kube-scheduler.kubeconfig"

echo "2、创建kube-scheduler配置文件"
cat > /opt/kubernetes/config/kube-scheduler.conf << EOF
KUBE_SCHEDULER_OPTS="--logtostderr=false \\
--v=2 \\
--log-dir=/opt/kubernetes/logs \\
--leader-elect \\
--kubeconfig=/opt/kubernetes/config/kube-scheduler.kubeconfig \\
--bind-address=${masterIP}"
EOF


echo "3、使用systemd管理kube-scheduler"

cat > /usr/lib/systemd/system/kube-scheduler.service << EOF
[Unit]
Description=Kubernetes Scheduler
Documentation=https://github.com/kubernetes/kubernetes

[Service]
EnvironmentFile=/opt/kubernetes/config/kube-scheduler.conf
ExecStart=/opt/kubernetes/bin/kube-scheduler \$KUBE_SCHEDULER_OPTS
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

echo "4、启动kube-scheduler并设置开机自启"
systemctl daemon-reload;
systemctl start kube-scheduler;
systemctl status kube-scheduler;
systemctl enable kube-scheduler;
}

function kubectl-init() {
echo ""    
echo "初始化kubectl组件"
echo "配置kubectl连接集群"

echo "生成kubectl连接集群的证书"
cd /opt/TLS/k8s/
cat > admin-csr.json <<EOF
{
  "CN": "admin",
  "hosts": [],
  "key": {
    "algo": "rsa",
    "size": 2048
  },
  "names": [
    {
      "C": "CN",
      "L": "Shenzhen",
      "ST": "Shenzhen",
      "O": "system:masters",
      "OU": "System"
    }
  ]
}
EOF
echo "生成证书"
cfssl gencert -ca=ca.pem -ca-key=ca-key.pem -config=ca-config.json -profile=kubernetes admin-csr.json | cfssljson -bare admin

echo "生成kubeconfig文件"
mkdir /root/.kube    #创建一个隐藏目录
#下面这段直接在shell命令终端执行
KUBE_CONFIG="/root/.kube/config"
KUBE_APISERVER="https://${masterIP}:6443"

kubectl config set-cluster kubernetes \
  --certificate-authority=/opt/kubernetes/ssl/ca.pem \
  --embed-certs=true \
  --server=${KUBE_APISERVER} \
  --kubeconfig=${KUBE_CONFIG}
kubectl config set-credentials cluster-admin \
  --client-certificate=/opt/TLS/k8s/admin.pem \
  --client-key=/opt/TLS/k8s/admin-key.pem \
  --embed-certs=true \
  --kubeconfig=${KUBE_CONFIG}
kubectl config set-context default \
  --cluster=kubernetes \
  --user=cluster-admin \
  --kubeconfig=${KUBE_CONFIG}
kubectl config use-context default --kubeconfig=${KUBE_CONFIG}

#在/root/.kube下生成了一个config配置文件
echo ""
echo "通过kubectl工具查看当前集群组件状态"
kubectl get cs  

echo "授权kubelet-bootstrap用户允许请求证书"
kubectl create clusterrolebinding kubelet-bootstrap \
--clusterrole=system:node-bootstrapper \
--user=kubelet-bootstrap
#判断集群绑定是否创建成功
while [ $? -ne 0  ]
do
  sleep 2
  kubectl create clusterrolebinding kubelet-bootstrap --clusterrole=system:node-bootstrapper --user=kubelet-bootstrap
done
}

function deploy-node() {
echo ""    
echo "部署Node节点组件,主要是kubelet、kube-proxy组件，同时master节点也部署这2个组件"
echo "在node节点上创建工作目录并拷贝二进制文件"
echo "在node1、node2节点上创建目录"
ssh -p ${ssh_port} ${user}@${node1}  "mkdir -p /opt/kubernetes/{bin,config,ssl,logs}"
ssh -p ${ssh_port} ${user}@${node2}  "mkdir -p /opt/kubernetes/{bin,config,ssl,logs}"

echo "在master节点拷贝源码包里面的kubelet、kube-proxy命令到/opt/kubernetes/bin/目录"
cd ${install_dir}
cp kubernetes/server/bin/kube-proxy /opt/kubernetes/bin/
cp kubernetes/server/bin/kubelet /opt/kubernetes/bin/
echo "在master节点上拷贝源码包里面的kubelet、kube-proxy命令到的${node1}、${node2}节点/opt/kubernetes/bin/目录"
scp -P ${ssh_port} kubernetes/server/bin/kube-proxy ${user}@${node1}:/opt/kubernetes/bin/
scp -P ${ssh_port} kubernetes/server/bin/kubelet ${user}@${node1}:/opt/kubernetes/bin/ 
scp -P ${ssh_port} kubernetes/server/bin/kube-proxy ${user}@${node2}:/opt/kubernetes/bin/  
scp -P ${ssh_port} kubernetes/server/bin/kubelet ${user}@${node2}:/opt/kubernetes/bin/ 
echo ""
echo "部署kubelet组件,${master}节点和${node1}、${node2}节点都部署"
echo "1、先在master节点上生成kubelet初次加入集群时的引导kubeconfig文件"
KUBE_CONFIG="/opt/kubernetes/config/bootstrap.kubeconfig"
KUBE_APISERVER="https://${masterIP}:6443"
TOKEN=`cat ${install_dir}/token.txt`

kubectl config set-cluster kubernetes \
  --certificate-authority=/opt/kubernetes/ssl/ca.pem \
  --embed-certs=true \
  --server=${KUBE_APISERVER} \
  --kubeconfig=${KUBE_CONFIG}
kubectl config set-credentials "kubelet-bootstrap" \
  --token=${TOKEN} \
  --kubeconfig=${KUBE_CONFIG}
kubectl config set-context default \
  --cluster=kubernetes \
  --user="kubelet-bootstrap" \
  --kubeconfig=${KUBE_CONFIG}
kubectl config use-context default --kubeconfig=${KUBE_CONFIG}

echo "执行完就生成了/opt/kubernetes/config/bootstrap.kubeconfig文件，把这个文件复制到${node1}、${node2}节点上"
scp -P ${ssh_port}  /opt/kubernetes/config/bootstrap.kubeconfig ${user}@${node1}:/opt/kubernetes/config/
scp -P ${ssh_port}  /opt/kubernetes/config/bootstrap.kubeconfig ${user}@${node2}:/opt/kubernetes/config/
echo ""
echo "2、 配置参数文件"
echo "先去master节点上把/opt/kubernetes/ssl/ca.pem文件复制到node1、node2节点"
scp -P ${ssh_port} /opt/kubernetes/ssl/ca.pem ${user}@${node1}:/opt/kubernetes/ssl/
scp -P ${ssh_port} /opt/kubernetes/ssl/ca.pem ${user}@${node2}:/opt/kubernetes/ssl/
 
echo "在${master}节点创建kubelet-config.yml文件"
cat > /opt/kubernetes/config/kubelet-config.yml << EOF
kind: KubeletConfiguration
apiVersion: kubelet.config.k8s.io/v1beta1
address: 0.0.0.0
port: 10250
readOnlyPort: 10255
cgroupDriver: systemd
clusterDNS:
- 10.0.0.2
clusterDomain: cluster.local 
failSwapOn: false
authentication:
  anonymous:
    enabled: false
  webhook:
    cacheTTL: 2m0s
    enabled: true
  x509:
    clientCAFile: /opt/kubernetes/ssl/ca.pem
authorization:
  mode: Webhook
  webhook:
    cacheAuthorizedTTL: 5m0s
    cacheUnauthorizedTTL: 30s
evictionHard:
  imagefs.available: 15%
  memory.available: 100Mi
  nodefs.available: 10%
  nodefs.inodesFree: 5%
maxOpenFiles: 1000000
maxPods: 110
EOF
echo "将kubelet-config.yml文件复制到${node1}、${node2}节点"
scp -P ${ssh_port} /opt/kubernetes/config/kubelet-config.yml ${user}@${node1}:/opt/kubernetes/config/
scp -P ${ssh_port} /opt/kubernetes/config/kubelet-config.yml ${user}@${node2}:/opt/kubernetes/config/

echo ""
echo "3、创建kubelet配置文件"
echo "在${master}节点创建kubelet.conf"
cat > /opt/kubernetes/config/kubelet.conf << EOF
KUBELET_OPTS="--logtostderr=false \\
--v=2 \\
--log-dir=/opt/kubernetes/logs \\
--hostname-override=master \\
--network-plugin=cni \\
--kubeconfig=/opt/kubernetes/config/kubelet.kubeconfig \\
--bootstrap-kubeconfig=/opt/kubernetes/config/bootstrap.kubeconfig \\
--config=/opt/kubernetes/config/kubelet-config.yml \\
--cert-dir=/opt/kubernetes/ssl \\
--pod-infra-container-image=registry.aliyuncs.com/google_containers/pause:3.5"
EOF
echo ""
echo "复制/opt/kubernetes/config/kubelet.conf配置文件到${node1}、${node2}节点"
scp -P ${ssh_port} /opt/kubernetes/config/kubelet.conf ${user}@${node1}:/opt/kubernetes/config/
scp -P ${ssh_port} /opt/kubernetes/config/kubelet.conf ${user}@${node2}:/opt/kubernetes/config/
ssh -p ${ssh_port} ${user}@${node1} 'sed -i "s/master/node1/g" /opt/kubernetes/config/kubelet.conf'
ssh -p ${ssh_port} ${user}@${node2} 'sed -i "s/master/node2/g" /opt/kubernetes/config/kubelet.conf'
echo ""
echo "5、设置systemd管理kubelet服务"
echo "创建kubelet.service文件"
cat > /usr/lib/systemd/system/kubelet.service << EOF
[Unit]
Description=Kubernetes Kubelet
After=docker.service

[Service]
EnvironmentFile=/opt/kubernetes/config/kubelet.conf
ExecStart=/opt/kubernetes/bin/kubelet \$KUBELET_OPTS
Restart=on-failure
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF
echo ""
echo "复制kubelet.service文件到${node1}、${node2}节点"
scp -P ${ssh_port} /usr/lib/systemd/system/kubelet.service ${user}@${node1}:/usr/lib/systemd/system/
scp -P ${ssh_port} /usr/lib/systemd/system/kubelet.service ${user}@${node2}:/usr/lib/systemd/system/
echo ""
echo "6、启动kubelet 并设置开机启动"
echo "启动kubelet服务";
systemctl daemon-reload;
systemctl start kubelet;
systemctl status kubelet;
systemctl enable kubelet;
echo ""
echo "启动${node1}节点上的kubelet服务"
ssh -p ${ssh_port} ${user}@${node1} "systemctl daemon-reload;systemctl start kubelet;systemctl status kubelet;systemctl enable kubelet"
echo "启动${node2}节点上的kubelet服务"
ssh -p ${ssh_port} ${user}@${node2} "systemctl daemon-reload;systemctl start kubelet;systemctl status kubelet;systemctl enable kubelet"

echo ""
echo "master节点批准kubelet证书申请并加入集群"
echo "此处需要等待全部节点的kubelet服务启动后再批准加入集群"
for i in $(seq 1 30);do echo -n "." ; sleep 1; done

echo ""
echo "在master节点批准kubelet证书申请并加入集群"
#判断是否可以获取资源，因为发现这步有时候回报错error: the server doesn't have a resource type "csr"
status=$(kubectl get csr &> /dev/null)
while [ $? -ne 0  ]
do
  sleep 5
  status=$(kubectl get csr &> /dev/null)
done
#批准加入集群
for i in `kubectl get csr | grep -v 'NAME' | grep 'Pending' | awk '{print $1}'`; do kubectl certificate approve $i ; done;
echo ""
echo "部署kube-proxy"
echo "1、配置参数文件"
cat > /opt/kubernetes/config/kube-proxy-config.yml << EOF
kind: KubeProxyConfiguration
apiVersion: kubeproxy.config.k8s.io/v1alpha1
bindAddress: 0.0.0.0
metricsBindAddress: 0.0.0.0:10249
clientConnection:
  kubeconfig: /opt/kubernetes/config/kube-proxy.kubeconfig
hostnameOverride: master
clusterCIDR: 10.244.0.0/16
EOF

echo "复制到node节点"
scp -P ${ssh_port} /opt/kubernetes/config/kube-proxy-config.yml ${user}@${node1}:/opt/kubernetes/config/
scp -P ${ssh_port} /opt/kubernetes/config/kube-proxy-config.yml ${user}@${node2}:/opt/kubernetes/config/
ssh -p ${ssh_port} ${user}@${node1} 'sed -i "s/master/node1/g" /opt/kubernetes/config/kube-proxy-config.yml'
ssh -p ${ssh_port} ${user}@${node2} 'sed -i "s/master/node2/g" /opt/kubernetes/config/kube-proxy-config.yml'

echo "2、创建kube-proxy配置文件"
cat > /opt/kubernetes/config/kube-proxy.conf << EOF
KUBE_PROXY_OPTS="--logtostderr=false \\
--v=2 \\
--log-dir=/opt/kubernetes/logs \\
--config=/opt/kubernetes/config/kube-proxy-config.yml"
EOF

scp -P ${ssh_port} /opt/kubernetes/config/kube-proxy.conf ${user}@${node1}:/opt/kubernetes/config/
scp -P ${ssh_port} /opt/kubernetes/config/kube-proxy.conf ${user}@${node2}:/opt/kubernetes/config/

echo "3、在master节点上生成kube-proxy.kubeconfig文件"
# 切换工作目录
cd /opt/TLS/k8s/
echo "创建证书请求文件"
cat > kube-proxy-csr.json << EOF
{
  "CN": "system:kube-proxy",
  "hosts": [],
  "key": {
    "algo": "rsa",
    "size": 2048
  },
  "names": [
    {
      "C": "CN",
      "L": "Shenzhen",
      "ST": "Shenzhen",
      "O": "k8s",
      "OU": "System"
    }
  ]
}
EOF

echo "生成证书"
cfssl gencert -ca=ca.pem -ca-key=ca-key.pem -config=ca-config.json -profile=kubernetes kube-proxy-csr.json | cfssljson -bare kube-proxy
echo ""
echo "生成kubeconfig文件"
KUBE_CONFIG="/opt/kubernetes/config/kube-proxy.kubeconfig"
KUBE_APISERVER="https://${masterIP}:6443"

kubectl config set-cluster kubernetes \
  --certificate-authority=/opt/kubernetes/ssl/ca.pem \
  --embed-certs=true \
  --server=${KUBE_APISERVER} \
  --kubeconfig=${KUBE_CONFIG}
kubectl config set-credentials kube-proxy \
  --client-certificate=/opt/TLS/k8s/kube-proxy.pem \
  --client-key=/opt/TLS/k8s/kube-proxy-key.pem \
  --embed-certs=true \
  --kubeconfig=${KUBE_CONFIG}
kubectl config set-context default \
  --cluster=kubernetes \
  --user=kube-proxy \
  --kubeconfig=${KUBE_CONFIG}
kubectl config use-context default --kubeconfig=${KUBE_CONFIG}
echo ""
echo "生成了/opt/kubernetes/config/kube-proxy.kubeconfig，把这文件复制到${node1}、${node2}节点上"
scp -P ${ssh_port} /opt/kubernetes/config/kube-proxy.kubeconfig  ${user}@${node1}:/opt/kubernetes/config/
scp -P ${ssh_port} /opt/kubernetes/config/kube-proxy.kubeconfig  ${user}@${node2}:/opt/kubernetes/config/
echo ""
echo "4、使用systemd管理kube-proxy"
cat > /usr/lib/systemd/system/kube-proxy.service << EOF
[Unit]
Description=Kubernetes Proxy
After=network.target

[Service]
EnvironmentFile=/opt/kubernetes/config/kube-proxy.conf
ExecStart=/opt/kubernetes/bin/kube-proxy \$KUBE_PROXY_OPTS
Restart=on-failure
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF
echo ""
echo "复制/usr/lib/systemd/system/kube-proxy.service文件到${node1}、${node2}节点上"
scp -P ${ssh_port} /usr/lib/systemd/system/kube-proxy.service  ${user}@${node1}:/usr/lib/systemd/system/
scp -P ${ssh_port} /usr/lib/systemd/system/kube-proxy.service  ${user}@${node2}:/usr/lib/systemd/system/
echo ""
echo "5、启动kube-proxy并设置开机启动"
systemctl daemon-reload  ;
systemctl start kube-proxy;
systemctl status kube-proxy;
systemctl enable kube-proxy; 
echo ""
echo "启动${node1}、${node2}节点kube-proxy并设置开机启动" 
ssh -p ${ssh_port} ${user}@${node1} "systemctl daemon-reload;systemctl start kube-proxy;systemctl status kube-proxy;systemctl enable kube-proxy;"
ssh -p ${ssh_port} ${user}@${node2} "systemctl daemon-reload;systemctl start kube-proxy;systemctl status kube-proxy;systemctl enable kube-proxy;"
}

function deploy-calico() {
echo ""
echo "安装部署calico网络插件"
docker images| grep 'calico/cni' | grep 'v3.24.3'
if [ $? -ne 0 ]
then
echo "正在下载calico/cni:v3.24.3镜像"
docker pull guo214/calico-cni:v3.24.3
while [ $? -ne 0 ] 
do
 echo "calico-cni:v3.24.3镜像下载失败，正在重试..."
 docker pull guo214/calico-cni:v3.24.3
done
fi

docker images| grep 'calico/node' | grep 'v3.24.3'
if [ $? -ne 0 ]
then
echo "正在下载calico/node:v3.24.3镜像"
docker pull guo214/calico-node:v3.24.3
while [ $? -ne 0 ]
do
 echo "calico-node:v3.24.3镜像下载失败，正在重试..."
 docker pull guo214/calico-node:v3.24.3
done
fi
docker images| grep 'calico/kube-controllers'| grep 'v3.24.3'
if [ $? -ne 0 ]
then
echo "正在下载calico/kube-controllers:v3.24.3镜像"
docker pull guo214/calico-kube-controllers:v3.24.3
while [ $? -ne 0 ]
do 
 echo "calico/kube-controllers:v3.24.3镜像下载失败，正在重试..."
 docker pull guo214/calico-kube-controllers:v3.24.3
done
fi
#修改镜像的tag,因为yaml文件里面的镜像tag和现在的不一样
docker tag guo214/calico-cni:v3.24.3 			calico/cni:v3.24.3
docker tag guo214/calico-node:v3.24.3 			calico/node:v3.24.3
docker tag guo214/calico-kube-controllers:v3.24.3	calico/kube-controllers:v3.24.3
#删除tag
docker rmi guo214/calico-cni:v3.24.3
docker rmi guo214/calico-node:v3.24.3 
docker rmi guo214/calico-kube-controllers:v3.24.3
#打包镜像
cd ${install_dir}/calico
docker save -o calico-cni.tar.gz 		calico/cni:v3.24.3
docker save -o calico-node.tar.gz 		calico/node:v3.24.3
docker save -o calico-kube-controllers.tar.gz 	calico/kube-controllers:v3.24.3
#将打包好的镜像分发到其他节点
scp -P ${ssh_port} ./*.tar.gz  ${user}@${node1}:/tmp/
scp -P ${ssh_port} ./*.tar.gz  ${user}@${node2}:/tmp/
for i in `ls *.tar.gz`; do docker load -i $i; done;
ssh -p ${ssh_port} ${user}@${node1} 'for i in `ls /tmp/*.tar.gz`; do docker load -i $i; done;'
ssh -p ${ssh_port} ${user}@${node2} 'for i in `ls /tmp/*.tar.gz`; do docker load -i $i; done;'

kubectl apply -f calico.yaml 
#删除镜像
cd ${install_dir}/calico
rm -rf calico-cni.tar.gz calico-node.tar.gz  calico-kube-controllers.tag.gz
}

function deploy-coredns() {
echo ""    
echo "部署coredns"
cd ${install_dir}/coredns
kubectl apply -f coredns.yaml
}

function others() {
echo ""    
echo "解决kube-proxy出现无法代理的情况"
yum install  -y conntrack;
systemctl  restart kube-proxy.service
ssh -p ${ssh_port} ${user}@${node1} "yum install conntrack -y ;systemctl restart kube-proxy.service"
ssh -p ${ssh_port} ${user}@${node1} "yum install conntrack -y ;systemctl restart kube-proxy.service"
echo ""
echo "修改集群节点的角色"
kubectl  label nodes master  node-role.kubernetes.io/control-plane=
kubectl  label nodes master  node-role.kubernetes.io/master=
kubectl  label nodes node1  node-role.kubernetes.io/node=
kubectl  label nodes node2  node-role.kubernetes.io/node=
echo ""
echo "设置kubectl命令自动补全"
source /usr/share/bash-completion/bash_completion
source  <(kubectl completion bash)
echo 'source /usr/share/bash-completion/bash_completion' >> ~/.bash_profile
echo 'source  <(kubectl completion bash)' >> ~/.bash_profile
source ~/.bash_profile

#部署helm测试k8s集群是否正常
echo ""
echo "部署helm工具，安装nginx chart校验k8s集群是否正常"
cd ${install_dir}
tar xf helm-v3.7.1-linux-amd64.tar.gz
mv linux-amd64/helm  /usr/local/bin/
helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo update bitnami
helm install nginx nginx-13.2.33.tgz  -n default
#检查k8s集群是否开始创建nginx pod,如果没有创建则进入while循环等待
kubectl  get pod -n default | grep nginx &> /dev/null
while [ $? -ne 0 ]
do
echo -n "."
sleep 1
kubectl  get pod -n default | grep nginx &> /dev/null
done
#k8s开始创建nginx pod，检查是否pod就绪
status=$(kubectl  get pod -n default | grep nginx | awk '{print $2}')
echo ""
echo "等待nginx pod启动就绪"
while [ ${status} != '1/1' ]
do
echo -n "."
sleep 1
status=$(kubectl  get pod -n default | grep nginx | awk '{print $2}')
done
curl `kubectl get svc --namespace default | grep nginx | awk '{print $3}'`:80

#设置helm命令自动补全
helm completion bash > /etc/bash_completion.d/helm
}

function deploy() {
#部署etcd集群
deploy-etcd

#部署kube-apiserver、kube-scheduler、kube-controller-manager组件
deploy-apiserver
deploy-scheduler
deploy-controller-manager

#初始化kubectl
kubectl-init

#部署kubelet.service、kube-proxy.service服务
deploy-node

#部署calico
deploy-calico

#部署coredns
deploy-coredns

#集群后置工作
others
}


function environment-recover() {
echo ""
echo "各节点firewall防火墙、selinux、swap分区、NetworkManager已经关闭，如需启动可手动执行下面命令启动"
echo "systemctl start firewalld.service NetworkManager.service; systemctl enable firewalld.service NetworkManager.service"
echo 'setenforce 1 ; sed -ri 's/SELINUX=disabled/SELINUX=enforcing/g' /etc/selinux/config '
echo "swapon -a ; vim /etc/fstab 取消swap行注释；mount -a;"
echo ""
echo "删除各个节点的/etc/sysctl.d/kubernetes.conf文件"
rm -rf /etc/sysctl.d/kubernetes.conf
sysctl --system
ssh -p ${ssh_port} ${user}@${node1}  "rm -rf /etc/sysctl.d/kubernetes.conf;sysctl --system"
ssh -p ${ssh_port} ${user}@${node2}  "rm -rf /etc/sysctl.d/kubernetes.conf;sysctl --system"
}

function remove-docker() {
echo ""
echo "卸载各个节点docker服务并删除数据"
systemctl stop docker
yum remove -y docker \
	docker-ce \
	docker-ce-cli \
	docker-ce-rootless-extras \
	docker-scan-plugin \
	docker-client \
	docker-client-latest \
	docker-common \
	docker-latest \
	docker-latest-logrotate \
	docker-logrotate \
	docker-engine \
	containerd.io
rm -rf /var/lib/docker /etc/docker /run/docker /var/lib/dockershim 
rm -rf /usr/lib/systemd/system/docker.service
systemctl daemon-reload

ssh -p ${ssh_port} ${user}@${node1} "yum remove -y docker docker-ce docker-ce-cli docker-ce-rootless-extras docker-scan-plugin docker-client docker-client-latest docker-common docker-latest docker-latest-logrotate docker-logrotate docker-engine containerd.io"
rm -rf /var/lib/docker /etc/docker /run/docker /var/lib/dockershim 
rm -rf /usr/lib/systemd/system/docker.service
systemctl daemon-reload

ssh -p ${ssh_port} ${user}@${node2} "yum remove -y docker docker-ce docker-ce-cli docker-ce-rootless-extras docker-scan-plugin docker-client docker-client-latest docker-common docker-latest docker-latest-logrotate docker-logrotate docker-engine containerd.io"
rm -rf /var/lib/docker /etc/docker /run/docker /var/lib/dockershim 
rm -rf /usr/lib/systemd/system/docker.service
systemctl daemon-reload
}

function remove-master() {
echo "停止master节点服务组件"
systemctl  stop kube-apiserver.service kube-scheduler.service kube-controller-manager.service kubelet.service kube-proxy.service etcd.service
rm -rf  /usr/lib/systemd/system/kube*.service /usr/lib/systemd/system/etcd.service
systemctl daemon-reload
echo '删除k8s配置目录/opt/{cni,etcd,kubernetes,TLS},家目录下的.kube目录,helm客户端工具'
rm -rf /opt/{cni,etcd,kubernetes,TLS}  ~/.kube
rm -rf /usr/local/bin/helm
rm -rf /usr/bin/kubectl
}

function remove-cfssl() {
echo "删除cfssl证书工具"
rm -rf /usr/local/bin/cfssl
rm -rf /usr/local/bin/cfssljson
rm -rf /usr/bin/cfssl-certinfo
}

function remove-node() {
echo "删除node节点服务组件"
ssh -p ${ssh_port} ${user}@${node1} 'systemctl  stop kubelet.service kube-proxy.service etcd.service'
ssh -p ${ssh_port} ${user}@${node1} 'rm -rf  /usr/lib/systemd/system/{kubelet.service,kube-proxy.service} /usr/lib/systemd/system/etcd.service'
ssh -p ${ssh_port} ${user}@${node1} 'systemctl daemon-reload;'
ssh -p ${ssh_port} ${user}@${node1} 'rm -rf /opt/{cni,etcd,kubernetes}'
ssh -p ${ssh_port} ${user}@${node2} 'systemctl  stop kubelet.service kube-proxy.service etcd.service'
ssh -p ${ssh_port} ${user}@${node2} 'rm -rf  /usr/lib/systemd/system/{kubelet.service,kube-proxy.service} /usr/lib/systemd/system/etcd.service'
ssh -p ${ssh_port} ${user}@${node2} 'systemctl daemon-reload;'
ssh -p ${ssh_port} ${user}@${node2} 'rm -rf /opt/{cni,etcd,kubernetes}'
}

#remove卸载k8s集群函数
function remove() {
environment-recover
remove-docker
remove-master
remove-cfssl
remove-node
}


function status() {
#只检查了master节点，有问题待完算
echo "检查master节点各服务组件:"

netstat -lntup | grep 6443 | grep LISTEN &> /dev/null
if [ $? -ne 0 ]
then
  echo "kube-apiserver的6443端口不存在，请检查是否已安装k8s集群"
  exit 1
fi
stauts_0=$(systemctl status kube-apiserver.service | grep -i running | awk -F'(' '{print $2}' | awk -F')' '{print $1}')
if [ ${stauts_0} != "running" ]
then
  echo "kube-apiserver.service未正常运行，请检查"
  exit 1
else
  echo "kube-apiserver.service is running"
fi
stauts_1=$(systemctl status kube-scheduler.service | grep -i running | awk -F'(' '{print $2}' | awk -F')' '{print $1}')
if [ ${stauts_1} != "running" ]
then
  echo "kube-scheduler.service未正常运行，请检查"
  exit 1
else
  echo "kube-scheduler.service is running"
fi
stauts_2=$(systemctl status kube-controller-manager.service | grep -i running | awk -F'(' '{print $2}' | awk -F')' '{print $1}')
if [ ${stauts_2} != "running" ]
then
  echo "kube-controller-manager.service未正常运行，请检查"
  exit 1
else
  echo "kube-controller-manager.service is running"
fi
stauts_3=$(systemctl  status  kubelet.service | grep -i running | awk -F'(' '{print $2}' | awk -F')' '{print $1}')
if [ ${stauts_3} != "running" ]
then
  echo "kubelet.service未正常运行，请检查"
  exit 1
else
  echo "kubelet.service is running"
fi
stauts_4=$(systemctl  status  kube-proxy.service | grep -i running | awk -F'(' '{print $2}' | awk -F')' '{print $1}')
if [ ${stauts_4} != "running" ]
then
  echo "kube-proxy.service未正常运行，请检查"
  exit 1
else
  echo "kube-proxy.service is running"
fi
echo
echo "执行kubectl get pod -A命令,查看全部的pod是否正常:"
kubectl get pod -A
}

########################################
# 主函数
########################################
function main() {
    local command="${1:-unknown}"
    case "${command}" in
        deploy)
            #计算脚本执行时间
            start_time=$(date "+%Y-%m-%d %H:%M:%S")

            environment-check
	        kernel-check
            environment-init
	        deploy-docker
	        deploy-cfssl
	        deploy

            #脚本执行结束时间
            end_time=$(date "+%Y-%m-%d %H:%M:%S")
            echo ""
            echo "脚本执行开始时间: ${start_time}" 
            echo "脚本执行结束时间: ${end_time}" 
            exit 0
            ;;
        remove)
            #脚本执行开始时间
            start_time=$(date "+%Y-%m-%d %H:%M:%S")

	        remove

            #脚本执行结束时间
            end_time=$(date "+%Y-%m-%d %H:%M:%S")
            echo ""
            echo "脚本执行开始时间: ${start_time}" 
            echo "脚本执行结束时间: ${end_time}" 
            exit 0
            ;;
        status)
            status
            exit 0
            ;;
        -h|--help)
	    usage
            exit 1
	    ;;
        *)
            echo "Unknown command: ${command}"
            usage
            exit 1
            ;;
    esac
}

main "$@"