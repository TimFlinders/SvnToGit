#!/usr/bin/perl

package Test::SvnToGit::Class;

use Modern::Perl;
use Test::Most;
use File::Basename;
use Cwd qw(fast_abs_path);

use parent 'Test::Class';
use lib fast_abs_path(dirname(__FILE__) . qw(/../../../../lib));

END { Test::Class->runtests }

sub startup : Tests(startup => 1) {
  my $test = shift;
  # require our class and make sure that works at the same time
  use_ok 'SvnToGit::Converter';
}

1;