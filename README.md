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

The web application will provide a hyperlink to the original (official) source
if the chosen hyperlink is provided in `navadmin_meta.json`.  The download
script does this by default but you have to remember to check the updated
meta.json back into the repository.

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

    docker build -t navadmin-viewer:latest .

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

# Auxiliary NAVADMIN admin

Some other scripts are popping up in this repo to help with cleaning up and
parsing the downloaded NAVADMIN messages.

## NAVADMIN Cleansing

These scripts are used when building the Docker container immediately prior to
deployment.  The changes they make are performed each deployment without
updating the file in the git repository and without making textual changes to
the NAVADMINs themselves.

* check-file-miscoded.pl -- reads in a list of files and then writes out a message if any character set issues are present.
* gen-miscoded-files-list -- A shell script using check-file-miscoded.pl against all downloaded NAVADMINs
* fix-miscoded-files -- A shell script reading in a list of files and a specific issue and then updating the file to correct the issue

This script makes minor edits to the NAVADMINs passed on the command line, or
to all NAVADMINs if no specific files are mentioned, trying to correct
obviously errorneous mistakes and simplify multiple possible forms for a
message feature (e.g. GENTEXT/RMKS) into a single format for easier
understanding later.  This writes the result into a separate .ctxt file to
avoid the potential for accidentally committing the result needlessly.

* clean-rmks.pl -- as above

## NAVADMIN Parsing

I'm now working on a script that can read in a NAVADMIN and try to reformat it into a computer-readable form.

* split-msg.pl -- Reads in a NAVADMIN filename and prints out a JSON blob with the decoded contents of the NAVADMIN.

The JSON output of the above script is an object containing three fields:

1. `head`, a string with the newline-separated text of the NAVADMIN including all radio formatting codes.
2. `body`, a string with the newline-separated text of the NAVADMIN body, including other associated radio formatting (e.g. the `BT` at the end).
3. `fields`, an object containing best-effort decoding attempt at the fields in the header.  All sub-fields that are read will be
strings except for `REF`, which if present will be an array of objects.
  * Each object in the `REF` array will have up to three entries:
    1. `id`, the REF ID as identified in the message (A, B, etc).
    2. `text, the remainder of the field, normally containing reference type, date, etc.
    3. `ampn`, "amplification", optional part of the message but normally has more info on what the reference is (e.g. NAVADMIN 142/18).

A test suite can be run testing this script against the repository database of
NAVADMIN messages, if the Perl "Test::Harness" module is installed.  If so, you
can run the `prove` command: `prove -I modules -r`, which recursively runs all
modules under `t/`.
