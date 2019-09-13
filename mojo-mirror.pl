#!/usr/bin/env perl

use v5.18;

use Mojo::DOM;
use Mojo::Collection;
use Mojo::File;
use Mojo::UserAgent;
use Mojo::URL;

use Time::HiRes qw(usleep);

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

# Pulls the base website listing NAVADMINs and returns a promise that will
# resolve to the links to the per-year web pages
sub pull_navadmin_year_links
{
    my $ua = shift; # User agent must outlive this function

    my $BASE_URL = 'https://www.public.navy.mil/bupers-npc/reference/messages/NAVADMINS/Pages/default.aspx';
    my $base = Mojo::URL->new($BASE_URL);

    my $promise = $ua->get_p($BASE_URL)
        ->then(sub {
            my $tx = shift;
            die ("Something broke: " . $tx->message)
                if $tx->result->is_error;
            say "Result success, looking for hyperlinks";
            my $dom = $tx->result->dom;
            my $links_ref = $dom->find('a')
                ->grep(sub { ($_->attr("href") // "") =~ qr(NAVADMIN[0-9]*\.aspx$)})
                ->map(attr => 'href')
                ->to_array;

            my @urls = map { $base->clone->path($_)->to_abs } (@{$links_ref});
            return @urls;
        });

    return $promise;
}

my $ua = Mojo::UserAgent->new;
my @navadmin_urls;

pull_navadmin_year_links($ua)->then(sub {
    my @promises = map { $ua->get_p($_)->then(sub {
        my $tx = shift;
        my $req_url = $tx->req->url->to_abs;
        die "Failed to load $req_url: $tx->result->message"
            if $tx->result->is_error;

        say "Loaded NAVADMINs for $req_url";
        my @links = read_navadmin_listing($tx->result->body);

        push @navadmin_urls, map { $req_url->clone->path($_) } (@links);
        return 1;
    })} (@_);

    return Mojo::Promise->all(@promises);
})->catch(sub {
    say "An error occurred! $_[0]";
})->wait;

say "Ended up knowing about ", scalar @navadmin_urls, " separate NAVADMINs";

my %errors;
mkdir ("NAVADMIN") unless -e "NAVADMIN";

while (my $url = shift @navadmin_urls) {
    my $name = $url->to_string;
    $name =~ s(^.*/)(); # Remove everything up to last /
    $name = "NAVADMIN/$name";
    next if -e $name;   # Don't clobber files we've already downloaded
                        # TODO: Check if modified?
    say "Downloading NAVADMIN $name";

    my $result = $ua->get($url)->result;
    if ($result->is_error) {
        $errors{$url->to_string} = {
            code => $result->code,
            msg  => $result->message,
        };
        say STDERR "Failed to download $url: ", $result->code;
    }

    # Save file to disk
    $result->save_to($name);

    usleep (30000); # Some slowdown out of respect to the giant Sharepoint in the sky
}

while (my ($url, $err) = each %errors) {
    say "$url failed: ", $err->{code}, " ", $err->{msg};
}
