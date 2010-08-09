#!/usr/bin/env perl

use lib 't/tests';
use Test::SvnToGit::Initialization;
use Test::SvnToGit::StandardLayout;
use Test::SvnToGit::TrunkOnlyLayout;

Test::Class->runtests;