# batsman — self-test Dockerfile
# Copyright (C) 2002-2026 R-fx Networks <proj@rfxn.com>
# GNU GPL v2 — see LICENSE
ARG BASE_IMAGE=batsman-base-debian12
FROM ${BASE_IMAGE}
RUN apt-get update && apt-get install -y --no-install-recommends python3 && rm -rf /var/lib/apt/lists/*
COPY lib/ /opt/batsman/lib/
COPY scripts/ /opt/batsman/scripts/
COPY dockerfiles/ /opt/batsman/dockerfiles/
COPY tests/ /opt/tests/
WORKDIR /opt/tests
CMD ["bats", "--formatter", "tap", "/opt/tests/"]
