FROM ubuntu:22.04

RUN apt update && apt install -y curl jq

COPY graylog-init.sh /init.sh
RUN chmod +x /init.sh

ENTRYPOINT ["/init.sh"]
