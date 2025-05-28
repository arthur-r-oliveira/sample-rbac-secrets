FROM registry.access.redhat.com/ubi9/ubi-minimal:latest

LABEL maintainer="Arthur Oliveira arolivei@redhat.com>"

# Install jq only. curl-minimal is likely already present and sufficient.
# We also use 'microdnf update -y' to ensure package lists are fresh before installing.
RUN microdnf update -y && \
    microdnf install -y jq && \
    microdnf clean all && \
    rm -rf /var/cache/microdnf/*

CMD ["/bin/bash"]
