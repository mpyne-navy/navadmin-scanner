FROM perl:slim
RUN apt-get update && apt-get upgrade -y && apt-get install -y tini git && \
    cd /opt && git clone https://github.com/mpyne-navy/navadmin-scanner && \
    apt-get remove -y --purge git && apt-get clean -y                   && \
    apt-get autoremove -y
WORKDIR /opt/navadmin-scanner
RUN cpanm --installdeps -n .
EXPOSE 3000
ENTRYPOINT ["/usr/bin/tini", "--"]
CMD ./navadmin-viewer.pl prefork -m production
