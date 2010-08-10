#!/usr/bin/perl

package Test::SvnToGit::Converter::Initialization;

use Modern::Perl;
use Test::Most;
use File::Spec;
use File::Basename;
use File::pushd;
use Cwd qw(fast_abs_path);
use Data::Dumper::Simple;

use parent 'Test::SvnToGit::Class';

my $fixtures_dir = fast_abs_path(dirname(__FILE__) . "/../../../../fixtures");
my $fixture_dir = "$fixtures_dir/repo";

sub test_bails_on_no_svn_repo_option : Tests {
  my $test = shift;
  throws_ok {
    SvnToGit::Converter->buildargs;
  } qr/SvnToGit::Converter: You must pass an svn_repo option!\n/,
  "bails if svn_repo option not given";
}

sub test_uses_basename_of_svn_repo_as_git_repo : Tests {
  my $test = shift;
  my %data = SvnToGit::Converter->buildargs(
    svn_repo => "/path/to/some_repo"
  );
  like $data{git_repo}, qr/some_repo$/, "uses the basename of the svn repo as the name of the new git repo";
}

sub test_appends_git_to_git_repo_if_already_exists : Tests {
  my $dir = pushd($fixtures_dir);
  `mkdir -p repo.git`;
  my %data = SvnToGit::Converter->buildargs(
    svn_repo => "/path/to/repo"
  );
  like $data{git_repo}, qr/repo\.git$/, "appends .git to destination if already present";
}

sub test_doesnt_append_git_to_git_repo_if_force_option_given : Tests {
  my $dir = pushd($fixtures_dir);
  my %data = SvnToGit::Converter->buildargs(
    svn_repo => "/path/to/repo",
    force => 1
  );
  like $data{git_repo}, qr/repo$/, "doesn't append .git to destination if already present and force option given";
}

sub test_uses_default_authors_file_if_not_given : Tests {
  my $test = shift;
  my %data = SvnToGit::Converter->buildargs(
    svn_repo => "/path/to/repo"
  );
  is $data{authors_file}, "$ENV{HOME}/.svn2git/authors", "uses default authors file if no authors_file option given";
}

sub test_bails_if_authors_file_doesnt_exist : Tests {
  my $test = shift;
  throws_ok {
    SvnToGit::Converter->buildargs(
      svn_repo => "/path/to/repo",
      authors_file => "/some/nonexistent/file"
    );
  } qr/SvnToGit::Converter: The authors file you specified doesn't exist!\n/,
  "bails if authors file doesn't exist";
}

1;