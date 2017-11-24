# simple-bash-workflow
`simple-bash-workflow` is a bash framework to execute simple jobs, defined by sequences of bash commands, with support for multiple environment configuration, controlled execution and log4j style logging. It was built to automate batch file processing, but can be easily extended for other purposes. 

## Example workflow

```bash
BASE_DIR="$(dirname $( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd ))"
source $BASE_DIR/lib/common.sh
source $BASE_DIR/lib/ft_lib.sh

# Load configuration and initialize the scripting framework
common::initialize $@ || exit 1

# Clean up work directories (inbox, outbox and temp)
ft_lib::clean_work_dirs &&

# Download files via SFTP
ft_lib::sftp_download_from $SOURCE_CONN_STR $SOURCE_DIR "*.txt" $INBOX_DIR 
|| exit 1 # Exit if unable to download files

# Check if files exist and archive files and exit without errors if no files are found
ft_lib::check_and_archive_files $INBOX_DIR $ARCHIVE_DIR; [ $? -eq 2 ] && exit 0 

# Move files from Inbox to outbox
mv $INBOX_DIR/*.txt $OUTBOX_DIR

# Upload files from the outbox dir to destination system via SFTP
ft_lib::sftp_upload_to $DEST_CONN_STR $OUTBOX_DIR "*" $DEST_DIR
```
## Configuration

Each workflow has its own configuration file located on /etc/{env}/<workflow name>.conf. All workflow scripts load a top-level configuration file and attempt to identify the environment they are running in. There are currently 3 hardcoded environments options: `dev`, `stg` and `prod`, that must correspond to directories inside `/etc`.

### Top-level configuration

Located in `etc/common.conf` this file defines the environment hosts and any other common variables you need.
```bash
STG_HOST="prod.example.com"
PRD_HOST="stg.example.com"
```
Only STG and PRD hosts need to be defined. If current host is different, it is assumed we are in development.

### Environment specific configuration

It is possible to define configuration settings per environment: working directories, hosts, credentials, any other varibles you need. Each environment has a common file that will be included by all workflows. Example of `/etc/dev/common.conf`

```bash
# Relative directories
JOB_DIR="$BASE_DIR/data/${SCRIPTNAME%.*}"

ARCHIVE_SUBDIR="Archive"
TEMP_SUBDIR="tmp"
INBOX_SUBDIR="in"
OUTBOX_SUBDIR="out"
LOG_SUBDIR="log"
ARCHIVE_DIR=$JOB_DIR/$ARCHIVE_SUBDIR
TEMP_DIR=$JOB_DIR/$TEMP_SUBDIR
INBOX_DIR=$JOB_DIR/$INBOX_SUBDIR
OUTBOX_DIR=$JOB_DIR/$OUTBOX_SUBDIR

NUM_RETRIES_ON_FAILURE=3
WAIT_BEFORE_RETRY_SECONDS=5
```
### Workflow specific configuration

Each workflow can have its settings, in a per-environment basis. Example of `/etc/dev/example_workflow.conf`
```bash
# Environment will define which common configuration settings will be included
# DO NOT REMOVE THE LINES BELOW
ENV="dev"
source "$BASE_DIR/etc/$ENV/common_$ENV.conf"

# Workflow specific settings
SOURCE_CONN_STR="jmc@127.0.0.1"
SOURCE_DIR="a"
DEST_CONN_STR="jmc@127.0.0.1"
DEST_DIR="b"
```






