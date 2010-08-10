#!/usr/bin/env perl

use lib 't/tests';
#use Test::SvnToGit::Initialization;
use Test::SvnToGit::StandardLayout;
use Test::SvnToGit::RootOnlyLayout;
use Test::SvnToGit::InconsistentLayoutWithoutGap;
use Test::SvnToGit::InconsistentLayoutWithGap;

Test::Class->runtests;