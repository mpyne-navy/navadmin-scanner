# Introduction

This is a script to spider the [Navy Personnel
Command](https://www.public.navy.mil/bupers-npc/reference/messages/NAVADMINS/Pages/default.aspx)
website to help identify and download NAVADMIN messages.

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
`./download-updated-navadmins.pl`.

The first time the script is ever run, it will download all NAVADMINs it can
find on the NPC website.

Subsequently (based on whether a `.has-run` file is present) it will only check
for NAVADMINs for the current year, and will use the timestamp of existing
NAVADMIN files to re-download from the server if the NAVADMIN is changed.

## Serving up NAVADMINs

After downloading the NAVADMINs, you can run `./navadmin-viewer.pl` to run a
simple Web server (also powered by Mojolicious) to list NAVADMINs and serve up
individual NAVADMINs. It is pretty bare at this point but wouldn't be too hard
to pretty up.

Please don't actually run this on a production website if you aren't familiar
enough with Mojolicious to set it up, I haven't configure CSRF token support or
client secret configs or running with hypnotoad or any of that fun stuff.
