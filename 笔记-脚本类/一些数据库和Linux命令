show binary logs;
#查看MySQL服务器上的binlog文件

#查看日志开启状态 
show variables like 'log_%';

#查看所有binlog日志列表
show master logs;

#查看最新一个binlog日志的编号名称，及其最后一个操作事件结束点 
show master status;

#刷新log日志，立刻产生一个新编号的binlog日志文件，跟重启一个效果 
flush logs;

#清空所有binlog日志 
reset master;

select `name` from mysql.proc where db = 'your_db_name' and `type` = 'PROCEDURE'
查找全部的存储过程

show create procedure proc_name;
show create function func_name;
查看存储过程或函数的创建代码

select a.delay_time ,a.GMT_MODIFIED from delay_stat a ,pipeline b where a.pipeline_id = b.id and b.id = ? order by a.GMT_MODIFIED desc limit 1;
查找otter

show master status\G;
查找位点

show OPEN TABLES where In_use > 0;
查看是否锁表

SELECT * FROM INFORMATION_SCHEMA.INNODB_LOCKS;
查看正在锁的事务

SELECT * FROM INFORMATION_SCHEMA.INNODB_LOCK_WAITS;
查看等待锁的事务

SELECT * FROM information_schema.processlist WHERE command != 'Sleep' and time > 5 and user <> 'system user' and user <> 'replicator' and DB <> 'NULL' order by time\G
查找慢sql

select count(*) from table_history_stat where GMT_CREATE <  date(date_add(now(),interval -2 day));
查询两天前的条数

SELECT table_schema FROM information_schema.TABLES WHERE table_name = 'tb_uhome_billboard';
查找某个表在哪个库

show binlog events in 'mysql-bin.006195';
查看binlog日志

ALTER TABLE service_attr_inst_his  modify attr_value varchar(2048);
modify修改表字段属性

ALTER TABLE service_attr_inst_his  modify attr_value varchar(2048) after GMT_CREATE;
modify修改表字段位置

TRUNCATE TABLE tablename;
清空表

SET GLOBAL SQL_SLAVE_SKIP_COUNTER = 1;
mysql主从跳过一个事务


reset slave all;
set global gtid_mode='ON_PERMISSIVE';
set global gtid_mode='OFF_PERMISSIVE';
CHANGE MASTER TO  
    MASTER_HOST='10.51.8.155',    
    MASTER_USER='repl',    
    MASTER_PASSWORD='8ZCF6Ntn9q1ijMB3RlHX',    
    MASTER_PORT=3306,    
    MASTER_AUTO_POSITION = 0,
    master_log_file='mysql-bin.006148',
    master_log_pos=15991330;
start slave;
show slave status\G
主从同步

SELECT DISTINCT
t.table_name,
c.COLUMN_NAME
FROM
information_schema.TABLES t
INNER JOIN information_schema.COLUMNS c
ON c.TABLE_NAME = t.TABLE_NAME
where t.TABLE_TYPE = 'base table'
and c.COLUMN_NAME = 'MESSAGE'
and t.TABLE_SCHEMA = 'segiods'
ORDER BY t.TABLE_TYPE
查找字段在哪个表

show table status where comment='view'; 
查看哪些是视图

kubectl tab补全
yum install bash-completion
echo "source /usr/share/bash-completion/bash_completion" >>  ~/.bashrc
echo 'source <(kubectl completion bash)' >>~/.bashrc
source ~/.bashrc
type _init_completion
kubectl tab补全

kubens 切换k8s namespace
curl -L https://github.com/ahmetb/kubectx/releases/download/v0.9.4/kubens -o /bin/kubens
chmod +x /bin/kubens


-- 1. 进入information_schema 数据库（存放了其他的数据库的信息）
use information_schema;

-- 2. 查询所有数据的大小：
select concat(round(sum(data_length/1024/1024),2),'MB') as data 
from information_schema.tables
;

-- 3. 查看实例下所有数据库的空间占用情况
select 
     table_schema
    ,concat(round(sum(data_length/1024/1024),2),'MB') as data 
from information_schema.tables 
where table_schema like 'db_name_%' 
group by table_schema
;

-- 4.查看指定数据库的大小：
select concat(round(sum(data_length/1024/1024),2),'MB') as data 
from information_schema.tables 
where table_schema='home'
;

-- 5. 查看指定数据库下的所有表的空间占用情况
select table_name,round(sum(data_length/1024/1024),2) as size 
from information_schema.tables 
where table_schema='mycommunity_zhhy_1'
group by table_name
order by size
;

-- 6. 查看指定数据库的某个表的大小
select concat(round(sum(data_length/1024/1024),2),'MB') as data 
from information_schema.tables 
where table_schema='home' and table_name='members'
;

select
table_schema
,round(sum(data_length/1024/1024),2) as data_length
,round(sum(DATA_FREE/1024/1024),2) as data_free
,round(sum(INDEX_LENGTH/1024/1024),2) as INDEX_LENGTH
from information_schema.tables
where table_schema='mycommunity_bigdata'
group by table_schema
order by data_length
;

select
     TABLE_SCHEMA
    ,sum(DATA_LENGTH)/1024/1024/1024                            as size_DATA_LENGTH_g 
    ,sum(INDEX_LENGTH)/1024/1024/1024                           as size_INDEX_LENGTH_g 
    ,sum(DATA_FREE)/1024/1024/1024                              as size_DATA_FREE_g 
    ,sum((DATA_LENGTH+INDEX_LENGTH+DATA_FREE))/1024/1024/1024   as size_g 
from information_schema.tables 
where table_type = 'BASE TABLE'
group by TABLE_SCHEMA
order by size_DATA_FREE_g
;

select
     TABLE_NAME
    ,sum(DATA_LENGTH)/1024/1024/1024                            as size_DATA_LENGTH_g 
    ,sum(INDEX_LENGTH)/1024/1024/1024                           as size_INDEX_LENGTH_g 
    ,sum(DATA_FREE)/1024/1024/1024                              as size_DATA_FREE_g 
    ,sum((DATA_LENGTH+INDEX_LENGTH+DATA_FREE))/1024/1024/1024   as size_g 
from information_schema.tables 
where table_type = 'BASE TABLE'
    and table_schema = 'db_name'
    -- and TABLE_NAME = 'table_name'
group by TABLE_NAME
order by size_g desc
limit 20
;

 # 只有master节点的创建方式
./redis-trib.rb create  192.168.66.2:7000 192.168.66.2:7001 192.168.66.2:7002 192.168.66.3:7003 192.168.66.3:7004 192.168.66.3:7005
使用 --replicas 1 创建 每个master带一个 slave 指令
./redis-trib.rb create --replicas 1  10.51.114.17:43000 10.51.114.17:43001 10.51.114.18:43000 10.51.114.18:43001 10.51.114.19:43000 10.51.114.19:43001

-- 更改主从忽略表
stop slave;
CHANGE REPLICATION FILTER REPLICATE_WILD_IGNORE_TABLE = ('dis_nc.%');
start slave;

实际IN和EXIST查询效率：当大表IN小表时效率高；小表EXIST大表时效率高

IN表是外边和内表进行hash连接，是先执行子查询。
EXISTS是对外表进行循环，然后在内表进行查询。
因此如果外表数据量大，则用IN，如果外表数据量小，也用EXISTS。
IN有一个缺陷是不能判断NULL，因此如果字段存在NULL值，则会出现返回，因为最好使用NOT EXISTS。

查询数据库中的存储过程和函数

select `name` from mysql.proc where db = 'xx' and `type` = 'PROCEDURE'   //存储过程
select `name` from mysql.proc where db = 'xx' and `type` = 'FUNCTION'   //函数

show procedure status; //存储过程
show function status;     //函数

查看存储过程或函数的创建代码

show create procedure proc_name;
show create function func_name;

查看视图
SELECT * from information_schema.VIEWS   //视图
SELECT * from information_schema.TABLES   //表

查看触发器
SHOW TRIGGERS [FROM db_name] [LIKE expr]
SELECT * FROM triggers T WHERE trigger_name=”mytrigger” \G

几条有用的docker命令
dockers system df  查看docker容器，镜像，网络，挂载的卷在系统上的占用
docker image prune  删除所有未被 tag 标记和未被容器使用的镜像
docker image prune -a 删除所有未被容器使用的镜像
docker container prune 删除所有停止运行的容器
docker volume prune  删除所有未被挂载的卷 
docker network prune 删除所有网络
docker system prune 删除 docker 所有资源
docker inspect [OPTIONS] NAME|ID [NAME|ID...]  获取容器/镜像的元数据
OPTIONS说明：
-f :指定返回值的模板文件。
-s :显示总的文件大小。
--type :为指定类型返回JSON。
docker inspect --format='{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' container_name 获取container_name的ip
docker ps -q | xargs docker inspect --format '{{.State.Pid}}, {{.Id}}, {{.Name}}, {{.GraphDriver.Data.WorkDir}}' | grep "docker/overlay2/下的文件夹名称" 获取对应的容器信息
docker ps -q | xargs docker inspect --format '{{.State.Pid}}, {{.Id}}, {{.Name}}, {{.GraphDriver.Data.WorkDir}}' | grep  container_name 获取docker/overlay2/下的文件夹
