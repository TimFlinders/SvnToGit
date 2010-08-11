#!/usr/bin/perl

package Test::SvnToGit::Converter::ConsistentLayout::RootOnlyLayout;

use Modern::Perl;
use Test::Most;
use File::Spec;
use File::Basename;
use Cwd qw(fast_abs_path);
use Data::Dumper::Simple;

use parent 'Test::SvnToGit::Class';

my $fixtures_dir = fast_abs_path(dirname(__FILE__) . "/../../../../../fixtures");
my $fixture_dir = "$fixtures_dir/root_only_layout";

sub setup : Test(setup) {
  my $test = shift;
  $test->{converter} = SvnToGit::Converter->get_converter(
    svn_repo => "file://$fixture_dir/repo",
    git_repo => "$fixture_dir/repo.git",
    force => 1,
    verbosity_level => 0,
    root_only => 1
  )
}

# test converting a repo where root is trunk
# - commits (on master) should be exactly same
# - no branches
# - no tags
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
    "Update test.txt from trunk, yet again",
    "Update test.txt from trunk, again",
    "Update test.txt from trunk",
    "Initial commit"
  );
  cmp_deeply \@actual_commits, \@expected_commits, "all commits are present";
}

sub test_no_branches_exist : Tests {
  my $test = shift;
  $test->{converter}->run;
  chdir "$fixture_dir/repo.git";
  my @remote_branches = map { s/^\*?\s+//; $_ } split("\n", `git branch -r`);
  is scalar(@remote_branches), 0, "no remote branches exist";
  my @local_branches = grep { $_ ne "master" } map { s/^\*?\s+//; $_ } split("\n", `git branch -l`);
  is scalar(@local_branches), 0, "no local branches exist";
}

sub test_no_tags_exist : Tests {
  my $test = shift;
  $test->{converter}->run;
  chdir "$fixture_dir/repo.git";
  my @tags = map { s/^\*?\s+//; $_ } split("\n", `git tag`);
  is scalar(@tags), 0, "no tags exist";
}

sub test_revision_option : Tests {
  my $test = shift;
  $test->{converter}->{revisions} = "1:3";
  $test->{converter}->run;
  chdir "$fixture_dir/repo.git";
  my $first_commit = (split("\n", qx'git log --all --format=%s'))[0];
  is $first_commit, "Update test.txt from trunk, again", "copies over only the specified revisions";
}

sub test_authors_file_option : Tests {
  my $test = shift;
  $test->{converter}->{authors_file} = "$fixture_dir/authors.txt";
  $test->{converter}->run;
  chdir "$fixture_dir/repo.git";
  my @actual_authors = split("\n", qx'git log --all --format="%an"');
  my @expected_authors = qw(jane jane joe john john);
  cmp_deeply \@actual_authors, \@expected_authors;
}

sub test_no_clone_option : Tests {
  my $test = shift;
  `rm -rf $fixture_dir/repo.git`;
  mkdir "$fixture_dir/repo.git";
  chdir "$fixture_dir/repo.git";
  `git svn init --trunk=file://$fixture_dir/repo file://$fixture_dir/repo &>/dev/null`;
  `git svn fetch &>/dev/null`;
  $test->{converter}->{clone} = 0;
  $test->{converter}->run;
  my @commits = split("\n", `git log --all --oneline`);
  is scalar(@commits), 5;
}

1;