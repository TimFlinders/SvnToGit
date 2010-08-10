#!/usr/bin/env perl

use lib 't/tests';
#use Test::SvnToGit::Initialization;
#use Test::SvnToGit::StandardLayout;
#use Test::SvnToGit::TrunkOnlyLayout;
use Test::SvnToGit::InconsistentLayoutWithoutGap;

Test::Class->runtests;