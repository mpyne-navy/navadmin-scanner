#!/usr/bin/env perl

use v5.28;

use feature 'signatures';

use Mojo::File;

sub simplify_rmks($path, $text)
{
    my @lines = split("\n", $text);
    my $newtext;

    for (@lines) {
        next unless m,RMKS/,;

        if (/^RMKS/) {
            return; # No alts
        }

        $newtext = $text;

        if (/^ +RMKS/) {
            $newtext =~ s,^ +/,,; # update source newtext
            s,^ +,,;              # also update cur line
        }

        if (m,GENTEXT?/RMKS,) {
            $newtext =~ s,GENTEXT?/*,,; # update source newtext
            s,GENTEXT?/,,;              # also update cur line
        }

        if (m,GENTEXT/REMARKS,) {
            $newtext =~ s,GENTEXT/REMARKS,,; # update source newtext
            s,GENTEXT/REMARKS,,;             # also update cur line
        }

        if (m,GENTEXT[A-Z ]*// *RMKS,) {
            $newtext =~ s,GENTEXT.*// *,,; # update source newtext
            s,GENTEXT.*// *,,;             # also update cur line
        }

        if (m,// ?RMKS,) {
            $newtext =~ s,// ?RMKS,//\nRMKS,; # update source newtext
            s,.*// ?RMKS,RMKS,;               # also update cur line
        }

        last
    }

    return unless $newtext;

    # If we make it here, we made alterations
    return $newtext;
}

sub read_navadmin($path)
{
    my $content = $path->slurp;
    my $result = simplify_rmks($path, $content);

    if ($result) {
        say "$path: Writing override";

        my $newpath = $path->to_string;
        $newpath =~ s,\.txt$,.ctxt,; # c for canonical

        my $newfile = Mojo::File->new($newpath);
        $newfile->spurt($result);
    } else {
        say "$path: OK";
    }
}

my @files;

if (@ARGV) {
    # Create Mojo::File for each path param
    @files = map { Mojo::File->new($_) } @ARGV;
} else {
    # List all NAVADMINs if no file specified
    @files = Mojo::File->new('NAVADMIN')->list_tree->grep(qr/\.txt$/)->each;
}

foreach my $path (@files) {
    read_navadmin($path);
}
