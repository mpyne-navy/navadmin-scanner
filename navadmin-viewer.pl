#!/usr/bin/env perl

use Mojolicious::Lite;
use Mojolicious::Validator;

use File::Glob;

my %navadmin_by_year;
my %navadmin_subj;

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
    my @content = split(/\r?\n/, Mojo::File->new($file)->slurp);
    my @subj_lines;

    foreach (@content) {
        if (m(SUBJ/) .. m(//\s*$)) { # perl range operator
            push @subj_lines, $_;
        }
    }
    next unless @subj_lines;

    my $subj = join(' ', @subj_lines);
    $subj =~ s(^SUBJ/+\s*)();
    $subj =~ s(/+\s*$)();

    next if length $subj > 180;
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
<h1>NAVADMIN Viewer</h1>

This server has NAVADMINs on file for the following years:

<ul>
% for my $year (@{$years}) {
<li><a href="<%= url_for('list-by-year', {year => $year}) %>">Listing for <%= $year %></a>.</li>
% }
<li><a href="<%= url_for('list-all') %>">All NAVADMINs</a></li>
</ul>

@@ list-navadmins.html.ep
% layout 'default';
% title $list_title;

<h3><%= $list_title %>:</h3>
<div class="total_count"><%= scalar @{$navadmin_list} %> total</div>

<table border="1">
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

@@ layouts/default.html.ep
<!DOCTYPE html>
<html>
  <head><title><%= title %></title></head>
  <body><%= content %></body>
</html>
