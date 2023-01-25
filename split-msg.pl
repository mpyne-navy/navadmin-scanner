#!/usr/bin/env perl

# Breaks a NAVADMIN record message (passed as a filename on the command line)
# into a header and then a main body.

use v5.28;

use feature 'signatures';

use Mojo::File;
use Mojo::JSON qw(encode_json);

sub usage()
{
    say <<~EOF;
        $0 <path-to-navadmin.txt>

        Reads the given NAVADMIN and spits out a JSON array containing two
        strings in order, the header and then the message body.
        EOF
    exit 1;
}

sub split_up_navadmin($text)
{
    my ($head, $body);
    my $in_head = 1;

    my @lines = split("\n", $text);
    while (defined (my $line = shift @lines)) {
        # Look for header fields getting jammed together, this risks mixing
        # with the body
        if ($in_head && $line =~ m,// *[^ ], && $line !~ m, *//[\r ]*$,) {
            my ($field, $rest) = split(/\/\/ */, $line, 2); # split into 2 fields max
            $field = "$field//";
            $line = $field;
            unshift @lines, $rest;

            # current field in $line should now be guaranteed to have no text after //
        }

#       say "cur line: $line (", scalar @lines, " more to read)";

        if ($in_head && (
                $line =~ m,^(GENTEXT/)?[rR][mM][kK][sS]/, ||
                $line =~ m,^(GENTEXT/)?REMARKS/,          ||
                # maybe they just started with the text...
                $line =~ m,^RMKS1\.,                      ||
                $line =~ m,^1\.,
            ))
        {
            $in_head = 0; # switch to reading body
        }

        if ($in_head) {
            $head .= "$line\n";
        } else {
            $body .= "$line\n";
        }
    }

    if (!$body) {
        # Something went wrong, return error exit code
        exit 1;
    }

    return ($head, $body);
}

sub read_navadmin($path)
{
    my $content = $path->slurp;
    my ($head, $body) = split_up_navadmin($content);
    say encode_json({ head => $head, body => $body });
}

my @files;

if (@ARGV) {
    # Create Mojo::File for each path param
    @files = map { Mojo::File->new($_) } @ARGV;
} else {
    usage();
    # List all NAVADMINs if no file specified
#   @files = Mojo::File->new('NAVADMIN')->list_tree->grep(qr/\.txt$/)->each;
}

foreach my $path (@files) {
    read_navadmin($path);
}
