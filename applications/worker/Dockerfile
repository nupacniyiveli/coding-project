FROM php:7.2.11-cli

ADD . /opt/personio-worker
WORKDIR /opt/personio-worker

CMD [ "php", "./src/listener.php" ]
