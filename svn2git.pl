#!/usr/bin/env perl
#
# svn2git - A reimplementation of James Coglan's svn2git Ruby script
# as a Perl module and accompanying executable, adapted from
# http://github.com/schwern/svn2git by Elliot Winkler.
#
# This script delegates all the hard work to SvnToGit.pm
# (included in this bundle) so see that for more.
#

use Modern::Perl;
use Getopt::Long;
use Pod::Usage;
use File::Basename;

use lib dirname(__FILE__);
use SvnToGit;

my %opts;
GetOptions(
  \%opts,
  "trunk:s", "branches:s", "tags:s", "root-is-trunk",
  "authors-file:s",
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

__END__

=head1 NAME

svn2git - Convert a Subversion repository to Git

=head1 SYNOPSIS

B<svn2git [OPTIONS] SVN_URL [NEW_REPO_DIR]>

Run C<--help> for the list of options.

=head1 DESCRIPTION

svn2git converts a Subversion repository into a git repository. It
uses git-svn to do the bulk of the conversion, but does a little extra
work to convert the SVN way of doing things into the git way:

=over 4

=item *

git-svn maps SVN branches to git branches, but keeps them as remotes.
svn2git copies those to local branches so you can use them right away.

=item *

git-svn maps Subversion tags to git branches. svn2git creates real git
tags instead.

=item *

git-svn will map trunk in your Subversion repo to an explicit branch,
and sometimes this is not the same as what ends up being master.
svn2git ensures that trunk maps correctly to master.

=back

Additionally, svn2git can handle the case in which the SVN repo you're
converting did not start out as having a conventional
trunk/branches/tags structure, but was moved over at a specific
revision in the history. Read L<SvnToGit/"Converting a repo with an
inconsistent structure"> for more information.

Once done, your new repository is ready to be used. Once you're in the
repo directory, you can push it to a new remote repository like so:

  git remote add origin REMOTE_URL
  git push origin --all
  git push origin --tags

=head1 OPTIONS

=over 4

=item B<--trunk TRUNK_PATH>

=item B<--branches BRANCHES_PATH>

=item B<--tags TAGS_PATH>

These tell the converter about the layout of your repository -- what
subdirectories contain the trunk, branches, and tags, respectively.

If none of these are specified, a standard Subversion layout is
assumed.

=item B<--root-is-trunk>

This tells the converter that trunk is at 'trunk', and not to worry
about the branches or tags (except for converting trunk to the master
branch).

=item B<--no-clone>

Skips the step of cloning the SVN repository. This is useful
when you just want to convert the tags on a git repository you'd
previously cloned using git-svn. Note that this assumes you're already
in the git repo.

=item B<--revision REV>, B<-r REV>

=item B<--revision REV1:REV2>, B<-r REV1:REV2>

Specifies which revision(s) within the Subversion repo show up in the
new git repo.

=item B<--authors-file AUTHORS_FILE>

The location of the authors file to use when mapping Subversion authors
to git authors. See L<git-svn>'s C<-A> option for more on how this works.

=item B<--strip-tag-prefix>

When converting tags, removes this string from each tag. For example,
C<--strip-tag-prefix="release-"> would turn "release-1.2.3" into
"1.2.3".

=item B<--force>, B<-f>

If the directory where the new git repo will be created already
exists, it will be overwritten.

=item B<--verbose>, B<-v>

Each shell command will be printed to the console before it is
executed.

=item B<--really-verbose>, B<-vv>

Each shell command will be printed to the console before it is
executed, as well as the output which that command generates.

=item B<--quiet>, B<-q>

Prevents anything from being printed to the console.

=back

=head1 EXAMPLES

Convert an SVN project with a standard structure, autocreating the
F<some-project> directory:

  svn2git http://svn.example.com/some-project

Convert an SVN project that doesn't have a trunk/branches/tags
structure:

  svn2git http://svn.example.com/some-project --root-is-trunk

Convert an SVN project into the F<some-dir> directory:

  svn2git http://svn.example.com/some-project some-dir

Perform tag and trunk mapping on an existing git repo you've created
using git-svn:

  cd some-git-svn-project
  svn2git --no-clone

=head1 AUTHOR

Elliot Winkler <elliot.winkler@gmail.com>

Based on code by Michael G Schwern <schwern@pobox.com>

=head1 SEE ALSO

=over 4

=item *

L<SvnToGit>

=item *

L<git-svn>

=item *

Michael Schwern's Perl script: L<http://github.com/schwern/svn2git>

=item *

Current fork of Ruby svn2git: L<http://github.com/nirvdrum/svn2git>

=back

=cut