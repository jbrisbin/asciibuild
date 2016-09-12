# tag::alpine[]
ENV \
  OS_FAMILY=alpine \
  OS_VERSION=3.4 \
  OS_FLAVOR=x86_64
# end::alpine[]

# Install build-essential
# tag::alpine[]
RUN apk add --no-cache build-base openssh-client openssl openssl-dev git curl wget python-dev libffi-dev py-pip cyrus-sasl cyrus-sasl-dev ca-certificates ruby-rake ruby-dev ruby-rdoc jq which tar bash
RUN curl -sSL -o /etc/apk/keys/sgerrand.rsa.pub https://raw.githubusercontent.com/sgerrand/alpine-pkg-glibc/master/sgerrand.rsa.pub
RUN curl -sSL -O https://github.com/sgerrand/alpine-pkg-glibc/releases/download/2.23-r3/glibc-2.23-r3.apk
RUN apk add glibc-2.23-r3.apk
# end::alpine[]
# tag::ubuntu[]
RUN apt-get update
RUN apt-get install -qy openssl libssl-dev tar git wget curl vim build-essential autoconf automake libtool python-dev python-pip libsasl2-dev libsasl2-modules libapr1-dev libffi-dev apt-transport-https ca-certificates iputils-ping realpath rake ruby-dev jq
# end::ubuntu[]

# Install Docker
# tag::alpine[]
RUN apk add --no-cache docker
# end::alpine[]
# tag::ubuntu[]
RUN curl -fsSL https://get.docker.com/ | sh
# end::ubuntu[]

# tag::common[]
RUN curl -L -o /usr/local/bin/docker-compose https://github.com/docker/compose/releases/download/1.8.0-rc1/docker-compose-Linux-x86_64
RUN chmod a+x /usr/local/bin/docker-compose
# end::common[]
