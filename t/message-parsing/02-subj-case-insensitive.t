use v5.28;
use feature 'signatures';

use MsgReader qw(read_navadmin_from_file);

use Test::More;

my $data = read_navadmin_from_file('NAVADMIN/NAV23025.txt');
is(scalar @{$data->{fields}->{REF}}, 1, 'Read all REF fields of NAVADMIN 025/23');

is($data->{fields}->{REF}->[0]->{id}, 'A', 'REF A is read in');
is($data->{fields}->{REF}->[0]->{ampn}, 'OPNAVINST 3006.1 CH-2', 'AMPN decoded with lowercase "is"');

done_testing();
