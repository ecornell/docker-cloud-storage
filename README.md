~DOCS ARE A WORK IN PROGRESS~

This image was primarily built for use with a cloud based media center. Its primary purpose is to provide a media service (Plex, or otherwise) with a native filesystem to serve content from while that content is actually being permantely stored in a cloud storage service (such as Amazon Cloud Drive, etc.).

There is a particular workflow which has been evolved over the life of this container that has worked well for my media needs.

Directory Structure:
/data (Empty)
/data/.Local (local storage / buffer for .Vault)
/data/.Vault (remote storage via rclone mount and where all media should end up)
/data/Media (union filesystem via mergerfs )
/data/Media/Incoming (unsanitized data)
/data/Media/Unsorted (used by Filebot when it can't find a strict match)
/data/Media/Shows (where TV Show media is permanently stored)
/data/Media/Movies (where Movie media is permanently stored)

My Example Data Workflow:
1) All new data is brought in to the environment via /data/Media/Incoming. This is exposed via an RSYNC service, but as long as new data hits this folder first (in an atomic fashion), it will be taken through the workflow.
2) When a file or directory appears (created, moved_to) in /data/Media/Incoming it should kick off a Watcher that runs Filebot to analyze, rename and move the new media.
3) Sanitized media is moved in to one of three folders /data/Media/(Unsorted|Shows|Movies)
4) When a file is (created, moved_to, written_to) in /data/.Local it triggers a script to copy that file to the .Vault.  This ensures that we have a copy in our cloud storage. Because we are using MergerFS, this will also trigger a plex event if you are monitoring for Library changes in Plex.
5) When a file is copied to the cloud, it checks to see how much free space is available .Local. If it's available space drops below 50% (Default). It will begin to move files out of .Local to .Vault based on last access time. Because the files should already be in the cloud, it will only send data if the file modification time is newer locally or if there is a size difference between the local and remote file.
6) MergerFS hides the real location of the files and will serve local files first if available, otherwise will stream the file on demand from the cloud if needed.

Components:

RCLONE:
Used to connect to various cloud services to transparently mount contents of a cloud service as a filesystem.

MERGERFS:
A union filesystem with more granularity in configuring it than other union filesystems.

RSYNC:
Used to provide a way for new media to enter the environment.

FILEBOT:
Used to sanitize incoming media, rename to meet naming standards, download correct subtitles, fetch artwork, etc.

WATCHER.sh:
Used to executed a commmand based on filesystem changes (based on inotifywait).

PIPE.sh:
A parallel processing pipeline with a persistent queue used to do concurrent operations and keep track of outputs/failures/etc.

Example Kubernetes Deployment (Plex + Cloud-Storage):
```
apiVersion: extensions/v1beta1
kind: Deployment
metadata:
  name: plex
  labels:
    name: plex
spec:
  replicas: 1
  strategy:
    type: Recreate
  template:
    metadata:
      labels:
        name: plex
      annotations:
        #Change to redeploy the containers
        version: "1" 
        #scheduler.alpha used to run the pod on a master node (single node cluster)
        scheduler.alpha.kubernetes.io/tolerations: |
          [{"key": "dedicated", "value": "master", "effect": "NoSchedule" }]
    spec:
      containers:
        - name: plex
          image: tcf909/plex
          env:
            - name: DEBUG
              value: "false"
              #Run Plex as ROOT (not ideal, but eliminates permissions incompatibilities across containers
            - name: PLEX_UID
              value: "0"
            - name: PLEX_GID
              value: "0"
             #Custom script that sets the advertise ip of the plex server every 60seconds based on a dns name
            - name: PLEX_ADVERTISE_DNS
              value: https://plex.cornercafe.net:32400
              #used to automatically register a plex server with plex account, this eliminates the need for token creations
            - name: PLEX_USERNAME
              valueFrom:
                secretKeyRef:
                  name: plex
                  key: PLEX_USERNAME
            - name: PLEX_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: plex
                  key: PLEX_PASSWORD
            - name: TZ
              value: America/Los_Angeles
          ports:
            - name: plex
              containerPort: 32400
            - name: roku-companion
              containerPort: 8324
          volumeMounts:
            - name: plex
              mountPath: /config
              subPath: plex/config
              #Use the cloud-storage mount, but mount as a slave so mounts in /data don't propogate to other containers/host
            - name: plex
              mountPath: /data:slave
              subPath: plex/data
              #Memory backed mount for fastest transcode
            - name: plex-transcode
              mountPath: /transcode
        - name: cloud-storage
          image: tcf909/cloud-storage
          #Required for fuse
          securityContext:
            #privileged only required for kubernetes to pass /dev/fuse device
            privileged: true 
            #In a normal docker instance, SYS_ADMIN capabilities is all we need for fuse
            capabilities:
              add:
                - SYS_ADMIN #This doesn't actually work for now because of something to do with using VolumeMounts to pass /dev/fuse -- require privileged
          env:
            - name: DEBUG
              value: "false"
              #Make the pipe.sh script use persistent storage so queues and failures persist beyond reboots
            - name: PIPE_TMP_DIR
              value: "/data/.pipe"
            #RCLONE_MOUNT
            - name: RCLONE_MOUNT_0
              value: "ACD_VAULT:/Media|/data/.Vault"
            - name: RCLONE_MOUNT_0_OPTIONS
              value: "--max-read-ahead 200M --buffer-size 32M --allow-other"
            #UNION_MOUNT
            - name: UNION_MOUNT_0
              value: "/data/.Local:/data/.Vault|/data/Media"
            #RSYNC_SERVER
            - name: RSYNC_SERVER_USER
              value: "root"
            - name: RSYNC_SERVER_GROUP
              value: "root"
            - name: RSYNC_SERVER_VOLUME_0
              value: "Incoming|/data/Media/Incoming"
            #FILEBOT
            - name: WATCHER_PATH_0
              value: '/data/.Local/Incoming|||[[ -f ${FILE} ]] && echo ${FILE} | /scripts/pipe.sh -t 4 "/scripts/filebot-amc.sh /data/.Local {}"'
            - name: WATCHER_PATH_0_OPTIONS
              value: '-r -e close_write -e moved_to --exclude /data/.Local/Incoming/\..+'
            #TRANSFERS
            - name: WATCHER_PATH_1
              value: '/data/.Local|||[[ -f ${FILE} ]] && echo ${FILE} | /scripts/pipe.sh -t 20 "/scripts/transfer_copy.sh /data/.Local ACD_VAULT:/Media {}" && /scripts/transfer_tier.sh /data/.Local ACD_VAULT:/Media'
            - name: WATCHER_PATH_1_OPTIONS
              value: '-r -e close_write -e moved_to --exclude /data/.Local/Incoming'
          ports:
            - name: rsync-server
              containerPort: 837
          volumeMounts:
            #FOR RCLONE_MOUNT and #UNION_MOUNT
            - name: fuse
              mountPath: /dev/fuse
            #FOR RCLONE_MOUNT
            - name: etc-rclone
              mountPath: /etc/rclone
            #Make sure to mount /data as a shared device so that all fuse devices we mount IN /data are seen in other containers
            - name: plex
              mountPath: /data:shared
              subPath: plex/data
      volumes:
        - name: fuse
          hostPath:
            path: /dev/fuse
        - name: etc-rclone
          secret:
            secretName: plex
            items:
            - key: "rclone-rclone.conf"
              path: "rclone.conf"
        - name: plex
          persistentVolumeClaim:
            claimName: plex
        - name: plex-transcode
          emptyDir:
            medium: Memory
```