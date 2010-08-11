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

sub test_converts_svn_repo_to_url_if_absolute_file_path : Tests {
  my $test = shift;
  my %data = SvnToGit::Converter->buildargs(
    svn_repo => "/path/to/repo"
  );
  is $data{svn_repo}, "file:///path/to/repo", "converts the given svn_repo to a file:// url if it's an absolute file path";
}

sub test_converts_svn_repo_to_absolute_path_before_prepending_file : Tests {
  my $test = shift;
  my $dir = pushd("/");
  my %data = SvnToGit::Converter->buildargs(
    svn_repo => "repo"
  );
  is $data{svn_repo}, "file:///repo", "converts the given svn_repo to an absolute file path before prepending file://";
}

sub test_leaves_svn_repo_as_is_if_a_url : Tests {
  my $test = shift;
  my %data = SvnToGit::Converter->buildargs(
    svn_repo => "http://url/to/repo"
  );
  is $data{svn_repo}, "http://url/to/repo", "leaves svn_repo as-is if it's a URL";
}

sub test_uses_basename_of_svn_repo_as_git_repo_by_default : Tests {
  my $test = shift;
  my %data = SvnToGit::Converter->buildargs(
    svn_repo => "/path/to/some_repo"
  );
  like $data{git_repo}, qr/some_repo$/, "uses the basename of the svn repo as the name of the new git repo";
}

sub test_appends_git_to_git_repo_if_already_exists : Tests {
  my $test = shift;
  my $dir = pushd(File::Spec->tmpdir);
  system("mkdir -p repo");
  my %data = SvnToGit::Converter->buildargs(
    svn_repo => "repo"
  );
  like $data{git_repo}, qr/repo\.git$/, "appends .git to destination if already present";
}

sub test_doesnt_append_git_to_git_repo_if_force_option_given : Tests {
  my $test = shift;
  my $dir = pushd(File::Spec->tmpdir);
  system("mkdir -p repo.git");
  my %data = SvnToGit::Converter->buildargs(
    svn_repo => "repo",
    force => 1
  );
  like $data{git_repo}, qr/repo$/, "doesn't append .git to destination if already present and force option given";
}

sub test_converts_git_repo_to_absolute_path_if_not_one : Tests {
  my $test = shift;
  my $dir = pushd("/tmp");
  my %data = SvnToGit::Converter->buildargs(
    svn_repo => "/path/to/repo",
    git_repo => "foo"
  );
  # Get around effing Mac OS...
  (my $git_repo = $data{git_repo}) =~ s{^/private}{};
  is $git_repo, "/tmp/foo", "converts git_repo to an absolute path if it's not one";
}

sub test_doesnt_convert_git_repo_to_absolute_path_if_already_one : Tests {
  my $test = shift;
  my %data = SvnToGit::Converter->buildargs(
    svn_repo => "/path/to/repo",
    git_repo => "/tmp/foo"
  );
  is $data{git_repo}, "/tmp/foo", "doesn't convert git_repo to an absolute_path if it's already one";
}

sub test_uses_default_authors_file_if_not_given : Tests {
  my $test = shift;
  my $tmpdir = File::Spec->tmpdir . "/.svn2git";
  system("mkdir", "-p", $tmpdir);
  system("touch", "$tmpdir/authors");
  $ENV{HOME} = File::Spec->tmpdir;
  my %data = SvnToGit::Converter->buildargs(
    svn_repo => "/path/to/repo"
  );
  is $data{authors_file}, "$tmpdir/authors", "uses default authors file if no authors_file option given";
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

sub test_converts_authors_file_to_absolute_path_if_not_one : Tests {
  my $test = shift;
  my $tmpdir = File::Spec->tmpdir;
  system("touch", "$tmpdir/authors.txt");
  my $dir = pushd($tmpdir);
  my %data = SvnToGit::Converter->buildargs(
    svn_repo => "/path/to/repo",
    authors_file => "authors.txt"
  );
  # Get around effing Mac OS...
  (my $authors_file = $data{authors_file}) =~ s{^/private}{};
  is $authors_file, "$tmpdir/authors.txt", "converts authors_file to an absolute path if it's not one";
}

sub test_doesnt_convert_authors_file_to_absolute_path_if_already_one : Tests {
  my $test = shift;
  my $tmpdir = File::Spec->tmpdir;
  system("touch", "$tmpdir/authors.txt");
  my $dir = pushd($tmpdir);
  my %data = SvnToGit::Converter->buildargs(
    svn_repo => "/path/to/repo",
    authors_file => "$tmpdir/authors.txt"
  );
  is $data{authors_file}, "$tmpdir/authors.txt", "doesn't convert authors_file to an absolute path if it's already one"
}

1;