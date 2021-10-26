FROM php:7.2.11-apache
COPY --from=composer:1.7 /usr/bin/composer /usr/bin/composer

RUN apt-get update && apt-get install -y git

RUN rm -f /etc/apache2/sites-enabled/*
COPY build/apache2/vhost.conf /etc/apache2/sites-enabled/

ADD . /var/www/html/

RUN composer install

# Make Application version #id stored on the container
ARG APPLICATION_VERSION=not-defined
ENV APPLICATION_VERSION=${APPLICATION_VERSION}
