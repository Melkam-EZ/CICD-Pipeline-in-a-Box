# CI runner image = official Gitea act_runner + Docker CLI (copied from the
# official docker:cli image) + bash/git/curl for pipeline steps.
ARG RUNNER_BASE=gitea/act_runner:0.2.11
ARG DOCKER_CLI_IMAGE=docker:27-cli

FROM ${DOCKER_CLI_IMAGE} AS dockercli

FROM ${RUNNER_BASE}
COPY --from=dockercli /usr/local/bin/docker /usr/local/bin/docker
COPY --from=dockercli /usr/local/libexec/docker/cli-plugins/docker-buildx /usr/local/libexec/docker/cli-plugins/docker-buildx
RUN apk add --no-cache bash git curl
