#!/usr/bin/env perl

use Mojolicious::Lite;
use Mojolicious::Validator;

use File::Glob;

my %navadmin_by_year;
my %navadmin_subj;

# Set static content directory (must be done early, before routes are defined)
app->static->paths->[0] = app->home->child('assets');

# Find known NAVADMINs and build up data mapping for later
foreach my $file (glob("NAVADMIN/NAV*.txt")) {
    my ($twoyr, $id) = ($file =~ m/^NAVADMIN\/NAV([0-9]{2})([0-9]{3})\.txt$/);

    if (!($twoyr && $id)) {
        say "Skipping $file!";
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

get '/' => sub {
    my $c = shift;
    $c->render(template => 'index', years => [reverse sort keys %navadmin_by_year]);
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

    my $name = "NAVADMIN/NAV$twoyr$id.txt";
    return $c->reply->not_found
        unless -e "$name";

    $c->res->headers->content_type('text/plain');
    if (!$c->reply->file($c->app->home->child($name))) {
        $c->reply->exception("Couldn't serve the NAVADMIN!");
    }
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
    for my $year (reverse sort keys %navadmin_by_year) {
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
        list_title => 'All NAVADMIN listing',
        navadmin_list => \@list,
        subjects => \%navadmin_subj
    );
} => 'list-all';

app->start;

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

@@ list-navadmins.html.ep
% layout 'default';
% title $list_title;

<nav class="breadcrumb" aria-label="breadcrumbs">
  <ul>
    <li><a href="/">Home</a></li>
    <li><a href="/">NAVADMINs</a></li>
    <li class="is-active"><a href="#" aria-content="page"><%= $list_title %></a></li>
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
  </head>
  <body>
  <section class="section">
    <div class="container">
      <%= content %>
    </div>
  </section>
  </body>
</html>
