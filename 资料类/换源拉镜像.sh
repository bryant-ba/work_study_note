set -o errexit
set -o nounset
set -o pipefail

##这里定义版本，按照上面得到的列表自己改一下版本号

KUBE_VERSION=v1.22.0
KUBE_PAUSE_VERSION=3.5
ETCD_VERSION=3.5.0-0
DNS_VERSION=v1.8.4

##这是原始仓库名，最后需要改名成这个
GCR_URL=registry.cn-hangzhou.aliyuncs.com/bryantba

##这里就是写你要使用的仓库
DOCKERHUB_URL=gotok8s

##这里是镜像列表，新版本要把coredns改成coredns/coredns
images=(
kube-proxy:${KUBE_VERSION}
kube-scheduler:${KUBE_VERSION}
kube-controller-manager:${KUBE_VERSION}
kube-apiserver:${KUBE_VERSION}
pause:${KUBE_PAUSE_VERSION}
etcd:${ETCD_VERSION}
coredns:${DNS_VERSION}
)

##这里是拉取和改名的循环语句
for imageName in ${images[@]} ; do
  docker pull $DOCKERHUB_URL/$imageName
  docker tag $DOCKERHUB_URL/$imageName $GCR_URL/$imageName
  docker rmi $DOCKERHUB_URL/$imageName
  docker push $GCR_URL/$imageName
done
