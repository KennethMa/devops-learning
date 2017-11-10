#!/bin/bash

TmpBakDir=/home/ubuntu/backups
GitlabDir=/home/ubuntu/docker/gitlab/gitlab/backups
DroneDir=/home/ubuntu/docker/drone
rm -rf $GitlabDir/*
docker exec -t gitlab_web_1 gitlab-rake gitlab:backup:create
docker exec -t gitlab_web_1 /bin/sh -c 'umask 0077; tar cfz /data/backups/$(date "+%s_%Y_%m_%d_etc-gitlab.tgz") -C / etc/gitlab'
# rm -rf $TmpBakDir/* 这里用 qshell 的 delete_on_success 参数就好 好
sudo tar zcvf $TmpBakDir/$(date +"%s_%Y_%m_%d")_gitlab_backup.tgz $GitlabDir
tar zcvf $TmpBakDir/$(date +"%s_%Y_%m_%d")_drone_backup.tgz $DroneDir
cd /home/ubuntu/tools
rm -rf /home/ubuntu/.qshell/qupload
./qshell qupload qshellconf.json