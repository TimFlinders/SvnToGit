#!/usr/bin/env perl
#
# A reimplementation of James Coglan's svn2git Ruby script as a Perl
# module and accompanying executable, adapted from
# http://github.com/schwern/svn2git by Elliot Winkler.
#
# This script delegates all the hard work to SvnToGit.pm (included
# in this bundle) so see that for more.
#

use strict;
use warnings;

use Getopt::Long;
use Pod::Usage;
use File::Basename;

use lib dirname(__FILE__);
use SvnToGit;

my %opts;
GetOptions(
  \%opts,
  "trunk:s", "branches:s", "tags:s", "root-is-trunk",
  "authors:s",
  "clone!",
  "strip-tag-prefix:s",
  "revision|r:s",
  "force|f",
  "verbose|v",
  "quiet|q",
  "help|h"
) or pod2usage(2);
pod2usage(1) if $opts{help};

# convert --foo-bar to $ARGV{foo_bar}
for my $k (keys %opts) {
  my $v = $opts{$k};
  $k =~ s/-/_/g;
  $ARGV{$k} = $v;
}

pod2usage(2) if @ARGV == 0;
my($svn_repo, $git_repo) = @ARGV;
$ARGV{svn_repo} = $svn_repo;
$ARGV{git_repo} = $git_repo;

my $c = SvnToGit->new(%ARGV);
$c->run;

my $repo_name = $c->{git_repo};
$repo_name =~ s/\.git$//;
print <<EOT;

----
Conversion complete! Now ssh into your server and run something like this:

su git
cd /path/to/git/repos
mkdir $repo_name.git
cd $repo_name.git
git init --bare
# Thanks <https://kerneltrap.org/mailarchive/git/2008/10/9/3569854/thread>
git config core.sharedrepository 1
chmod -R o-rwx .
chmod -R g=u .
find . -type d | xargs chmod g+s

To upload it to your server, simply run:

cd $c->{git_repo}
git remote add origin FINAL_REPO_URL
# git config user.email YOUR_EMAIL if necessary
# modify .gitignore & commit if necessary
git push origin --all

EOT

=head1 NAME

svn2git - Convert a Subversion repository to Git

=head1 SYNOPSIS

  svn2git [OPTIONS] SVN_URL [NEW_REPO_DIR]
  
  OPTIONS:
    --trunk TRUNK_PATH
    --branches BRANCHES_PATH
    --tags TAGS_PATH
    --root-is-trunk
    --no-clone
    --revision REV_OR_REVS
    --authors AUTHORS_FILE
    --strip-tag-prefix
    --force, -f
    --verbose, -v
    --quiet, -q

=head1 DESCRIPTION

svn2git converts a Subversion project into a git repository.  It uses
git-svn to do the bulk of the conversion, but does a little extra work
to convert the Subversion way of doing things into the git way:

* Subversion tag branches become git tags.
* Local branches are made for each remote Subversion branch.
* master is assured to be trunk.

Once done, your new repository is ready to be used.  You can push it
to a new remote origin like so...

  git remote add origin <git_remote_url>
  git push origin --all
  git push origin --tags

=head2 Switches

=head3 --trunk TRUNK_PATH

=head3 --branches BRANCHES_PATH

=head3 --tags TAGS_PATH

These tell svn2git about the layout of your repository; what subdirs
contain the trunk, branches and tags respectively.  If none are given
a standard Subversion layout is assumed.

=head3 --root-is-trunk

This tells svn2git that trunk is at 'trunk', and not to worry about
the branches or tags (except for converting trunk to the master branch).

=head3 --no-clone

Skip the step of cloning the SVN repository.  This is useful when you
just want to convert the tags on a git repository you'd previously
cloned using git-svn. This assumes you're already in the git repo.

=head3 --revision REV

=head3 --revision REV1:REV2

=head3 -r REV

=head3 -r REV1:REV2

Specifies which revision(s) to fetch, when running C<git svn fetch>.

=head3 --authors AUTHORS_FILE

The location of the authors file to use for the git-svn clone.  See
L<git-svn>'s -A option for details.

=head3 --strip-tag-prefix

A prefix to strip off all tags.  For example,
C<<--strip-tag-prefix=release->> would turn "release-1.2.3" into
"1.2.3".

=head3 --force

=head3 -f

If the directory where the new git repo will be created already exists,
it will be overwritten.

=head3 --verbose

=head3 -v

If either -v or --verbose is given, svn2git will output each command
before it runs it.

=head1 EXAMPLES

Convert an SVN project with a standard structure, autocreating the
'some-project' directory:

  svn2git http://svn.example.com/some-project
  
Convert an SVN project that doesn't have a trunk/branches/tags setup:

  svn2git http://svn.example.com/some-project --root-is-trunk

Convert an SVN project with a custom path:

  svn2git http://svn.example.com/some-project some-dir

Convert the tags on an existing git-svn project:

  cd some-git-svn-project
  svn2git --no-clone

=head1 AUTHOR

Michael G Schwern <schwern@pobox.com>

Modifications by Elliot Winkler <elliot.winkler@gmail.com>

=head1 SEE ALSO

L<git>, L<git-svn>

The original Perl script:
L<http://github.com/schwern/svn2git>

The original Ruby svn2git:
L<http://github.com/jcoglan/svn2git/>

=cut