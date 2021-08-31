docker迅速发展的三个重要原因
1.Docker image通过技术手段解决了PaaS的根本问题
2.Docker 容器同开发者之间的密切关系
容器其实是一种沙盒技术，沙盒的“边界”是容器的基础
计算机进程执行起来，就从磁盘上的二进制文件，变成了计算机内存钟的数据，寄存器里的值，堆栈中的指令，被打开的文件，以及各种设备的状态信息的集合。
程序运行起来后计算机的执行环境的综合--进程。
对于进程来说，静态表现就是程序，一旦运行起来就变成了计算机里数据和状态的总和，这是进程的动态表现，而容器的核心功能，就是通过约束和修改进程的动态表现，创造出一个边界。
对于容器来说，Cgroups 技术是用来制造约束的主要手段，而Namespace 技术则是用来修改进程视图的主要方法。
`docker run  -it  busybox /bin/sh` 创建一个容器，-it 参数指定了启动容器后，给一个TTY，与容器标准输入相关联。
查看docker容器的namespace： 1. docker ps拿到containerID 2. 有三种常用方式查看docker在宿主机的PID：1) 直接查看文件cat /sys/fs/cgroup/memory/docker/<container ID>/cgroup.procs 2）docker container top <containerID> 3） docker inspect -f '{{.State.Pid}}' <containerID> 3. 拿到进程ID后，执行ll /proc/<PID>/ns/ 可查看docker启用的具体Namespace参数 docker启用的六个Namespace。

kubeadm 的工作原理
容器部署 Kubernetes
如何容器化 kubelet
kubelet 是 Kubernetes 项目用来操作 Docker 等容器运行时的核心组件。可是，除了跟容器运行时打交道外，kubelet 在配置容器网络、管理容器数据卷时，都需要直接操作宿主机。
如果现在 kubelet 本身就运行在一个容器里，那么直接操作宿主机就会变得很麻烦。对于网络配置来说还好，kubelet 容器可以通过不开启 Network Namespace（即 Docker 的 host network 模式）的方式，直接共享宿主机的网络栈。可是，要让 kubelet 隔着容器的 Mount Namespace 和文件系统，操作宿主机的文件系统，就有点儿困难了。
kubeadm 选择了一种妥协方案：把 kubelet 直接运行在宿主机上，然后使用容器部署其他的 Kubernetes 组件。
kubeadm init 的工作流程
当你执行 kubeadm init 指令后，kubeadm 首先要做的，是一系列的检查工作，以确定这台机器可以用来部署 Kubernetes。这一步检查，我们称为“Preflight Checks”，它可以为你省掉很多后续的麻烦。其实，Preflight Checks 包括了很多方面，比如：
Linux 内核的版本必须是否是 3.10 以上？Linux Cgroups 模块是否可用？机器的 hostname 是否标准？在 Kubernetes 项目里，机器的名字以及一切存储在 Etcd 中的 API 对象，都必须使用标准的 DNS 命名（RFC 1123）。用户安装的 kubeadm 和 kubelet 的版本是否匹配？机器上是不是已经安装了 Kubernetes 的二进制文件？Kubernetes 的工作端口 10250/10251/10252 端口是不是已经被占用？ip、mount 等 Linux 指令是否存在？Docker 是否已经安装？
在通过了 Preflight Checks 之后，kubeadm 要为你做的，是生成 Kubernetes 对外提供服务所需的各种证书和对应的目录。
Kubernetes 对外提供服务时，除非专门开启“不安全模式”，否则都要通过 HTTPS 才能访问 kube-apiserver。这就需要为 Kubernetes 集群配置好证书文件。kubeadm 为 Kubernetes 项目生成的证书文件都放在 Master 节点的 /etc/kubernetes/pki 目录下。在这个目录下，最主要的证书文件是 ca.crt 和对应的私钥 ca.key。此外，用户使用 kubectl 获取容器日志等 streaming 操作时，需要通过 kube-apiserver 向 kubelet 发起请求，这个连接也必须是安全的。kubeadm 为这一步生成的是 apiserver-kubelet-client.crt 文件，对应的私钥是 apiserver-kubelet-client.key。除此之外，Kubernetes 集群中还有 Aggregate APIServer 等特性，也需要用到专门的证书，这里我就不再一一列举了。

pod yaml的
Lifecycle 字段。它定义的是 Container Lifecycle Hooks。顾名思义，Container Lifecycle Hooks 的作用，是在容器状态发生变化时触发一系列“钩子”。
先说 postStart 吧。它指的是，在容器启动后，立刻执行一个指定的操作。需要明确的是，postStart 定义的操作，虽然是在 Docker 容器 ENTRYPOINT 执行之后，但它并不严格保证顺序。
也就是说，在 postStart 启动时，ENTRYPOINT 有可能还没有结束。当然，如果 postStart 执行超时或者错误，Kubernetes 会在该 Pod 的 Events 中报出该容器启动失败的错误信息，导致 Pod 也处于失败的状态。
而类似地，preStop 发生的时机，则是容器被杀死之前（比如，收到了 SIGKILL 信号）。而需要明确的是，preStop 操作的执行，是同步的。所以，它会阻塞当前的容器杀死流程，直到这个 Hook 定义操作完成之后，才允许容器被杀死，这跟 postStart 不一样。所以，在这个例子中，我们在容器成功启动之后，在 /usr/share/message 里写入了一句“欢迎信息”（即 postStart 定义的操作）。而在这个容器被删除之前，我们则先调用了 nginx 的退出指令（即 preStop 定义的操作），从而实现了容器的“优雅退出”。
postStart和ENTRYPOINT是异步执行，preStop和SIGKILL是同步执行的。
prestop和poststart不同之处在于poststart与entrypoint启动顺序是entrypoint先于poststart，但是poststart并不会等待entrypoint完成之后再执行。
而prestop与容器退出是同步的，必须执行完成prestop容器才会退出。

pod对象在kubernets中的生命周期
pod生命周期的变化，主要体现在Pod API对象的Status部分，这是除了Metadata和Spec之外的第三个重要字段，pod.status.phase 代表pod的当前状态：
1. Pending 这个状态意味着，pod的yaml文件已经提交给kubernets执行，api对象已经创建并保存在etcd中。但是这个pod里有些容器因为某种原因没有顺利被创建。比如，调度不成功。
2. Running 这个状态下，pod已经调度成功，和一个具体的node节点绑定，pod包含的容器也已经全部创建成功，并且至少有一个正在运行中。
3. Succeeded 这个状态意味着，Pod 里的所有容器都正常运行完毕，并且已经退出了。这种情况在运行一次性任务时最为常见。
4. Faild 这个状态下，Pod 里至少有一个容器以不正常的状态（非 0 的返回码）退出。这个状态的出现，意味着你得想办法 Debug 这个容器的应用，比如查看 Pod 的 Events 和日志。
5. Unknown 这是一个异常状态，意味着 Pod 的状态不能持续地被 kubelet 汇报给 kube-apiserver，这很有可能是主从节点（Master 和 Kubelet）间的通信出现了问题。

Pod 对象的 Status 字段，还可以再细分出一组 Conditions。这些细分状态的值包括：PodScheduled、Ready、Initialized，以及 Unschedulable。它们主要用于描述造成当前 Status 的具体原因是什么。

对于 Pod 状态是 Ready，实际上不能提供服务的情况能想到几个例子：
1. 程序本身有 bug，本来应该返回 200，但因为代码问题，返回的是500；
2. 程序因为内存问题，已经僵死，但进程还在，但无响应；
3. Dockerfile 写的不规范，应用程序不是主进程，那么主进程出了什么问题都无法发现；
4. 程序出现死循环。

Downward API支持的字段
1. 使用fieldRef可以声明使用:
spec.nodeName - 宿主机名字
status.hostIP - 宿主机IP
metadata.name - Pod的名字
metadata.namespace - Pod的Namespace
status.podIP - Pod的IP
spec.serviceAccountName - Pod的Service Account的名字
metadata.uid - Pod的UID
metadata.labels['<KEY>'] - 指定<KEY>的Label值
metadata.annotations['<KEY>'] - 指定<KEY>的Annotation值
metadata.labels - Pod的所有Label
metadata.annotations - Pod的所有Annotation
2. 使用resourceFieldRef可以声明使用:
容器的CPU limit
容器的CPU request
容器的memory limit
容器的memory request
Downward API 能够获取到的信息，一定是 Pod 里的容器进程启动之前就能够确定下来的信息。