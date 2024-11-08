FROM golang:1.22.8-alpine3.20 AS builder

RUN apk add --no-cache \
	ca-certificates \
	git \
	libcap

ENV XCADDY_VERSION v0.4.4
# Configures xcaddy to build with this version of Caddy
ENV CADDY_VERSION v2.8.4
# Configures xcaddy to not clean up post-build (unnecessary in a container)
ENV XCADDY_SKIP_CLEANUP 1
# Sets capabilities for output caddy binary to be able to bind to privileged ports
ENV XCADDY_SETCAP 0

RUN set -eux; \
	apkArch="$(apk --print-arch)"; \
	case "$apkArch" in \
		x86_64)  binArch='amd64'; checksum='09b0bd09c879c2985c562deec675da074f896c9e114717d07f11bdb2714b7e9ecbb26748431732469c245e1517cde6e78ee6b0f6e839de3992d22a3d474188fe' ;; \
		armhf)   binArch='armv6'; checksum='dd1ee3d27bb9f0c2b6b900e19e779398c972fc7a0affaf19ee64fb01689cdd18e2df1429251607dbdeca1ad57d1851317c9f0c0c4c4ead3aa2b9e68678a62d52' ;; \
		armv7)   binArch='armv7'; checksum='e13003e727c228e84b1abb72db3f92362dd232087256ea51249002d4d0a17d002760123a33dafb8d47553d54c7d821f3d3dee419347a61f967ea4617abaef46a' ;; \
		aarch64) binArch='arm64'; checksum='c04464f944ebad714ded44691d359cf27109f5e088f7ee7ed5b49941c88382b0d31c91b81cb1c11444371abe7c491df06aba7306503a17627a7826ac8992e02a' ;; \
		ppc64el|ppc64le) binArch='ppc64le'; checksum='c05c883e3a6162b77454ed4efa1e28278d0624a53bb096dced95e27b61f60fdcc0a40e90524806fa07e2da654c6420995fede7077c2c2319351f8f0bc1855cd9' ;; \
		riscv64) binArch='riscv64'; checksum='84d1e61330aed77373ffa91dcfda5e20757372fb6ec204e33916a78d864aeb5e0560b2a8aad3166a91311110cb41fce4684a5731cf0d738780f11ee7838811de' ;; \
		s390x)   binArch='s390x'; checksum='93ff65601c255e9a2910b8ccfd3bcd4765ea6e5261fab31918e8bef0ffa37bcfaf45e2311fd43f9d9a13751102c3644d107d463fdb64d05c2af02307b96e9772' ;; \
		*) echo >&2 "error: unsupported architecture ($apkArch)"; exit 1 ;;\
	esac; \
	wget -O /tmp/xcaddy.tar.gz "https://github.com/caddyserver/xcaddy/releases/download/v0.4.4/xcaddy_0.4.4_linux_${binArch}.tar.gz"; \
	echo "$checksum  /tmp/xcaddy.tar.gz" | sha512sum -c; \
	tar x -z -f /tmp/xcaddy.tar.gz -C /usr/bin xcaddy; \
	rm -f /tmp/xcaddy.tar.gz; \
	chmod +x /usr/bin/xcaddy;

WORKDIR /usr/bin

RUN xcaddy build --with github.com/corazawaf/coraza-caddy/v2

FROM alpine:3.20 AS final

ARG DATA_FOLDER="/data"
ARG CADDY_UID=1654
ARG CADDY_GID=1654
ARG CADDY_USER=caddy
ARG CADDY_GROUP=caddy

ENV XDG_DATA_HOME="$DATA_FOLDER"

RUN rm -rf /usr/share/caddy/ \
    && apk --update-cache upgrade \ 
    && mkdir -p "${DATA_FOLDER}/caddy" \
    && addgroup \
        --system \
        --gid="$CADDY_GID" \
        "$CADDY_GROUP" \
    && adduser \
        -u "$CADDY_UID" \
        -G "$CADDY_GROUP" \
        -s /bin/false \
        -H \
        -S \
        "$CADDY_USER" \
    && chown -R "$CADDY_UID":"$CADDY_GID" \
        "$DATA_FOLDER" \
	&& find /usr/sbin /usr/bin /sbin /bin -delete -executable -not -iname '*.so*' -a -not -type d
 
COPY --from=builder /usr/bin/caddy /usr/bin/caddy
COPY Caddyfile /etc/caddy/Caddyfile
COPY coraza-config /opt/coraza/config

USER "${CADDY_USER}:${CADDY_GROUP}"

ENTRYPOINT [ "/usr/bin/caddy" ] 
CMD [ "run", "--config", "/etc/caddy/Caddyfile", "--adapter", "caddyfile"]