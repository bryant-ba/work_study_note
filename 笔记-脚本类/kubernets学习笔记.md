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
Kubernetes 项目的 Projected Volume 其实只有三种，因为第四种 ServiceAccountToken，只是一种特殊的 Secret 而已。

Service Account 对象的作用，就是 Kubernetes 系统内置的一种“服务账户”，它是 Kubernetes 进行权限分配的对象。比如，Service Account A，可以只被允许对 Kubernetes API 进行 GET 操作，而 Service Account B，则可以有 Kubernetes API 的所有操作权限。

每一个 Pod，都已经自动声明一个类型是 Secret、名为 default-token-xxxx 的 Volume，然后 自动挂载在每个容器的一个固定目录上。

Kubernetes 其实在每个 Pod 创建的时候，自动在它的 spec.volumes 部分添加上了默认 ServiceAccountToken 的定义，然后自动给每个容器加上了对应的 volumeMounts 字段。这个过程对于用户来说是完全透明的。

Kubernetes 客户端以容器的方式运行在集群里，然后使用 default Service Account 自动授权的方式，被称作“InClusterConfig”

在 Kubernetes 中，你可以为 Pod 里的容器定义一个健康检查“探针”（Probe）。这样，kubelet 就会根据这个 Probe 的返回值决定这个容器的状态，而不是直接以容器镜像是否运行（来自 Docker 返回的信息）作为依据。

Kubernetes 中并没有 Docker 的 Stop 语义。所以虽然是 Restart（重启），但实际却是重新创建了容器。
这个功能就是 Kubernetes 里的 Pod 恢复机制，也叫 restartPolicy。它是 Pod 的 Spec 部分的一个标准字段（pod.spec.restartPolicy），默认值是 Always，即：任何时候这个容器发生了异常，它一定会被重新创建。

Pod 的恢复过程，永远都是发生在当前节点上，而不会跑到别的节点上去。事实上，一旦一个 Pod 与一个节点（Node）绑定，除非这个绑定发生了变化（pod.spec.node 字段被修改），否则它永远都不会离开这个节点。这也就意味着，如果这个宿主机宕机了，这个 Pod 也不会主动迁移到其他节点上去。
Pod 出现在其他的可用节点上，就必须使用 Deployment 这样的“控制器”来管理 Pod，哪怕你只需要一个 Pod 副本。

还可以通过设置 restartPolicy，改变 Pod 的恢复策略。除了 Always，它还有 OnFailure 和 Never 两种情况：
Always：在任何情况下，只要容器不在运行状态，就自动重启容器；OnFailure: 只在容器 异常时才自动重启容器；Never: 从来不重启容器。

1. 只要 Pod 的 restartPolicy 指定的策略允许重启异常的容器（比如：Always），那么这个 Pod 就会保持 Running 状态，并进行容器重启。否则，Pod 就会进入 Failed 状态 。
2. 对于包含多个容器的 Pod，只有它里面所有的容器都进入异常状态后，Pod 才会进入 Failed 状态。在此之前，Pod 都是 Running 状态。此时，Pod 的 READY 字段会显示正常容器的个数。

除了在容器中执行命令外，livenessProbe 也可以定义为发起 HTTP 或者 TCP 请求的方式：
...
livenessProbe:
     httpGet:
       path: /healthz
       port: 8080
       httpHeaders:
       - name: X-Custom-Header
         value: Awesome
       initialDelaySeconds: 3
       periodSeconds: 3
这是http请求方式


    ...
    livenessProbe:
      tcpSocket:
        port: 8080
      initialDelaySeconds: 15
      periodSeconds: 20
tcp请求方式

Pod 这个看似复杂的 API 对象，实际上就是对容器的进一步抽象和封装而已。
“容器”镜像虽然好用，但是容器这样一个“沙盒”的概念，对于描述应用来说，还是太过简单了。这就好比，集装箱固然好用，但是如果它四面都光秃秃的，吊车还怎么把这个集装箱吊起来并摆放好呢？所以，Pod 对象，其实就是容器的升级版。它对容器进行了组合，添加了更多的属性和字段。这就好比给集装箱四面安装了吊环，使得 Kubernetes 这架“吊车”，可以更轻松地操作它。
Kubernetes 操作这些“集装箱”的逻辑，都由控制器（Controller）完成。

Deployment -- 最基本的控制器，例如nginx-deployment.yaml中，这个 Deployment 定义的编排动作非常简单，即：确保携带了 app=nginx 标签的 Pod 的个数，永远等于 spec.replicas 指定的个数，即 2 个。这就意味着，如果在这个集群中，携带 app=nginx 标签的 Pod 的个数大于 2 的时候，就会有旧的 Pod 被删除；反之，就会有新的 Pod 被创建。

kube-controller-manager 组件就是一系列控制器的集合。可以在kubernets/pkg/controller/下看到一系列的控制器，这个目录下面的每一个控制器，都以独有的方式负责某种编排功能。而我们的 Deployment，正是这些控制器中的一种。