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
