use v5.28;
use feature 'signatures';

use MsgReader qw(read_navadmin_from_file);

use Test::More;

my $data = read_navadmin_from_file('NAVADMIN/NAV23012.txt');
is(scalar @{$data->{fields}->{REF}}, 6, 'Read all REF fields of NAVADMIN 012/23');

is($data->{fields}->{REF}->[0]->{id}, 'A', 'REF A is read in');
ok(exists $data->{fields}->{REF}->[0]->{ampn}, 'REF A has AMPN set');

is($data->{fields}->{REF}->[1]->{id}, 'B', 'REF B is read in');
ok(exists $data->{fields}->{REF}->[1]->{ampn}, 'REF B has AMPN set');

is($data->{fields}->{REF}->[2]->{id}, 'C', 'REF C is read in');
ok(exists $data->{fields}->{REF}->[2]->{ampn}, 'REF C has AMPN set');

is($data->{fields}->{REF}->[3]->{id}, 'D', 'REF D is read in');
ok(exists $data->{fields}->{REF}->[3]->{ampn}, 'REF D has AMPN set');

is($data->{fields}->{REF}->[4]->{id}, 'E', 'REF E is read in');
ok(exists $data->{fields}->{REF}->[4]->{ampn}, 'REF E has AMPN set');

is($data->{fields}->{REF}->[5]->{id}, 'F', 'REF F is read in');
ok(exists $data->{fields}->{REF}->[5]->{ampn}, 'REF F has AMPN set');

$data = read_navadmin_from_file('NAVADMIN/NAV23002.txt');
is($data->{fields}->{SUBJ},
    "ANNOUNCING NEW YEARS DAY DECK LOG POEM CONTEST FOR 2023//",
    'Read malformed SUBJ with SUBJ// instead of SUBJ/');

$data = read_navadmin_from_file('NAVADMIN/NAV18023.txt');
is($data->{fields}->{REF}->[0]->{ampn},
    "NAVADMIN 248/17",
    'Read amplification present in AMPN rather than NARR field');

done_testing();
