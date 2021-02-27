FROM perl:slim

# Ensure the base image packages are updated and install mandatory build-
# and run-time dependencies and the web application's source code
RUN apt-get update && apt-get upgrade -y                                && \
    apt-get install -y tini git libev4 libev-dev gcc                    && \
    cd /opt && git clone https://github.com/mpyne-navy/navadmin-scanner

WORKDIR /opt/navadmin-scanner

# Install the web app's Perl dependencies. To use EV we need libev-dev and gcc
# to be present when cpanm runs, then the build-time deps can be removed.
RUN cpanm --installdeps -n .                                            && \
    apt-get remove -y --purge git libev-dev gcc                         && \
    apt-get clean -y && apt-get autoremove -y

EXPOSE 3000

# tini acts as the init to handle UNIX signal propagation and process
# management
ENTRYPOINT ["/usr/bin/tini", "--"]
CMD ./navadmin-viewer.pl prefork -m production
