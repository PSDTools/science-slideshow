FROM debian:bullseye

RUN apt-get update && apt-get install -y \
    wget \
    unzip \
    kpartx \
    qemu-user-static \
    fdisk \
    dosfstools \
    sudo \
    curl

WORKDIR /build

COPY build-image.sh /build/build-image.sh
RUN chmod +x /build/build-image.sh

CMD ["/build/build-image.sh"]
