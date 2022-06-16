# You can pick any Debian/Ubuntu-based image. 😊
FROM mcr.microsoft.com/vscode/devcontainers/base:bullseye

COPY library-scripts/*.sh library-scripts/aws-cli-pub.asc /tmp/library-scripts/

# [Option] Install zsh
ARG INSTALL_ZSH="true"
# [Option] Upgrade OS packages to their latest versions
ARG UPGRADE_PACKAGES="false"

# Install needed packages and setup non-root user. Use a separate RUN statement to add your own dependencies.
ARG USERNAME=vscode
ARG USER_UID=1000
ARG USER_GID=$USER_UID
RUN apt-get update && export DEBIAN_FRONTEND=noninteractive \
    && bash /tmp/library-scripts/common-debian.sh "${INSTALL_ZSH}" "${USERNAME}" "${USER_UID}" "${USER_GID}" "${UPGRADE_PACKAGES}" "true" "true" \ 
    && apt-get install -y graphviz \
    && apt-get clean -y && rm -rf /var/lib/apt/lists/*

# [Option] Install Azure CLI
ARG INSTALL_AZURE_CLI="true"
# [Option] Install AWS CLI
ARG INSTALL_AWS_CLI="true"
# [Option] Install Docker CLI
ARG INSTALL_DOCKER="true"
# [Choice] Node.js version: none, lts/*, 16, 14, 12, 10
ARG NODE_VERSION="none"
ENV NVM_DIR=/usr/local/share/nvm
ENV NVM_SYMLINK_CURRENT=true \
    PATH=${NVM_DIR}/current/bin:${PATH}
RUN if [ "${INSTALL_AZURE_CLI}" = "true" ]; then bash /tmp/library-scripts/azcli-debian.sh; fi \
    && if [ "${INSTALL_AWS_CLI}" ]; then bash /tmp/library-scripts/awscli-debian.sh; fi \
    && if [ "${NODE_VERSION}" != "none" ]; then bash /tmp/library-scripts/node-debian.sh "${NVM_DIR}" "${NODE_VERSION}" "${USERNAME}"; fi \
    && if [ "${INSTALL_DOCKER}" = "true" ]; then \
        bash /tmp/library-scripts/docker-debian.sh "true" "/var/run/docker-host.sock" "/var/run/docker.sock" "${USERNAME}"; \
    else \
        echo '#!/bin/bash\n"$@"' > /usr/local/share/docker-init.sh && chmod +x /usr/local/share/docker-init.sh; \
    fi \
    && rm -rf /var/lib/apt/lists/*

# Install Terraform, tflint, Terragrunt
ARG TERRAFORM_VERSION=0.12.16
ARG TFLINT_VERSION=0.8.2
ARG TERRAGRUNT_VERSION=0.28.1
RUN bash /tmp/library-scripts/terraform-debian.sh "${TERRAFORM_VERSION}" "${TFLINT_VERSION}" "${TERRAGRUNT_VERSION}" \
    && rm -rf /tmp/library-scripts

#RUN curl https://bootstrap.pypa.io/get-pip.py -O \
#    && python3 get-pip.py \
#    && rm get-pip.py
RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y python3-pip \
    && apt-get clean -y && rm -rf /var/lib/apt/lists/*

# Add terraformer
RUN export PROVIDER=all; \
    curl -fLO https://github.com/GoogleCloudPlatform/terraformer/releases/download/$(curl -s https://api.github.com/repos/GoogleCloudPlatform/terraformer/releases/latest | grep tag_name | cut -d '"' -f 4)/terraformer-${PROVIDER}-linux-amd64 \
    && chmod +x terraformer-${PROVIDER}-linux-amd64 \
    && mv terraformer-${PROVIDER}-linux-amd64 /usr/local/bin/terraformer

# Add inframap for visualization
RUN curl -fLO https://github.com/cycloidio/inframap/releases/download/$(curl -s https://api.github.com/repos/cycloidio/inframap/releases/latest | grep tag_name | cut -d '"' -f 4)/inframap-linux-amd64.tar.gz \
    && tar -xvzf inframap-linux-amd64.tar.gz \
    && rm inframap-linux-amd64.tar.gz \
    && mv inframap-linux-amd64 /usr/local/bin/inframap

ENTRYPOINT [ "/usr/local/share/docker-init.sh" ]
CMD [ "sleep", "infinity" ]

# [Optional] Uncomment this section to install additional OS packages.
# RUN apt-get update && export DEBIAN_FRONTEND=noninteractive \
#     && apt-get -y install --no-install-recommends <your-package-list-here>
