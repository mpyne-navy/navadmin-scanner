FROM perl:slim AS base

# Ensure the base image packages are updated
RUN apt-get update && apt-get upgrade -y       && \
    apt-get install -y tini libev4             && \
    apt-get clean -y && apt-get autoremove -y

WORKDIR /opt/navadmin-scanner

# Bare essentials to build and/or run the web app
COPY Makefile.PL navadmin-viewer.pl /opt/navadmin-scanner/
COPY NAVADMIN                       /opt/navadmin-scanner/NAVADMIN/
COPY assets                         /opt/navadmin-scanner/assets/

FROM base AS builder

# Install a compiler (needed for EV which builds C code as part of its install)
# and the development files for libev. These build products will be installed
# to /usr/local as part of the way the perl:slim image is configured. In fact
# Debian will install a second copy of perl but that will not be used by us.
RUN apt-get install -y libev-dev gcc && cpanm --installdeps -n .

FROM base AS webapp

# The web app is already present from "base", we just need to copy the Perl
# modules (including XS modules) we built earlier. Copying *all* of /usr/local
# is probably overkill but it's better than trying to pick Mojolicious and EV
# one by one throughout /usr/local/lib/perl5/{5.*, site_perl/5.*}/*
COPY --from=builder /usr/local /usr/local

EXPOSE 3000

# tini acts as the init to handle UNIX signal propagation and process
# management
ENTRYPOINT ["/usr/bin/tini", "--"]
CMD ./navadmin-viewer.pl prefork -m production
