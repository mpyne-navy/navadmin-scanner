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
    my $content = Mojo::File->new($file)->slurp;
    my ($subj) = ($content =~ m(SUBJ/[/\s]*(.*)//));
    $navadmin_subj{"$id/$twoyr"} = $subj
        if $subj;
}

get '/' => sub {
    my $c = shift;
    $c->render(template => 'index', years => [sort keys %navadmin_by_year]);
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
    my @list = map { "$_/$two_digit_year" } (sort keys %{$navadmins_for_year_ref});

    $c->render(template => 'list-by-year', navadmin_list => \@list, subjects => \%navadmin_subj);
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
</ul>

@@ list-by-year.html.ep
% layout 'default';
% title "List for $year";

<h3>Here are some NAVADMINs:</h3>
<ul>
<!-- URL here based on format supported by 'serve-navadmin' route -->
% for my $i (@{$navadmin_list}) {
%   if (my $subj = $subjects->{$i}) {
<li><a href="/NAVADMIN/<%= $i %>">NAVADMIN <%= $i %> - <%= $subj %></a></li>
%   } else {
<li><a href="/NAVADMIN/<%= $i %>">NAVADMIN <%= $i %></a></li>
%   }
% }
</ul>

@@ layouts/default.html.ep
<!DOCTYPE html>
<html>
  <head><title><%= title %></title></head>
  <body><%= content %></body>
</html>
