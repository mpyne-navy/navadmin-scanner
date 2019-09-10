#!/usr/bin/env perl

use v5.18;

use Mojo::DOM;
use Mojo::Collection;
use Mojo::File;

my $BASE_URL = 'https://www.public.navy.mil/bupers-npc/reference/messages/NAVADMINS/Pages/default.aspx';

# Reads a binary blob of HTML and pulls out list of .txt hyperlinks
sub read_navadmin_listing
{
    my $dom = Mojo::DOM->new(shift);
    my $links_ref = $dom->find('a')
        ->grep(sub { ($_->attr("href") // "") =~ qr(NAV[^/]*\.txt$)})
        ->map(attr => 'href')
        ->to_array;

    return @{$links_ref};
}

my $file = Mojo::File->new($ARGV[0]) or die "No such file";
my @links = read_navadmin_listing($file->slurp);

say $_ foreach @links;
