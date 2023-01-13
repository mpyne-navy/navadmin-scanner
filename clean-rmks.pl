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

sub decode_navadmin($path, $text)
{
    my $state = 'start';
    my $dtg = 'unknown';
    my %rules = (
        start => [
            [ qr/^(?:ROUTINE *)?(?:DTG )?(?:[ZRPO] ?)*([0-9]{6,}[zZ]+ [A-Za-z]{3,4} ?[0-9]{2})/
                => sub { $dtg = $1; $state = 'mtf' }
            ],
            [ qr/^(?:[ZRPO] ?)*([0-9]{6} [A-Za-z]{3} ?[0-9]{2})/
                => sub { $dtg = $1; $state = 'mtf' }
            ],
        ],

        mtf => [
            [ qr/./ => sub { $state = 'end' }
            ],
        ],
    );

    LINE: for my $line (split("\n", $text)) {
        last if $state eq 'end';
        my $ruleList = $rules{$state} or die "Unhandled state $state";

        for my $rule (@$ruleList) {
            my ($re, $sub) = ($rule->[0], $rule->[1]);
            if ($line =~ $re) {
                $sub->();
                next LINE;
            }
        }
    }

    $dtg = uc $dtg;   # Some had lowercase months for some reason
    $dtg =~ s,Z+,Z,g; # Some had consecutive 'Z' markers by accident
    $dtg =~ s,([A-Z]{3})([0-9]{2}),\1 \2,g; # Missing space between month and year NAV06083
    $dtg =~ s,([0-9]{6}) ([A-Z]{3}),\1Z \2,g; # Missing timezone NAV12002, NAV12020
    $dtg =~ s,AUGY ,AUG ,;

    say "$path: DTG is $dtg";
}

sub read_navadmin($path)
{
    my $content = $path->slurp;
    my $result = simplify_rmks($path, $content);

    if ($result) {
        my $newpath = $path->to_string;
        $newpath =~ s,\.txt$,.ctxt,; # c for canonical

        my $newfile = Mojo::File->new($newpath);
        $newfile->spurt($result);
        $content = $result;
    }

    decode_navadmin($path, $content);
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
