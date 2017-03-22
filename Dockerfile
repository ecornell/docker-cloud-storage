FROM tcf909/ubuntu-slim:latest
MAINTAINER T.C. Ferguson <tcf909@gmail.com>

ARG RCLONE_URL=http://downloads.rclone.org/rclone-v1.36-linux-amd64.zip
ARG RCLONE_BUILD_DIR=/usr/local/src

ARG MERGERFS_URL=https://github.com/trapexit/mergerfs/releases/download/2.19.0/mergerfs_2.19.0.ubuntu-xenial_amd64.deb

RUN \
    apt-get update && \
    apt-get upgrade && \

#RCLONE
    apt-get install \
        wget \
        unzip \
        fuse && \
    cd ${RCLONE_BUILD_DIR} && \
    wget -q $RCLONE_URL -O rclone.zip && \
    unzip -j rclone.zip -d rclone && \
    mv ${RCLONE_BUILD_DIR}/rclone/rclone /usr/local/bin/ && \
    rm -rf ${RCLONE_BUILD_DIR}/rclone && \

#MERGERFS
    apt-get install \
        curl \
        fuse && \
    curl -L -o /tmp/mergerfs.deb ${MERGERFS_URL} && \
    apt-get install /tmp/mergerfs.deb && \

#RSYNC
    apt-get install rsync && \

#WATCHER
    apt-get install \
        inotify-tools && \

#FILEBOT
    apt-get install openjdk-8-jre libmediainfo0v5 && \
    mkdir -p /tmp/filebot && cd /tmp/filebot && \
    curl -o filebot-amd64.deb -L 'http://filebot.sourceforge.net/download.php?type=deb&arch=amd64' && \
    dpkg --force-depends -i filebot-*.deb && \
    cd ~ && \

#CLEANUP
    apt-get autoremove && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* \
    rm -rf /tmp/*

RUN \
    if [ "${DEBUG}" = "true" ]; then \
        apt-get update && \
        apt-get install iptables net-tools iputils-ping mtr && \
        apt-get autoremove && \
        apt-get clean && \
        rm -rf /var/lib/apt/lists/* /tmp/*; \
    fi

COPY rootfs /

#RSYNC
EXPOSE 873

CMD ["/sbin/my_init"]

#mergerfs -o defaults,max_readahead=32M,allow_other,direct_io,use_ino,moveonenospc=true,category.action=all,category.create=ff,category.search=ff,func.getattr=newest /mnt/test1:/mnt/test2 /mnt/test