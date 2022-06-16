#!/usr/bin/env bash
#-------------------------------------------------------------------------------------------------------------
# Copyright (c) Xcape, Inc. All rights reserved.
# Licensed under the MIT License.
#-------------------------------------------------------------------------------------------------------------
#
# Docs:
# Maintainer:
#
# Syntax: ./awscli-debian.sh

set -e
trap 'catch $? $LINENO' ERR
catch() {
  echo "Error $1 occurred on $2" >&2
}
set -euo pipefail

SCRIPT_PATH=$0

if [[ "$OSTYPE" == "darwin"* ]]; then
  # MacOS equivalent of readlink -f

  cd $(dirname "${SCRIPT_PATH}")
  SCRIPT_BASE_NAME=$(basename "${SCRIPT_PATH}")

  # Iterate down a (possible) chain of symlinks
  CUR_TARGET=${SCRIPT_BASE_NAME}
  while [ -L "${SCRIPT_BASE_NAME}" ]
  do
      CUR_TARGET=$(readlink "${CUR_TARGET}")
      cd $(dirname "${CUR_TARGET}")
      CUR_TARGET=$(basename "${CUR_TARGET}")
  done

  # Compute the canonicalized name by finding the physical path 
  # for the directory we're in and appending the target file.
  SCRIPT_DIR=$(pwd -P)
  REAL_SCRIPT_PATH="${SCRIPT_DIR}/${CUR_TARGET}"
else
  REAL_SCRIPT_PATH=$(readlink -f "${SCRIPT_PATH}")
  SCRIPT_DIR=$(dirname "${REAL_SCRIPT_PATH}")
fi

cd "${SCRIPT_DIR}"

### Set vars ###
TARGET_OS=${TARGET_OS:-linux}
TARGET_ARCH=${TARGET_ARCH:-"$(dpkg --print-architecture)"}
TARGET_KERNEL_VERSION=${TARGET_KERNEL_VERSION:-$(uname -r)}
AWSCLI_VERSION=${1:-"latest"}
AWSCLI_GPG_KEY_FILENAME="aws-cli-pub.asc"
AWSCLI_ARCHIVE_ARCHITECTURES="amd64 aarch64"

if [ "$(id -u)" -ne 0 ]; then
    echo -e 'Script must be run as root. Use sudo, su, or add "USER root" to your Dockerfile before running this script.'
    exit 1
fi

# Function to run apt-get if needed
apt_get_update_if_needed()
{
    if [ ! -d "/var/lib/apt/lists" ] || [ "$(ls /var/lib/apt/lists/ | wc -l)" = "0" ]; then
        echo "Running apt-get update..."
        apt-get update
    else
        echo "Skipping apt-get update."
    fi
}

# Checks if packages are installed and installs them if not
check_packages() {
    if ! dpkg -s "$@" > /dev/null 2>&1; then
        apt_get_update_if_needed
        apt-get -y install --no-install-recommends "$@"
    fi
}

export DEBIAN_FRONTEND=noninteractive

install_using_zip() {
    echo "(*) Installing via zip."
    if ! dpkg -s less groff unzip curl > /dev/null 2>&1; then
        apt_get_update_if_needed
        apt-get -y install less groff unzip curl
    fi

    if [ "${AWSCLI_VERSION}" = "latest" ] || [ "${AWSCLI_VERSION}" = "lts" ] || [ "${AWSCLI_VERSION}" = "stable" ]; then
        # Empty, meaning grab the "latest" from the web
        ver=""
    else
        ver="-${AWSCLI_VERSION}"
    fi

    FILE_ARCH="${TARGET_ARCH}"
    if [ 'amd64' == "${FILE_ARCH}" ]; then
        FILE_ARCH='x86_64'
    fi

    gpg --import "${SCRIPT_DIR}/${AWSCLI_GPG_KEY_FILENAME}"

    curl "https://awscli.amazonaws.com/awscli-exe-linux-${FILE_ARCH}${ver}.zip.sig" -o "awscliv2.sig"
    curl "https://awscli.amazonaws.com/awscli-exe-linux-${FILE_ARCH}${ver}.zip" -o "awscliv2.zip"

    gpg --verify awscliv2.sig awscliv2.zip
    rm -rf aws
    unzip awscliv2.zip

    set +e
        ./aws/install
        ret_code="$?"
        rm -rf aws

        # Fail gracefully
        if [ "$ret_code" != 0 ]; then
            echo "Could not install aws-cli${ver} via zip"
            return 1
        fi

        aws --version
        # Fail gracefully
        if [ "$?" != 0 ]; then
            echo "Could not install aws-cli${ver} via zip"
            return 1
        fi
    set -e
}

# See if we're on x86_64 and if so, install via apt-get, otherwise use pip3
echo "(*) Installing AWS CLI..."
. /etc/os-release
if [[ "${AWSCLI_ARCHIVE_ARCHITECTURES}" != *"${TARGET_ARCH}"* ]]; then
    echo "No zip for architecture ${TARGET_ARCH}" && false
fi

# Presently no other option for install that zip
use_zip='true'
if [ "${use_zip}" = "true" ]; then
    install_using_zip

    if [ "$?" != 0 ]; then
        echo "Please provide a valid version for your distribution ${ID:-} ${VERSION_CODENAME:-} (${TARGET_ARCH})."
        false
    fi
fi

echo "Done!"