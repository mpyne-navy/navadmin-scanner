#!/usr/bin/env perl

use Mojolicious::Lite;
use Mojolicious::Validator;

use File::Glob;

get '/' => sub {
    my $c = shift;
    $c->render(template => 'index');
};

get '/by-year/:year' => sub {
    my $c = shift;
    my $year = int($c->stash('year'));

    if ($year < 2005 || $year > 2019) {
        $c->reply->not_found;
        return;
    }

    my $two_digit_year = sprintf("%02d", $year % 100);
    my @list = glob("NAVADMIN/NAV$two_digit_year*.txt");
    if (!@list) {
        $c->reply->exception("Couldn't find NAVADMIN!");
        return;
    }

    foreach (@list) {
        s/^NAVADMIN.//;
        s/\.txt$//;
        s/^NAV..//; # we already know the year
    }

    @list = map { "$_/$two_digit_year" } (@list);
    $c->render(template => 'list-by-year', navadmin_list => \@list);
} => 'list-by-year';

# The extra => [] adds built-in placeholder restrictions
get '/NAVADMIN/:id/:twoyr'
=> [id => qr/\d{3}/, twoyr => qr/\d{2}/]
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
% title 'Welcome';
<h1>NAVADMIN Viewer</h1>

<p>See <a href="<%= url_for('list-by-year', {year => 2019}) %>">Listing for 2019</a>.</p>

@@ list-by-year.html.ep
% layout 'default';
% title "List for $year";

<h3>Here are some NAVADMINs:</h3>
<ul>
<!-- URL here based on format supported by 'serve-navadmin' route -->
% for my $i (@{$navadmin_list}) {
<li><a href="/NAVADMIN/<%= $i %>">NAVADMIN <%= $i %></a></li>
% }
</ul>

@@ layouts/default.html.ep
<!DOCTYPE html>
<html>
  <head><title><%= title %></title></head>
  <body><%= content %></body>
</html>
