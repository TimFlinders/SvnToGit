#!/usr/bin/perl

package Test::SvnToGit::Converter::InconsistentLayout::Initialization;

use Modern::Perl;
use Test::Most;
use File::Spec;
use File::Basename;
use File::pushd;
use Cwd qw(fast_abs_path);
use Data::Dumper::Simple;

use parent 'Test::SvnToGit::Class';

sub startup : Tests(startup => 1) {
  my $test = shift;
  # require our class and make sure that works at the same time
  use_ok 'SvnToGit::Converter::InconsistentLayout';
}

sub test_end_root_only_at_default_value : Tests {
  my $test = shift;
  my %data = SvnToGit::Converter::InconsistentLayout->buildargs(
    svn_repo => "/path/to/repo",
    start_std_layout_at => 10
  );
  is $data{end_root_only_at}, 9, "sets end_root_only_at to 1 less than start_std_layout_at by default";
}

sub test_final_git_url_default_value : Tests {
  my $test = shift;
  my %data = SvnToGit::Converter::InconsistentLayout->buildargs(
    svn_repo => "/path/to/repo",
    start_std_layout_at => 1
  );
  is $data{final_git_url}, 'ssh://you@yourserver.com/path/to/git/repo', "sets final_git_url to a default value";
}

sub test_absolutizes_grafts_file_path_if_relative : Tests {
  my $test = shift;
  my $dir = pushd dirname(__FILE__);
  my %data = SvnToGit::Converter::InconsistentLayout->buildargs(
    svn_repo => "/path/to/repo",
    start_std_layout_at => 1,
    grafts_file => "WithGap.pm"
  );
  is $data{grafts_file}, "$dir/WithGap.pm", "makes grafts_file an absolute path if given";
}

sub test_doesnt_absolutize_grafts_file_if_already_absolute : Tests {
  my $test = shift;
  my $dir = pushd dirname(__FILE__);
  my %data = SvnToGit::Converter::InconsistentLayout->buildargs(
    svn_repo => "/path/to/repo",
    start_std_layout_at => 1,
    grafts_file => "$dir/WithGap.pm"
  );
  is $data{grafts_file}, "$dir/WithGap.pm", "doesn't worry about making grafts_file an absolute path if it already is one";
}

sub test_stops_at_grafting_if_grafts_file_not_supplied : Tests {
  my $test = shift;
  my $dir = pushd dirname(__FILE__);
  my %data = SvnToGit::Converter::InconsistentLayout->buildargs(
    svn_repo => "/path/to/repo",
    start_std_layout_at => 1
  );
  is $data{stop_at_grafting}, 1, "sets stop_at_grafting to 1 if grafts_file was not supplied";
}

=begin
sub test_doesnt_stop_at_grafting_if_grafts_file_not_given_but_grafts_file_exists : Tests {
  my $test = shift;
  my $tmpdir = File::Spec->tmpdir;
  $SvnToGit::Converter::InconsistentLayout::cached_pre_repo_path = $tmpdir;
  `mkdir -p $tmpdir/.git/info`;
  `touch $tmpdir/.git/info/grafts`;
  my %data = SvnToGit::Converter::InconsistentLayout->buildargs(
    svn_repo => "/path/to/repo",
    start_std_layout_at => 1
  );
  isnt $data{stop_at_grafting}, 1, "doesn't stop at grafting if grafts_file wasn't given, but .git/info/grafts file exists in pre-repo";
}
=cut

1;