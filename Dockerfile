FROM docker.io/library/ubuntu:24.04

# Install pgbouncer, bash, and jq
RUN apt-get update && apt-get install -y pgbouncer bash jq pipx curl unzip && apt-get clean

# Install the AWS CLI depending on ARCH
RUN ARCH=$(uname -m | sed 's/x86_64/x86_64/;s/aarch64/aarch64/') \
    && curl "https://awscli.amazonaws.com/awscli-exe-linux-${ARCH}.zip" -o "awscliv2.zip" \
    && unzip awscliv2.zip \
    && ./aws/install \
    && rm -rf aws awscliv2.zip

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