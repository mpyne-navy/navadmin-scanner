#!/usr/bin/env perl

use v5.36;

use Mojo::Date;
use Mojo::DOM;
use Mojo::Collection;
use Mojo::JSON qw(decode_json);
use Mojo::File;
use Mojo::UserAgent;
use Mojo::URL;

use Term::ANSIColor qw(:constants);
use Time::HiRes qw(usleep);

no warnings "experimental::for_list";

# Returns a JSON object keyed by NAVADMIN ID
sub read_navadmin_metadata
{
    my $text = eval { Mojo::File->new("navadmin_meta.json")->slurp } // "{}";
    return decode_json($text);
}

sub save_navadmin_metadata ($obj)
{
    my $json = Mojo::JSON::encode_json($obj);

    my $file = Mojo::File->new("navadmin_meta.json");
    $file->spew($json);
}

# Reads a binary blob of HTML and pulls out list of .txt hyperlinks
sub read_navadmin_listing ($html)
{
    my $dom = Mojo::DOM->new($html);
    my $links_ref = $dom->find('a')
        ->grep(sub { ($_->attr("href") // "") =~ qr([nN][aA][vV][^/]*\.txt\??)})
        ->map(attr => 'href')
        ->to_array;

    return @{$links_ref};
}

# Pulls the base website listing NAVADMINs and returns a promise that will
# resolve to the links to the per-year web pages
#
# Note the required Mojo::UserAgent must outlive this function since a promise
# is returned
sub pull_navadmin_year_links ($ua)
{
    my $cur_year = (localtime)[5] + 1900;
    my @years = '2016'.."$cur_year";

    my $BASE_URL = 'https://www.mynavyhr.navy.mil/References/Messages/NAVADMIN-';
    my $base = Mojo::URL->new($BASE_URL);

    my @urls = map { "${BASE_URL}$_/" } (@years);

    return Mojo::Promise->new->resolve(@urls);
}

# Returns a promise that, once resolved, will ensures the NAVADMIN pointed to
# by $url is saved to disk.
sub download_navadmin ($url, $ua, $metadata, $errors)
{
    # Some links end in ?ver=<gibberish>, try them without ver first. But some
    # require ?ver= part too...
    my $no_ver_url = $url->clone->query({ver => undef});
    my $dl_path = $url->path->parts->[-1]; # filename/query from URL
    my $name = $no_ver_url->path->parts->[-1]; # filename from URL
    my $err_key = $no_ver_url->to_string;  # tracking for result of this call

    # The URL may have had lowercase chars, enforce filename starting with "NAV"
    substr $name, 0, 3, "NAV";
    my $shortname = (substr $name, 5, 3) . '/' . (substr $name, 3, 2);

    # Filename to download to
    $name = "NAVADMIN/$name";

    # If file already exists, try to mirror instead of re-download
    my %get_opts;
    if (-e $name) {
        my $ctime = (stat(_))[10];
        $get_opts{'If-Modified-Since'} = Mojo::Date->new($ctime)->to_string;
        $get_opts{'User-Agent'} = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/105.0.0.0 Safari/537.36";
    }

    my $req = $ua->get_p($no_ver_url, \%get_opts)
        ->then(sub ($tx) {
            my $res = $tx->result;

            # Download w/out ?ver= didn't work, assume that is reason and try again
            if ($res->is_error) {
                say "$shortname: Download failed, retrying $dl_path";
                return $ua->get_p($url, \%get_opts);
            }

            # Proceed with existing $tx
            return $tx;
            })
        ->then(sub ($tx) {
            my $res = $tx->result;
            my $url = $tx->req->url->to_string;

            # If we failed it's time to give up
            if ($res->is_error) {
                $errors->{$err_key} = {
                    code => $res->code,
                    msg  => $res->message,
                };

                die "$shortname: Failed to download $url, " . $res->message . " (" . $res->code . ")";
            }

            if (!$res->is_empty) {
                # Save file to disk
                say "Downloaded $name";
                $metadata->{$shortname} //= { };
                $metadata->{$shortname}->{dl_date} = time;
                $metadata->{$shortname}->{dl_url}  = $url;

                $res->save_to($name);
            }

            # Add delay out of respect to the giant Sharepoint in the sky
            my $promise = Mojo::Promise->new(sub ($resolve, $reject) {
                Mojo::IOLoop->timer(0.2 => sub {
                    $resolve->($res->code);
                });
            });

            return $promise;
            })
        ->catch(sub ($err) {
            say STDERR "Error downloading $url: $err";
            return $errors->{$err_key}->{code};
            });

    return $req;
}

my $ua = Mojo::UserAgent->new->request_timeout(10);

my $dl_promise = pull_navadmin_year_links($ua)->then(sub (@urls) {
    # This downloads each provided URL of the by-year page and extracts
    # individual NAVADMIN URLs.
    my @promises = map { $ua->get_p($_)->then(sub ($tx) {
        # $tx represents result of downloading by-year page
        my $req_url = $tx->req->url->to_abs;
        die "Failed to load $req_url: $tx->result->message"
            if $tx->result->is_error;

        my $year = (localtime(time))[5] + 1900;
        if (-e '.has-run' && $req_url !~ /-$year\/$/) {
            return (); # Already run, no additional URLs to grab
        } else {
            say "Loaded NAVADMINs for $req_url";
            Mojo::File->new('.has-run')->spew("NAVADMIN scanner has run");
        }

        # Decode web page result into URLs of individual NAVADMINs
        my @links = read_navadmin_listing($tx->result->body);
        return map { $req_url->clone->path_query($_) } (@links);
    })} (@urls);

    return Mojo::Promise->all(@promises);
})->then(sub (@url_groups) {
    # @url_groups is a nested list of url-lists (one batch per year). Flatten
    # to one list and grab them all.

    my @navadmin_urls = Mojo::Collection->new(@url_groups)->flatten->each;
    my $errors = { };
    my $metadata = read_navadmin_metadata();
    mkdir ("NAVADMIN") unless -e "NAVADMIN";

    if (!@navadmin_urls) {
        say "No NAVADMINs yet this year...";
        return;
    }

    say "Downloading and updating ", scalar @navadmin_urls, " NAVADMIN messages";

    return Mojo::Promise->map({concurrency => 6 }, sub {
            download_navadmin($_, $ua, $metadata, $errors);
        }, @navadmin_urls)
        ->then(sub (@results) {
            my %code_count;
            $code_count{$_->[0]}++ foreach @results;

            for my ($code, $count) (%code_count) {
                if ($code == 200) {
                    say (sprintf ("HTTP %s results: %s", BOLD . GREEN . $code . RESET, BOLD . GREEN . $count . RESET));
                } elsif ($code >= 400) {
                    say (sprintf ("HTTP %s results: %s", BRIGHT_YELLOW . $code . RESET, BRIGHT_YELLOW . $count . RESET));
                } else {
                    say "HTTP $code results: $count";
                }
            }
            say "Total:            ", scalar @results;

            for my ($url, $err) (%$errors) {
                say "$url failed: ", $err->{code}, " ", $err->{msg};
            }

            save_navadmin_metadata($metadata);
        });
})->catch(sub ($err) {
    say "An error occurred! $err";
});

$dl_promise->wait;
