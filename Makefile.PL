use strict;
use warnings;

use ExtUtils::MakeMaker;

WriteMakefile(
  VERSION   => '0.02',
  PREREQ_PM => {
    'Mojolicious' => '8.72',
    'EV' => '4.32',
  },
  test => {TESTS => 't/*.t'}
);
