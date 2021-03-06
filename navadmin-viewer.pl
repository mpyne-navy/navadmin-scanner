#!/usr/bin/env perl

use Mojolicious::Lite;
use Mojolicious::Validator;

use File::Glob;

my %navadmin_by_year;
my %navadmin_subj;
my @SORTED_YEARS;

# Set static content directory (must be done early, before routes are defined)
app->static->paths->[0] = app->home->child('assets');

# Find known NAVADMINs and build up data mapping for later
foreach my $file (glob("NAVADMIN/NAV*.txt")) {
    my ($twoyr, $id) = ($file =~ m/^NAVADMIN\/NAV([0-9]{2})([0-9]{3})\.txt$/);

    if (!($twoyr && $id)) {
        app->log->debug("Skipping $file!");
        next;
    }

    my $year = $twoyr + (($twoyr > 80) ? 1900 : 2000);
    $navadmin_by_year{$year}->{$id} = $file;

    # Try to find subject
    my @subj_lines = grep {
        m(^\s*SUBJ[/:]) .. m(//\s*$) # perl range operator
    } split(/\r?\n/, Mojo::File->new($file)->slurp . " //");

    next unless @subj_lines;

    my $subj = join(' ', @subj_lines);
    $subj =~ s(^SUBJ[/:]+\s*)();
    $subj =~ s(/+\s*$)();

    substr ($subj, 217) = '...'
        if length $subj > 220;
    $navadmin_subj{"$id/$twoyr"} = $subj
}

@SORTED_YEARS = reverse sort keys %navadmin_by_year;

# Now that we've loaded all NAVADMINs we are aware of, define the Web site
# routes that we will support using Mojolicious::Lite's DSL.

get '/' => sub {
    my $c = shift;
    $c->render(template => 'index', years => \@SORTED_YEARS);
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

    my $title = $navadmin_subj{"$id/$twoyr"};
    return $c->reply->exception("Couldn't find the NAVADMIN!")
        unless $title;

    my $name = "NAVADMIN/NAV$twoyr$id.txt";
    return $c->reply->not_found
        unless -e "$name";

    $c->render(template => 'show-navadmin',
        navadmin_title => $title,
        filepath => $name,
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

<h1 class="title">NAVADMIN Viewer</h1>

This server has NAVADMINs on file for the following years:

<div class="content">
  <ul>
% for my $year (@{$years}) {
    <li><a href="<%= url_for('list-by-year', {year => $year}) %>">Listing for <%= $year %></a>.</li>
% }
    <li><a href="<%= url_for('list-all') %>">All NAVADMINs</a></li>
  </ul>
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

<h3 class="title"><%= $navadmin_title %>:</h3>

<div class="content">
<pre>
% my $content = Mojo::File->new($filepath)->slurp;
<%= b($content)->xml_escape %>
</pre>
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

@@ layouts/default.html.ep
<!DOCTYPE html>
<html>
  <head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title><%= title %></title>
    <link rel="stylesheet" href="/css/bulma.css">
    <%= content 'header_meta' %>
  </head>
  <body>
  <nav class="navbar is-dark" role="navigation" aria-label="main navigation">
    <div class="navbar-brand">
      <a class="navbar-item">NAVADMIN Scanner/Viewer</a>

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
