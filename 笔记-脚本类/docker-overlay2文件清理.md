docker overlay2目录清理
---

kubernets集群 work节点磁盘告警，查看为/data/docker/overlay2 目录占用过大导致

    [root@k8s-work5 overlay2]# du -hs * | sort -rh | head -n 10 
    408G	99de740f4411d230231a3b97fe173b9cb96301e1fc7b5023f8cf412dfc638177
    16G	557205f2552cc7abf74017bbb8dfe5389e197563d7f84e47670a9145f6335f86
    5.7G	a7876bd3dee0843776fbcf154539b53e684ed40525845b5545957cb04bc6bba6
    4.3G	c4a2edc4b6e705db910c240378972001cfea2df6b0ea3bf09f47678defc092a8
    2.7G	23a7018f162142a2104c6d3a1b983081348ce1570698934e11ecd7d357f88dab
    2.2G	93ff343367d318b84e2a130ed2fd31ff8b21aaaf79c2e1284d5b467cb4abb793
    1.3G	2fc79d4b89986d31273d978e4523d723d0848539a533d3f88089222d648b2db3
    1.2G	5099f91772211926c6f7c1ddb01d9aca806f29f412837b022f7b7c6fe993c4ff
    955M	6d904d6b768c6fde07b4611ab66e12e2b235caf7b04cd096bf433c440180025f
    872M	bfc351c2ca2fafbf41bc4b20ce3a5e6961b05ad4c9ca805b7fa96b09bb4b3673
    [root@k8s-work5 overlay2]# cd 99de740f4411d230231a3b97fe173b9cb96301e1fc7b5023f8cf412dfc638177
    [root@k8s-work5 99de740f4411d230231a3b97fe173b9cb96301e1fc7b5023f8cf412dfc638177]# ll
    total 8
    drwxr-xr-x 5 root root  41 Jan 11 22:03 diff
    -rw-r--r-- 1 root root  26 Jan 11 22:03 link
    -rw-r--r-- 1 root root 144 Jan 11 22:03 lower
    drwxr-xr-x 1 root root  41 Jan 11 22:03 merged
    drwx------ 3 root root  18 Jan 11 22:03 work
    [root@k8s-work5 99de740f4411d230231a3b97fe173b9cb96301e1fc7b5023f8cf412dfc638177]# pwd
    /data/docker/overlay2/99de740f4411d230231a3b97fe173b9cb96301e1fc7b5023f8cf412dfc638177
    [root@k8s-work5 99de740f4411d230231a3b97fe173b9cb96301e1fc7b5023f8cf412dfc638177]# docker ps -q | xargs docker inspect --format '{{.State.Pid}}, {{.Name}}, {{.GraphDriver.Data.WorkDir}}' | grep "99de740f4411d230231a3b97fe173b9cb96301e1fc7b5023f8cf412dfc638177"
    22439, /k8s_bill-c_bill-c-64fccc8b54-4kgpn_bill_78a15583-5ae0-463d-8c57-81eef41dfe37_0, /data/docker/overlay2/99de740f4411d230231a3b97fe173b9cb96301e1fc7b5023f8cf412dfc638177/work
    [root@k8s-work5 99de740f4411d230231a3b97fe173b9cb96301e1fc7b5023f8cf412dfc638177]# cd work/

    docker ps -q | xargs docker inspect --format '{{.State.Pid}}, {{.Name}}, {{.GraphDriver.Data.WorkDir}}' | grep "文件目录"  可以查看到是哪个容器占用这个文件夹