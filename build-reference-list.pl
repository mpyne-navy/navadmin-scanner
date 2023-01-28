#!/usr/bin/env perl

# Breaks a NAVADMIN record message (passed as a filename on the command line)
# into a header and then a main body.

use v5.28;

use feature 'signatures';
use lib 'modules';

use MsgReader qw(read_navadmin_from_file);

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
    NAVADMINs =>  { },
    OPNAVINSTs => { },
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

        if ($ampn =~ /^NAVADMIN/) {
            my ($dest_navadmin) = $ampn =~ /([0-9]{3} *[\/-]? *[0-9]{2})\b/;
            if (!$dest_navadmin) {
                say STDERR "Can't figure out dest NAVADMIN in $cur_navadmin REF ", $ref->{id}, " dest $ampn";
                next;
            }
            $dest_navadmin =~ s/-/\//;
            $refs{NAVADMINs}->{$dest_navadmin} //= [ ];
            push @{$refs{NAVADMINs}->{$dest_navadmin}}, $cur_navadmin;
        }
    }
}

say encode_json(\%refs);
