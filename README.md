docker
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
