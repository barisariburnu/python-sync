FROM ubuntu:22.04

# Prevent interactive prompts
ENV DEBIAN_FRONTEND=noninteractive

# Set environment variables
ENV PGCLIENTENCODING=UTF8 \
    NLS_LANG=AMERICAN_AMERICA.UTF8 \
    TZ=Europe/Istanbul \
    PYTHONUNBUFFERED=1

# Install base dependencies
RUN apt-get update && apt-get install -y \
    postgresql-client \
    python3 \
    python3-pip \
    python3-dev \
    python3-venv \
    libpq-dev \
    wget \
    unzip \
    libaio1 \
    curl \
    cron \
    vim \
    alien \
    build-essential \
    software-properties-common \
    cmake \
    libsqlite3-dev \
    libproj-dev \
    libcurl4-gnutls-dev \
    libexpat1-dev \
    libxerces-c-dev \
    libgeos-dev \
    libtiff5-dev \
    libgeotiff-dev \
    libpng-dev \
    libjpeg-dev \
    libgif-dev \
    libwebp-dev \
    libhdf4-alt-dev \
    libhdf5-dev \
    libnetcdf-dev \
    libarmadillo-dev \
    libxml2-dev \
    libkml-dev \
    libspatialite-dev \
    libfreexl-dev \
    unixodbc-dev \
    libcfitsio-dev \
    libzstd-dev \
    libblosc-dev \
    liblcms2-dev \
    libpcre3-dev \
    libcrypto++-dev \
    libssl-dev \
    && rm -rf /var/lib/apt/lists/*

# Oracle Instant Client kurulumu - GDAL'dan ÖNCE
COPY oracle-client/instantclient-basic-linux.x64-21.16.0.0.0dbru.zip /tmp/
COPY oracle-client/instantclient-sqlplus-linux.x64-21.16.0.0.0dbru.zip /tmp/
COPY oracle-client/instantclient-sdk-linux.x64-21.16.0.0.0dbru.zip /tmp/

RUN mkdir -p /usr/lib/oracle \
    && cd /tmp \
    && unzip -o instantclient-basic-linux.x64-21.16.0.0.0dbru.zip \
    && unzip -o instantclient-sqlplus-linux.x64-21.16.0.0.0dbru.zip \
    && unzip -o instantclient-sdk-linux.x64-21.16.0.0.0dbru.zip \
    && cp -r instantclient_21_16 /usr/lib/oracle/instantclient \
    && rm -rf instantclient_21_16 \
    && rm instantclient-*.zip \
    && cd /usr/lib/oracle/instantclient \
    && rm -f libclntsh.so libocci.so \
    && ln -s libclntsh.so.21.1 libclntsh.so \
    && ln -s libocci.so.21.1 libocci.so \
    && echo "/usr/lib/oracle/instantclient" > /etc/ld.so.conf.d/oracle-instantclient.conf \
    && ldconfig

# Oracle environment variables - GDAL build öncesi ayarlanmalı
ENV ORACLE_HOME=/usr/lib/oracle/instantclient \
    LD_LIBRARY_PATH=/usr/lib/oracle/instantclient:$LD_LIBRARY_PATH \
    TNS_ADMIN=/usr/lib/oracle/instantclient \
    PATH=$PATH:/usr/lib/oracle/instantclient \
    OCI_HOME=/usr/lib/oracle/instantclient \
    OCI_LIB_DIR=/usr/lib/oracle/instantclient \
    OCI_INCLUDE_DIR=/usr/lib/oracle/instantclient/sdk/include

# GDAL'ı Oracle desteğiyle kaynak koddan derle
RUN cd /tmp \
    && wget https://github.com/OSGeo/gdal/releases/download/v3.8.0/gdal-3.8.0.tar.gz \
    && tar -xzf gdal-3.8.0.tar.gz \
    && cd gdal-3.8.0 \
    && mkdir build && cd build \
    && cmake .. \
        -DCMAKE_INSTALL_PREFIX=/usr \
        -DCMAKE_BUILD_TYPE=Release \
        -DGDAL_USE_ORACLE=ON \
        -DOracle_ROOT=/usr/lib/oracle/instantclient \
        -DOracle_INCLUDE_DIR=/usr/lib/oracle/instantclient/sdk/include \
        -DOracle_LIBRARY=/usr/lib/oracle/instantclient/libclntsh.so \
        -DGDAL_USE_POSTGRESQL=ON \
        -DGDAL_USE_GEOS=ON \
        -DGDAL_USE_GEOTIFF=ON \
        -DGDAL_USE_CURL=ON \
        -DGDAL_USE_SQLITE3=ON \
        -DGDAL_USE_PROJ=ON \
    && make -j$(nproc) \
    && make install \
    && ldconfig \
    && cd /tmp && rm -rf gdal-3.8.0*

# Python için sembolik link
RUN ln -s /usr/bin/python3 /usr/bin/python

# Environment variables for GDAL
ENV GDAL_DATA=/usr/share/gdal \
    GDAL_DRIVER_PATH=/usr/lib/gdalplugins

# Çalışma dizinini ayarla
WORKDIR /app

# Scripts kopyala
COPY scripts/su_tuketim_bilgileri_sync.sh /app/scripts/su_tuketim_bilgileri_sync.sh
COPY scripts/abone_adres_bilgileri_sync.sh /app/scripts/abone_adres_bilgileri_sync.sh
RUN chmod +x /app/scripts/su_tuketim_bilgileri_sync.sh
RUN chmod +x /app/scripts/abone_adres_bilgileri_sync.sh

# Entrypoint script'ini kopyala ve çalıştırılabilir yap
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Cron job'ları ayarla
RUN echo "30 3 * * * root cd /app && /app/scripts/sync.sh >> /app/logs/cron.log 2>&1" >> /etc/cron.d/su_tuketim_bilgileri_sync && \
    echo "30 4 * * * root cd /app && /app/scripts/sync.sh >> /app/logs/cron.log 2>&1" >> /etc/cron.d/abone_adres_bilgileri_sync && \
    echo "" >> /etc/cron.d/su_tuketim_bilgileri_sync && \
    echo "" >> /etc/cron.d/abone_adres_bilgileri_sync && \
    chmod 0644 /etc/cron.d/su_tuketim_bilgileri_sync && \
    chmod 0644 /etc/cron.d/abone_adres_bilgileri_sync

# Log dizinini oluştur
RUN mkdir -p /app/logs

# Environment değişkenlerini cron için hazırla
RUN printenv | grep -v "no_proxy" >> /etc/environment

# Uygulama dosyalarını kopyala
COPY . /app/

# OCI driver'ı test et
RUN ogrinfo --formats | grep -i oci || echo "Warning: OCI driver not found"

# Entrypoint ile başlat
ENTRYPOINT ["/entrypoint.sh"]