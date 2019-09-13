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

    my $two_digit_year = $year % 100;
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
