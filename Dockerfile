# Copyright (c) 2022, 2023 Oracle and/or its affiliates.
# Licensed under the Universal Permissive License v 1.0 as shown at https://oss.oracle.com/licenses/upl.
#
# hadolint global ignore=DL3013

FROM ghcr.io/oracle/oraclelinux8-python:3.9

ARG BUILDTIME
ARG VERSION
ARG REVISION

ENV IMAGE_BUILDTIME=${BUILDTIME} \
    IMAGE_VERSION=${VERSION} \
    IMAGE_REVISION=${REVISION}

RUN dnf -y install jq curl cronie && rm -rf /var/cache/dnf/* \
    && python3 -m pip install --no-cache-dir --upgrade pip \
    && python3 -m pip install --no-cache-dir oci-cli \
    && cp /usr/local/lib/python3.9/site-packages/oci_cli/bin/oci_autocomplete.sh /usr/local/bin/oci_autocomplete.sh \
    && chmod +x /usr/local/bin/oci_autocomplete.sh \
    && useradd -m -d /oracle oracle \
    && echo '[[ -e "/usr/local/bin/oci_autocomplete.sh" ]] && source "/usr/local/bin/oci_autocomplete.sh"' >> /oracle/.bashrc \
    && mkdir -p /oracle/.oci

# Copy OCI config files to the .oci directory
COPY --chown=oracle:oracle config /oracle/.oci/
COPY --chown=oracle:oracle oci_api_key.pem /oracle/.oci/
COPY --chown=oracle:oracle oci_api_key_public.pem /oracle/.oci/

# Update the key_file path in the config file
RUN sed -i 's|/home/arghya/.oci/oci_api_key.pem|/oracle/.oci/oci_api_key.pem|g' /oracle/.oci/config

# Copy the instance creation script
COPY --chown=oracle:oracle create_instance.sh /oracle/create_instance.sh
RUN chmod +x /oracle/create_instance.sh

# Create the required configuration files
WORKDIR /oracle
# Create required JSON configuration files and config directory
RUN mkdir -p /oracle/config /oracle/logs
COPY --chown=oracle:oracle availabilityConfig.json /oracle/config/availabilityConfig.json
COPY --chown=oracle:oracle instanceOptions.json /oracle/config/instanceOptions.json
COPY --chown=oracle:oracle shapeConfig.json /oracle/config/shapeConfig.json
COPY --chown=oracle:oracle ssh-key-2025-03-23.key.pub /oracle/config/ssh-key-2025-03-23.key.pub


# Create entrypoint script
COPY --chown=root:root entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Set up cron job to run create_instance.sh every 5 minutes
COPY --chown=root:root crontab.txt /etc/cron.d/instance-cron
RUN chmod 0644 /etc/cron.d/instance-cron \
    && crontab /etc/cron.d/instance-cron

ENTRYPOINT ["/entrypoint.sh"]
CMD ["run"]
