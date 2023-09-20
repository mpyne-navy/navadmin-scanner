#!/usr/bin/env perl

use v5.36;

use Mojolicious::Lite -signatures;
use Mojolicious::Validator;

use Mojo::File;
use Mojo::JSON;

use File::Glob;
use List::Util qw(min);

no warnings "experimental::for_list";

my %navadmin_by_year;
my %navadmin_subj;
my $navadmin_dl_metadata;
my $cross_refs;
my @SORTED_YEARS;

# Set static content directory (must be done early, before routes are defined)
app->static->paths->[0] = app->home->child('assets');

# Compress dynamically-generated content (gzip by default).
app->renderer->compress(1);

hook(after_static => sub ($c) {
    $c->res->headers->cache_control('max-age=604800, public, immutable');
});

# Read in metadata from download phase
my $file_text = eval { Mojo::File->new("navadmin_meta.json")->slurp; } // "{}";
$navadmin_dl_metadata = Mojo::JSON::decode_json($file_text);

my $cross_ref_data = eval { Mojo::File->new("cross-refs.json")->slurp; };
$cross_ref_data  //= q( { "NAVADMINs": {} } );
$cross_refs = Mojo::JSON::decode_json($cross_ref_data);

# Find known NAVADMINs and build up data mapping for later
foreach my $file (glob("NAVADMIN/NAV*.txt")) {
    my ($twoyr, $id) = ($file =~ m/^NAVADMIN\/NAV([0-9]{2})([0-9]{3})\.txt$/);

    if (!($twoyr && $id)) {
        app->log->debug("Skipping $file!");
        next;
    }

    my $year = $twoyr + (($twoyr > 80) ? 1900 : 2000);
    $navadmin_by_year{$year}->{$id} = $file;

    # Look for override file
    my $filename = $file;
    $filename =~ s,\.txt,.ctxt,;
    $filename = $file unless -e $filename;

    # Try to find subject
    my @subj_lines = grep {
        m(^\s*SUBJ[/:]) .. m(//\s*$) # perl range operator
    } split(/\r?\n/, Mojo::File->new($filename)->slurp . " //");

    next unless @subj_lines;

    my $subj = join(' ', @subj_lines);
    $subj =~ s(^SUBJ[/:]+\s*)();
    $subj =~ s(/+\s*$)();

    substr ($subj, 217) = '...'
        if length $subj > 220;
    $navadmin_subj{"$id/$twoyr"} = $subj
}

@SORTED_YEARS = reverse sort keys %navadmin_by_year;

# Add a helper in templates to grab NAVADMIN title by id
helper title_from_id => sub ($c, $id) {
    return $navadmin_subj{$id};
};

# Now that we've loaded all NAVADMINs we are aware of, define the Web site
# routes that we will support using Mojolicious::Lite's DSL.

get '/' => sub {
    my $c = shift;

    # Figure out number of NAVADMINs by year so we can render the yearly list
    my $year_counts = {
        map { ($_, scalar keys %{$navadmin_by_year{$_}}) } @SORTED_YEARS,
    };

    state @msg_list;

    # Find the most recent messages in the current and last year to display
    # them first
    if (!@msg_list) {
        for my $year ($SORTED_YEARS[0], $SORTED_YEARS[1]) {
            my $two_digit_year = sprintf("%02d", $year % 100);

            my $msg_bounds = min($year_counts->{$year}, 8 - @msg_list) - 1;
            last if $msg_bounds < 0; # stop if the list is full

            my @last_msg_ids = (reverse sort keys %{$navadmin_by_year{$year}})[0..$msg_bounds];
            my @last_msg = @navadmin_subj{map { "$_/$two_digit_year" } @last_msg_ids};

            push @msg_list, map { {
                id    => $_,
                twoyr => $two_digit_year,
                subj  => $navadmin_subj{"$_/$two_digit_year"}
            } } @last_msg_ids;
        }
    }

    $c->render(template => 'index',
        years       => \@SORTED_YEARS,
        year_counts => $year_counts,
        last_eight  => \@msg_list,
    );
};

get '/about' => sub {
    my $c = shift;
    $c->render();
};

get '/by-year/:year' => sub {
    my $c = shift;
    my $year = int($c->stash('year'));

    if (!exists $navadmin_by_year{$year}) {
        $c->reply->not_found;
        return;
    }

    my $navadmins_for_year_ref = $navadmin_by_year{$year};
    my $two_digit_year = sprintf("%02d", $year % 100);
    my @list = map { "$_/$two_digit_year" } (reverse sort keys %{$navadmins_for_year_ref});

    $c->render(
        template => 'list-navadmins',
        list_title => "NAVADMINs sent in $year",
        breadcrumb => $year,
        navadmin_list => \@list,
        subjects => \%navadmin_subj
    );
} => 'list-by-year';

# The extra => [] adds built-in placeholder restrictions
get '/NAVADMIN/:id/:twoyr'
=> [id => qr/[0-9]{3}/, twoyr => qr/[0-9]{2}/]
=> sub {
    my $c = shift;
    my $id = $c->stash('id');
    my $twoyr = $c->stash('twoyr');
    my $index = "$id/$twoyr";

    my $title = $navadmin_subj{$index};
    return $c->reply->not_found("Couldn't find NAVADMIN $index!")
        unless $title;

    my $name = "NAVADMIN/NAV$twoyr$id.ctxt";
    $name = "NAVADMIN/NAV$twoyr$id.txt"
        unless -e "$name";

    return $c->reply->not_found
        unless -e "$name";

    # Was text/plain specifically requested?
    if ($c->accepts('', 'txt')) {
        return $c->reply->file($name);
    }

    my $meta = $navadmin_dl_metadata->{$index} // '';

    # Will be an array of NAVADMINs that link to this one in format "xxx/yy"
    my $cross_ref = $cross_refs->{NAVADMINs}->{$index} // [];

    # Otherwise show a fancy web page
    $c->render(template => 'show-navadmin',
        navadmin_title => $title,
        filepath => $name,
        metainfo => $meta,
        crossref => $cross_ref,
    );
} => 'serve-navadmin';

get '/NAVADMIN' => sub {
    my $c = shift;
    my $qsrch = $c->req->query_params->param('q');

    if (!$qsrch) {
        $c->redirect_to('list-all');
        return;
    }

    $qsrch = lc $qsrch;
    my @results;
    for my $year (@SORTED_YEARS) {
        my $navadmins_for_year_ref = $navadmin_by_year{$year};
        my $two_digit_year = sprintf("%02d", $year % 100);

        my @ids = map { "$_/$two_digit_year" } (reverse sort keys %{$navadmins_for_year_ref});
        push @results,
            grep { index(lc $navadmin_subj{$_}, $qsrch) != -1 }
            grep { exists $navadmin_subj{$_} }
                (@ids);
    }

    $c->render(
        template => 'list-navadmins',
        list_title => 'Search Results',
        breadcrumb => "NAVADMIN Subject search for $qsrch",
        navadmin_list => \@results,
        subjects => \%navadmin_subj
    );
} => 'search-navadmin';

get '/NAVADMIN/all' => sub {
    my $c = shift;

    my @list;
    for my $year (sort keys %navadmin_by_year) {
        my $navadmins_for_year_ref = $navadmin_by_year{$year};
        my $two_digit_year = sprintf("%02d", $year % 100);
        push @list, map { "$_/$two_digit_year" } (sort keys %{$navadmins_for_year_ref});
    }

    $c->render(
        template => 'list-navadmins',
        list_title => 'List of all NAVADMINs',
        breadcrumb => 'All',
        navadmin_list => \@list,
        subjects => \%navadmin_subj
    );
} => 'list-all';

get '/known_instructions' => sub ($c) {
    my $data = { };

    my @inst_keys = grep { $_ ne 'NAVADMINs' } keys $cross_refs->%*;
    $data->{$_} = {} foreach @inst_keys;

    for my $inst_key (@inst_keys) {
        my @inst_series      = keys   $cross_refs->{$inst_key}->%*;
        my @inst_series_refs = values $cross_refs->{$inst_key}->%*;
        # Convert list of NAVADMINs refs to size of the list
        @inst_series_refs = map { scalar $_->@* } @inst_series_refs;
        $data->{$inst_key}->@{@inst_series} = @inst_series_refs;
    }

    $c->stash(inst_keys => $data);

    $c->respond_to(
        json => { json => $data },
        html => { template => 'list-inst' },
    );
} => 'list-inst';

get '/instruction/:cat/:series'
=> [cat => [qw(DOD OPNAV SECNAV)], series => qr/[0-9]{4,5}\.[0-9]{1,2}[A-Z]?/]
=> sub ($c) {
    my $cat    = $c->stash('cat');
    my $series = $c->stash('series');

    if (!exists $cross_refs->{"${cat}INSTs"}->{$series}) {
        $c->reply->not_found;
        return;
    }

    my $refs_list = $cross_refs->{"${cat}INSTs"}->{$series};
    $c->stash(
        inst      => "${cat}INST $series",
        inst_refs => $refs_list,
        subjects  => \%navadmin_subj,
    );

    $c->respond_to(
        json => { json => [map { "NAVADMIN $_" } @$refs_list] },
        html => { template => 'show-inst-refs' },
    );
} => 'show-inst-refs';

app->start;

# This Perl tag closes out the Perl code and Perl will make everything *after*
# this tag available to the code above under a filehandle known as "DATA".
# Mojolicious::Lite uses this internally and splits this data up into
# virtual files (each separate file tagged by @@).
#
# Files ending in .ep are "Embedded Perl", similar to other Web templating
# frameworks.
__DATA__

@@ index.html.ep
% layout 'default';
% title 'NAVADMIN Viewer';
<nav class="breadcrumb" aria-label="breadcrumbs">
  <ul>
    <li class="is-active"><a href="/">Home</a></li>
  </ul>
</nav>

<div class="content">

<h1 class="title">NAVADMIN Viewer</h1>

<h2>Most Recent Eight</h2>

<ul>
% for my $entry (@{$last_eight}) {
%   my $id = $entry->{id};
%   my $twoyr = $entry->{twoyr};
    <li><a href="<%= url_for('serve-navadmin', { id => $id, twoyr => $twoyr }) %>">
            <span class="tag"><%= "$id/$twoyr" =%></span>
            <%= $entry->{subj} %>
        </a>
    </li>
% }
</ul>

<h2>List of all NAVADMINs per year</h2>

  <table class="table is-striped is-bordered is-hoverable">
    <thead>
      <tr>
        <th>Year</th>
        <th>Number of NAVADMINs</th>
      </tr>
    </thead>

    <!-- URLs here based on format supported by 'serve-navadmin' route -->
    <tbody>
% for my $year (@{$years}) {
% my $count = $year_counts->{$year};
      <tr>
        <td><%= $year %></td>
        <td><a href="<%= url_for('list-by-year', { year => $year }) %>">
                <b><%= $count %></b> NAVADMINs on file
            </a>
        </td>
      </tr>
% }
    </tbody>
  </table>
</div>

@@ show-navadmin.html.ep
% layout 'default';
% title $navadmin_title;
% my $year = $twoyr > 80 ? "19$twoyr" : "20$twoyr";

%# Provide social media open graph metadata to make Twitter, Slack, etc.
%# happy
% content_for header_meta => begin
    <meta property="og:title" content="<%= qq(NAVADMIN $id/$twoyr) %>" />
    <meta property="og:type" content="website" />
    <meta property="og:image" content="/img/social-graph-logo.png" />
    <meta property="og:image:type" content="image/png" />
    <meta property="og:image:width" content="961" />
    <meta property="og:image:height" content="482" />
    <meta property="og:image:alt" content="Picture of title page of 1913 series Navy General Orders" />
    <meta property="og:url" content="<%= url_for()->to_abs %>" />
    <meta property="og:description" content="<%= $navadmin_title %>" />
    <meta property="og:locale" content="en_US" />
    <meta property="og:site_name" content="NAVADMIN Scanner/Viewer (Unofficial)" />
% end

<nav class="breadcrumb" aria-label="breadcrumbs">
  <ul>
    <li><a href="/">Home</a></li>
    <li><a href="/">NAVADMINs</a></li>
    <li><a href="<%= url_for('list-by-year', year => $year) %>"><%= $year %></a></li>
    <li class="is-active"><a href="#" aria-content="page"><%= "NAVADMIN $id/$twoyr" %></a></li>
  </ul>
</nav>

<div class="content">
<h3 class="title"><%= $navadmin_title %>:</h3>

% if (scalar @$crossref) {
<details class="crossrefs mb-3">
<summary>
<span class="tag"><%= scalar @$crossref %></span> NAVADMINs are known that
refer back to this one:</summary>
<table class="table">
<thead>
  <tr>
    <th>NAVADMIN ID</th>
    <th>Title</th>
  </tr>
</thead>
<tbody>
% for my $cr (@$crossref) {
% my ($refid, $reftwoyr) = split('/', $cr);
  <tr>
    <td>NAVADMIN <%= $cr %></td>
    <td><a href="<%= url_for('serve-navadmin', id => $refid, twoyr => $reftwoyr) %>"><%= title_from_id($cr) %></a></td>
  </tr>
% }
</tbody>
</table>
</details>
% }

<main>
% if ($metainfo) {
<div class="level">
  <div class="level-left">
    % if ($metainfo->{links}) {
        % for my $link (@{$metainfo->{links}}) {
        <a rel="noopener nofollow" class="level-item button is-link" target="_blank"
           href="<%= b($link->{url}) %>">
          <%= $link->{text} %>
        </a>
        % }
    % }
  </div>

  <div class="level-right">
    <a rel="noopener nofollow" class="level-item button is-info" target="_blank"
       href="<%= b($metainfo->{dl_url}) %>">
      Official NAVADMIN
    </a>
  </div>
</div>
% }

<pre>
% my $content = Mojo::File->new($filepath)->slurp;
% my $escaped = b($content)->decode('UTF-8')->xml_escape;
% $escaped =~ s{NAVADMIN ?([0-9][0-9][0-9])([-/])([0-9][0-9])}{<a href="/NAVADMIN/$1/$3">NAVADMIN $1$2$3</a>}g;
% $escaped =~ s{([a-zA-Z0-9._-]+)\([Aa][Tt]\)([a-zA-Z.]+\.[a-zA-Z]+)}{<a title="Decoded from $&" href="mailto:\L$1\@$2\E">\L$1\@$2</a>}g;
<%= b($escaped) %>
</pre>
</main>

</div>

@@ about.html.ep
% layout 'default';
% title "About NAVADMIN Viewer";

<nav class="breadcrumb" aria-label="breadcrumbs">
  <ul>
    <li><a href="/">Home</a></li>
    <li class="is-active"><a href="<%= url_for('about') %>">About</a></li>
  </ul>
</nav>

<h3 class="title"><%= stash 'title' %></h3>

<div class="content">

<p>This is a viewer for archived U.S. Navy administrative messages
(NAVADMINs) dating back to 2005.</p>

<p>Written by CDR Mike Pyne, USN</p>

</div>

@@ list-navadmins.html.ep
% layout 'default';
% title $list_title;

<nav class="breadcrumb" aria-label="breadcrumbs">
  <ul>
    <li><a href="/">Home</a></li>
    <li><a href="/">NAVADMINs</a></li>
    <li class="is-active"><a href="#" aria-content="page"><%= $breadcrumb %></a></li>
  </ul>
</nav>

<h3 class="title"><%= $list_title %>:</h3>

<div class="content">
  <p><span class="tag is-primary"><%= scalar @{$navadmin_list} %></span> listed NAVADMINs in this list:</p>

  <table class="table is-striped is-bordered is-hoverable">
    <thead>
      <tr>
        <th>NAVADMIN</th>
        <th>Title</th>
      </tr>
    </thead>

    <!-- URLs here based on format supported by 'serve-navadmin' route -->
    <tbody>
% for my $i (@{$navadmin_list}) {
      <tr>
        <td><%= $i %></td>
%   if (my $subj = $subjects->{$i}) {
        <td><a href="/NAVADMIN/<%= $i %>"><%= $subj %></a></td>
%   } else {
        <td><a href="/NAVADMIN/<%= $i %>">NAVADMIN <%= $i %> - Unknown title</a></td>
%   }
      </tr>
% }
    </tbody>
  </table>
</div>

@@ show-inst-refs.html.ep
% layout 'default';
% title "Cross references to $inst";

<nav class="breadcrumb" aria-label="breadcrumbs">
  <ul>
    <li><a href="/">Home</a></li>
    <li><a href="<%= url_for('list-inst') %>">Known Instructions</a></li>
    <li class="is-active"><a href="<%= url_for %>"><%= stash 'title' %></a></li>
  </ul>
</nav>

<h3 class="title"><%= stash 'title' %></h3>

<div class="content">

<p>This instruction was referenced by the following NAVADMINs in the NAVADMIN database.
This list is only a partial best guess.

<table class="table">
<thead>
  <tr>
    <th>NAVADMIN</th>
    <th>Subject</th>
  </tr>
</thead>
<tbody>
% for my $cross_ref ($inst_refs->@*) {
  <tr>
    <td><a href="/NAVADMIN/<%=$cross_ref%>">NAVADMIN <%= "$cross_ref" %></a></td>
    <td><%= $subjects->{$cross_ref} %></td>
  </tr>
% }
</tbody>
</table>

</div>

@@ list-inst.html.ep
% layout 'default';
% title 'Instruction cross-reference';

<nav class="breadcrumb" aria-label="breadcrumbs">
  <ul>
    <li><a href="/">Home</a></li>
    <li class="is-active"><a href="<%= url_for %>"><%= stash 'title' %></a></li>
  </ul>
</nav>

<h3 class="title"><%= stash 'title' %></h3>

<div class="content">

<p>These instructions were referenced by NAVADMINs in the NAVADMIN database.
This list is only a partial best guess.

<table class="table">
<thead>
  <tr>
    <th>Directive</th>
    <th>Number of References</th>
  </tr>
</thead>
<tbody>
% for my $cat (keys $inst_keys->%*) {
%   my $cat_name = $cat =~ s/s$//r;
%   my $cat_no_inst = $cat_name =~ s/INST$//r;

%   my $inst_series_of_cat = $inst_keys->{$cat};
%   my @inst_ids = sort keys $inst_series_of_cat->%*;
%   for my $inst (@inst_ids) {
    <tr>
      <td><a href="<%= url_for('show-inst-refs', cat => $cat_no_inst, series => $inst) %>"><%= "$cat_name $inst" %></a></td>
      <td><%= $inst_series_of_cat->{$inst} %></td>
    </tr>
%   }
% }
</tbody>
</table>

</div>


@@ layouts/default.html.ep
<!DOCTYPE html>
<html>
  <head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title><%= title %></title>
    <link rel="stylesheet" href="/css/bulma.css">
    <link rel="icon" href="/img/Nautical_star.svg">
    <%= content 'header_meta' %>
    <style>
    body {
      display: flex;
      min-height: 100vh;
      flex-direction: column;
    }

    .section {
      flex: 1; /* Fill up all space before footer to force footer to end */
    }
    </style>
  </head>
  <body>
  <nav class="navbar is-dark" role="navigation" aria-label="main navigation">
    <div class="navbar-brand">
      <span class="navbar-item">NAVADMIN Scanner/Viewer</span>

      <a role="button" class="navbar-burger burger" aria-label="menu" aria-expanded="false" data-target="navbarMenu">
        <span aria-hidden="true"></span>
        <span aria-hidden="true"></span>
        <span aria-hidden="true"></span>
      </a>
    </div>

    <!-- By default, does not show on mobile. Javascript to toggle visibility contained below. -->
    <div id="navbarMenu" class="navbar-menu">
      <div class="navbar-start">
        <a href="/" class="navbar-item">Home</a>

        <a href="<%= url_for('list-inst') %>" class="navbar-item">Instruction Cross-refs</a>

        <div class="navbar-item has-dropdown is-hoverable">
          <a class="navbar-link">
            More
          </a>

          <div class="navbar-dropdown">
            <a class="navbar-item" href="https://github.com/mpyne-navy/navadmin-scanner">
                Github
            </a>
            <!--
            <a class="navbar-item">
              Contact
            </a>
            -->
            <hr class="navbar-divider">
            <a class="navbar-item" href="<%= url_for('about') %>">
              About
            </a>
          </div>
        </div>
      </div>

      <div class="navbar-end">
        <div class="navbar-item">
          <form action="<%= url_for('search-navadmin') %>" method="GET">
            <div class="field has-addons">
              <div class="control">
                <input name="q" class="input" type="text" placeholder="Search NAVADMIN subjects...">
              </div>
              <div class="control">
                <button class="button is-link">Search</button>
              </div>
            </div>
          </form>
        </div>
      </div>
    </div>
  </nav>

  <section class="section">
    <div class="container">
      <%= content %>
    </div>
  </section>

  <footer class="footer">
    <div class="content has-text-centered">
      <p>This site is an <strong>UNOFFICIAL</strong> copy of the <a
      href="https://www.mynavyhr.navy.mil/References/Messages/">U.S. Navy NAVADMIN messages site</a>.
      It is intended as a convenience for users but you should confirm from the source reference
      before doing anything important.
    </div>
  </footer>

  <!-- Toggle visibility of mobile menu -->
  <!-- See https://bulma.io/documentation/components/navbar/ -->
  <script>
    document.addEventListener('DOMContentLoaded', () => {
      const $navbarBurgers = Array.prototype.slice.call(document.querySelectorAll('.navbar-burger'), 0);

      $navbarBurgers.forEach(el => {
        el.addEventListener('click', () => {
          const $target = document.getElementById(el.dataset.target);
          el.classList.toggle('is-active');
          $target.classList.toggle('is-active');
        });
      });
    });
  </script>

  </body>
</html>

@@ not_found.html.ep
% layout 'default';
% title 'NAVADMIN not found';

<div class="notification is-warning is-size-4 has-text-centered">
    The page or NAVADMIN you are looking for could not be found.
</div>
