#!/usr/bin/env perl

use v5.36;

use Mojo::Date;
use Mojo::DOM;
use Mojo::Collection;
use Mojo::JSON qw(decode_json);
use Mojo::File;
use Mojo::IOLoop;
use Mojo::Message::Response;
use Mojo::UserAgent;
use Mojo::URL;

use IPC::Cmd qw(run);
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

# Returns a promise that resolves to the provided value (which can itself be
# another promise), after a set delay in seconds, which can be fractional
# seconds
sub resolve_after_delay ($val, $delay)
{
    # Add delay out of respect to the giant Sharepoint in the sky
    return Mojo::Promise->new(sub ($resolve, $reject) {
        Mojo::IOLoop->timer($delay, sub { $resolve->($val); });
    });
}

# Downloads the given URL based on Mojo::UserAgent $ua, but using curl (on
# command line) instead of $ua so that HTTP/2 is used. $opts is a hashref of
# HTTP headers to set
#
# Returns a Mojo::Transaction::HTTP ($tx)
sub download_with_curl ($url, $ua, $opts={})
{
    # We still build a Mojo::Transaction but we won't actually put it into the
    # IOLoop. Instead we will call curl to do that and then parse in the result
    # manually
    my $tx = $ua->build_tx(GET => $url, $opts);

    return Mojo::IOLoop->subprocess->run_p(sub {
        my %o = (%$opts,
            'User-Agent' => 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10.15; rv:136.0) Gecko/20100101 Firefox/136.0',
        );

        # --compressed is required by the firewall, as is the default
        # User-Agent above
        my $args = [qw(curl --compressed --fail --fail-early -m 30 --silent)];

        while (my ($header, $val) = each %o) {
            push @$args, "-H", "$header: $val";
        }
        push @$args, $url;

        my $output = '';
        my ($success, $msg) = run(
            command => $args,
            verbose => 0,
            buffer  => \$output);

        if (!$success) {
            die "curl failed: $msg";
        }

        return $output;
    })->then(sub ($output) {
        # Convert curl output into the appropriate $tx object
        my $res = Mojo::Message::Response->new;

        # Mojo::Message::Response will stop at the content-length when this is
        # in use so we cannot use the response's own ->parse($output) command
        # along with Curl showing header output, so configure Curl to show only
        # the body content and regenerate a fake header.
        $res->code(200);
        $res->body($output);

        $res->save_to("/tmp/navadmin.html");

        open(my $tmp, '>', '/tmp/navadmin.raw');
        say $tmp $output;
        close $tmp;

        $tx->res($res);

        return $tx;
    })->catch(sub ($err) {
        # Convert error into a failed tx
        my $res = Mojo::Message::Response->new;
        $res->code(500);
        $res->headers->content_type('text/plain');
        $res->body("$err");

        say "$url: CURL ERROR: $err";
        $tx->res($res);
        return $tx;
    });
}

# Returns a promise that, once resolved, will ensures the NAVADMIN pointed to
# by $url is saved to disk.
sub download_navadmin ($url, $ua, $metadata, $errors)
{
    # Some of the server redirects may add '../', work those out on our end
    $url = $url->path($url->path->canonicalize);

    # Some links end in ?ver=<gibberish>, try them without ver first. But some
    # require ?ver= part too...
    my $no_ver_url = $url->clone->query({ver => undef});
    my $dl_path = $url->path->parts->[-1]; # filename/query from URL
    my $name = $no_ver_url->path->parts->[-1]; # filename from URL
    my $err_key = $no_ver_url->to_string;  # tracking for result of this call

    # The URL may have had lowercase chars, enforce filename starting with "NAV"
    substr $name, 0, 3, "NAV";
    my $shortname = (substr $name, 5, 3) . '/' . (substr $name, 3, 2);

    # Check for things that will trip the server firewall like directory traversal
    if ($err_key =~ m,\.\./,) {
        die "$shortname: $url would fail if we tried to download it, clean up the URL first!";
    }

    # Filename to download to
    $name = "NAVADMIN/$name";

    # If file already exists, try to mirror instead of re-download
    my %get_opts;
    if (-e $name) {
        my $ctime = (stat(_))[10];
# Disabled with Curl-based downloader since the only info we currently get
# is whether the download failed or not, can't tell 304 vs 200
#       $get_opts{'If-Modified-Since'} = Mojo::Date->new($ctime)->to_string;
    }

    my $req = download_with_curl($url, $ua, \%get_opts)
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
            return resolve_after_delay($res->code, 0.2);
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
    my $year_url_groups = Mojo::Promise->map({ concurrency => 1 }, sub {

        my $p = download_with_curl($_, $ua)->then(sub ($tx) {
            # $tx represents result of downloading by-year page
            my $req_url = $tx->req->url->to_abs;

            my $year = (localtime(time))[5] + 1900;
            if (-e '.has-run' && $req_url !~ /-$year\/$/) {
                return (); # Already run, no additional URLs to grab
            } else {
                # Ignore errors if they occur when refreshing prior years -- yes, this really happens.
                die ("Failed to load $req_url: " . $tx->result->message)
                    if $tx->result->is_error;

                say "Loaded NAVADMINs for $req_url";
                Mojo::File->new('.has-run')->spew("NAVADMIN scanner has run");
            }

            # Decode web page result into URLs of individual NAVADMINs
            my @links = read_navadmin_listing($tx->result->body);
            return map { $req_url->clone->path_query($_) } (@links);
        });

        # More respect for the Great Navy Webserver
        return resolve_after_delay($p, 0.1);
    }, @urls);

    return $year_url_groups;
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
