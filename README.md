# AWS PGBouncer

This repository contains the code for the AWS PGBouncer project. It help you start a PGBouncer that will auto-refresh credentials from AWS Secrets Manager.

## Example

For use in a docker-compose file:

```yaml
version: '3'
services:
  pgbouncer:
    build:
      context: .
      dockerfile: Dockerfile
    ports:
      - 5432:5432
    environment:
      - AWS_REGION=eu-west-3
      - AWS_SECRET_NAME=rds!db-fcbuuuac4-a766-4033-9e24-436c6ea0ba46
      - AWS_PROFILE=myprofile
      - DB_HOST=mydb.xxxxxxxxxxxx.eu-west-3.rds.amazonaws.com
      - DB_PORT=5432
      - DB_NAME=postgres
      - SECRET_CHECK_INTERVAL=3600 # Optional, default is 3600 (⚠️ Doing too many requests to AWS can lead to rate limiting and increased costs)
    volumes:
      - ${HOME}/.aws:/home/pgbouncer/.aws
```

You have to customize:
- `AWS_REGION`: The region where the secret is stored
- `AWS_SECRET_NAME`: The name of the secret in AWS Secrets Manager
- `AWS_PROFILE`: The profile to use to access AWS (if you are using a mounted profile)
