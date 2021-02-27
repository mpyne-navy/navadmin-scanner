# Introduction

This is a script to spider the NAVADMIN messages from the
[MyNavy HR](https://www.mynavyhr.navy.mil/References/Messages/) (formerly Navy
Personnel Command) website to help identify and download NAVADMIN messages.

The idea will be to migrate from just downloading and syncing up messages to
one day mirroring them with better search, maybe better formatting, *maybe*
even auto-addition of appropriate hyperlinks. But for now only downloading
and re-displaying the NAVADMINs works.

# Setup

You need Perl 5 and the [Mojolicious](https://mojolicious.org/) web framework
installed to try this.  Pretty much every Unix-like OS has Perl easily
available, from there Mojolicious is self-contained and not too hard to
install, either by using its own installer or from CPAN (I recommend [CPAN
Minus](https://metacpan.org/pod/App::cpanminus)).

# Run

## Downloading NAVADMINs

After completing the setup above, you should be able to just run
`./download-updated-navadmins.pl` to update existing and download new
NAVADMINs.

The first time the script is ever run, it will download all NAVADMINs it can
find on the MyNavy HR website (though even in this case it will request the
server only respond if the NAVADMIN has somehow changed).

Subsequently (based on whether a `.has-run` file is present) it will only check
for NAVADMINs for the current year, and will use the timestamp of existing
NAVADMIN files to re-download from the server if the NAVADMIN is changed.

## Serving up NAVADMINs

You can run `./navadmin-viewer.pl daemon` to run a simple Web server (also
powered by Mojolicious) to list NAVADMINs and serve up individual NAVADMINs. It
is pretty bare at this point but wouldn't be too hard to pretty up.

Please don't actually run this on a production website if you aren't familiar
enough with Mojolicious to set it up, I haven't configured CSRF token support
or client secret configs or running with hypnotoad or any of that fun stuff.

The resulting web server will by default run at localhost port 3000, i.e.
[this link](http://localhost:3000/). You can also simply run the script
directly to show off which routes are configured (`./navadmin-viewer.pl
routes`) or test the response of a given GET request without a browser
(`./navadmin-viewer.pl get /by-year/2019`).

# Containerizing the application

This repository contains a Dockerfile you can use to turn the application into
a working container-based app.

## Build

To build, run

    docker build --target webapp -t navadmin-viewer:latest .

You can replace the `navadmin-viewer:latest` with an appropriate image name and
image version as you wish.

## Run

To run a new container with the image you just built, run

    docker run -P --rm -it navadmin-viewer:latest

The `-P` switch allows docker to expose port 3000 in the container (where the web app
will be expecting traffic) to a randomly-generated port that docker will choose. You
can run `docker ps` to find out what the external port will be, or there's probably a
better way to set the port by reading the [`docker-run`
documentation](https://docs.docker.com/engine/reference/run/#expose-incoming-ports).

`docker ps` will also tell you the name of the new container. Run `docker stop
$name` (where $name is the name as listed by `docker ps`) to stop the
application.

Once you have a working container then getting it published and available to
the wider world can be done using the vast array of platform services that are
now available, including AWS, Azure, Google, [Fly](https://fly.io/) and
probably a hundred others.
