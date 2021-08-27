#!/bin/sh
/data/tmp/xtrabackup/bin/innobackupex \
--defaults-file=/etc/my.cnf \
--user=xtrabk \
--password='onlyxtrabk!@#$2336' \
--stream=tar --parallel=5 \
--no-timestamp  \
/data/tmp/backup_full_mysql | ssh -p 22 dbops@10.51.18.203 " gzip - > /data/tmp/backup_full_mysql/backup_159.tar.gz"