ARG BASE_IMAGE=batsman-base-debian12
FROM ${BASE_IMAGE}
COPY lib/ /opt/batsman/lib/
COPY scripts/ /opt/batsman/scripts/
COPY dockerfiles/ /opt/batsman/dockerfiles/
COPY tests/ /opt/tests/
WORKDIR /opt/tests
CMD ["bats", "--formatter", "tap", "/opt/tests/"]
