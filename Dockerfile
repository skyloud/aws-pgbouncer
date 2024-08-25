FROM docker.io/library/ubuntu:22.04

# Install pgbouncer, bash, and jq
RUN apt-get update && apt-get install -y pgbouncer bash jq

# Install the AWS CLI
RUN apt-get install -y python3-pip && pip3 install awscli

# Copy the script to the container
COPY aws-pgbouncer.sh /usr/local/bin/aws-pgbouncer.sh

# Make the script executable
RUN chmod +x /usr/local/bin/aws-pgbouncer.sh

# Add user and group for pgbouncer to run as with a home directory
RUN groupadd -r pgbouncer && useradd -r -g pgbouncer -d /home/pgbouncer pgbouncer \
    && mkdir -p /etc/pgbouncer /var/log/pgbouncer /var/run/pgbouncer \
    && chown -R pgbouncer:pgbouncer /etc/pgbouncer /var/log/pgbouncer /var/run/pgbouncer
USER pgbouncer
STOPSIGNAL SIGINT
# Set the script as the entrypoint
ENTRYPOINT ["/bin/bash", "/usr/local/bin/aws-pgbouncer.sh"]