#!/usr/bin/env perl

# Breaks a NAVADMIN record message (passed as a filename on the command line)
# into a header and then a main body.

use v5.28;

use feature 'signatures';
use lib 'modules';

use MsgReader qw(read_navadmin_from_file);

use List::Util qw(first);
use Mojo::JSON qw(encode_json);

# Get list of all available NAVADMINs, preferring .ctxt version if available
my @files = Mojo::File->new('NAVADMIN')
    ->list
    ->grep(qr/\.txt$/)
    ->map(sub ($f) {
        my $base = $f->basename('.txt');
        my $simplified = $f->sibling("$base.ctxt");
        (-e $simplified->to_string)
            ? $simplified
            : $f
            ;
    })
    ->each;

my %refs = (
    NAVADMINs   => { },
    OPNAVINSTs  => { },
    SECNAVINSTs => { },
    DODINSTs    => { },
);

# Each key should map to a regex with a capture group that pulls out the
# series/ID of the instruction for the type that corresponds to the key
my %ref_scanners = (
    NAVADMINs   => qr/^NAVADMIN ([0-9]{3} *[\/-]? *[0-9]{2})\b/,
    OPNAVINSTs  => qr/^OPNAVINST *([0-9]{4,5}\.[0-9][A-Z]?)\b/,
    SECNAVINSTs => qr/^SECNAVINST *([0-9]{4,5}\.[0-9][A-Z]?)\b/,
    DODINSTs    => qr/^DODINST *([0-9]{4,5}\.[0-9]{1,2})\b/,
);

foreach my $path (@files) {
    say STDERR "Reading $path";
    my $data = eval {
        read_navadmin_from_file($path);
    };

    # Filter out issues
    if ($@) {
        say STDERR "Failed to read from $path";
        next;
    }

    if (!exists $data->{fields} || !exists $data->{fields}->{REF}) {
        say STDERR "No references for $path";
        next;
    }

    my $cur_navadmin = $data->{fields}->{NAVADMIN} // '';
    if (!$cur_navadmin || $cur_navadmin !~ /[0-9]{3}\/[0-9]{2}\b/) {
        say STDERR "Unclear which NAVADMIN $path is";
        next;
    }
    $cur_navadmin =~ s/-/\//;

    # Read in references to central dict
    foreach my $ref (@{$data->{fields}->{REF}}) {
        my $ampn = $ref->{ampn} // undef;
        next unless $ampn;

        my $dest_ref;
        my $dest_dictionary =
            first {
                ($dest_ref) = $ampn =~ $ref_scanners{$_};
            } keys %ref_scanners;
        next unless $dest_dictionary;

        $dest_ref =~ s/-/\//; # NAVADMIN 123-92 rather than 123/92

        $refs{$dest_dictionary}->{$dest_ref} //= [ ];
        push @{$refs{$dest_dictionary}->{$dest_ref}}, $cur_navadmin;
    }
}

say encode_json(\%refs);
