#!/usr/bin/perl

package Test::SvnToGit::Converter::ConsistentLayout::Initialization;

use Modern::Perl;
use Test::Most;
use File::Spec;
use File::Basename;
use Cwd qw(fast_abs_path);
use Data::Dumper::Simple;

use parent 'Test::SvnToGit::Class';

sub startup : Tests(startup => 1) {
  my $test = shift;
  # require our class and make sure that works at the same time
  use_ok 'SvnToGit::Converter::ConsistentLayout';
}

sub test_clone_option_is_true_by_default : Tests {
  my $test = shift;
  my %data = SvnToGit::Converter::ConsistentLayout->buildargs(
    svn_repo => "/path/to/repo"
  );
  is $data{clone}, 1, "clone option is true by default";
}

sub test_removes_trailing_slash_from_trunk_path : Tests {
  my $test = shift;
  my %data = SvnToGit::Converter::ConsistentLayout->buildargs(
    svn_repo => "/path/to/repo",
    trunk => "trunk/",
  );
  is $data{trunk}, "trunk", "removes trailing slash from trunk path";
}

sub test_removes_trailing_slash_from_branches_path : Tests {
  my $test = shift;
  my %data = SvnToGit::Converter::ConsistentLayout->buildargs(
    svn_repo => "/path/to/repo",
    branches => "branches/",
  );
  is $data{branches}, "branches", "removes trailing slash from branches path";
}

sub test_removes_trailing_slash_from_tags_path : Tests {
  my $test = shift;
  my %data = SvnToGit::Converter::ConsistentLayout->buildargs(
    svn_repo => "/path/to/repo",
    tags => "tags/",
  );
  is $data{tags}, "tags", "removes trailing slash from tags path";
}

sub test_removes_trailing_slash_from_strip_tag_prefix : Tests {
  my $test = shift;
  my %data = SvnToGit::Converter::ConsistentLayout->buildargs(
    svn_repo => "/path/to/repo",
    strip_tag_prefix => "foobar/",
  );
  is $data{strip_tag_prefix}, "foobar", "removes trailing slash from tags path";
}

1;