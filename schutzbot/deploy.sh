#!/bin/bash
set -euxo pipefail

DNF_REPO_BASEURL=http://osbuild-composer-repos.s3-website.us-east-2.amazonaws.com

# The osbuild-composer commit to run reverse-dependency test against.
OSBUILD_COMPOSER_COMMIT=692a8076bb4bf38dae05ce99631ebcdd3f0ab054

# Get OS details.
source /etc/os-release
ARCH=$(uname -m)

# Register RHEL if we are provided with a registration script.
if [[ -n "${RHN_REGISTRATION_SCRIPT:-}" ]] && ! sudo subscription-manager status; then
    sudo chmod +x $RHN_REGISTRATION_SCRIPT
    sudo $RHN_REGISTRATION_SCRIPT
fi

# Add osbuild team ssh keys.
cat schutzbot/team_ssh_keys.txt | tee -a ~/.ssh/authorized_keys > /dev/null

# Set up dnf repositories with the RPMs we want to test
sudo tee /etc/yum.repos.d/osbuild.repo << EOF
[osbuild]
name=osbuild ${GIT_COMMIT}
baseurl=${DNF_REPO_BASEURL}/osbuild/${ID}-${VERSION_ID}/${ARCH}/${GIT_COMMIT}
enabled=1
gpgcheck=0
# Default dnf repo priority is 99. Lower number means higher priority.
priority=5

[osbuild-composer]
name=osbuild-composer ${OSBUILD_COMPOSER_COMMIT}
baseurl=${DNF_REPO_BASEURL}/osbuild-composer/${ID}-${VERSION_ID}/${ARCH}/${OSBUILD_COMPOSER_COMMIT}
enabled=1
gpgcheck=0
# Give this a slightly lower priority, because we used to have osbuild in this repo as well.
priority=10
EOF

if [[ $ID == rhel ]]; then
    # Set up EPEL repository (for ansible and koji)
    sudo dnf install -y https://dl.fedoraproject.org/pub/epel/epel-release-latest-8.noarch.rpm
fi

# Install the Image Builder packages.
# Note: installing only -tests to catch missing dependencies
sudo dnf -y install osbuild-composer-tests

# Set up a directory to hold repository overrides.
sudo mkdir -p /etc/osbuild-composer/repositories

# NOTE(mhayden): RHEL 8.3 is the release we are currently targeting, but the
# release is in beta right now. For RHEL 8.2 (latest release), ensure that
# the production (non-beta content) is used.
if [[ "${ID}${VERSION_ID//./}" == rhel82 ]]; then
    sudo cp ${WORKSPACE}/test/external-repos/rhel-8.json \
        /etc/osbuild-composer/repositories/rhel-8.json
fi

# Start services.
sudo systemctl enable --now osbuild-composer.socket

# Verify that the API is running.
sudo composer-cli status show
sudo composer-cli sources list
