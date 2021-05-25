FROM php:7.4-apache
LABEL maintainer="Andy Miller <rhuk@getgrav.org> (@rhukster)"

# Enable Apache Rewrite + Expires Module
RUN a2enmod rewrite expires && \
    sed -i 's/ServerTokens OS/ServerTokens ProductOnly/g' \
    /etc/apache2/conf-available/security.conf

# Needed only if exiting https but is better to do with a docker-compose and the traefic proxy in front
## (MD) Enable only secure ciphers:
#RUN sed -i 's|SSLCipherSuite HIGH:!aNULL|SSLCipherSuite HIGH:!aNULL:!eNULL:!EXPORT:!3DES:!DES:!MD5:!PSK:!RC4|' /etc/apache2/mods-available/ssl.conf
#RUN sed -i 's|#SSLHonorCipherOrder on|SSLHonorCipherOrder on|' /etc/apache2/mods-available/ssl.conf
#RUN sed -i 's|SSLProtocol all -SSLv3|SSLProtocol all -SSLv3 -TLSv1 -TLSv1.1\n\tSSLCompression off\n\tSSLSessionTickets off|' /etc/apache2/mods-available/ssl.conf
#RUN a2enmod ssl

RUN apt-get update && apt-get install -y --no-install-recommends \
    unzip \
    libfreetype6-dev \
    libjpeg62-turbo-dev \
    libpng-dev \
    libyaml-dev \
    libzip4 \
    libzip-dev \
    zlib1g-dev \
    libicu-dev \
    g++ \
    git \
    cron \
    vim \
    && docker-php-ext-install opcache \
    && docker-php-ext-configure intl \
    && docker-php-ext-install intl \
    && docker-php-ext-configure gd --with-freetype --with-jpeg \
    && docker-php-ext-install -j$(nproc) gd \
    && docker-php-ext-install zip \
    && rm -rf /var/lib/apt/lists/*

# install mod_auth_openidc packages
RUN apt-get update && apt-get install -y --no-install-recommends \
    wget \
    libhiredis0.14 \
    && wget https://github.com/zmartzone/mod_auth_openidc/releases/download/v2.4.0/libcjose0_0.6.1.5-1.buster+1_amd64.deb \
    && dpkg -i libcjose0_0.6.1.5-1.buster+1_amd64.deb \
    && rm -fv libcjose0_0.6.1.5-1.buster+1_amd64.deb \
    && wget https://github.com/zmartzone/mod_auth_openidc/releases/download/v2.4.8.2/libapache2-mod-auth-openidc_2.4.8.2-1.buster+1_amd64.deb \
    && dpkg -i libapache2-mod-auth-openidc_2.4.8.2-1.buster+1_amd64.deb \
    && rm -fv libapache2-mod-auth-openidc_2.4.8.2-1.buster+1_amd64.deb \
    && rm -rf /var/lib/apt/lists/*

# set recommended PHP.ini settings
# see https://secure.php.net/manual/en/opcache.installation.php
RUN { \
    echo 'opcache.memory_consumption=128'; \
    echo 'opcache.interned_strings_buffer=8'; \
    echo 'opcache.max_accelerated_files=4000'; \
    echo 'opcache.revalidate_freq=2'; \
    echo 'opcache.fast_shutdown=1'; \
    echo 'opcache.enable_cli=1'; \
    echo 'upload_max_filesize=128M'; \
    echo 'post_max_size=128M'; \
    echo 'expose_php=off'; \
    } > /usr/local/etc/php/conf.d/php-recommended.ini

RUN pecl install apcu \
    && pecl install yaml-2.0.4 \
    && docker-php-ext-enable apcu yaml

# Set user to www-data
RUN chown www-data:www-data /var/www
USER www-data

# Define Grav specific version of Grav or use latest stable
ARG GRAV_VERSION=latest

# Install grav
WORKDIR /var/www
RUN git clone https://github.com/bozzochet/herd-grav.git && \
    mv -Tf /var/www/herd-grav /var/www/html && \
    cd html && \
    ./install.sh

# Create cron job for Grav maintenance scripts
RUN (crontab -l; echo "* * * * * cd /var/www/html;/usr/local/bin/php bin/grav scheduler 1>> /dev/null 2>&1") | crontab -

# Create cron job to update the Grav plugins
# (every night at 02:15, to add,
# and at 02:45, to remove [if one package is kept in both places is however removed for safety, for example the Admin one])
RUN (crontab -l; echo "15 2 * * * cd /var/www/html;./install_plugins.sh 1>> /dev/null 2>&1") | crontab -
RUN (crontab -l; echo "45 2 * * * cd /var/www/html;./remove_plugins.sh 1>> /dev/null 2>&1") | crontab -
RUN (crobtab -l; echo "15 3 * * * cd /var/www/html/herd;./clone_wiki_and_link.sh 1>> /dev/null 2>&1") | crontab -

# Create cron job to update Grav github repo (i.e. web site content) every hour.
# In case the list of plugins is changed (install_plugins.sh and remove_plugins.sh)
# it will be updated at 02:15 & 02:45 (starting 15 minutes after the last execution of this cron)
RUN (crontab -l; echo "0 * * * * cd /var/www/html;git pull 1>> /dev/null 2>&1") | crontab -

# Return to root user
USER root

# Copy init scripts
# COPY docker-entrypoint.sh /entrypoint.sh

# provide container inside image for data persistence
VOLUME ["/var/www/html"]

# (MD) add conf for OpenIDC
ADD openidc.conf /etc/apache2/conf-available
RUN a2enconf openidc

# ENTRYPOINT ["/entrypoint.sh"]
# CMD ["apache2-foreground"]
CMD ["sh", "-c", "cron && apache2-foreground"]
