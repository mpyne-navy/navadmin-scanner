#!/usr/bin/env perl

# Breaks a NAVADMIN record message (passed as a filename on the command line)
# into a header and then a main body.

use v5.28;

use feature 'signatures';
use lib 'modules';

use MsgReader qw(read_navadmin_from_file);

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

if (!@ARGV) {
# List all NAVADMINs if no file specified
#   @files = Mojo::File->new('NAVADMIN')->list_tree->grep(qr/\.txt$/)->each;
    usage();
    exit 1;
}

foreach my $path (@ARGV) {
    my $navadmin_data = eval {
        read_navadmin_from_file($path);
    };

    if ($@) {
        say STDERR "Ran into error $@ on $path";
        exit 1;
    }

    say encode_json($navadmin_data);
}
