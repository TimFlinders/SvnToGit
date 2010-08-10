#!/usr/bin/perl

package Test::SvnToGit::StandardLayout;

use lib qw(../../../../lib);
use Modern::Perl;
use Test::Most;
use parent 'Test::Class';
use File::Spec;
use File::Basename;
use Cwd qw(fast_abs_path);
use Data::Dumper::Simple;

my $fixtures_dir = fast_abs_path(dirname(__FILE__) . "/../../../fixtures");
my $fixture_dir = "$fixtures_dir/standard_layout";

sub startup : Tests(startup => 1) {
  my $test = shift;
  # require our class and make sure that works at the same time
  use_ok 'SvnToGit::Converter';
}

sub setup : Test(setup) {
  my $test = shift;
  # go ahead and convert the repo
  $test->{converter} = SvnToGit::Converter->new(
    svn_repo => "file://$fixture_dir/repo",
    git_repo => "$fixture_dir/repo.git",
    force => 1,
    verbosity_level => 0
  )
}

# test converting a repo with a standard layout
# - all commits present
# - master commits should be same as trunk
# - all branches should be there and have same commits as branches
# - all tags should be there and have same commits as tags
# - test revision option
# - test authors file option
# - test no-clone option

sub test_all_commits_present : Tests {
  my $test = shift;
  $test->{converter}->run;
  chdir "$fixture_dir/repo.git";
  my @actual_commits = map { s/^\*?\s+//; $_ } split("\n", qx'git log --all --format=%s');
  my @expected_commits = (
    "Update test.txt from trunk for the fourth time",
    "Make 'v1.0.0' tag",
    "Update test.txt from foo, again",
    "Update test.txt from foo",
    "Make 'foo' branch",
    "Update test.txt from trunk, yet again",
    "Make 'v0.1.0' tag",
    "Update test.txt from trunk, again",
    "Update test.txt from trunk",
    "Initial commit"
  );
  cmp_deeply \@actual_commits, \@expected_commits, "all commits are present";
}

sub test_branches_are_converted : Tests {
  my $test = shift;
  $test->{converter}->run;
  chdir "$fixture_dir/repo.git";
  
  my @expected_branches = ("foo");
  my @actual_remote_branches = map { s/^\*?\s+//; $_ } split("\n", `git branch -r`);
  cmp_deeply \@actual_remote_branches, \@expected_branches, "SVN branches are converted to git remote branches";
  my @actual_local_branches = grep { $_ ne "master" } map { s/^\*?\s+//; $_ } split("\n", `git branch -l`);
  cmp_deeply \@actual_local_branches, \@expected_branches, "Remote branches are copied to local branches";
  
  my @actual_commits = map { s/^\*?\s+//; $_ } split("\n", qx'git log refs/heads/foo --format=%s');
  my @expected_commits = (
    "Update test.txt from foo, again",
    "Update test.txt from foo",
    "Make 'foo' branch",
    "Update test.txt from trunk, yet again",
    "Update test.txt from trunk, again",
    "Update test.txt from trunk",
    "Initial commit"
  );
  cmp_deeply \@actual_commits, \@expected_commits, "all commits are present";
}

sub test_tags_are_converted : Tests {
  my $test = shift;
  $test->{converter}->run;
  chdir "$fixture_dir/repo.git";
  my @actual_tags = map { s/^\*?\s+//; $_ } split("\n", `git tag`);
  my @expected_tags = ("v0.1.0", "v1.0.0");
  cmp_deeply \@actual_tags, \@expected_tags, "SVN tags are converted to git tags";
  my @actual_commits = map { s/^\*?\s+//; $_ } split("\n", qx'git log refs/tags/v0.1.0 --format=%s');
  my @expected_commits = (
    "Make 'v0.1.0' tag",
    "Update test.txt from trunk, again",
    "Update test.txt from trunk",
    "Initial commit"
  );
  cmp_deeply \@actual_commits, \@expected_commits, "all commits are present";
}

sub test_trunk_is_converted : Tests {
  my $test = shift;
  $test->{converter}->run;
  chdir "$fixture_dir/repo.git";
  my @actual_commits = map { s/^\*?\s+//; $_ } split("\n", qx'git log master --format=%s');
  my @expected_commits = (
    "Update test.txt from trunk for the fourth time",
    "Update test.txt from trunk, yet again",
    "Update test.txt from trunk, again",
    "Update test.txt from trunk",
    "Initial commit"
  );
  cmp_deeply \@actual_commits, \@expected_commits, "all commits are present";
  my @local_branches = map { s/^\*?\s+//; $_ } split("\n", `git branch -l`);
  ok((! grep { $_ eq "trunk" } @local_branches), "trunk isn't present in local branches");
  my @remote_branches = map { s/^\*?\s+//; $_ } split("\n", `git branch -r`);
  ok((! grep { $_ eq "trunk" } @remote_branches), "trunk isn't present in remote branches");
}

sub test_revision_option : Tests {
  my $test = shift;
  $test->{converter}->{revision} = "1:7";
  $test->{converter}->run;
  chdir "$fixture_dir/repo.git";
  my $first_commit = (split("\n", qx'git log --all --format=%s'))[0];
  is $first_commit, "Update test.txt from foo", "copies over only the specified revisions";
}

sub test_authors_file_option : Tests {
  my $test = shift;
  $test->{converter}->{authors_file} = "$fixture_dir/authors.txt";
  $test->{converter}->run;
  chdir "$fixture_dir/repo.git";
  my @actual_authors = split("\n", qx'git log --all --format="%an"');
  my @expected_authors = qw(jane jane joe joe joe jane jane john john john);
  cmp_deeply \@actual_authors, \@expected_authors;
}

sub test_no_clone_option : Tests {
  my $test = shift;
  `rm -rf $fixture_dir/repo.git`;
  mkdir "$fixture_dir/repo.git";
  chdir "$fixture_dir/repo.git";
  `git svn init -s file://$fixture_dir/repo &>/dev/null`;
  `git svn fetch &>/dev/null`;
  $test->{converter}->{clone} = 0;
  $test->{converter}->run;
  my @commits = split("\n", `git log --all --oneline`);
  is scalar(@commits), 10;
}

1;