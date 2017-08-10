#!/bin/bash
SCRIPTNAME=$(basename $0)

#Logging functions
function __write_to_log {
  # generate call stack to print in log. args 0 and 1 will be ignored as they represent the calls to logging functions
  # LOG_FILE variable is defined during configuration load (see @common::initialize )
  local call_stack=()
  for (( i=${#FUNCNAME[@]}-1 ; i>1 ; i-- )) ; do
    call_stack+=$(printf ".'${FUNCNAME[i]}'" $call_stack)
  done
  call_stack=${call_stack:1} # remove first '.'

  local level="$1"
  local msg="$2"
  local timeAndDate=`date "+%Y-%m-%d %H:%M:%S"`

  log_redirect=$( $LOG_TO_STDOUT && echo "tee -a $LOG_FILE" || echo "cat >> $LOG_FILE")

  if [ $level = NO_PREFIX ]; then
    printf "$msg\n" | eval $log_redirect
  else
    printf "\n[%s] [%s] %s - %s\n" "$timeAndDate" "$level" "$call_stack" "$msg" | eval $log_redirect
  fi
}

function log::error { __write_to_log ERROR "$1"; }
function log::warn { __write_to_log WARN "$1"; }
function log::info { __write_to_log INFO "$1"; }
function log::debug { __write_to_log DEBUG "$1"; }
function log::no_prefix { __write_to_log NO_PREFIX "$1"; }


#Execute and log output
function common::exec {
  local retry_on_failure=$1
  local command=${@:2}

  if ( $retry_on_failure ); then
    num_retries=$NUM_RETRIES_ON_FAILURE
  else
    num_retries=1;
  fi
  # try counter
  local n=1
  until [ $n -gt $num_retries ]; do
    local log_msg="Invoking external command '${command:0:8192}'"
    #__result cannot be a global variable, otherwise execution return is not correctly caputured
    __result=$(eval $command 2>&1)
    local code=$?
    if [ $code != 0 ]; then
        log_msg+=" - Try #$n of $num_retries - ERROR code $code: $__result"
        log::error "$log_msg"
      else
        log::no_prefix "$log_msg"
        #echo "$log" # return output of command execution in case of succcess
        break
    fi
    n=$[$n+1]
    if [ $n -le $num_retries ]; then sleep $WAIT_BEFORE_RETRY_SECONDS; fi
  done
  return $code
}

#Parse command line options and load configuration
function common::initialize {
  local date=`date "+%Y-%m-%d"`
  local ENV

  # Parse command line options
  for i in "$@"
  do
  case $i in
      --config-file=*)
      local CONFIG_FILE="${i#*=}"
      shift
      ;;
      --silent)
      LOG_TO_STDOUT=false
      shift
      ;;
      *)
      ;;
  esac
  done

  #Load common config file
  source "$BASE_DIR/etc/common.conf" || (echo "Unable to load common configuration file at $BASE_DIR/etc/common.conf" && exit 1)

  # Attempt to determine environment
  local hostname=$(hostname)
  if [ $hostname = $STG_HOST ]; then
    ENV="stg"
  elif [ $hostname = $PRD_HOST ]; then
    ENV="prod"
  else
    ENV="dev"
  fi

  CONFIG_FILE="$BASE_DIR/etc/$ENV/${SCRIPTNAME%.*}.conf"
  # Exit if no configuration file is specified
  if [ ! -f $CONFIG_FILE ]; then
    echo "Config file was not found or is invalid: '$CONFIG_FILE'."
    return 1
  fi
  # Load configuration file
  source $CONFIG_FILE || return 1; #Exit in case configuration loading fails

  # Initialize logging
  LOG_FILE="$JOB_DIR/$LOG_SUBDIR/${SCRIPTNAME%.*}_$date.log"
  mkdir -p "$JOB_DIR/$LOG_SUBDIR" && touch "$LOG_FILE"

  log::no_prefix "\n\n\n=== Starting execution of script runtime '$SCRIPTNAME' with PID '$$' and '$ENV' configuration file '$CONFIG_FILE'"
  log::no_prefix "=== Using log file '$LOG_FILE'"
  # Setup job working directories (create them if necessary)
  common:setup_workdir
  if [ ! $? -eq 0 ]; then
    echo "Initialization failure - unable to setup work dirs"
    exit 1
  fi
  # Check if this job is already running
  [ "$SKIP_PID_CHECK" = true ] || common:check_pid
  # Ensure PID file is removed on program exit.
  trap "common:exit_routine" EXIT
}

# Handle exit scenarios
function common:exit_routine {
  if [ $? -eq 0 ]; then
    log::info "Execution complete"
  else
    log::error "Failed to complete script execution"
  fi
  # Remove PID file
  [ -f "$pidfile" ] && rm $pidfile
}

# Standard PID execution check
function common:check_pid {
  # Check if script is already running
  pidfile="$JOB_DIR/$SCRIPTNAME.pid"
  if [ -e $pidfile ]; then
    local msg="This job is already running, with PID file $pidfile"
    log::error "$msg"
    echo "$msg"
    exit 1
  else
    # Create a file with current PID to indicate that process is running.
    echo $$ > "$pidfile"
    return 0
  fi
}

#Setup subdirectories on Job work directory
function common:setup_workdir {
  log::debug "Directory configuration"
  log::no_prefix "Archive dir: $ARCHIVE_DIR"
  log::no_prefix "Temp dir: $TEMP_DIR"
  log::no_prefix "Inbox dir: $INBOX_DIR"
  log::no_prefix "Outbox dir: $OUTBOX_DIR"
  log::no_prefix "Log dir: $JOB_DIR/$LOG_SUBDIR"
  # Create job directories if they don't exist
  result=$(mkdir -p "$ARCHIVE_DIR" 2>&1 &&
  mkdir -p "$TEMP_DIR" 2>&1 &&
  mkdir -p "$INBOX_DIR" 2>&1 &&
  mkdir -p "$OUTBOX_DIR" 2>&1)

  if [ $? -eq 1 ]; then
    log::error "Unable to create work directories: $result"
    return 1
  else
    return 0
  fi
}

#Setup subdirectories on Job work directory
function common:create_folder {
  local job_id=$1 && [ -z "$job_id" ] && log::error "$EMPTY_ARG_MSG: source_dir" && return 1
  log::info "Creating folder $1 in INBOX($INBOX_DIR/$1) and OUTBOX($OUTBOX_DIR/$1)"

  # Create job directories if they don't exist
  result=$(mkdir -p "$INBOX_DIR/$job_id" 2>&1 &&
  mkdir -p "$OUTBOX_DIR/$job_id" 2>&1)

  if [ $? -eq 1 ]; then
    log::error "Unable to create folder: $result"
    return 1
  else
    return 0
  fi
}

# Count files on a given directory
function common::count_files {
  local filecount=$(ls $1 2>/dev/null | wc -l | tr -d '\040')
  echo $filecount
  return 0
}

# Check if a directory contains files
function common::check_files_exist {
  local filecount=$(common::count_files "$1")
  if [ $filecount -gt 0 ]; then
    return 0
  else
    log::warn "No files to process on $1."
    return 1
  fi
}
