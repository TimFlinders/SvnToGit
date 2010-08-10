#!/usr/bin/perl

package Test::SvnToGit::InconsistentLayoutWithGap;

use Modern::Perl;
use Test::Most;
use parent 'Test::Class';
use Cwd qw(getcwd fast_abs_path);
use File::Basename;
use Cwd qw(fast_abs_path);
use Data::Dumper::Simple;

use lib fast_abs_path(dirname(__FILE__) . "/../../../../lib");

my $fixtures_dir = fast_abs_path(dirname(__FILE__) . "/../../../fixtures");
my $fixture_dir = "$fixtures_dir/inconsistent_layout_with_gap";

sub startup : Tests(startup => 1) {
  my $test = shift;
  # require our class and make sure that works at the same time
  use_ok 'SvnToGit::Converter';
}

sub setup : Test(setup) {
  my $test = shift;
  $test->{converter} = SvnToGit::Converter->get_converter(
    svn_repo => "file://$fixture_dir/repo",
    git_repo => "$fixture_dir/repo.git",
    end_root_only_at => 3,
    start_std_layout_at => 7,
    verbosity_level => $ENV{VERBOSITY} // 0,
    clear_cache => 1,
    grafts_file => "$fixture_dir/grafts.txt"
  );
}

# test converting a repo with an inconsistent layout (with gap)
# - all commits present
# - master commits should be same as before trunk + trunk
# - all branches should be there and have same commits as branches
# - all tags should be there and have same commits as tags
# - test revision option
# - test authors file option
# - test no-clone option

sub test_all_commits_present : Tests {
  my $test = shift;
  $test->{converter}->run;
  chdir "$fixture_dir/repo.git" or die "Couldn't chdir: $!";
  
  my @actual_commits = map { s/^\*?\s+//; $_ } split("\n", qx'git log --all --format=%s');
  my @expected_commits = (
    "Update test.txt finally, from trunk",
    "Update test.txt from foo",
    "Make 'foo' branch",
    "Update test.txt from trunk",
    "Update test.txt, again",
    "Update test.txt",
    "Initial commit"
  );
  cmp_deeply \@actual_commits, \@expected_commits, "all commits in the project are present";
}

sub test_branches_are_converted : Tests {
  my $test = shift;
  $test->{converter}->run;
  chdir "$fixture_dir/repo.git" or die "Couldn't chdir: $!";
  
  my @expected_branches = ("foo");
  my @actual_local_branches = grep { $_ ne "master" } map { s/^\*?\s+//; $_ } split("\n", `git branch -l`);
  cmp_deeply \@actual_local_branches, \@expected_branches, "SVN branches are copied to git branches";
  
  my @actual_remote_branches = map { s/^\*?\s+//; $_ } split("\n", `git branch -r`);
  is scalar(@actual_remote_branches), 0, "Remote branches are removed in favor of local branches";
  
  my @actual_commits = map { s/^\*?\s+//; $_ } split("\n", qx'git log foo --format=%s');
  my @expected_commits = (
    "Update test.txt from foo",
    "Make 'foo' branch",
    "Update test.txt from trunk",
    "Update test.txt, again",
    "Update test.txt",
    "Initial commit"
  );
  cmp_deeply \@actual_commits, \@expected_commits, "all commits in branches are present";
}

# TODO: Need to fix this
#sub test_tags_are_converted : Tests {
#  my $test = shift;
#  $test->{converter}->run;
#  chdir "$fixture_dir/repo.git" or die "Couldn't chdir: $!";
#  
#  my @actual_tags = map { s/^\*?\s+//; $_ } split("\n", `git tag`);
#  my @expected_tags = ("v0.1.0", "v1.0.0");
#  cmp_deeply \@actual_tags, \@expected_tags, "SVN tags are converted to git tags";
#  
#  my @actual_commits = map { s/^\*?\s+//; $_ } split("\n", qx'git log refs/tags/v0.1.0 --format=%s');
#  my @expected_commits = (
#    "Make 'v0.1.0' tag",
#    "Update test.txt from trunk, again",
#    "Update test.txt from trunk",
#    "Initial commit"
#  );
#  cmp_deeply \@actual_commits, \@expected_commits, "all commits are present";
#}

sub test_trunk_is_converted : Tests {
  my $test = shift;
  $test->{converter}->run;
  chdir "$fixture_dir/repo.git" or die "Couldn't chdir: $!";
  
  my @actual_commits = map { s/^\*?\s+//; $_ } split("\n", qx'git log master --format=%s');
  my @expected_commits = (
    "Update test.txt finally, from trunk",
    "Update test.txt from trunk",
    "Update test.txt, again",
    "Update test.txt",
    "Initial commit"
  );
  cmp_deeply \@actual_commits, \@expected_commits, "all commits in master are present";
  
  my @local_branches = map { s/^\*?\s+//; $_ } split("\n", `git branch -l`);
  ok((! grep { $_ eq "trunk" } @local_branches), "trunk isn't present in local branches");
  
  my @remote_branches = map { s/^\*?\s+//; $_ } split("\n", `git branch -r`);
  ok((! grep { $_ eq "trunk" } @remote_branches), "trunk isn't present in remote branches");
}

sub test_authors_file_option : Tests {
  my $test = shift;
  $test->{converter}->{authors_file} = "$fixture_dir/authors.txt";
  $test->{converter}->run;
  chdir "$fixture_dir/repo.git" or die "Couldn't chdir: $!";
  my @actual_authors = split("\n", qx'git log --all --format="%an"');
  my @expected_authors = qw(john joe joe joe john john john);
  cmp_deeply \@actual_authors, \@expected_authors;
}

1;