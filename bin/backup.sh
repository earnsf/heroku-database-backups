#!/bin/bash

# terminate script as soon as any command fails, of variable undefined or piped command fails
set -euo pipefail

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
# Create and use a temp dir which we remove at the end
TMP_DIR=$SCRIPT_DIR/scratch
mkdir -p $TMP_DIR
cd $TMP_DIR

if [[ -z "${APP:-}" ]]; then
  echo "Missing APP variable which must be set to the name of your app where the db is located"
  exit 1
fi

if [[ -z "${DATABASE:-}" ]]; then
  echo "Missing DATABASE variable which must be set to the name of the DATABASE you would like to backup"
  exit 1
fi

if [[ -z "${S3_BUCKET_PATH:-}" ]]; then
  echo "Missing S3_BUCKET_PATH variable which must be set the directory in s3 where you would like to store your database backups"
  exit 1
fi

# install aws-cli
#  - this will already exist if we're running the script manually from a dyno more than once

PATH=$PATH:/tmp/bin

if ! hash aws 2>/dev/null; then
  echo "aws cli v2..."
  curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
  unzip -q awscliv2.zip
  ./aws/install --bin-dir /tmp/bin --install-dir /tmp/aws
fi

# if the app has heroku pg:backup:schedules, we might just want to just archive the latest backup to S3
# https://devcenter.heroku.com/articles/heroku-postgres-backups#scheduling-backups
#
# set ONLY_CAPTURE_TO_S3 when calling to skip database capture

BACKUP_FILE_NAME="$(date +"%Y-%m-%d_%H-%M_%Z__")${APP}_${DATABASE}.dump"

if [[ -z "$ONLY_CAPTURE_TO_S3" ]]; then
  heroku pg:backups capture $DATABASE --app $APP
else
  BACKUP_FILE_NAME="archive__${BACKUP_FILE_NAME}"
  echo " --- Skipping database capture"
fi

echo "Listing backups"
heroku pg:backups --app $APP

echo "Downloading latest backup as $BACKUP_FILE_NAME"
heroku pg:backups:download --output $BACKUP_FILE_NAME --app $APP

FINAL_FILE_NAME=$BACKUP_FILE_NAME
echo Dump file size
ls -lh $FINAL_FILE_NAME

if [[ -z "${NOGZIP:-}" ]]; then
  gzip $BACKUP_FILE_NAME
  FINAL_FILE_NAME=$BACKUP_FILE_NAME.gz
  echo Gzipped file size
  ls -lh $FINAL_FILE_NAME
fi

if [[ -n "${PG_BACKUP_PASSWORD:-}" ]]; then
  echo "Encrypting backup..."
  ENCRYPTED_FILE_NAME="${FINAL_FILE_NAME}.encrypted"
  gpg --batch --passphrase=$PG_BACKUP_PASSWORD --output $ENCRYPTED_FILE_NAME --symmetric --cipher-algo AES256 $FINAL_FILE_NAME
  # Remove unencrypted file
  rm $FINAL_FILE_NAME
  # You can use the following command to decrypt:
  # gpg --batch --passphrase=$PG_BACKUP_PASSWORD --output DECRYPTED_OUTPUT_FILE --decrypt ENCRYPTED_INPUT_FILE
  FINAL_FILE_NAME=$ENCRYPTED_FILE_NAME
fi


aws s3 cp $FINAL_FILE_NAME s3://$S3_BUCKET_PATH/$APP/$DATABASE/$FINAL_FILE_NAME

echo "backup $FINAL_FILE_NAME complete"

if [[ -n "$HEARTBEAT_URL" ]]; then
  echo "Sending a request to the specified HEARTBEAT_URL that the backup was created"
  curl $HEARTBEAT_URL
  echo "heartbeat complete"
fi

cd $SCRIPT_DIR
echo "Removing temp files $TMP_DIR"
rm -rf $TMP_DIR