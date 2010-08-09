#!/usr/bin/perl

package Test::SvnToGit::Initialization;

use lib qw(../.. ../../../../lib);
use Modern::Perl;
use Test::Most;
use base 'Test::Class';
# If multiple tests in a test method and one dies, exit whole method
#BEGIN { $ENV{DIE_ON_FAIL} = 1 }
#use Test::MockObject;
#use Test::MockObject::Extends;

our $CLASS = 'SvnToGit';

#sub mock {
#  Test::MockObject::Extends->new(shift);
#}

=begin
sub startup : Tests(startup => 1) {
  my $test = shift;
  # require our class and make sure that works at the same time
  use_ok $CLASS;
  # set up our mocking lib
  #$test->{mockery} = Test::MockObject->new;
}

sub convert : Tests {
  my $test = shift;
  my $klass = mock("SvnToGit");
  my $c = mock();
  $c->mock('run', sub { 1 });
  $klass->mock('new', sub { $c });
  
  my $c2 = $klass->convert(foo => "bar", baz => "quux");
  
  is($c2, $c, "returns a converter");
  $klass->called_ok('new', {foo => "bar", baz => "quux"})
}
=cut

sub startup : Tests(startup => 1) {
  my $test = shift;
  # require our class and make sure that works at the same time
  use_ok $CLASS;
}

sub test_bails_on_no_svn_repo_option : Tests {
  my $test = shift;
  my $c;
  eval {
    $c = SvnToGit->new;
  };
  is("SvnToGit: You must pass an svn_repo option!\n", $@, "bails if svn_repo option not given");
}

sub test_git_repo_option : Tests {
  my $test = shift;
  eval {
    `mkdir repo`;
    my $c;
    $c = SvnToGit->new(
      svn_repo => "/path/to/some_repo"
    );
    is("some_repo", $c->{git_repo}, "uses the basename of the svn repo as the name of the new git repo");
    $c = SvnToGit->new(
      svn_repo => "/path/to/repo"
    );
    is("repo.git", $c->{git_repo}, "appends .git to destination if already present");
    $c = SvnToGit->new(
      svn_repo => "/path/to/repo",
      force => 1
    );
    is("repo", $c->{git_repo}, "doesn't append .git to destination if already present and force option given");
  };
  die $@ if $@;
  `rmdir repo`;
}

sub test_revisions_option : Tests {
  my $test = shift;
  my $c;
  $c = SvnToGit->new(
    svn_repo => "/path/to/repo",
    revisions => "1:2"
  );
  is("1:2", $c->{revision}, "aliases revisions option to revision");
}

sub test_uses_default_authors_file_if_not_given : Tests {
  my $test = shift;
  my $c;
  $c = SvnToGit->new(
    svn_repo => "/path/to/repo"
  );
  is("$ENV{HOME}/.svn2git/authors", $c->{authors_file}, "uses default authors file if no authors_file option given")
}

sub test_bails_if_authors_file_doesnt_exist : Tests {
  my $test = shift;
  my $c;
  eval {
    $c = SvnToGit->new(
      svn_repo => "/path/to/repo",
      authors_file => "/some/nonexistent/file"
    );
  };
  is("SvnToGit: The authors file you specified doesn't exist!\n", $@, "bails if authors file doesn't exist");
}

sub test_clone_option_is_true_by_default : Tests {
  my $test = shift;
  my $c;
  $c = SvnToGit->new(
    svn_repo => "/path/to/repo"
  );
  is(1, $c->{clone}, "clone option is true by default");
}

1;