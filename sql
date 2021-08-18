select a.delay_time ,a.GMT_MODIFIED from delay_stat a ,pipeline b where a.pipeline_id = b.id and b.id = ? order by a.GMT_MODIFIED desc limit 1;
查找otter

show master status\G;
查找位点

SELECT * FROM information_schema.processlist WHERE command != 'Sleep' and time > 5 and user <> 'system user' and user <> 'replicator' and DB <> 'NULL' order by time\G
查找慢sql

select count(*) from table_history_stat where GMT_CREATE <  date(date_add(now(),interval -2 day));
查询两天前的条数

SELECT table_schema FROM information_schema.TABLES WHERE table_name = 'TB_UHOME_PATROL_SCHEDULE_HIS';
查找某个表在哪个库

show binlog events in 'mysql-bin.000243';
查看binlog日志

ALTER TABLE service_attr_inst_his  modify attr_value varchar(2048);
modify修改表字段

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
