#-------------------------------------------------------------
# File transfer function library
#-------------------------------------------------------------

# Download files from a SFTP server
function ft_lib::sftp_download_from {
  local conn_str=$1
  local source_dir=$2
  local source_files=$3
  local dest=$4
  log::info "Downloading files from $conn_str: $source_dir/$source_files"
  common::exec true sftp $conn_str <<EOF
  mget $source_dir/$source_files $dest
  bye
EOF
}

# Upload files to a SFTP server
function ft_lib::sftp_upload_to {
  local conn_str=$1
  local source_dir=$2
  local source_files=$3
  local dest=$4
  common::check_files_exist "$source_dir/$source_files"
  if [ $? -eq 0 ]; then
    log::info "Uploading files to $conn_str: $dest"
    log::no_prefix "$(ls -d $source_dir/$source_files)"
    common::exec true scp "$source_dir/$source_files" $conn_str:$dest/
    return $?
  fi
  return 0
}

# Archive files on the Inbox folder
function ft_lib::check_and_archive_files {
  local date=`date "+%Y-%m-%d_%H%M%S"`
  local source_dir="$1"
  local archive_dir="$2/$date"

  # Check if files exist and return error code 2 in case they don't
  common::check_files_exist "$source_dir" || return 2

  log::debug "Archiving files ($source_dir -> $archive_dir)"
  log::no_prefix "$(ls -d $source_dir/*)"
  result=$(mkdir $archive_dir && cp $source_dir/* $archive_dir)

  if [ $? != 0 ]; then
      log::error "Failed to archive files: '$result'"
      echo $result
      return 1
  fi
  return 0
}

# Clean up work directories (inbox, outbox & temp)
function ft_lib::clean_work_dirs {
  local dirs=($INBOX_DIR $OUTBOX_DIR $TEMP_DIR)
  for i in ${dirs[*]}
  do
    result=$(rm -f $i/* 2>&1)
    if [ $? -eq 1 ]; then
      log::error "Unable to clean-up directories: $result"
      return 1
    fi
  done
  log::info "Successfully cleaned up work directories"
  return 0
}
