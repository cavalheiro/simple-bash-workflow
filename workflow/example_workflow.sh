#!/bin/bash

BASE_DIR="$(dirname $( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd ))"
source $BASE_DIR/lib/common.sh
source $BASE_DIR/lib/ft_lib.sh

# Load configuration and initialize the scripting framework
common::initialize $@ || exit 1

# ------------------------------------
#  Example workflow
# ------------------------------------

# Clean up work directories (inbox, outbox and temp)
ft_lib::clean_work_dirs &&

# Download files via SFTP
ft_lib::sftp_download_from $SOURCE_CONN_STR $SOURCE_DIR "*.txt" $INBOX_DIR || exit 1 # Exit if unable to download files

# Check if files exist and archive files and exit without errors if no files are found
ft_lib::check_and_archive_files $INBOX_DIR $ARCHIVE_DIR; [ $? -eq 2 ] && exit 0 # return code 2 means no files found

# Move files from Inbox to outbox
mv $INBOX_DIR/*.txt $OUTBOX_DIR

# Upload files from the outbox dir to destination system via SFTP
ft_lib::sftp_upload_to $DEST_CONN_STR $OUTBOX_DIR "*" $DEST_DIR
