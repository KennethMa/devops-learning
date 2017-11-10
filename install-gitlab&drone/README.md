虽然[两年前](https://gist.github.com/KennethMa/2ce20178820c2a696b8f)就捣鼓了不少 [Docker](https://www.docker.com/what-docker)、[CI](https://zh.wikipedia.org/wiki/%E6%8C%81%E7%BA%8C%E6%95%B4%E5%90%88)/[CD](https://zh.wikipedia.org/wiki/%E6%8C%81%E7%BA%8C%E4%BA%A4%E4%BB%98) 相关的东西，但都没有系统地学习 [DevOps](https://zh.wikipedia.org/wiki/DevOps)，所以打算写一个系列的博文来记录下自己的学习过程，共勉。

## TL;DR
> 本篇文章记录使用 [Docker Compose](https://docs.docker.com/compose/overview/) 安装 [GitLab](https://docs.gitlab.com/omnibus/README.html) 与 [Drone](http://docs.drone.io/zh/) 的经验，然后会讲如何利用 [Crontab](http://pubs.opengroup.org/onlinepubs/7908799/xcu/crontab.html) 和 [qshell](https://github.com/qiniu/qshell) 定期把数据备份到七牛云，相关的代码会放到 [GitHub](https://github.com/KennethMa/devops-learning)。

## 前提
* Ubuntu 16.04.1
* Docker CE 17.06
* GitLab CE 10.1.1
* Drone 0.8

## 安装 GitLab
 GitLab 官方有维护一个 [Omnibus Gitlab](https://docs.gitlab.com/omnibus/README.html)，所以这里我们会用到相应的 [Docker 镜像](https://hub.docker.com/r/gitlab/gitlab-ce/)。

``` yml
web:
  image: 'gitlab/gitlab-ce:latest'
  restart: always
  hostname: '127c87a9.ngrok.io''
  environment:
    GITLAB_OMNIBUS_CONFIG: |
      external_url 'http://127c87a9.ngrok.io'
      gitlab_rails['backup_path'] = '/data/backups'
  ports:
    - '8080:80'
    - '22:22'
  volumes:
    - './gitlab/config:/etc/gitlab'
    - './gitlab/logs:/var/log/gitlab'
    - './gitlab/data:/var/opt/gitlab'
    - './gitlab/backups:/data/backups'
```

注意这里需要设置 `hostname` 为你的域名，并在环境变量里设置 `external_url` 加上协议，`gitlab_rails['backup_path']` 是设置 GitLab 的备份路径，我们把它挂载到当前目录下的 `./gitlab/backups` ，方便后续备份。然后执行如下命令：
``` bash
$ docker-compose up -d
```
> 这里安利下 [ngrok](https://ngrok.com/) 这款软件，作为前端经常会有「把本机开发中的 web 项目给朋友看一下」这种临时需求，官网注册一个免费账号便可使用其强大的内网穿透功能。

几秒钟之后我们打开配置的域名，就能看到服务跑起来了，初始化页面要求设置 root 用户的密码。

进来之后点击顶栏的扳手图标（`Admin area`），再点击侧边栏的 `Application`（路由 `/admin/applications`），新增一个系统级应用，使 GitLab 作为 OAuth 服务提供者，授权给 CI 服务。配置如下图所示：
![](https://ww1.sinaimg.cn/large/006zqIDbgy1fl6ddpysp8j31420lwmzw.jpg)

这里的回调地址是 CI 服务的域名＋`/authorize`，`Trusted`选项如果勾选则登录 CI 时  GitLab 会自动授权，这里 `OpenID` 我们不需要，所以勾选其他两项，点击提交，生成 `Application Id` 和 `Secret `。

## 安装 Drone
Drone 是一款开源的轻量级持续交付工具，内置 Docker，由 Go 语言编写。大家如果混 GitHub 比较多的话应该都熟悉 [Travis CI](https://travis-ci.org/)，基本和这个差不多啦。

首先编写我们的 `docker-compose.yml`：
``` yml
version: '2'

services:
  drone-server:
    image: drone/drone:0.8
    ports:
      - 8081:8000
    volumes:
      - ./:/var/lib/drone/
    restart: always
    environment:
      - DRONE_HOST=http://018c370d.ngrok.io
      - DRONE_OPEN=true
      - DRONE_SECRET=h6y7tFxBn794oEoA
      - DRONE_ADMIN=billy,root
      - DRONE_GITLAB=true
      - DRONE_GITLAB_CLIENT=e01aaa85b97b6c7cd38419f35a4d1d3493d875a62c7437579f394c3764854ef2
      - DRONE_GITLAB_SECRET=56ba5ce6eeb53866ac986cb8be89721816d5e75b15f8c520b8346afd6f3a0628
      - DRONE_GITLAB_URL=http://127c87a9.ngrok.io
  
  drone-agent:
    image: drone/agent:0.8
    restart: always
    depends_on:
      - drone-server
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
    environment:
      - DRONE_SERVER=drone-server:9000
      - DRONE_SECRET=h6y7tFxBn794oEoA
      - DRONE_MAX_PROCS=3
```

这里注意，`DRONE_HOST ` 选项填上 drone 服务的域名；`drone-server` 与 `drone-agent` 的环境变量 `DRONE_SECRET` 要设置成一致的随机字符串；`DRONE_GITLAB_CLIENT` 填写上一步 GitLab 生成的 `Application Id`；`DRONE_GITLAB_SECRET `填写上一步 GitLab 生成的 `Secret`；`DRONE_GITLAB_URL` 填写 GitLab 服务的链接。

Drone 的数据库是 `SQLite`，所以我们把数据库文件挂载到当前文件夹，方便后续备份。

执行命令：
``` bash
$ docker-compose up -d
```

然后打开 drone 的链接，完成授权，即可看到当前用户的 git repo 列表。

## 数据备份
这一步虽说是可选的，但还是建议大家做下异地备份，有的云服务商提供定期快照功能，也可以用那个。

这里介绍大家使用七牛云的 [qshell](https://github.com/qiniu/qshell) 上传备份文件。按文档说明下载下来后，设置好环境变量，然后执行：
``` bash
$ qshell account Account_Key Secret_Key
```
这会在 `/home/xxx/.qshell/` 目录下生成 `account.json`，后续的上传都会依赖于此文件做认证。

备份脚本我就直接贴了：
``` shell
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
```

这里注意，我们备份 GitLab 配置文件时，设置只有 root 才能操作该备份文档，所以需要在下面的压缩命令加上 `sudo`；`qshell` 上传文件成功后会生成缓存在 `/home/xxx/.qshell/qupload` 目录下，所以上传之前需要清空该文件夹。

`qshell` 的配置文件 `qshellconf.json` 内容如下：
``` json
{"bucket": "Bucket Name", "src_dir": "/home/ubuntu/backups", "file_type": 1, "delete_on_success": true}
```

然后我们在 `/etc/cron.d` 目录下新建一个文件 `git_ci_backups`，写入：
``` txt
0 6 * * 2-7 ubuntu /home/ubuntu/tools/backup.sh >/dev/null 2>&1
```

这样一来，每周二至周天的早晨六点，都会执行脚本备份数据。

上述是关于如何使用 `docker-compose` 手动安装的过程，既然用了容器，那使用 `kubernetes` 也是顺理成章，下面我会跟大家分享如何使用 `kubernetes` 来安装如上应用。

待续 -