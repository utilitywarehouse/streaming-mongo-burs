#!/bin/bash

set -eo pipefail

##
# Make sure we can upload to an actual bucket
#

if [[ -z "${BUCKET}" ]];then
    echo "Missing required BUCKET env VAR"
    exit 1
fi


if [[ -z "${MONGO}" ]];then
    echo "Missing required MONGO env VAR"
    exit 1
fi

UTIL="aws s3"
CRYPTO="--sse AES256"
BUCKET_PREFIX="s3"

if [[ -z "${GOOGLE_CREDENTIALS_PATH}" ]];then

    if [[ -z "${AWS_ACCESS_KEY_ID}" ]];then
        echo "missing required AWS_ACCESS_KEY_ID env var"
        exit 1
    fi

    if [[ -z "${AWS_SECRET_ACCESS_KEY}" ]];then
        echo "missing required AWS_SECRET_ACCESS_KEY env var"
        exit 1
    fi

    if [[ -z "${AWS_REGION}" ]];then
        echo "missing required AWS_REGION env var"
        exit 1
    fi
else
    stat ${GOOGLE_CREDENTIALS_PATH}
    if [[ $? -ne 0 ]];then
        echo "invalid service account json location"
        exit 1
    fi
    UTIL="gsutil"
    CRYPTO=""
    BUCKET_PREFIX="gs"
    gcloud auth activate-service-account --key-file=${GOOGLE_CREDENTIALS_PATH}
    if [[ $? -ne 0 ]];then
        echo "unable to authenticate service account with google"
        exit 1
    fi
fi

function doBackup {
    local timestamp=`date +%Y-%m-%dT%H-%M-%S`
    local backup_name="${timestamp}"
    local algo=`echo ${COMPRESSION}| awk '{print tolower($0)}'`
    
	case $algo in
        gzip)
            backup_name="${backup_name}.gz"
            ;;
        xz)
            backup_name="${backup_name}.xz"
            algo="${algo} -zT0"
            ;;
        zstd)
            backup_name="${backup_name}.zst"
            algo="zstd -zT0"
            ;;
        *)
            backup_name="${backup_name}.gz"
            algo="gzip"
            ;;
    esac
    
    local bucket_path="$BUCKET_PREFIX://$BUCKET/$backup_name"

    mongodump --uri ${MONGO} --archive | eval $algo - | $UTIL cp $CRYPTO - ${bucket_path}
    if [[ $? -ne 0 ]];then
     echo "Failed to create mongo dump!"
        exit 1
    fi

    ##
    # Success
    #
    echo "Successfully created backup ${backup_name}, available at ${bucket_path}"
}


function doRestore {
    local backup_name="${TIMESTAMP}"
    local algo=`echo $COMPRESSION | awk '{print tolower($0)}'`
    case $algo in
        gzip)
            backup_name="${backup_name}.gz"
            algo="gzip -cd"
            ;;
        xz)
            backup_name="${backup_name}.xz"
            algo="${algo} -cd"
            ;;
        zstd)
            backup_name="${backup_name}.zst"
            algo="${algo} -cd"
            ;;
        *)
            backup_name="${backup_name}.gz"
            algo="gzip -cd"
            ;;
    esac
    local bucket_path="$BUCKET_PREFIX://$BUCKET/$backup_name"

    local nsIncludes=""
    if [[ -n $COLLECTIONS ]]; then
        nsIncludes="--nsInclude=\"$(echo ${COLLECTIONS} | sed "s/,/\" --nsInclude=\"/g")\""
    fi

    $UTIL cp ${bucket_path} - | eval $algo | mongorestore --uri ${MONGO} --archive ${nsIncludes}
    if [[ $? -ne 0 ]]; then
        echo "Failed to restore mongo dump ${bucket_path}"
        exit 1
    fi

    echo "finished restore"
}


function doLegacyRestore {
    local backup_name="${TIMESTAMP}.tar.gz"
    local bucket_path="$BUCKET_PREFIX://$BUCKET/$backup_name"
    mkdir restore

    $UTIL cp $bucket_path $backup_name
    if [[ $? -ne 0 ]];then
     echo "Failed to copy mongo dump from bucket ${bucket_path}"
        exit 1
    fi

    tar -zxvf $backup_name
    rm $backup_name

    for i in $(echo ${COLLECTIONS} | sed "s/,/ /g")
    do
        local database=$(echo ${i} | awk -F "/" '{print $1}')
        local collection=$(echo ${i} | awk -F "/" '{print $2}')

        mkdir -p restore/$database
        mv ${TIMESTAMP}/${i}.bson restore/$database
        mv ${TIMESTAMP}/${i}.metadata.json restore/$database
        echo ${i}
    done

    rm -rf ${TIMESTAMP}
    mongorestore --uri ${MONGO} --dir restore
    if [[ $? -ne 0 ]];then
     echo "Failed to restore mongo dump ${bucket_path}"
        rm -rf restore
        exit 1
    fi
    rm -rf restore

    echo "finished legacy restore"
}


case $1 in
    restore)
        TIMESTAMP=$2
        COLLECTIONS=$3
        doRestore
    ;;
    legacyRestore)
        TIMESTAMP=$2
        COLLECTIONS=$3
        doLegacyRestore
    ;;
    *)
        doBackup
    ;;
esac
