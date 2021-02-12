# Se trabaja haciendo un merge a mano desde https://github.com/theia-ide/theia-apps/blob/master/theia-full-docker/Dockerfile
FROM ubuntu:18.04 as common

ENV DEBIAN_FRONTEND noninteractive

ARG NODE_VERSION=12.18.3
ENV NODE_VERSION $NODE_VERSION
ENV YARN_VERSION 1.22.5

# Common deps
RUN apt-get update && \
    apt-get -y install build-essential \
                       curl \
                       git \
                       gpg \
                       python \
                       wget \
                       xz-utils \
                       sudo \
    && \
    apt-get clean && \
    apt-get autoremove -y && \
    rm -rf /var/cache/apt/* && \
    rm -rf /var/lib/apt/lists/* && \
    rm -rf /tmp/*

## User account
RUN adduser --disabled-password --gecos '' theia && \
    adduser theia sudo && \
    echo '%sudo ALL=(ALL) NOPASSWD:ALL' >> /etc/sudoers

# Install node and yarn
# Ojo acá con las llaves, las cuales se deben obtener desde: https://github.com/nodejs/node#release-keys
RUN set -ex \
    && for key in \
	4ED778F539E3634C779C87C6D7062848A1AB005C \
	94AE36675C464D64BAFA68DD7434390BDBE9B9C5 \
	74F12602B6F1C4E913FAA37AD3A89613643B6201 \
	71DCFD284A79C3B38668286BC97EC7A07EDE3FC1 \
	8FCCA13FEF1D0C2E91008E09770F7A9A5AE15600 \
	C4F0DFFF4E8C1A8236409D08E73BC641CC11F4C8 \
	C82FA3AE1CBEDC6BE46B9360C43CEC45C17AB93C \
	DD8F2338BAE7501E3DD5AC78C273792F7D83545D \
	A48C2BEE680E841632CD4E44F07496B3EB3C1762 \
	108F52B48DB57BB0CC439B2997B01419BD92F80A \
	B9E2F5981AA6E0CD28160D9FF13993A75599653C \
    ; do \
    gpg --batch --keyserver ipv4.pool.sks-keyservers.net --recv-keys "$key" || \
    gpg --batch --keyserver pool.sks-keyservers.net --recv-keys "$key" || \
    gpg --batch --keyserver pgp.mit.edu --recv-keys "$key" || \
    gpg --batch --keyserver keyserver.pgp.com --recv-keys "$key" || \
    gpg --batch --keyserver ha.pool.sks-keyservers.net --recv-keys "$key" ; \
    done

RUN ARCH= && dpkgArch="$(dpkg --print-architecture)" \
    && case "${dpkgArch##*-}" in \
    amd64) ARCH='x64';; \
    ppc64el) ARCH='ppc64le';; \
    s390x) ARCH='s390x';; \
    arm64) ARCH='arm64';; \
    armhf) ARCH='armv7l';; \
    i386) ARCH='x86';; \
    *) echo "unsupported architecture"; exit 1 ;; \
    esac \
    && curl -SLO "https://nodejs.org/dist/v$NODE_VERSION/node-v$NODE_VERSION-linux-$ARCH.tar.xz" \
    && curl -SLO --compressed "https://nodejs.org/dist/v$NODE_VERSION/SHASUMS256.txt.asc" \
    && gpg --batch --decrypt --output SHASUMS256.txt SHASUMS256.txt.asc \
    && grep " node-v$NODE_VERSION-linux-$ARCH.tar.xz\$" SHASUMS256.txt | sha256sum -c - \
    && tar -xJf "node-v$NODE_VERSION-linux-$ARCH.tar.xz" -C /usr/local --strip-components=1 --no-same-owner \
    && rm "node-v$NODE_VERSION-linux-$ARCH.tar.xz" SHASUMS256.txt.asc SHASUMS256.txt \
    && ln -s /usr/local/bin/node /usr/local/bin/nodejs

RUN set -ex \
    && for key in \
    6A010C5166006599AA17F08146C2130DFD2497F5 \
    ; do \
    gpg --batch --keyserver ipv4.pool.sks-keyservers.net --recv-keys "$key" || \
    gpg --batch --keyserver pool.sks-keyservers.net --recv-keys "$key" || \
    gpg --batch --keyserver pgp.mit.edu --recv-keys "$key" || \
    gpg --batch --keyserver keyserver.pgp.com --recv-keys "$key" || \
    gpg --batch --keyserver ha.pool.sks-keyservers.net --recv-keys "$key" ; \
    done \
    && curl -fSLO --compressed "https://yarnpkg.com/downloads/$YARN_VERSION/yarn-v$YARN_VERSION.tar.gz" \
    && curl -fSLO --compressed "https://yarnpkg.com/downloads/$YARN_VERSION/yarn-v$YARN_VERSION.tar.gz.asc" \
    && gpg --batch --verify yarn-v$YARN_VERSION.tar.gz.asc yarn-v$YARN_VERSION.tar.gz \
    && mkdir -p /opt/yarn \
    && tar -xzf yarn-v$YARN_VERSION.tar.gz -C /opt/yarn --strip-components=1 \
    && ln -s /opt/yarn/bin/yarn /usr/local/bin/yarn \
    && ln -s /opt/yarn/bin/yarn /usr/local/bin/yarnpkg \
    && rm yarn-v$YARN_VERSION.tar.gz.asc yarn-v$YARN_VERSION.tar.gz

FROM common as theia

ARG GITHUB_TOKEN

# Use "latest" or "next" version for Theia packages
ARG version=latest

# Optionally build a striped Theia application with no map file or .ts sources.
# Makes image ~150MB smaller when enabled
ARG strip=false
ENV strip=$strip

USER theia
WORKDIR /home/theia
ADD $version.package.json ./package.json

RUN if [ "$strip" = "true" ]; then \
yarn --pure-lockfile && \
    NODE_OPTIONS="--max_old_space_size=2560" yarn theia build && \
    yarn theia download:plugins && \
    yarn --production && \
    yarn autoclean --init && \
    echo *.ts >> .yarnclean && \
    echo *.ts.map >> .yarnclean && \
    echo *.spec.* >> .yarnclean && \
    yarn autoclean --force && \
    yarn cache clean \
;else \
yarn --cache-folder ./ycache && rm -rf ./ycache && \
     NODE_OPTIONS="--max_old_space_size=2560" yarn theia build && yarn theia download:plugins \
;fi

FROM common

#Developer tools

USER root

## Git and sudo (sudo needed for user override)
RUN apt-get update && apt-get -y install git sudo

# Java
RUN apt-get update && apt-get -y install openjdk-11-jdk maven gradle

# Docker CLI y Docker Compose
RUN curl -fsSL https://download.docker.com/linux/ubuntu/gpg | apt-key add - \
    && apt-get update && apt-get --assume-yes install \
    apt-transport-https \
    ca-certificates \
    curl \
    gnupg-agent \
    software-properties-common \
    && add-apt-repository  "deb [arch=armhf] https://download.docker.com/linux/ubuntu \
    $(lsb_release -cs) stable"
    
#&& echo 'deb [arch=arm64] https://download.docker.com/linux/ubuntu bionic stable' | tee -a /etc/apt/sources.list

#python3-pip python3 && /usr/bin/python3 -m pip install -U docker-compose --user 
#curl -L https://github.com/linuxserver/docker-docker-compose/releases/download/1.28.2-ls30/docker-compose-arm64 | sudo tee /usr/local/bin/docker-compose >/dev/null
RUN apt-get update && apt-get --assume-yes install docker-ce-cli \
    && curl --silent "https://github.com/linuxserver/docker-docker-compose/releases/latest" | \
    grep 'tag/' | \
    sed -E 's/.*tag\/([^"]+)".*/\1/' | \
    xargs -I {} curl -sL "https://github.com/linuxserver/docker-docker-compose/releases/download/"{}'/docker-compose-arm64' \
    -o /usr/local/bin/docker-compose && chmod +x /usr/local/bin/docker-compose

# THEIA desde acá termina las herramientas de desarrollo
WORKDIR /home/theia

COPY --from=theia --chown=theia:theia /home/theia /home/theia

RUN chmod g+rw /home && \
    mkdir -p /home/project && \
    mkdir -p /home/theia/.pub-cache/bin && \
    mkdir -p /usr/local/cargo && \
    mkdir -p /usr/local/go && \
    mkdir -p /usr/local/go-packages && \
    chown -R theia:theia /home/project && \
    chown -R theia:theia /home/theia/.pub-cache/bin && \
    chown -R theia:theia /usr/local/cargo && \
    chown -R theia:theia /usr/local/go && \
    chown -R theia:theia /usr/local/go-packages

# Theia application
## Needed for node-gyp, nsfw build
RUN apt-get clean && \
  apt-get autoremove -y && \
  rm -rf /var/cache/apt/* && \
  rm -rf /var/lib/apt/lists/* && \
  rm -rf /tmp/*

# Change permissions to make the `yang-language-server` executable.
RUN chmod +x ./plugins/yangster/extension/server/bin/yang-language-server

USER theia
EXPOSE 3000
# Configure Theia
ENV SHELL=/bin/bash \
    THEIA_DEFAULT_PLUGINS=local-dir:/home/theia/plugins  \
    # Configure user Go path
    GOPATH=/home/project

ENV LC_ALL=C.UTF-8
ENV LANG=C.UTF-8

ENTRYPOINT [ "node", "/home/theia/src-gen/backend/main.js", "/home/project", "--hostname=0.0.0.0" ]
