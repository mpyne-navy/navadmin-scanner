# Introduction

This is a script to spider the [Navy Personnel
Command](https://www.public.navy.mil/bupers-npc/reference/messages/NAVADMINS/Pages/default.aspx)
website to help identify and (soon) download NAVADMIN messages.

The idea will be to migrate from just downloading and syncing up messages to
one day mirroring them with better search, maybe better formatting, *maybe*
even auto-addition of appropriate hyperlinks. But for now I need to just get
downloading this to work.

# Setup

You need Perl 5 and the [Mojolicious](https://mojolicious.org/) web framework
installed to try this.  Pretty much every Unix-like OS has Perl easily
available, from there Mojolicious is self-contained and not too hard to
install, either by using its own installer or from CPAN (I recommend [CPAN
Minus](https://metacpan.org/pod/App::cpanminus)).

# Run

From there you should just be able to run `./mojo-mirror.pl` (I'll fix the name
later, I promise).
