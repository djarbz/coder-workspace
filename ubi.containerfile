ARG UBI_VERSION=9
FROM registry.access.redhat.com/ubi${UBI_VERSION}/ubi:latest

# Install container tools
RUN <<EORUN
dnf -y install git podman buildah skopeo
dnf clean all
rm -rf /var/cache /var/log /var/lib/dnf /var/lib/rhsm
EORUN
