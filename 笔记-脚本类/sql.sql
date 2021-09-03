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

TRUNCATE TABLE tablename
清空表


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