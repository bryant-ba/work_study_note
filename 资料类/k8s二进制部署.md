本篇文章中所有组件都将使用二进制或 Docker 镜像的方式部署，包括 Nginx 和 Keepalived，不是因为它装起来有多方便，而是二进制程序和容器能在不考虑系统发行版层面的情况下去使用，所以参考此篇博文你完全可以在任何一个 Linux 发行版上来成功部署一套多 Master 的 Kubernetes 集群。

除此之外，本片文章中所有使用到的组件都标上来源或附上了官方来源链接，即便后续的版本有更新，你也能知道该从哪里去获取最新的程序版本，部署方式其实不会有很大的变化~

# 环境准备

## 主机规划

我这里所有机器系统均使用 CentOS 7.8，规划如下：

| 主机名  | IP                               | CPU/内存 | 角色                                                         |
| :------ | :------------------------------- | :------- | :----------------------------------------------------------- |
| `K8s01` | 192.168.5.140                    | 2C/4G    | Master(`kube-apiserver`、`kube-controller-manager`、`kube-scheduler`、`etcd`) |
| `K8s02` | 192.168.5.141                    | 2C/4G    | Master(`kube-apiserver`、`kube-controller-manager`、`kube-scheduler`) |
| `K8s03` | 192.168.5.142                    | 4C/8G    | Node(`kubelet`、`kube-proxy`、`etcd`)                        |
| `k8s04` | 192.168.5.144                    | 4C/8G    | Node(`kubelet`、`kube-proxy`、`etcd`)                        |
| `k8s05` | 192.168.5.145(VIP:192.168.0.180) | 2C/4G    | L4 LB-Master(`nginx`)                                        |
| `k8s06` | 192.168.5.146                    | 2C/4G    | L4 LB-Backup(`nginx`)                                        |

## 目录约定

由于是使用二进制部署，所以所有的目录都需要我们来自己定义，这里我规划目录结构如下：

- `/opt/apps`：所有二进制程序安装目录；
- `/opt/apps/<application_name>/bin`：程序的二进制包存放目录；
- `/opt/apps/<application_name>/conf`：程序的配置文件存放目录；
- `/opt/apps/<application_name>/data`：程序的数据目录；
- `/opt/apps/<application_name>/ssl`：程序所需的证书和私钥文件存放目录；
- `/opt/apps/<application_name>/log`：程序日志存放目录；

下面命令创建了此次部署所需要的程序目录：

```bash
$ mkdir -p /opt/apps/etcd/{bin,data,conf,ssl} # etcd，k8s01、k8s03、k8s04
$ mkdir -p /opt/apps/kubernetes/{bin,conf,ssl,log} # kubernetes，k8s01、k8s02、k8s03、k8s04
$ mkdir -p /opt/apps/docker/{bin,data,conf} # docker，k8s03、k8s04
$ mkdir -p /opt/apps/cni/{bin,conf} # CNI 网络插件，k8s03、k8s04
$ mkdir -p /opt/apps/nginx/{conf/conf.d,log} # Nginx，k8s05、k8s06
$ mkdir -p /opt/apps/keepalived/conf # Keepalived，k8s05、k8s06
```

## 初始化

关闭防火墙：

```bash
$ systemctl stop firewalld
$ systemctl disable firewalld
```

关闭 selinux：

```bash
$ sed -i 's/enforcing/disabled/' /etc/selinux/config  # 永久
$ setenforce 0  # 临时
```

关闭 swap：

```bash
$ swapoff -a  # 临时
$ vim /etc/fstab  # 永久
```

设置对应的主机名：

```bash
$ hostnamectl set-hostname <hostname>
```

在所有主机添加 hosts：

```bash
$ cat >> /etc/hosts << EOF
192.168.5.140 k8s01
192.168.5.141 k8s02
192.168.5.141 k8s03
192.168.5.144 k8s04
192.168.5.145 k8s05
192.168.5.1 k8s06
EOF
```

将桥接的 IPv4 流量传递到 iptables 的链并开启核心转发：

```bash
$ cat > /etc/sysctl.d/k8s.conf << EOF
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1
net.ipv4.ip_forward = 1
EOF
$ sysctl --system  # 生效
```

调整单个进程能打开的文件描述符数量：

```bash
$ echo '*               -       nofile          65535' >> /etc/security/limits.conf
```

加载 IPVS 模块：

```bash
$ echo 'for i in $(ls /usr/lib/modules/$(uname -r)/kernel/net/netfilter/ipvs|grep -o "^[^.]*");do /sbin/modinfo -F filename $i >/dev/null 2>&1 && /sbin/modprobe $i;done' > /etc/profile.d/ipvs_module.sh
$ . /etc/profile.d/ipvs_module.sh
# 检查
$ lsmod | grep ip_vs
```

时间同步：

```bash
$ yum install ntpdate -y
$ sudo crontab -l
*/5 * * * * /usr/sbin/ntpdate ntp1.aliyun.com &> /dev/null
```

升级内核版本（内核版本低于 `4.1` 则需要升级，通过 `uname -r` 查看），参考 【[CentOS 7 升级内核版本到最新](https://www.zze.xyz/archives/linux-update-kernel.html)】。

## 二进制包下载

### Kubernetes 二进制包

下载 Kubernetes 二进制包，官网地址：https://kubernetes.io/docs/setup/release/notes/，下载如下文件：

- [kubernetes-server-linux-amd64.tar.gz](https://dl.k8s.io/v1.19.0/kubernetes-server-linux-amd64.tar.gz)

> 我这里的直链使用的是 `v1.19.0` 版本。
> 官网好像只有大版本下载，小版本二进制包可在 Github 中下载，地址：https://github.com/kubernetes/kubernetes/tree/master/CHANGELOG。

这个压缩包中包含了服务端和客户端所有的二进制程序，所以只下载它就够了。

### cfssl 二进制包

下载 cfssl 二进制包用于签发证书，官网地址：https://pkg.cfssl.org/，下载如下文件：

- [cfssl_linux-amd64](https://pkg.cfssl.org/R1.2/cfssl_linux-amd64)
- [cfssljson_linux-amd64](https://pkg.cfssl.org/R1.2/cfssljson_linux-amd64)
- [cfssl-certinfo_linux-amd64](https://pkg.cfssl.org/R1.2/cfssl-certinfo_linux-amd64)

将 cfssl 的几个二进制包添加到 `PATH` 包含的目录下：

```bash
$ ls cfssl*
cfssl-certinfo_linux-amd64  cfssljson_linux-amd64  cfssl_linux-amd64
$ chmod +x cfssl*
$ cp cfssl-certinfo_linux-amd64 /usr/local/bin/cfssl-certinfo
$ cp cfssljson_linux-amd64 /usr/local/bin/cfssl-json
$ cp cfssl_linux-amd64 /usr/local/bin/cfssl
```

### ETCD 二进制包

下载 ETCD 的二进制包，官方 Github 地址：https://github.com/etcd-io/etcd/releases，下载如下文件：

- [etcd-v3.4.13-linux-amd64.tar.gz](https://github.com/etcd-io/etcd/releases/download/v3.4.13/etcd-v3.4.13-linux-amd64.tar.gz)

### Docker 二进制包

这里我以二进制包形式安装 Docker，其官方仓库地址为 https://download.docker.com/linux/static/stable/x86_64/，下载如下文件：

- [docker-19.03.9.tgz](https://download.docker.com/linux/static/stable/x86_64/docker-rootless-extras-19.03.0.tgz)

### CNI 网络插件二进制包

官方 Github 地址：https://github.com/containernetworking/plugins/releases，下载如下文件：

- [cni-plugins-linux-amd64-v0.8.7.tgz](https://github.com/containernetworking/plugins/releases/download/v0.8.7/cni-plugins-linux-amd64-v0.8.7.tgz)

# 签发证书

## ETCD 证书

### 准备文件

```bash
$ tree 
.
├── generate_cert.sh
└── json_file
    ├── ca-config.json
    ├── ca-csr.json
    └── server-csr.json
```

上述几个文件的内容分别如下（标 '*' 的文件名表示该文件内容你要根据你的环境进行修改）：

- `generate_cert.sh`：

```bash
cfssl gencert -initca json_file/ca-csr.json | cfssl-json -bare ca -
cfssl gencert -ca=ca.pem -ca-key=ca-key.pem -config=json_file/ca-config.json -profile=www json_file/server-csr.json | cfssl-json -bare server
```

- `json_file/ca-config.json`：

```json
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
```

- `json_file/ca-csr.json`：

```json
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
```

- `json_file/server-csr.json`*：

```json
{
    "CN": "etcd",
    "hosts": [
                "192.168.5.140",
                "192.168.5.142",
                "192.168.5.144"
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
```

> 此处 `hosts` 列表要添加上所有 etcd 节chmo	点的 IP。

### 颁发证书

这里直接执行一下 `generate_cert.sh` 即可，该文件会在当前目录自签一套 CA 证书并基于这个 CA 为 ETCD 签发一套证书，如下：

```bash
$ ./generate_cert.sh 
2020/10/17 15:33:57 [INFO] generating a new CA key and certificate from CSR
2020/10/17 15:33:57 [INFO] generate received request
2020/10/17 15:33:57 [INFO] received CSR
2020/10/17 15:33:57 [INFO] generating key: rsa-2048
2020/10/17 15:33:58 [INFO] encoded CSR
2020/10/17 15:33:58 [INFO] signed certificate with serial number 404959556665807068980910454062715305835429368392
2020/10/17 15:33:58 [INFO] generate received request
2020/10/17 15:33:58 [INFO] received CSR
2020/10/17 15:33:58 [INFO] generating key: rsa-2048
2020/10/17 15:33:58 [INFO] encoded CSR
2020/10/17 15:33:58 [INFO] signed certificate with serial number 237832953223916742008695684817534737514975537687
2020/10/17 15:33:58 [WARNING] This certificate lacks a "hosts" field. This makes it unsuitable for
websites. For more information see the Baseline Requirements for the Issuance and Management
of Publicly-Trusted Certificates, v.1.1.6, from the CA/Browser Forum (https://cabforum.org);
specifically, section 10.2.3 ("Information Requirements").
```

生成文件如下：

```bash
$ ls ca* server* | xargs -n1
ca.csr # CA 证书请求
ca-key.pem # CA 私钥
ca.pem # CA 证书
server.csr # etcd 证书请求
server-key.pem # etcd 私钥
server.pem # etcd 证书
```

将私钥与证书移动到 ETCD 的证书目录：

```bash
$ cp *.pem /opt/apps/etcd/ssl/
$ ls /opt/apps/etcd/ssl/
ca-key.pem  ca.pem  server-key.pem  server.pem
```

## K8S 组件证书

### 准备文件

```bash
$ tree
.
├── generate_cert.sh
└── json_file
    ├── admin-csr.json
    ├── ca-config.json
    ├── ca-csr.json
    ├── kube-proxy-csr.json
    └── server-csr.json
```

上述几个文件的内容分别如下（标 '*' 的文件名表示该文件内容你要根据你的环境进行修改）：

- `generate_cert.sh`：

```bash
cfssl gencert -initca json_file/ca-csr.json | cfssl-json -bare ca -
cfssl gencert -ca=ca.pem -ca-key=ca-key.pem -config=json_file/ca-config.json -profile=kubernetes json_file/server-csr.json | cfssl-json -bare server
cfssl gencert -ca=ca.pem -ca-key=ca-key.pem -config=json_file/ca-config.json -profile=kubernetes json_file/admin-csr.json | cfssl-json -bare admin
cfssl gencert -ca=ca.pem -ca-key=ca-key.pem -config=json_file/ca-config.json -profile=kubernetes json_file/kube-proxy-csr.json | cfssl-json -bare kube-proxy
```

- `json_file/admin-csr.json`：

```json
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
```

- `json_file/ca-config.json`：

```json
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
```

- `json_file/ca-csr.json`：

```json
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
```

- `json_file/kube-proxy-csr.json`：

```json
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
```

- `json_file/server-csr.json`*：

```json
{
    "CN": "kubernetes",
    "hosts": [
      "10.0.0.1",
      "127.0.0.1",
      "kubernetes",
      "kubernetes.default",
      "kubernetes.default.svc",
      "kubernetes.default.svc.cluster",
      "kubernetes.default.svc.cluster.local",
          "192.168.0.180",
          "192.168.0.181",
          "192.168.0.182",
          "192.168.0.185",
          "192.168.0.186",
          "192.168.0.187"
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
```

> 此处 `hosts` 列表要添加上所有可能作为 `kube-apiserver` 与其它节点进行通信的 IP，可以多写一些为扩容 Master 节点做准备。不需要写 Node 节点 IP，当然，就算把集群中所有节点都写上也无所谓，能多不能少。

### 颁发证书

这里直接执行一下 `generate_cert.sh` 即可，该文件会在当前目录自签一套 CA 证书并基于这个 CA 为 `kube-proxy` 和 `kube-apiserver` 各签发一套证书，如下：

```bash
$ ./generate_cert.sh 
2020/10/17 19:27:11 [INFO] generating a new CA key and certificate from CSR
2020/10/17 19:27:11 [INFO] generate received request
2020/10/17 19:27:11 [INFO] received CSR
2020/10/17 19:27:11 [INFO] generating key: rsa-2048
2020/10/17 19:27:11 [INFO] encoded CSR
2020/10/17 19:27:11 [INFO] signed certificate with serial number 641830844433546780183324661463441167399431570104
2020/10/17 19:27:11 [INFO] generate received request
2020/10/17 19:27:11 [INFO] received CSR
2020/10/17 19:27:11 [INFO] generating key: rsa-2048
2020/10/17 19:27:11 [INFO] encoded CSR
2020/10/17 19:27:11 [INFO] signed certificate with serial number 719580435123938571279291463694541983597634532906
2020/10/17 19:27:11 [WARNING] This certificate lacks a "hosts" field. This makes it unsuitable for
websites. For more information see the Baseline Requirements for the Issuance and Management
of Publicly-Trusted Certificates, v.1.1.6, from the CA/Browser Forum (https://cabforum.org);
specifically, section 10.2.3 ("Information Requirements").
2020/10/17 19:27:11 [INFO] generate received request
2020/10/17 19:27:11 [INFO] received CSR
2020/10/17 19:27:11 [INFO] generating key: rsa-2048
2020/10/17 19:27:12 [INFO] encoded CSR
2020/10/17 19:27:12 [INFO] signed certificate with serial number 466588837195544706605285763981212689199127751757
2020/10/17 19:27:12 [WARNING] This certificate lacks a "hosts" field. This makes it unsuitable for
websites. For more information see the Baseline Requirements for the Issuance and Management
of Publicly-Trusted Certificates, v.1.1.6, from the CA/Browser Forum (https://cabforum.org);
specifically, section 10.2.3 ("Information Requirements").
```

生成文件如下：

```bash
$ ls *.pem *.csr | xargs -n1
ca.csr # CA 证书请求
ca-key.pem # CA 私钥
ca.pem # CA 证书
kube-proxy.csr # kube-proxy 证书请求
kube-proxy-key.pem # kube-proxy 私钥
kube-proxy.pem # kube-proxy 证书
server.csr # API Server 证书请求
server-key.pem # API Server 私钥
server.pem # API Server 证书
```

将除 `kube-proxy` 的私钥与证书移动到 Kubernetes 的证书目录：

```bash
$ cp ca*.pem server*.pem /opt/apps/kubernetes/ssl/
$ ls /opt/apps/kubernetes/ssl/
ca-key.pem  ca.pem  server-key.pem  server.pem
```

# ETCD 部署

> 下面操作在 `k8s01`、`k8s03`、`k8s04` 中进行：

按如上规划，我这里 ETCD 将在 `k8s01`、`k8s03`、`k8s04` 这三台主机部署，将下载好的 ETCD 二进制包分发到这几个主机并解压：

```bash
$ tar xf etcd-v3.4.13-linux-amd64.tar.gz 
$ ls etcd-v3.4.13-linux-amd64/
Documentation  etcd  etcdctl  README-etcdctl.md  README.md  READMEv2-etcdctl.md
```

将二进制包移动到 `bin` 目录下：

```bash
$ mkdir -p /opt/apps/etcd/
$ mv etcd-v3.4.13-linux-amd64/{etcd,etcdctl} /opt/apps/etcd/bin/
```

## 配置

创建 ETCD 的配置文件，以 `k8s01` 为例内容如下：

```bash
$ cat /opt/apps/etcd/conf/etcd.conf 
#[Member]
# 节点名称，唯一
ETCD_NAME="etcd-1"
# 数据目录
ETCD_DATA_DIR="/opt/apps/etcd/data/default.etcd"
# 集群内部通信监听的地址
ETCD_LISTEN_PEER_URLS="https://192.168.0.181:2380"
# 与客户端通信监听的地址
ETCD_LISTEN_CLIENT_URLS="https://192.168.0.181:2379"

#[Clustering]
# 对外公告的该节点集群内监听地址
ETCD_INITIAL_ADVERTISE_PEER_URLS="https://192.168.0.181:2380"
# 对外公告的该节点客户端监听地址
ETCD_ADVERTISE_CLIENT_URLS="https://192.168.0.181:2379"
# 集群所有成员
ETCD_INITIAL_CLUSTER="etcd-1=https://192.168.0.181:2380,etcd-2=https://192.168.0.183:2380,etcd-3=https://192.168.0.184:2380"
# 通信 Token（密钥），可自行修改
ETCD_INITIAL_CLUSTER_TOKEN="etcd-cluster"
# 标识是创建新的集群，加入已有的集群设为 exist
ETCD_INITIAL_CLUSTER_STATE="new"
```

> 在 `k8s03`、`k8s04` 节点该配置中的 `ETCD_LISTEN_PEER_URLS`、`ETCD_LISTEN_CLIENT_URLS`、`ETCD_INITIAL_ADVERTISE_PEER_URLS`、`ETCD_ADVERTISE_CLIENT_URLS` 值要修改为对应节点的本机地址。

## Systemd 管理

创建 ETCD 的 Systemd service 文件：

```bash
$ cat /usr/lib/systemd/system/etcd.service 
[Unit]
Description=Etcd Server
After=network.target
After=network-online.target
Wants=network-online.target

[Service]
Type=notify
EnvironmentFile=/opt/apps/etcd/conf/etcd.conf
ExecStart=/opt/apps/etcd/bin/etcd \
        --cert-file=/opt/apps/etcd/ssl/server.pem \
        --key-file=/opt/apps/etcd/ssl/server-key.pem \
        --peer-cert-file=/opt/apps/etcd/ssl/server.pem \
        --peer-key-file=/opt/apps/etcd/ssl/server-key.pem \
        --trusted-ca-file=/opt/apps/etcd/ssl/ca.pem \
        --peer-trusted-ca-file=/opt/apps/etcd/ssl/ca.pem
Restart=on-failure
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
```

> 注意：我这里使用的 ETCD 版本为 `3.4+`，它会自动读取环境变量的配置，所以设置了 `EnvironmentFile` 即可，不需要额外通过选项引用配置文件中的参数，比如像之前的版本需要这样配置：
>
> ```bash
> ...
> ExecStart=/opt/apps/etcd/bin/etcd \
>      --name=${ETCD_NAME} \
>      --data-dir=${ETCD_DATA_DIR} \
>      --listen-peer-urls=${ETCD_LISTEN_PEER_URLS} \
>      --listen-client-urls=${ETCD_LISTEN_CLIENT_URLS},http://127.0.0.1:2379 \
>      --advertise-client-urls=${ETCD_ADVERTISE_CLIENT_URLS} \
>      --initial-advertise-peer-urls=${ETCD_INITIAL_ADVERTISE_PEER_URLS} \
>      --initial-cluster=${ETCD_INITIAL_CLUSTER} \
>      --initial-cluster-token=${ETCD_INITIAL_CLUSTER_TOKEN} \
>      --initial-cluster-state=new \
>      --cert-file=/opt/apps/etcd/ssl/server.pem \
>      --key-file=/opt/apps/etcd/ssl/server-key.pem \
>      --peer-cert-file=/opt/apps/etcd/ssl/server.pem \
>      --peer-key-file=/opt/apps/etcd/ssl/server-key.pem \
>      --trusted-ca-file=/opt/apps/etcd/ssl/ca.pem \
>      --peer-trusted-ca-file=/opt/apps/etcd/ssl/ca.pem
> ...
> ```
>
> 下面再对上面几个重要的参数进行说明：
>
> - `--peer-trusted-ca-file`：由于这里我们使用的是自建的 CA，所以需要手动指定它可信任；
> - `--peer-cert-file` 和 `--peer-key-file`：指定 ETCD 集群内部通信需要的证书和私钥；
> - `--cert-file` 和 `--key-file`：指定 ETCD 客户端和 ETCD 集群通信使用的证书和私钥；

## 启动检查

分别在 `k8s01`、`k8s03`、`k8s04` 这几个节点启动 ETCD 服务并加入开机自启：

```bash
$ systemctl daemon-reload
$ systemctl start etcd
$ systemctl enable etcd
```

检查 ETCD 集群健康状态，输出内容如下则说明 ETCD 集群正常：

```bash
$ /opt/apps/etcd/bin/etcdctl \
--endpoints="https://192.168.5.140:2379,https://192.168.5.144:2379,https://192.168.5.142:2379" \
--cacert=/opt/apps/etcd/ssl/ca.pem \
--key=/opt/apps/etcd/ssl/server-key.pem  \
--cert=/opt/apps/etcd/ssl/server.pem  \
endpoint health 
https://192.168.0.181:2379 is healthy: successfully committed proposal: took = 31.353402ms
https://192.168.0.184:2379 is healthy: successfully committed proposal: took = 35.075302ms
https://192.168.0.183:2379 is healthy: successfully committed proposal: took = 35.262771ms
```

# Kubernetes Master 组件部署

> 下面操作在 `k8s01` 上进行。

解压压缩包并移动几个二进制程序到安装目录：

```bash
$ tar xf kubernetes-server-linux-amd64.tar.gz
$ ls kubernetes/server/bin/
apiextensions-apiserver  kube-apiserver             kube-controller-manager             kubectl     kube-proxy.docker_tag  kube-scheduler.docker_tag
kubeadm                  kube-apiserver.docker_tag  kube-controller-manager.docker_tag  kubelet     kube-proxy.tar         kube-scheduler.tar
kube-aggregator          kube-apiserver.tar         kube-controller-manager.tar         kube-proxy  kube-scheduler         mounter
$ mv kubernetes/server/bin/{kube-apiserver,kube-controller-manager,kubectl,kube-scheduler} /opt/apps/kubernetes/bin/
```

将 `kubectl` 链接到 `$PATH` 包含的路径下：

```bash
$ ln -s /opt/apps/kubernetes/bin/kubectl /usr/local/bin/
```

## 配置

创建 `kube-apiserver` 的配置文件：

```bash
$ cat /opt/apps/kubernetes/conf/kube-apiserver.conf 
KUBE_APISERVER_OPTS="--logtostderr=false \
--v=2 \
--log-dir=/opt/apps/kubernetes/log \
--etcd-servers=https://192.168.0.181:2379,https://192.168.0.183:2379,https://192.168.0.184:2379 \
--bind-address=192.168.0.181 \
--secure-port=6443 \
--advertise-address=192.168.0.181 \
--allow-privileged=true \
--service-cluster-ip-range=10.0.0.0/24 \
--enable-admission-plugins=NamespaceLifecycle,LimitRanger,ServiceAccount,ResourceQuota,NodeRestriction \
--authorization-mode=RBAC,Node \
--enable-bootstrap-token-auth=true \
--token-auth-file=/opt/apps/kubernetes/conf/token.csv \
--service-node-port-range=30000-32767 \
--kubelet-client-certificate=/opt/apps/kubernetes/ssl/server.pem \
--kubelet-client-key=/opt/apps/kubernetes/ssl/server-key.pem \
--tls-cert-file=/opt/apps/kubernetes/ssl/server.pem  \
--tls-private-key-file=/opt/apps/kubernetes/ssl/server-key.pem \
--client-ca-file=/opt/apps/kubernetes/ssl/ca.pem \
--service-account-key-file=/opt/apps/kubernetes/ssl/ca-key.pem \
--etcd-cafile=/opt/apps/etcd/ssl/ca.pem \
--etcd-certfile=/opt/apps/etcd/ssl/server.pem \
--etcd-keyfile=/opt/apps/etcd/ssl/server-key.pem \
--audit-log-maxage=30 \
--audit-log-maxbackup=3 \
--audit-log-maxsize=100 \
--audit-log-path=/opt/apps/kubernetes/log/k8s-audit.log"
```

创建 Node 认证配置（上面的 `kube-apiserver` 配置中 `--token-auth-file` 依赖此文件）：

```bash
$ cat /opt/apps/kubernetes/conf/token.csv 
8fba966b6e3b5d182960a30f6cb94428,kubelet-bootstrap,10001,"system:node-bootstrapper"
```

创建 `kube-controller-manager` 的配置文件：

```bash
$ cat /opt/apps/kubernetes/conf/kube-controller-manager.conf 
KUBE_CONTROLLER_MANAGER_OPTS="--logtostderr=false \
--v=2 \
--log-dir=/opt/apps/kubernetes/log \
--leader-elect=true \
--master=127.0.0.1:8080 \
--address=127.0.0.1 \
--allocate-node-cidrs=true \
--cluster-cidr=10.244.0.0/16 \
--service-cluster-ip-range=10.0.0.0/24 \
--cluster-signing-cert-file=/opt/apps/kubernetes/ssl/ca.pem \
--cluster-signing-key-file=/opt/apps/kubernetes/ssl/ca-key.pem  \
--root-ca-file=/opt/apps/kubernetes/ssl/ca.pem \
--service-account-private-key-file=/opt/apps/kubernetes/ssl/ca-key.pem \
--experimental-cluster-signing-duration=87600h0m0s"
```

创建 `kube-scheduler` 的配置文件：

```bash
$ cat /opt/apps/kubernetes/conf/kube-scheduler.conf 
KUBE_SCHEDULER_OPTS="--logtostderr=false \
--v=2 \
--log-dir=/opt/apps/kubernetes/log \
--leader-elect \
--master=127.0.0.1:8080 \
--address=127.0.0.1"
```

## Systemd 管理

创建 `kube-apiserver` 的 Systemd service 文件：

```bash
$ cat /usr/lib/systemd/system/kube-apiserver.service
[Unit]
Description=Kubernetes API Server
Documentation=https://github.com/kubernetes/kubernetes

[Service]
EnvironmentFile=/opt/apps/kubernetes/conf/kube-apiserver.conf
ExecStart=/opt/apps/kubernetes/bin/kube-apiserver $KUBE_APISERVER_OPTS
Restart=on-failure

[Install]
WantedBy=multi-user.target
```

创建 `kube-controller-manager` 的 Systemd service 文件：

```bash
$ cat /usr/lib/systemd/system/kube-controller-manager.service 
[Unit]
Description=Kubernetes Controller Manager
Documentation=https://github.com/kubernetes/kubernetes

[Service]
EnvironmentFile=/opt/apps/kubernetes/conf/kube-controller-manager.conf
ExecStart=/opt/apps/kubernetes/bin/kube-controller-manager $KUBE_CONTROLLER_MANAGER_OPTS
Restart=on-failure

[Install]
WantedBy=multi-user.target
```

创建 `kube-controller-manager` 的 Systemd service 文件

```bash
$ cat /usr/lib/systemd/system/kube-scheduler.service 
[Unit]
Description=Kubernetes Scheduler
Documentation=https://github.com/kubernetes/kubernetes

[Service]
EnvironmentFile=/opt/apps/kubernetes/conf/kube-scheduler.conf
ExecStart=/opt/apps/kubernetes/bin/kube-scheduler $KUBE_SCHEDULER_OPTS
Restart=on-failure

[Install]
WantedBy=multi-user.target
```

## 启动检查

启动并设置开机自启：

```bash
$ systemctl start kube-apiserver.service kube-controller-manager.service kube-scheduler.service 
$ systemctl enable kube-apiserver.service kube-controller-manager.service kube-scheduler.service 
Created symlink from /etc/systemd/system/multi-user.target.wants/kube-apiserver.service to /usr/lib/systemd/system/kube-apiserver.service.
Created symlink from /etc/systemd/system/multi-user.target.wants/kube-controller-manager.service to /usr/lib/systemd/system/kube-controller-manager.service.
Created symlink from /etc/systemd/system/multi-user.target.wants/kube-scheduler.service to /usr/lib/systemd/system/kube-scheduler.service.
```

检查日志目录是否生成了 `kube-apiserver`、`kube-controller-manager` 和 `kube-scheduler` 的日志文件：

```bash
$ ls /opt/apps/kubernetes/log/
kube-apiserver.ERROR                                      kube-apiserver.k8s01.root.log.INFO.20201017-202658.4811            kube-controller-manager.k8s01.root.log.WARNING.20201017-203149.5031
kube-apiserver.INFO                                       kube-apiserver.k8s01.root.log.INFO.20201017-202745.4871            kube-controller-manager.WARNING
kube-apiserver.k8s01.root.log.ERROR.20201017-202752.4871  kube-apiserver.k8s01.root.log.WARNING.20201017-202748.4871         kube-scheduler.INFO
kube-apiserver.k8s01.root.log.INFO.20201017-202452.4698   kube-apiserver.WARNING                                             kube-scheduler.k8s01.root.log.INFO.20201017-203317.5075
kube-apiserver.k8s01.root.log.INFO.20201017-202454.4707   kube-controller-manager.ERROR                                      kube-scheduler.k8s01.root.log.WARNING.20201017-203319.5075
kube-apiserver.k8s01.root.log.INFO.20201017-202455.4714   kube-controller-manager.INFO                                       kube-scheduler.WARNING
kube-apiserver.k8s01.root.log.INFO.20201017-202456.4722   kube-controller-manager.k8s01.root.log.ERROR.20201017-203200.5031
kube-apiserver.k8s01.root.log.INFO.20201017-202458.4736   kube-controller-manager.k8s01.root.log.INFO.20201017-203147.5031
```

检查组件状态：

```bash
$ kubectl get cs
Warning: v1 ComponentStatus is deprecated in v1.19+
NAME                 STATUS    MESSAGE             ERROR
scheduler            Healthy   ok                  
controller-manager   Healthy   ok                  
etcd-1               Healthy   {"health":"true"}   
etcd-0               Healthy   {"health":"true"}   
etcd-2               Healthy   {"health":"true"} 
```

## 启用 TLS Bootstrapping

TLS Bootstrapping 机制的作用就是让 Node 中的 `kubelet` 启动时能自动向 `kube-apiserver` 发起申请为 `kubelet` 颁发证书，它在启动 `kube-apiserver` 是通过 `--enable-bootstrap-token-auth=true` 选项来启用，在上面已经启用了。然后可通过 `--token-auth-file` 来指定一个认证配置，也就是上面添加的 `/opt/apps/kubernetes/conf/token.csv` 文件，其内容如下：

```bash
$ cat /opt/apps/kubernetes/conf/token.csv 
8fba966b6e3b5d182960a30f6cb94428,kubelet-bootstrap,10001,"system:node-bootstrapper"
```

其中各列的含义如下：

- `8fba966b6e3b5d182960a30f6cb94428`：认证 Token，该 Token 可通过 `head -c 16 /dev/urandom | od -An -t x | tr -d ' '` 自行生成，但 API Server 中配置的 Token 必须要与 Node 节点的 `/opt/apps/kubernetes/conf/bootstrap.kubeconfig` 配置里一致；
- `kubelet-bootstrap`：用户；
- `10001`：UID；
- `"system:node-bootstrapper"`：组；

此时我们虽然已经启用了 TLS Bootstrapping，但 `kubelet-bootstrap` 目前还是没有任何权限的，此时我们需要给它手动授权一下，将它绑定到内置的集群角色 `system:node-bootstrapper` 即可，操作如下：

```bash
$ kubectl create clusterrolebinding kubelet-bootstrap \
--clusterrole=system:node-bootstrapper \
--user=kubelet-bootstrap
```

# Docker 部署

> 在 `k8s03`、`k8s04`、`k8s05`、`k8s06` 上部署 Docker，其实我们仅需在 Node 节点部署 Docker，只不过我打算在 LB 节点使用 Docker 来跑 Nginx 和 Keepalived。

分发 Docker 二进制压缩包到 Node 节点，解压如下：

```bash
$ tar xf docker-19.03.9.tgz 
$ ls docker
containerd  containerd-shim  ctr  docker  dockerd  docker-init  docker-proxy  runc
```

将二进制程序放到 Docker 的安装目录并链接到 `$PATH` 包含的目录下：

```bash
$ mv docker/* /opt/apps/docker/bin/
$ find /opt/apps/docker/bin/ -type f | xargs -i ln -s {} /usr/local/bin/
```

## 配置

创建 Docker 的配置文件：

```bash
$ cat /opt/apps/docker/conf/daemon.json
{
  "registry-mirrors": ["https://7hsct51i.mirror.aliyuncs.com"],
  "log-driver":"json-file",
  "log-opts": {"max-size":"500m", "max-file":"3"},
  "insecure-registries": ["192.168.0.186"]
}
```

## Systemd 管理

创建 Docker 的 Systemd service 文件：

```bash
$ cat /usr/lib/systemd/system/docker.service
[Unit]
Description=Docker Application Container Engine
Documentation=https://docs.docker.com
After=network-online.target firewalld.service containerd.service
Wants=network-online.target

[Service]
Type=notify
ExecStart=/opt/apps/docker/bin/dockerd \
  --config-file /opt/apps/docker/conf/daemon.json \
  --data-root /opt/apps/docker/data
ExecReload=/bin/kill -s HUP $MAINPID
TimeoutSec=0
RestartSec=2
Restart=always
StartLimitBurst=3
StartLimitInterval=60s
LimitNOFILE=infinity
LimitNPROC=infinity
LimitCORE=infinity
TasksMax=infinity
Delegate=yes
KillMode=process

[Install]
WantedBy=multi-user.target
```

## 启动检查

启动 Docker 并设置开机自启：

```bash
$ systemctl start docker 
$ systemctl enable docker
```

检查数据目录如果正常生成数据则说明 Docker 运行正常：

```undefined
$ ls /opt/apps/docker/data
builder  buildkit  containerd  containers  image  network  overlay2  plugins  runtimes  swarm  tmp  trust  volumes
```

# Kubernetes Node 组件部署

> 下面操作先在 `k8s03` 上进行，没问题的话再在 `k8s04` 上进行。

Kubernetes Node 节点上除了要部署 Docker，还需要的 Kubernetes 组件有 `kubelet` 和 `kube-proxy`，这两个二进制程序在部署 Kubernetes Master 节点时解压的 `kubernetes-server-linux-amd64.tar.gz` 中已经存在，在解压后的 `kubernetes/server/bin/` 目录下，将它们拷贝到两个 Kubernetes Node 节点的 Kubernetes 安装目录：

```bash
$ scp kubernetes/server/bin/{kubelet,kube-proxy} k8s03:/opt/apps/kubernetes/bin
$ scp kubernetes/server/bin/{kubelet,kube-proxy} k8s04:/opt/apps/kubernetes/bin
```

## 分发证书

由于 Kubernetes Node 端的 `kubelet` 和 `kube-proxy` 是要与 API Server 进行通信的，所以需要将之前生成的 `ca.pem` 、 `kube-proxy.pem` 和 `kube-proxy-key.pem` 拷贝到 kubernetes Node 端，如下：

```bash
$ scp ca.pem kube-proxy*.pem k8s03:/opt/apps/kubernetes/ssl
```

所以在 Kubernetes Node 端查看证书文件有如下：

```bash
$ ls /opt/apps/kubernetes/ssl/
ca.pem  kube-proxy-key.pem  kube-proxy.pem
```

## 配置

创建 `kubelet` 用于 TLS Bootstrapping 的认证配置文件：

```bash
$ cat /opt/apps/kubernetes/conf/bootstrap.kubeconfig 
apiVersion: v1
clusters:
- cluster:
    certificate-authority: /opt/apps/kubernetes/ssl/ca.pem
    server: https://192.168.0.181:6443
  name: kubernetes
contexts:
- context:
    cluster: kubernetes
    user: kubelet-bootstrap
  name: default
current-context: default
kind: Config
preferences: {}
users:
- name: kubelet-bootstrap
  user:
    token: 8fba966b6e3b5d182960a30f6cb94428
```

创建 `kubelet` 的资源型配置的 YAML 文件：

```bash
$ cat /opt/apps/kubernetes/conf/kubelet-config.yml 
kind: KubeletConfiguration
apiVersion: kubelet.config.k8s.io/v1beta1
address: 0.0.0.0
port: 10250
readOnlyPort: 10255
cgroupDriver: cgroupfs
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
    clientCAFile: /opt/apps/kubernetes/ssl/ca.pem 
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
```

创建 `kubelet` 的启动配置文件：

```bash
$ cat /opt/apps/kubernetes/conf/kubelet.conf
KUBELET_OPTS="--logtostderr=false \
--v=4 \
--log-dir=/opt/apps/kubernetes/log \
--hostname-override=k8s-node1 \
--network-plugin=cni \
--cni-bin-dir=/opt/apps/cni/bin \
--cni-conf-dir=/opt/apps/cni/conf \
--kubeconfig=/opt/apps/kubernetes/conf/kubelet.kubeconfig \
--bootstrap-kubeconfig=/opt/apps/kubernetes/conf/bootstrap.kubeconfig \
--config=/opt/apps/kubernetes/conf/kubelet-config.yml \
--cert-dir=/opt/apps/kubernetes/ssl \
--pod-infra-container-image=registry.cn-shenzhen.aliyuncs.com/zze/pause:3.2"
```

> 注意这里的 `--hostname-override` 在不同的 Kubernetes Node 上是不同的。

创建 `kube-proxy` 与 `kube-apiserver` 通信的认证配置文件：

```bash
$ cat /opt/apps/kubernetes/conf/kube-proxy.kubeconfig
apiVersion: v1
clusters:
- cluster:
    certificate-authority: /opt/apps/kubernetes/ssl/ca.pem
    server: https://192.168.0.181:6443
  name: kubernetes
contexts:
- context:
    cluster: kubernetes
    user: kube-proxy
  name: default
current-context: default
kind: Config
preferences: {}
users:
- name: kube-proxy
  user:
    client-certificate: /opt/apps/kubernetes/ssl/kube-proxy.pem
    client-key: /opt/apps/kubernetes/ssl/kube-proxy-key.pem
```

创建 `kube-proxy` 的资源型配置的 YAML 文件：

```bash
$ cat /opt/apps/kubernetes/conf/kube-proxy-config.yml
kind: KubeProxyConfiguration
apiVersion: kubeproxy.config.k8s.io/v1alpha1
address: 0.0.0.0
metricsBindAddress: 0.0.0.0:10249
clientConnection:
  kubeconfig: /opt/apps/kubernetes/conf/kube-proxy.kubeconfig
hostnameOverride: k8s-node1
clusterCIDR: 10.0.0.0/24
mode: ipvs
ipvs:
  scheduler: "rr"
iptables:
  masqueradeAll: false
```

> 注意这里的 `hostnameOverride` 在不同的 Kubernetes Node 上是不同的。

创建 `kube-proxy` 的启动配置文件：

```bash
$ cat  kube-proxy.conf
KUBE_PROXY_OPTS="--logtostderr=false \
--v=4 \
--log-dir=/opt/apps/kubernetes/log \
--config=/opt/apps/kubernetes/conf/kube-proxy-config.yml"
```

## Systemd 管理

创建 `kubelet` 的 Systemd service 文件：

```bash
$ cat /usr/lib/systemd/system/kubelet.service 
[Unit]
Description=Kubernetes Kubelet
After=docker.service
Before=docker.service

[Service]
EnvironmentFile=/opt/apps/kubernetes/conf/kubelet.conf
ExecStart=/opt/apps/kubernetes/bin/kubelet $KUBELET_OPTS
Restart=on-failure
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
```

创建 `kube-proxy` 的 Systemd service 文件：

```bash
$ cat /usr/lib/systemd/system/kube-proxy.service 
[Unit]
Description=Kubernetes Proxy
After=network.target

[Service]
EnvironmentFile=/opt/apps/kubernetes/conf/kube-proxy.conf
ExecStart=/opt/apps/kubernetes/bin/kube-proxy $KUBE_PROXY_OPTS
Restart=on-failure
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
```

## 启动检查

启动 `kubelet` 并设置开机自启：

```bash
$ systemctl start kubelet.service
$ systemctl enable kubelet.service
```

由于在前面我们启用了 TLS Bootstrapping，所以这里 `kubelet` 启动时能自动向 kube-apiserver 发起申请为 `kubelet` 颁发证书，我们需要切换到 Kubernetes Master 节点查看一下有没有接收到申请：

```bash
$ kubectl get csr
NAME                                                   AGE   SIGNERNAME                                    REQUESTOR           CONDITION
node-csr-d2QVCXjnkseslo6USNRVyRaIkX_tmSNa6618GWWKIRo   10m   kubernetes.io/kube-apiserver-client-kubelet   kubelet-bootstrap   Pending
```

可以看到已经接收到了证书签发申请，然后需要执行下面命令来允许该证书申请：

```bash
$ kubectl certificate approve node-csr-d2QVCXjnkseslo6USNRVyRaIkX_tmSNa6618GWWKIRo
certificatesigningrequest.certificates.k8s.io/node-csr-d2QVCXjnkseslo6USNRVyRaIkX_tmSNa6618GWWKIRo approved
```

接下来就可以查看到新加入的节点了：

```bash
$ kubectl get node
NAME        STATUS     ROLES    AGE     VERSION
k8s-node1   NotReady   <none>   2m55s   v1.19.0
```

检查 Kubernetes Node 节点的证书目录会发现自动为 `kubelet` 颁发的证书文件：

```bash
$ ls /opt/apps/kubernetes/ssl/kubelet*
/opt/apps/kubernetes/ssl/kubelet-client-2020-10-18-13-05-28.pem  /opt/apps/kubernetes/ssl/kubelet-client-current.pem  /opt/apps/kubernetes/ssl/kubelet.crt  /opt/apps/kubernetes/ssl/kubelet.key
```

检查 Kubernetes Node 节点的配置目录会发现自动为 `kubelet` 生成了与 `kube-apiserver` 通信的认证配置文件：

```bash
$ cat /opt/apps/kubernetes/conf/kubelet.kubeconfig 
apiVersion: v1
clusters:
- cluster:
    certificate-authority: /opt/apps/kubernetes/ssl/ca.pem
    server: https://192.168.0.181:6443
  name: default-cluster
contexts:
- context:
    cluster: default-cluster
    namespace: default
    user: default-auth
  name: default-context
current-context: default-context
kind: Config
preferences: {}
users:
- name: default-auth
  user:
    client-certificate: /opt/apps/kubernetes/ssl/kubelet-client-current.pem
    client-key: /opt/apps/kubernetes/ssl/kubelet-client-current.pem
```

启动 `kube-proxy` 并设置开机自启：

```bash
$ systemctl start kube-proxy.service
$ systemctl enable kube-proxy.service
```

查看 `kube-proxy` 的状态：

```bash
$ systemctl  status kube-proxy
● kube-proxy.service - Kubernetes Proxy
   Loaded: loaded (/usr/lib/systemd/system/kube-proxy.service; disabled; vendor preset: disabled)
   Active: active (running) since Sun 2020-10-18 13:11:06 CST; 10min ago
 Main PID: 27944 (kube-proxy)
    Tasks: 8
   Memory: 20.2M
   CGroup: /system.slice/kube-proxy.service
           └─27944 /opt/apps/kubernetes/bin/kube-proxy --logtostderr=false --v=4 --log-dir=/opt/apps/kubernetes/log --config=/opt/apps/kubernetes/conf/kube-proxy-config.yml

Oct 18 13:11:06 k8s03 systemd[1]: Started Kubernetes Proxy.
Oct 18 13:11:06 k8s03 kube-proxy[27944]: E1018 13:11:06.564315   27944 proxier.go:381] can't set sysctl net/ipv4/vs/conn_reuse_mode, kernel version must be at least 4.1
```

> 此处如果出现了 `can't set sysctl net/ipv4/vs/conn_reuse_mode, kernel version must be at least 4.1` 这个报错则可参考【 [CentOS 7 升级内核版本到最新](https://www.zze.xyz/archives/linux-update-kernel.html)】来升级内核版本。
>
> 注意：在部署一个新 Node 时，如果直接拷贝已有的 Kubernetes Node 节点的 `/opt/apps/kubernetes` 目录到新 Node 节点，则在新 Node 上需要删除原来生成的 `kubelet` 认证文件和证书文件，然后启动才可正常向 `kube-apiserver` 发出证书申请。
>
> 要删除的几个文件如下：
>
> ```bash
> # 删除 kubelet 认证文件
> $ rm -f /opt/apps/kubernetes/conf/kubelet.kubeconfig 
> # 删除 kubelet 证书文件
> $ rm -f /opt/apps/kubernetes/ssl/kubelet*
> # 最好还清空一下日志目录
> $ rm -f /opt/apps/kubernetes/log/*
> ```

# CNI 网络插件部署

> CNI（Contaniner Network Interface）网络插件需要所有 Kubernetes Node 节点部署，因为 `kubelet` 和 `kube-proxy` 需要它。

创建 CNI 的程序目录和配置目录：

```bash
$ mkdir -p /opt/apps/cni/{bin,conf}
```

解压下载好的压缩包到程序目录：

```bash
$ tar xf cni-plugins-linux-amd64-v0.8.7.tgz -C /opt/apps/cni/bin
```

> 这里要确保 `kubelet` 启动时指定了 `--network-plugin=cni`，上面我在 `/opt/apps/kubernetes/conf/kubelet.conf` 中已经指定了。

到这里 CNI 网络查件本身其实只部署完成一部分，因为这里的 CNI 它其实是类似编程语言中的一个接口定义了网络插件的规范，但具体的实现它并没有做，第三方的实现常见的有 Flannel 和 Cakico、Canal 和 Weave 等，这里我们就使用最常用的 Flannel 了。

> 官方文档对 CNI 也做了介绍，地址：https://kubernetes.io/zh/docs/concepts/cluster-administration/networking/。

## Flannel 部署

Flannel 的部署很简单，直接在 Kubernetes Master 节点上执行下面命令即可：

```bash
$ kubectl apply -f https://raw.githubusercontent.com/coreos/flannel/master/Documentation/kube-flannel.yml
```

但是！由于这里使用的镜像地址在国外，所以拉取的时候很慢甚至无法拉取成功，所以我把它丢到了阿里云镜像仓库一份，然后你可以先下载下来这个 YAML 文件，然后修改里面的镜像地址后再进行部署，如下：

```bash
$ wget https://raw.githubusercontent.com/coreos/flannel/master/Documentation/kube-flannel.yml
$ sed -i -r 's#(\s)(image:.*$)#\1image: registry.cn-shenzhen.aliyuncs.com/zze/flannel:v0.13.0#' kube-flannel.yml
$ kubectl apply -f kube-flannel.yml
```

要注意的是，`kube-flannel.yml` 中的名为 `kube-flannel-cfg` 的 `ConfigMap` 中的名为 `net-conf.json` 的键对应的值中的 `Network` 字段值需要与 Kubernetes Master 节点中的 `/opt/apps/kubernetes/conf/kube-controller-manager.conf` 配置中 `--cluster-cidr` 选项指定的值一致，`kube-flannel.yml` 中默认为 `10.244.0.0/16`，如下：

```bash
$ cat kube-flannel.yml | grep '"Network":'
      "Network": "10.244.0.0/16",
```

我这里 `/opt/apps/kubernetes/conf/kube-controller-manager.conf` 中的值也是，如下：

```bash
$ cat /opt/apps/kubernetes/conf/kube-controller-manager.conf | grep 'cluster-cidr'
--cluster-cidr=10.244.0.0/16 \
```

还有一处要注意的地方是我在上面 Kubelet 配置文件中修改了 CNI 配置文件默认的位置为 `/opt/apps/cni/conf`，如下：

```bash
$ cat /opt/apps/kubernetes/conf/kubelet.conf | grep cni-conf-dir
--cni-conf-dir=/opt/apps/cni/conf \
```

而 Flannel 资源默认的配置文件目录是使用 hostPath 方式挂载到宿主机的 `/etc/cni/net.d` 目录，所以这里要修改它为 `/opt/apps/cni/conf`：

```bash
$ cat kube-flannel.yml | grep 'name: cni' -A 2 | grep path
          path: /opt/apps/cni/conf
```

执行部署操作后，运行成功效果如下：

```bash
$ kubectl get ds -n kube-system
NAME              DESIRED   CURRENT   READY   UP-TO-DATE   AVAILABLE   NODE SELECTOR   AGE
kube-flannel-ds   2         2         2       2            2           <none>          70s
# 要在所有 Kubernetes Node 中都解压 CNI 压缩包到安装目录，否则 STATUS 是不会处于 Ready 的
$ kubectl get node -o wide -n kube-system
NAME        STATUS   ROLES    AGE     VERSION   INTERNAL-IP     EXTERNAL-IP   OS-IMAGE                KERNEL-VERSION              CONTAINER-RUNTIME
k8s-node1   Ready    <none>   3h24m   v1.19.0   192.168.0.183   <none>        CentOS Linux 7 (Core)   5.9.1-1.el7.elrepo.x86_64   docker://19.3.9
k8s-node2   Ready    <none>   70m     v1.19.0   192.168.0.184   <none>        CentOS Linux 7 (Core)   5.9.1-1.el7.elrepo.x86_64   docker://19.3.9
```

## 用户授权

按理说到这一步网络插件应该可以正常工作了，但我这里有一个节点的 `flannel` 容器一直 `Error`，查看一下 `Pod` 状态：

```bash
$ kubectl get pod -n kube-system -o wide
NAME                    READY   STATUS        RESTARTS   AGE   IP              NODE        NOMINATED NODE   READINESS GATES
kube-flannel-ds-ccppl   1/1     Running       0          17m   192.168.0.184   k8s-node2   <none>           <none>
kube-flannel-ds-w4svb   1/1     Error         5          18m   192.168.0.183   k8s-node1   <none>           <none>
```

会发现 Pod 的状态是 `Error`，查看一下 Pod 日志：

```bash
$ kubectl -n kube-system logs kube-flannel-ds-kw2bh
Error from server (Forbidden): Forbidden (user=kubernetes, verb=get, resource=nodes, subresource=proxy) ( pods/log kube-flannel-ds-qc2tz)
```

这里提示权限拒绝了，这是因为我们默认使用的是 `kubernetes` 用户与 `kube-apiserver` 进行交互，而 `kubernetes` 用户默认是没有权限去查看 Pod 等资源的日志的，所以这里我们需要先为 `kubernetes` 用户授权：

```bash
$ cat kubernetes-user-log-rbac.yml
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  annotations:
    rbac.authorization.kubernetes.io/autoupdate: "true"
  labels:
    kubernetes.io/bootstrapping: rbac-defaults
  name: system:kube-apiserver-to-kubelet
rules:
  - apiGroups:
      - ""
    resources:
      - nodes/proxy
      - nodes/stats
      - nodes/log
      - nodes/spec
      - nodes/metrics
      - pods/log
    verbs:
      - "*"
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: system:kube-apiserver
  namespace: ""
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: system:kube-apiserver-to-kubelet
subjects:
  - apiGroup: rbac.authorization.k8s.io
    kind: User
    name: kubernetes
$ kubectl apply -f kubernetes-user-log-rbac.yml
clusterrole.rbac.authorization.k8s.io/system:kube-apiserver-to-kubelet created
clusterrolebinding.rbac.authorization.k8s.io/system:kube-apiserver created
```

再次查看日志：

```bash
$ kubectl -n kube-system logs kube-flannel-ds-kw2bh 
I1018 08:54:21.365194       1 main.go:518] Determining IP address of default interface
I1018 08:54:21.366752       1 main.go:531] Using interface with name eth0 and address 192.168.0.183
I1018 08:54:21.366802       1 main.go:548] Defaulting external address to interface address (192.168.0.183)
W1018 08:54:21.366874       1 client_config.go:517] Neither --kubeconfig nor --master was specified.  Using the inClusterConfig.  This might not work.
E1018 08:54:51.468436       1 main.go:243] Failed to create SubnetManager: error retrieving pod spec for 'kube-system/kube-flannel-ds-kw2bh': Get "https://10.0.0.1:443/api/v1/namespaces/kube-system/pods/kube-flannel-ds-kw2bh": dial tcp 10.0.0.1:443: i/o timeout
```

## 问题排查

从上面日志报出的问题可以看出是访问 `https://10.0.0.1:443/api/v1/namespaces/kube-system/pods/kube-flannel-ds-kw2bh` 的时候超时了，然后我就切换到报错的这个节点即 `k8s03` 主机，试着手动访问一下：

> 因为 Flannel 镜像使用的是宿主机的网络，所以理论上来说在宿主机上访问和容器里访问的效果是相同的。

```bash
$ curl --connect-timeout 10 https://10.0.0.1:443/api/v1/namespaces/kube-system/pods/kube-flannel-ds-kw2bh
curl: (28) Connection timed out after 10002 milliseconds
```

可以看到的确是超时的。。所以现在要找一下超时的原因了。

试着 `ping` 一下 `10.0.0.1`：

```bash
$ ping 10.0.0.1
PING 10.0.0.1 (10.0.0.1) 56(84) bytes of data.
64 bytes from 10.0.0.1: icmp_seq=1 ttl=64 time=0.138 ms
^C
--- 10.0.0.1 ping statistics ---
1 packets transmitted, 1 received, 0% packet loss, time 0ms
rtt min/avg/max/mdev = 0.138/0.138/0.138/0.000 ms
```

也是 OK 的，证明 `ping` 的 ICMP 数据包是可以正常来回的，但 `curl` HTTP 数据包就不知道了，但至少确定了不是 `10.0.0.1` 这个目标地址的问题。

现在只能抓一下包了，打开一个窗口，执行 `tcpdump -i eth0 host 10.0.0.1 -n` 进行监听，然后在另一个窗口执行 `curl https://10.0.0.1:443/api/v1/namespaces/kube-system/pods/kube-flannel-ds-kw2bh`，此时 `tcpdump` 抓取到的报文如下：

```bash
$ tcpdump -i eth0 host 10.0.0.1 -n 
tcpdump: verbose output suppressed, use -v or -vv for full protocol decode
listening on eth0, link-type EN10MB (Ethernet), capture size 262144 bytes
18:04:36.404311 IP 10.0.0.1.45998 > 192.168.0.181.sun-sr-https: Flags [S], seq 479485038, win 65495, options [mss 65495,sackOK,TS val 3269988560 ecr 0,nop,wscale 7], length 0
18:04:37.440153 IP 10.0.0.1.45998 > 192.168.0.181.sun-sr-https: Flags [S], seq 479485038, win 65495, options [mss 65495,sackOK,TS val 3269989596 ecr 0,nop,wscale 7], length 0
...
```

现在就来分析一下这个报文了：

- 首先，我是通过 `curl` 访问 `10.0.0.1`；
- 由于 `10.0.0.1` 这个地址是对 `kube-apiserver` 地址的代理，所以报文会被转发到 `kube-apiserver`，即 `192.168.0.181`；
- 而在上面抓取到的报文可以看出，报文转到 `192.168.0.181` 时源地址为 `10.0.0.1`，这就说明 `192.168.0.181` 回报文时也是直接会给 `10.0.0.1` 了；
- 而显然，回给 `10.0.0.1` 是不可取的，因为现在每个 Kubernetes Node 上都有一个 `kube-apiserver` 的代理地址，并且 `kube-apiserver` 所在主机并没有正确到到达 `10.0.0.1` 的路由；
- 而现在有一个 Kubernetes Node 是正常的，说明当前网络就把 `10.0.0.1` 这个地址绑定到了这个 Kubernetes Node，所以也就只有一个 Kubernetes Node 能够正常访问；
- 所以这个报文对于 `k8s03` 来说是处于一个只能出不能进的状态，那就当然超时了；

知道了问题所在，现在就有解决办法了，只需要将从 Kubernetes Node 出去的报文的源地址改为 Kubernetes Node 本身的地址而不是 `10.0.0.1` 就行了，这样响应报文就能正确从 `kube-apiserver` 所在主机响应到 Kubernetes Node 主机了。

在所有 Kubernetes Node 上添加如下 SNAT 的 iptables 规则即可：

```bash
$ iptables -t nat -A POSTROUTING -s 10.0.0.1/32 -j MASQUERADE
```

将其添加到 `/etc/rc.local` 让其开机自运行：

```bash
$ chmod +x /etc/rc.d/rc.local && echo 'iptables -t nat -A POSTROUTING -s 10.0.0.1/32 -j MASQUERADE' >> /etc/rc.d/rc.local
```

> 网上还有个解决方案是在 Flannel 运行时指定使用的网卡，如 `--iface=eth0`，修改 Flannel 部署的 YAML 文件在 Flannel 容器部分运行参数列表加上就行，如下：
>
> ```yaml
> containers:
>   - name: kube-flannel
>     image: registry.cn-shenzhen.aliyuncs.com/zze/flannel:v0.13.0
>     command:
>     - /opt/bin/flanneld
>     args:
>     - --ip-masq
>     - --iface=eth0
>     - --kube-subnet-mg
> ```
>
> 不过这个方案对我没有效果。。。

# Dashboard UI 部署

可以通过如下地址来获取 Kubernetes Dashboard 的信息：

- [Kubernetes 官方文档](https://kubernetes.io/docs/tasks/access-application-cluster/web-ui-dashboard/#deploying-the-dashboard-ui)
- [Github 地址](https://github.com/kubernetes/dashboard/releases)

下面我就使用 Github 中提供的 YAML 来部署了，先把 YAML 文件下载下来：

```bash
$ wget https://raw.githubusercontent.com/kubernetes/dashboard/v2.0.4/aio/deploy/recommended.yaml -O dashboard.yml
```

## 修改配置

由于默认的 YAML 没有暴露 Dashboard 服务到外部，这里我将其 `Service` 网络类型改为 `NodePort` 并指定其访问端口为 `30001`，然后通过指定环境变量让 UI 以中文显示：

```bash
$ vim dashboard.yml
...
kind: Service
apiVersion: v1
...
spec:
  type: NodePort
  ports:
    - port: 443 
      targetPort: 8443
      nodePort: 30001
      ...
kind: Deployment
apiVersion: apps/v1
...
spec:
...
    spec:
      containers:
        - name: kubernetes-dashboard
          image: kubernetesui/dashboard:v2.0.0-beta8
          imagePullPolicy: Always
          ports:
            - containerPort: 8443
              protocol: TCP 
          env:
            - name: ACCEPT_LANGUAGE
              value: zh
...
```

执行部署操作：

```bash
$ kubectl apply -f dashboard.yml 
namespace/kubernetes-dashboard created
serviceaccount/kubernetes-dashboard created
service/kubernetes-dashboard created
secret/kubernetes-dashboard-certs created
secret/kubernetes-dashboard-csrf created
secret/kubernetes-dashboard-key-holder created
configmap/kubernetes-dashboard-settings created
role.rbac.authorization.k8s.io/kubernetes-dashboard created
clusterrole.rbac.authorization.k8s.io/kubernetes-dashboard created
rolebinding.rbac.authorization.k8s.io/kubernetes-dashboard created
clusterrolebinding.rbac.authorization.k8s.io/kubernetes-dashboard created
deployment.apps/kubernetes-dashboard created
service/dashboard-metrics-scraper created
deployment.apps/dashboard-metrics-scraper created
```

检查 `Pod` 和 `Service` 状态：

```bash
$ kubectl get pod -n kubernetes-dashboard
NAME                                         READY   STATUS    RESTARTS   AGE
dashboard-metrics-scraper-7b59f7d4df-rsxpp   1/1     Running   0          77s
kubernetes-dashboard-665f4c5ff-lrs5j         1/1     Running   0          79s
$ kubectl get svc -n kubernetes-dashboard
NAME                        TYPE        CLUSTER-IP   EXTERNAL-IP   PORT(S)         AGE
dashboard-metrics-scraper   ClusterIP   10.0.0.92    <none>        8000/TCP        2m26s
kubernetes-dashboard        NodePort    10.0.0.225   <none>        443:30001/TCP   2m29s
```

## Chrome 无法访问

在上面我们已经部署好了 Dashboard，此时就可以通过浏览器访问 [https://:30001](https://192.168.0.183:30001/) 来访问它了。

但是使用如果你是使用 Chrome 或 Safari 浏览器，此时就会显示这样一个界面：

[![image.png](https://www.zze.xyz/upload/2020/10/image-bdfa7a58a8fc46d0a1f53bd1a92ec1b5.png)](https://www.zze.xyz/upload/2020/10/image-bdfa7a58a8fc46d0a1f53bd1a92ec1b5.png)

因为 Kubernetes Dashboard 默认的证书问题，使用 Chrome 等浏览器是不能正常访问 Dashboard UI 的，此时需要修改一下 Dashboard 使用的证书。

------

删除默认的 `secret`，用自签证书创建新的 `secret`：

```bash
$ kubectl delete secret kubernetes-dashboard-certs -n kubernetes-dashboard
$ kubectl create secret generic kubernetes-dashboard-certs \
--from-file=/opt/apps/kubernetes/ssl/server.pem --from-file=/opt/apps/kubernetes/ssl/server-key.pem -n kubernetes-dashboard
```

修改 `dashboard.yml` 文件，在 `args` 下面增加证书两行参数，然后重新部署，如下：

```bash
$ vim dashboard.yml
...
          args:
            - --auto-generate-certificates
            - --namespace=kubernetes-dashboard
            - --tls-key-file=server-key.pem
            - --tls-cert-file=server.pem
...
$ kubectl apply -f dashboard.yml
```

然后就可以正常使用 Google Chrome 添加信任访问 Dashboard UI 了，如下：

[![image.png](https://www.zze.xyz/upload/2020/10/image-e75b2a2fcdf14da181f200260992cd83.png)](https://www.zze.xyz/upload/2020/10/image-e75b2a2fcdf14da181f200260992cd83.png)

## 创建用户并授权

到这里我们已经可以正常使用浏览器访问到 Kubernetes Dashboard UI 了，但是如上图认证的时候还需要一个 Token 或 Kubeconfig 文件。这里我就使用 Token 的方式，需要先创建一个用户并授予相关权限，然后提取这个用户的 Token 来登录 Dashboard。

------

创建 `ServiceAccount` 并绑定默认 `cluster-admin` 管理员集群角色：

```bash
$ kubectl create serviceaccount dashboard-admin -n kube-system
serviceaccount/dashboard-admin created
$ kubectl create clusterrolebinding dashboard-admin --clusterrole=cluster-admin --serviceaccount=kube-system:dashboard-admin
clusterrolebinding.rbac.authorization.k8s.io/dashboard-admin created
# 获取 Token
$ kubectl describe secrets -n kube-system $(kubectl -n kube-system get secret | awk '/dashboard-admin/{print $1}')
Name:         dashboard-admin-token-dgbqw
Namespace:    kube-system
Labels:       <none>
Annotations:  kubernetes.io/service-account.name: dashboard-admin
              kubernetes.io/service-account.uid: 2983de0e-f165-44d0-9b4a-7cb4bf8b1a8c

Type:  kubernetes.io/service-account-token

Data
====
ca.crt:     1363 bytes
namespace:  11 bytes
token:      eyJhbGciOiJSUzI1NiIsImtpZCI6IkttMVJ4aDFQRE9McnA0UGZfd1gyQjkxSFNKclhmc3ZuSWo2dk14MlZkMnMifQ.eyJpc3MiOiJrdWJlcm5ldGVzL3NlcnZpY2VhY2NvdW50Iiwia3ViZXJuZXRlcy5pby9zZXJ2aWNlYWNjb3VudC9uYW1lc3BhY2UiOiJrdWJlLXN5c3RlbSIsImt1YmVybmV0ZXMuaW8vc2VydmljZWFjY291bnQvc2VjcmV0Lm5hbWUiOiJkYXNoYm9hcmQtYWRtaW4tdG9rZW4tZGdicXciLCJrdWJlcm5ldGVzLmlvL3NlcnZpY2VhY2NvdW50L3NlcnZpY2UtYWNjb3VudC5uYW1lIjoiZGFzaGJvYXJkLWFkbWluIiwia3ViZXJuZXRlcy5pby9zZXJ2aWNlYWNjb3VudC9zZXJ2aWNlLWFjY291bnQudWlkIjoiMjk4M2RlMGUtZjE2NS00NGQwLTliNGEtN2NiNGJmOGIxYThjIiwic3ViIjoic3lzdGVtOnNlcnZpY2VhY2NvdW50Omt1YmUtc3lzdGVtOmRhc2hib2FyZC1hZG1pbiJ9.v7h_BxmiQSJwCP2dECEGrFtmUS2BW1Pfdoebo-PTzyrBbvi9f50nbTwQ19ihwu9fC2JQig4qu-qmnjDgrINkNgp1jskwsFq4YeTVnanAEeFRFBUMXr0FjNOY0ho_5ATUz-Y6DCJ-fYZ5JSTfbFEeEKnRGzM9xbDo0Okg5B2m2F1nOnHDNNSyJ9s65C_0O2dVBFlc-KbbmPSLg9OtqC8zpD-86IoQnYSk7e49fTZe4mPtRgy814QEqmW640jQMEv0mmZGLmmVMBqIUWTtN0xQmyQft5BCdtKeIIZn-ZxuBk7lgQEg0PV6F620ytHF87zDob4Q5sXUyrm0qE0d9m3TBw
```

在 Dashboard 的 Web 页面选中 `Token` 项，在输入框输入上面生成的 `token` 值就能成功登入。

# core DNS 部署

DNS 主要是为 `Service` 来提供名称解析的，下面为它的 Github 地址：

- https://github.com/kubernetes/kubernetes/tree/master/cluster/addons/dns/coredns

这里要部署它我们需要先下载几个文件：

```bash
$ wget https://raw.githubusercontent.com/kubernetes/kubernetes/master/cluster/addons/dns/coredns/transforms2sed.sed
$ wget https://raw.githubusercontent.com/kubernetes/kubernetes/master/cluster/addons/dns/coredns/coredns.yaml.base
$ ls
coredns.yaml.base  transforms2sed.sed
```

## 配置

上述下载的文件不是可以直接使用的，需要稍作操作，如下。

首先将 `transforms2sed.sed` 中的 `$DNS_SERVER_IP` 和 `$DNS_DOMAIN` 替换为 Kubernetes Node 节点中的 `/opt/apps/kubernetes/conf/kubelet-config.yml` 中配置的内容：

- `$DNS_SERVER_IP` 对应 `clusterDNS` 的值；
- `$DNS_DOMAIN` 对应 `clusterDomain` 的值；
- 将 `$DNS_MEMORY_LIMIT` 设置为限制的内存大小值；
- 由于默认使用的镜像源也在国外，所以需要替换为国内源，直接在最后添加一行替换镜像地址的命令即可；

经过上述操作后 `transforms2sed.sed` 的内容如下：

```bash
$ cat transforms2sed.sed 
s/__DNS__SERVER__/10.0.0.2/g
s/__DNS__DOMAIN__/cluster.local./g
s/__CLUSTER_CIDR__/$SERVICE_CLUSTER_IP_RANGE/g
s/__DNS__MEMORY__LIMIT__/170Mi/g
s/__MACHINE_GENERATED_WARNING__/Warning: This is a file generated from the base underscore template file: __SOURCE_FILENAME__/g
s#(\s)(image.*$)#\1image: registry.cn-shenzhen.aliyuncs.com/zze/coredns:1.7.0#g
```

生成部署 coreDNS 用的 YAML 资源文件：

```bash
$ sed -r -f transforms2sed.sed coredns.yaml.base > coredns.yaml
```

执行部署操作：

```bash
$ kubectl apply -f coredns.yaml
serviceaccount/coredns created
clusterrole.rbac.authorization.k8s.io/system:coredns created
clusterrolebinding.rbac.authorization.k8s.io/system:coredns created
configmap/coredns created
deployment.apps/coredns created
service/kube-dns created
```

## 检查

检查 coreDNS 的 Pod 状态：

```bash
$ kubectl get pod -n kube-system -o wide | grep coredns
coredns-678f657597-ssrf5   1/1     Running       0          5m3s    10.244.0.10     k8s-node1   <none>           <none>
```

创建一个测试用的 Pod：

```bash
$ cat bs.yml 
apiVersion: v1
kind: Pod
metadata:
  name: busybox
  namespace: default
spec:
  containers:
  - image: busybox:1.28.4
    command:
    - sleep
    - "3600"
    imagePullPolicy: IfNotPresent
    name: busybox
  restartPolicy: Always
$ kubectl apply -f bs.yml
pod/busybox created
```

测试解析 `Service` 名称：

```bash
$ kubectl get svc
NAME         TYPE        CLUSTER-IP   EXTERNAL-IP   PORT(S)        AGE
kubernetes   ClusterIP   10.0.0.1     <none>        443/TCP        27h
test         NodePort    10.0.0.204   <none>        80:30599/TCP   5h3m
$ kubectl exec -it busybox -- sh
$ kubectl exec -it busybox -- sh
/ # nslookup test
Server:    10.0.0.2
Address 1: 10.0.0.2 kube-dns.kube-system.svc.cluster.local

Name:      test
Address 1: 10.0.0.204 test.default.svc.cluster.local
/ # nslookup kubernetes
Server:    10.0.0.2
Address 1: 10.0.0.2 kube-dns.kube-system.svc.cluster.local

Name:      kubernetes
Address 1: 10.0.0.1 kubernetes.default.svc.cluster.local
```

如上可以正确通过 `Service` 名称解析出其对应的 `Cluster-IP`，则说明 coreDNS 部署成功。

# Kubernetes Master 高可用

## 新增 Kubernetes Master 节点

> 要高可用 Master 首先需要部署多个 Master， 现在在 `k8s02` 上再部署一个 Master。

直接从 `k8s01` 上的 `/opt/apps/`目录拷贝需要的文件到 `k8s02` 上，然后删除日志目录里面生成的文件，下面操作在 `k8s02` 上执行 ：

```bash
$ mkdir -p /opt/apps/kubernetes/log /opt/apps/etcd/ssl
$ scp -rp k8s01:/opt/apps/kubernetes/{bin,conf,ssl} /opt/apps/kubernetes/
$ scp -rp k8s01:/opt/apps/etcd/ssl/* /opt/apps/etcd/ssl/
```

将 `kubectl` 链接到 `$PATH` 包含的路径下：

```bash
$ ln -s /opt/apps/kubernetes/bin/kubectl /usr/local/bin/
```

修改配置，唯一要修改的就是 `kube-apiserver.conf` 文件：

```bash
$ grep '192.168.0.181' /opt/apps/kubernetes/conf/* 
/opt/apps/kubernetes/conf/kube-apiserver.conf:--etcd-servers=https://192.168.0.181:2379,https://192.168.0.183:2379,https://192.168.0.184:2379 \
/opt/apps/kubernetes/conf/kube-apiserver.conf:--bind-address=192.168.0.181 \
/opt/apps/kubernetes/conf/kube-apiserver.conf:--advertise-address=192.168.0.181 \

# 修改 --bind-address 和 --advertise-address 值为 k8s02 主机的 IP 192.168.0.182
$ sed -i 's/--bind-address=192.168.0.181/--bind-address=192.168.0.182/g;s/--advertise-address=192.168.0.181/--advertise-address=192.168.0.182/g' /opt/apps/kubernetes/conf/kube-apiserver.conf
```

从 `k8s01` 拷贝几个 Systemd Service 文件到 `k8s02`：

```bash
$ scp -p k8s01:/usr/lib/systemd/system/{kube-apiserver.service,kube-controller-manager.service,kube-scheduler.service} /usr/lib/systemd/system/
```

启动服务并加入开机自启：

```bash
$ systemctl start kube-apiserver.service kube-controller-manager.service kube-scheduler.service
$ systemctl enable kube-apiserver.service kube-controller-manager.service kube-scheduler.service
```

测试 `kubectl` 命令：

```bash
$ kubectl get node
NAME        STATUS   ROLES    AGE   VERSION
k8s-node1   Ready    <none>   33h   v1.19.0
k8s-node2   Ready    <none>   31h   v1.19.0
```

输出信息就说明 `kube-apiserver` 工作正常，`kube-controller-manager` 和 `kube-scheduler` 的配置没有做修改，一般不会出现问题。

## Nginx 四层代理

> 下面操作在 `k8s05` 和 `k8s06` 上执行。

拉取 Nginx 和 Keepalived 的镜像：

```bash
$ docker pull nginx
$ docker pull alterway/keepalived
```

创建主配置文件：

```bash
$ cat /opt/apps/nginx/conf/nginx.conf 
user  nginx;
worker_processes  1;

error_log  /var/log/nginx/error.log warn;
pid        /var/run/nginx.pid;


events {
    worker_connections  1024;
}

include /etc/nginx/conf.d/*.l4.conf;

http {
    include       /etc/nginx/mime.types;
    default_type  application/octet-stream;

    log_format  main  '$remote_addr - $remote_user [$time_local] "$request" '
                      '$status $body_bytes_sent "$http_referer" '
                      '"$http_user_agent" "$http_x_forwarded_for"';

    access_log  /var/log/nginx/access.log  main;

    sendfile        on;
    #tcp_nopush     on;

    keepalive_timeout  65;

    #gzip  on;

    include /etc/nginx/conf.d/*.l7.conf;
}
```

创建 `kube-apiserver` 的四层代理配置文件：

```bash
$ cat /opt/apps/nginx/conf/conf.d/kube-apiserver-proxy.l4.conf 
stream {

    log_format  main  '$remote_addr $upstream_addr - [$time_local] $status $upstream_bytes_sent';

    access_log  /var/log/nginx/k8s-access.log  main;

    upstream k8s-apiserver {
        server 192.168.0.181:6443;
        server 192.168.0.182:6443;
    }
    
    server {
       listen 6443;
       proxy_pass k8s-apiserver;
    }
}
```

创建提供健康检查的接口：

```bash
$ cat /opt/apps/nginx/conf/conf.d/health_check.l7.conf 
server {
        listen 52999;
        server_name _;
        access_log off;

        default_type text/html;
        return 200 'ok';
}
```

运行一个 Nginx 容器：

```bash
$ docker run -d -v /opt/apps/nginx/conf/conf.d:/etc/nginx/conf.d \
    --restart=always \
    -v /opt/apps/nginx/conf/nginx.conf:/etc/nginx/nginx.conf \
    -v /opt/apps/nginx/log:/var/log/nginx \
    --net=host \
    --name nginx-proxy nginx:latest
```

## Keepalived 高可用

> 虚拟 IP `192.168.0.180` 准备放在 `k8s05` 和 `k8s06` 上，所以下面的操作就在 `k8s05` 和 `k8s06` 上进行。

```bash
$ cat /opt/apps/keepalived/conf/keepalived.conf
global_defs { 
   notification_email { 
     acassen@firewall.loc 
     failover@firewall.loc 
     sysadmin@firewall.loc 
   } 
   notification_email_from Alexandre.Cassen@firewall.loc  
   smtp_server 127.0.0.1 
   smtp_connect_timeout 30 
   # 备节点改为 NGINX_BACKUP
   router_id NGINX_MASTER
} 

vrrp_script check_nginx {
    script " curl -s -I --connect-timeout 3 127.0.0.1:52999"
    interval 3
    timeout 5
    # 失败 3 次才认为是 Down 状态
    fall 3
    # 成功 3 次才认为是 UP 状态
    rise 3
}

vrrp_instance VI_1 {
    # 备节点改为 BACKUP
    state MASTER
    interface eth0
    virtual_router_id 51 # VRRP 路由 ID实例，每个实例是唯一的 
    # 备节点改为 90
    priority 100
    # 指定VRRP 心跳包通告间隔时间，默认1秒
    advert_int 3    
    authentication { 
        auth_type PASS      
        auth_pass 1111 
    }  
    virtual_ipaddress { 
        192.168.0.180/24 dev eth0
    } 
    track_script {
        check_nginx
    } 
}
```

运行一个 Keepalived 容器：

```bash
$ docker run -d \
    --restart=always \
    --net host \
    -it \
    -v /opt/apps/keepalived/conf/keepalived.conf:/etc/keepalived/keepalived.conf \
    --name kube-proxy-ha \
    --cap-add NET_ADMIN \
    arcts/keepalived \
    keepalived -n -l -f /etc/keepalived/keepalived.conf
```

## Kubernetes Node 配置修改

> 在上面已经使用 `k8s05` 和 `k8s06` 对 `kube-apiserver` 做了代理，并给两个代理节点添加了虚拟 IP `192.168.0.180`，现在就要让 Kubernetes Node 节点不直接与 `kube-apiserver` 进行通信，而是走 `k8s05` 和 `k8s06` 的 虚拟 IP。所以下面的操作在 `k8s03` 和 `k8s04` 这两个 Node 节点上进行。

修改 `kubelet` 指向的 `kube-apiserver` 地址：

```bash
# 原来指向的是 k8s01 节点
$ grep '192.168.0.181' *
bootstrap.kubeconfig:    server: https://192.168.0.181:6443
kubelet.kubeconfig:    server: https://192.168.0.181:6443
kube-proxy.kubeconfig:    server: https://192.168.0.181:6443
# 修改为指向 VIP
$ sed -i 's/192.168.0.181/192.168.0.180/g' *
```

重启 `kubelet` 服务即可：

```bash
$ systemctl restart kubelet
```

至此，二进制搭建一套高可用的 Kubernetes 集群已经完成了。

# 启用 Ingress Controller

这里就涉及 `Ingress Controller` 的选型了，之前都是用 `Nginx Ingress Controller`，那么这次就换一个，这里我使用 `HAProxy Ingress Controller`，其官方 Github 地址为：

- https://github.com/haproxytech/kubernetes-ingress

在这个项目中提供了写好的资源配置，由于我还要做一点修改，所以先把它下载下来：

```bash
$ wget https://raw.githubusercontent.com/haproxytech/kubernetes-ingress/master/deploy/haproxy-ingress-daemonset.yaml
```

## 配置

这个资源配置不能直接使用，原因是它使用的 `defaultbackend` 镜像地址在国外，我把它拉下来并丢到了阿里云仓库，所以这里要改一下镜像的地址：

```bash
# 替换镜像
$ sed -i 's#image: gcr.io/google_containers/defaultbackend:1.0#image: registry.cn-shenzhen.aliyuncs.com/zze/defaultbackend:1.0#g' haproxy-ingress-daemonset.yaml
```

还有一点就是这个资源配置 YAML 中默认是采用 `NodePort Service` 来暴露 `Ingress Controller`，而这里我打算让 `Ingress Controller` 直接接收外部流量，就直接让 `Ingress Controller` 使用宿主机的网络了，只需要在名为 `haproxy-ingress` 的 `DamonSet` 资源下添加 `hostNetwork: yes` ，然后删除其中的 `Service` 资源，如下：

```yml
$ vim haproxy-ingress-daemonset.yaml
...
apiVersion: apps/v1
kind: DaemonSet
metadata:
  labels:
    run: haproxy-ingress
  name: haproxy-ingress
  namespace: haproxy-controller
spec:
  selector:
    matchLabels:
      run: haproxy-ingress
  template:
    metadata:
      labels:
        run: haproxy-ingress
    spec:
      hostNetwork: yes
      ...
```

最后执行部署操作：

```bash
$ kubectl apply -f haproxy-ingress-daemonset.yaml 
namespace/haproxy-controller created
serviceaccount/haproxy-ingress-service-account created
clusterrole.rbac.authorization.k8s.io/haproxy-ingress-cluster-role created
clusterrolebinding.rbac.authorization.k8s.io/haproxy-ingress-cluster-role-binding created
configmap/haproxy-configmap created
deployment.apps/ingress-default-backend created
service/ingress-default-backend created
daemonset.apps/haproxy-ingress created
```

## 检查

查看 `Pod` 的运行状态：

```bash
$ kubectl get pod -n haproxy-controller -o wide
NAME                                     READY   STATUS    RESTARTS   AGE     IP              NODE        NOMINATED NODE   READINESS GATES
haproxy-ingress-cwxt8                    1/1     Running   0          2m33s   192.168.0.183   k8s-node1   <none>           <none>
haproxy-ingress-f4dv4                    1/1     Running   0          2m33s   192.168.0.184   k8s-node2   <none>           <none>
ingress-default-backend-c675c85f-hm6lf   1/1     Running   0          2m36s   10.244.0.15     k8s-node1   <none>           <none>
```

可以看到其 `Pod` IP 就是对应的 Kubernetes Node 的 IP，这说明我们设置的 `hostNetwork: yes` 是生效的。

## 测试

下面来简单的使用 Nginx 来提供一个 Web 网页，然后用 `Ingress` 将其暴露到外部以测试 `Ingress` 运作是否正常。

创建一个 Nginx `Deployment` 资源，并使用 `ClusterIP` 的 `Service` 将其关联：

```bash
$ kubectl create deploy nginx-web --image=nginx
deployment.apps/nginx-web created
$ kubectl expose deploy nginx-web --target-port=80 --port=80
service/nginx-web exposed
```

编写 `Ingress` 资源以创建 `Ingress` 规则：

```bash
$ cat nginx-web-ingress.yml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: minimal-ingress
  annotations:
    nginx.ingress.kubernetes.io/rewrite-target: /
spec:
  rules:
  - host: "www.zze.cn"
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: nginx-web
            port:
              number: 80
$ kubectl apply -f nginx-web-ingress.yml 
ingress.networking.k8s.io/minimal-ingress created
```

下面就可以通过 [http://www.zze.cn](http://www.zze.cn/) 来访问到 `nginx-web` 了，只是这里我没有内建 DNS，就手动改一下 PC 的 `hosts` 配置：

```yaml
# 解析到任意一个 Node 即可
192.168.0.183 www.zze.cn
```

然后就可以使用浏览器或者其它 HTTP 客户端访问测试了，我这里就直接在 Mac 上 `curl` 了，结果如下：

```bash
$ curl www.zze.cn   
<!DOCTYPE html>
...
<p><em>Thank you for using nginx.</em></p>
</body>
</html>
```

OK，`Ingress` 也工作正常了~

# 释疑

## 镜像使用什么版本？

在上面 Kubernetes Node 组件部署中，我在 `kubelet` 的配置文件中指定了使用的 3.0 版本 `pasue` 镜像，那为什么要是这个版本呢？

关于 Kubernetes 相关组件的镜像要使用什么版本，可以通过 `kubeadm` 查看，在 `kubernetes-server-linux-amd64.tar.gz` 解压后的 `kubernetes/server/bin` 目录下有一个名为 `kubeadm` 二进制程序，我们可以通过它来查看当前版本的 Kubernetes 所需要的组件镜像的版本。下面命令会输出 `kubeadm` 对应版本的 Kubernetes 集群所需镜像名及其标签：

```bash
$ kubernetes/server/bin/kubeadm config images list
W1018 11:10:43.145284    7790 kubelet.go:200] cannot automatically set CgroupDriver when starting the Kubelet: cannot execute 'docker info -f {{.CgroupDriver}}': executable file not found in $PATH
W1018 11:10:44.308930    7790 configset.go:348] WARNING: kubeadm cannot validate component configs for API groups [kubelet.config.k8s.io kubeproxy.config.k8s.io]
k8s.gcr.io/kube-apiserver:v1.19.3
k8s.gcr.io/kube-controller-manager:v1.19.3
k8s.gcr.io/kube-scheduler:v1.19.3
k8s.gcr.io/kube-proxy:v1.19.3
k8s.gcr.io/pause:3.2
k8s.gcr.io/etcd:3.4.9-1
k8s.gcr.io/coredns:1.7.0
```

> 因为国内被墙的原因，上述镜像是直接拉去不到的，这里我把它们传到了阿里云仓库，如果你需要拉取它们的话只需要将镜像名中的 `k8s.gcr.io` 替换为 `registry.cn-shenzhen.aliyuncs.com/zze` 即可，比如你需要 `pause` 镜像则拉取命令为 `docker pull registry.cn-shenzhen.aliyuncs.com/zze/pause:3.2` 。

上面输出的镜像是使用 `kubeadm` 部署所需要的，而这里因为我们使用二进制的方式部署了其中几个组件，有 `kube-apiserver`、`kube-controller-manager`、`kube-scheduler`、`kube-proxy`、`etcd` ，所以在这里我们只需要使用 `pause`、`coredns` 镜像而已。

## kubectl 能整个命令补全吗？

既然写在这里了，那肯定是可以的。。其实 `kubectl` 二进制程序本身就为命令补全提供了支持，只是需要配合 `bash-completion` 来使用。

首先，`kubectl bash` 就能生成补全规则了，只是这个规则是输出到标准输出，我们只要将它保存到 `bash-completion` 的配置目录即可。

执行下面几步两条命令就能让 `kubectl` 有补全功能了~

```bash
# 安装 bash-completion
$ yum install bash-completion -y
# 生成补全规则配置文件
$ kubectl completion bash > /usr/share/bash-completion/completions/kubectl \
&& . /usr/share/bash-completion/completions/kubectl
```