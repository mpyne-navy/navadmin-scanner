FROM alpine:latest

# Need Perl, Mojolicious, a decent event loop (Alpine supports AnyEvent but not
# libev and Perl::EV, so I use Perl::Event as the implementation). Also need
# IO::Socket::SSL. Fly.io provides the init so we don't need tini.

RUN apk add --no-cache                    \
    perl                                  \
    perl-anyevent                         \
    perl-event                            \
    perl-io-socket-ssl                    \
    perl-mojolicious                      \
    zlib # Only here to terminate the list with a small package :)

WORKDIR /opt/navadmin-scanner

# Bare essentials to build and/or run the web app
COPY navadmin-viewer.pl      \
     check-file-miscoded.pl  \
     clean-rmks.pl           \
     navadmin_meta.json      \
     gen-miscoded-files-list \
     fix-miscoded-files      \
         /opt/navadmin-scanner/
COPY NAVADMIN                /opt/navadmin-scanner/NAVADMIN/
COPY assets                  /opt/navadmin-scanner/assets/

RUN ./gen-miscoded-files-list | ./fix-miscoded-files && rm *miscoded* && ./clean-rmks.pl && ./build-reference-list.pl >cross-refs.json 2>/dev/null

EXPOSE 3000

CMD ./navadmin-viewer.pl prefork -m production
