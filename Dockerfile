ARG git_tag="master"

FROM mattermost/mattermost-build-webapp as webapp-builder

RUN cd /tmp && git clone --depth 1 https://github.com/Miouyouyou/mattermost-webapp -b $git_tag
RUN cd /tmp/mattermost-webapp && \
	npm ci &&\
	cd node_modules/mattermost-redux && npm i && npm run build

RUN cd /tmp/mattermost-webapp && npm run check

RUN cd /tmp/mattermost-webapp && npm run check-types

RUN cd /tmp/mattermost-webapp && make package-ci

FROM mattermost/mattermost-build-server as server-builder

COPY --from=webapp-builder /tmp/mattermost-webapp /tmp/mattermost-webapp

RUN cd /tmp && git clone --depth 1 https://github.com/Miouyouyou/mattermost-server -b $git_tag
RUN cd /tmp/mattermost-server && make app-layers
RUN cd /tmp/mattermost-server && make store-layers
RUN cd /tmp/mattermost-server && make config-reset
RUN cd /tmp/mattermost-server && make build
RUN cd /tmp/mattermost-server && make package
RUN cd /tmp/mattermost-server && cp dist/mattermost-team-linux-amd64.tar.gz /tmp

FROM alpine:3.10

# Some ENV variables
ENV PATH="/mattermost/bin:${PATH}"
ENV PGID=2000
ENV PUID=2000

# Install some needed packages
# Myy : netcat !!?
RUN apk add --no-cache \
	ca-certificates \
	curl \
	jq \
	libc6-compat \
	libffi-dev \
    libcap \
	linux-headers \
	mailcap \
	netcat-openbsd \
	xmlsec-dev \
	tzdata \
	&& rm -rf /tmp/*

COPY --from=server-builder /tmp/mattermost-team-linux-amd64.tar.gz /mattermost-team-linux-amd64.tar.gz

# Get Mattermost
RUN mkdir -p /mattermost/data /mattermost/plugins /mattermost/client/plugins
RUN cd / && tar xvf mattermost-team-linux-amd64.tar.gz
RUN cp /mattermost/config/config.json /config.json.save
RUN rm -rf /mattermost/config/config.json
RUN addgroup -g ${PGID} mattermost
RUN adduser -D -u ${PUID} -G mattermost -h /mattermost -D mattermost
RUN chown -R mattermost:mattermost /mattermost /config.json.save /mattermost/plugins /mattermost/client/plugins
RUN setcap cap_net_bind_service=+ep /mattermost/bin/mattermost

USER mattermost

#Healthcheck to make sure container is ready
HEALTHCHECK --interval=5m --timeout=3s \
  CMD curl -f http://localhost:8065/api/v4/system/ping || exit 1


# Configure entrypoint and command
COPY entrypoint.sh /
ENTRYPOINT ["/entrypoint.sh"]
WORKDIR /mattermost
CMD ["mattermost"]

EXPOSE 8065 8067 8074 8075

# Declare volumes for mount point directories
VOLUME ["/mattermost/data", "/mattermost/logs", "/mattermost/config", "/mattermost/plugins", "/mattermost/client/plugins"]
