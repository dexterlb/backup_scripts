#!/bin/bash

restic_cmd=restic
retention=(--keep-daily 5 --keep-weekly 3 --keep-monthly 6 --keep-yearly 30)

# What to backup and what not to backup
backups=(
    some_dir:dir:/absolute/path/to/some/dir
)

common_tag=auto_backup

repo=rest:http://user:pass@host:port/repo
repo_password=i_am_so_secret
repo_compression=max

error_email="foo@example.com"
