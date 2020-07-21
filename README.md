# _Streaming_ MongoBURS

Streaming Mongo backup and restore for AWS and GCP.

[![Docker Repository on Quay](https://quay.io/repository/utilitywarehouse/streaming-mongo-burs/status "Docker Repository on Quay")](https://quay.io/repository/utilitywarehouse/streaming-mongo-burs)

## About
This is a simple tool to backup and restore mongo collections from S3. Data is streamed through a configurable compression algorithm directly to S3 without using ephemeral storage on a node, with the exception of a legacyRestore operation, which will copy data to ephemeral storage for compatibility.

This work is based on the original `mongo-burs` script however differs significantly from it, as backups are now BSON blobs from `mongodump`; this is what allows streaming. 

### Backup
Run the container in your environment (typically on a cron) with the configured environment variables

### Restore
Run the container with the following arguments `restore $TIMESTAMP $COLLECTIONS`. If you are restoring backups made prior to mongo-burs v1.4.0 use `legacyRestore` instead of _restore_; this is due to previous versions creating an archive of a mongo dump directory, rather than compressing an archive binary blob. Both commands take the same `$TIMESTAMP` and `$COLLECTIONS` args.

|Argument|Format|Description|
|--------|------|-----------|
|TIMESTAMP|YYYY-MM-DDTHH-MM-SS (2019-01-01T12:42:04)|the date to restore the database from|
|COLLECTIONS|Database.Collection,... (test.test,test.test2)|the collections you wish to restore into the database as a CSV string|


### Environment Variables

|ENV|Description|Required|
|---|-----------|--------|
|MONGO|a mongo connection string|[x]|
|BUCKET|the name of the bucket you want to backup the database to|[x]|
|AWS_ACCESS_KEY_ID|the aws key ID|[x] (AWS only)|
|AWS_SECRET_ACCESS_KEY|the aws secret key|[x] (AWS only)|
|AWS_REGION|the aws region|[x] (AWS only)|
|GOOGLE_CREDENTIALS_PATH|location of the service account JSON file|[x] GCP only|
|COMPRESSION|compression algorithm to use, default `gzip`, other options are `xz` and `zstd`||
|VOLUME_MOUNT|optional path to mounted PVC to use as temporary storage||

***Note***
in addition to the `GOOGLE_CREDENTIALS_PATH` env var you will need to mount the credentials file into the container


## Examples
### AWS
```
apiVersion: batch/v1beta1
kind: CronJob
metadata:
  labels:
    app: a-mongo-backup
  name: a-mongo-backup
  namespace: your_namespace
spec:
  schedule: "@daily"
  successfulJobsHistoryLimit: 1
  failedJobsHistoryLimit: 1
  concurrencyPolicy: Forbid
  jobTemplate:
    spec:
      template:
        spec:
          restartPolicy: Never
          containers:
            - name: burs
              image: registry.uw.systems/energy/energy-mongo-burs:v1.0.0
              env:
                - name: MONGO
                  valueFrom:
                    secretKeyRef:
                      key: backup.mongo.servers
                      name: a-mongo-backup-secrets
                - name: AWS_ACCESS_KEY_ID
                  valueFrom:
                    secretKeyRef:
                      key: aws.key
                      name: a-mongo-backup-secrets
                - name: AWS_SECRET_ACCESS_KEY
                  valueFrom:
                    secretKeyRef:
                      key: aws.secret
                      name: a-mongo-backup-secrets
                - name: AWS_REGION
                  value: eu-west-1
                - name: BUCKET
                  value: some-aws-bucket
                - name: COMPRESSION
                  value: zstd
              imagePullPolicy: Always
```

### GCP
```
apiVersion: batch/v1beta1
kind: CronJob
metadata:
  labels:
    app: a-mongo-backup
  name: a-mongo-backup
  namespace: your_namespace
spec:
  schedule: "@daily"
  successfulJobsHistoryLimit: 1
  failedJobsHistoryLimit: 1
  concurrencyPolicy: Forbid
  jobTemplate:
    spec:
      template:
        spec:
          restartPolicy: Never
          containers:
            - name: burs
              image: registry.uw.systems/energy/energy-mongo-burs:v1.0.0
              env:
                - name: MONGO
                  valueFrom:
                    secretKeyRef:
                      key: backup.mongo.servers
                      name: a-mongo-backup-secrets
                - name: GOOGLE_CREDENTIALS_PATH
                  value: /var/gcp/service_account.json
                - name: BUCKET
                  value: some-aws-bucket
              imagePullPolicy: Always
              volumeMounts:
                - mountPath: /var/gcp
                  name: creds
                  readOnly: true
          volumes:
            - name: creds
              secret:
                secretName: a-mongo-backup-secrets
                items:
                  - key: gcp.creds.json
                    path: service_account.json


```
