#!/usr/bin/perl

package Test::SvnToGit::Initialization;

use lib qw(../../../../lib);
use Modern::Perl;
use Test::Most;
use parent 'Test::Class';

sub startup : Tests(startup => 1) {
  my $test = shift;
  # require our class and make sure that works at the same time
  use_ok 'SvnToGit::Converter';
}

sub test_bails_on_no_svn_repo_option : Tests {
  my $test = shift;
  my $c;
  throws_ok {
    $c = SvnToGit::Converter->buildargs;
  } qr/SvnToGit::Converter: You must pass an svn_repo option!\n/,
  "bails if svn_repo option not given";
}

sub test_git_repo_option : Tests {
  my $test = shift;
  eval {
    `mkdir repo`;
    my $c;
    $c = SvnToGit::Converter->buildargs(
      svn_repo => "/path/to/some_repo"
    );
    is("some_repo", $c->{git_repo}, "uses the basename of the svn repo as the name of the new git repo");
    $c = SvnToGit::Converter->buildargs(
      svn_repo => "/path/to/repo"
    );
    is("repo.git", $c->{git_repo}, "appends .git to destination if already present");
    $c = SvnToGit::Converter->buildargs(
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
  $c = SvnToGit::Converter->buildargs(
    svn_repo => "/path/to/repo",
    revisions => "1:2"
  );
  is("1:2", $c->{revision}, "aliases revisions option to revision");
}

sub test_uses_default_authors_file_if_not_given : Tests {
  my $test = shift;
  my $c;
  $c = SvnToGit::Converter->buildargs(
    svn_repo => "/path/to/repo"
  );
  is("$ENV{HOME}/.svn2git/authors", $c->{authors_file}, "uses default authors file if no authors_file option given")
}

sub test_bails_if_authors_file_doesnt_exist : Tests {
  my $test = shift;
  my $c;
  throws_ok {
    $c = SvnToGit::Converter->buildargs(
      svn_repo => "/path/to/repo",
      authors_file => "/some/nonexistent/file"
    );
  } qr/SvnToGit::Converter: The authors file you specified doesn't exist!\n/,
  "bails if authors file doesn't exist";
}

sub test_clone_option_is_true_by_default : Tests {
  my $test = shift;
  my $c;
  $c = SvnToGit::Converter->buildargs(
    svn_repo => "/path/to/repo"
  );
  is(1, $c->{clone}, "clone option is true by default");
}

1;